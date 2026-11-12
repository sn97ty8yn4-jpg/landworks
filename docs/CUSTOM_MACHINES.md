# Custom machinery meshes — engineering-art pass

The playable Godot sandbox uses nine original, segmented GLB assets in
`landworks/assets/engineered/`. This is newly authored geometry, not an AI
image displayed over the scene, not a purchased donor and not Kubota CAD.
Model names identify the intended reference machines rather than an OEM
endorsement. No manufacturer brochure imagery is bundled as game artwork.

## What changed

- B7100HST: narrow formed bonnet, radiator grille and twin lamps, engine and
  injection lines, steering wheel and instruments, HST pedal, folded rear
  mudguards, ROPS, hitch, dished rims, fasteners and staggered R3 turf blocks.
- KX080-3: formed counterweight and service panels, sloped framed glazing,
  seat/joysticks/operator, mirror/wiper/work lights, arched plated boom,
  tapered dipper, hydraulic pipes, hollow rolled bucket, cutting edge/teeth,
  drive/idler/roller details and two 54-shoe instanced crawler belts.
- The original cab art rose above 3.1m. The new roof crown is about 2.55m;
  the optional beacon sits above it. The reference KX080-3S roof height is
  2.54m. The real sandbox boom hinge is now at `(0.48,1.28,-0.66)` instead of
  at cab-roof height. All connected rigid bodies are constructed from that
  hinge. The isolated laboratory geometry retains its existing baseline.
- The sandbox's old broad invisible ground-pushing toe is replaced by a
  small 0.76m-wide contact proxy centred at the visible cutting lip. The
  bucket collision remains a simplified solid shape, not concave plate CAD.
- Three telescoping cylinders have fixed barrel lengths. The bucket ram
  drives a visually closed four-bar linkage constructed from two circles.
  The physical bucket still uses its established torque-limited hinge.
- Wheel spin and steering remain centred on their actual runtime pivots.
  Track shoes follow measured longitudinal point velocities on each side,
  including differential yaw. They are visual belts, not a rigid track chain.
- Visible stored soil follows the real bucket volume ledger and disappears
  after discharge. It is a fill mesh, not an additional source of soil mass.
- Mouse-wheel zoom and F2 low inspection framing expose the new detail.

## Scale and provenance

All files use metres and Godot axes (X right, Y up, -Z forward). Each asset
has unit scale and origin at its body or wheel spin pivot. Boom end pin:
`(0,0,-3.0)`; dipper end pin: `(0,0,-2.32)`; effective bucket lip:
`(0,0,-0.82)`. These arm lengths are retained simulation assumptions.

| Quantity | Model baseline | Evidence / remaining uncertainty |
| --- | ---: | --- |
| Tractor wheelbase | 1.390m | B7100HST workshop reference; existing simulation |
| Front turf nominal diameter | 0.5207m | 20.5-inch nominal size; rounded tread adds small relief |
| Rear turf nominal diameter | 0.7366m | 29-inch nominal size; no loaded-radius calibration |
| Tractor width over rear turf tyres | about 1.017m | Existing axle centres plus tyre width |
| Excavator width over tracks | 2.20m | KX080-3S envelope reference |
| Excavator cab roof | about 2.55m | Sibling reference 2.54m; beacon excluded |
| Track length | 3.10m | Existing physics envelope; sibling brochure is 2.90m |
| Boom/dipper pivot spacing | 3.00 / 2.32m | Provisional existing solver geometry, not measured OEM pins |
| Sandbox boom base height | 1.28m | Proportional reconstruction; owner measurement needed |

Primary manufacturer references:

- [Kubota KX080-3S brochure](https://media.kubota.io/uploads/Kubota_Excavator-KX080-3S.pdf)
- [Kubota B7100HST workshop manual scan](https://kubotarepairmanual.com/wp-content/uploads/2019/12/B7100.pdf)

The sibling excavator dimensions constrain the envelope; they do not prove
that every KX080-3 option, arm, bucket or panel matches the owner's machine.
The reference illustration is useful for visual direction but contains
invented engineering and lettering, so it is not used as dimension evidence.

## Rebuild / edit

```sh
blender --background --python tools/build_machine_assets.py
godot --headless --path . --editor --import
```

Blender 4.3.2 authored the current GLBs. The generator is the canonical
editable source. It also writes `model_source/custom_machinery.blend`, which
is excluded from Godot import and Git; the downloadable source package
includes it. Meshes are merged by material within each rigid segment, so
fasteners and tread blocks do not become hundreds of Godot scene nodes.
Runtime track shoes share one mesh via two MultiMeshes. Full geometry is
roughly 200,000 triangles for the two machines together, with no large image
textures; the manifest records exact counts per reusable part.

The Blender source opens with both machines assembled at 1:1 scale and
separate wheel/arm pivot empties. Source cylinders show the saved pose;
their moving telescoping and linkage solution runs in Godot. Keep
`tools/assemble_machine_source.py` alongside the generator when rebuilding.

## Verification and next calibration

`machine_visual_smoke.gd` loads the actual scene, checks all ten attached
parts, wheel origins, measured track circulation, fixed-barrel reach,
four-bar closure under powered joint changes and empty/loaded soil visibility.
Existing access, hydraulic, earthworks, integrated sandbox and 13 field-trial
checks remain independent. `visual_snapshot.gd` captures four actual Godot
frames (gameplay and low inspection views) in the visual CI workflow.

To progress from reference proportions to an owner-specific replica, use
square side/front/rear photographs, tyre sidewall sizes, the excavator arm
option and bucket width, then measure boom/dipper/cylinder pin centres. The
longer crawler proxy, simple bucket collision/toe, estimated arm geometry,
hydraulic force calibration and non-colliding soil parcels remain open work.
