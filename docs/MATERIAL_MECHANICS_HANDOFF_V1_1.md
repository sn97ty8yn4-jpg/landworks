# Codex handoff — Durham Park Material Mechanics v1.1

**Intent:** Integrate the v1.1 material mechanics specification into `sn97ty8yn4-jpg/landworks` incrementally. **Do not** silently replace the existing physics yard or claim Godot test success from Python checks.

## Initial inspection

Review `project.godot`, `docs/EARTHWORKS.md`, `docs/SANDBOX.md`, `landworks/scripts/earthworks.gd`, `sandbox_world.gd`, `sandbox_excavator.gd`, `excavator_work_lab.gd`, `hydraulic_model.gd`, `ground_response.gd`, and the existing `earthworks_smoke.gd`, `earthwork_machine_smoke.gd`, `hydraulic_smoke.gd`, plus `tests/test_earthworks.py`/CI.

**Baseline facts:** Godot 4.6 Jolt 120 Hz, 18×18 m editable pad, 81² surface heights at 225 mm, no genuine depth strata, prototype bucket 240 L, 800 moving 0.75 L soil parcels, cut volume removed before resistance force is applied, original floor collision under dirt pad, existing load and art scenes.

## Stage M-00 — Commit reference and fixtures, no Godot modifications

Copy `DURHAM_PARK_MATERIAL_MECHANICS_V1.1.md` to `docs/MATERIAL_MECHANICS_V1_1.md`. Add JSON profiles to `landworks/data/soil/material_profiles_v1_1.json`, Python reference and tests to appropriate existing `tools/` and `tests/` directories. Ensure Python tests pass. Capture current Godot headless regression outputs separately before editing physics. Treat profile values as tunable **unverified** assumptions.

## Stage M-01 — Material state and ledger

Implement `landworks/scripts/soil/material_profile.gd`, `soil_state.gd`, `terrain_column_store.gd`, `material_ledger.gd` with a **compatibility adapter** from existing `earthworks.gd` material IDs. A physically stored volume must have per-constituent dry masses, pore water, free water and void ratio; no authoritative bulk density variable. Prefer 80×80 cell ownership below the 81×81 surface grid, with cell area `0.050625 m²`. Split/merge, bank→loose, wetting, compaction must conserve every constituent, check on save/reload, and reject duplicate transfer receipt IDs.

## Stage M-02 — Trench physics and strata

Remove only the static ground collision footprint covered by the mutable pad. Retain continuous ground at its edges and actual machine entry. Create depth-ordered bank strata and refusal substrate. Verify 0.5 m below-grade trench and crawler traversal across all four boundaries without jitter or suspended machine.

## Stage M-03/M-04 — Material resistance / hydraulic handshake

Add `soil/tooth_contact_sampler.gd`, `soil/cut_proposal.gd`, `soil/tool_contact_solver.gd` and `integration/earthmoving_coordinator.gd`. `propose_cut()` must be read-only. Contact must include actual bucket transforms and multiple teeth/lip/shell contacts. Parameterise a Reece-style FEE baseline, test monotonic depth and strength. No double-counting FEE shear with separate equivalent shear law. Apply force before physics integration and commit only material actually cut using post-solve displacement/energy. A stalled/unpowered bucket must not cut; retain actual recoil, stalling, pushing and overloading through Jolt.

Important: update hydraulic actuator linkage geometry as specified in v1.0; the existing 75/45/20 kNm motor limits and cylinder moment constants are not Kubota specifications. Distinguish front attachment 27.4 MPa reference from travel 29.4 MPa reference, with variant confirmation gate.

## Stage M-05 — Spoil and bucket

Add per-constituent bucket inventory and bulk-volume occupancy; use measured/validated shell opening geometry. Route surplus cut material to a loose moving wedge. Add contents mass/CoM to machine without momentum injection. Implement angle/material-dependent dump including wet clay carryback and overflow parcel aggregation. Preserve manual `R` as debugging override only.

## Stage M-06/M-07 — Soil history, collapse, compaction and wet ground

Implement structural damage, remoulding, stateful loose→compacted fill, water partition, conservative layer-wise slump and failure wedges. Crawler track pressure/sinkage input from actual Jolt contacts must create rut/berm mass receipts, not just negative height marks. Add material-dependent hydraulic loss and sinkage only once per physical mechanism, avoiding doubled drag forces. Implement soft-ground failures and rock refusals. Keep active-chunk only updates and profile runtime.

## Required logs and pass gates

Every active soil tick should optionally emit: `tick, transaction_id, cell/layer, material_id, dry_mass_before/after, water_before/after, void_ratio, saturation, damage, contact_depth, candidate_volume, committed_volume, force_N, work_J, bucket_fill_m3, active_parcels, residual_mass_error_kg, collision_update_us`.

A check passes only if it is executed against the appropriate layer:

- Pure Python tests → conservation/math reference only.
- Godot headless tests → actual Godot component / Jolt contact validation.
- Windows scene run → actual frame timing, rig controls, collider seam, physics stability and live driving.

**Stop/review conditions:** mass disappearance, saturated pore water overflow without storage, material deduplication, hydraulic cut with zero movement, negative void ratio, machine teleporting, hidden ground under excavated trench, unbounded parcel count, or existing working-scene regression.

## Integration quality and merging

Do not change engine backend, renderer, machine aesthetic, input layout or tick frequency as part of a soil physics PR. Keep the old physics path behind a feature flag until new tests pass. Commit each stage separately and include a concise change log, actual test commands, runtime environment and CSV receipts. All new material parameters must carry a `source_label` distinguishing assumption from measurement.
