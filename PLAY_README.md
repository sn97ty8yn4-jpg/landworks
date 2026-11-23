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

**Which build am I running?**

Top right of the screen, and in the window title: `Landworks v0.9.0 • build
<commit> • <date>`. Run from this folder it is read live out of the
repository, so it cannot go stale — if it does not match what you expect,
you are running a different copy.

**Controls — keyboard**

Press **F1** in game for the same list; that overlay is the authority and
this table is copied from it.

| Action | Key |
| --- | --- |
| Change machine | Tab |
| Orbit camera / zoom | Z, C / mouse wheel |
| Cab or follow view | V (arrows or right-drag to look, Home to centre) |
| Tractor: travel / steer | W, S / A, D |
| Excavator arm (dipper) | W, X |
| Excavator boom | keypad 8, 2 |
| Excavator bucket | keypad 4, 6 |
| Slew | A, D |
| Boom offset | keypad 7, 9 |
| Left / right track | arrow keys (hold Shift to reverse) |
| Blade | up / down arrows |
| Stop tracks | S |
| Boom and arm, either pattern | I/K and O/L |
| Release the lifting strap | G |
| Dump soil / tip the trailer | R / N, B |
| Drop or re-couple the hitch | H |
| Reset all machines | F8 |
| Swap ISO to SAE pattern | F6 |
| Inspection view / old yard | F2 / F12 |

The excavator ships on the **ISO** pattern.

**Controls — gamepad (PowerA Wired Controller for Nintendo Switch 2)**

| Action | Control |
| --- | --- |
| Arm out and in, slew | Left stick |
| Boom (pull back raises), bucket (push left curls) | Right stick |
| Each track forward | L / R |
| That same track in reverse | ZL / ZR |
| Blade, or tip the trailer on the tractor | D-pad up / down |
| Boom offset | D-pad left / right |
| Strap on the digger, hitch on the tractor | A |
| Change machine / reset | Plus / Minus |
| Re-bind any of it | F7 |

Soil tips out when you turn the bucket over — there is no dump button on
the pad.

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
