<#
GptApiYar CDP repair / launcher for Windows PowerShell 5.1+.
- Does not change your normal Chrome profile.
- Does not install extensions, download browsers, run Maven, commit or push.
- Backs up and replaces only scripts/start-chrome-debug.ps1 in the existing project.
- Verifies the actual HTTP CDP endpoint before declaring success.
Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "...\Fix-GptApiYar-CDP.ps1"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "...\Fix-GptApiYar-CDP.ps1" -PageUrl "http://127.0.0.1:8787/demo.html"
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = 'D:\ChatGPT_Projects\GptApiYar',
    [ValidateRange(1024,65535)][int]$Port = 9222,
    [string]$PageUrl = 'http://127.0.0.1:8787/demo.html',
    [switch]$SkipInstall
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Say([string]$Message, [string]$Color = 'Gray') {
    Write-Host ('[GptApiYar-CDP] ' + $Message) -ForegroundColor $Color
}
function Get-CdpInfo([int]$CdpPort) {
    $req = $null; $resp = $null; $reader = $null
    try {
        $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create("http://127.0.0.1:$CdpPort/json/version")
        $req.Proxy = $null  # Do not send loopback requests through corporate/system proxy.
        $req.Timeout = 1800
        $req.ReadWriteTimeout = 1800
        $resp = $req.GetResponse()
        if ([int]$resp.StatusCode -ne 200) { return $null }
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $data = $reader.ReadToEnd() | ConvertFrom-Json
        if (-not $data.Browser -or -not $data.webSocketDebuggerUrl) { return $null }
        return $data
    } catch { return $null }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($resp) { $resp.Dispose() }
    }
}
function Get-Tabs([int]$CdpPort) {
    $resp = $null; $reader = $null
    try {
        $req = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create("http://127.0.0.1:$CdpPort/json/list")
        $req.Proxy = $null
        $req.Timeout = 2200
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $parsed = ConvertFrom-Json -InputObject ($reader.ReadToEnd())
        return @($parsed | Where-Object { $_.type -eq 'page' } | Select-Object -ExpandProperty url)
    } catch { return @() }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($resp) { $resp.Dispose() }
    }
}
function Find-Chrome {
    $candidates = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not [string]::IsNullOrWhiteSpace($base)) {
            $candidates += (Join-Path $base 'Google\Chrome\Application\chrome.exe')
        }
    }
    foreach ($p in $candidates) { if (Test-Path -LiteralPath $p -PathType Leaf) { return $p } }
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
    )
    foreach ($rp in $regPaths) {
        try {
            $p = (Get-Item -LiteralPath $rp -ErrorAction Stop).GetValue('')
            if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return $p }
        } catch {}
    }
    throw 'chrome.exe not found. Install Google Chrome or adjust Find-Chrome in this script.'
}
function Get-IsolatedChromeProcesses([string]$ProfileDir) {
    try {
        return @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -and
                $_.CommandLine.IndexOf('--user-data-dir', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $_.CommandLine.IndexOf($ProfileDir, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    } catch {
        Say 'Could not inspect Chrome process command lines. Close only GptApiYar isolated Chrome windows manually if restart is needed.' 'Yellow'
        return @()
    }
}
function Get-PortOwner([int]$CdpPort) {
    try {
        $listeners = @(Get-NetTCPConnection -LocalPort $CdpPort -State Listen -ErrorAction Stop)
        foreach ($item in $listeners) {
            $ownerId = [int]$item.OwningProcess
            $proc = Get-Process -Id $ownerId -ErrorAction SilentlyContinue
            if ($proc) { return "PID $ownerId ($($proc.ProcessName))" }
            return "PID $ownerId"
        }
    } catch {}
    return $null
}

$targetLauncher = Join-Path $ProjectRoot 'scripts\start-chrome-debug.ps1'
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'backend') -PathType Container) -or
    -not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'frontend') -PathType Container)) {
    throw "This is not the expected project root: $ProjectRoot"
}
if ($PageUrl -notmatch '^https?://') { throw 'PageUrl must begin with http:// or https://.' }

# Install the improved launcher for all future runs of scripts/start-all.ps1.
if (-not $SkipInstall) {
    $self = [System.IO.Path]::GetFullPath($PSCommandPath)
    $targetFull = [System.IO.Path]::GetFullPath($targetLauncher)
    if (-not [string]::Equals($self, $targetFull, [StringComparison]::OrdinalIgnoreCase)) {
        $backupFolder = Join-Path (Split-Path -Parent $ProjectRoot) '_GptApiYar_Backups\CDP'
        New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
        if (Test-Path -LiteralPath $targetLauncher) {
            $oldHash = (Get-FileHash -LiteralPath $targetLauncher -Algorithm SHA256).Hash
            $newHash = (Get-FileHash -LiteralPath $self -Algorithm SHA256).Hash
            if ($oldHash -ne $newHash) {
                $backup = Join-Path $backupFolder ('start-chrome-debug-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.ps1')
                Copy-Item -LiteralPath $targetLauncher -Destination $backup -ErrorAction Stop
                Copy-Item -LiteralPath $self -Destination $targetLauncher -Force
                Say "Updated launcher. Backup: $backup" 'Green'
            } else { Say 'Launcher already up to date.' 'Green' }
        } else {
            Copy-Item -LiteralPath $self -Destination $targetLauncher
            Say 'Installed new launcher into project/scripts.' 'Green'
        }
    }
}

$chromeProfileDir = Join-Path $env:LOCALAPPDATA 'GptApiYar\ChromeProfile'
$defaultChromeProfile = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
if ([string]::Equals($chromeProfileDir, $defaultChromeProfile, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Refusing to enable CDP on the normal Chrome profile.'
}
New-Item -ItemType Directory -Path $chromeProfileDir -Force | Out-Null
Say "CDP endpoint: http://127.0.0.1:$Port"
Say "Isolated profile: $chromeProfileDir"

$info = Get-CdpInfo $Port
if ($info) {
    Say "CDP already running: $($info.Browser)" 'Green'
} else {
    $owner = Get-PortOwner $Port
    if ($owner) {
        throw "Port $Port is already listening ($owner), but is NOT a valid Chrome CDP endpoint. Stop the other service or choose a free port in both Chrome and React."
    }
    $isolated = @(Get-IsolatedChromeProcesses $chromeProfileDir)
    if ($isolated.Count -gt 0) {
        Say "Found $($isolated.Count) already-running Chrome process(es) using this isolated profile, but CDP is not available." 'Yellow'
        Say 'Likely cause: Chrome was previously started without remote-debugging, and new launch flags were ignored.' 'Yellow'
        $approval = Read-Host 'Type RESTART to close ONLY GptApiYar isolated-profile Chrome processes (unsaved tabs may be lost); anything else cancels'
        if ($approval -cne 'RESTART') { throw 'Cancelled safely. Close the GptApiYar isolated Chrome window and run again.' }
        foreach ($p in $isolated) {
            Say "Stopping isolated-profile Chrome PID $($p.ProcessId)"
            Stop-Process -Id ([int]$p.ProcessId) -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
        $remaining = @(Get-IsolatedChromeProcesses $chromeProfileDir)
        if ($remaining.Count -gt 0) {
            throw 'Some GptApiYar isolated Chrome processes are still running. Close those windows manually; never close the regular Chrome just to fix CDP.'
        }
    }
    $chrome = Find-Chrome
    Say "Chrome executable: $chrome"
    Say 'Launching a separate Chrome instance with remote debugging enabled...'
    $arguments = @(
        '--remote-debugging-address=127.0.0.1',
        "--remote-debugging-port=$Port",
        ('--user-data-dir="' + $chromeProfileDir + '"'),
        '--no-first-run',
        '--no-default-browser-check',
        ('"' + $PageUrl + '"')
    )
    Start-Process -FilePath $chrome -ArgumentList $arguments -ErrorAction Stop | Out-Null
    $info = $null
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 700
        $info = Get-CdpInfo $Port
        if ($info) { break }
    }
    if (-not $info) {
        $owner = Get-PortOwner $Port
        $extra = if ($owner) { "Port owner: $owner." } else { 'No process is listening on the CDP port.' }
        throw "Chrome launch did not produce a CDP endpoint on 127.0.0.1:$Port. $extra Check chrome://policy for RemoteDebuggingAllowed, security software, and whether Chrome uses this isolated profile."
    }
    Say 'Chrome launched successfully with CDP.' 'Green'
}

Say "Browser: $($info.Browser)" 'Green'
Say 'CDP validation returned a WebSocket debugger address.' 'Green'
$tabs = @(Get-Tabs $Port)
if ($tabs.Count -gt 0) {
    Say 'Tabs exposed by this CDP instance:' 'Cyan'
    $tabs | Select-Object -First 10 | ForEach-Object { Write-Host ('  ' + $_) }
} else { Say 'No page tabs yet; open the demo page inside the isolated Chrome window.' 'Yellow' }
Say 'In React, click "Check CDP", select Local Demo, then click Connect.' 'Cyan'
Say "Quick test: curl.exe --noproxy '*' http://127.0.0.1:$Port/json/version"
Say 'This launcher does NOT automate or extract conversations from ChatGPT.'
