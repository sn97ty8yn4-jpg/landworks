# Real Godot physics acceptance gates

The CI runner executes eleven headless Godot 4.6.1 / Jolt scenarios and archives their original
measured telemetry. These acceptance checks run **after** the Godot process, so a passing
Python source test cannot impersonate physical simulation.

Command: `python3 tools/validate_physics.py --dir field_test_results`.

## Provisional test expectations

- B7100HST + dynamic trailer: moves >3 m, speed 2–17 km/h, braking displacement
  between 0.05 and 15 m, hitch separation <0.25 m, no jackknife/tipping.
- KX080-3 prototype + physical suspended payload: 250/500 kg rise at least 0.8 m,
  the nominal 1000 kg long-reach stall remains below 0.25 m, motor-controlled slew
  stays 45–105 degrees during successful lifts, straight-track scenarios travel
  1–15 m, and hold drift stays below 0.2 m.
- When a lift cannot get 0.5 m clear of its initial position, the AUTOMATED
  test operator does not command slewing or travel. Failure to lift is not
  treated as permission to drag a load across the ground. This is a test
  procedure, not an enforced safety function of the player's excavator.
- The current 1000 kg long-reach stall is a tuning state, not an OEM rated
  load or a verified hydraulic overload condition. Capacity changes with
  hook radius, height, direction and blade position.
- Opposed-track 500 kg pivot scenario: the hull rotates at least 35 degrees with
  horizontal drift at most 0.9 m. A stationary turn is *not* required to travel 1 m.
- The tracks use four independently computed contact-patch forces with longitudinal
  traction and bounded lateral skid; chassis box friction is deliberately low to
  avoid double-counting resistance. This is not a calibrated soil model.
- A missing, invalid or nonfinite measurement fails the build.

**These ranges are regression gates, not manufacturer performance envelopes.**
They do not establish excavator safe working load, travel slope ratings, stability on
real soil, or equivalence to the actual Kubota machines. When the model improves,
these gates must be re-evaluated alongside OEM load charts, calibrated torque,
fuel consumption, suspension settings, controller feedback and terrain.

## Ground-contact material handling

A 1000 kg grounded box is connected to the bucket hook and the machine tries to
**drag** it. A free 1500 kg crate can be **pushed** by a steel bucket-toe contact
shape. A free 1000 kg cylindrical drum can **roll** under the same bucket.
All bodies use Godot Jolt collision forces and gravity. The scripts never set
the objects' travel velocities or final positions. CI checks at least 0.4 m of
horizontal object displacement; the cylinder must physically rotate at least
45 degrees. The provisional friction values are not calibrated for soil rutting
or ground disturbance. An object that fails to lift is still allowed to move
horizontally when sufficient crawler force and ground contact are available.

## Playable demonstration shortcuts

Open the main yard and press F9 (drag the 1000 kg hooked object),
F10 (physically push the 1500 kg free block), or F11 (push/roll
the 1000 kg free drum). These launch automatic work demonstrations
using the same Jolt rigid bodies as CI. F8 continues to launch
the default 500 kg live-lift scenario. The demo scripts do not
provide fully interactive digging controls yet.

The track-normal estimate now excludes grounded loads rather than
granting the excavator extra driving grip simply because it is
pushing or dragging a heavy object. The provisional 8.17 t
machine-mass value excludes the load itself.
