# Durham Park Sandbox — Earthmoving Physics v2 architecture
Status: PROPOSAL ONLY (no engine implementation or Windows runtime validation in this branch)
Date: 2026-11-12 | Source: user's 15 locked design decisions

## Non-negotiable outcomes
- Engineering-inspired, force-limited excavation; realistic bucket teeth/edge, cylinder kinematics, motor stall, load transfer.
- Clay, sand, gravel, topsoil, compacted fill, rocks, wet mud; spatially varying stratigraphy.
- Material transport, segregation, slumping, bulking, compaction, wet-ground effects, ground/track interactions.
- 10–30 mm **local bucket-contact sampling**, not 10–30 mm whole-world terrain cells.
- ~60 fps visual target on mid-range Windows gaming PC, with adaptive physical fidelity.
- Closed end-to-end loop: excavate -> carry -> load -> transport -> dump -> spread -> compact.
- Stay compatible with current illustrative art, 250 x 250 m gameplay terrain concept, and Jolt equipment dynamics.

## Current repository baseline (audited)
- `project.godot`: Godot 4.6/Jolt 3D, 120 physics ticks/sec, GL Compatibility renderer.
- `landworks/scripts/earthworks.gd`: 18 m pad, 81x81 height map at 0.225 m pitch, two surface material IDs, approximate cutting-force response, maximum 0.24 m3 bucket, 800 airborne 0.75 L parcels, ~5.6 Hz whole-map mesh/collider rebuild, approximate repose relaxation.
- `landworks/scripts/sandbox_world.gd`: one bucket-tip-point sweep with 0.76 m tool width, cuts terrain before applying resisting force; one flat 140 m square StaticBody floor beneath pad; material ledger is bulk volume, not dry mass; the soft-clay traction zone is unrelated to the pad material IDs.
- `landworks/scripts/excavator_work_lab.gd`: movable rigid-body chassis, boom, dipper, bucket with motorised hinges, 4 track contacts and force-limited pseudo tracks.
- `landworks/scripts/hydraulic_model.gd`: provisional 144 L/min total reference flow, 29.4 MPa relief and 36 kW power budget; fixed joint torque ceilings and rough load estimate. No verified cylinder pin geometry or independent true cylinder force calculation.
- `docs/EARTHWORKS.md` retains old 41x41 historical notes; current code uses 81x81. `earthworks_smoke.gd` tests swept cuts and volume conservation, not machine-energy feasibility.

### Known problems to resolve FIRST
1. Full pad remains on top of a collision-enabled flat yard plane. Excavate bank material, but cannot make a proper trench below the original y=0 plane without changing the collision architecture.
2. Soil mass is not conserved when bulking and compaction are implemented: volume should be a derived consequence of mass/void ratio, not the accounting unit.
3. Soil is debited before the physical response can oppose the cut. A motor stall can still produce a volume debit if the moving lip just entered a cell.
4. A single bucket-tip sweep is not contact geometry. The coarse 225 mm grid exaggerates gouging and hides tooth engagement.
5. The fixed 5-6 Hz collision rebuild can lag physics by ~0.18 s. Contact-safe near-tool geometry, and synchronised collision refresh at boundaries, are needed.
6. A heightmap cannot represent vertical undercuts/overhangs or free soil fragments. Keep that as a deliberately bounded limitation, or add local signed distance / breakaway rigid clods later.
7. Ground response is based on fixed world-X zones, not the actual material/moisture/load state under the crawler.

## Proposed services (independent modules)
| Component | Purpose | Data contract |
|---|---|---|
| `EarthRegionManager` | Active 16–32 m chunks, dirty bounds, far-field 0.25–0.5 m cells, local working patches | stable terrain cell IDs, geometry versions |
| `StratigraphyStore` | Per-column soil intervals: topsoil, clay, gravel, mixed fill, rock; buried individual objects | material composition, horizon depths, state |
| `SoilMaterialState` | Dry solids kg, pore-water kg, porosity/void ratio, saturation, bulk density, cohesion, friction, compaction, plasticity | conservation and mechanical properties |
| `BucketContactSampler` | Multiple 3D cutting teeth + edge/side/heel swept transforms, 10–30 mm step, proper bucket interior | requested local penetration + cross-section |
| `SoilFailureSolver` | Soil cutting wedge, shear resistance, local slumping, soil-bearing response | predicted force/wrench, permitted detached mass |
| `HydraulicActuatorSolver` | Per-cylinder piston/rod areas, pin geometry, cylinder stroke, valve flow, pump power and relief | allowed joint torques, velocities, stall pressure |
| `MassTransferLedger` | Immutable transfers with dry solid kg by material and water kg, per container | checksums for ground -> bucket -> mobile -> trailer -> ground/offsite |
| `LooseMaterialSolver` | Hybrid pile cells + moving weighted parcels + large clods/rocks | mobile mass, velocity, material/water fractions |
| `GroundContactSolver` | Normal-pressure-dependent shear, slip, sinkage/ruts, berm resistance and compaction | contact force + accumulated ground deformation |
| `TerrainCollisionBridge` | Replace floor in live pads, maintain consistent Jolt collision, retire outdated contact proxies | collision geometry version + update timestamp |
| `PhysicsTelemetry` | Reproducible tests, perf timings, graphs, failure capture, scene state persistence | structured CSV/JSON per scenario |

Keep Godot/Jolt for vehicles, machine links, rocks, logs, trailers and collision response. Do NOT instantiate a RigidBody3D for every grain. Start GDScript for correctness; profile, then move only hot loops into a small C++ GDExtension if needed.

**Renderer constraint:** project uses GL Compatibility. Godot RenderingDevice compute shaders are not available in Compatibility; upgrading to Forward+ solely for soil physics should NOT be the first step. Keep a CPU deterministic solver, MultiMesh for visually represented granular parcels, and painterly art independent of collider mesh. GPU computation is an optional A/B experiment only after profiling and renderer-risk audit.

## Simulation state and mass accounting
For each physical material bucket (not per visual particle), store:
- `dry_solid_mass_kg` (invariant unless imported/exported);
- `pore_water_mass_kg` (transferable via redistribution/evaporation optional, baseline no evaporation);
- `solid_density_kg_m3`, composition fractions, void ratio `e`;
- `bulk_density_kg_m3` derived from dry mass, water and geometry, never a second independent source of mass;
- `cohesion_kpa`, friction `phi_deg`, moisture/saturation, plasticity, relative density, compaction history, rock content, stratigraphic ID.
No presumed universal constant for soils: define ranges to calibrate empirically.

Dry-solid mass: `M_s = rho_s V_s`; bulk cell volume: `V_bulk = V_s (1 + e)` for an idealised void-ratio model. Water volume is included within pores at partial/full saturation and not added twice. Excavation can increase void ratio (swell), dumping may increase it, compaction reduces it. **Never equate in-situ excavated bulk volume directly with deposited loose volume.** Track dry solid and water separately in ground, bucket, moving parcels, trailer, offsite sink.

Design ledger:
`transfer(source, target, solids_by_material_kg, water_kg, transaction_id)` with one atomic debit and credit. Out-of-bounds export is a recorded offsite container, not disappearance.

## Bucket/soil/actuator coupling
1. Get bucket, teeth, cutting edge and sides world poses at previous/current 120 Hz physics snapshots.
2. Substep each swept contact trajectory to <=0.02 m (tune 0.01–0.03 m); compute candidate intersections with stratigraphy and local cut faces.
3. Estimate required resistance vector from tooth penetration, area, soil cohesion, friction/confinement, speed, local wedge, suction/wet resistance and current material state. Use a bounded semi-empirical cutting-wedge model first; upgrade with calibrated benchmarks.
4. Compute tool force wrench about machine pins, using `tau = J(q)^T F_tool` and cylinder lever arm geometry `tau_j = F_cyl,j * r_perp,j(q)`. Cylinder driving force `F = p_cap*A_cap - p_rod*A_rod - friction`, with relief, stroke limits, load-sensing flow allocation and `P_oil = sum(p_i Q_i)` bounded by available engine-to-oil power. Do not interpret generic HingeJoint caps as calibrated OEM cylinder performance.
5. The physical Jolt rigid-body motion is authoritative. **Only commit soil debit for actual penetrated, positively worked cutting motion that passed the force/energy feasibility gate.** When blocked, apply reaction torque and keep terrain intact. For marginal cases reduce cut depth/advance to match available work; don't simply cap force while removing an unchanged volume.
6. Credit removed dry solids/water into a bucket payload whose mass, COM and fill are coupled into Jolt (gradual COM evolution or calibrated bucket payload body). Bucket scoop capacity is true interior geometry/curl orientation, not a magic scalar; 0.24 m3 prototype size is preserved until actual model dimensions are measured.
7. When lip and bucket reorient, gravity/spill and adhesion determine escaped material; carry through particle and pile solver; physically load trailer bed via spatial contacts. Soil must never be transported via scene reload or just emitter visuals.
8. Commit one deterministic ledger transaction per contact substep. If Jolt update/soil update disagree, flag a collision/energy regression; never silently delete mass.
9. Resolve material state and dynamic ground traction from the same active cells, so repeated passes create actual ruts.

**Important implementation note:** Jolt internal joint solving is not coupled to an external iterative soil constraint automatically. Start with conservative predictor/corrector based on previous-solved motion and capped removal; measure error. If stiffness or contact latency causes impossible cuts, introduce native constraint/correction path or smaller substeps. The architecture is an engineering-inspired reduced-order model, NOT a claim of DEM/FEM/MPM fidelity.

## Multi-resolution terrain
- Map: 250x250 m existing design, lightweight coarse collision/render outside work area; maintain landscape matte/parallax system as decoration only.
- Interactive pad first: preserve current 18x18 m soil pad for a contained benchmark. Then tile local mutable terrain into 16 m chunks with explicit seamless collision boundaries.
- Far cells: ~0.25–0.5 m, medium near machine ~0.10 m. Tooth-interaction patch at 0.01–0.03 m **contact sampling** and ~0.025–0.05 m optional active deformation grid over 3–5 m local region; no demand to store an entire 250 m map as 2 cm voxels.
- Stratigraphy stored as variable-depth layers (5–20 cm initial vertical breakpoints, refined at cut boundary); active high-detail cut-face mesh only within tool ROI. Local SDF geometry for overhangs/big undercuts is a later optional branch.
- Dirtied local chunks/tiles only. A delayed bulk heightmap update is allowed ONLY when an immediate contact proxy prevents Jolt-ground interpenetration and continuous thin tools.
- Avoid globally colliding 140 m flat floor under actively excavated terrain; use hole/collision region segmentation with robust seam tests.

## Material behaviour
- Topsoil: root binding and small aggregates, soft until compacted; lighter than wet clay.
- Loose dry sand: low cohesion, repose/slip and segregation; possible high penetration friction depending confinement.
- Gravel/rock fill: larger falling grains, bridging, rolling and high abrasion; no infinite particles.
- Moist clay: cohesion, apparent steep cut faces, clods, adhesion to bucket; saturation reduces effective stress/traction, not automatically all shear strength.
- Compacted material: higher density / reduced void ratio, higher penetration resistance; rebound and bearing capacity model.
- Rock/roots: discrete Jolt collision objects with soil-constrained sockets; extract/roll/drag under threshold forces; breakage only with justified force and material parameters.
- Slumping/collapse: check effective friction and cohesion versus loading, wet state, depth and local geometry; conserve dry mass; avalanches cascade locally.
- Wetness scope: soil moisture, mud, traction and strength only. No full hydrogeology, fluid flooding or SPH water simulation in v2.

## Machine-ground interaction
Contact patches per track need estimated ground normal pressure `p=F_n/A_contact`, slip and shear resistance. Couple pressure-dependent bearing deformation, plastically accumulated rut depth, material displacement ahead of track, and local compaction. The current four track probes are retained initially but supported by expanded contact-area samples. Distinguish traction breakdown from mechanical power limit; overloaded bucket may stall, push, drag or roll material while the machine creeps or bogs.

## Frame/event schedule (proposal)
- Physics: retain 120 Hz Jolt initially (8.33 ms step). Do not change tick rate unmeasured.
- Each tick: receive machine inputs -> sample terrain/material contact and actuator constraints -> issue Jolt forces/motors -> after motion snapshot commit validated displacements and mass transactions -> update dirty regions and telemetry.
- Loose material: 30–60 Hz event/adaptive steps; moving render at game frame rate; high-speed collisions substep or swept-test to avoid tunnelling.
- Local slope failure ~10–30 Hz and when freshly cut / loaded (tune).
- Visual chunk meshes may rebuild 10–30 Hz; Jolt near-tool collision must stay consistent with active terrain; global collider rebuild frequency is not a surrogate for correctness.
- Frame-rate objective: ≥60 fps scene on nominated Windows hardware under representative load, not just empty yard. At 120 Hz physics, target ≤8.33 ms per full simulation step with meaningful p95 margin; tune soil path to ~1–2 ms median on reference PC as an **initial profiling budget, not achieved measured performance**.
- Deterministic golden seeds; bounded parcel count and graceful LOD. Quality slider reduces *far-field* detail, not physical mass loss.

## Implementation order (gated)
P0: baseline capture; scripted genuine Godot tests and telemetry; make independent workpad diggable below original grade; verify Jolt track entry and collision seams.
P1: dry mass + water ledger and stratified material model, including bulk volume changes without mass errors; transaction rollback.
P2: multi-point tooth/edge geometry, force-before-cut, failed/stalled cut test, bucket mass and COM coupling; retain simple hydraulic model as fallback.
P3: geometry-dependent hydraulic cylinders, work/pressure/flow budgeting, real hose/valve approximations, force/energy telemetry; calibrate to KX080 known geometry.
P4: local multiresolution deformation, soil wedge/collapse, moisture/adhesion, mixed soils, particle->pile transfer, whole-pad consistency.
P5: track rutting, terramechanics, bogging, grader/blade/compactor contact; discrete rocks/roots.
P6: full job-chain scenario and persistence; tune art and particles AFTER physical pass.
P7 (optional): 3D SDF undercuts, large free fragments, more expensive granular simulation only where justified.

## Acceptance policy
Use `docs/PHYSICS_V2_TEST_PLAN.md` as the executable-test design. Every material transaction must balance. A v2 claim requires actual Godot/Jolt Windows measurements plus CSV traces; source checks and Python surrogates are **not** Godot validation.

## Sources
- Godot HeightMapShape3D 4.6: https://docs.godotengine.org/en/4.6/classes/class_heightmapshape3d.html
- Godot compute shader renderer constraint: https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html
- Existing repo files linked above.
