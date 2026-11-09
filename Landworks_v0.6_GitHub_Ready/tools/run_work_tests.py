"""Run all real 3D dynamics tests with a local Godot 4.6 executable.

No vendor libraries required: the tests use the independently built baseline
tractor and Godot's rigid bodies and joints, not GEVP/KV installations.
"""
from __future__ import annotations
import argparse
import csv
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parent.parent
CASE_SCENES={
    'flat_empty':'res://landworks/scenes/tractor_work_lab.tscn',
    'flat_400':'res://landworks/scenes/tractor_work_lab.tscn',
    'hill_400':'res://landworks/scenes/tractor_work_lab.tscn',
    'hill_800':'res://landworks/scenes/tractor_work_lab.tscn',
    'lift_250':'res://landworks/scenes/excavator_work_lab.tscn',
    'lift_500':'res://landworks/scenes/excavator_work_lab.tscn',
    'lift_1000':'res://landworks/scenes/excavator_work_lab.tscn',
}


def validate_sample(path:Path, case:str) -> None:
    if not path.exists():
        raise RuntimeError(f'Missing measured telemetry for {case}: {path}')
    with path.open(newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)<80:
        raise RuntimeError(f'Incomplete physics samples for {case}: {len(rows)}')
    last=float(rows[-1]['time_s'])
    if last < (31.9 if case.startswith('lift_') else 27.9):
        raise RuntimeError(f'Test {case} ended early at {last:.2f}s')


def main() -> int:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--godot',default=os.environ.get('GODOT_EXE','godot'),help='Path to Godot 4.6 editor or console executable')
    ap.add_argument('--out',default=str(ROOT/'field_test_results'))
    ap.add_argument('--case',choices=['all']+list(CASE_SCENES),default='all')
    a=ap.parse_args()
    exe=shutil.which(a.godot) or (str(Path(a.godot).resolve()) if Path(a.godot).is_file() else None)
    if exe is None:
        print('Cannot run physical test: Godot 4.6 executable not found. Specify --godot PATH.',file=sys.stderr)
        return 2
    output=Path(a.out).resolve()
    output.mkdir(parents=True,exist_ok=True)
    cases= list(CASE_SCENES) if a.case=='all' else [a.case]
    for case in cases:
        scene=CASE_SCENES[case]
        prefix='excavator' if case.startswith('lift_') else 'tractor'
        summary=output/f'{prefix}_{case}_summary.csv'
        samples=output/f'{prefix}_{case}_samples.csv'
        for file in [summary,samples]:
            file.unlink(missing_ok=True)
        cmd=[exe,'--headless','--path',str(ROOT),scene,'--',f'--scenario={case}',f'--output-dir={output}','--batch']
        print('RUNNING',case,flush=True)
        try:
            result=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,timeout=240)
        except subprocess.TimeoutExpired:
            print('TIMEOUT:',case,file=sys.stderr)
            return 4
        (output/f'{case}_godot.log').write_text(result.stdout+'\n---stderr---\n'+result.stderr,encoding='utf-8')
        if result.returncode!=0:
            print('Godot FAILED',case,'exit',result.returncode, '\n'+result.stderr[-1800:], file=sys.stderr)
            return 5
        validate_sample(samples,case)
        if not summary.exists():
            print('Summary not produced for',case,file=sys.stderr)
            return 6
        print('MEASURED:',case,summary,flush=True)
    print('All requested cases completed; see CSV and Godot logs in:',output)
    return 0

if __name__=='__main__':
    raise SystemExit(main())
