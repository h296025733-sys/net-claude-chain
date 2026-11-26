function Get-SupportedBrowsers {
    foreach ($pair in @(@('Chrome','chrome.exe','Google\Chrome\Application'), @('Edge','msedge.exe','Microsoft\Edge\Application'))) {
        $name,$file,$subdir=$pair
        $candidates=@(
            foreach ($key in @('HKCU:\','HKLM:\')) {
                $entry=Get-Item -LiteralPath ($key+"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$file") -ErrorAction SilentlyContinue
                if ($entry) { $entry.GetValue('') }
            }
            foreach ($base in @($env:ProgramFiles, [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'), $env:LOCALAPPDATA)) {
                if ($base) { Join-Path (Join-Path $base $subdir) $file }
            }
        )
        $found=$candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
        if ($found) { [pscustomobject]@{Name=$name;Path=$found} }
    }
}

function Get-ClaudeExecutable([string]$UserSid='') {
    $query=@{Name='Claude'}
    if ($UserSid) { $query.User=$UserSid }
    $package=Get-AppxPackage @query | Where-Object PackageFamilyName -eq 'Claude_pzs8sxrjxfjjc' |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($package) {
        $exe=Join-Path $package.InstallLocation 'app\claude.exe'
        if (Test-Path -LiteralPath $exe -PathType Leaf) { return $exe }
    }
}

function Get-PhysicalIndexes {
    @(Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | ForEach-Object ifIndex)
}

function Assert-PhysicalRoute([string]$VpsIp) {
    $route=Find-NetRoute -RemoteIPAddress $VpsIp -ErrorAction Stop |
        Where-Object DestinationPrefix | Select-Object -First 1
    if (-not $route -or $route.InterfaceIndex -notin @(Get-PhysicalIndexes)) {
        throw 'The route to the VPS is not through an active physical adapter.'
    }
}

function Update-PhysicalRoute([string]$VpsIp,[string]$StatePath) {
    $physical=@(Get-PhysicalIndexes)
    $gateway=Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' |
        Where-Object { $_.InterfaceIndex -in $physical -and $_.NextHop -ne '0.0.0.0' } |
        Sort-Object @{Expression={ $_.RouteMetric + $_.InterfaceMetric }} | Select-Object -First 1
    if (-not $gateway) { throw 'No active physical IPv4 gateway.' }
    $prefix="$VpsIp/32"
    $current=@(Get-NetRoute -DestinationPrefix $prefix -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
    $owned=if (Test-Path -LiteralPath $StatePath) { Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json }
    if ($current | Where-Object { $_.InterfaceIndex -eq $gateway.InterfaceIndex -and $_.NextHop -eq $gateway.NextHop }) {
        Assert-PhysicalRoute $VpsIp
        return
    }
    $foreign=@($current | Where-Object {
        -not $owned -or $_.DestinationPrefix -ne $owned.Prefix -or
        $_.InterfaceIndex -ne $owned.InterfaceIndex -or $_.NextHop -ne $owned.NextHop -or $_.RouteMetric -ne 4
    })
    if ($foreign) { throw 'An existing conflicting VPS route needs review.' }
    if ($current) { $current | Remove-NetRoute -Confirm:$false }
    New-NetRoute -DestinationPrefix $prefix -InterfaceIndex $gateway.InterfaceIndex -NextHop $gateway.NextHop -RouteMetric 4 -PolicyStore ActiveStore | Out-Null
    @{Prefix=$prefix;InterfaceIndex=$gateway.InterfaceIndex;NextHop=$gateway.NextHop} |
        ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8
    Assert-PhysicalRoute $VpsIp
}

function Get-DesktopFirewallPrograms([string]$ProductRoot) {
    Get-ChildItem -LiteralPath $ProductRoot -Recurse -File -Filter '*.exe' -ErrorAction Stop |
        ForEach-Object FullName
}

function Get-ProgramRuleNames([string]$Program) {
    $hash=[Security.Cryptography.SHA256]::Create()
    try { $bytes=$hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Program.ToLowerInvariant())) }
    finally { $hash.Dispose() }
    $id=([BitConverter]::ToString($bytes,0,10)).Replace('-','')
    "NetClaudeChain-$id-Network"
    "NetClaudeChain-$id-UDP"
}

function Assert-FirewallEnabled {
    if (@(Get-NetFirewallProfile -PolicyStore ActiveStore | Where-Object Enabled -ne 'True').Count) {
        throw 'The Windows firewall must be enabled on all profiles for the dedicated desktop client.'
    }
}

function Set-DesktopFirewall([string]$ProductRoot) {
    Assert-FirewallEnabled
    $outsideLoopback=@('0.0.0.0-127.0.0.0','127.0.0.2-255.255.255.255','::2-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
    foreach ($program in Get-DesktopFirewallPrograms $ProductRoot) {
        $network,$udp=Get-ProgramRuleNames $program
        if (-not (Get-NetFirewallRule -Name $network -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name $network -DisplayName 'Claude dedicated client: block non-loopback' -Group NetClaudeChain -Program $program -Direction Outbound -Action Block -Profile Any -RemoteAddress $outsideLoopback | Out-Null
        }
        if (-not (Get-NetFirewallRule -Name $udp -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -Name $udp -DisplayName 'Claude dedicated client: block UDP' -Group NetClaudeChain -Program $program -Direction Outbound -Action Block -Profile Any -Protocol UDP | Out-Null
        }
    }
}

function Assert-DesktopFirewall([string]$ProductRoot) {
    Assert-FirewallEnabled
    $names=@(Get-DesktopFirewallPrograms $ProductRoot | ForEach-Object { Get-ProgramRuleNames $_ })
    if (-not $names) { throw 'No Claude executables found for the firewall check.' }
    $active=@(Get-NetFirewallRule -PolicyStore ActiveStore -Group NetClaudeChain -ErrorAction SilentlyContinue |
        Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Outbound' -and $_.Action -eq 'Block' })
    if ($names | Where-Object { $_ -notin $active.Name }) { throw 'The dedicated Claude firewall rules are not active.' }
}

function Remove-LegacyClaudeDesktopTask {
    $name='NetClaudeChain-Desktop'
    $launcher=Join-Path $env:ProgramData 'NetClaudeChain\claude-client.ps1'
    $task=Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
    if (-not $task) { return }
    $owned=$task.Actions | Where-Object {
        $_.Execute -match 'powershell(?:\.exe)?$' -and
        $_.Arguments -match [regex]::Escape($launcher) -and
        $_.Arguments -match '-Mode\s+Watch\b'
    }
    if (-not $owned) { return }
    Disable-ScheduledTask -TaskName $name -TaskPath '\' | Out-Null
    Stop-ScheduledTask -TaskName $name -TaskPath '\'
    Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false
}
