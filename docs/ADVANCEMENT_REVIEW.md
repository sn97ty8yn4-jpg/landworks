# November 12 advancement review

**Historical review checkpoint:** the subsequent
[runtime soil/cab integration](MATERIAL_CAB_INTEGRATION.md) now adapts the
detailed cab and activates the first material mechanics stages in Godot.
The dispositions below describe the earlier review, before that implementation.

Source: ChatGPT chat **Game Areas for Chat Advancement**
(`6af4da10-c108-83ec-bf05-303cd8007a7f`), its downloaded
`kx080-cab-qa-latest.zip`, and [draft PR 2](https://github.com/sn97ty8yn4-jpg/landworks/pull/2)
at commit `8b29ac91afed718f709b951e1d42fe066f20e59c`.

## What is usable

| Output | Assessment and disposition |
|---|---|
| Cab QA ZIP: exterior, seated view, controls view and renderer logs | Reviewed locally. These demonstrate the older procedural machine, not the recovered detailed GLBs. Preserve as reference in ignored `validation/external-cab-review`; do not replace the detailed exterior with it. |
| PR 2 seated camera | Useful design: camera inherits the upper carriage, bounded head movement, lean and return to follow view. Its seat position is calibrated to the old shell and its 270 m far plane would clip the current countryside. Adapt to the detailed cabin before integration. Not installed in this pass. |
| PR 2 joystick and tram controls | Useful command-driven animation with smoothing and radial joystick limits. Existing detailed GLB already includes interior furniture; adding the old procedural station would duplicate it. Separate the detailed controls at export, then animate those meshes using actual machine commands. Not installed in this pass. |
| Material Mechanics v1.1 ZIP | Received and verified against all seven manifest hashes. Imported the documents, seven profiles, offline reference solver and 22 tests as stage M-00. All reference tests pass locally; new CI step runs them. Advanced material behaviour is not yet enabled in Godot. |
| Numerical benchmark proposals | Retained below as proposed fixtures, supplementing the existing Physics v2 plan. These are analytical expectations and calibration targets, not measured game results. |
| Statement that detailed assets did not exist | Applied to the other chat's GitHub checkout. It is obsolete for this local integration, which has ten independently attached detailed machine parts and articulated track shoes. |

The source chat ended with the user reporting a visual regression and asking
for reassessment. That makes a wholesale merge inappropriate. The current
detailed assets and original landscape PNGs remain the visual baseline.

## Material package integration completed: M-00

The two downloaded copies of `Durham_Park_Sandbox_Material_Mechanics_v1.1.zip`
are identical, SHA-256
`3950ff79e226ee3380da1951ebd6f1973196453cd284330c7b59dc0603358ef3`.
All seven enclosed file hashes match the supplied manifest. Files adopted:

- `docs/ENGINEERING_SPEC_V1_0.md`: original coupled-physics specification.
- `docs/MATERIAL_MECHANICS_V1_1.md`: evolving material specification.
- `docs/MATERIAL_MECHANICS_HANDOFF_V1_1.md`: original staged handoff.
- `landworks/data/soil/material_profiles_v1_1.json`: seven original profiles;
  their source labels correctly identify unverified tuning assumptions.
- `tools/material_reference.py`: original offline solver, with only its
  default profile path adapted to the repository layout.
- `tests/test_material_reference.py`: original 22 tests, with only its import
  directory adapted. The earthworks CI now runs this suite separately from
  Godot contact tests.

Local Python validation: **56 tests passed**, including all 22 material tests.
These establish the reference's mathematical behaviour, not field calibration
or Jolt material integration. The reference has no persistent terrain-column
store, duplicate-receipt protection, live contact handshake or bucket CoM
coupling. Its force and moisture laws are deliberately simplified. Stage
M-01 and subsequent stages remain implementation work.

The imported handoff records the earlier hidden floor under the soil pad.
That specific defect is already fixed in this local game, with four-boundary
and below-grade collision checks. Its depth strata requirement remains open.
The original handoff is preserved rather than rewritten as current status.

## Bucket correction applied

The distributed bucket GLB has its transverse axes reversed relative to the
live rig. Its hinge and teeth still align with the rig's -Z axis, so the old
endpoint test could pass while the bucket opened away from the excavator.
The loader now rotates only the imported bucket by 180 degrees about that
axis. Source GLB bytes, physical bodies, joints, tooth contact, arm geometry,
materials and landscape assets are unchanged.

`detailed_skin_smoke.gd` now also samples actual central shell geometry to
verify which side of the hinge-tooth line contains the back of the bucket.
The reversed fixture is available with `-- --reversed-bucket-fixture` and
must fail even though hinge/tooth alignment still passes.

Windows Godot 4.6.3 validation: all eight integration checks passed, including
articulation and physical digging. Corrected shell mean local Y is +0.6159 m
over 2,764 sampled vertices; lip-to-contact error remains 0.01747 m and maximum
arm-pin surface distance remains 0.06001 m. Actual renderer before/after
views are in `validation/bucket-review`. The shell check is a regression
guard for this mesh, not a dimensional certification of a Kubota bucket.

## Proposed benchmark fixtures to carry forward

These need a dedicated controlled harness. Do not silently substitute them
for existing field tests or quote their numbers as measured performance.

| Fixture | Reference expectation from the chat |
|---|---|
| Ideal lift, 40 kNm torque, 4 m radius, negligible arm weight | 500 kg requires 19.62 kNm; 1,000 kg requires 39.24 kNm; 1,200 kg requires 47.09 kNm and should stall. Proposed stalled displacement <=20 mm. |
| Drag 1,500 kg, static friction 0.5, kinetic 0.4, g=9.81 | Breakaway 7,357.5 N. 5 kN should hold; 10 kN gives about 2.743 m/s² after breakaway and 1.371 m in one second from rest, using `(10000 - 0.4*1500*9.81)/1500`. |
| Trench 4.05 x 0.90 x 0.45 m | 1.64025 m³ bank volume; at 1,700 kg/m³, 2,788.425 kg. 20% swell gives 1.9683 m³ loose; 0.24 m³ bucket at 85% usable capacity requires 10 loads. |
| Dump 0.204 m³ gravel | At 1,416.7 kg/m³ loose density, about 289 kg. Proposed >=99% retention for 3 s, >=95% discharge in 5 s, repose 36 ±5 degrees. These are calibrated targets. |
| Adhesive clod, 20 kg | Weight 196.2 N. In an ideal vertical force fixture, 300 N adhesion holds and 100 N does not. |
| Ground support, 8,170 kg, two 0.46 x 3.1 m tracks | Area 2.852 m², average pressure about 28.1 kPa. Linear stiffness 1,500 kPa/m gives about 18.7 mm sinkage; 250 kPa/m gives about 112.4 mm. |
| Excavated ramp | 4.5 m wide, 3 m run, 0.45 m descent, 8.53 degrees. Proposed descend/stop/reverse test with final level -0.45 ±0.10 m. |
| Ideal hydraulic supply | 36 kW at 27.4 MPa permits about 78.8 L/min. 60 L/min at 10 MPa requires 10 kW. 144 L/min requested at 27.4 MPa requires flow scaling to about 0.547. |
| Force/work cut gate | 12 kN resistance vs 8 kN available: stall and zero soil transfer. 20 kN can cut only with actual displacement and work. A 0.1 x 0.9 x 0.2 m cut is 0.018 m³ / 30.6 kg at 1,700 kg/m³; a constant 12 kN force over 0.1 m requires 1.2 kJ. |

The earlier v2 acceptance plan specifies stricter separate dry/water mass
tolerances than the later chat's proposed 0.5% integrated budget. Keep the
earlier requirements until calibration justifies a deliberate change.

Recommended sequence: implement a tested mass/water ledger and
force-before-cut transaction; add controlled
benchmarks; adapt the seated camera and individually animated detailed
controls. Keep exterior render checks alongside every stage.
