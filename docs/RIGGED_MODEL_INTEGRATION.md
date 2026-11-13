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

## Couplings

`landworks/scripts/coupler.gd` serves both the tow hitch and the lifting
strap. Capture is deliberately generous about *where* the two points are and
strict about *what* the machine is doing: the points must fall inside the
capture radius **and** be nearly at rest relative to each other. A released
pair stays disarmed until it has separated past `radius * 1.7`, so a machine
can always drive away from what it just dropped. Both are real Jolt pin
constraints, so a load too heavy to lift or tow still refuses to follow.

| | Tow hitch | Lifting strap |
| --- | --- | --- |
| Carrier point | tow ball, `(0, -0.20, 1.30)` on the tractor | bucket tooth, `BUCKET_TIP` |
| Target point | the trailer's ring hitch | each loose load's origin |
| Capture radius | 0.45 m | 0.95 m |
| Relative speed limit | 1.6 m/s | 2.2 m/s |
| Pin placed at | midway, so neither body is yanked the whole way | the tooth, so the load hangs and swings |
| Release | `H` | `G` / Square |

The hitch starts coupled because the trailer is parked on the ball. Press `H`
to drop it, drive clear, reverse back and it couples itself; the HUD reads
`Hitched`, `READY — hold still to couple` or `Unhitched (H)`, driven by the
same predicate as the capture rule rather than a separate guess.

The strap takes hold on its own. `G` is the release; pressed with nothing held
it re-arms and tries immediately, so an operator can insist rather than wait.
`load_hook_joint` and `attached_load` are now read-through views of the
coupler's live constraint rather than cached copies.

An uncoupled single-axle trailer would nose into the ground, so the jockey
stand is a real collision shape under the drawbar, enabled whenever the
trailer is unhitched. Parked, the drawbar settles 4.8 degrees nose-down onto
the foot and holds. Letting the solver own that contact avoids inventing a
support spring, and the parked trailer can still be shunted.

## Global reset

`F8` restores every machine, the trailer, its tray and the loose loads to the
start condition. It is a deliberate restore, not a physics path, and two
things keep it from being a cheat:

* **It cannot create or destroy soil.** Anything the machines were carrying is
  released as loose material where it actually stood before the bodies move,
  so the bucket and tray come home empty and `mass_totals()` still balances.
  Measured error after a reset: 4e-9 kg.
* **The jump home is never read as a cut.** The bucket's and blade's
  cutting-edge histories are dropped and the pending soil contact is cleared,
  so the next tick does not see a metre-long sweep through the bank and commit
  it. `reset_smoke` asserts the excavated total does not move afterwards.

**The ground is left exactly as dug.** A reset returns the machines, not the
terrain; it is not an undo.

The snapshot is taken at startup and then re-taken once the scene has settled,
about 1.5 s in, because the crate drops onto the ground and the tray takes up
on its hinge. Without that, `F8` restored a pre-settle pose that immediately
sagged 0.15 m. A body that has already moved more than a metre by then was
moved by the player, so its spawn pose stays the thing to restore.

## Faults found by playing it, and their causes

Six faults came back from actual play. `machine_feel_smoke` now measures each
one from the live scene rather than from an internal number.

* **Tracks looked far too narrow.** The shoe plate's 450 mm width runs along
  the mesh's own Y, and the instance transforms applied neither that nor the
  model-to-game quarter turn, so every plate sat edge-on. Separately, the
  MultiMesh silently refused transform writes (a direct `set_instance_transform`
  did not read back), which left all 78 plates at identity. Replaced with one
  mesh node per shoe. Plates now read 1.00 square across the track.
* **Cylinders projected the wrong way.** Barrels are modelled extending +X
  from their pin, rods extending **-X**; both were aimed as +X, so every rod
  pointed out of the back of its barrel. The running direction is now read
  from each mesh's own bounding box.
* **The boom bounced with no input, and stalled short of full lift.** One
  cause: the damping term was taken from the bodies' angular velocity about
  the pin, whose sign does not follow the angle the error is measured in, so
  it *added* to the error. Damping is now the rate of change of that same
  angle. Full lift went from never arriving in 7.5 s to 2.2 s, and the hold
  shows zero direction reversals. What remains is a 1.5 degree one-way creep
  to target, which is settling, not a bounce.
* **The controls felt unresponsive.** `NOMINAL_RADS` still described the old
  joint ceilings, so one lever at full command over-requested pump flow and
  the allocator scaled it back; three together asked 274 L/min against 144.
  The ratings now match the ceilings they serve, and net power to oil went
  36 to 45 kW. All axes always ran together; they were simply all being cut.
* **The trailer would not fill.** The tray was a single solid box, which
  cannot be loaded at all. It is now a floor and four sides, and the soil
  container sits inside it.
* **The tipper dropped the front instead of lifting it.** `tip_angle_rad()`
  had its operands reversed and returned the negative of the real angle, so a
  positive command drove the front down while the number read positive, and
  the test agreed with it. The angle, the pin's limit range and the motor sign
  are all corrected, and the check now measures the tray front's world height.
* **The tractor stuck while hitched.** The hitch pin was placed midway
  between the tow ball and the ring, baking a standing quarter-metre offset
  into the constraint that pulled the tractor back for as long as it was
  coupled. The pin now lands on the ball, and the tray no longer collides
  with the tractor. The resting ball-to-ring gap is asserted under 80 mm.

## The strap that pinned the boom

Found afterwards, by pushing the commit to CI and reading what went red.

The lifting strap armed itself on the first tick and took hold of whatever was
already inside its capture radius. The sandbox spawns a 1500 kg test crate
within reach of the parked bucket, so the strap hooked it before the player
touched a control. The crate was resting on the ground, so the pin tied the
bucket to the ground: the boom then held perfectly still, under a full 0.80
rad/s command and the full 75 kN·m torque cap, at 2.35 MPa. Measured angular
velocity was 0.00001 rad/s for ten seconds while the target swept 0.24 to 0.64
and back. Nothing was under-powered; the boom was anchored.

Where this bites, measured rather than assumed: in the sandbox smoke
configuration the crate stands within reach of the tooth, and the strap took
it. In the playable scene the nearest load sits 7.5 m away, so no grab happens
at spawn there, and this is **not** an explanation for the excavator having
felt awkward — that was the flow mis-rating and the boom damping, both already
fixed. What the fault does show is that the rule was wrong: any load standing
in the zone was taken without being asked.

Coming to a load and having it take hold is the wanted behaviour, so the strap
now stays
**disarmed until the bucket has been clear of a load** (`start_disarmed`), the
same rule that already applied after a release. The tow hitch keeps the old
behaviour deliberately: its trailer spawns parked on the ball and should be
coupled from the first tick. The strap key still arms on demand, so an
operator who wants to insist never has to move away first.

The cost: a load standing beside the bucket at the start is not picked up
automatically until the bucket has been 1.6 m clear of it once, or the strap
key is pressed.

### The gate that agreed with it

`validate_sandbox.py` required `boom_change_deg >= 4.0` to prove "the physics
boom moved", and the pinned run reported **4.221** — earned entirely after the
boom commands had finished, by the chassis being shoved while crawling. The
boom's own answer to a command was 0.45 degrees. A second gate was fooled the
same way: the crate was recorded travelling 2.568 m, but it was being *towed
by the strap*, not pushed by the toe. Honest figures are now 21.440 degrees of
commanded boom movement and 0.890 m of pushing.

The summary therefore carries a new `boom_commanded_deg` column, measured only
inside the window in which the programme actually commands the boom, and gated
at 15 degrees of its roughly 24 degree sweep. Both observed failure modes sat
under 5 degrees. `machine_feel_smoke` places a load on the hook *before the
first physics tick* and asserts the strap refuses it; that check fails on the
old code and passes on the new, and it has to inject its own load because this
scene's props sit 7.5 m away, which is why the existing boom checks never
caught the fault.

## The stops that were in a different frame from the commands

Reported from play as the arm breaking when used, the bucket range being too
limited, and some movements running backwards.

A `HingeJoint3D` limit is measured from the pose the two bodies are in when
the joint is made. Every target, clamp and test here instead talks in
`_joint_angle` terms, the child's rotation inside the parent's frame — and
`target_angles` even starts at `{boom: 0.24, stick: -0.72, bucket: -0.24}`,
which is each limb's build angle. The bands were handed to the joint without
shifting, so the stops landed somewhere else entirely:

| service | commanded band | where the stops actually were |
|---|---|---|
| boom | −1.047 … +1.100 | −0.809 … +1.338 |
| arm | −2.094 … 0.000 | −2.812 … **−0.718** |
| bucket | −0.698 … +1.833 | −0.941 … +1.590 |

The arm's **rest pose was its own upper stop**. Pulling it out could only
stretch the pin, which is the arm appearing to break: measured 62 mm of
separation between the same material point in each body, and 100 mm at the
bucket, against the 40 mm this project already holds itself to elsewhere. The
lowest 0.238 rad of the boom's commanded travel sat below its stop and the top
0.243 of the bucket's curl sat above its own, so those parts of the levers did
nothing. Nothing was inverted — one direction of each service simply ended at
a stop that was not where the lever thought it was. (The boom also refuses to
lower with its bucket already resting on the ground, which is not this fault.)

`_make_hinge` now shifts each band into the joint's own frame, and the band is
kept beside the joint that enforces it so callers clamp against one source of
truth rather than typing the numbers again. Measured after: the stops land on
their bands to within 0.01 rad, the worst pin separation across a full sweep
of every service is **16 mm**, and the arm holds −1.196 rad on command where
it could previously only reach −0.729.

The bands themselves were then widened, since the first pass gave the bucket
only 26 degrees of dump: the arm goes to 135 degrees and the bucket to 180.

### The hinge limit is symmetric

Shifting the bands was still not enough, and chasing why turned up the real
constraint. With the motor at full command and full impulse, the bucket free
in the air and flow unrestricted, the curl simply stopped at `_joint_angle`
+0.722 and stayed there. In the joint's own frame that is **+0.96, the exact
magnitude of its lower bound**. The earlier band said the same thing: with
−0.698 … +1.833 the bucket had stopped at +0.698.

This engine's `HingeJoint3D` applies its limit **symmetrically** — the bound
smaller in magnitude becomes the stop on both sides — so an asymmetric band
cannot be expressed on the joint at all. The joint now carries a symmetric
backstop wide enough for the whole band, and the band itself is held by the
target clamp, which is the only place it can be asymmetric. The bucket went
from 54 degrees of curl, to 91 once the frame was right, to **149**.

Two things were tried along the way and undone, which is worth recording so
they are not tried again. Raising the arm and bucket torques to 60 and 28 kN·m
looked like the fix while the limit was still biting; it was not — with the
limit fixed the curl is the same 148.6 degrees at the original 45 and 20, and
the extra torque only bought pins the solver could not hold. Taking the
ground-handling toe off the sandbox bucket, on the suspicion it was jamming
against the arm, made the separation far worse (1.14 m) and was reverted.

What did matter was the solver. A chain of heavy bodies on powered pins was
running at Jolt's default 10 velocity and 2 position steps. With the bucket
now reaching poses it never could before, the default settings pulled its pin
**204 mm** out of line in clear air; at 16 velocity and 8 position steps that
falls to **66 mm**. Doubling again to 24 and 16 bought 5 mm more and was not
worth the time, and raising velocity steps alone did nothing — the position
steps are what hold the chain together.

That change failed `coupling_smoke`, which looked like the trailer nosing
over at 66 degrees. It was not: the test parks the trailer by placing its
drawbar ring, which puts the body 0.70 m below the tractor's own origin and
so well under the ground. It had never been standing on its jockey foot — it
was settling up out of the terrain onto its nose, reporting the same 66
degrees every run, and only passing because the weaker solver pushed it out
gently enough to land flat. It is now dropped in from clear air, which is
what parking it means, and reads 4.8 degrees.

The damping term also needed attention. It took the rate of change from a
single tick's difference, which at 120 Hz multiplies solver noise by 120, and
the boom buzzed at rest, reversing direction on 599 of 600 samples where it
had settled with none. The rate is now smoothed over about four ticks.
Reversals are back to 0 and full lift still arrives in 2.3 s. The feel gate
was not touched. A stalled service also eases its torque now, standing in for
a relief valve lifting rather than a pin being dragged out of line.

The reset check needed the same treatment. It waited a fixed two seconds and
then measured once, which landed in the middle of the rock a 9 tonne machine
does when it is set back down on its tracks — and with the bucket hanging
4.5 m out, a fraction of a degree of chassis roll swings it a long way. The
same reset read anywhere between 10 and 160 mm depending only on which part of
the swing was caught, and it had been passing on phase. It now waits for
sustained quiet rather than a single tick under the threshold (which is also
what the far end of a swing looks like) and averages the offset over a second,
since drifting away means a persistent offset. Reading 82 mm against a limit
of 120 that was not touched. Worth knowing: the machine never goes perfectly
still, idling with a wobble under 20 mm/s, so the wait reaches its ten second
cap every time.

### Two things that turned out not to be broken

* **The slew.** A first probe showed both slew keys turning the house the same
  way. The probe was at fault: it let `slew_target_rad` accumulate between the
  two directions and read world yaw rather than yaw relative to the
  undercarriage. Driven properly the slew follows +0.59 for +0.60 and −0.57
  for −0.60.
* **The excavator's mass.** Reported as much too low; measured at 8,760 kg
  across the seven bodies, which is right for this class, and full-lever
  travel tops out at 2.9 km/h against 2.9 for the real machine's low range.
  Nothing was changed. If it still reads light in play it is not the mass.

## The camera that did not follow

`orbit_yaw` was an absolute world bearing, so the camera held its heading
while the machine turned under it and drove out of frame. It is now an offset
from the followed machine's heading, smoothed, with the look-at point riding
in the machine's frame so it stays ahead rather than drifting to one side.
Both machines spawn facing yaw 0, so every angle tuned against the old
behaviour still frames what it used to. Measured: the machine turns 0.80 rad
and the view bearing moves 0.018.

## Control pattern

The sandbox shipped the ISO pattern — arm and swing on the left lever, boom
and bucket on the right. That is the default and is what play confirmed as
correct. `F6` swaps to SAE, which exchanges boom and arm, as the valve on a
real machine does. The older single-purpose keys keep their own service in
either pattern. Which lever works which service is measured by pressing the
key and seeing which target moves, not read off the source.

## Trailer wheels

The trailer was still rolling on the procedural tyres. Two faults together:
`M.tyre` hangs its meshes off a support node, and the hide pass only looked
one level down, so nothing was ever hidden; and the modelled `Wheel_L` and
`Wheel_R` sat rigid inside the bound chassis, where they could not turn. Each
modelled wheel now moves onto the hub the trailer already rolls, keeping the
rotation it carries in the model — `_bind` replaces a part's basis, which is
right for a limb on its own origin and would lay a wheel flat. The hide is
recursive, and the check counts any mesh still drawing on a hub that did not
come from the model.

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
* **`visual_snapshot`** still asked the procedural visuals for the operator
  station. The excavator stopped being dressed by them when the model was
  bound, so `machine_visuals.cab` was null and the two cab frames were never
  written. The renderer exits 0 regardless, so only the step's `SCRIPT ERROR:`
  grep failed the build — the frames had simply been missing from the CI
  artifacts since the model went in. The visual workflow last passed at
  `35f2fa2`, the commit before the integration. It now asks whichever owner built a cab
  and refuses to continue if neither did, and the workflow asserts all six
  frames rather than two, so a missing frame fails on its own.
* **`machine_controls_smoke`** is new. It asserts that every service's stops
  land on the band its lever commands, that a lever cannot ask for an angle
  outside it, that sweeping each service does not pull a pin apart, that the
  bucket keeps a usable curl, that the camera follows the machine round, that
  each lever works the service its pattern says, and that the trailer rolls on
  the modelled wheels with nothing procedural still drawing. Reverting the
  stop shift alone fails it on all three joints, which is what it is for.
* **`reset_smoke`** had been passing on phase. See the reset note above: it
  waits for sustained rest and averages the offset over a second now, with
  its 120 mm limit unchanged.

## Known limitations

* **The bucket pin still separates about 66 mm** at the extremes of its
  travel, in clear air, with nothing touching it. That is down from 204 mm at
  the old solver settings, but it is not good. It shows now because the bucket
  reaches poses it never could before. The gate is set at 85 mm to catch a
  return to that, not to bless 66. Lowering the bucket cylinder torque barely
  moved it (66 mm at 20 kN·m against 63 at 28), so the remaining separation is
  the solver rather than the load.

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
