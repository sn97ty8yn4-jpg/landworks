# Windows integration results — 12 November 2026

Environment: Godot 4.6.3 stable, Jolt at 120 Hz, GL Compatibility, Windows.
Actual rendered captures identify Intel Iris Xe Graphics, OpenGL 3.3.

## Subsequent runtime material/cab update

All **eleven** checks in `RUN_INTEGRATION_TESTS.ps1` passed after the runtime
material integration and detailed cab adaptation. All **56** Python tests
also passed. The original field-scenario results below are the earlier
baseline; they have not been re-labelled as new material calibration.

- Runtime material fixture: largest constituent discrepancy 2.33e-10 kg;
  gravel bank-to-loose volume ratio 1.125786.
- Powered Jolt dig: 0.40725 m³ bank material removed; about 0.04971 m³
  bulk swell; largest constituent discrepancy 1.40e-9 kg. Dump phase released
  0.69659 m³ while further powered cutting continued.
- Unpowered Jolt bucket moved 0.11021 m under physics and removed exactly
  zero soil. No mass discrepancy above the 0.001 kg gate.
- Detailed cab: radial joystick limits, opposing travel controls, neutral
  return, upper-carriage camera attachment and V/Tab switching passed.
- Upper-carriage conversion retains all 74,014 original triangles. Source
  GLB remains immutable; the derived rig animates existing control meshes.
- Actual GL captures reviewed for exterior, seated view, controls and a
  loaded bucket. The loaded-bucket diagnostic uses isolated surroundings
  and inspection lighting to reveal its below-grade digging pose.

See `MATERIAL_CAB_INTEGRATION.md` for current limitations and controls.

## Earlier integration baseline

- Editor import and script loading, with errors checked in logs.
- 34 Python unit tests, plus GLB metadata/refusal checks and static preflight.
- Detailed mesh alignment: maximum pin-surface distance approximately 0.060 m;
  bucket-lip surface distance approximately 0.0175 m, within existing gates.
- Moving visual test: circulating tracks, hydraulic rods and linkage closure.
- Soil cutting and dumping: 0.240 m3 removed and redeposited; reported balance
  error below 0.0001 m3 in the standalone check.
- Physical powered-bucket digging and dumping with the recovered detailed rig.
- Below-grade test: actual Jolt ray hit at y=-1.594 m after scripted excavation;
  volume error approximately 0.00000083 m3; all four pad seams supported;
  excavation cannot pass the provisional -3 m floor.
- Crawler pad entry: 4.00 m travel, maximum tilt approximately 1.06 degrees.
- Hydraulic allocation/relief and load-hook attachment/release checks.
- All thirteen measured field gates: flat empty/400 kg towing, 400/800 kg hill
  towing, 250/500/1000 kg lifts, 500 kg lift/pivot, 1000 kg dragging, 1500 kg
  pushing, 1000 kg rolling, and clay pushing/dragging comparisons.
- Four real rendered machine views; sixteen landscape direction/height
  captures; backdrop structure has no collision nodes.
- All four landscape image hashes match their original supplied manifest.

The integration runner completes all eight smoke tests after editor import.
Detailed logs, field CSVs and screenshots are under local `validation/`.
The thirteen lab cases validate their established rigs; they are not a complete
working-job-cycle test of the sandbox, nor proof of every Physics v2 requirement.

## Not established

OEM-calibrated forces, dry-mass/water conservation, force-before-cut gating,
stratigraphy, fine tooth-scale deformation, rutting/bogging, a complete
load/haul/grade/compact cycle, long interactive playthrough and sustained
60 FPS under heavy excavation remain unverified or unimplemented.

The original landscape pack is prototype resolution with non-matching edges.
Runtime blending and repeated cylindrical sectors make it usable in-game;
they do not turn it into uniquely authored seamless 8K artwork. The transition
is simplified, particularly at elevated viewpoints.

No remote branch was merged and no changes were pushed to GitHub in this
integration. These results describe the local workspace.
