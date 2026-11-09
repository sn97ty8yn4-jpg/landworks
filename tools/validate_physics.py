"""Enforce regression limits on ACTUAL Godot physics telemetry, never surrogate CSVs.

Limits are provisional acceptance ranges, not Kubota OEM specifications.
Nonfinite or missing data is a failure. A deliberately overloaded 1000 kg
excavator case is expected to remain on the ground in this test configuration.
"""
from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path
import sys

TRACTOR = ("flat_empty", "flat_400", "hill_400", "hill_800")
EXCAVATOR = ("lift_250", "lift_500", "lift_1000", "lift_pivot_500")
SUMMARY_FIELDS = {
    "tractor": ("peak_kmh", "forward_distance_m", "brake_displacement_m",
                "max_articulation_deg", "max_tilt_deg", "max_hitch_error_m", "tipped"),
    "excavator": ("peak_lift_m", "hold_drift_m", "base_travel_m", "max_slew_deg",
                  "max_chassis_tilt_deg", "tipping_detected", "max_base_yaw_deg", 
                  "base_planar_displacement_m"),
}
FAILURES = "FAIL"


def read_summary(path: Path, typ: str) -> dict[str, float]:
    if not path.is_file():
        raise ValueError(f"Missing real Godot summary: {path}")
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise ValueError(f"Expected one real summary row in {path}, got {len(rows)}")
    row = rows[0]
    parsed = {}
    for field in SUMMARY_FIELDS[typ]:
        try:
            value = float(row[field])
        except (KeyError, ValueError, TypeError) as exc:
            raise ValueError(f"Missing/bad {field} in {path}") from exc
        if not math.isfinite(value):
            raise ValueError(f"Nonfinite {field} in {path}: {value}")
        parsed[field] = value
    return parsed


def check_case(case: str, r: dict[str, float]) -> list[str]:
    problems: list[str] = []
    if case.startswith("lift_"):
        if r["max_chassis_tilt_deg"] > 18 or r["tipping_detected"] > 0:
            problems.append("chassis instability")
        if r["hold_drift_m"] > 0.20:
            problems.append("load drifts during HOLD phase")
        if case == "lift_1000":
            # At the CURRENT long-reach prototype geometry 1000 kg stalls.
            # The test driver must not slew or drive with a grounded load.
            # This is NOT a Kubota rated-load claim.
            if r["peak_lift_m"] > 0.25:
                problems.append("1000 kg reference-stall case unexpectedly lifted")
            if r["max_slew_deg"] > 15:
                problems.append("test operator slewed a failed lift")
            if r["base_planar_displacement_m"] > 0.5:
                problems.append("test operator travelled with a grounded load")
            if r["max_base_yaw_deg"] > 15:
                problems.append("grounded-load chassis rotated excessively")
        else:
            if not (0.8 <= r["peak_lift_m"] <= 4.5):
                problems.append("250/500 kg load not lifted to plausible test height")
            if r["max_slew_deg"] < 45 or r["max_slew_deg"] > 105:
                problems.append("slew outside 45-105 degrees")
            if case == "lift_pivot_500":
                if r["base_planar_displacement_m"] > 0.9:
                    problems.append("neutral turn drifted more than 0.9 m")
                if r["max_base_yaw_deg"] < 35:
                    problems.append("opposed crawler commands did not produce pivot turn")
            elif r["base_travel_m"] < 1 or r["base_travel_m"] > 15:
                problems.append("crawler straight distance outside 1-15 m")
            if case != "lift_pivot_500" and r["max_base_yaw_deg"] > 35:
                problems.append("uncommanded crawler yaw greater than 35 degrees")
    else:
        if not 2 <= r["peak_kmh"] <= 17:
            problems.append("tractor speed outside 2-17 km/h")
        if r["forward_distance_m"] < 3:
            problems.append("tractor barely moved")
        if not 0.05 <= r["brake_displacement_m"] <= 15:
            problems.append("braking distance outside sanity range")
        if r["max_hitch_error_m"] > 0.25:
            problems.append("physical tow hitch stretched")
        if r["max_articulation_deg"] > 60 or r["tipped"] > 0:
            problems.append("trailer jackknife or rollover")
        if r["max_tilt_deg"] > 20:
            problems.append("excessive tractor/trailer tilt")
    return problems


def validate(directory: Path) -> list[tuple[str, list[str]]]:
    results = []
    for case in (*TRACTOR, *EXCAVATOR):
        typ = "excavator" if case.startswith("lift_") else "tractor"
        values = read_summary(directory / f"{typ}_{case}_summary.csv", typ)
        results.append((case, check_case(case, values)))
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", type=Path, default=Path("field_test_results"))
    args = parser.parse_args()
    try:
        cases = validate(args.dir)
    except ValueError as exc:
        print(f"LANDWORKS_PHYSICS_INVALID: {exc}", file=sys.stderr)
        return 2
    for case, failures in cases:
        print(f"{case:13} {'FAIL' if failures else 'PASS':5} " + "; ".join(failures))
    if any(problems for _, problems in cases):
        return 1
    print("All 8 measured behaviour gates passed (provisional thresholds; not OEM validation)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
