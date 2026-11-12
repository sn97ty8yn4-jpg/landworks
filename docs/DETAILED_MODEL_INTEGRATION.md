# Detailed Kubota model integration

This build replaces the previous procedural skins with the approved B7100 HST and KX080-3 static models. It is a playable Godot project, not a studio render viewer.

## What moves

Four independent, centred tractor wheels retain their concave rims, fasteners, sidewalls and turf tread. Steering, wheel rotation and suspension remain driven by the tractor solver. The body retains the engine fittings, grille, dashboard, seat, footplates and three-point hitch.

The excavator has separate undercarriage, upper body, boom, dipper and bucket meshes. Detailed shoes circulate using measured chassis velocity, including turning. Fixed-length hydraulic barrels and variable exposed rods follow the rigid bodies. The four-bar bucket linkage remains solved geometrically; static source rams and hoses spanning moving joints were removed. The missing dipper upper pivot eye was added during conversion. Cosmetic bearing and linkage attachments bridge the imported panels to the live pivots.

## Physics boundary

The imported GLBs contain rendering geometry only. No triangle-mesh collisions, masses, joints or animation tracks are imported. Excavator rigid-body masses, joint limits, motor torques, hydraulic relief and flow allocation, contact-track solver, bucket cutting calculation, soil conservation and hook constraints are retained.

The tractor wheelbase is now 1.400 m; front and rear wheel centre tracks are 0.895 m and 0.815 m. These agree with the detailed source. Tyre radii remain 0.26035 / 0.3683 m. Mass, power, HST, friction and suspension coefficients are retained. The towing and hill tests are rerun for the wider contact footprint.

The static excavator had different pin spacings from the working rig. Its arm visuals have been rebased and fitted to the established 3.00 m boom, 2.32 m dipper and 0.82 m bucket working lengths; the track art follows the existing 3.10 m belt envelope. This preserves the tested working reach rather than silently changing leverage with an art swap. These are prototype dimensions, not a claim of exact OEM linkage geometry. The cosmetic blade remains fixed.

Collision is still simplified physics proxies; the detailed bucket back, cab and panels are not exact contact surfaces. Track shoes are visual instances, not individual rigid links. The regression suite verifies the existing simulation's behaviour, not manufacturer-calibrated hydraulic performance. The painted textures are preserved, though the in-game finish remains cleaner than the concept illustrations.

## Rebuilding and testing

Open `project.godot` with Godot 4.6.3 or run the bundled Windows launcher. The editable game scripts and split GLBs are included. The original Blender scenes remain in `Kubota_Detailed_Static_Models_v1.zip`.

To reconvert those scenes:

```bash
blender -b --python tools/integrate_detailed_models.py -- /absolute/path/to/models
```

`tools/build_machine_assets.py` is the legacy generator; running it overwrites these detailed assets with the earlier models.

Validation logs and measured field-test CSVs are included under `validation`. The imported-skin check measures actual loaded geometry against the live spin axes, hinge axes and soil-cutting line. The visual smoke test exercises the real powered joints, cylinder extension and linkage closure. The thirteen field cases cover tractor towing/braking/hills, excavator lifting/stalling, travel with load, dragging, pushing and rolling, including clay resistance.

The game and its real OpenGL renders were exercised on Linux using Godot 4.6.3 and Jolt at 120 Hz. The Windows runtime is copied byte-for-byte from the preceding playable package; this update has not had a Windows desktop playthrough.
