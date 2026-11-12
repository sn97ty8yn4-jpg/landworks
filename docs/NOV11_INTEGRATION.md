# November 11 development integration

Consolidated locally on 12 November 2026 (Australia/Sydney).
This is the current integration record; older README sections and package
validation claims describe earlier builds, not proof of this build's behaviour.

## Sources and precedence

1. **Create Machine Illustrations**: detailed model package delivered as
   `Landworks_Detailed_Machines_Windows.zip`. Recovered from Downloads, not
   from GitHub main. Contains articulated B7100 and KX080 meshes, fitted pivot
   geometry, hydraulic linkage visuals, wheel/track animation and tests.
2. **Landscape Render Terminology**: the user's final answers supersede the
   early panorama-only proposal. The supplied Durham_Park_360_Landscape_Pack.zip
   is now integrated using its four original images, without replacing or
   editing them. See LANDSCAPE_INTEGRATION.md for the prototype limitations.
3. **Excavation Physics Questions**: all 15 answers are requirements for staged
   development. GitHub PR #1 contains an architecture and test plan only.
   Both documents are now included locally without merging the remote PR.

Repository baseline: `ac8a95db00e24db45edefefd0c98494dbc0606a6`.
Recovered machine ZIP SHA-256:
`699b1c571166d92158fdf345f361ee10ad136d8b934e1b1396e7a3e402d3c47d`.

## Machine integration

Imported the detailed visual assets and animation scripts, sandbox boom-base
pin correction, bucket toe collider correction, matching wheel contacts, zoom
and inspection controls. The original lab geometry remains available.
The current below-grade terrain changes are retained during the merge.
The package's historical Linux validation is not Windows validation.

## Locked landscape direction

- Hunter Valley farmland; geographically and botanically credible eucalyptus,
  pasture, wooded ridges and scattered farms. Hand-painted anime aesthetic,
  muted natural greens/golds, fixed golden afternoon, static painterly clouds.
- Target playable terrain 250 x 250 m, 10–30 m elevation variation and roughly
  150 m camera travel. These are design targets, not current terrain dimensions.
- Switchable follow, orbit and operator perspectives; machine-specific pitch.
- Far panorama: seamless equirectangular sky and ridges, apparent 2–8 km.
- Three separate illustrated middle-distance layers: roughly 300 m–1.5 km,
  light readable parallax, trees/pasture/scattered farm structures.
- Directional variation and moderate ridges; sky openness and farm density vary
  by direction. Soft far edges and clearer nearer silhouettes.
- Roads are permissible but must not terminate into the playable area or imply
  an available route. Avoid powerlines, town clusters and bright infrastructure.
- Blend with terrain shape, haze and directional tree/shrub masks. Preserve
  depth from elevated viewpoints (E3B). Scenery must not obstruct near cameras.
- Minimal rendering cost; mid-range Windows target, 60 FPS objective. Retain
  Compatibility and prioritise the machinery/soil simulation.
- Original proposal: 8192x4096 master, 4096x2048 or 8192x4096 runtime after
  measurement. Do not label a concept board or sector crop a seamless panorama.

## Physics integration and remaining scope

See PHYSICS_V2_ARCHITECTURE.md and PHYSICS_V2_TEST_PLAN.md for the full
requirements. All fifteen user selections remain in scope of that roadmap:
engineering-based forces, mixed and wet materials, variable strata and stones,
teeth/edge/bucket geometry, hydraulic relief and stall, flowing/segregating soil,
progressive failure, wet-ground traction, rutting/bogging, compaction, physical
rock extraction/breakage, additional implements, local 1–3 cm contact detail,
adaptive 60 FPS target, and the complete excavate/haul/dump/grade cycle.

First foundation implemented here: remove the permanent yard collision from
the active pad, remove the painted surface overlay there, include below-grade
soil in volume accounting and bound excavation at a provisional -3 m base.
This does not implement the dry-mass/water ledger, stratigraphy, force-before-cut,
calibrated cylinders, adaptive terrain, rutting or the complete job chain.
Do not describe this build as the completed Physics v2 simulator.

## Acceptance

Validate actual Windows Godot/Jolt import, detailed geometry, articulation,
digging, soil balance, pad entry and below-grade collision. Inspect rendered
views of both machines. Landscape acceptance requires the original assets,
eight compass directions, travel/elevation checks, seam checks and foreground
visibility checks. Record outcomes separately from the targets above.
