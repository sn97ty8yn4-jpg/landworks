"""Static integration checks; runtime behaviour is tested by cab_control_smoke.gd."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class KX080CabIntegrationTests(unittest.TestCase):
    def test_cab_is_mounted_on_slewing_upper(self):
        src = (ROOT / "landworks/scripts/machine_art.gd").read_text()
        self.assertIn("excavator.upper.add_child(cab)", src)
        self.assertIn('CabFrontWindow', src)
        self.assertIn('CabOperatorAvatar', src)

    def test_input_is_shared_not_resampled(self):
        machine = (ROOT / "landworks/scripts/sandbox_excavator.gd").read_text()
        visuals = (ROOT / "landworks/scripts/machine_art.gd").read_text()
        self.assertIn("cab_input =", machine)
        self.assertIn("left_speed / 0.80", machine)
        self.assertIn("right_speed / 0.80", machine)
        self.assertIn("cab.set_commands(excavator.cab_input)", visuals)
        cab = (ROOT / "landworks/scripts/excavator_cab.gd").read_text()
        self.assertNotIn("Input.is_key_pressed", cab)
        self.assertNotIn("Input.get_joy_axis", cab)

    def test_first_person_retains_follow_view(self):
        src = (ROOT / "landworks/scripts/sandbox_world.gd").read_text()
        self.assertIn("KEY_V", src)
        self.assertIn("camera.current = not in_cab", src)
        self.assertIn("cab.adjust_look", src)
        self.assertIn("cab.set_seated", src)


if __name__ == "__main__":
    unittest.main()
