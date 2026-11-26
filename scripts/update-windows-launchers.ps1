[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'windows-client-common.ps1')

$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this update as an administrator in the interactive user account.'
}

$root=Join-Path $env:ProgramData 'NetClaudeChain'
if (-not (Test-Path -LiteralPath (Join-Path $root 'settings.json') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $root 'windows-client-common.ps1') -PathType Leaf)) {
    throw 'Run the Windows client installer to configure the dedicated proxy first.'
}
if ((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'Unexpected redirected runtime directory.'
}

Remove-LegacyClaudeDesktopTask
$claude=Get-ClaudeExecutable
$browser=(Get-SupportedBrowsers | Select-Object -First 1).Path
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
if (-not $claude -or -not $browser -or -not $desktop) {
    throw 'Claude Desktop, a supported browser and a Windows desktop folder are required.'
}

foreach ($file in @('claude-client.ps1','launch-claude-client.js')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $root $file) -Force
}
$labels=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'windows-shortcuts.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$entries=Join-Path $desktop $labels.Folder
New-Item -ItemType Directory -Path $entries -Force | Out-Null
$shell=New-Object -ComObject WScript.Shell
$scriptHost=Join-Path $env:SystemRoot 'System32\wscript.exe'
$launcher=Join-Path $root 'launch-claude-client.js'

function New-LandingShortcut($Name,$Mode,$Icon) {
    $shortcut=$shell.CreateShortcut((Join-Path $entries "$Name.lnk"))
    $shortcut.TargetPath=$scriptHost
    $shortcut.Arguments='//B //NoLogo //E:JScript "{0}" {1}' -f $launcher,$Mode
    $shortcut.WorkingDirectory=$root
    $shortcut.IconLocation="$Icon,0"
    $shortcut.Save()
}

New-LandingShortcut $labels.Web 'Web' $browser
New-LandingShortcut $labels.Desktop 'Desktop' $claude
New-LandingShortcut $labels.Check 'Check' $browser
$entries
