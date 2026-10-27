param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\backend')).Path
if (-not (Get-Command java.exe -ErrorAction SilentlyContinue)) { throw 'Java JDK 21+ not found in PATH. Install JDK 21 and reopen PowerShell.' }
if (-not (Get-Command mvn.cmd -ErrorAction SilentlyContinue)) { throw 'Apache Maven (mvn.cmd) not found in PATH. Install Maven and reopen PowerShell.' }
if (-not $env:GATEWAY_TOKEN) { $env:GATEWAY_TOKEN = 'dev-change-this-token' }
Write-Host '[GptApiYar] Starting Spring Boot on http://127.0.0.1:8787' -ForegroundColor Cyan
Push-Location $root
try { & mvn.cmd spring-boot:run; if ($LASTEXITCODE -ne 0) { throw "Maven exited with code $LASTEXITCODE" } }
finally { Pop-Location }
