# Rigged KX080-3 and tipping-trailer integration

Two externally built Blender models replaced the segmented placeholder art and
the proxy trailer, and the machine and soil physics were remapped onto their
measured geometry. The models are `landworks/assets/engineered/kx080_3_machine.glb`
and `landworks/assets/engineered/farm_tipping_trailer.glb`, both tracked in Git LFS.

Both are authored +X forward, +Y up, machine-left -Z, with every moving part's
origin on its real pivot pin and no scale transforms. The sandbox drives limbs
along -Z, so bound art carries a quarter turn about Y and nothing else.

## How the art is bound

`landworks/scripts/rigged_machine_art.gd` instantiates each GLB once and
reparents the model's own rig nodes onto the live rigid bodies:

| Model node | Rigid body |
| --- | --- |
| `Undercarriage` | `digger.undercarriage` |
| `Upper_Swing` | `digger.upper`, 0.80 m up on the swing bearing |
| `Boom_Swing_Bracket` | `digger.king_post` |
| `Boom` / `Arm` / `Bucket` | `digger.boom` / `digger.stick` / `digger.bucket` |
| `Dozer_Blade` | `digger.dozer_blade` |
| `Chassis` / `Tray_Pivot` | `trailer` / `trailer.tray` |

The baked demo clip is removed on load, so no part is ever driven by an
animation. The six cylinders are aimed at their real pin partners every physics
tick, the way the source rig aims them with Damped Track. The 78 individual
track shoes are replaced by two MultiMeshes drawing the model's own shoe mesh
39 times a side on the measured loop, circulated by the undercarriage's
measured point velocity.

## Geometry remapped onto the model

| Quantity | Before | Now | Source |
| --- | --- | --- | --- |
| Boom, foot pin to arm pin | 3.00 m | 3.60 m | model pin spacing |
| Arm, pin to pin | 2.32 m | 1.75 m | model pin spacing |
| Bucket pin to tooth tip | 0.82 m radial | `(0, -0.5, -0.8)`, 0.943 m | `Bucket_Tip` socket |
| Bucket cutting width | 0.76 m | 0.65 m | modelled bucket |
| Boom foot pin | (0.48, 1.28, -0.66) | (0.10, 1.36, -1.30) | model |
| Swing bearing height | 0.97 m | 0.80 m | model |
| Track gauge / shoe width | 1.72 / 0.46 m | 1.75 / 0.45 m | model |
| Crawler length / height | 3.10 / 0.54 m | 2.85 / 0.71 m | model |
| Track shoes per side | 54 | 39 | model |
| Boom / arm / bucket range | -40..66 / -86..9 / -57..43 deg | -60..63 / 30..150 crowd / -40..105 deg | model rig limits |
| Trailer wheel track / radius | 1.58 / 0.36 m | 1.33 / 0.365 m | model |
| Trailer hitch ahead of axle | 1.80 m | 2.00 m | `Drawbar_RingHitch` |
| Trailer tray pivot | none | (0, 0.725, 0.84), 0-45 deg | `Tray_Pivot` |

The bucket's tooth tip is no longer a radial point on -Z. Everything that
sampled `Vector3(0,0,-BUCKET_LENGTH)` now uses `BUCKET_TIP`, including the soil
cutting edge, the load hook and the smoke tests.

## New mechanisms

All three are genuine Jolt bodies on powered pins, not scripted transforms.

* **Dozer blade** — hinged on the car body at (0, 0.30, -0.62), -18 to +18
  degrees, on its own motor. `T` raises, `Y` lowers.
* **Boom offset (king post)** — the boom now hangs from a vertical-pin bracket
  on the upper structure, 60 degrees right to 70 degrees left. `[` and `]`.
* **Tipping tray** — a sibling rigid body on the trailer's real rear pin,
  0 to 45 degrees with a 26 kNm limit. `N` tips, `B` lowers. The tray is a
  registered container: parcels dumped into it are caught on the way down
  instead of reaching the ground, and past 17 degrees it discharges them over
  the rear sill as loose material again.

The blade cuts below grade and pushes spoil ahead of itself through
`Earthworks.blade_push()`. It never carries material: a cut moves from the bank,
through the blade's own `blade_inventory`, to loose material in a single tick.
That store is counted in `mass_totals()`, so a push is conserved like every
other movement. The force available is whatever the tracks actually developed
that tick, so a blade load the machine cannot push simply stalls.

## Assumptions, and what is not measured

These numbers are engineering choices, not values the models supply.

* **Bucket mass 300 kg** (was 210 kg). The modelled bucket is larger and its
  tooth sits on a longer lever, which pushed peak bucket-pin separation during
  digging from 36 mm to 41 mm, past the 40 mm regression limit. 300 kg for a
  650 mm bucket with teeth, side plates and wear strips is both more realistic
  and brings separation back to 36 mm. The limit itself was not relaxed.
* **Blade 320 kg / 42 kNm, king post 180 kg / 30 kNm, tray 240 kg / 26 kNm.**
  Starting assumptions; no OEM figures were used.
* **Seated eye point 1.90 m** in the upper structure's frame. Checked by
  `detailed_cab_smoke` to fall inside the modelled cab shell, not measured from
  a seat.
* **Upper structure collision** is still a single box, dropped onto the 0.80 m
  swing plane and widened to 2.00 m. It is not the modelled round-tail shape.

## Tests that changed, and why

Four checks tested the old art or were aimed at the old arm. None had its
threshold relaxed to accommodate the remap; each was re-pointed at what is
actually there now, and `rigged_model_smoke` was added on top.

* **`detailed_skin_smoke`** checked the segmented `Engineered_kx080_*` nodes.
  It now checks the bound model limbs, and measures *reach* rather than
  surface depth: the slender modelled boom has no skin at the pin centre, and
  the dipper's cylinder lever really does sit 0.64 m behind its pivot, so the
  far end must land on the far pin and the near end must cover its own. It
  also gained a check the old one could not make: the soil cut width must
  equal the width of the visible bucket steel (0.658 m against 0.65 m).
* **`machine_visual_smoke`** tested the hand-built four-bar linkage and
  fixed-length barrels, which the model replaces. It now checks the tractor's
  five parts, the two track belts and, for the five aimed cylinders, that each
  stays on its own pin and keeps pointing at its partner through three worked
  arm poses. Measured: 4e-5 m pin drift, 4e-7 aim error.
* **`detailed_cab_smoke`** asserted four moving lever nodes. It asserts the
  lever gate only when a rig exposes those controls, and now also checks the
  seated eye point falls inside the modelled cab shell.
* **`tractor_work_lab`** hitched the trailer at a hardcoded tongue offset and
  never built a tray. Against the remapped trailer that attached the drawbar
  0.65 m below the real ring hitch, and left the payload unapplied, so
  `hill_400` and `hill_800` measured identically and both tilted 20.3 degrees
  against a 20 degree gate. The lab now reads `trailer.HITCH_POINT`, and a
  trailer without a tray carries its payload on the body, as it did before.
  Tilt fell to 7.2 and 7.1 degrees and the two loads separate again.
* **`earthwork_machine_smoke`** positioned its bank for the old arm. With the
  tooth 0.5 m below the bucket pin the bucket started buried 0.7 m in the face
  and stalled, cutting 1.5 L against a 5 L floor. The pad is now seated so the
  lip begins 50 mm clear of the face; the commanded motion then cuts 0.292 m3.

## Known limitations

* **The cab levers no longer animate.** The modelled interior is one mesh
  rather than separate joystick and travel-lever nodes, so `detailed_cab.gd`
  reports `levers_rigged = false`, fits the camera and leaves the levers
  static. `detailed_cab_smoke` asserts the lever gate only when a rig exposes
  those controls, and now also checks the eye point sits inside the cab shell.
* **The measurement lab runs the bare machine.** `fit_blade_and_offset` is off
  in `excavator_work_lab.gd`, so the thirteen field trials keep comparing the
  same mass and the same ground contact. Only the sandbox carries the blade and
  king post.
* **The field-trial thresholds were not re-derived, and did not need to be.**
  All thirteen measured gates in `tools/validate_physics.py` pass on the
  remapped machine with every limit unchanged, including the nine excavator
  cases. They are still provisional acceptance ranges, not OEM validation.
* **The model's own envelope is already off the published figures** by its
  authors' measurement: digging height reads 15 percent low and dumping height
  19 percent high. Depth and reach land within 4 percent.
* The blade pushes a surface pile; it does not yet build a true blade load that
  spills around the ends.
* The tray catches material by a box test, not by its real shell, so a parcel
  entering the box is caught wherever the drop-sides happen to be.
