# Durham Park Sandbox — Material Mechanics Specification v1.1

**Project:** `sn97ty8yn4-jpg/landworks` (Godot 4.6, Jolt Physics)  
**Date:** 12 November 2026  
**Scope:** Detailed material behaviour for the coupled soil/hydraulic architecture in *Engineering Specification v1.0*  
**Status:** Design specification and executable **offline** Python reference; **not** integrated into or benchmarked inside Godot.  
**Audience:** Codex implementer, simulation engineer, Godot developer, eventual field-test calibrator.

## 0. Decision and required experience

A soil is not a visual type or an unchanging cutting-pressure constant. It is an **evolving mixture of solid grains, pore water, air and larger inclusions** with a history of disturbance and compaction. The simulator must distinguish **bank**, **cutting failure wedge**, **bucket**, **falling spoil**, **settled loose fill** and **recompacted ground**. Each transfer conserves independently tracked dry-solid mass and water mass. Changes in volume reflect changes in pore space and structure, not matter appearing or disappearing.

**Priority experience:** A dry gravel pile pours from the bucket and runs out; moist silty clay shears in blocks, forms temporary faces and collapses progressively; wet sticky clay smears on teeth and may cling in the bucket; saturated soft mud loses bearing capacity, deforms widely and may require shaking/rotation to discharge; compacted fill is harder to penetrate than the same loose material, and successive crawler passes leave depressions and alter the next dig. Rocks obstruct or move under force and do not vanish through a material label.

**Engineering boundary:** Not a finite-element/MPM/DEM geotechnical simulator, not a groundwater-flow CFD model, not intended for excavator certification or actual earthworks design. The model is engineering-inspired and deliberately reduced-order, with calibration and error metrics visible.

## 1. Existing source integration — do not rebuild blindly

`landworks/scripts/earthworks.gd` currently implements an 18 m pad of 81×81 height samples spaced 0.225 m; material IDs are a byte for gravel/clay; each cut lowers heights; 800 volume-bearing 0.75 L parcels represent loose spoil; slope repose is represented by moving height between neighbours. `landworks/scripts/sandbox_world.gd` stores a single bucket volume and one dominant material name; `earthworks.cut_sweep()` removes soil **before** testing machine force; `hydraulic_model.gd` is an approximate flow allocator. Existing smoke tests verify a first-order volume ledger, not material physics.

Design v1.1 as a **strangler extension**: retain the scenes, controls, visual layer, and existing tests; add versioned material store and new tests behind an adapter. Preserve a working fall-back mode until the new coupled path passes all acceptance gates.

## 2. Authoritative mass, pore volume and water state

### 2.1 Store conserved variables, derive bulk quantities

For every material-bearing entity (bank cell layer, mobile parcel, bucket inventory, wedge, rock) store **by constituent**:

- `dry_mass_kg[material_id]` — mass of dry mineral/organic solids; each constituent separately.
- `pore_water_kg` — water retained in the soil pores.
- `free_water_kg` — water exceeding pore capacity, carried separately in puddles/runoff/storage.
- `void_ratio e = V_void/V_solid` — the current volume of voids relative to volume of solid grains.
- `damage D ∈ [0,1]` — fraction of destructured/remoulded bond/peak strength.
- `state` — intact bank, shearing wedge, loose parcel, in bucket, freshly placed, compacted, rigid rock, etc.
- `history` — accumulated plastic shear strain, dissipated compaction work, cycle count, last rewetting, deposition source and last contact frame, to the extent needed for behaviour and tests.

The grain density `rho_grain_i` is a material constant. Compute:

```
V_s       = sum_i(dry_mass_i / rho_grain_i)    [m3 solid grains]
V_void    = e * V_s                            [m3 pore space]
V_bulk    = (1 + e) * V_s                      [m3 ground/spoil envelope]
n         = e/(1+e)                            [porosity]
S_r       = pore_water_kg / (1000*V_void)      [degree of saturation, 0..1]
w         = pore_water_kg / sum_i(dry_mass_i)  [gravimetric moisture]
rho_dry   = sum_i(dry_mass_i) / V_bulk          [kg/m3]
rho_wet   = (sum_i(dry_mass_i)+pore_water_kg) / V_bulk
```

`rho_wet` excludes **free water** outside pore space. Water beyond `1000*V_void` must be transferred to `free_water_kg` or a separate cell's water store **without reducing the total ledger**. `S_r` must never be silently clamped while leaving excess water unaccounted. Free water contributes load when physically carried and may affect buoyancy/drag when a surface-water model is activated.

**No additional density variable is authoritative.** Dry/wet bulk density and bulk volume must derive from stored mass and void ratio. Do not mix wet and dry bulk density. Porosity and void ratio are different.

### 2.2 Mixtures and compaction energy

A mixed batch may contain multiple `material_id` dry masses. Mixed solid volume is additive, while the combined void ratio initially preserves total bulk volume. Disturbance can change void ratio, particle packing and strength; the granular composition remains recorded. Do not turn a mixture into whichever soil type dominates. Do not average *angles* or *strength* naively when evaluating interfaces; in v1.1 use carefully documented volume-weighted **proxies**, with contact strength controlled by whether a cohesive fines matrix dominates.

The initial offline reference `reference/material_reference.py` deliberately uses homogeneous representative mixed void ratio. The Godot production model needs depth ordering, contact-specific constituent fractions and clast-resolved behaviour where relevant.

### 2.3 Worked conservation example

For **0.100 m³** bank-volume of the illustrative `moist_silty_clay` profile, grain density = 2,650 kg/m³ and bank void ratio = 0.74:

- Solid volume `V_s` = **0.05747 m³**.
- Dry-solid mass = **152.30 kg**.
- Pore-water mass at 22% gravimetric moisture = **33.51 kg**.
- Bank wet mass = **185.80 kg**; bulk density = **1,858 kg/m³**.
- Initial pore saturation = **78.8%**.
- At loose void ratio `e = 1.00`, bulk volume rises to **0.11494 m³**, or **14.9% swell**, without changing mass.
- Under 25 kJ *dissipated, material-directed compaction energy* in the illustrative reference, bulk volume decreases to approximately **0.11029 m³**, again with no soil or water lost.

These values illustrate arithmetic and calibration knobs; **they are not measured properties of the user's NSW site**.

## 3. Data definitions and material profiles

Seven starting profiles are supplied in `material_profiles_v1_1.json`:

| Profile | Initial wet bulk density (approx.) | Initial moisture (% dry mass) | Effective c' (kPa) | Peak φ' | Behaviour target |
|---|---:|---:|---:|---:|---|
| loose_gravel | 1,725 kg/m³ | 3.5% | 1 | 39° | rapid discharge, angle-controlled runout |
| dry_sand | 1,619 kg/m³ | 2% | 0 | 34° | flowing granular wedge, little adhesion |
| moist_topsoil | 1,457 kg/m³ | 20% | 7 | 30° | rooting/aggregate structure, dark humic fines |
| moist_silty_clay | 1,858 kg/m³ | 22% | 18 | 26° | coherent cutting ribbons and temporary faces |
| wet_sticky_clay | 1,854 kg/m³ | 28% | 9.5 | 23° | high steel adhesion, remoulding and carryback |
| saturated_soft_mud | 1,792 kg/m³ | 40% | 2.7 | 20° | low bearing, extensive yielding, slow cohesive flow |
| compacted_fill | 2,029 kg/m³ | 9.5% | 13 | 38° | dense mechanical refusal, hard rut resistance |

**Provenance:** All numbers in this table and the JSON are **initial simulation tuning assumptions**, not geotechnical samples. Ranges and physical trends are informed by NSW soil physics guidance, NRCS density references and published geotechnical soil-strength examples. They must be adjusted against actual soil observations and should never be represented as material certificates.

Each profile also contains: particle density, bank/loose/minimum void ratios, drained residual friction and cohesion, **undrained shear strength** (separate, not summed with drained cohesion), soil–steel friction, adhesion, static/dynamic repose, permeability, plasticity index, compaction-energy calibration coefficient, disturbance strain scale, and coarse grading fractions. Color is purely a render attribute and cannot determine mechanical properties.

**Future layer assignment:** A plausible Hunter Valley alluvial worksite may have topsoil, silty clay, sand/gravel lenses, weathered subsoil and buried stones. Use these as configurable *scenario possibilities*, **not** a claim of sampled stratigraphy. Provide deterministic scenario presets with seeded spatial variation and lenses/pockets in 3D.

## 4. Moisture, suction, drainage and softening

Water must affect **several distinct mechanisms**, not simply a universal multiplier on hardness.

1. **Weight:** pore water increases the wet unit weight; buoyancy and pore water pressure affect effective stress when a water table is present.
2. **Drained shear strength:** `tau = c' + max(sigma_n - u, 0) * tan(phi')`. `u` is pore-water pressure [Pa], not the bulk gravimetric water content. Never subtract hydrostatic pressure twice.
3. **Unsaturated suction:** intermediate moisture can temporarily increase apparent cohesion. Treat as a calibrated bounded suction contribution, peaking at intermediate saturation rather than assuming dry or saturated soil is always strongest.
4. **Undrained soft-clay response:** when loading is much faster than drainage, use a **separate `s_u` [Pa] branch** and remoulded strength. Do **not** add undrained `s_u` to drained Mohr–Coulomb cohesion; choose appropriate response based on drainage time and loading regime.
5. **Plasticity and adhesion:** water near the plastic state can increase steel adhesion, smear, clod coherence and carryback even as cutting strength falls.
6. **Bearing and rutting:** wet weak soil loses normal load capacity and track thrust; repeated traffic can increase rut depth, while saturated conditions limit rapid compaction.
7. **Slow water movement:** if no groundwater solver exists, update scenario-controlled `pore_water_kg`, saturation and free-water stores at a lower rate. Don't invent rapid clay drainage or instant cross-site equilibrium.

**Minimal state transitions:** `dry → damp (capillary effects) → plastic/sticky → saturated soft mud` are behavioural regimes based on saturation and material plasticity, not a single smooth colour ramp. Reverse transitions need hysteresis because remoulded soil does not instantly regain intact structure merely by drying.

**Water injection gate:** For each addition, allocate to remaining pore capacity; transfer surplus to explicitly conserved surface water. A change in compaction can expel pore water to the same free-water ledger. Evaporation/drainage later must enter as a named boundary flux, with source/destination, not disappear.

## 5. Soil cutting: teeth, blade, sidewalls and failure wedge

### 5.1 Distinguish penetration, cutting, transport and scraping

Split bucket contact into individual tooth tips, cutting lip, side plates, shell interior and rear heel. One 0.76 m-wide point sweep is inadequate. Contacts are represented by sampled teeth/edge points or a signed swept section of an oriented convex cutting shape. The visual shell does not determine contacts unless geometry has been validated.

- **Penetration:** local normal indentation with predominantly bearing/crushing resistance; can stall at a firm inclusion.
- **Cutting:** tool advances, mobilises a failure wedge, shears it free and pushes it toward the bucket opening.
- **Scraping/grading:** a very shallow angle removes a thin surface layer with frictional resistance; no geometric penetration means no soil removal.
- **Shell drag:** soil friction on inner and outer bucket surfaces and additional resistance from sidewall pressure.
- **Clod fracture:** cohesive wedge separates into discrete larger clods when strain or tensile/shear criterion is exceeded.
- **Oversize stone:** the stone imposes a rigid collision and wedging load; the bucket must push/roll/extract or work around it, not consume it into a scalar soil mass.

### 5.2 First-order digging resistance law

Use a **Reece-style fundamental earthmoving equation** as the default reduced-order *blade/wedge resistance* term:

```
F_cut ≈ b [ρ g d² Nγ + c d Nc + q d Nq + ca d Na]   [newtons]
```

Here `b` is cutting width [m], `d` effective depth [m], `ρ` bulk density [kg/m³], `c` appropriate cohesive parameter [Pa], `q` surface surcharge pressure [Pa], `ca` adhesion [Pa], and the N coefficients are dimensionless functions of rake angle, soil strength, width/depth ratio and soil–tool properties. **Do not confuse this with the complete FEE calibration.** In particular, effective-stress drained and undrained branches must be configured coherently; the above equation is a first-order model, not a sum of all conceivable soil forces.

For an optional contact-scale secondary branch, use `tau_f = c' + σ' tanφ'` integrated over a separate shear area. **Do not sum that shear force with an FEE wedge term representing the same shearing failure**. For a tool contact choose either a calibrated wedge or discrete shear integration, then add only demonstrably distinct normal, friction and adhesive contacts.

The bundled offline demonstrator uses fixed `Nγ=1.4`, `Nc=1.8`, `Nq=1.0`, `Na=0.5` **for tests and parameter sensitivity only**. Calibrate coefficients for the actual tooth/edge geometry; do not blindly inject them into the live game and call the output real digging force.

### 5.3 Yield, damage and remoulding

The first cut through intact clay should differ from the second cut through rehandled clay. Store accumulated plastic shear strain `γ_p` and structural damage `D`. Example bounded evolution:

```
D_new = 1 - (1-D_old) exp(-Δγ_p / γ_ref)
c_mob = c_residual + (c_peak-c_residual)*(1-D)
φ_mob = φ_residual + (φ_peak-φ_residual)*(1-D)
```

Apply the damage law **only after computed plastic deformation or material separation**. Elastic contact, static load holding and an unpowered scrape must not automatically destroy soil strength. Moisture-dependent destructuring can be calibrated as a modifier to `γ_ref`, not used to create mass.

Treat undrained strength similarly (`s_u` peak→remoulded), but keep it separate from drained effective-stress parameters. The model is hysteretic: placing loose disturbed clay does not restore bank strength without a simulated consolidation process.

### 5.4 Force / work / actual movement transaction

1. Create a **non-mutating** geometric cut proposal for the actual bucket tooth/edge sweeps.
2. Evaluate soil resistance and contacts **before** integration, applying reciprocal forces/moments to the Jolt physical bucket via a dedicated contact owner. The hydraulic solver limits available actuator forces and flow.
3. Allow the physics solver to advance. Record actual physical tool movement and supplied/absorbed work, including inertia and gravity where physically relevant; a joystick target alone is not mechanical work.
4. Commit only volume genuinely intersected by physically feasible motion, limited by the mass available in the contacted strata, active bucket capacity, and positive dissipated cutting work. At zero travel, commit zero. At inadequate force, the tool must stall or slide instead of tunnelling through soil.
5. Transfer each dry-material constituent and its pore water through one **atomic ledger receipt**, then update bucket load, physical machine mass properties and rendering.
6. Never credit both a detached wedge and bucket with the same mass. Material that does not enter the bucket becomes a visible, independently conserved loose wedge/stockpile.

**Jolt ownership:** avoid applying two copies of contact resistance. One approach is a distinct earthwork collision layer: crawler/support collides with heightfield; analytical soil solver alone owns the cutting-tool/soil contact; shell non-cutting and underside contacts receive appropriately constrained analytical contact or a separate non-overlapping collision policy. Godot collision masks and update ordering must be tested with an actual engine runtime, especially as heightmap rebuilds are throttled.

## 6. Excavated material, bucket loading and discharge

### 6.1 Bank-to-loose swelling

When material is detached, increase void ratio toward its `e_loose` target to represent structure breakup and granular rearrangement, without creating solids/water. A useful definition:

```
Swell factor = V_loose / V_bank = (1+e_loose)/(1+e_bank)
```

The provided clay reference has a **1.149 swell factor** from `e=0.74` to `e=1.00`. This is a tuning example, not a universal clay factor. Compacted fill can swell much more on loosening because of its initially low pore volume. Material form and clod size also matter: blocky clay can have large **between-clod** voids not captured by intra-clod void ratio. In the production model use **two levels** if required: intra-clod porosity and inter-clod packing; total loose envelope must still be computed conservatively from both.

### 6.2 Bucket fill geometry and energetic loading

A bucket has a real shell opening and capacity, not just a scalar `bucket_room_m3`. Use a low-resolution signed-distance occupancy or convex partition of the actual shell in bucket-local coordinates, with a separate physical contents ledger. Calculate:

- Bulk volume of each constituent and effective fill height/occupancy.
- Fill efficiency versus rake/angle, tooth penetration, penetration direction, clod size and material stickiness.
- Centre of gravity of the moving soil load (and optional low-order shifting CoM).
- Additional required boom/arm torque, bucket curl torque and chassis overturning moment.
- Particle/clod retention and spill through the real bucket opening.

If available shell volume is insufficient, the cut must continue displacing soil **ahead of/alongside** the bucket rather than invisibly storing more than capacity. A full bucket can still push earth, subject to resisting forces.

**Live rigid-body mass integration:** Avoid arbitrary mass reset impulse artefacts. Add a coupled payload force and inertial compensation, or a properly mass-updated bucket assembly with linear/angular momentum accounted for. The actual strategy requires Jolt validation. Use explicit per-step telemetry for work, momentum and CoM.

### 6.3 Discharge rules

Granular soil begins flowing when the effective free-surface and bucket angle exceed the dynamic friction/repose threshold and the throat is open. Cohesive clay requires gravity/shear to exceed bond/steel adhesion, yielding in clods or ribbons rather than identical spheres. Wet sticky clay can leave carryback; vibration, bucket curl reversal and tapping can dislodge it. Saturated mud may slump continuously. The manual R-key remains a *developer test override* and must not be the only production mechanism.

Define `discharge_request` independent of mass movement. Compute **actual release mass** each physics update; if all pooled particles are occupied, consolidate into larger mass-bearing parcels or a constrained, conservative deposit queue. Do **not** delete soil when the 800-parcel visual budget is reached.

## 7. Surface deposition, stockpiles, material segregation and slope failure

### 7.1 Material carriers

Three representations should coexist:

1. **Intact layered columns** for almost all grounded soil.
2. **Small number of mobile volume-bearing parcels** for temporarily moving spoil; each carries masses, velocity, moisture, e, material fractions and structural damage.
3. **Oversize clods/rock rigid bodies** for large pieces whose individual contacts materially change machine performance. Cap count and merge inactive clods into deposits once appropriate.

Parcels are **not** one tonne-size monolithic spherical rock just because their mass is combined. Render multi-scale aggregate flakes, ribbons, splashes and fine particles independently of physical parcel count. The visual particles are not the authoritative ledger.

### 7.2 Conservative flow and angle of repose

The existing angle-of-repose relaxation should become **mass flux**, not height transfer. For neighbouring columns `a,b`, compute a signed potential mass flux based on local slope, mobile layer thickness, residual friction, cohesion, moisture and time; limit transfer by available donor mass and receiving capacity. Commit equal and opposite masses. In a dry granular pile the dynamic angle is generally below static initiation angle, giving hysteresis. For cohesive clay the same angle alone is insufficient; include structural support and progressive yielding.

Transfer surface material in correct order so the original stratigraphy beneath it is not arbitrarily blended away. On receiving ground, either create a new deposition layer or merge compatible fresh fill into the top layer while preserving the full constituent masses and provenance.

### 7.3 Progressive failures, not instant global slumping

- The local failure criterion shall compare driving shear/surcharge with mobilised strength; use a reduced-order **factor of safety** `FS = R/D` as a testable concept.
- If `FS < 1`, accumulate plastic shear/damage over time, begin a crack/slide region and transfer an actual **failure wedge**. In wet clay the delay may be short and propagation wide; in intact cohesive clay a steep bank may persist temporarily.
- Failure boundaries must respect original soil strata and weaker seams; a sandy lens can promote slip below a clay cap.
- A bucket's removal of toe support may initiate failure even after the bucket stops moving; record additional displaced mass as slope failure, not bucket cutting.
- Surface surcharge from crawler/stockpile increases driving forces and may trigger failure.
- True overhangs, tension cracks of finite width and cave geometry exceed an ordinary heightfield's representation. Use approximated heightfield failures for v1.1; treat future overhangs as discrete retained clods or chunk-mesh extensions, without claiming full subsurface geometry.

### 7.4 Segregation

Gravel and coarse fragments may travel farther down a stockpile slope than cohesive fines, but **each constituent mass remains accounted**. Start with a low-order size-class bias in parcel settling/rolling and face-to-face flux, not expensive grain DEM. Conservation tests must confirm that segregation cannot change total gravel/sand/clay content.

## 8. Compaction, rutting, trafficability and hysteresis

### 8.1 Physical premise

A loaded track produces distributed pressure and shearing. This can densify suitable moist unsaturated soil, remould wet clay, produce shear ruts, or squeeze soft saturated mud laterally. A realistic model requires *different* routes for volumetric compaction and plastic shear displacement.

- Contact pressure `p = N/A_eff` from actual Jolt track contacts, respecting contact distribution; do not assume whole track area always loaded equally.
- Normal compression must exceed a material's yield/preconsolidation pressure before permanent densification. Add a tunable yield threshold and loading history.
- Densification reduces void ratio `e` toward a material-specific `e_min`, never below without explicit grain crushing.
- Use the **dissipated** mechanical work/energy of compaction to drive evolution, not arbitrary vehicle passage count. A bounded reference law is:

```
e_new = e_min + (e_old-e_min) exp[-k_c * E_dissipated_per_dry_mass]
```

`E_dissipated_per_dry_mass` [J/kg], `k_c` [kg/J]. Moisture controls the response, with an optimum and reduced efficiency when too dry or saturated. Repeated passes exhibit diminishing density change at equal work. The offline reference includes a deliberately tunable approximation; it lacks a measured compaction pressure/yield curve, so production must add that before claiming accurate roller physics.

- **Rutting** must displace soil laterally as well as compress it; a rut is not merely a negative height adjustment. Compute how much settlement comes from `ΔV_void` and how much dry-solid mass moves into side berms or mobile mud. Apply identical ledger transactions for both.
- **Wet saturated ground:** if trapped pore water prevents volume reduction in the short term, preferentially shear, form ruts and expel water only with a configured drainage/displacement pathway; do not make mud denser without corresponding free-water/void changes.
- **Re-excavation:** disturbed/compacted tracks are persistent inputs to the next cut, not visual decal-only marks.

### 8.2 Track sinkage and contact reaction

For early implementation use a distributed **pressure–sinkage surrogate** per track patch, optionally of Bekker style `p = (k_c/b + k_phi) z^n`, only after **unit-consistent** calibration. This is not a direct plugin for Jolt. Replace/augment current friction multipliers and box-track grounding only after benchmarking contact stability. Mud shear traction and rut resistance interact, so don't use the same soil strength as both a force response and a second total traction penalty. Record sinkage, slip ratio, wheel/track normal loading, displaced soil mass, and immobilisation/bogging events.

## 9. Rocks, inclusions and stratigraphy

Each column can hold depth-ordered lenses, compacted hardpan, clast counts/size fractions, and separately registered rigid inclusions. Suggested first-pass rock size thresholds are simulation tuning choices rather than geological limits: sub-40 mm as aggregate grading; 40–150 mm in coarsened bulk interactions/clod visual; above ~150 mm as discrete tracked rock bodies *when important to gameplay*. Use streaming/pooling and cap live objects.

Rock may be pushed, rolled, dragged, wedged, or extracted when surrounding soil weakens. Detached boulders must inherit physical density/size and collide with teeth and bucket. A rock too large for the bucket cannot disappear into a scalar fill factor. Impact or drilling breakage is out of v1.1 unless a dedicated calibrated fracture model is introduced.

## 10. Godot numerical design

### 10.1 Grid and storage

Start with 81×81 **surface vertices** over 18 m and model authoritative material **columns over the 80×80 cell footprints**. This matters: a vertex cannot consistently own an entire cell's dry mass. Cell area `A = 0.225² = 0.050625 m²`. The four vertices of a cell determine its rendered/collision surface but **do not each store the whole soil cell mass**. Integrate cell volume from the interpolated surface over cell area; maintain the authoritative material masses in per-cell layers. A limited number (e.g., 4–8 in common cases) of variable-depth layer records should be used; dynamic split/merge must preserve strata and account for underground bedrock refusal.

- Proposed Godot format: per-chunk packed arrays of 32-bit floats for evolving scalar state, 64-bit accumulator for global mass totals, material IDs integer indices, sparse stores for clasts/water/rare layers, and a spatial index of dirty rectangles. **Numerical ledger** should use float64 during accumulation/audit even when GPU surface uses float32.
- Heights are cached **derived output**, not the authoritative source of dry mass.
- Track `surface_elevation`, `bedrock_elevation`, `active_layer_offsets`, `dry_mass[]`, `pore_water[]`, `free_water[]`, `e[]`, `D[]`, `strain[]`, `compaction_work[]`, material fractions and source.
- Never remove more solids from a layer than it holds; a thin layer is exhausted before cutting the next.
- Material preservation when cells cross chunk boundaries is enforced by an atomic transfer queue; no double counting from independent chunk updates.

### 10.2 Update cadence, contact ownership and stale terrain collision

At 120 Hz, update actuator constraints and active bucket-soil contact against **current authoritative material data**. At 15–30 Hz, update mobile flux, collapse and compaction for active regions only. At ~2–10 Hz or change-driven cadence, update slower moisture equilibration and water pooling. Rebuild dirty render meshes at render-rate if cheap; rebuild collision geometry at measured safe cadence, initially target 10–15 Hz during active digging and lower when idle. These cadences are engineering targets, **not measured performance**.

A delayed collider cannot make the excavator cut through an unupdated wall. Use a nonpenetration/contact strategy for analytical soil with explicit clipping/reconciliation until collision catches up. Do not leave the original 140 m static floor under below-grade editable terrain. Godot's `HeightMapShape3D` supports terrain heightfields and `NAN` holes, but cannot form actual caves/overhangs. When scaling it by 0.225 m, be attentive to **Y coordinate scaling**: if the collision shape has uniform scale `0.225`, encode map-data heights relative to that scale; a 1.0 m change in world Y must not become 0.225 m by accidental double scaling. Check the current `_rebuild_terrain()` implementation under Godot/Jolt.

**No all-world 250×250 m high-resolution update.** Activate local chunks around working machines, merge low-activity deposits into heightfield columns, stream persistent changes from save data, and use distant purely visual terrain elsewhere.

## 11. Two-way coupling to hydraulics

Material forces and machine forces belong to the same mechanical system:

- Tool geometry supplies contact normals, swept distance and failure-wedge dimensions.
- Material law supplies resisting forces/torques in world coordinates and estimated dissipation.
- Jolt receives reciprocal forces on the bucket at actual contact positions (or equivalent torque-correct solver input), while valve/cylinder model enforces boom/arm/bucket force/flow/power and relief constraints.
- Actual post-solve movement authorises soil mass transfers. A physically moving bucket can expend hydraulic power, gravity potential or kinetic energy on cutting; the ledger must not implicitly assume all cutting work comes from the pump.
- Filled-bucket mass, water mass and evolving CoM feed back through rigid joints; load changes slew inertia, lifting response and chassis stability.
- Track contact pressure and slip feed compaction/rutting; resulting ground state feeds back into traction and later excavation.

**Discrete integration warning:** pre-contact force and post-movement commit must use a single consistent transaction ID and a well-defined tick. Avoid force/terrain duplicate response and avoid cutting on merely predicted movement. Underpowered bucket tests must include both zero motion and material/energy ledger checks.

## 12. API contract for Codex

```text
MaterialProfile v1.1 (source_label, confidence, grain_density, e_bank, e_loose,
  e_min, moisture, phi_peak, phi_res, c_peak, c_res, su_peak,
  adhesion_to_steel, permeability, plasticity, grading, compaction_coeff)

SoilState (dry_mass_by_material_kg, pore_water_kg, free_water_kg,
  void_ratio, damage, plastic_strain, compaction_energy_J, state_kind)

TerrainCell (surface_y, bedrock_y, ordered_layers[], mobile_puddle_kg,
  rigid_inclusion_ids[], changed_generation)

ToolContact (sweep_id, tooth_index, contact_position_world_m,
  direction_world, normal_world, penetration_m, width_m,
  rake_rad, actual_travel_m, contact_layer_id)

CutProposal (sweep_id, resistance_force_world_N, resisting_moment_world_Nm,
  dry_mass_candidate_kg_by_material, water_candidate_kg,
  required_work_J, failure_wedge[], source_generation_ids[])

SoilTransferReceipt (transaction_id, source_generation_ids[], source_cells[],
  destination_bucket_or_wedge, actual_tool_travel_m, work_dissipated_J,
  bank_bulk_volume_m3, new_loose_bulk_volume_m3,
  dry_mass_kg_by_material[], pore_water_kg, free_water_kg)

MaterialLedger (dry_mass_totals_by_material, water_pore_kg, water_free_kg,
  scripted_water_inputs_kg, runoff_exports_kg, offsite_solids_kg)
```

**Core invariants:** each committed receipt applied exactly once; total per-material dry mass and total water conserved including exports; all mass >= 0 within epsilon; `0 ≤ S_r ≤ 1`, `e ≥ e_min` for ordinary soil; terrain surface matches derived column bulk volume within mesh approximation tolerance; source cell generation must match on commit; stale or repeated cut proposal rejected.

## 13. Material-specific demonstration tests

The production Godot engine should generate CSV traces, actual machine force/pressure telemetry, soil mass receipts and before/after terrain snapshots for each of the following. Proposed thresholds are **acceptance targets**, not results.

| ID | Scenario | Expected mechanical and visual outcome |
|---|---|---|
| MAT-01 | 100 L bank clay cut and loosened | Conserved solids+water; approximately 115 L loose volume for bundled example |
| MAT-02 | Same material re-compacted | Smaller bulk volume, no dry-mass loss, water moved only by accounted flux |
| MAT-03 | Repeated pass over damp topsoil | Diminishing settlement at constant energy; persistent rut/berm |
| MAT-04 | Repeated pass on near-saturated mud | Greater shear/rutting than volumetric density gain; visible track sinkage |
| MAT-05 | Gravel dump versus sticky clay dump | Gravel begins flowing easily; sticky clay can retain clods and carryback |
| MAT-06 | Mix 60 kg sand + 40 kg clay, then dump | Exactly conserved 60/40 solids mass and separately conserved water |
| MAT-07 | Water addition beyond pore capacity | Saturation capped at 100%; surplus goes to free-water store |
| MAT-08 | Water removal through named drainage | Water export accounted; structure remains remoulded unless reconsolidated |
| MAT-09 | Dry granular stockpile | Runout to consistent dynamic repose; global mass balance maintained |
| MAT-10 | Undercut damp clay bank | Delayed/progressive failure based on weakened support, not whole-pad collapse |
| MAT-11 | Undercut sand lens beneath clay | Layer-specific progressive failure, both constituents correctly transferred |
| MAT-12 | Repeat cut through remoulded clay | Lower peak cohesive resistance than intact equivalent at same state |
| MAT-13 | Hard inclusion near bucket tooth | Physical refusal, wedging or extraction; no deletion of stone mass |
| MAT-14 | Zero available hydraulic pressure | No soil removed through stalled tooth; Jolt chassis/bucket remain subject to forces |
| MAT-15 | Tool force 50% below resistance | No geometrically invalid cut; contact pressure/reactive force measurable |
| MAT-16 | Tool forces and work sufficient | Soil extracted in proportion to actual swept geometry and work |
| MAT-17 | Bucket reaches available internal volume | Further soil displaced to front/side wedge; not swallowed invisibly |
| MAT-18 | 800 parcels already active | No matter lost; merged/coarsened parcels or deposit queue honours conservation |
| MAT-19 | Tracks above excavated ground | No hidden floor collider; real sinking and contact support |
| MAT-20 | Mixed-material save/reload | Per-constituent mass, water, density, layer ordering and damage persist |
| MAT-21 | 10 minutes of excavation cycles | No NaN/negative layers/duplicate receipts; memory bounded; profiling recorded |
| MAT-22 | Soil-steel adhesion angle experiment | Wet sticky clay retains/releases with angle/contact; independent from cut resistance |
| MAT-23 | Mixed water/mass ponding | Water mass carried into trench or runoff boundary; no instant disappearance |
| MAT-24 | Soil+excavator 120 Hz contact | Instrument actual force impulse, cut receipts, contact latency, collider rebuild cost |

**Numerical invariants:** `|error(dry_mass_i)| ≤ max(0.1 kg, 0.25% of transferred dry_mass_i)` for each constituent; equivalent total water ledger tolerance; all output finite. For purely offline references, use far tighter floating point conservation tolerances. Full machine-motion/soil tests must run in Godot/Jolt on the target runtime and cannot be considered passed by Python alone.

## 14. Implementation sequence and module boundaries

1. **M-00 — Introduce reference fixtures:** commit this document, JSON profiles, Python reference and its unit tests without changing current Godot behaviour. Pin original CI baselines.
2. **M-01 — Authoritative material store:** add dry solid + water masses, void ratio, damage, mixture constituents and layer ownership. Build conversions from existing 81×81 visual surface to 80×80 authoritative cells and reversible save/load. Verify mass invariants.
3. **M-02 — Stratigraphy and excavatable depth:** add below-grade layers and bedrock refusal; remove underlying flat collision section; test crawl-on and below-zero trench.
4. **M-03 — Non-mutating cutting proposal:** integrate separate tooth/edge contacts and FEE-inspired wedge resistance; return a proposal without touching bank masses or heights.
5. **M-04 — Hydraulic/soil force handshake:** include actual actuator geometry, pressure/power limits and reciprocal Jolt loads; apply the cut only after constrained physical movement. Keep existing test rig as fallback.
6. **M-05 — Bank→loose→bucket→deposit:** conserve composition and water, incorporate void ratio swell, actual bucket volume and mass-dependent lifting, physically derived dumping/carryback.
7. **M-06 — Bank collapse and stockpiles:** conservative face-to-face mass flux; cohesive progressive wedge failure and segregating granular runout.
8. **M-07 — Compaction and soft ground:** Jolt track-contact pressure and energy-driven densification with explicit rut-side displacement, mud remoulding and sinkage.
9. **M-08 — Field calibration and profiling:** record valid Godot 120 Hz/60 fps figures, tune soil parameters from observation, optimise hot loops (native/GDExtension only on measured need).

For each stage add a real Godot acceptance scene and machine-readable CSV before altering the next stage. No stage may silently discard an existing accepted behaviour.

## 15. Executable reference bundle

Included files:

```text
DURHAM_PARK_MATERIAL_MECHANICS_V1.1.md
material_profiles_v1_1.json
reference/material_reference.py
tests/test_material_reference.py
CODEX_HANDOFF_MATERIAL_V1.1.md
```

Run offline mathematical conservation checks from the bundle root:

```bash
python -m unittest discover -s tests -v
```

**22 unit tests currently pass** in the isolated Python reference. These check data range, split/merge, mass/water conservation, volume swelling and compaction, moisture overflow, remoulding, monotonic penetration resistance and basic force/work gating. No actual Godot or Jolt simulation has been run for this addendum.

## 16. Sources, distinctions and uncertainties

- NSW Government, *Soil physics*: https://www.nsw.gov.au/regional-and-primary-industries/agriculture/soil/physics — soil structure, density, moisture and compaction principles.
- USDA NRCS, *Bulk Density — Soil Health Guide*: https://www.nrcs.usda.gov/sites/default/files/2022-11/Bulk%20Density%20-%20Soil%20Health%20Guide_0.pdf — broad density/texture context (agronomic classification, not an excavation strength calibration).
- *A multiscale model of terrain dynamics for real-time earthmoving simulation* (2021): https://doi.org/10.1186/s40323-021-00196-3 — hybrid terrain mechanics and FEE-style wedge components. The v1.1 model is **inspired by**, not an implementation of, its full solver.
- McKyes & Ali, *The cutting of soil by narrow blades*, Journal of Terramechanics (1977): https://doi.org/10.1016/0022-4898(77)90001-5 — width/depth, rake angle and failure geometry matter to cutting force.
- Itasca FLAC3D, *Material Properties*: https://docs.itascasoftware.com/flac3d700/flac3d/docproject/source/modeling/problemsolving/material_properties.html — illustrative drained soil strength ranges, not a specific ground model.
- Godot 4.6 `HeightMapShape3D`: https://docs.godotengine.org/en/4.6/classes/class_heightmapshape3d.html — one height per XZ point, limitations, scaling and collision holes.
- Existing project baseline: https://github.com/sn97ty8yn4-jpg/landworks, especially `docs/EARTHWORKS.md`, `landworks/scripts/earthworks.gd`, `hydraulic_model.gd`, `sandbox_world.gd`.

**Authoritative priority:** actual site/machine measurements > verified manufacturer/lab engineering reference > literature generic range > explicit game calibration assumption. Not all published strength values refer to the same test (drained vs undrained, peak vs residual, compacted vs loose); do not interchange them. The test suite validates arithmetic **only**, not physical calibration.
