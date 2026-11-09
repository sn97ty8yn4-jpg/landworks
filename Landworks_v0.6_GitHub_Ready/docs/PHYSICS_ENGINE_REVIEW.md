# Landworks physical simulation selection (9 November 2026)

## Architecture decision

**Keep Godot/Tinybox as the world and gameplay layer.** Test the pinned Godot addons, then adapt *one* into a self-contained tractor module. Use Godot's **built-in Jolt Physics** backend for rigid bodies and joints. Do not combine different drivetrain add-ons on the same vehicle.

### Tractor physics

1. **KV Vehicle** — Godot 4, modular engine, clutch, drivetrain, differential, selectable raycast or shapecast wheel contacts, tyre grip response per surface. MIT code; CC0 `.obj` meshes and attribution-required CC BY icons. This is the preferred base for precise tractor wheel/ground interaction. It does **not** model a Kubota hydrostatic transmission off-the-shelf. An adapter will translate a desired ground speed/pedal command into a continuously variable hydrostatic drive ratio and torque limit, using the add-on's existing wheel dynamics. Inspect real implementation before writing the adapter.
2. **Easy Vehicle Physics (GEVP)** — Godot 4, raycast tyre forces, differential locking, engine/automatic gearbox, traction/ABS, prebuilt driving scenes. MIT. Faster first driven comparison, but a car automatic gearbox is **not** a correct HST model.

### Excavator

- Built-in Jolt handles articulated rigid bodies, `HingeJoint3D` motors, swing and bucket collision and loads. The current excavator uses only animated arm nodes: it must be rebuilt as a constrained rigid-body articulation. Use explicit masses, pivot positions, contact exclusion and power-limited joint motors. Godot's built-in joints support hinge-motor target velocity and max motor impulse, not direct hydraulic cylinder pressures.
- Jolt's C++ library includes `TrackedVehicleController`, but Godot's exposed PhysicsServer3D API has no direct dedicated tracked vehicle controller. Using C++ tracked vehicle physics means writing a native interface, not just toggling Godot's physics backend.
- `lucasw/godot_raycast_vehicles` is an MIT older-Godot example with 10 raycast contacts, five per track and differential/neutral steering. It is a **reference for track locomotion**, not an installable Godot 4 addon.
- For excavator hydraulics, `LoneWolfDog/hydrasim` (MIT) models real cylinder chamber pressures, shared pump flow, valve deadbands and load effects. Its own docs state current numerical computation can take 30–60 seconds per simulated second; direct frame-by-frame runtime import is unsuitable. Benchmark a reduced, real-time compatible C++ implementation later.
- Project Chrono (BSD-3) supports realistic tracked/wheeled vehicle dynamics and Soil Contact Model with near-real-time contact in suitable settings. Embedding Chrono in a Godot game, sharing collision worlds, and synchronizing transforms and force contacts would be a major architecture change; defer until Godot Jolt solution proves inadequate.
- Godot Rapier 3D is a promising alternative backend in November 2026 (joint improvements, deterministic replay), but not a complete excavator or vehicle module. Retain Jolt unless comparison benchmarks justify switching.

## Upgrade gates

1. Run current Landworks yard with baseline 60 Hz; record metrics and controls.
2. Switch **only the standalone yard** to Jolt and 120 Hz; test contact stability and performance, inspect collision and joint changes.
3. Download both pinned MIT addons (Windows setup script). Launch GEVP's simcade demonstration in isolation and use the KV addon in a separate test scene. **Do not overwrite prototype scripts yet.**
4. Choose one tractor chassis simulation: setup mass, centre of mass, wheelbase, tyre radius and grip. Implement HST drive adapter using existing suspension/tyre dynamics. Validate forward/reverse, hillside, trailer hitch force, tyre load and unloaded/loaded behaviour.
5. Make a powered boom/arm/bucket test bench from Jolt hinge motors, with real body collisions and load response. Then connect them into KX080 with the existing model-pivot fitting workflow.
6. Track contact physics: start with 5–8 collision/ground samples per side before investing in native Jolt tracked controllers.
7. Do not add deformable soil or Chrono into the game until suspension, hydraulics and controller latency pass the baseline.

## Benchmarks (design goals, not measured results)

- 60 fps render target, 120 Hz physics trial on a Windows PC with controller/TV.
- Both vehicles settled on flat ground without jitter; loaded tractor trailer remains stable at low speed.
- Excavator can raise and hold a physical load, slew with it and lower under a limited motor force without floating or energy injection.
- Excavator neutral turn on flat ground; slight sinkage and traction changes are **future work**.
- Fully reproducible settings, per-test frame time, joint drift and contact impulse measurements.

## Upstream sources and licence references

- https://github.com/godot-jolt/jolt (MIT) — native C++ physics (Godot built-in subsystem).
- https://github.com/Kurtzmusch/kv-vehicle (MIT code; CC0 models; CC BY3.0 icons) — pinned at `e37b7ea335a45a2f6d220a4fea3603a248aaac08`.
- https://github.com/DAShoe1/Godot-Easy-Vehicle-Physics (MIT) — pinned at `c392257f54f6ca537dc10bc5badad0c060f18982`.
- https://github.com/lucasw/godot_raycast_vehicles (MIT; old Godot) — reference only.
- https://github.com/LoneWolfDog/hydrasim (MIT) — hydraulic physics reference, not vendored.
- https://github.com/projectchrono/chrono (BSD-3) — soil and advanced simulation reference.
- https://godot.rapier.rs/blog/2026-updates/ (open-source Rapier engine alternative).

No third-party physics files are bundled in Landworks ZIP. Pinned source is downloaded explicitly and its complete project license is copied to `vendor/licenses` when run. Check model/audio-specific licenses before distributing upstream demo assets.
