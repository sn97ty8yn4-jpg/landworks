# Landworks physics sandbox (first integrated build)

The default Godot scene is now `landworks/scenes/sandbox_world.tscn`.

**Integrated machines:** the B7100HST rigid-body tractor, connected by a real
pin-joint hitch to a 400 kg loaded single-axle trailer; and the KX080-inspired
8.17t physical excavator using the **same rigid-body boom, stick, bucket,
slew joint, four contact-patch tracked-traction proxy, and flow-limited
hydraulic model** already tested in CI.

The old yard remains accessible with F12. The independent 13 field-trial
scenes remain in the repo and execute on every CI push.

## Controls

TAB / PlayStation Triangle: change machine.

B7100HST: W/S forward/reverse, A/D steering; PlayStation R2/L2 travel pedal
and left stick steering. Right stick or Z/C rotates the follow camera.

Excavator: W/S tracked forward/reverse, A/D differential turning, I/K boom,
O/L stick, P/semicolon bucket, Q/E slew. On PlayStation: left stick tracks,
R2/L2 boom, right stick dipper/bucket and L1/R1 slewing.

The excavator arm joints are physical hinge motors. Raising an overloaded
object is not guaranteed, but the tracks and bucket remain free to push,
drag or roll ground-supported objects. The free 1,500 kg crate from the
tested push case spawns directly in front of the excavator.

## Initial sandbox

Flat ~140 m collision ground, hardpack and silty-clay zones, a small ramp,
400 kg trailer, 1,500 kg crate, 450 kg log, 900 kg rock and 650 kg blocks.
The environment is intentionally simple so machine dynamics, ground
contact and controller responsiveness can be assessed before adding terrain
deformation, complex textures or a large map.

**Technical limitations:** Jolt box-track collision and longitudinal force
patches are NOT a genuine track chain. The hydraulic moment arm estimates,
nominal engine-to-oil budget and friction values remain uncalibrated. Ground
zones influence rolling resistance and grip but do not deform terrain.
No digging/soil volume transfer is implemented yet.

## Real engine smoke test

```bash
godot --headless --path . res://landworks/scenes/sandbox_world.tscn -- --sandbox-smoke --output-dir=./sandbox_test_results
python3 tools/validate_sandbox.py --dir sandbox_test_results
```

The same playable scene receives time-varying HST and excavator inputs.
It writes CSVs measuring tractor travel, crawler travel, excavator joint
rotation, trailer hitch separation, chassis stability, hydraulic pressure
and free-crate displacement. The validator refuses incomplete or nonfinite
results. These are regression checks, not a claim of Kubota OEM-level fidelity.


## Ground-object lifting hook

When operating the excavator, press **G / PlayStation Square** to attach
a nearby free-standing object to the bucket tip with a real `PinJoint3D`.
Press again to release it. No rigid body is teleported or given a scripted
movement velocity. An overloaded object may remain on the ground while the
excavator can still drag it or push against it. The prototype capture range
is 1.6 m from hook to object centre. This is **not** a calibrated quick hitch,
a flexible chain, an attachment safety device or a rated lift procedure.
