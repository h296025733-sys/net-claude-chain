[CmdletBinding()]
param([Parameter(Mandatory)][string]$Destination)

$ErrorActionPreference='Stop'
$architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture
$assetName=switch ($architecture) {
    'X64' { 'Xray-windows-64.zip' }
    'Arm64' { 'Xray-windows-arm64-v8a.zip' }
    default { throw "Unsupported Windows architecture: $architecture" }
}
$release=Invoke-RestMethod -Uri 'https://api.github.com/repos/XTLS/Xray-core/releases/latest' -Headers @{
    'User-Agent'='net-claude-chain'
    'Accept'='application/vnd.github+json'
} -TimeoutSec 45
$asset=$release.assets | Where-Object name -eq $assetName | Select-Object -First 1
if (-not $asset -or $asset.digest -notmatch '^sha256:[a-f0-9]{64}$' -or
    -not $asset.browser_download_url.StartsWith('https://github.com/XTLS/Xray-core/releases/download/')) {
    throw 'The official Xray archive or its SHA-256 digest is unavailable.'
}
$folder=New-Item -ItemType Directory -Path $Destination -Force
$archive=Join-Path $folder.FullName $assetName
try {
    & curl.exe -q --location --fail --silent --show-error --proto '=https' --proto-redir '=https' --retry 1 --connect-timeout 15 --max-time 120 --output $archive $asset.browser_download_url
    if ($LASTEXITCODE -ne 0) { throw 'Official Xray download failed.' }
    $digest=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($digest -ne $asset.digest.Substring(7)) { throw 'Official Xray archive SHA-256 mismatch.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $folder.FullName -Force
    $exe=Join-Path $folder.FullName 'xray.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'The official archive did not contain xray.exe.' }
    $exe
} finally {
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
}
