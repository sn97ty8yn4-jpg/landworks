$ErrorActionPreference = 'Stop'
$repository = 'https://github.com/sn97ty8yn4-jpg/landworks.git'
$source = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = Join-Path $env:USERPROFILE 'Documents\landworks-github'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was not found. Install Git for Windows or GitHub Desktop, then use START_HERE_WINDOWS.md.'
}
if (-not (Test-Path (Join-Path $source 'project.godot'))) {
    throw 'project.godot was not found beside this script. Extract the entire ZIP first.'
}
if (Test-Path (Join-Path $target '.git')) {
    Write-Host "Using existing checkout: $target"
    & git -C $target pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw 'git pull failed: resolve the checkout first.' }
} elseif (Test-Path $target) {
    throw "The destination exists but isn't a git checkout: $target. Rename it first."
} else {
    & git clone $repository $target
    if ($LASTEXITCODE -ne 0) { throw 'git clone failed. Check internet connection and repository access.' }
}
Write-Host 'Copying Godot project source into GitHub checkout...'
& robocopy $source $target /E /XD '.git' '.godot' '__pycache__' 'field_test_results' /XF '*.pyc' '*.import' | Out-Host
if ($LASTEXITCODE -gt 7) { throw "robocopy failed (exit $LASTEXITCODE)" }
& git -C $target add -A
if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
& git -C $target diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host 'No new files; already up to date.'
} else {
    & git -C $target commit -m 'Import Landworks v0.6 Godot machinery prototype and CI configuration'
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed. Ensure Git user.name and user.email are configured.' }
    & git -C $target push origin main
    if ($LASTEXITCODE -ne 0) { throw 'git push failed. Sign in to GitHub using Git Credential Manager or GitHub Desktop.' }
}
Write-Host 'Repository updated. View GitHub Actions:'
Write-Host 'https://github.com/sn97ty8yn4-jpg/landworks/actions'
