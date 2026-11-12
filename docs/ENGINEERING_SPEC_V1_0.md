# Durham Park Sandbox — Engineering Specification v1.0
## Coupled soil mechanics and Kubota KX080-3 excavator hydraulics

**Date:** 12 November 2026  
**Status:** Engineering design baseline; not a claim of validated real-time performance  
**Target:** Godot 4.6, Jolt Physics, Windows, nominal 120 Hz physics / 60 fps graphics  
**Repository reviewed:** `sn97ty8yn4-jpg/landworks`, `main`, 12 November 2026  
**Integration approach:** Preserve existing Godot scenes, regression tests, machine controls and artwork; incrementally replace provisional force and soil models.

### 1. Design decision

Build an **engineering-inspired, two-way coupled hybrid simulator**, not a cinematic digging animation and not a full per-grain discrete element solver. The hydraulic system limits available implement force and speed. The soil supplies penetration/cutting reaction, can resist motion and can prevent excavation. Soil is only removed when the physical bucket's geometry actually sweeps material **and** the hydraulic/soil contact solution permits that cut. Removed material must remain accounted for as bank material, bucket contents, falling/flowing parcels, deposited fill or explicitly recorded off-pad export.

**Non-negotiable behaviour:** A weak or stalled bucket cannot magically remove earth; a machine that cannot lift an object may still drag, roll or push it; the terrain is physically traversable and can be cut below its original surface; soil does not materialise or disappear during compaction, dumping or collapse.

**Explicit non-goals for v1.0:** full DEM/SPH/MPM; fluid-pressure CFD; real-time rigid-body grains by the thousand; tunnelling and overhangs; calibrated machine operator-training or rated-lift certification; physical hydraulic fluid temperature/cavitation; detailed line-hose dynamics. Such features may follow once the core model meets acceptance tests.

### 2. Starting point and immediate discrepancies

**Verified from repository source (existing, not to be thrown away):**

- `project.godot`: Jolt and 120 Hz, Godot 4.6 compatibility renderer.
- `landworks/scripts/earthworks.gd`: 18 × 18 m pad; `81×81` heights; `0.225 m` spacing; gravel and clay; 800 mobile soil parcels nominally `0.00075 m³` each; `0.24 m³` provisional bucket limit; slope slump and dynamic heightmap collision every ~`0.18 s` when dirty.
- `landworks/scripts/excavator_work_lab.gd` and `sandbox_excavator.gd`: approximately 8,170 kg machine assembled from rigid links and powered Jolt hinges, with separate excavator tracking and slewing; torque limits of 75 / 45 / 20 kN·m for boom/stick/bucket are current **assumptions**, not OEM values.
- `landworks/scripts/hydraulic_model.gd`: approximate shared flow allocator of 144 L/min, 29.4 MPa, 36 kW and fixed assumed torque leverage (`CYLINDER_MOMENT_M3`); presently a hydraulic-power *proxy*, not cylinder geometry or chamber pressure simulation.
- `landworks/scripts/sandbox_world.gd`: actual bucket-lip motion calls `earth.cut_sweep` and credits bucket volume; only afterwards applies a reaction force to the Jolt bucket. The current 140 m ground box remains physically under the editable earth pad.
- Existing smoke tests include `hydraulic_smoke.gd`, `earthworks_smoke.gd`, `earthwork_machine_smoke.gd`, and CI. Preserve and extend them; do not erase historic baselines.

**Required corrections before claiming realistic excavation:**

1. **Force causality:** `cut_sweep` currently removes volume first and applies a capped reaction later. Change to propose → resist/allocate → verify movement → commit. An underpowered tooth must stop or skid; it cannot excavate by repeated false-positive callbacks.
2. **Trench clearance:** The flat ground box overlaps the dig zone. Replace that section of the floor with a true opening and a continuous seam so trenches below `y=0` do not collide with invisible support geometry.
3. **Hydraulic circuit pressure:** The current `29.4 MPa` is documented as the *travel circuit* setting in a transcribed KX080-3 workshop manual. That reference lists **27.4 MPa** for the load-sensing front-attachment circuit and **20.6 MPa** for P3. Use distinct settings and verify by machine serial/variant. Do not use travel relief pressure as general bucket-cylinder pressure.
4. **Terrain substrate:** Existing `ground_volume_m3()` counts above `BASE_HEIGHT`, preventing meaningful excavation of undisturbed ground below the baseline. Add a depth-resolved material column, bedrock bound and a mass ledger.
5. **Bucket material mixture:** The current bucket remembers the dominant material only. Track volume and mass of each constituent; preserve mixtures, water and future rock fragments.
6. **Geometry:** A single bucket-lip sweep with hard-coded 0.76 m width is insufficient for variable fill and individual teeth. Replace with a segmented swept bucket cutting-edge and shell approximation.

### 3. Machine parameter register

**Manufacturer KX080-3 baseline:** operating weight approximately **8,170 kg** (including 75 kg operator); standard bucket nominal **0.25 m³**; bucket width 700 mm without side cutters / 800 mm with; overall width 2,200 mm; max published bucket breakout **65.2 kN**; engine published 47.8 kW at 2,000 rpm; maximum digging depth 4.29 m. These describe the *KX080-3* rather than the related KX080-3S and must be checked against the actual configured machine.

**Hydraulic source values requiring serial confirmation** (from online transcription of a KX080-3 workshop manual):

| Parameter | Design register | Source/confidence |
|---|---:|---|
| P1 + P2 nominal delivery | 72 + 72 L/min at rated speed | workshop-manual transcription; reference ceiling, not simultaneous all-functions promise |
| P3 nominal delivery | ~66.6–67 L/min | workshop-manual transcription |
| Front attachment LS system pressure | 27.4 MPa | workshop-manual transcription; provisionally preferred |
| Travel circuit pressure | 29.4 MPa | workshop-manual transcription; do **not** apply to front attachment |
| P3 system pressure | 20.6 MPa | workshop-manual transcription |
| Boom cylinder bore / rod / stroke | 115 / 65 / 878 mm | workshop-manual transcription; verify machine and boom variant |
| Arm cylinder bore / rod / stroke | 100 / 60 / 914 mm | workshop-manual transcription; verify arm variant |
| Bucket cylinder bore / rod / stroke | 90 / 55 / 741 mm | workshop-manual transcription; verify linkage and attachment |
| Engine-to-oil continuous power | initially 36 kW | **tunable simulator assumption**; not OEM value |
| Current motor cap baseline | 75 / 45 / 20 kN·m | **existing simulator assumptions**; replace with cylinder geometry |
| Bucket store volume | 0.24 m³ currently | existing prototype; reconcile measured shell volume with OEM nominal 0.25 m³ |

**Source hierarchy:** exact machine measurements / serial-specific documentation > KX080-3 manufacturer material > workshop manual transcript > sibling KX080-3S > assumptions. Record source, units, variant, confidence and test status with every parameter. The source is never an excuse to substitute an arbitrary constant without provenance.

### 4. Core simulation architecture

```text
Player / scripted controls
          │ command [-1,+1] and engine setting
          ▼
HydraulicPumpAndValveSolver ◄── load torques + cylinder geometry
          │ available cylinder forces / flows / power
          ▼
Rigid Excavator (Jolt) ◄──── SoilContactSolver
   boom / arm / bucket         ▲    │ contact normal, friction, resistance
   upper / tracks              │    │ feasible cut proposal
          │ actual swept teeth │    ▼
          └───────────────────►│ TerrainColumnStore
                               │ material debit/credit ledger
                               ▼
                      BucketLoadStore ──► MobileSoilParcels
                               ▲                 │
                               └──── deposit / slump / fill
```

A central `EarthmovingCoordinator` owns the update order and transfers typed results between subsystems. Existing machine articulation stays a physical Jolt mechanism; no soil update teleports a machine, changes its target transform, or injects a large artificial impulse.

**Modules proposed for later Codex integration:**

- `hydraulics/hydraulic_config.gd` — versioned source-labelled parameters.
- `hydraulics/cylinder_geometry.gd` — pin positions, stroke and linkage Jacobians; geometry validation.
- `hydraulics/pump_valve_solver.gd` — pump allocation, valve controls, relief and engine power constraint.
- `soil/soil_material.gd` — density, cohesion, internal friction, moisture, compaction, swell and water.
- `soil/terrain_column_store.gd` — layered cells and authoritative mass state.
- `soil/tool_contact_solver.gd` — swept tooth/edge geometry, resistance and failure region proposals.
- `soil/soil_motion.gd` — discrete volume-bearing parcels, deposits and slope failure.
- `soil/material_ledger.gd` — dry solids, water, bulk volume and exported mass.
- `integration/earthmoving_coordinator.gd` — coupling, bounded work application and telemetry.

These are proposed interfaces; do **not** replace existing scripts before creating adapters and retaining smoke-test compatibility.

### 5. Soil model

**5.1 Spatial representation.** Retain the 18 m experimental soil pad with 225 mm baseline resolution for the first validation. Move from a single height and material ID to **height + depth-ordered stratigraphic columns**. Each column is a set of segments (`material_id`, top/bottom elevations or solid mass and porosity, dry-mass kg, water-mass kg, compaction state, strength parameters). Store a configurable intact substrate below the original surface, provisionally several metres deep with an explicit bottom refusal layer. A heightfield can represent open trenches but **not** undercuts or caves; these are excluded from v1.0. Later place active soil chunks only where digging occurs within the ~250 × 250 m playable area.

**5.2 Mass, moisture and volumetric change.** Use conservation of **dry solids mass and water mass**, rather than a constant bulk volume. Loose spoils swell because their bulk density decreases; mechanically compacted fill loses bulk volume but does not lose dry soil. At a transfer, use `mass = in_situ_bulk_density × in_situ_volume` with water partition accounted for; compute loose volume using the loose-state bulk density. The ledger separates solid grains, pore volume, water and bulk volume. Never treat density and moisture as interchangeable.

**5.3 Materials.** Support topsoil, cohesive silty clay, wet mud, compacted fill, granular sand/gravel and mixed material; buried stone inclusions may become separate collision-bearing rigid bodies above a size threshold. Keep material parameters data-driven. Representative *initial tuning ranges*, not geotechnical test results:

| Material | Bulk density, kg/m³ | Effective friction angle | Cohesion / behaviour |
|---|---:|---:|---|
| Loose dry granular soil | 1,450–1,850 | 28–38° | near-zero effective cohesion; granular runout |
| Moist silty clay | 1,550–1,950 | 18–32° | cohesive, cut faces briefly stand |
| Saturated soft mud | 1,500–1,950 | 10–25° | reduced effective stress; plastic remoulding |
| Compacted granular fill | 1,750–2,150 | 32–42° | higher penetration resistance and smaller void ratio |

The ranges are calibration placeholders, not authoritative values for a particular soil sample. Wetting should not simply multiply an arbitrary stiffness; water modifies effective stress, undrained strength/adhesion, density, pore pressure and traction through separate parameters.

**5.4 Soil strength.** Use a reduced-order Mohr–Coulomb inspired shear law:

`tau_max = c_eff + max(sigma_n - u, 0) * tan(phi_eff)`

where `tau_max` [Pa] is local shear capacity, `c_eff` [Pa] is effective cohesion, `sigma_n` [Pa] is total normal stress, `u` [Pa] is pore-water pressure and `phi_eff` is effective friction angle. Start with pressure and failure coefficients calibrated against observed digging, not a claim to solve complete finite-element stress fields. An optional compact passive-wedge surrogate can add `0.5 * Kp * gamma_eff * width * depth²` [N], with `Kp=(1+sin(phi))/(1-sin(phi))` for a simple cohesionless idealisation. Avoid double-counting passive and shearing resistance; identify which contact scenario uses which term.

**5.5 Failure / movement.** Slumping transfers mass between neighbouring columns when friction/cohesion capacity is exceeded, taking into account moisture, surcharge, excavation beneath the slope and time. Use conservative face-to-face mass flux; do not add/subtract vertex heights without the proper area/density conversion. Run lightweight iterative local relaxation only on dirty cells. Wet clay should slump progressively after support removal; gravel should flow to a shallower repose angle. Buried rocks should be displaced or wedged by contact forces, not vanish on touch.

### 6. Bucket–soil contact mechanics

**6.1 Contact geometry.** The articulated bucket needs validated pivot and tooth-tip transforms, side plates, cutting edge, open shell and approximate swept occupied volume. Divide teeth/edge into 5 or more lateral contact elements. Each contact reports point, normal, sweep, local penetration, working width, material layer, proposed excavation volume and applied normal/tangential force. Tooth contacts cut first; shell/side plates add drag and adhesion. Mesh shape is separate from efficient collision probes.

**6.2 Proposed resistance.** For each element use an effective working face and depth to estimate `F_shear = A_face * tau_max`, add calibrated passive-wedge and adhesion terms and velocity-dependent resistance where justified. Produce force vector opposite penetration/sliding and a moment at the actual contact point. Force estimates must be continuous as the tooth first touches ground and bounded by physical response; do not arbitrarily hard-cap aggregate resistance at the existing 22 kN. A very hard obstruction can stall the actuator.

**6.3 Force gate and cutting work.** A candidate excavation may be committed only if actual constrained motion enters the ground, the hydraulic force solution can overcome the contact resistance, and the required cutting work is supplied. Track:

`W_available = sum(max(0, F_contact · v_tool_opposition) * dt)`

with a carefully defined sign convention: *positive* supplied work is actuator force doing work against soil resistance. Compare it with `W_required = F_resist * cut_distance` for a candidate incremental sweep; limit removed material to a feasible fraction if the available work is insufficient. The force/energy gate prevents material creation or deletion while the implement is stalled. Use the actual post-Jolt swept trajectory to confirm the geometric overlap; do not commit based only on joystick command or motor target.

**6.4 Loading.** Bucket capacity is a function of validated open-shell volume, angle, cohesion and fill fraction. Track each material constituent separately (`dry_mass_kg`, `water_mass_kg`, `bulk_volume_m3`). Material entering the bucket transfers weight to the physical bucket/implement assembly via a moving payload mass/force and centre-of-mass approximation; ensure changing payload mass does not inject momentum. Oversize rocks remain discrete bodies or are explicitly rejected. A full bucket cannot continue accepting soil; extra loosened soil remains as a moving wedge/stockpile rather than disappearing.

**6.5 Discharge.** The existing R-key manual dump may remain for regression tests, but production behaviour uses bucket attitude, material friction/cohesion, opening geometry and gravity. Dry gravel releases sooner than cohesive mud. Material moves as volume- and mass-bearing parcels, settles to a deposit, and is progressively consolidated. Use the present 800-parcel cap as a benchmark, not an immutable limit; exceeding it should merge parcels conservatively or postpone discharge, never silently delete mass.

### 7. Hydraulic model

**7.1 Mechanism.** Model boom, arm and bucket as rigid bodies with physical pins. Define per-cylinder moving mount points in each parent body and a validated four-bar linkage for the bucket where fitted. Calculate cylinder length `L(theta)` from pin coordinates and stroke limits. The signed effective joint moment arm is `dL/dtheta`; joint torque is `T_joint = F_cylinder * dL/dtheta`, or the corresponding Jacobian mapping for multiple cylinder/linkage degrees of freedom. This replaces the current fixed `CYLINDER_MOMENT_M3` torque assumption. Approximations are allowed only until geometry is measured.

**7.2 Directional cylinder force.** For bore diameter `D` and rod diameter `d`:

`A_cap = pi * D²/4`; `A_ann = pi * (D² - d²)/4`.

Signed extension force: `F_cyl = p_cap * A_cap - p_rod * A_ann - F_friction`, incorporating opposing load, seal friction and the chosen sign convention. Reverse the chamber roles for retraction. Use Pa, m² and N internally; MPa, mm and L/min only in UI/config. At 27.4 MPa, cap-end theoretical forces **before return pressure/losses** are approximately 285 kN for a 115 mm boom piston, 215 kN for a 100 mm arm piston and 174 kN for a 90 mm bucket piston. These are **cylinder forces, not available bucket-tip digging force**.

**7.3 Flow, speed and power.** For each driven chamber, `Q = A * abs(dL/dt)` and `P_hydraulic = sum(Δp * Q)`; in compatible display units `P[kW] = p[MPa] * Q[L/min] / 60`. Allocate actual P1/P2/P3 circuit contributions according to the machine schematic, simultaneous valve commands and travel demands. Do not assume each cylinder receives all 144 L/min or add P3 automatically to that flow. Bound oil power by the available engine-to-hydraulic power at current engine speed/torque. Simultaneous boom+arm+bucket operations should visibly slow when flow or power limited.

**7.4 Pressure and hold.** Keep separate load-sensing, travel and P3 pressure ceilings; approximate hydraulic load sense, deadband, spool metering and ramping. Pressurisation should depend on cylinder external load, not simply maximum requested speed. A centred valve and load-holding function may sustain a static payload at essentially zero flow; do not force a loaded boom to collapse because commanded flow is zero. Relief must prevent further forced movement when the load requires pressure above the applicable ceiling, while mechanical support and ground contact can still prevent falling.

**7.5 Motor integration.** Until explicit cylinder constraints have passed performance benchmarks, convert cylinder forces through geometric Jacobians into joint torques and enforce them through Jolt joint motor impulses/limits. Apply consistent reaction through the real rigid-body chain. Keep joint target velocity subordinate to allowed hydraulic flow and torque. Measure per-tick impulse conversion at 120 Hz; do not assume the numerical hinge-motor limit directly equals pressure.

### 8. Two-way coupling contract and update order

Use a **central coordinator**, not competing `_physics_process` handlers whose order is implicit. The initial system can be semi-implicit at 120 Hz with one-tick delayed observations; only adopt more expensive iterative coupling if needed for stability.

1. Sample player commands, engine RPM, real body transforms, pin positions, joint angles/velocities and active soil contacts.
2. Build a **non-mutating** candidate tooth/edge sweep and soil resistance proposal using the expected short-step motion; include material identity, wetness and support failure.
3. Compute hydraulic pressure/flow/torque allocation, gravity moments, current bucket payload and contact resistance. Resolve the feasible velocity/force at each axis and apply equal-and-opposite reaction to the bucket at contact points (and through articulated joints).
4. Advance Jolt for the fixed step. Inspect **actual** swept tooth trajectories and solver contact response; prevent unrealistic penetration. If soil resistance exceeds actuator capability, movement must stall or slide, not extract volume.
5. Commit only approved removed dry mass/water from terrain columns to bucket/spoil; update payload mass and centre of mass without violating momentum conservation. Resolve progressive face failure and falling/rolling rocks separately.
6. Batch dirty terrain mesh and heightmap collider updates at a validated frequency, with an explicit maximum collision lag. Log ledger and energy/pressure/impulse anomalies.

**Critical implementation note:** Godot frame callbacks and engine integration ordering must be experimentally verified. The above is the intended causal dependency, **not** a claim that `_physics_process` alone permits an exact after-solver callback. An implementation may use Jolt force integration callbacks plus the next physics tick's observed sweep, and must include a consistency test for one-tick latency.

Suggested return structures:

```text
SoilCutProposal {
  contact_points[], soil_layer_ids[], swept_volume_m3,
  resistance_force_world_N[], torque_world_Nm[],
  required_work_J, candidate_dry_mass_kg, candidate_water_mass_kg
}
HydraulicState {
  pressure_ls_Pa, pressure_p3_Pa, pressure_travel_Pa,
  flow_p1_m3s, flow_p2_m3s, flow_p3_m3s, oil_power_W,
  cylinder_forces_N{}, joint_torque_limits_Nm{},
  joint_speed_limits_rads{}, relief_open{}
}
SoilTransferReceipt {
  id, geometry_sweep_id, committed_dry_mass_kg,
  committed_water_mass_kg, bank_volume_removed_m3,
  loose_volume_added_m3, destination, signed_work_J
}
```

### 9. Collision, coordinate and performance rules

- All world dimensions use metres, mass kg, forces N, moments N·m, pressure Pa, power W, angular speed rad/s and fixed timestep seconds. Document transforms in world/local space; keep tooth offsets tied to the real bucket `RigidBody3D` and rig pivots.
- Remove the sandbox floor collision **under** the editable pad, retaining continuous support elsewhere. Build seam tests across every side, including crawler entry at the present approach lane. No hidden second collider at `y=0` may block trench formation.
- Keep a heightfield collider and indexed mesh per **active chunk**; outside, use simpler static terrain. Batch updates, avoid rebuilding the entire future 250 m landscape after every bucket movement. Heightfield collision is a suitable open-terrain representation, but cannot generate caves or overhangs.
- Preserve existing Godot 4.6 Compatibility renderer and Jolt machine contacts. Do not switch the physics engine, renderer or physics tick rate during this upgrade without controlled A/B benchmarks.
- Maintain 120 Hz machine dynamics, with soil contact evaluated at the physics tick. Start with dirty terrain visual/collider updates at 10–15 Hz *while actively digging*, subject to benchmarks; preserve conservative contact when collider data lags.
- **Initial performance targets (unverified):** 60 fps graphics, 120 Hz physics on a mid-range Windows gaming PC; average soil+hydraulic bookkeeping at or below ~2 ms per rendered frame with no recurrent >4 ms spikes; 800 active parcel benchmark; no per-frame allocations proportional to all 250 × 250 m terrain cells.
- Use packed arrays, pooled parcels and local dirty rectangles; consider GDExtension/native acceleration only if measured profiling indicates a sustained need. Keep deterministic test seeds and an optional lower-fidelity mode.

### 10. Acceptance criteria and test matrix

| ID | Test | Pass / failure criterion |
|---|---|---|
| H-01 | Static cylinder geometry | `L(theta)` continuous; derivative/Jacobian agrees with finite differences within 2% away from singularities; stroke stops respected |
| H-02 | Pressure segregation | Front attachment never uses travel-only 29.4 MPa cap; applicable 27.4 MPa reference ceiling is respected within solver tolerance |
| H-03 | No-load motion | Boom/arm/bucket move smoothly in free air; no uncommanded rotation, teleportation or overspeed |
| H-04 | Loaded stall | Increase opposing bucket contact load; at insufficient hydraulic force bucket stalls/slides; hydraulic pressure reaches applicable limit rather than deleting soil |
| H-05 | Shared power | Combined hydraulic oil power never exceeds configured engine oil-power budget; simultaneous motions receive finite shared flow |
| H-06 | Static load hold | With neutral valve, configured holding mechanism keeps a test load stationary within a provisional 2° joint-drift tolerance over 30 s; no unbounded energy injection |
| S-01 | Soil mass | Dry solids and water independently balance to within the greater of **0.1 kg or 0.25% of transferred mass** across a full cut→carry→dump cycle |
| S-02 | Below-grade trench | Cut a trench at least 0.5 m below surrounding baseline, with no collision against original flat floor |
| S-03 | Unpowered cut | Command a sweep into clay with hydraulic torque suppressed: no soil transfer beyond numerical tolerance, machine cannot phase through bank |
| S-04 | Variable hardness | With fixed tool input, compact/wet/hard material exhibits measurably different resistance, flow, failure or traction from dry gravel |
| S-05 | Bucket capacity | Bucket never exceeds measured geometric capacity; displaced overfill remains in terrain/mobile stockpile ledger |
| S-06 | Mass versus bulk volume | Excavating/swelling/compacting changes bulk volume but keeps solid and water masses conserved |
| S-07 | Slope failure | Undercut cohesive bank fails progressively; repose and settlement depend on strength/moisture; no one-frame global collapse |
| S-08 | Material mixture | Gravel, clay and wet material retain separate mass inventories through mixing, loading, discharge and deposition |
| C-01 | Coupled cut | 120 Hz actual Jolt bucket sweep creates resisting contact **before/while** cutting; insufficient force prevents advance; adequate force enables measurable extraction |
| C-02 | Machine reaction | Ground reaction propagates through bucket/stick/boom/upper to chassis; base tips/slips if physics requires, never anchored invisibly |
| C-03 | Overweight interaction | 1000–1500 kg test objects may resist lifting but remain pushable, draggable or rollable subject to ground friction |
| C-04 | Pad access | Excavator drives onto and off editable pad from current sandbox approach, without an artificial collision lip |
| P-01 | Runtime stability | 10 minutes of repeatable excavation without NaNs, negative masses, collider explosions or cumulative uncontrolled memory growth |
| P-02 | Real performance | 60 fps / 120 Hz target recorded on actual Windows machine; test report contains frame timings and dirty-collider cost (not simulated numbers) |

**Gate:** existing tests must continue to pass; if a test is obsolete, replace its assertion explicitly with a stronger equivalent and document the migration. Never assert success from structural checks, Python surrogate traces or editor load alone. Save machine/soil telemetry CSVs and an execution environment record for each measured test.

### 11. Development order for Codex

**Stage 0 — Freeze baselines and add instrumentation.** Pin known-good commit; run existing Godot headless/Windows tests; record frequency, motor torque, contact force, volume balance, bucket contents and frame timing. Confirm Jolt version, cylinder pin transforms and actual compilation. Do not change simulation yet.

**Stage 1 — Make excavation spatially valid.** Remove colliding floor beneath the pad; introduce below-grade substrate/columns; add the 0.5 m trench and pad-access tests. Keep existing gravel/clay prototype functional.

**Stage 2 — Physically parameterise hydraulic cylinders.** Create source-labelled hydraulic config; distinguish 27.4 / 29.4 / 20.6 MPa circuits; model chamber areas, stroke and geometry-derived moment arms; enforce pump power and directional flow. Initially keep a compatibility adapter to current `hydraulic_model.gd` return dictionary.

**Stage 3 — Fix causality and tool geometry.** Split destructive `cut_sweep` into non-mutating proposal and authorised commit. Replace single-lip removal with teeth/edge sweep. Couple resistance before material transfer, account for work and preserve reciprocal Jolt forces. Add underpowered-tool test.

**Stage 4 — Realistic material handling.** Extend ledger to dry mass, water and swell; correct bucket composition, load-derived mass/inertia and automatic dumping; implement local failure and compacted fill. Keep mobile parcels pooled and conserved.

**Stage 5 — Calibrate and optimise.** Check against known breakout force scale, OEM reach/dig depth, measured machine dimensions and field observations; benchmark actual Windows/Jolt runtime; only then consider native code or more granular material solver.

Every stage should be a small independent pull request; preserve current prototype in a fallback scene and avoid unrelated machine-art, landscape or controller refactors.

### 12. Explicit open measurements / calibration gates

1. Confirm serial-specific **KX080-3** variant, bucket dimensions, quick hitch and whether the arm is 1.75 or 2.10 m; the published 0.25 m³ bucket is not proof that the current modeled shell has that internal volume.
2. Measure or obtain cylinder mounting pin centre coordinates for the boom, arm and bucket linkage across several poses. Diameter/stroke alone does not determine joint force.
3. Verify circuit schematic, engine RPM response, boom holding valve behaviour and pressure settings for that machine. The workshop-manual data is a reference, not a safety certification.
4. Collect representative loose and in-situ soil bulk density, water content, compaction state, and a few observed penetration / cut comparisons to calibrate the simplified material law.
5. Run actual Godot Windows tests and compare trace files. Until then, every target in this document is a **proposed acceptance criterion**, not a verified achievement.

### 13. Source register

**Machine:** Official Kubota KX080-3 listing — https://kubota.com.mm/en/products/mini-excavator/kx080-3/index.html  
**Related variant:** Kubota Australia KX080-3S (cross-check only) — https://kubota.com.au/product/excavator-kx080-3s/  
**Hydraulic workshop manual transcription:** https://manualzz.com/doc/54714335/kubota-kx080-3-workshop-manual — variant and source transcription must be verified before final calibration.  
**Godot:** https://docs.godotengine.org/en/4.6/classes/class_heightmapshape3d.html and https://docs.godotengine.org/en/stable/classes/class_physicsserver3d.html  
**Repository:** https://github.com/sn97ty8yn4-jpg/landworks — existing `docs/EARTHWORKS.md`, `docs/V06_FIELD_TRIALS.md`, `landworks/scripts/hydraulic_model.gd`, `earthworks.gd`, `sandbox_world.gd`.

**v1.0 authoring status:** Specification drafted from repository inspection and external technical references. No code edits, tests, simulation execution, calibration measurements or repository commits are claimed in this document.
