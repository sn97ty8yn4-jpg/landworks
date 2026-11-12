# Original landscape integration

Source: the user's `Durham_Park_360_Landscape_Pack.zip`, recovered from
Downloads on 12 November 2026. All four PNG SHA-256 hashes match the supplied
manifest. No newly generated image from this chat is used in the game.

`landworks/assets/landscape` retains the original README, manifest and contact
sheet. Their readiness warnings are preserved as provenance. The new runtime
implementation is `landworks/scripts/landscape_backdrop.gd`.

## Implementation

- The 1774 x 887 panorama is rendered as an infinite sky. A lightweight sky
  shader blends the left/right seam and adjusts vertical horizon alignment.
  Source: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html
- Three 2172 x 724 RGBA strips use world-anchored cylindrical geometry at
  450 m, 850 m and 1400 m radius. Camera translation therefore creates actual
  relative parallax. Each ring has 192 segments; no per-frame mesh rebuild.
- The strips are not full spherical maps. Six curved sectors per ring retain
  reasonable tree and building proportions; narrow alpha-weighted seam blends
  soften mismatched edges. This repeats motifs and does not invent unique
  geography for every compass direction.
- Alpha-cut silhouettes retain normal depth testing. Scenery casts no shadows
  and creates no physics nodes. Existing machines and ground occlude it.
- A visual-only terrain skirt bridges the 140 m yard to the distant layers.
  It does not expand the playable collision world to the planned 250 m map.
- Removed runtime construction of old distant ridges, modelled clouds and
  decorative trees; reduced grass, flowers and stones. Nearby barn/fences and
  the interactive soil and machinery remain in 3D.
- Fixed the existing meadow material's back-face culling so it covers the
  background beneath machines; its exact pad opening leaves trenches visible.

## Validation and limits

Windows Godot 4.6.3 Compatibility rendering captured eight bearings at 1.7 m
and 30 m elevation, with the elevated viewpoint at the yard edge. The test
also rejects any collision node in the backdrop. Representative frames were
visually inspected; this is not a pixel-by-pixel certification of every join.

The camera remains inside all belts. Original 3:1 art is a concept/prototype:
repeated farms/trees and blended seam regions remain, and low sky resolution
looks soft at 1080p. Elevated views reveal the simplified terrain transition.
This is a working integration of the requested artwork, not a new seamless
8K master, finished 250 m rolling map or performance qualification.

To reproduce the captures, run Godot with the Compatibility renderer and
`--script res://landworks/scripts/landscape_smoke.gd`. Images are written to
`validation/landscape/compass`; normal machine views use `visual_snapshot.gd`.
