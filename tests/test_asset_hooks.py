"""Check visual-mount contract without requiring model bytes or Godot runtime."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
tractor = (root / "landworks/scripts/tractor.gd").read_text()
excavator = (root / "landworks/scripts/excavator.gd").read_text()
viewer = (root / "landworks/scripts/asset_lab.gd").read_text()
for name in ["b7100_body.glb", "b7100_wheel_front.glb", "b7100_wheel_rear.glb"]:
    assert name in tractor, f"Missing tractor part hook: {name}"
for name in ["kx080_upper.glb", "kx080_boom.glb", "kx080_stick.glb", "kx080_bucket.glb", "kx080_track.glb"]:
    assert name in excavator, f"Missing excavator part hook: {name}"
assert "ResourceLoader.exists" in viewer
assert "if not ResourceLoader.exists(path)" in (root / "landworks/scripts/model_swap.gd").read_text()
assert (root / "landworks/scenes/asset_lab.tscn").exists()
assert "garden-tractor-with-trailer.glb" in viewer
assert "compact-tracked-excavator.glb" in viewer
assert "M.block(bucket_art" in excavator
assert 'const VEHICLE_MASS := 573.0' in tractor
assert 'mass = 8170.0' in excavator
print("PASS all optional GLB slots and independent preview scene present")
