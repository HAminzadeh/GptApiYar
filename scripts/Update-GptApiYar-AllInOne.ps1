#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ProjectPath = 'D:\ChatGPT_Projects\GptApiYar',
    [switch]$Push,
    [switch]$Build,
    [switch]$Start
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoUrl = 'https://github.com/HAminzadeh/GptApiYar.git'
$repoSsh = 'git@github.com:HAminzadeh/GptApiYar.git'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$changes = [ordered]@{}
$scriptName = 'Update-GptApiYar-AllInOne.ps1'

function Say([string]$message, [string]$color='Cyan') { Write-Host ("[GptApiYar] " + $message) -ForegroundColor $color }
function Assert-Ok([string]$message) { if ($LASTEXITCODE -ne 0) { throw $message } }
function Read-ProjectFile([string]$relative) {
    $p = Join-Path $ProjectPath $relative
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing required file: $p" }
    return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
}
function Replace-Required([string]$text, [string]$old, [string]$new, [string]$description) {
    # The replacement can itself contain the old snippet; check the new block FIRST.
    if ($new.Length -gt 0 -and $text.Contains($new)) { return $text }
    if ($old.Length -gt 0 -and $text.Contains($old)) { return $text.Replace($old, $new) }
    if ($new.Length -eq 0) { return $text }  # an optional removed UI element
    throw "Patch signature has changed: $description. No files have been written."
}
function Stage-Change([string]$relative, [string]$content) {
    $changes[$relative] = $content
}
function Write-Utf8([string]$path, [string]$value) {
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $encoding = if ([System.IO.Path]::GetExtension($path) -ieq '.ps1') { [System.Text.UTF8Encoding]::new($true) } else { $utf8 }
    [System.IO.File]::WriteAllText($path, $value, $encoding)
}

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) { throw "Project not found: $ProjectPath" }
$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path.TrimEnd('\')
foreach ($relative in @('backend\pom.xml','frontend\src\main.jsx','frontend\src\style.css','scripts\Publish-GptApiYar.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath $relative))) { throw "Unexpected project layout, cannot continue: $relative" }
}
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'Git for Windows is not installed or not in PATH.' }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath '.git'))) { throw 'No .git directory. Clone or initialize the repository safely before running this update.' }

Push-Location $ProjectPath
try {
    Say "Checking the repository at $ProjectPath"
    $root = (& git.exe rev-parse --show-toplevel)
    Assert-Ok 'git rev-parse failed'
    if (-not [string]::Equals(($root.Trim().Replace('/','\')).TrimEnd('\'),$ProjectPath,[StringComparison]::OrdinalIgnoreCase)) {
        throw "This folder is not the Git repository root: $root"
    }
    $statusBefore = @(& git.exe status --porcelain)
    Assert-Ok 'git status failed'
    if ($statusBefore.Count -gt 0) {
        & git.exe status --short
        throw 'Local changes were found. Please commit or stash them first. No files changed by this script.'
    }
    $names = @(& git.exe remote)
    if ($names -notcontains 'origin') {
        & git.exe remote add origin $repoUrl
        Assert-Ok 'Cannot create origin remote'
        Say 'Added the missing origin remote.' 'Green'
    } else {
        $origin = (& git.exe remote get-url origin).Trim()
        Assert-Ok 'Cannot read origin remote'
        if ($origin -cne $repoUrl -and $origin -cne $repoSsh) {
            throw "Origin points to another repository: $origin"
        }
    }
    $branch = (& git.exe branch --show-current).Trim()
    if ($branch -ne 'main') { throw "Expected branch main, found: $branch" }
    Say 'Fetching the latest main from GitHub (no forced changes)...'
    & git.exe fetch origin main
    Assert-Ok 'Cannot fetch from GitHub. Check network and credentials.'
    & git.exe rev-parse --verify refs/remotes/origin/main *> $null
    Assert-Ok 'GitHub main branch not found'
    & git.exe merge-base --is-ancestor HEAD refs/remotes/origin/main
    if ($LASTEXITCODE -eq 0) {
        & git.exe merge --ff-only refs/remotes/origin/main
        Assert-Ok 'Fast-forward update failed'
    } else {
        & git.exe merge-base --is-ancestor refs/remotes/origin/main HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Local/remote histories diverged; refusing to overwrite either.' }
        Say 'Local main has commits ahead of origin/main; preserving them.' 'Yellow'
    }

    # ---- BACKEND: fast, browser-download-free diagnostic before Playwright.connectOverCDP ----
    $relative = 'backend\src\main\java\ir\gptapiyar\bridge\core\CdpProbe.java'
    $java = @'
package ir.gptapiyar.bridge.core;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

@Component
public class CdpProbe {
    private final HttpClient client = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(2))
        .followRedirects(HttpClient.Redirect.NEVER)
        .build();
    private final ObjectMapper mapper = new ObjectMapper();

    public record Tab(String title, String url) {}
    public record Result(boolean reachable, String message, String browser, List<Tab> tabs) {}

    private URI requireLocalHttp(String endpoint) {
        URI uri;
        try { uri = URI.create(endpoint == null ? "" : endpoint.trim()); }
        catch (Exception ex) { throw new IllegalArgumentException("Invalid CDP URL"); }
        String host = uri.getHost();
        if (!"http".equalsIgnoreCase(uri.getScheme()) ||
            !("127.0.0.1".equals(host) || "localhost".equalsIgnoreCase(host) || "::1".equals(host)) ||
            uri.getPort() <= 0 || uri.getPort() > 65535 ||
            uri.getUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null ||
            (uri.getPath() != null && !uri.getPath().isEmpty() && !"/".equals(uri.getPath()))) {
            throw new IllegalArgumentException("CDP must be a local http://127.0.0.1:PORT endpoint");
        }
        return uri;
    }

    private JsonNode read(URI uri, String path) throws Exception {
        URI target = new URI("http", null, uri.getHost(), uri.getPort(), path, null, null);
        HttpRequest request = HttpRequest.newBuilder(target)
            .GET().timeout(Duration.ofSeconds(3)).build();
        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) throw new IllegalStateException("CDP HTTP " + response.statusCode());
        return mapper.readTree(response.body());
    }

    public Result inspect(String endpoint) {
        URI uri = requireLocalHttp(endpoint);
        try {
            JsonNode version = read(uri, "/json/version");
            String browser = version.path("Browser").asText("Chrome");
            JsonNode targets = read(uri, "/json/list");
            List<Tab> tabs = new ArrayList<>();
            if (targets.isArray()) {
                for (JsonNode node : targets) {
                    if (tabs.size() >= 30) break;
                    if (!"page".equals(node.path("type").asText())) continue;
                    tabs.add(new Tab(node.path("title").asText(""),node.path("url").asText("")));
                }
            }
            return new Result(true, "CDP is reachable", browser, tabs);
        } catch (Exception e) {
            return new Result(false, "CDP unavailable: " + e.getClass().getSimpleName() +
                ". Start the separate Chrome CDP window on port " + uri.getPort() + ".", "", List.of());
        }
    }
}
'@
    if (Test-Path -LiteralPath (Join-Path $ProjectPath $relative)) {
        $existing = Read-ProjectFile $relative
        if ($existing -cne $java) { throw 'CdpProbe.java already exists with different content; manual review required.' }
    }
    Stage-Change $relative $java

    $relative = 'backend\src\main\java\ir\gptapiyar\bridge\core\BrowserBridgeService.java'
    $service = Read-ProjectFile $relative
    $patchOld1 = '    private Playwright playwright;'
    $patchNew1 = @'
    private final CdpProbe probe;
    public BrowserBridgeService(CdpProbe probe) { this.probe = probe; }

    private Playwright playwright;
'@
    $service = Replace-Required $service $patchOld1 $patchNew1 'BrowserBridgeService injection'
    $patchOld2 = @'
        disconnect();
        try {
            playwright = Playwright.create();
'@
    $patchNew2 = @'
        CdpProbe.Result inspection = probe.inspect(request.cdpEndpoint());
        if (!inspection.reachable()) {
            throw new IllegalStateException(inspection.message());
        }
        disconnect();
        try {
            playwright = Playwright.create();
'@
    $service = Replace-Required $service $patchOld2 $patchNew2 'BrowserBridgeService preflight'
    Stage-Change $relative $service

    $relative = 'backend\src\main\java\ir\gptapiyar\bridge\api\BrowserController.java'
    $controller = Read-ProjectFile $relative
    $patchOld3 = 'import ir.gptapiyar.bridge.core.BrowserBridgeService;'
    $patchNew3 = @'
import ir.gptapiyar.bridge.core.BrowserBridgeService;
import ir.gptapiyar.bridge.core.CdpProbe;
'@
    $controller = Replace-Required $controller $patchOld3 $patchNew3 'BrowserController import'
    $patchOld4 = @'
    private final BrowserBridgeService bridge;

    public BrowserController(BrowserBridgeService bridge) { this.bridge = bridge; }
'@
    $patchNew4 = @'
    private final BrowserBridgeService bridge;
    private final CdpProbe cdpProbe;

    public BrowserController(BrowserBridgeService bridge, CdpProbe cdpProbe) {
        this.bridge = bridge;
        this.cdpProbe = cdpProbe;
    }

    @GetMapping("/bridge/diagnose")
    public CdpProbe.Result diagnose(@RequestParam(defaultValue = "http://127.0.0.1:9222") String cdpEndpoint) {
        return cdpProbe.inspect(cdpEndpoint);
    }
'@
    $controller = Replace-Required $controller $patchOld4 $patchNew4 'BrowserController diagnostics'
    Stage-Change $relative $controller

    # ---- FRONTEND: white/light-only theme, visible diagnostic and finite request timeouts ----
    $relative = 'frontend\src\main.jsx'
    $react = Read-ProjectFile $relative
    $react = Replace-Required $react "  const [dark, setDark] = useState(true);" "  // Light theme only; dark mode deliberately disabled." 'React default theme'
    $react = Replace-Required $react "className={dark ? 'app dark' : 'app light'}" 'className="app light"' 'React light class'
    $patchOld5 = @'
<button className="icon-button" title={dark?'حالت روشن':'حالت تیره'} onClick={()=>setDark(!dark)}>{dark?<Sun size={19}/>:<Moon size={19}/>}</button>
'@
    $react = Replace-Required $react $patchOld5 '' 'React theme toggle'
    $patchOld6 = "  const [connecting, setConnecting] = useState(false);"
    $patchNew6 = @'
  const [connecting, setConnecting] = useState(false);
  const [cdpReport, setCdpReport] = useState(null);
'@
    $react = Replace-Required $react $patchOld6 $patchNew6 'React CDP report state'
    $patchOld7 = @'
  const [threads, setThreads] = useState(() => [newThread()]);
'@
    $patchNew7 = @'
  const [threads, setThreads] = useState(() => {
    try {
      const saved = JSON.parse(localStorage.getItem('gptapiyar.threads') || 'null');
      return Array.isArray(saved) && saved.length ? saved : [newThread()];
    } catch { return [newThread()]; }
  });
'@
    $react = Replace-Required $react $patchOld7 $patchNew7 'React local chat persistence'
    $patchOld8 = @'
  useEffect(() => { checkStatus(); }, [token]);
'@
    $patchNew8 = @'
  useEffect(() => { checkStatus(); }, [token]);
  useEffect(() => {
    try { localStorage.setItem('gptapiyar.threads', JSON.stringify(threads)); } catch {}
  }, [threads]);
'@
    $react = Replace-Required $react $patchOld8 $patchNew8 'React save chat history'
    $patchOld9 = @'
  const request = async (path, options={}) => {
    const result = await fetch(API + path, {
      ...options,
      headers: { 'X-Gateway-Token': token, ...(options.body instanceof FormData ? {} : { 'Content-Type':'application/json' }), ...options.headers }
    });
    const data = await result.json().catch(() => ({}));
    if(!result.ok) throw new Error(data.error || `خطای سرور: ${result.status}`);
    return data;
  };
'@
    $patchNew9 = @'
  const request = async (path, options={}) => {
    const { timeoutMs = 10000, ...fetchOptions } = options;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const result = await fetch(API + path, {
        ...fetchOptions,
        signal: controller.signal,
        headers: { 'X-Gateway-Token': token, ...(fetchOptions.body instanceof FormData ? {} : { 'Content-Type':'application/json' }), ...fetchOptions.headers }
      });
      const data = await result.json().catch(() => ({}));
      if(!result.ok) throw new Error(data.error || `خطای سرور: ${result.status}`);
      return data;
    } catch (e) {
      if (e.name === 'AbortError') throw new Error('مهلت درخواست تمام شد؛ وضعیت Chrome CDP و Spring Boot را بررسی کن.');
      throw e;
    } finally { clearTimeout(timer); }
  };
'@
    $react = Replace-Required $react $patchOld9 $patchNew9 'React fetch timeouts'
    $patchOld10 = @'
  const connect = async () => {
'@
    $patchNew10 = @'
  const diagnose = async () => {
    setNotice(''); setCdpReport(null);
    try {
      const report = await request('/bridge/diagnose?cdpEndpoint=' + encodeURIComponent(settings.cdpEndpoint), {timeoutMs: 6000});
      setCdpReport(report);
      setNotice(report.reachable ? `CDP فعال است؛ ${report.tabs.length} تب در دسترس است.` : report.message);
      log(report.reachable ? 'CDP در دسترس است' : report.message, report.reachable ? 'success' : 'error');
    } catch(e) {setNotice(e.message); log(e.message, 'error');}
  };
  const connect = async () => {
'@
    $react = Replace-Required $react $patchOld10 $patchNew10 'React CDP diagnose action'
    $patchOld11 = @'
const result = await request('/bridge/connect', { method:'POST', body: JSON.stringify(settings) });
'@
    $patchNew11 = @'
const result = await request('/bridge/connect', { method:'POST', body: JSON.stringify(settings), timeoutMs: 18000 });
'@
    $react = Replace-Required $react $patchOld11 $patchNew11 'React connect timeout'
    $patchOld12 = @'
const result = await request('/chat', { method:'POST', body:payload });
'@
    $patchNew12 = @'
const result = await request('/chat', { method:'POST', body:payload, timeoutMs: 105000 });
'@
    $react = Replace-Required $react $patchOld12 $patchNew12 'React chat timeout'
    $patchOld13 = @'
        <div className="connection-actions"><button className="primary-action" disabled={connecting} onClick={connect}>
'@
    $patchNew13 = @'
        <button className="cdp-diagnose-btn" onClick={diagnose}>بررسی CDP و مشاهده تب‌های مرورگر</button>
        {cdpReport && <div className="cdp-report">
          <b>{cdpReport.reachable ? `متصل: ${cdpReport.browser}` : 'CDP در دسترس نیست'}</b>
          {cdpReport.tabs?.slice(0, 20).map((tab, i) => <button key={`${tab.url}-${i}`} title={tab.url}
            onClick={() => {setSettings(current => ({...current, pageUrl: tab.url})); setPreset('custom'); setAdvanced(true);}}>
            {tab.title || tab.url}
          </button>)}
        </div>}
        <div className="connection-actions"><button className="primary-action" disabled={connecting} onClick={connect}>
'@
    $react = Replace-Required $react $patchOld13 $patchNew13 'React diagnostics control'
    Stage-Change $relative $react

    $relative = 'frontend\src\style.css'
    $css = Read-ProjectFile $relative
    if (-not $css.Contains('/* GptApiYar maintenance light UI */')) {
        $css += @'

/* GptApiYar maintenance light UI */
.app.light .notice{background:#fff6e7;color:#825019;border-color:#e7cda6}
.app.light .cdp-diagnose-btn{display:block;width:100%;background:#fff;border:1px solid #cbd6e8;border-radius:10px;padding:12px 8px;margin-top:16px;color:#334d75;font-weight:700;font-size:11px}
.app.light .cdp-diagnose-btn:hover{background:#f2f5ff;border-color:#8895ed}
.app.light .cdp-report{display:flex;flex-direction:column;gap:5px;margin-top:9px;padding:10px;background:#fff;border:1px solid #e4e9f1;border-radius:11px;max-height:200px;overflow:auto}
.app.light .cdp-report b{font-size:11px;color:#1c2640}
.app.light .cdp-report button{padding:7px;text-align:left;direction:ltr;border-bottom:1px solid #edf0f6;overflow-wrap:anywhere;font-size:10px;color:#40577d}
'@
    }
    Stage-Change $relative $css

    # ---- SCRIPTS: prevent Playwright browser bundle downloads and repair origin ----
    $relative = 'scripts\start-backend.ps1'
    $backendStart = Read-ProjectFile $relative
    if (-not $backendStart.Contains('$env:PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD')) {
        $patchOld14 = @'
if (-not $env:GATEWAY_TOKEN) { $env:GATEWAY_TOKEN = 'dev-change-this-token' }
'@
        $patchNew14 = @'
if (-not $env:GATEWAY_TOKEN) { $env:GATEWAY_TOKEN = 'dev-change-this-token' }
# CDP connects to an already-installed Chrome. Do not download Playwright browsers.
$env:PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = '1'
'@
        $backendStart = Replace-Required $backendStart $patchOld14 $patchNew14 'Playwright skip downloads'
    }
    Stage-Change $relative $backendStart

    $relative = 'scripts\Publish-GptApiYar.ps1'
    $publisher = Read-ProjectFile $relative
    $patchOld15 = @'
    $remote = (& git.exe remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $remote) {
        & git.exe remote add origin $repoUrl
        if ($LASTEXITCODE -ne 0) { throw 'Unable to add origin' }
    } else {
        $remote = $remote.Trim()
        if ($remote -ne $repoUrl -and $remote -ne 'git@github.com:HAminzadeh/GptApiYar.git') {
            throw "Origin points somewhere else: $remote. No changes made to remote."
        }
    }
'@
    $patchNew15 = @'
    $remoteNames = @(& git.exe remote)
    if ($remoteNames -notcontains 'origin') {
        & git.exe remote add origin $repoUrl
        if ($LASTEXITCODE -ne 0) { throw 'Unable to add origin' }
    } else {
        $remote = (& git.exe remote get-url origin).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Unable to read origin' }
        if ($remote -ne $repoUrl -and $remote -ne 'git@github.com:HAminzadeh/GptApiYar.git') {
            throw "Origin points somewhere else: $remote. No changes made to remote."
        }
    }
'@
    $publisher = Replace-Required $publisher $patchOld15 $patchNew15 'Publish script remote detection'
    Stage-Change $relative $publisher

    $relative = 'scripts\Diagnose-GptApiYar.ps1'
    $diagnostic = @'
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
'@
    Stage-Change $relative $diagnostic

    $relative = '.gitignore'
    $ignore = Read-ProjectFile $relative
    if (-not $ignore.Contains('# GptApiYar local secrets')) {
        $ignore += @'

# GptApiYar local secrets and browser state
.env
.env.*
!.env.example
**/application-local.yml
**/application-local.yaml
**/application-secret.yml
**/application-secret.yaml
*.pem
*.p12
*.pfx
*.key
ChromeProfile/
_GptApiYar_Backups/
'@
    }
    Stage-Change $relative $ignore

    $relative = 'README-fa.md'
    $readme = Read-ProjectFile $relative
    if (-not $readme.Contains('## Maintenance: CDP diagnostic and light UI')) {
        $readme += @'

## Maintenance: CDP diagnostic and light UI

این تغییرات رابط React را به تم روشن پیش‌فرض و بدون دکمه تم تیره تبدیل می‌کند و گفت‌وگوهای محلی را در localStorage نگه می‌دارد.
این مکالمه‌ها مستقل از مکالمات پروژه ChatGPT هستند؛ ایجاد خودکار چت ChatGPT یا تبدیل رابط وب آن به API در این نسخه پیاده نشده است.
برای آزمایش CDP، Chrome را با `scripts/start-chrome-debug.ps1` و پروفایل جداگانه اجرا کنید، سپس در React گزینه «بررسی CDP و مشاهده تب‌های مرورگر» را انتخاب کنید.
پشتیبانی از اتصال به سایت‌های ثالث فقط برای صفحات تحت کنترل یا دارای مجوز مناسب است. این برنامه برای صفحه محلی `demo.html` آمادهٔ تست است.

- `GET /api/bridge/diagnose?cdpEndpoint=http://127.0.0.1:9222` سلامت CDP را قبل از اجرای Playwright بررسی می‌کند.
- `scripts/Diagnose-GptApiYar.ps1` وضعیت React، Spring Boot، Chrome CDP و صفحه demo را گزارش می‌دهد.
- `scripts/start-backend.ps1` متغیر `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` را برای جلوگیری از دانلود Firefox/WebKit/Chromium در اجرای Maven تنظیم می‌کند.
- اگر Spring Boot از IntelliJ اجرا می‌شود، در Run Configuration همین متغیر محیطی را جداگانه اضافه کنید.
- در این نسخه اتصال Chrome از طریق CDP به Extension نیاز ندارد و Chrome روزمرهٔ شما به‌طور خودکار متصل نمی‌شود.
- تم روشن، تشخیص CDP و پایداری نمایش خطاها جایگزین وعدهٔ اتصال خودکار به ChatGPT نیست.
'@
    }
    Stage-Change $relative $readme

    # Save this one-file maintainer inside the repository, too.
    $relative = 'scripts\Update-GptApiYar-AllInOne.ps1'
    $self = [System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)
    Stage-Change $relative $self

    # All expected signatures have been validated. Only now begin writing.
    $backupBase = Join-Path (Split-Path -Parent $ProjectPath) '_GptApiYar_Backups'
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $backupBase ("Update-AllInOne-" + $stamp)
    New-Item -Path $backup -ItemType Directory -Force | Out-Null
    $modified = @()
    foreach ($rel in $changes.Keys) {
        $target = Join-Path $ProjectPath $rel
        $oldText = if (Test-Path -LiteralPath $target -PathType Leaf) { [System.IO.File]::ReadAllText($target,[Text.Encoding]::UTF8) } else { $null }
        if ($null -ne $oldText -and $oldText -ceq $changes[$rel]) { continue }
        if ($null -ne $oldText) {
            $backupPath = Join-Path $backup $rel
            $backupDir = Split-Path -Parent $backupPath
            if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
            Copy-Item -LiteralPath $target -Destination $backupPath -Force
        }
        Write-Utf8 $target $changes[$rel]
        $modified += $rel
        Say "Updated $rel" 'Green'
    }
    Write-Utf8 (Join-Path $backup 'changed-paths.txt') ($modified -join [Environment]::NewLine)
    Say "Backup folder: $backup" 'Green'

    $stageArgs = @('add','--') + @($changes.Keys)
    & git.exe @stageArgs
    Assert-Ok 'git add failed'
    & git.exe diff --cached --check
    Assert-Ok 'git diff --check failed'
    Say 'Changes to commit:'
    & git.exe diff --cached --stat

    if ($Build) {
        $env:PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = '1'
        if (Get-Command mvn.cmd -ErrorAction SilentlyContinue) {
            & mvn.cmd -f (Join-Path $ProjectPath 'backend\pom.xml') -q -DskipTests package
            Assert-Ok 'Maven build failed (changes remain available, not yet committed)'
        } else { Say 'Maven missing: backend build skipped.' 'Yellow' }
        if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
            Push-Location (Join-Path $ProjectPath 'frontend')
            try {
                if (Test-Path -LiteralPath 'node_modules') {
                    & npm.cmd run build
                    Assert-Ok 'React build failed (changes remain available, not yet committed)'
                } else { Say 'node_modules missing: React build skipped; run npm install first.' 'Yellow' }
            } finally { Pop-Location }
        } else { Say 'npm missing: React build skipped.' 'Yellow' }
    }

    & git.exe diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        $ident = @(& git.exe var GIT_AUTHOR_IDENT)
        Assert-Ok 'Set git config user.name and user.email first.'
        & git.exe commit -m 'Improve CDP diagnostics, light UI, startup and Git publishing'
        Assert-Ok 'git commit failed'
        Say 'Local commit created.' 'Green'
    } elseif ($LASTEXITCODE -eq 0) {
        Say 'Nothing new to commit; patch was already applied.' 'Green'
    } else { throw 'Git diff failed' }

    if ($Push) {
        $ok = Read-Host 'Type PUSH to publish main to HAminzadeh/GptApiYar'
        if ($ok -cne 'PUSH') { Say 'Push cancelled; local changes are committed.' 'Yellow' }
        else {
            & git.exe push -u origin main
            Assert-Ok 'Git push failed. Review authentication or remote state; no force-push was used.'
            Say 'Published: https://github.com/HAminzadeh/GptApiYar' 'Green'
        }
    } else { Say 'Push skipped. Rerun this script with -Push, or push main manually.' 'Yellow' }
    if ($Start) {
        Say 'Launching backend, React and isolated CDP Chrome...' 'Cyan'
        $launch = Join-Path $ProjectPath 'scripts\start-all.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launch
        Assert-Ok 'start-all.ps1 failed'
    } else { Say 'Restart IntelliJ backend and React Vite to load the changes.' 'Yellow' }
    Say 'Done.' 'Green'
} finally { Pop-Location }
