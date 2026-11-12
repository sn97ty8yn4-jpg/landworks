# v0.5 — B7100 side-by-side and force-producing excavator rig

## What is actually implemented

- `landworks/scenes/physics_comparison_lab.tscn` runs the original v0.4 tractor, a **KVVehicle with four KVWheel instances, KVEngine, KVDrivetrain and KVBreak**, and an **Easy Vehicle Physics `Vehicle` with four `Wheel` instances**, in three adjacent lanes. Third-party code is loaded only if installed under `addons/`.
- Each engine runs *its own* wheel/tyre physics. Neither KV nor Easy Vehicle Physics is simulated by reusing the baseline tractor controller. There is no fake benchmark result for a missing add-on.
- The Godot physics loop applies the same timed control schedule to all three: 2.5 s settle; 10 s full forward input; 4.5 s brake; 6 s 62% throttle and steer. The benchmark logs real body positions and velocities from Godot, sample CSV and end summary CSV, plus visible status.
- `landworks/scenes/physical_excavator_lab.tscn` physically hinges a 650 kg boom, 400 kg stick and 210 kg bucket to an anchored 6,910 kg chassis. The 250 kg test payload is an independent `RigidBody3D` connected to the bucket by a `PinJoint3D`. The three arm pins are `HingeJoint3D` constraints with velocity motors and maximum impulse. Lifting acts through the physics solver, not through setting arm `rotation.x` every tick.
- A second 500 kg test load may be selected with **M / Square**. Toggle automatic demo vs manual input using **Space / Cross**. If manual, I/K boom, O/L stick, P/semicolon bucket; PlayStation joysticks work too.

## Geometry and mass basis

The comparison models share 573 kg tractor operating mass, 1.39 m wheelbase, front diameter 0.5207 m (20.5-inch turf tyre), rear diameter 0.7366 m (29-inch turf tyre), 0.2032 m front width and 0.3048 m rear width. Overall hull and input schedule are matched; *suspension/drive* remain their different implementations.

For KV and GEVP, the initial 52 Nm peak motor torque, 850 rpm idle and 3200 rpm max are **tuning assumptions**, not validated measurements from a B7100HST. KV and GEVP use geared transmissions; **neither represents a true hydrostatic drive yet**. KV is configured with 4WD power delivered to all four wheels and a simulated clutch. GEVP uses a 35% front axle torque split and automatic gears. The legacy tractor has a fixed 4250 N traction-force model, not an engine.

The angle limits and motor max impulses are starting tunings. Godot's hinge motor can exert a reaction force, but this is **not a model of hydraulic cylinders, valve pressure, pump displacement or oil compressibility**. Mechanical load lifting still requires run-time verification.

## Side-by-side code audit — not measured handling results

| Category | Legacy tractor | KV Vehicle | Easy Vehicle Physics |
| --- | --- | --- | --- |
| Source of traction | Four raycast contacts, simple force clamp | KVWheel tyre-force response with grip curves | Wheel brush tyre contact model |
| Engine | No engine | KVEngine, custom torque curve | Vehicle engine, torque curve |
| Transmission | Fixed propulsion force | KVDrivetrain gears/clutch | Automatic geared transmission |
| Braking | Added direct force-resistance input for bench | KVBreak applied to four wheels | Per-wheel braking/ABS model |
| Differential | Fixed nominal axle weights | KV drivetrain / optional diff modules | Built-in differential lock and axle torque split |
| Correct HST? | No | Not yet; best control integration point | Not yet; auto gearbox workaround |
| Runtime measurements | NOT EXECUTED | NOT EXECUTED | NOT EXECUTED |

**Engineering conclusion (source-level):** adopt **KV Vehicle for the B7100** if its Godot 4.6/Jolt stability tests pass, because the motor/drivetrain/wheels are modular and easier to adapt to a hydrostatic pump–motor relationship. Use GEVP as a quantitative benchmark and potential basis for on-road trucks, not as proof it performs better until the CSV measurements exist.

## How to run on Windows

1. Open the project with **Godot 4.6**. The project defaults to **Jolt Physics at 120 physics ticks/s**, with the reversible scripts to test the old backend.
2. Double-click `tools/windows/SETUP_PHYSICS_WINDOWS.bat` (requires Python 3). Verify both addon folders exist, then **restart Godot** so `class_name` scripts re-index.
3. Open `landworks/scenes/physics_comparison_lab.tscn` and press F6 (or from the main yard, D-pad left/F5). The three lines appear only when each real engine is installed. If the code has import errors, use Godot Output / Debugger to identify the failing component; do not record a benchmark for a variant which could not start.
4. Wait for **SETTLE → ACCELERATE → BRAKE → TURN → DONE**. Results are written under Godot's app `user://` data directory as `landworks_comparison_samples.csv` and `landworks_comparison_summary.csv`. The console prints the data directory. Run `tools/windows/ANALYSE_BENCH_WINDOWS.bat` with the summary CSV path to write a Markdown comparison report; missing engine results remain explicitly marked as not run.
5. Open `landworks/scenes/physical_excavator_lab.tscn`, press F6, and observe physical payload height in the overlay. Use Space/Cross to switch to manual, M/Square to change the mass. If the rig moves without corresponding mass movement, or the hinge violently oscillates, record that as a failed physics acceptance test.
6. Keep the earlier `landworks/scenes/test_yard.tscn` as the original playable baseline. The visual-only excavator remains there for backwards comparison.

## Acceptance gates before Tinybox merger

- All three tractors instantiate without parse errors and remain on the ground through the 22-second test. Compare peak speed, 10-second path, braking path, turn yaw and roll, with the complete telemetry CSV.
- Benchmark uses a fixed 120 Hz physics tick and fresh project launch (especially following backend switch). Confirm body centre of mass and correct front/rear tyre radii for each engine.
- Force-based excavator can hold the 250 kg test load and raise it **at least 0.3 m measured from its actual rigid-body position**, without snapping or large oscillations. Test 500 kg; do not interpret these arbitrary loads as rated lift capacities.
- Chassis is deliberately **frozen**, so this first test does **not** establish stability, counterweight effectiveness, tracked traction, or safe lifting limits. Unfreeze and track-contact tests must come after the joint solver is stable.
- Do not infer that CSV results are apples-to-apples manufacturer performance curves: transmission ratios, tyre contact models and control assists have not been validated against the actual Kubota.

## Source and licences

- KV Vehicle — MIT code: https://github.com/Kurtzmusch/kv-vehicle — pinned `e37b7ea335a45a2f6d220a4fea3603a248aaac08`.
- Easy Vehicle Physics — MIT code: https://github.com/DAShoe1/Godot-Easy-Vehicle-Physics — pinned `c392257f54f6ca537dc10bc5badad0c060f18982`.
- Godot `HingeJoint3D` reference: https://docs.godotengine.org/en/4.3/classes/class_hingejoint3d.html
- All third-party assets and code are excluded from this source ZIP until the opt-in installer runs.

## Validation limitations

Python tests and project static checks were run in the authoring environment. Godot runtime, Windows input, Jolt joint stability, and either installed vendor add-on **were not executable in this environment**. This is implementation-ready source for a live benchmark and powered-joint trial, NOT a report of already measured physics performance. Source-level issues may still appear on the first run and need correction based on actual Godot output.
