#!/usr/bin/env python3
"""Read real Godot-output benchmark summary and compare engines (never invent results)."""
import argparse
import csv
import math
from pathlib import Path

FIELDS = ["max_speed_kmh", "accel_path_m", "brake_path_m", "turn_yaw_deg", "max_roll_deg"]


def load_results(path: Path):
    if not path.is_file():
        raise FileNotFoundError(f"Godot data not found at {path}. Run the PhysicsComparisonLab scene first.")
    with path.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    results = {}
    for row in rows:
        name = row.get("engine")
        if name not in ("BASELINE", "KV", "GEVP"):
            raise ValueError("Unknown engine in recorded Godot output")
        if name in results:
            raise ValueError(f"Duplicated engine: {name}")
        values = {k: float(row[k]) for k in FIELDS}
        if any(not math.isfinite(v) for v in values.values()):
            raise ValueError("Non-finite physics data; possible solver instability")
        results[name] = values
    return results


def report(results: dict) -> str:
    out = ["# Landworks tractor physics — recorded test comparison", "",
           "These readings came from the Godot body-state CSV. They are not manufacturer calibration data.", "",
           "| Parameter | Legacy | KV Vehicle | Easy Vehicle Physics |",
           "| --- | ---: | ---: | ---: |"]
    names = ["BASELINE", "KV", "GEVP"]
    captions = {"max_speed_kmh": ("Peak speed (km/h)", "1f"),
                "accel_path_m": ("Path during acceleration (m)", "1f"),
                "brake_path_m": ("Path during braking (m)", "1f"),
                "turn_yaw_deg": ("Yaw change during turn (deg)", "1f"),
                "max_roll_deg": ("Peak roll during turn (deg)", "1f")}
    for field, (caption,fmt) in captions.items():
        vals = []
        for name in names:
            vals.append(format(results[name][field], fmt) if name in results else "Not run")
        out.append(f"| {caption} | {' | '.join(vals)} |")
    missing = [n for n in names if n not in results]
    if missing:
        out.append(f"\n**INCOMPLETE:** Missing actual benchmark outputs for {', '.join(missing)}. No ranking is supported.")
    else:
        out.append("\n**All three engines recorded.** Interpret braking distance and turn response against repeatability, wheel slip and actual B7100 HST tests before choosing a winner.")
    out.append("\n**Limits:** Single flat grass course; different default aids/gearing; no towing or HST modelling; no suspension stroke or tyre-pressure calibration. More trials are required.")
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("summary", type=Path, help="Path to Godot's landworks_comparison_summary.csv")
    parser.add_argument("--out", type=Path, default=Path("landworks_tractor_comparison.md"))
    args = parser.parse_args()
    data = load_results(args.summary)
    args.out.write_text(report(data), encoding="utf-8")
    print("Read", len(data), "actual engine results. Wrote", args.out)
    print(report(data))


if __name__ == "__main__":
    main()
