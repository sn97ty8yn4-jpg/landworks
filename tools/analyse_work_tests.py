"""Analyse measured Godot work trial summaries. Does not invent missing data."""
from __future__ import annotations
import argparse
import csv
from pathlib import Path

SCENARIOS=['flat_empty','flat_400','hill_400','hill_800','lift_250','lift_500','lift_1000','lift_pivot_500','drag_1000','push_1500','roll_1000','push_clay_1500','drag_clay_1000']

def analyse(directory:Path) -> list[dict]:
    results=[]
    for scenario in SCENARIOS:
        typ='excavator' if scenario.startswith(('lift_', 'drag_', 'push_', 'roll_')) else 'tractor'
        path=directory/f'{typ}_{scenario}_summary.csv'
        if not path.exists():
            results.append(dict(scenario=scenario, status='NOT_RUN', note='No measured Godot CSV'))
            continue
        with path.open(newline='') as f:
            record=next(csv.DictReader(f))
        if typ=='tractor':
            flags=[]
            if float(record['peak_kmh'])<0.5: flags.append('DID_NOT_MOVE')
            if float(record['max_hitch_error_m'])>0.4: flags.append('HITCH_STRETCH')
            if int(record['tipped']): flags.append('ROLLOVER')
            if float(record['max_articulation_deg'])>85: flags.append('JACKKNIFE')
            note='; '.join(flags) if flags else 'Completed geometric sanity checks; tuning still required'
        else:
            flags=[]
            if scenario.startswith(('drag_', 'push_', 'roll_')):
                if float(record['object_displacement_m'])<0.25: flags.append('OBJECT_DID_NOT_MOVE')
                if scenario.startswith('roll_') and float(record['object_roll_deg'])<40: flags.append('DRUM_DID_NOT_ROLL')
                note='; '.join(flags) if flags else 'Ground handling completed; uncalibrated soil/contact model'
                results.append({**record, 'scenario': scenario, 'status': 'REVIEW' if flags else 'PRELIM_PASS', 'note': note})
                continue
            if float(record['peak_lift_m'])<0.15: flags.append('LOAD_NOT_LIFTED')
            if float(record['max_slew_deg'])<35: flags.append('INSUFFICIENT_SLEW')
            if float(record['base_travel_m'])<0.7: flags.append('DID_NOT_TRAVEL')
            if int(record['tipping_detected']): flags.append('TIP_EVENT')
            note='; '.join(flags) if flags else 'Completed geometric sanity checks; calibration still required'
        results.append({**record, 'scenario': scenario, 'status': 'REVIEW' if flags else 'PRELIM_PASS', 'note': note})
    return results

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--dir',default='field_test_results')
    args=ap.parse_args()
    directory=Path(args.dir)
    for r in analyse(directory):
        print(f'{r["scenario"]:<13} {r["status"]:<12} {r["note"]}')

if __name__=='__main__':
    main()
