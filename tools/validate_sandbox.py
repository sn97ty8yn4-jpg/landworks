"""Validate telemetry from the SAME interactive sandbox used by players.

Running the stand-alone excavator/tractor labs is not enough for sandbox CI.
The headless smoke script must demonstrate both machine bodies and the hitch.
"""
import argparse
import csv
import math
from pathlib import Path

COLUMNS = ("tractor_travel_m", "excavator_travel_m", "crate_travel_m",
           "boom_change_deg", "max_hitch_error_m", "max_chassis_tilt_deg",
           "peak_hydraulic_pressure_mpa", "test_duration_s")


def validate(root: Path) -> list[str]:
    summary = root / "sandbox_summary.csv"
    sample = root / "sandbox_samples.csv"
    if not summary.exists() or not sample.exists():
        return ["missing live sandbox telemetry"]
    with summary.open(newline="") as f:
        rows = list(csv.DictReader(f))
    with sample.open(newline="") as f:
        samples = list(csv.DictReader(f))
    if len(rows) != 1 or len(samples) < 60:
        return ["missing or truncated sandbox physics replay"]
    values = {}
    for key in COLUMNS:
        try:
            values[key] = float(rows[0][key])
        except (KeyError, ValueError, TypeError):
            return [f"bad or missing metric: {key}"]
        if not math.isfinite(values[key]):
            return [f"nonfinite metric: {key}"]
    errors = []
    if values["tractor_travel_m"] < 2.0:
        errors.append("tractor did not drive")
    if values["excavator_travel_m"] < 0.5:
        errors.append("excavator crawler did not travel")
    if values["boom_change_deg"] < 4.0:
        errors.append("physics boom did not move")
    if values["max_hitch_error_m"] > 0.3:
        errors.append("trailer hitch detached or stretched")
    if values["max_chassis_tilt_deg"] > 20:
        errors.append("excavator tipped over")
    if values["peak_hydraulic_pressure_mpa"] > 29.41:
        errors.append("hydraulic relief pressure exceeded")
    if values["test_duration_s"] < 20.9:
        errors.append("sandbox terminated prematurely")
    return errors


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--dir", type=Path, required=True)
    a = p.parse_args()
    problems = validate(a.dir)
    if problems:
        print("SANDBOX_FAIL: " + "; ".join(problems))
        return 1
    with (a.dir / "sandbox_summary.csv").open(newline="") as f:
        print("SANDBOX_PASS:", next(csv.DictReader(f)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
