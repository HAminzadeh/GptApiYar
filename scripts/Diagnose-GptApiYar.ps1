param([string]$CdpUrl = 'http://127.0.0.1:9222')
$ErrorActionPreference = 'Stop'
function Check($name, $url) {
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
        Write-Host "[OK] $name HTTP $($r.StatusCode)" -ForegroundColor Green
        if ($name -eq 'Chrome CDP') {
            $info = $r.Content | ConvertFrom-Json
            Write-Host ("     " + $info.Browser)
        }
    } catch {
        Write-Host "[FAIL] $name - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
Check 'React' 'http://127.0.0.1:5173'
$token = if ($env:GATEWAY_TOKEN) { $env:GATEWAY_TOKEN } else { 'dev-change-this-token' }
try {
    $r = Invoke-WebRequest 'http://127.0.0.1:8787/api/health' -Headers @{'X-Gateway-Token'=$token} -UseBasicParsing -TimeoutSec 5
    Write-Host "[OK] Spring Boot HTTP $($r.StatusCode)" -ForegroundColor Green
} catch { Write-Host "[FAIL] Spring Boot - $($_.Exception.Message)" -ForegroundColor Yellow }
Check 'Chrome CDP' "$($CdpUrl.TrimEnd('/'))/json/version"
Check 'Local demo' 'http://127.0.0.1:8787/demo.html'
Write-Host 'No browser extension is required for CDP. Use scripts/start-chrome-debug.ps1.'