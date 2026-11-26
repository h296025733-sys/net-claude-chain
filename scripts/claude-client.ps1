[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Web','Desktop','Check','Watch')][string]$Mode,
    [ValidateSet('Auto','Chrome','Edge')][string]$Browser='Auto'
)

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'windows-client-common.ps1')
$settings=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'settings.json') -Raw | ConvertFrom-Json
$proxy="http://127.0.0.1:$($settings.ProxyPort)"
$proxyArg="--proxy-server=$proxy"
$browserFlags=@($proxyArg,'--disable-quic','--force-webrtc-ip-handling-policy=disable_non_proxied_udp')

function Assert-Chain {
    Assert-PhysicalRoute -VpsIp $settings.VpsIp
    $ip=& curl.exe -q --fail --silent --show-error --proxy $proxy --noproxy unused.invalid --connect-timeout 4 --max-time 9 https://api.ipify.org
    if ($LASTEXITCODE -ne 0 -or ([string]$ip).Trim() -ne $settings.ExpectedExit) {
        throw 'The dedicated proxy is unavailable or its exit IP changed.'
    }
}

function Get-ClaudeProcess([int]$SessionId) {
    Get-CimInstance Win32_Process -Filter "Name='claude.exe' AND SessionId=$SessionId" |
        Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '(?:^|\s)--type=' }
}

function Start-ClaudeDesktop {
    param([switch]$Watching)
    $exe=Get-ClaudeExecutable
    if (-not $exe) { throw 'Claude Desktop is not installed for this Windows user.' }
    $session=(Get-Process -Id $PID).SessionId
    $running=@(Get-ClaudeProcess $session)
    if ($running | Where-Object { $_.ExecutablePath -ne $exe -or $_.CommandLine -notlike "*$proxyArg*" }) {
        throw 'Close the existing Claude window and open the dedicated Desktop shortcut.'
    }
    Assert-DesktopFirewall -ProductRoot (Split-Path -Parent $exe)
    if ($running) {
        if (-not $Watching) {
            $window=$running | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue } |
                Where-Object MainWindowTitle | Select-Object -First 1
            if ($window) {
                $shell=New-Object -ComObject WScript.Shell
                [void]$shell.AppActivate([int]$window.Id)
            }
        }
        return
    }
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -ArgumentList $browserFlags
}

function Start-DedicatedBrowser {
    param([string]$Url)
    $available=Get-SupportedBrowsers
    $selected=if ($Browser -eq 'Auto') { $available | Select-Object -First 1 } else {
        $available | Where-Object Name -eq $Browser | Select-Object -First 1
    }
    if (-not $selected) { throw "Supported browser unavailable: $Browser" }
    $profile=Join-Path $settings.ProfileRoot $selected.Name
    $args=@("--user-data-dir=`"$profile`"") + $browserFlags +
        @('--no-first-run','--no-default-browser-check','--new-window',$Url)
    Start-Process -FilePath $selected.Path -ArgumentList $args
}

function Write-WatchStatus([string]$Message) {
    $log=Join-Path $env:LOCALAPPDATA 'NetClaudeChain\desktop-watch.log'
    if ($script:lastStatus -ne $Message) {
        if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 256KB) {
            Move-Item -LiteralPath $log -Destination "$log.previous" -Force
        }
        Add-Content -LiteralPath $log -Value ('{0:s} {1}' -f (Get-Date),$Message)
        $script:lastStatus=$Message
    }
}

if ($Mode -eq 'Watch') {
    $mutex=[Threading.Mutex]::new($false,'Local\NetClaudeChainDesktopWatch')
    $locked=$false
    try {
        try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
        if (-not $locked) { return }
        while ($true) {
            try {
                Assert-Chain
                Start-ClaudeDesktop -Watching
                Write-WatchStatus 'Dedicated route and Claude Desktop healthy'
            } catch {
                Write-WatchStatus $_.Exception.Message
            }
            Start-Sleep -Seconds 30
        }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
    return
}

try {
    Assert-Chain
    switch ($Mode) {
        'Web' { Start-DedicatedBrowser 'https://claude.ai/' }
        'Desktop' { Start-ClaudeDesktop }
        'Check' { Start-DedicatedBrowser 'https://ip.net.coffee/ip/' }
    }
} catch {
    $shell=New-Object -ComObject WScript.Shell
    [void]$shell.Popup($_.Exception.Message,12,'Claude dedicated connection',48)
    throw
}
