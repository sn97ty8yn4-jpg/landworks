# Landworks v0.3 — donor mesh separation and pivot fitting

This document is a **repeatable workflow**, not a claim that either downloaded model is already rigged. The donor files are independently downloadable CC0 GLBs, but their binary content was inaccessible in the development environment. A full model needs inspection on the computer that downloads it.

## 1. Tooling

- Windows 10/11, Python 3 and Blender **4.4 or later** (Blender's `bpy` includes glTF import/export).
- Godot **4.6 standard** for this standalone test yard. This is *not* yet merged into Tinybox.
- Start from the project directory containing `project.godot`.

## 2. Download and validate original models

Double-click `DOWNLOAD_MODELS_WINDOWS.bat`. The source GLBs go under `landworks/assets/source/`:

- `garden-tractor-with-trailer.glb`: unbranded, CC0, approx 17.8 MB, 406 mm front and 508 mm rear turf tyres, includes mower deck and trailer (these are **not** part of our B7100 chassis).
- `compact-tracked-excavator.glb`: unbranded, CC0, approx 6.2 MB, a much smaller machine than the KX080-3.

If automated download fails, use the `Download GLB` link in each original source page from `docs/ASSET_SOURCES.md`, then place the files in that folder. Run `python tools/get_models.py --inspect-only`. Do not use files from unknown mirrors.

## 3. GLB hierarchy scan

Run `SCAN_MODELS_WINDOWS.bat` or:

```cmd
python tools/rigging/scan_glb.py --machine b7100
python tools/rigging/scan_glb.py --machine kx080
```

This writes mesh-node, mesh-material, hash and transformed AABB data to `landworks/assets/reports/`. It also creates **empty mapping worksheets** at `tools/rigging/recipes/b7100.json` and `kx080.json`. The empty selections are intentional. Names alone are not sufficient to prove a wheel, track or bucket is separately articulated.

**Never pass `--overwrite-recipe` after editing a worksheet.** It destroys your manual selections.

## 4. Inspect and split in Blender

Double-click `INSPECT_IN_BLENDER_WINDOWS.bat`. If Blender is not on PATH, use these commands with your full `blender.exe` path:

```cmd
blender --background --python tools/rigging/blender_rig.py -- --stage inspect --machine b7100
blender --background --python tools/rigging/blender_rig.py -- --stage inspect --machine kx080
```

The script imports each donor and writes a report listing **exact Blender object names**, mesh vertices, parent, materials and extents. It also creates two editable `.blend` workbenches at `landworks/assets/workbench/`.

Open each `.blend` in Blender. If imported wheels, boom, dipper or bucket are already separate mesh objects, they can be chosen by name. If a donor is a monolithic mesh, you **must** split it manually using Edit Mode selection, `P` (Separate > Selection), or `Separate > By Loose Parts` where appropriate. Be cautious with loose-parts splitting: it may create hundreds of bolts, surfaces or triangles and does **not** identify mechanical joints by itself.

Save the `.blend` after editing. Do not delete the original source GLBs.

## 5. Complete the mapping recipe

The JSON worksheets have slots:

| Tractor role | What to select | Filename after export |
|---|---|---|
| `body` | Chassis/bonnet/seat/mudguards; **not** trailer or mower deck | `b7100_body.glb` |
| `wheel_front` | **One** front turf wheel, complete tyre and rim | `b7100_wheel_front.glb` |
| `wheel_rear` | **One** rear turf wheel, complete tyre and rim | `b7100_wheel_rear.glb` |

| Excavator role | What to select | Filename after export |
|---|---|---|
| `track` | **One** track assembly | `kx080_track.glb` |
| `upper` | Swivelling cab, counterweight and upper carriage | `kx080_upper.glb` |
| `boom` | Boom and rigidly attached geometry | `kx080_boom.glb` |
| `stick` | Dipper/stick and rigidly attached geometry | `kx080_stick.glb` |
| `bucket` | Bucket, cutting edge and teeth | `kx080_bucket.glb` |

For every role, set `objects` to one or more **exact Blender object names** from the Blender report. `pivot_source_blender_m` is the hinge or axle centre in the *original donor Blender scene's* XYZ, where Z is up, in metres. Do not use a random visual centre for the bucket hinge. A tractor body uses its intended chassis-origin reference; bucket, stick, boom and slew must use their real pin/slew centres.

The recipe also provides:

- `source_to_machine.uniform_scale` — global model scale.
- `source_to_machine.rotation_xyz_deg_blender_z_up` — source orientation correction.
- `part_scale_xyz` — per-part shape scaling for geometry proportions.
- `rest_rotation_xyz_deg_blender` — alignment correction if the donor is posed.

The donor garden tractor's rear turf tyres are listed as 508 mm diameter vs B7100 nominal 736.6 mm, and fronts 406 mm vs B7100 nominal 520.7 mm. That suggests starting **uniform per-wheel visual scale factors** of around 1.45 rear and 1.28 front if the original measured meshes agree. These are *starting visual-scale suggestions only*, not final fit or tyre physics calculations. Check measured mesh diameters in Blender before using them. In Godot, the existing physical-wheel dimensions remain independent from imported mesh size.

The source excavator is far smaller than the KX080, and a uniform scaling alone will not produce real KX080 geometry. Do not call a rescaled donor manufacturer-accurate.

A single selected front wheel or track mesh will be instanced twice by the game. **Do not select both left and right assemblies for a shared part**, or the game will render duplicates at both mounts. More complex asymmetric parts may need left/right-specific exports in a later release.

## 6. Export the separated parts

After completing each recipe, save each Blender workbench, then run `EXPORT_RIGS_WINDOWS.bat` or:

```cmd
blender --background landworks/assets/workbench/b7100.blend --python tools/rigging/blender_rig.py -- --stage export --machine b7100
blender --background landworks/assets/workbench/kx080.blend --python tools/rigging/blender_rig.py -- --stage export --machine kx080
```

The exporter refuses blank assignments, missing meshes, repeated object assignments, source hash mismatch and invalid pivots/scales. It **does not** infer mechanics. It outputs eight part GLBs into `landworks/assets/rigged/` plus per-machine JSON export manifests, with SHA256 hashes and pivot records. It never modifies physical vehicle collision shapes.

## 7. Fit and verify in Godot

Open `project.godot` in Godot 4.6; run `landworks/scenes/test_yard.tscn` (F6). When a valid imported part GLB exists, it replaces only its placeholder visual. The chassis and controls remain playable if any part is missing.

Press **F3** (keyboard) or **D-pad up** (controller) to show/hide 3D axis markers at the chassis, wheel centres and excavator mechanical pivots:

- red = positive X;
- green = positive Y;
- blue = positive Z.

In the neutral pose, each imported mesh should be correctly centred on its pivot and aligned to the machine's -Z-forward, +Y-up convention. Rotate the arm and verify that the parent/child parts meet at pins without changing length or teleporting. If not, adjust the worksheet and re-export.

**Important:** v0.3 excavator arm pivots remain *kinematic visual animations*, not hydraulic physics joints. Track motion and terrain cutting are also not yet simulated. Do not confuse visual alignment with realistic excavator hydraulics.

## 8. Known limitations and next engineering milestone

1. Neither original CC0 donor binary was shipped with this archive; model inspection requires obtaining the actual files.
2. Blender scripts are unexecuted in this environment (Blender not installed). `scan_glb.py` has automated tests using synthetic GLB data; that tests metadata, not real donor geometry.
3. Local visual geometry can be re-exported from Blender. No direct Tinybox integration, multiplayer or save integration yet.
4. Once rig fits are verified, next stage is trailer/towing and **force-based boom, stick, bucket joints**, followed by excavatable terrain.

Licensed project code can be maintained in a Landworks repository, using Git LFS for `.glb` and `.blend`; check per-file source licences before committing downloaded assets.
