[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Web','Desktop','Check')][string]$Mode,
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
    $exe=Get-ClaudeExecutable
    if (-not $exe) { throw 'Claude Desktop is not installed for this Windows user.' }
    $session=(Get-Process -Id $PID).SessionId
    $running=@(Get-ClaudeProcess $session)
    if ($running | Where-Object { $_.ExecutablePath -ne $exe -or $_.CommandLine -notlike "*$proxyArg*" }) {
        throw 'Close the existing Claude window and open the dedicated Desktop shortcut.'
    }
    Assert-DesktopFirewall -ProductRoot (Split-Path -Parent $exe)
    $window=$running | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue } |
        Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
    if ($window) {
        $shell=New-Object -ComObject WScript.Shell
        [void]$shell.AppActivate([int]$window.Id)
        return
    }

    $launch=[Diagnostics.ProcessStartInfo]::new($exe, ($browserFlags -join ' '))
    $launch.WorkingDirectory=Split-Path -Parent $exe
    $launch.UseShellExecute=$false
    $launch.CreateNoWindow=$true
    [void][Diagnostics.Process]::Start($launch)
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
