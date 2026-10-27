param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
foreach ($name in @('start-backend.ps1', 'start-frontend.ps1', 'start-chrome-debug.ps1')) {
    $file = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $file)) { throw "Script not found: $file" }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -NoExit -File "' + $file + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $root
    Write-Host "Started: $name"
    if ($name -eq 'start-backend.ps1') { Start-Sleep -Seconds 5 }
}
Write-Host ''
Write-Host '[GptApiYar] React: http://127.0.0.1:5173' -ForegroundColor Green
Write-Host '[GptApiYar] Demo : http://127.0.0.1:8787/demo.html' -ForegroundColor Green
Write-Host 'Wait until Maven and npm have started. Reload Chrome demo page if it opened before the backend.' -ForegroundColor Yellow
