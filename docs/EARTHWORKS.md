# Earthworks v0.1 — hybrid deformable terrain and granular flow

A **41 × 41 editable heightfield**, 0.45 m spacing (18 m active pad), with a
collision-backed continuum soil surface and two discrete deposits: dry gravel
and cohesive clay. A Jolt HeightMapShape3D is refreshed at 5–6 Hz when
dirty; rendering uses indexed ArrayMesh triangles and vertex colours.

The bucket's *actual rigid-body lip trajectory* can remove only the material
it penetrates. Cut volume is debited from the heightfield and credited to a
bounded **0.24 m³ prototype bucket**. In the integrated sandbox, this volume
will be tracked on the excavator and spilled from the moving bucket. Cutting
applies a velocity-opposing reaction **force to the rigid bucket** rather than
directly overwriting its position. Force parameters are currently estimates.

Material released into the air spawns moving 4.5 litre parcels with gravity,
limited bouncing, lateral damping, and deposition back onto the terrain.
A maximum of 240 active parcels is drawn through one MultiMesh; settled
material is merged back into the heightfield. Neighbouring heights collapse
above a material-dependent repose angle. Volume is conserved to within
numerical tolerances across ground, bucket, mobile particles and material
spilled outside the bounded work pad. The simplified parcel model is
**not** full DEM, SPH, MPM or calibrated soil mechanics. There are no
particle-particle impulses, compaction histories or soil failure wedges yet.

**Performance strategy:** Jolt simulates machines and load reactions. Static
continuum soil does not waste thousands of RigidBody3D contacts. Dislodged
soil is briefly modelled as moving, volume-bearing parcels, with fixed caps
on particle count and a limited heightfield collision-update frequency.
This is a first-stage real-time hybrid, not a photoreal granular fluid.

## Run engine conservation test

```
godot --headless --path . --script res://landworks/scripts/earthworks_smoke.gd
```

The test cuts through a gravel bank, asserts a non-zero reaction force,
transfers excavated soil to an abstract bucket store, releases it as
airborne parcels, and tests conservation after gravity and slope collapse.
Soil must actually be deducted from the grid; an emitter showing dirt
without removing material is insufficient.

Background: Godot HeightMapShape3D documentation
https://docs.godotengine.org/en/4.6/classes/class_heightmapshape3d.html

The multiscale hybrid approach is inspired by research on mesh–particle
coupling, not a direct implementation of a commercial solver:
https://doi.org/10.1186/s40323-021-00196-3


## First physical-machine coupling trial

The CI test moves a **bank** to a known work position, then drives the real
Jolt boom motor downward through it. The excavator itself is never teleported.
A correct test must remove at least 5 litres by moving the powered bucket lip
and conserve total material volume. The bank is 1.32 m high for gravel and
1.45 m high for clay, before repose relaxation.

Manual discharge is tested independently using the same flag as holding R.
Automatic spill based on actual bucket curl angle remains a separate control
condition and has NOT yet been calibrated against a correctly modelled
bucket shell or hydraulic linkages.


## Driveable entry fix

The previous excavation grid stood 45 mm above the adjoining flat Jolt
collision plane even before any bank, giving the rigid box-track contacts
a discrete edge to climb. Its **baseline is now 30 mm recessed** below the
yard collision level; only real gravel/clay bank material protrudes. The
1,500 kg test crate has been relocated to the side for the playable yard,
leaving a clear path for the excavator to enter the soil work pad. A separate
headless crawler-access test is required to verify actual traversal.
