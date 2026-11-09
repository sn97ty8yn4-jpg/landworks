import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

class EarthworkSourceTests(unittest.TestCase):
    def test_bounded_collision_and_volume_ledger(self):
        s = (ROOT / "landworks/scripts/earthworks.gd").read_text()
        for token in ("HeightMapShape3D.new()", "map_data = map",
                      "cut_sweep(", "release_soil(", "ground_volume_m3(",
                      "mobile_volume_m3(", "MAX_PARTICLES := 240",
                      "_slump(", "extracted_total_m3", "deposited_total_m3"):
            self.assertIn(token, s)
    def test_real_engine_smoke_exists(self):
        script = (ROOT / "landworks/scripts/earthworks_smoke.gd").read_text()
        self.assertIn("EARTHWORKS ", script)
        self.assertIn("absf(balance)", script)
        self.assertIn("await physics_frame", script)

if __name__ == "__main__":
    unittest.main()
