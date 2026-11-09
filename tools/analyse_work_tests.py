"""Analyse measured Godot work trial summaries. Does not invent missing data."""
from __future__ import annotations
import argparse
import csv
from pathlib import Path

SCENARIOS=['flat_empty','flat_400','hill_400','hill_800','lift_250','lift_500','lift_1000']

def analyse(directory:Path) -> list[dict]:
    results=[]
    for scenario in SCENARIOS:
        typ='excavator' if scenario.startswith('lift_') else 'tractor'
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
