# Durham Park Sandbox — Landworks

A Godot 4.6.3 / Jolt machinery sandbox with a detailed Kubota B7100 HST,
KX080-inspired excavator, coupled trailer, movable loads and deformable soil.

## Play on Windows

Double-click **PLAY_WINDOWS.bat**. This local workspace includes the runtime
recovered from the detailed-machine package. The launcher imports changed
assets before starting. Alternatively, open `project.godot` in Godot 4.6.3
and press F5. Python and Blender are not required to play.

For a fresh GitHub checkout, install Git LFS and run `git lfs pull` to fetch
the detailed GLB models. The engine runtime is local-only; install Godot
4.6.3 separately when playing from a fresh source checkout.

Tab switches machines; W/S drive; A/D steer; Z/C orbit; mouse wheel zooms;
F2 toggles inspection view; F1 displays the full controls. Excavator controls:
I/K boom, O/L stick, P/semicolon bucket, Q/E slew, R dump and G load hook.
V enters/leaves the detailed cab. Use arrow keys or right-drag to look around;
Home centres the view. The original joysticks and travel controls now animate.

## Current integrated build

- Detailed segmented meshes, rotating/steering tractor wheels, circulating
  track visuals, moving hydraulic cylinders and bucket linkage.
- Physical machines, trailer hitch and movable loads run in one Jolt world
  at 120 Hz. Detailed cosmetic meshes follow the physics bodies.
- An 18 m mutable soil pad supports below-grade digging, with a provisional
  3 m excavation limit. The surrounding 140 m yard no longer covers trenches
  with a hidden collision floor or painted grass surface.
- The playable soil path conserves dry constituents and water, swells dug
  material, loads the physical bucket, and gates cuts on solved motion and
  available hydraulic force/work. Mixed dumps retain their material masses.
  Depth strata, compaction/ruts and calibrated hydraulics remain future work.
- The original landscape panorama and three illustrated parallax layers are
  integrated, replacing the old distant hills/clouds/trees. Their source PNGs
  remain unchanged. Runtime seam blending joins the prototype strips; motifs
  repeat, and the supplied artwork is below the planned 8K master resolution.

## Folder layout

| Path | Contents |
| --- | --- |
| `PLAY_WINDOWS.bat` | Launch the game (uses the bundled engine in `runtime/`) |
| `RUN_INTEGRATION_TESTS.ps1` | Windows engine integration checks; logs to `validation/` |
| `landworks/` | Game: scenes, scripts, soil data, engineered models, landscape art |
| `tools/` | Python tooling; `tools/windows/` holds the secondary Windows launchers |
| `tests/` | Offline Python test suite |
| `docs/` | Current design and integration notes; `docs/archive/` holds superseded v0.5/v0.6, handoff and import notes |
| `runtime/` | Local Godot 4.6.3 engine (not in git) |
| `validation/` | Test output, screenshots and `logs/` (not in git) |

## Development record

See [November 12 advancement review](docs/ADVANCEMENT_REVIEW.md) for the
bucket orientation correction and assessment of the later cab/physics work.
See [runtime soil and detailed cab integration](docs/MATERIAL_CAB_INTEGRATION.md)
for the active mechanics, visual changes, checks and remaining limitations.
Run `python -m unittest discover -s tests -v` for the offline Python suite.

Start with [November 11 integration](docs/NOV11_INTEGRATION.md) for the three
source chats, accepted decisions, imported work and remaining requirements.
See [machine integration](docs/DETAILED_MODEL_INTEGRATION.md),
[physics architecture](docs/PHYSICS_V2_ARCHITECTURE.md) and
[physics acceptance plan](docs/PHYSICS_V2_TEST_PLAN.md).

The full Physics v2 specification is a roadmap, not a claim that its features
are implemented. The 250 x 250 m rolling landscape is also a target; this
build retains the existing working yard with a non-interactive visual surround.

Historical v0.4–v0.6 development notes are in
[Development history](docs/archive/DEVELOPMENT_HISTORY.md). Their older statements
about missing models or untested runtimes do not describe this integration.

## Validation

Run `RUN_INTEGRATION_TESTS.ps1` in PowerShell for the Windows engine import,
model alignment, articulation, soil conservation, below-grade collision,
pad-entry, digging, hydraulics and hook checks. Logs go to `validation`.

The thirteen field scenarios remain available through
`tools/run_work_tests.py`; validate their measured CSVs with
`tools/validate_physics.py --dir validation/field`.

These tests verify the prototype's behaviour. They do not establish OEM
calibration, a complete granular simulation or a measured 60 FPS guarantee.
See [Windows results](docs/WINDOWS_INTEGRATION_RESULTS.md) for this build's
measured checks and [landscape integration](docs/LANDSCAPE_INTEGRATION.md)
for source provenance, geometry and remaining visual limitations.
