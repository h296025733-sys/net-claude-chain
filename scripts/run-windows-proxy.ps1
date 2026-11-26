param([switch]$RouteOnly)

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'windows-client-common.ps1')
$settings=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$daemon=Join-Path $PSScriptRoot 'daemon'
$nextFirewallCheck=[datetime]::MinValue
$protectedRoot=$null
$log=Join-Path $PSScriptRoot 'proxy-watch.log'
$lastStatus=$null

function Write-ProxyStatus([string]$Message) {
    if ($script:lastStatus -eq $Message) { return }
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 256KB) {
        Move-Item -LiteralPath $log -Destination "$log.previous" -Force
    }
    Add-Content -LiteralPath $log -Value ('{0:s} {1}' -f (Get-Date),$Message)
    $script:lastStatus=$Message
}

function Update-DesktopProtection {
    if (-not $settings.UserSid -or [datetime]::UtcNow -lt $script:nextFirewallCheck) { return }
    $script:nextFirewallCheck=[datetime]::UtcNow.AddSeconds(30)
    try {
        $exe=Get-ClaudeExecutable -UserSid $settings.UserSid
        if (-not $exe) { return }
        $path=Split-Path -Parent $exe
        if ($path -ne $script:protectedRoot) {
            Set-DesktopFirewall $path
            Assert-DesktopFirewall $path
            $script:protectedRoot=$path
        }
    } catch {
        Write-ProxyStatus $_.Exception.Message
    }
}

if (-not $RouteOnly) {
    $executable=Join-Path $daemon 'xray.exe'
    Get-CimInstance -ClassName Win32_Process -Filter "Name='xray.exe'" |
        Where-Object ExecutablePath -eq $executable |
        ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
}
while ($true) {
    $worker=$null
    try {
        Update-PhysicalRoute $settings.VpsIp (Join-Path $PSScriptRoot 'route.json')
        if ($RouteOnly) {
            Update-DesktopProtection
            Start-Sleep -Seconds 10
            continue
        }
        $config=Join-Path $daemon 'client.json'
        $launch=@{
            FilePath=(Join-Path $daemon 'xray.exe')
            WorkingDirectory=$daemon
            ArgumentList=('run -c "{0}"' -f $config)
            WindowStyle='Hidden'
            PassThru=$true
            RedirectStandardOutput=(Join-Path $daemon 'xray.out.log')
            RedirectStandardError=(Join-Path $daemon 'xray.err.log')
        }
        $worker=Start-Process @launch
        Write-ProxyStatus 'Dedicated Xray worker started'
        while (-not $worker.WaitForExit(5000)) {
            Update-PhysicalRoute $settings.VpsIp (Join-Path $PSScriptRoot 'route.json')
            Update-DesktopProtection
        }
        Write-ProxyStatus ("Dedicated Xray worker exited with code {0}" -f $worker.ExitCode)
    } catch {
        Write-ProxyStatus $_.Exception.Message
    } finally {
        if ($worker -and -not $worker.HasExited) { $worker.Kill(); [void]$worker.WaitForExit(3000) }
    }
    Start-Sleep -Seconds 5
}
