[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VpsIp,
    [Parameter(Mandatory)][string]$ExpectedExit,
    [ValidateRange(1,65535)][int]$ProxyPort=10810,
    [string]$XrayExecutable,
    [string]$ClientConfig,
    [string]$ClaudePackage
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'windows-client-common.ps1')
foreach ($address in @($VpsIp,$ExpectedExit)) {
    $parsed=$null
    if (-not [Net.IPAddress]::TryParse($address,[ref]$parsed) -or $parsed.AddressFamily -ne 'InterNetwork') {
        throw 'The current Windows deployment requires literal IPv4 addresses.'
    }
}
if ([bool]$XrayExecutable -ne [bool]$ClientConfig) { throw 'Provide both XrayExecutable and ClientConfig, or reuse the existing local proxy.' }
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run setup as an administrator in the interactive user account.' }
$root=Join-Path $env:ProgramData 'NetClaudeChain'
$profile=Join-Path $env:LOCALAPPDATA 'NetClaudeChain\Profiles'
Remove-LegacyClaudeDesktopTask
$psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -ItemType Directory -Path $root,$profile -Force | Out-Null
if ((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unexpected redirected runtime directory.' }
& icacls.exe $root /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect Windows runtime.' }
foreach ($file in @('windows-client-common.ps1','run-windows-proxy.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $root $file) -Force
}
@{VpsIp=$VpsIp;ExpectedExit=$ExpectedExit;ProxyPort=$ProxyPort;ProfileRoot=$profile;UserSid=$identity.User.Value} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'settings.json') -Encoding UTF8
Update-PhysicalRoute $VpsIp (Join-Path $root 'route.json')
$restart=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

function Register-LocalTask($Name,$Script,$ScriptArgs,$Trigger,$TaskPrincipal) {
    $action=New-ScheduledTaskAction -Execute $psExe -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" {1}' -f (Join-Path $root $Script),$ScriptArgs) -WorkingDirectory $root
    Register-ScheduledTask -TaskName $Name -Action $action -Trigger $Trigger -Principal $TaskPrincipal -Settings $restart -Force | Out-Null
}

$system=New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
if ($XrayExecutable) {
    $config=Get-Content -LiteralPath $ClientConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($config.outbounds).Count -ne 1 -or $config.outbounds[0].protocol -ne 'vless' -or
        $config.outbounds[0].settings.vnext[0].address -ne $VpsIp -or
        $config.outbounds[0].streamSettings.security -ne 'reality' -or
        @($config.inbounds | Where-Object { $_.listen -ne '127.0.0.1' }).Count -gt 0 -or
        -not ($config.inbounds | Where-Object { $_.port -eq $ProxyPort -and $_.protocol -eq 'http' })) {
        throw 'Unexpected Xray client configuration.'
    }
    $daemon=Join-Path $root 'daemon'
    New-Item -ItemType Directory -Path $daemon -Force | Out-Null
    & icacls.exe $daemon /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not protect the proxy config.' }
    $installedXray=Join-Path $daemon 'xray.exe'
    if (-not (Test-Path -LiteralPath $installedXray -PathType Leaf) -or
        (Get-FileHash -LiteralPath $installedXray).Hash -ne (Get-FileHash -LiteralPath $XrayExecutable).Hash) {
        Copy-Item -LiteralPath $XrayExecutable -Destination $installedXray -Force
    }
    foreach ($name in @('geoip.dat','geosite.dat')) {
        $source=Join-Path (Split-Path -Parent $XrayExecutable) $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $daemon -Force }
    }
    Copy-Item -LiteralPath $ClientConfig -Destination (Join-Path $daemon 'client.json') -Force
    & (Join-Path $daemon 'xray.exe') run -test -c (Join-Path $daemon 'client.json')
    if ($LASTEXITCODE -ne 0) { throw 'Xray configuration validation failed.' }
    if (Get-ScheduledTask -TaskName 'NetClaudeChain-Route' -ErrorAction SilentlyContinue) { $null=Disable-ScheduledTask -TaskName 'NetClaudeChain-Route'; Stop-ScheduledTask -TaskName 'NetClaudeChain-Route' }
    Register-LocalTask 'NetClaudeChain-Proxy' 'run-windows-proxy.ps1' '' (New-ScheduledTaskTrigger -AtStartup) $system
    Start-ScheduledTask -TaskName 'NetClaudeChain-Proxy'
} else {
    Register-LocalTask 'NetClaudeChain-Route' 'run-windows-proxy.ps1' '-RouteOnly' (New-ScheduledTaskTrigger -AtStartup) $system
    Start-ScheduledTask -TaskName 'NetClaudeChain-Route'
}

$proxy="http://127.0.0.1:$ProxyPort"
$ready=$false
for ($attempt=0; $attempt -lt 10; $attempt++) {
    $observed=& curl.exe -q --fail --silent --proxy $proxy --noproxy unused.invalid --connect-timeout 2 --max-time 5 https://api.ipify.org
    if ($LASTEXITCODE -eq 0 -and ([string]$observed).Trim() -eq $ExpectedExit) { $ready=$true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { throw 'The local proxy did not report the expected exit IP.' }
function Get-OfficialPackage([string]$Url,[string]$Destination) {
    for ($attempt=0; $attempt -lt 3; $attempt++) {
        & curl.exe -q --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --proxy $proxy --noproxy unused.invalid --continue-at - --connect-timeout 15 --max-time 600 --output $Destination $Url 2>$null
        $result=$LASTEXITCODE
        if ($result -eq 0) { return }
        if ($result -eq 33 -or $result -eq 36) {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        }
    }
    throw "Official installer download failed (curl $result): $Url"
}

$stage=New-Item -ItemType Directory -Path (Join-Path $env:TEMP ("NetClaudeChain-"+[guid]::NewGuid().ToString('N')))
try {
    if (-not @(Get-SupportedBrowsers).Count) {
        $chrome=Join-Path $stage 'ChromeSetup.exe'
        Get-OfficialPackage 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' $chrome
        $sig=Get-AuthenticodeSignature -LiteralPath $chrome
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Google LLC(?:,|$)') {
            throw 'Chrome installer signature verification failed.'
        }
        $process=Start-Process -FilePath $chrome -ArgumentList '/silent /install' -WindowStyle Hidden -Wait -PassThru
        if ($process.ExitCode -ne 0 -or -not @(Get-SupportedBrowsers).Count) {
            throw 'The Chrome installer did not produce a supported browser.'
        }
    }
    if (-not (Get-ClaudeExecutable)) {
        if (-not $ClaudePackage) {
            $arch=switch ($env:PROCESSOR_ARCHITECTURE) {
                'AMD64' {'x64'}; 'ARM64' {'arm64'}; default { throw 'Unsupported Windows architecture for Claude Desktop.' }
            }
            $ClaudePackage=Join-Path $stage 'Claude.msix'
            Get-OfficialPackage "https://claude.ai/api/desktop/win32/$arch/msix/latest/redirect" $ClaudePackage
        }
        $sig=Get-AuthenticodeSignature -LiteralPath $ClaudePackage
        if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or
            $sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) -ne 'Anthropic, PBC') {
            throw 'Claude MSIX signature verification failed.'
        }
        Add-AppxPackage -Path $ClaudePackage -ErrorAction Stop
    }
} finally {
    Get-ChildItem -LiteralPath $stage.FullName -File | Remove-Item -Force
    Remove-Item -LiteralPath $stage.FullName
}

$claude=Get-ClaudeExecutable
if (-not $claude) { throw 'Claude MSIX is not registered for the interactive user.' }
$productRoot=Split-Path -Parent $claude
Set-DesktopFirewall $productRoot
Assert-DesktopFirewall $productRoot

$entries=& (Join-Path $PSScriptRoot 'update-windows-launchers.ps1')
[pscustomobject]@{Shortcuts=$entries;Browsers=@(Get-SupportedBrowsers).Name;ClaudeDesktop=$claude;Proxy=$proxy}
