# Runtime soil mechanics and detailed cab — November 12

## Active in the playable sandbox

The default sandbox now uses the imported v1.1 gravel and moist silty clay
profiles through a Godot `MaterialBatch` implementation. Dry mass by
constituent, pore water, free water, void ratio and disturbance are stored
explicitly. Bulk volume and density are derived. Ground samples, bucket,
airborne parcels and offsite deposits all own batches; split/merge consumes
the donor and preserves constituents. A mixed dump no longer turns all its
mass into whichever material was most recently scooped.

Excavated bank material loosens, increasing occupied bucket volume without
creating mass. The gravel fixture's bank-to-loose ratio is 1.125786. Parcels
carry this loose volume back to the pad; slumping transfers the actual batch.
The 240 L capacity limits loose occupancy rather than bank volume.

The cutting sequence now predicts contact and applies an opposing force to
the actual Jolt bucket before the next solve. The following tick proposes
the measured swept path and commits only forward solved movement within the
prior force/work budget. Insufficient force, zero work, no motion, stale
terrain proposals and repeated receipts reject the transfer. The swept
volume is bounded by width, penetration and actual travel. Contact search
is restricted to the sweep's grid bounds.

The budget uses the existing hydraulic allocator's torque caps, speeds,
power and current geometric lever arms. Cutting resistance uses the v1.1
simplified FEE-inspired law; disturbed clay is weaker than intact clay.
This is a prototype coupling, not measured cylinder pressure feedback.

Carried soil adds real bucket mass and an approximate contents centre of
mass. Capture includes linear momentum dilution for initially stationary
bank soil; discharge inherits tool velocity. The empty bucket retains its
original automatic centre of mass. Angular momentum of individual grains
is not resolved. Automatic discharge depends on the shell opening's world
direction and a provisional clay adhesion contact area; R is retained as a
manual debugging override. The fill graphic now occupies the corrected
bucket cavity rather than the space outside the old reversed shell.

## Cab controls and visual preservation

`tools/prepare_detailed_cab.py` separates existing connected mesh islands
into joystick and travel-control pivots. It preserves all 74,014 original
upper-carriage triangles, positions, normals, UVs and texture references.
No duplicate seat, console or replacement procedural cab is introduced.
The original `kx080_upper.glb` remains unchanged; the derived
`kx080_upper_cab_rig.glb` is reproducible. Conversion counts and source hash
are recorded in `detailed_cab_conversion.json`.

The camera inherits the real upper-carriage transform. Eye position is fitted
to the detailed source furniture, not an OEM ergonomic measurement. Its far
plane includes the existing landscape belts. Actual joystick and differential
track commands animate the original controls with smoothing and a radial
joystick limit. Travel pedals and their hand levers share each travel pivot.

- **V:** cab/follow view while operating the excavator.
- **Arrow keys or right mouse drag:** bounded head look.
- **Home:** centre the view.
- **Tab:** change machine and return to the follow camera.
- Existing driving, digging, controller and inspection controls are retained.

The user's supplied illustrated excavator image (preserved unchanged as
`docs/references/excavator-style-reference.png`) guides warmer orange paint,
less glossy enamel and restrained soil flecks on working dark metal. The
finish shader samples the existing texture maps; geometry, glass, labels,
hoses, pins and source images remain intact. This is an incremental refinement,
not a claim to reproduce the illustrated machine or scene exactly. No new
landscape imagery was generated or substituted.

## Validation and compatibility

`RUN_INTEGRATION_TESTS.ps1` includes eleven Godot checks: original geometry,
articulation, legacy parcel balance, below-grade rays/seams, crawler entry,
powered digging/dumping, hydraulics and hooking, plus runtime material
transactions, unpowered cutting and cab camera/control behaviour.

The physical digging test now checks constituent mass when the new path is
active. Its bulk-volume increase is expected swell, not a mass discrepancy.
The standalone legacy soil fixtures still check volume conservation.
Launch with `-- --legacy-soil` to compare the previous sandbox path.

Actual renderer views are retained in `validation/material-cab` (before the
finish refinement) and `validation/material-cab-refined` (refined exterior,
seated view and controls). Earlier bucket-corrected exterior views remain in
`validation/bucket-review/after`. Python reference checks remain separate
from these Godot tests. CI runs the new runtime checks as well.

## Deliberately incomplete parts of the larger specification

This implements the first coupled runtime stage, not all stages M-01–M-07.
The existing 81×81 node-centred inventory convention is retained to preserve
the tested collision pad; migration to 80×80 cell ownership is outstanding.
Each column is a homogeneous mixture, not ordered depth strata. Surface
colour and parcel appearance use the dominant constituent while the ledger
retains both masses. Ground support and contact still use the existing Jolt
heightfield and tooth proxy, not an exact multi-tooth shell contact model.

The seven profiles are available but the current pad exposes only gravel
and clay. Compaction history, rainfall/infiltration, track ruts, layered
failure wedges, full save-game persistence and calibrated hydraulic linkage
forces remain future stages. Batch state round-trips are tested; this is not
a persistent world ledger or a production soil solver. Full per-grain angular
momentum and calibrated wet-clay carryback are also outstanding.
