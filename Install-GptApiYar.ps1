# GptApiYar local installer - Windows PowerShell 5.1+
# Downloads GptApiYar.zip separately, then extracts it to D:\ChatGPT_Projects\GptApiYar.
# Never deletes the existing project; preserves overwritten files in timestamped backups.
param(
    [string]$ZipPath = ''
)
$ErrorActionPreference = 'Stop'
$target = 'D:\ChatGPT_Projects\GptApiYar'
$backupBase = 'D:\ChatGPT_Projects\_GptApiYar_Backups'
$stage = $null
$applied = New-Object System.Collections.ArrayList
$backupDir = $null

function Resolve-ZipFile {
    param([string]$ExplicitPath)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) { throw "ZIP not found: $ExplicitPath" }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    $candidates = @(
        (Join-Path $PSScriptRoot 'GptApiYar.zip'),
        (Join-Path (Join-Path $env:USERPROFILE 'Downloads') 'GptApiYar.zip'),
        'D:\ChromDownloads\GptApiYar.zip',
        (Join-Path (Join-Path $env:USERPROFILE 'Desktop') 'GptApiYar.zip')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'GptApiYar.zip not found in the script folder, Downloads, D:\ChromDownloads or Desktop. Use -ZipPath to specify it.'
}

try {
    if (-not (Test-Path -LiteralPath 'D:\' -PathType Container)) {
        throw 'Drive D: was not found. This installer is designed for D:\ChatGPT_Projects\GptApiYar.'
    }
    $zipFile = Resolve-ZipFile -ExplicitPath $ZipPath
    Write-Host "[1/5] ZIP found: $zipFile" -ForegroundColor Cyan
    $hash = (Get-FileHash -LiteralPath $zipFile -Algorithm SHA256).Hash
    Write-Host "      SHA256: $hash"

    # Check archive entries before expanding to a temporary directory.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipFile)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            $segments = $name.Split('/')
            if ($name.StartsWith('/') -or $name.StartsWith('//') -or
                $name -match '^[A-Za-z]:' -or
                $segments -contains '..' -or
                $name.Contains(':')) {
                throw "Unsafe ZIP path: $name"
            }
        }
    } finally { $archive.Dispose() }

    $stage = Join-Path $env:TEMP ('GptApiYar-installer-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Write-Host '[2/5] Extracting ZIP into temporary staging...' -ForegroundColor Cyan
    Expand-Archive -LiteralPath $zipFile -DestinationPath $stage -Force
    $payload = Join-Path $stage 'GptApiYar'
    if (-not (Test-Path -LiteralPath (Join-Path $payload 'backend\pom.xml') -PathType Leaf)) {
        $payload = $stage
    }
    foreach ($required in @('backend\pom.xml', 'frontend\package.json', 'scripts\start-backend.ps1', 'scripts\start-frontend.ps1', 'scripts\start-all.ps1', 'README-fa.md')) {
        $requiredFile = Join-Path $payload $required
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) { throw "Missing required ZIP file: $required" }
    }
    $sourceFiles = @(Get-ChildItem -LiteralPath $payload -Recurse -File)
    if ($sourceFiles.Count -lt 12) { throw 'Incomplete project archive: too few files.' }

    Write-Host "[3/5] Installing to $target" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
    }
    $backupLabel = (Get-Date).ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
    foreach ($source in $sourceFiles) {
        $relative = $source.FullName.Substring($payload.Length).TrimStart([char]'\', [char]'/')
        $destination = Join-Path $target $relative
        if (Test-Path -LiteralPath $destination -PathType Container) {
            throw "Expected file but found directory: $destination"
        }
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $hadExisting = Test-Path -LiteralPath $destination -PathType Leaf
        $backupFile = ''
        if ($hadExisting) {
            if (-not $backupDir) {
                $backupDir = Join-Path $backupBase $backupLabel
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            }
            $backupFile = Join-Path $backupDir $relative
            $backupParent = Split-Path -Parent $backupFile
            if (-not (Test-Path -LiteralPath $backupParent -PathType Container)) {
                New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
            }
            Copy-Item -LiteralPath $destination -Destination $backupFile -Force
        }
        [void]$applied.Add([pscustomobject]@{ Target = $destination; Previous = $backupFile })
        Copy-Item -LiteralPath $source.FullName -Destination $destination -Force
    }
    Write-Host "[4/5] Verified and copied $($sourceFiles.Count) files." -ForegroundColor Green
    if ($backupDir) { Write-Host "      Backups: $backupDir" -ForegroundColor Yellow }
    Write-Host '[5/5] Installation complete.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Project: D:\ChatGPT_Projects\GptApiYar' -ForegroundColor Green
    Write-Host 'To check prerequisites:' -ForegroundColor Cyan
    Write-Host 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\ChatGPT_Projects\GptApiYar\scripts\check-requirements.ps1"'
    Write-Host 'To launch backend, frontend and isolated Chrome:' -ForegroundColor Cyan
    Write-Host 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\ChatGPT_Projects\GptApiYar\scripts\start-all.ps1"'
    Write-Host 'UI: http://127.0.0.1:5173'
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($applied.Count -gt 0) {
        Write-Host 'Rolling back modified files...' -ForegroundColor Yellow
        for ($i = $applied.Count - 1; $i -ge 0; $i--) {
            $entry = $applied[$i]
            try {
                if ($entry.Previous) {
                    Copy-Item -LiteralPath $entry.Previous -Destination $entry.Target -Force
                } elseif (Test-Path -LiteralPath $entry.Target -PathType Leaf) {
                    Remove-Item -LiteralPath $entry.Target -Force
                }
            } catch { Write-Warning "Rollback failed: $($entry.Target)" }
        }
    }
    exit 1
} finally {
    if ($stage -and (Test-Path -LiteralPath $stage -PathType Container)) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
