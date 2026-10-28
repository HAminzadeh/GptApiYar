# Build a ZIP from the current, reviewed extension source. No Git actions.
param([string]$ProjectRoot = (Join-Path $PSScriptRoot '..'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$source = Join-Path $root 'chrome-extension'
$destinationDir = Join-Path $root 'frontend\public'
$destination = Join-Path $destinationDir 'GptApiYar-Chrome-Extension.zip'
$files = @('manifest.json','popup.html','popup.js','content.js','README-fa.md')
foreach ($name in @($files | Where-Object { $_ -ne 'README-fa.md' })) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) {
        throw "Missing required extension file: $name"
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.manifest_version -ne 3) { throw 'Expected Manifest V3.' }
if (-not (Test-Path -LiteralPath $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
}
$staging = Join-Path ([System.IO.Path]::GetTempPath()) ('gptapiyar-extension-' + [guid]::NewGuid().ToString('N'))
$temporaryZip = Join-Path ([System.IO.Path]::GetTempPath()) ('gptapiyar-extension-' + [guid]::NewGuid().ToString('N') + '.zip')
try {
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    foreach ($name in $files) {
        $file = Join-Path $source $name
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Copy-Item -LiteralPath $file -Destination (Join-Path $staging $name)
        }
    }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $temporaryZip -CompressionLevel Optimal -Force
    Add-Type -AssemblyName System.IO.Compression
    $archive = [System.IO.Compression.ZipFile]::OpenRead($temporaryZip)
    try {
        $entries = @($archive.Entries | ForEach-Object { $_.FullName })
        if ($entries -notcontains 'manifest.json' -or $entries -notcontains 'popup.html' -or
            $entries -notcontains 'popup.js' -or $entries -notcontains 'content.js') {
            throw 'ZIP verification failed: expected extension files at ZIP root.'
        }
    } finally { $archive.Dispose() }
    Copy-Item -LiteralPath $temporaryZip -Destination $destination -Force
    Write-Host "[OK] Extension ZIP created: $destination" -ForegroundColor Green
    Write-Host 'Vite download URL: http://127.0.0.1:5173/GptApiYar-Chrome-Extension.zip'
} finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    if (Test-Path -LiteralPath $temporaryZip) { Remove-Item -LiteralPath $temporaryZip -Force }
}