$ErrorActionPreference = 'Stop'
$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$chrome = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw 'Chrome not found. Edit this script with its correct path.' }
$profile = Join-Path $env:LOCALAPPDATA 'GptApiYar\ChromeProfile'
New-Item -ItemType Directory -Path $profile -Force | Out-Null
Write-Host 'Opening an ISOLATED Chrome profile with local CDP endpoint 127.0.0.1:9222.'
Write-Host 'Do not expose port 9222 to your LAN or the internet.'
& $chrome --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 "--user-data-dir=$profile" --no-first-run 'http://127.0.0.1:8787/demo.html'
