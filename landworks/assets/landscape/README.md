# Durham Park Sandbox — 360° landscape artwork pack

## Included files

- `assets/00_far_sky_panorama_2to1.png` — 1774 × 887 RGB panorama, for sky/backdrop prototype.
- `assets/03_parallax_far_wooded_hills.png` — 2172 × 724 RGBA; distant wooded slopes (roughly 1–2 km apparent depth).
- `assets/02_parallax_middle_pastures.png` — 2172 × 724 RGBA; pasture hills, eucalypt treelines and occasional buildings (roughly 600 m–1.5 km apparent depth).
- `assets/01_parallax_near_farms_treelines.png` — 2172 × 724 RGBA; closest illustrated rural features (roughly 300–800 m apparent depth).
- `landscape_contact_sheet.jpg` — visual index, with transparency displayed over blue-grey.
- `manifest.json` — file list and SHA-256 hashes.

## Initial Godot 4 setup

1. Import the PNG images into your Godot project.
2. For the background, create a `WorldEnvironment` using a `Sky` resource with `PanoramaSkyMaterial`, and assign `00_far_sky_panorama_2to1.png` to its panorama texture.
3. Treat the three RGBA strips as **independent alpha-blended illustrated layers**, not additional sky textures. Place them in a camera-relative parallax system or inward-facing non-colliding curved cards/rings with carefully chosen depth and height. Their 3:1 aspect ratio does **not** imply a full equirectangular sphere; a custom cylindrical UV layout or appropriately mapped segments will be needed.
4. Order layers far → middle → near and tune horizon alignment and fog. Keep the close 3D playground and machinery in front of these layers. Disable collisions/shadows for backdrop layers.
5. Test from first-person, behind-machine, and elevated viewpoints before adopting the artwork.

## IMPORTANT — production readiness limitations

These are **original, importable concept/prototype images**, not yet a technically validated seamless 360-degree environment. The 2:1 aspect ratio of the panorama fits the sky material's texture format, but doesn't prove its composition is correct over the full vertical sphere. The three RGBA strips have transparent backgrounds, but they are separate 3:1 landscape strips, not automatically wrap-ready 360° panoramas. There are visible edge differences; left/right tiling, perspective consistency and actual in-engine camera behaviour need validation and perhaps retouching. The images are 1774×887 and 2172×724, not the earlier discussed 8K master resolution. No engine scene, mesh or collision geometry is included.

Art direction: natural Hunter Valley agriculture, wooded distant ridgelines, illustrated eucalyptus and rolling fields, fixed golden-afternoon light, no roads terminating in playable area. Asset pack prepared 12 November 2026.
