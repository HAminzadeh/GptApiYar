param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\frontend')).Path
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'Node.js/npm not found in PATH. Install Node.js 22.12+ and reopen PowerShell.' }
Push-Location $root
try {
    if (-not (Test-Path -LiteralPath (Join-Path $root 'node_modules') -PathType Container)) {
        Write-Host '[GptApiYar] Installing React dependencies (first run needs internet)...' -ForegroundColor Yellow
        & npm.cmd install
        if ($LASTEXITCODE -ne 0) { throw "npm install exited with code $LASTEXITCODE" }
    }
    Write-Host '[GptApiYar] Starting React on http://127.0.0.1:5173' -ForegroundColor Cyan
    & npm.cmd run dev
    if ($LASTEXITCODE -ne 0) { throw "npm run dev exited with code $LASTEXITCODE" }
} finally { Pop-Location }
