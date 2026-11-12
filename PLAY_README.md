# Play Landworks — detailed machinery edition

## Windows playable package

1. Extract the **whole ZIP** to an ordinary folder.
2. Double-click **PLAY_WINDOWS.bat**. The first launch imports the game assets;
   later launches go straight to the game.
3. No Python, Blender, paid asset service or separate engine installation is
   needed in the Windows playable package. Keep its `runtime` folder intact.

The package includes the unmodified official **Godot 4.6.3 Windows x64**
runtime/editor executable. Its download was checked against the release's
SHA-512 manifest. Engine copyright, MIT licence and dependency notices are in
`runtime`. The engine is the official binary; the game source is independent.

**Controls**

| Action | Key |
| --- | --- |
| Switch tractor / excavator | Tab |
| Drive / reverse | W / S |
| Steer or differential crawler turn | A / D |
| Orbit camera | Z / C |
| Zoom | Mouse wheel |
| Low inspection camera | F2 |
| Controls overlay | F1 |
| Enter / leave excavator cab | V |
| Look around cab | Arrow keys / right mouse drag |
| Centre cab view | Home |
| Boom | I / K |
| Dipper | O / L |
| Bucket | P / semicolon |
| Slew | Q / E |
| Dump captured soil | R |
| Hook nearby loose object | G |

Drive the excavator forward onto the earth pad and scrape its bucket lip
through a bank. The bucket must physically enter and move through soil.
Watch the HUD's bucket volume and dump with R. The crate, log and blocks are
free physics objects. The tractor tows a physically hitched loaded trailer.

This local integration has been exercised with Godot 4.6.3 on Windows:
real Compatibility-renderer screenshots and Jolt integration checks.
See `docs/WINDOWS_INTEGRATION_RESULTS.md` for measured results and limits.
A long interactive playthrough and 60 FPS performance qualification are
separate from these scripted checks.

## Detailed models and editable source

This package contains the integrated detailed tractor and excavator, split into
working parts, plus the editable Godot project and conversion script. Read
`docs/DETAILED_MODEL_INTEGRATION.md` for geometry adjustments, physics scope
and validation. Original Blender scenes are in the earlier detailed model pack.

## Scope of this build

Detailed machinery, the existing painted test meadow, a single editable 18m
soil pad and hybrid mobile soil parcels. Full granular particle collisions,
calibrated OEM hydraulics, track-chain contact and an expanded world remain
future work. This update integrates the detailed models, opens the soil pad
for below-grade excavation and consolidates the November 11 decisions.
See `docs/NOV11_INTEGRATION.md` for landscape recovery and Physics v2 status.
