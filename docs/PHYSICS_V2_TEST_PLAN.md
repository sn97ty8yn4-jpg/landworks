# Earthmoving Physics v2 — reproducible acceptance and field-trial plan
Status: PROPOSED ACCEPTANCE TESTS — NOT YET IMPLEMENTED OR EXECUTED
Target engine: current Godot 4.6 / Jolt 120 Hz / Compatibility render, Windows build
Companion: `docs/PHYSICS_V2_ARCHITECTURE.md`

## Test harness contract
- Add `landworks/scenes/earthmoving_v2_lab.tscn` to create seed-controlled machine + ground + truck/trailer + test props. Keep existing sandbox unchanged until all P0/P1 gates pass.
- Add `landworks/scripts/earthmoving_v2_test_runner.gd` headless scene test executor (not provided in this proposal), with CLI `--scenario=<case>`, `--seed=2048`, `--output-dir=<path>`, `--batch`.
- Every case writes `samples.csv`, `summary.json`, `events.jsonl` (material transactions + solver events), `perf.csv`; error exit code on failure and full version/build/seed metadata.
- All comparisons use exactly the same seed, material reference curves, physical pose, inputs and simulation duration; rerun with at least two soil moistures.
- Existing `landworks/scripts/earthworks_smoke.gd` and field-trial scripts remain regressions. Future tests must prove that *the Jolt excavator* moved the soil, not an abstract scripted cut sweep.
- Thresholds below are engineering **targets** subject to empirical calibration; do not present them as measurements, OEM ratings or guarantees.

## Common telemetry, sampled at >=20 Hz and each ledger event
`time_s, step, seed, x/y/z of bucket and each tooth, lip_speed_m_s, tooth_penetration_m, actual_cut_mass_kg, expected_cut_force_n, applied_contact_force_n, work_required_j, work_available_j, boom/stick/bucket joint angles and angular rates, each actuator stroke_m, cylinder_force_n, pressure_mpa, pump_flow_lpm, hydraulic_power_kw, track_normal_forces_n, track_slip_pct, track_sinkage_m, chassis_pitch_roll_deg, bucket_payload_solids_kg, bucket_payload_water_kg, ground_solids_kg, mobile_solids_kg, trailer_solids_kg, offsite_solids_kg, dry_mass_error_kg, water_mass_error_kg, performance timing by subsystem, collision_shape_version, terrain_revision, min_fps and p95_frame_ms`.

### Conservation thresholds
- Atomic transaction invariant: each transfer source debit equals destination credit exactly within machine-precision representation (recommended integer grams for ledger; avoid float cancellation).
- Whole-scene dry mass after multi-stage event chain: absolute discrepancy <= max(0.1 kg, 0.1% of transferred dry mass). Wet mass separately <= max(0.1 kg, 0.1% of transferred water). Thresholds are targets for settled run; exports counted in `offsite`.
- Bulk volume is **not** globally conserved once looseness/compaction is active; instead validate mass/void ratio/density consistency and reasonable swell trends.
- Any carried soil should add corresponding machine mass and torque; it cannot merely set the HUD bucket fill volume.
- No new terrain modification if the bucket does not penetrate or moves at effectively zero speed.

## Scenario matrix (automatable)
| ID / gate | Setup & machine action | Expected physical result | Initial pass/fail requirement |
|---|---|---|---|
| T00 P0 | Drive unfrozen excavator from flat yard onto soil pad; enter/leave five times | No hidden curb, bouncing, track clipping or discontinuous support | Completes traversal; no spurious vertical impulse > baseline peak * 1.5; record all 4 track probes and collisions |
| T01 P0 | Dig beneath original grade to 0.60 m with excavator (not manually mutate heightmap) | Hole is actually deep and collision-consistent, machine can reach its bottom | Minimum 0.50 m **below y=0** measured after settling; no collision from old flat floor; tool doesn't fall through land |
| T02 P1 | Excavate, load, dump and recompact 0.20–0.40 m3 of two materials | Dry solid/water mass conserved while bulk volumes swell/change | Both ledger tolerances pass; loose fill volume > equal-mass compacted fill volume |
| T03 P2 | Hold bucket stationary, then scrape with high-res teeth through dry gravel | No removal on no-motion; separate teeth produce visibly distinguishable contact paths | Stationary removal 0 within 0.1 kg; measured tooth penetration and non-zero opposing reaction |
| T04 P2/P3 | Same commanded scoop into easy sand vs dense compacted wet clay at same reach | Tough soil gives greater force/pressure, less achieved penetration; stalls at limit | Monotonic resistance under controlled state; once stalled no ongoing excavation or artificial clipping |
| T05 P3 | Lift and curl partly filled vs empty bucket at three reaches | Bucket load changes required torque, hydraulic pressure, chassis reaction | Recorded payload mass creates corresponding changed torque/response; pressure never exceeds model relief + tolerance |
| T06 P4 | Excavation face through 0.25 m topsoil + 0.60 m clay + granular layer with 2 buried rocks | Correct changes in material, soil force, tint, clod/grain response and discrete contacts | Fractions sum to 1; stratigraphic sequence matches fixture; 2 rocks persist/are not quietly deleted |
| T07 P4 | Make steep cuts in dry sand, cohesive clay, and wetter clay; leave unsupported, apply nearby load | Sand avalanches progressively; clay can stand steeper initially then fail when loaded/moistened | No mass disappearance; slope failure depends on state; uncut unaffected cells remain stable |
| T08 P4 | Dump a half bucket of mixed gravel/clay onto slope; inspect parcels/pile | Flow, fall, settling and plausible segregation, and pile mass remain consistent | No clipping/teleportation; all airborne mass either held/deposited/offsite after test; particle caps never erase mass |
| T09 P5 | Track excavator across dry hardpack and wet clay with same forward and turning commands | Wet clay more slip/sinkage; successive passes create ruts, changed resistance | Repeated passes update physical rut depth; track forces obey load/traction bound; no vertical teleport |
| T10 P5 | Attempt to lift an oversized rooted stone, then drag/roll using low bucket contact | Can't lift unsupported overload, may drag/roll against soil forces, can extract if threshold reached | Object genuinely moves from Jolt forces, not transform changes; successful excavation depends on breakout threshold |
| T11 P5 | Build 1 m high embankment by dumping gravel and clay; grade using blade/bucket; compact 3 passes | Material piles, moves, becomes denser/harder to dig | Net mass balanced; density and rut response change in appropriate direction; no phantom material creation |
| T12 P6 | Complete trench -> spoil bucket -> trailer -> tractor haul -> dump -> spread -> compact | Entire material chain is physically consistent and persists across machine switch | Mass + water balance; bucket/trailer mass affects machine; scene reload/restart restores geometry, ledger and tool state |
| T13 PERF | Execute T12 with animated countryside and full machine detail on nominated midrange Windows PC | Target fluid 60 fps, no solver spikes or accumulating leaks | median fps >=60 target and p95 frame time <=20 ms as starting gate; collect p99 and worst 1% causes; defer strict hardware target until reference PC is specified |
| T14 STRESS | 1000 scoop/spill/settle cycles with soil chunk border crossing and save/load every 100 | No drift in mass/collision/height and no runaway allocations | Dry and water mass within thresholds, no invalid/floating data, stable memory after warm-up, reproducible seeded outcome |
| T15 REGRESS | Replay existing 13 machine field-trial cases, tractor hitch scenarios and art/visual layer smoke | No regression in rigid-body load handling, tractor controls, camera or art | Existing passing baseline metrics must remain passing; keep failures if baseline was already failing |

## Prioritised release gates
**Milestone A — Dig a real hole (P0):** `T00, T01, T15`. Success means physical below-grade trench under Jolt; do not add more particles until this works.
**Milestone B — No free dirt (P1–P2):** `T02, T03, T04`. Soil debits, loads and force-exhaustion behave consistently.
**Milestone C — Hydraulic/soil coupling (P3–P4):** `T05–T08`. Real reach-dependent resistance, mixed soils, slope failure and conservative motion.
**Milestone D — Actual earthmoving job (P5–P6):** `T09–T12`. Track rutting, extraction, grading, compacting and trailer hauling.
**Milestone E — Reliable Windows build:** `T13–T15` on the actual target PC, including full game art.

## Calibration plan
- Record donor KX080-3 bucket shell interior (m3), tooth count & pitch, tooth tip coordinate offsets, cylinder pin-to-pin lengths at known poses, bore/rod diameter (mm), rod stroke (mm), relief setting (MPa), real usable flow (L/min), and machine operating mass for installed attachment. Until available, label all assumed values provisional.
- Soil references: dry/wet bulk mass of a known volume, particle/solid density estimates, moisture and compaction state, simple repose observations for sand/gravel, and bucket breakout trials in soil. These are tuning observations, not geotechnical certificate values.
- Record machine dig cycle(s) at idle/working RPM plus reach, bucket pin angle, lift/penetration path and load. Use instrumented data where possible; video alone cannot certify cutting force.
- Establish reference hardware (CPU/GPU/RAM/OS) and compare frame-time curves for feature switches `legacy_v1`, `mass_v2`, `force_v2`, `layered_v2`, `tracks_v2`.
- All new soil physical constants stored in inspectable per-material resources, not embedded magic numbers throughout code.

## Known limitations not hidden by tests
- Physically convincing soil can be approximated without millions of particles. This won't be a certified soil mechanics simulator.
- A heightfield cannot retain caves/undercuts; later use local 3D geometry if actual undercut tasks justify it.
- Force/energy correctness depends on accurate hydraulic geometry and stable Jolt coupling, requiring real runtime tests.
- 1–3 cm near-tooth collision interaction is **local only**, not whole-world voxel resolution.
- Simulation 120Hz and renderer 60fps are different clocks. Both require separately timed measurements.
