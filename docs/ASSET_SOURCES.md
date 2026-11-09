# Verified CC0 donor-model listings — 9 November 2026

These are **unbranded donor meshes**, NOT dimensionally correct Kubota models.
We must not call their generic geometry manufacturer-accurate without reworking it.

| Use | Original source | On-page licence | File | Source note |
|---|---|---|---|---|
| Tractor | https://www.innerscene.com/tools/library/3d-parts/garden-tractor-with-trailer-40bf3bb8 | CC0 | `garden-tractor-with-trailer.glb` | 17.8 MB; includes 48-inch mower deck, a small trailer, front-engine garden tractor. Rear turf tyres 508 mm diameter, front 406 mm. Tractor component about 1.85 m long, not a B7100. |
| Excavator | https://www.innerscene.com/tools/library/3d-parts/compact-tracked-excavator-76c41cd5 | CC0 | `compact-tracked-excavator.glb` | 6.2 MB; generic compact excavator about 3.48 m long, not a KX080-3. |

Source pages state they are original Innerscene models, dedicated under CC0. Preserve these URLs and the verified licence statements in our source records. CC0 isn't itself a guarantee about trademarks or third-party rights; review visual branding if any before release.

## Get the actual GLB files

On a Windows PC with Python 3 installed, double-click `DOWNLOAD_MODELS_WINDOWS.bat` from the extracted project folder. Or run:

```
python tools/get_models.py
```

The script retrieves the original supplier's public download endpoint, follows its redirects, validates that the result is a complete GLB v2 file, computes SHA256, and records node/mesh names in `landworks/assets/source/download_report.json`.

**If downloads fail:** open either source page in a browser, press `Download GLB`, and place the exact named files in `landworks/assets/source/`. Run `python tools/get_models.py --inspect-only` to verify the manually downloaded copies.

Downloads cannot be bundled or inspected until their original file bytes are actually available. The Landworks ZIP therefore includes a download tool and inspection scene, not an unverified replacement mesh.

## Check the moving-part structure

Open the Godot 4.6 project. Open `landworks/scenes/asset_lab.tscn` and press **F6**. F1 selects tractor, F2 excavator. Camera orbits with A/D or left-stick X; zoom with W/S or trigger buttons. The preview shows whichever file is present, **not** a physics-ready machine.

Inspect `download_report.json`. It records every glTF node name. If wheel/track/arm components are not separate mesh nodes, Blender manual splitting is necessary before the donor can articulate convincingly.

## Visual-part target files

After model splitting, export each part as a separate GLB in `landworks/assets/rigged/`:

```
b7100_body.glb
b7100_wheel_front.glb
b7100_wheel_rear.glb
kx080_upper.glb
kx080_boom.glb
kx080_stick.glb
kx080_bucket.glb
kx080_track.glb
```

The Landworks motor and pivot scripts now have **optional visual-slot loading** for these specific filenames. If the file is missing, the original procedural placeholder remains and the test yard still works. Do not rename or delete the collisions: the GLBs are render meshes only.

For moving parts, put the GLB origin exactly at the corresponding functional pivot, with the geometry positioned relative to that origin and a consistent Godot -Z-forward, +Y-up coordinate system. The tractor body GLB origin should match the physics chassis origin. Wheels use a centre-origin and local X axle. Boom, stick, and bucket use their individual hinge centres. Units in metres. If a part is not correctly aligned in the asset lab / Blender, don't copy it into `rigged/` as a finished part yet.

## Why not just resize the whole donor GLB?

The tractor donor includes a trailer and mower deck. Making the combined object the vehicle body would cause the trailer to turn as part of the chassis and conceal the functioning turf tyres. The excavator donor may or may not have separable arm objects; scaling the entire model won't provide credible KX080 geometry. The next task after downloading is **mesh hierarchy inspection and segmentation**, not automatic model replacement.
