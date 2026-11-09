# Real Godot physics acceptance gates

The CI runner executes seven headless Godot 4.6.1 / Jolt scenarios and archives their original
measured telemetry. These acceptance checks run **after** the Godot process, so a passing
Python source test cannot impersonate physical simulation.

Command: `python3 tools/validate_physics.py --dir field_test_results`.

## Provisional test expectations

- B7100HST + dynamic trailer: moves >3 m, speed 2–17 km/h, braking displacement
  between 0.05 and 15 m, hitch separation <0.25 m, no jackknife/tipping.
- KX080-3 prototype + physical suspended payload: 250/500 kg rise at least 0.8 m,
  overloaded 1000 kg stays below 0.25 m, motor-controlled slew stays 45–105 degrees,
  straight-track scenarios travel 1–15 m, and hold drift stays below 0.2 m.
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
