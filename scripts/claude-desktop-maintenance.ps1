function Get-ClaudeDesktopState {
    $package = Get-ClaudePackage
    $state = 'Missing'
    if ($package) {
        $state = 'NeedsRepair'
        if ($package.InstallLocation -and $package.Status -eq 'Ok' -and
            (Test-Path -LiteralPath (Join-Path $package.InstallLocation 'app\claude.exe') -PathType Leaf)) {
            $state = 'Healthy'
        }
    }
    $legacyDirectories = @(
        'AnthropicClaude\claude.exe', 'AnthropicClaude\current\claude.exe', 'Programs\Claude\Claude.exe'
    )
    $legacy = $legacyDirectories | Where-Object { Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA $_) -PathType Leaf }
    $codeCli = (Get-Command claude -CommandType Application,ExternalScript -ErrorAction SilentlyContinue) -or
        (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.local\bin\claude.exe') -PathType Leaf)
    [pscustomobject]@{ State = $state; Package = $package; LegacyDesktop = [bool]$legacy; ClaudeCodeCli = [bool]$codeCli }
}

function Backup-ClaudeLocalData([string[]]$ProjectPaths) {
    $paths = [ordered]@{
        'Desktop-Package' = Join-Path $env:LOCALAPPDATA 'Packages\Claude_pzs8sxrjxfjjc'
        'Desktop-Roaming' = Join-Path $env:APPDATA 'Claude'
        'Desktop-Local' = Join-Path $env:LOCALAPPDATA 'Claude'
        'Code-Profile' = Join-Path $env:USERPROFILE '.claude'
        'Code-Preferences.json' = Join-Path $env:USERPROFILE '.claude.json'
    }
    if ($env:CLAUDE_CONFIG_DIR) {
        $configPath = [Environment]::ExpandEnvironmentVariables($env:CLAUDE_CONFIG_DIR)
        $paths['Code-ConfiguredProfile'] = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($configPath)
    }
    for ($index = 0; $index -lt $ProjectPaths.Count; $index++) {
        $paths['Project-' + ($index + 1)] = (Get-Item -LiteralPath $ProjectPaths[$index] -Force -ErrorAction Stop).FullName
    }

    $sources = @{}
    foreach ($name in $paths.Keys) {
        if (Test-Path -LiteralPath $paths[$name] -ErrorAction Stop) {
            $item = Get-Item -LiteralPath $paths[$name] -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Export the redirected Claude project or data folder before repairing: $($item.FullName)"
            }
            if ($item.FullName -notin $sources.Values.FullName) { $sources[$name] = $item }
        }
    }
    if (-not $sources.Count) { return }

    $base = Join-Path $env:LOCALAPPDATA 'NetClaudeChain\ClaudeBackups'
    $folderName = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N'))
    $backup = Join-Path $base $folderName
    foreach ($source in $sources.Values) {
        if ($source.PSIsContainer -and $backup.StartsWith($source.FullName.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "The Claude backup cannot be stored inside its source directory: $($source.FullName)"
        }
    }
    foreach ($folder in @((Split-Path -Parent $base), $base)) {
        $directory = if (Test-Path -LiteralPath $folder -ErrorAction Stop) {
            Get-Item -LiteralPath $folder -Force -ErrorAction Stop
        } else {
            New-Item -ItemType Directory -Path $folder -ErrorAction Stop
        }
        if (-not $directory.PSIsContainer) { throw 'The Claude backup location is not a directory.' }
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'The Claude backup location is redirected.' }
    }
    New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $backup /inheritance:r /grant:r "*$($userSid):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not protect the Claude data backup.' }

    $manifest = [ordered]@{}
    foreach ($name in $sources.Keys) {
        $source = $sources[$name]
        $destination = Join-Path $backup $name
        if ($source.PSIsContainer) {
            & robocopy.exe $source.FullName $destination /E /XJ /SL /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP | Out-Null
            if ($LASTEXITCODE -ge 8 -or -not (Test-Path -LiteralPath $destination -PathType Container)) {
                throw "Claude data backup failed. Original data remains in place. Incomplete backup: $backup"
            }
        } else {
            Copy-Item -LiteralPath $source.FullName -Destination $destination -ErrorAction Stop
        }
        $manifest[$name] = $source.FullName
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'sources.json') -Encoding UTF8 -ErrorAction Stop
    return $backup
}
