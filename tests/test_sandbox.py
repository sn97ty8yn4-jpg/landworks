import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sandbox_ci", ROOT / "tools/validate_sandbox.py")
sandbox = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sandbox)


class SandboxIntegrationTests(unittest.TestCase):
    def test_starts_as_real_integrated_scene(self):
        project = (ROOT / "project.godot").read_text()
        self.assertIn('run/main_scene="res://landworks/scenes/sandbox_world.tscn"', project)
        src = (ROOT / "landworks/scripts/sandbox_world.gd").read_text()
        # Each token has to appear in the file that owns the behaviour. The
        # tow hitch and the lifting strap now build their pin constraints in
        # coupler.gd, so the real-joint check follows them there, and the
        # sandbox must still be wired to the thing that builds them.
        owned_elsewhere = {
            "_drive_tracks": "landworks/scripts/sandbox_excavator.gd",
            "PinJoint3D.new()": "landworks/scripts/coupler.gd",
        }
        for token in ("sandbox_excavator.gd", "tractor.gd", "work_trailer.gd",
                      "coupler.gd", "PinJoint3D.new()", "RigidBody3D.new()",
                      "_drive_tracks", "landworks/scripts/ground_response.gd",
                      "sandbox_summary.csv"):
            owner = owned_elsewhere.get(token)
            if owner is not None:
                self.assertIn(token, (ROOT / owner).read_text())
            else:
                self.assertIn(token, src)

    def test_missing_measurements_cannot_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertTrue(sandbox.validate(Path(tmp)))

    def test_sandbox_and_old_yard_remain_separate(self):
        self.assertTrue((ROOT / "landworks/scenes/sandbox_world.tscn").exists())
        self.assertTrue((ROOT / "landworks/scenes/test_yard.tscn").exists())


if __name__ == "__main__":
    unittest.main()
