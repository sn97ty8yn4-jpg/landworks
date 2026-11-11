# Kubota KX080-3 cab operator view — first implementation

## Scope

This is a **visual and camera** layer added to the existing articulated
Jolt KX080-3 proxy. It does not change bucket power, tracked traction, dig
forces, soil conservation, mass or collisions.

The cab is mounted under `excavator.upper` rather than the fixed chassis,
so the seated camera rotates and tilts with the physical slewing upper body.
The forward view is along upper-local `-Z`, offset to `x=-0.50` (left-side
operator station). Initial camera eye is upper-local
`Vector3(-0.50, 2.58, -0.49)`. The eye and console measurements are
**visual estimates** from the existing proportional procedural cab shell,
not OEM-surveyed dimensions.

A named driver avatar is hidden in first-person to prevent head clipping.
The windshield's transparent front pane is hidden only in first-person
to preserve visibility; structural frames and the wiper remain visible.
When leaving the cab the glazing and operator return.

## Movement

Two pivoting joysticks and two independent travel hand levers with rocker
foot pedals are constructed as non-colliding visual geometry. Rubber
bellows and grips move together with the gimbal. Travel levers and pedal
rockers use the same left/right track commands.

The cab **does not re-read the controller**. The operating excavator exposes
`cab_input`, which is updated from the commands actually sent to the
boom, arm, bucket, slew and crawler solver. That state is copied to the
operator station once per render frame and filtered with a 16 s^-1
first-order response. Controls return to neutral when commands return to 0.
Scripting test commands also animate controls.

| Physical operator control | Animated function | Existing game input |
|---|---|---|
| Left joystick fore/aft | Arm | O / L or gamepad right stick Y |
| Left joystick lateral | Swing/slew | Q / E or L1 / R1 |
| Right joystick fore/aft | Boom | I / K or gamepad R2 / L2 |
| Right joystick lateral | Bucket | P / ; or gamepad right stick X |
| Left travel lever and pedal | Left track | W/S, A/D or left gamepad stick |
| Right travel lever and pedal | Right track | W/S, A/D or left gamepad stick |

**Note:** this is a realistic mapping of cab controls to *machine functions*,
but the original gamepad has different button/stick mappings from the actual
excavator's two-lever ISO pattern. Remapping the gamepad to authentic ISO
while preserving independent travel controls requires an explicit controller
configuration pass, not an unannounced breaking change. The joystick travel
angles are visual estimates, not Kubota measured travel limits.

## Controls

- **V:** switch from third-person to seated cab view while operating KX080-3.
- **Arrows or Z/C:** turn the operator's head; up/down changes pitch.
- **H / J:** lean left or right to see the track and bucket-side work.
- **Home:** recenter head.
- **M:** capture/release mouse for free head-look; **Esc:** release cursor.
- **Tab / Triangle:** select another machine, automatically returning to
  third-person view.
- All previous machinery controls, F1 help, R tip and G hook stay intact.

The in-cab HUD moves to the bottom left to preserve windscreen visibility.
A first-person FOV of 74 degrees provides an initial balance between
natural perspective and usable field of view; adjust after a Windows
inspection on the intended display.

## Acceptance gates

1. Seat camera is a child of the physical upper carriage and does not move
   independently during slew; no eye clipping through head, roof or windscreen.
2. Both joystick pivots respond to their corresponding boom/arm/bucket/slew
   command simultaneously; all release to neutral.
3. Travel pedal and hand lever on each side follow exactly the corresponding
   track request, including opposite-direction neutral turning.
4. No changes to rigid body masses, geometry, torque caps, soil handling or
   test cases.
5. Cab can be entered/exited without hiding the exterior operator permanently.
6. Front window and pillars remain visible without overwhelming the bucket
   view; track access and digging are still possible in first-person.
7. Validate on Windows with camera screenshots at forward, downward trench,
   ±90° side look, loading and backfilling positions.
8. Run `godot --headless --path . --script res://landworks/scripts/cab_control_smoke.gd`.
   Existing integrated field trials must still pass.

## Reference hierarchy

1. Kubota KX080-3 Australian operator manual (2007), especially pp. 4–5,
   14 and 25–32: physical drive levers/pedals, lock lever, layout and TPSS.
   https://www.flexihire.com.au/info-hub/Excavator_8_T_Kubota_KX_080_3_Operation_Manual_pdf_dc56cd28e3.pdf
2. Actual KX080-3 sale cab photo:
   https://www.sourcemachinery.com.au/kubota-kx-series-excavator-conventional-swing/58580-kubota-kx080-3-midi-excavator-82t-conventional-swing.html
3. KX080-3 cab photo:
   https://www.theconstructionindex.co.uk/the-digger-blog/view/digger-gets-hands-on-with-the-kubota-kx080-3
4. KX080-4 interior reference (secondary; don't transplant newer digital console):
   https://www.bossmachinery.nl/en/vehicles/Excavator/1365/kubotakx080-4a

## Limitations

Cab furniture is generated from simple meshes, albeit with moving parts,
not a dimensionally verified industrial-grade interior model. There is no
operator hand/foot IK, seat adjustment, armrest unlocking, functional blade
lever, window-opening animation, rain effects or mirror rendering in this pass.
The approximate glass transparency workaround should be reassessed when
authentic cabin textures are imported. Screenshots and perceptual alignment
require Windows / real Godot execution.
