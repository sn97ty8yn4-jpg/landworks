param([string]$Godot = (Join-Path $PSScriptRoot 'runtime/Godot_v4.6.3-stable_win64.exe'))
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $Godot)) { throw 'Specify -Godot with a Godot 4.6.3 executable.' }
$outputDirectory = Join-Path $PSScriptRoot 'validation/integration'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'validation/.gdignore') -Value ''
$cases = [ordered]@{
    detailed_skin_smoke = 'DETAILED_SKIN PASS'
    detailed_cab_smoke = 'DETAILED_CAB PASS'
    rigged_model_smoke = 'RIGGED_MODEL PASS'
    coupling_smoke = 'COUPLING PASS'
    reset_smoke = 'RESET PASS'
    machine_feel_smoke = 'MACHINE_FEEL PASS'
    machine_controls_smoke = 'MACHINE_CONTROLS PASS'
    material_mechanics_smoke = 'MATERIAL_MECHANICS PASS'
    slope_stability_smoke = 'SLOPE_STABILITY PASS'
    playable_dig_regression = 'PLAYABLE_DIG PASS'
    unpowered_soil_smoke = 'UNPOWERED_SOIL PASS'
    machine_visual_smoke = 'MACHINE_VISUAL PASS'
    earthworks_smoke = 'EARTHWORKS PASS'
    below_grade_smoke = 'BELOW_GRADE PASS'
    work_pad_access_smoke = 'WORK_PAD_ACCESS PASS'
    earthwork_machine_smoke = 'PHYSICAL_DIG PASS'
    hydraulic_smoke = 'HYDRAULIC_SMOKE PASS'
    sandbox_hook_smoke = 'SANDBOX_HOOK_PASS'
}
function Invoke-CheckedGodot([string]$Name, [string[]]$EngineArguments, [string]$Expected) {
    $log = Join-Path $outputDirectory ($Name + '.log')
    $arguments = @('--headless', '--path', ('"' + $PSScriptRoot + '"'),
        '--log-file', ('"' + $log + '"')) + $EngineArguments
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -PassThru -WindowStyle Hidden
    if (!$process.WaitForExit(120000)) {
        $process.Kill()
        throw "$Name exceeded the 120 second test limit. See $log"
    }
    $process.Refresh()
    $content = Get-Content -LiteralPath $log -Raw
    if ($process.ExitCode -ne 0 -or $content -match 'SCRIPT ERROR:|ERROR:|Parse Error:') {
        throw "$Name failed. See $log"
    }
    if ($Expected -and !$content.Contains($Expected)) { throw "$Name did not report success. See $log" }
    Write-Output "PASS $Name"
}
Invoke-CheckedGodot 'import' @('--editor', '--import', '--quit') ''
foreach ($case in $cases.GetEnumerator()) {
    Invoke-CheckedGodot $case.Key @('--script', "res://landworks/scripts/$($case.Key).gd") $case.Value
}
Write-Output "All integration checks passed. Logs: $outputDirectory"
