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
  tracks carry the chassis 1–15 m, and hold drift remains below 0.2 m.
- A missing, invalid or nonfinite measurement fails the build.

**These ranges are regression gates, not manufacturer performance envelopes.**
They do not establish excavator safe working load, travel slope ratings, stability on
real soil, or equivalence to the actual Kubota machines. When the model improves,
these gates must be re-evaluated alongside OEM load charts, calibrated torque,
fuel consumption, suspension settings, controller feedback and terrain.
