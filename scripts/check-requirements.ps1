$ErrorActionPreference = 'Stop'
$required = @(
    @{ Name = 'Java JDK 21+'; Cmd = 'java.exe' },
    @{ Name = 'Apache Maven'; Cmd = 'mvn.cmd' },
    @{ Name = 'Node.js'; Cmd = 'node.exe' },
    @{ Name = 'npm'; Cmd = 'npm.cmd' }
)
Write-Host '=== GptApiYar prerequisites ===' -ForegroundColor Cyan
$missing = $false
foreach ($item in $required) {
    $found = Get-Command $item.Cmd -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "[ OK ] $($item.Name): $($found.Source)" -ForegroundColor Green
    } else {
        Write-Host "[MISS] $($item.Name)" -ForegroundColor Yellow
        $missing = $true
    }
}
$paths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
if ($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1) {
    Write-Host '[ OK ] Google Chrome' -ForegroundColor Green
} else {
    Write-Host '[MISS] Google Chrome' -ForegroundColor Yellow
    $missing = $true
}
if ($missing) { Write-Host 'Install missing tools, then run again.' -ForegroundColor Yellow }
else { Write-Host 'All required executables detected. Versions and runtime connectivity are not verified.' -ForegroundColor Green }
