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
