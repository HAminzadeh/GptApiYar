param(
    [switch]$Push
)
$ErrorActionPreference='Stop'
$repoUrl='https://github.com/HAminzadeh/GptApiYar.git'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'Git not found in PATH. Install Git for Windows first.' }
Push-Location $root
try {
    if (-not (Test-Path -LiteralPath '.git' -PathType Container)) {
        & git.exe init -b main
        if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    }
    $actualRoot = (& git.exe rev-parse --show-toplevel).Trim().Replace('/', '\')
    if (-not [string]::Equals($actualRoot.TrimEnd('\'), $root.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Git repository root differs from project path: $actualRoot"
    }
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
    $branch = (& git.exe branch --show-current).Trim()
    if (-not $branch) { $branch = 'main' }
    if ($branch -ne 'main') { throw "Switch to main before publishing; current branch: $branch" }

    # This is the intended initial public repository; never silently overwrite upstream.
    $upstream = (& git.exe ls-remote --heads origin main 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot contact GitHub. Check network/authentication, then retry.' }
    if ($upstream -and -not (& git.exe rev-parse --verify refs/remotes/origin/main 2>$null)) {
        Write-Host '[WARN] Upstream main already has commits. Run git fetch origin main, inspect history and reconcile locally.' -ForegroundColor Yellow
        throw 'Upstream is not empty; aborting to avoid non-fast-forward or unrelated-history push.'
    }

    & git.exe add -- backend frontend scripts README-fa.md .gitignore Install-GptApiYar.ps1 Publish-GptApiYar.ps1
    if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
    # Refuse commonly sensitive files even if a previous commit already tracks them.
    $staged = @(& git.exe diff --cached --name-only)
    $forbidden = @($staged | Where-Object {
        $_ -match '(^|/)(\.env($|\.)|application-local\.ya?ml$|credentials\.|secrets?\.|ChromeProfile/)' -or
        $_ -match '\.(pem|p12|pfx|key)$'
    })
    if ($forbidden.Count -gt 0) {
        throw ("Possible secrets were staged; unstage them before retrying: " + ($forbidden -join ', '))
    }
    & git.exe diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw 'Whitespace/conflict issues in staged files' }
    Write-Host '[REVIEW] Files staged for the first commit:' -ForegroundColor Cyan
    & git.exe diff --cached --stat
    & git.exe status --short
    $name = (& git.exe var GIT_AUTHOR_IDENT 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $name) { throw 'Git identity is not configured: git config --global user.name and user.email' }
    $answer=Read-Host 'Type COMMIT to create the local commit after reviewing the file list'
    if ($answer -cne 'COMMIT') { Write-Host 'Cancelled. Staged files remain staged.' -ForegroundColor Yellow; exit 0 }
    & git.exe diff --cached --quiet
    if ($LASTEXITCODE -eq 1) {
        & git.exe commit -m 'Initial GptApiYar browser bridge: light UI and CDP diagnostics'
        if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
    } elseif ($LASTEXITCODE -ne 0) { throw 'Unable to inspect staged changes' }
    else { Write-Host 'No new changes to commit.' }
    Write-Host 'Local commit ready.' -ForegroundColor Green
    if ($Push) {
        $confirmation=Read-Host "Type PUSH to send main to $repoUrl"
        if ($confirmation -cne 'PUSH') { Write-Host 'Push cancelled.' -ForegroundColor Yellow; exit 0 }
        & git.exe push -u origin main
        if ($LASTEXITCODE -ne 0) { throw 'git push failed. Git Credential Manager/login may be needed.' }
        Write-Host 'Published: https://github.com/HAminzadeh/GptApiYar' -ForegroundColor Green
    } else {
        Write-Host 'Push has NOT been executed. To publish: .\scripts\Publish-GptApiYar.ps1 -Push' -ForegroundColor Cyan
    }
} finally { Pop-Location }
