import importlib.util
import math
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("physics_acceptance", ROOT / "tools/validate_physics.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class PhysicsAcceptanceTests(unittest.TestCase):
    def test_nominal_excavator_stable_load(self):
        good = {"peak_lift_m": 2.4, "hold_drift_m": 0.01,
                "base_travel_m": 2.5, "max_slew_deg": 68.8,
                "max_chassis_tilt_deg": 4, "tipping_detected": 0,
                "max_base_yaw_deg": 2, "base_planar_displacement_m": 3}
        self.assertEqual(gate.check_case("lift_500", good), [])
        self.assertTrue(gate.check_case("lift_1000", good))

    def test_expected_overload_stall(self):
        r = {"peak_lift_m": 0.0, "hold_drift_m": 0.0,
             "base_travel_m": 0.0, "max_slew_deg": 0.0,
             "max_chassis_tilt_deg": 0, "tipping_detected": 0,
             "max_base_yaw_deg": 0, "base_planar_displacement_m": 0}
        self.assertEqual(gate.check_case("lift_1000", r), [])

    def test_grounded_overload_must_not_slew_or_travel(self):
        r = {"peak_lift_m": 0.0, "hold_drift_m": 0.01,
             "base_travel_m": 0.0, "base_planar_displacement_m": 0.0,
             "max_slew_deg": 0.0, "max_base_yaw_deg": 0.0,
             "max_chassis_tilt_deg": 0.0, "tipping_detected": 0}
        self.assertEqual(gate.check_case("lift_1000", r), [])
        r["base_planar_displacement_m"] = 1.0
        r["max_slew_deg"] = 69
        problems = gate.check_case("lift_1000", r)
        self.assertTrue(any("travelled" in p for p in problems))
        self.assertTrue(any("slewed" in p for p in problems))

    def test_invalid_slew_and_crawler_not_green(self):
        r = {"peak_lift_m": 1.7, "hold_drift_m": 0.01,
             "base_travel_m": 0.02, "max_slew_deg": 179,
             "max_chassis_tilt_deg": 0, "tipping_detected": 0,
             "max_base_yaw_deg": 0, "base_planar_displacement_m": 3}
        self.assertGreaterEqual(len(gate.check_case("lift_250", r)), 2)

    def test_tractor_hitch_and_friction_anomaly(self):
        r = {"peak_kmh": 9, "forward_distance_m": 30,
             "brake_displacement_m": 1, "max_hitch_error_m": 0.8,
             "max_articulation_deg": 20, "max_tilt_deg": 2, "tipped": 0}
        self.assertIn("physical tow hitch stretched", gate.check_case("hill_800", r))

    def test_pivot_turn_has_low_translation(self):
        r = {"peak_lift_m": 2.9, "hold_drift_m": 0.01,
             "base_travel_m": 0.05, "max_slew_deg": 69,
             "max_chassis_tilt_deg": 1, "tipping_detected": 0,
             "max_base_yaw_deg": 62, "base_planar_displacement_m": 0.18}
        self.assertEqual(gate.check_case("lift_pivot_500", r), [])
        r["base_planar_displacement_m"] = 2.0
        self.assertTrue(gate.check_case("lift_pivot_500", r))

    def test_grounded_material_handling_is_independent_of_lifting(self):
        # Heavy objects can pass the drag/push/roll test without being lifted.
        base = {"peak_lift_m": 0.0, "hold_drift_m": 0.0,
                "base_travel_m": 2.0, "max_slew_deg": 0.0,
                "max_chassis_tilt_deg": 0.0, "tipping_detected": 0.0,
                "max_base_yaw_deg": 2.0, "base_planar_displacement_m": 2.0,
                "object_displacement_m": 1.1, "object_roll_deg": 0.0}
        for case in ("drag_1000", "push_1500"):
            self.assertEqual(gate.check_case(case, dict(base)), [])
        rolled = dict(base, object_roll_deg=120.0)
        self.assertEqual(gate.check_case("roll_1000", rolled), [])
        stalled = dict(rolled, object_displacement_m=0.0)
        self.assertTrue(gate.check_case("roll_1000", stalled))

    def test_nonfinite_csv_cannot_pass(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "excavator_lift_250_summary.csv"
            path.write_text("peak_lift_m,hold_drift_m,base_travel_m,max_slew_deg,max_chassis_tilt_deg,tipping_detected\nNaN,0,2,68,0,0\n")
            with self.assertRaises(ValueError):
                gate.read_summary(path, "excavator")


if __name__ == "__main__":
    unittest.main()
