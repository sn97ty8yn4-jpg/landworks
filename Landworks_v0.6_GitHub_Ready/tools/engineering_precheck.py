"""Independent static-load and simplified towing checks, not Godot physics results.

Physically meaningful screening: geometry, static gravitational boom torque,
6-degree grade requirement and traction cap. Do NOT use as a run-time verdict.
"""
from __future__ import annotations
import argparse
import csv
import math
from pathlib import Path

G = 9.81
BOOM_L, STICK_L, BUCKET_L = 3.0, 2.32, 0.82
BOOM_KG, STICK_KG, BUCKET_KG = 650, 400, 210
TRACTOR_KG, TRAILER_EMPTY_KG = 573, 320
BOOM_TORQUE_NM = 75_000.0  # assumed, not manufacturer's hydraulic specification


def boom_torque(payload_kg: float, boom_deg: float = math.degrees(0.24),
                stick_relative_deg: float = math.degrees(-0.72),
                bucket_relative_deg: float = math.degrees(-0.24)) -> float:
    a = math.radians(boom_deg)
    b = a + math.radians(stick_relative_deg)
    c = b + math.radians(bucket_relative_deg)
    x_boom = BOOM_L / 2 * math.cos(a)
    x_stick = BOOM_L * math.cos(a) + STICK_L / 2 * math.cos(b)
    x_bucket = BOOM_L * math.cos(a) + STICK_L * math.cos(b) + BUCKET_L / 2 * math.cos(c)
    x_hook = BOOM_L * math.cos(a) + STICK_L * math.cos(b) + BUCKET_L * math.cos(c)
    return G * (BOOM_KG * x_boom + STICK_KG * x_stick + BUCKET_KG * x_bucket
                + payload_kg * x_hook)


def towing_forces(payload_kg: float, slope_deg: float) -> dict:
    trailer_mass = TRAILER_EMPTY_KG + payload_kg
    total_mass = TRACTOR_KG + trailer_mass
    angle = math.radians(slope_deg)
    gravity = total_mass * G * math.sin(angle)
    rolling = 0.03 * total_mass * G * math.cos(angle)
    required = gravity + rolling
    # Approximate tongue transfer (10%) and 0.80 effective turf tyre grip.
    traction = 0.80 * (TRACTOR_KG + 0.10 * trailer_mass) * G * math.cos(angle)
    driving_force = min(4250.0 * 0.80, traction)
    return dict(slope_deg=slope_deg, trailer_payload_kg=payload_kg,
                gross_kg=total_mass, grade_N=gravity, rolling_N=rolling,
                resistance_N=required, traction_ceiling_N=traction,
                requested_drive_N=driving_force,
                tractive_margin_N=driving_force-required)


def run(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    with (output / 'engineering_lift_precheck.csv').open('w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['payload_kg', 'static_boom_torque_kNm', 'proxy_limit_kNm', 'static_margin_kNm', 'verdict'])
        for kg in (250, 500, 1000):
            torque = boom_torque(kg) / 1000
            w.writerow([kg, round(torque, 2), BOOM_TORQUE_NM / 1000,
                        round(BOOM_TORQUE_NM/1000-torque, 2),
                        'STATIC_ONLY_BELOW_ASSUMED_LIMIT' if torque < BOOM_TORQUE_NM / 1000
                        else 'STATIC_ONLY_ABOVE_ASSUMED_LIMIT'])
    with (output / 'engineering_tow_precheck.csv').open('w', newline='') as f:
        examples = [towing_forces(p, s) for p, s in [(0, 0), (400, 0), (400, 6), (800, 6)]]
        w = csv.DictWriter(f, fieldnames=list(examples[0]))
        w.writeheader()
        for d in examples:
            w.writerow({k: round(v, 2) for k,v in d.items()})
    print('Independent engineering checks (NOT simulated Godot runtime measurements):')
    for kg in (250, 500, 1000):
        print('Boom static gravity moment at initial arm extension: %4d kg: %.1f kNm / 75 kNm assumed cap'
              % (kg, boom_torque(kg)/1000))
    for p,s in [(0,0),(400,0),(400,6),(800,6)]:
        f=towing_forces(p,s)
        print('Tractor trailer payload %4d kg, slope %2d°: grade+rolling %.0f N; available drive %.0f N'
              % (p,s,f['resistance_N'],f['requested_drive_N']))
    print('CSV estimates:',output)

if __name__ == '__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',default='engineering_prechecks')
    args=ap.parse_args()
    run(Path(args.out).resolve())
