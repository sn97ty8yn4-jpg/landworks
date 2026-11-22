# Stamps the build into landworks/build_stamp.txt.
#
# Only an EXPORTED copy needs this: run from a checkout, the game reads the
# commit straight out of .git, which cannot go stale. Run this immediately
# before an export so the packaged game can still name the build it came from.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Push-Location $root
try {
    $commit = (& git rev-parse --short=7 HEAD).Trim()
    $date = (& git log -1 --format=%cs).Trim()
    $dirty = (& git status --porcelain)
    if ($dirty) {
        Write-Warning 'Uncommitted changes: the stamp will name a commit that is not what you are packaging.'
    }
    $stamp = Join-Path $root 'landworks/build_stamp.txt'
    Set-Content -LiteralPath $stamp -Encoding utf8 -Value @(
        "commit=$commit",
        "date=$date")
    Write-Host "Stamped $stamp with $commit ($date)"
} finally {
    Pop-Location
}
