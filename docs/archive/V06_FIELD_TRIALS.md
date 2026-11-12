# Landworks 0.6 — tractor towing and excavator working-load verification

## What has actually been executed in the authoring environment

- Python structural checks, static engineering force calculations and an **independent reduced-order dynamics surrogate** (see `tools/surrogate_dynamics.py` and `tools/engineering_precheck.py`).
- **NOT** the actual Godot real-time dynamics: the Godot 4.6 binary and the required renderer/physics runtime are unavailable in the authoring container. Consequently, **no tractor or excavator Godot result is claimed**. The physics scenes themselves need running on a Windows PC with Godot 4.6.
- The surrogate is not an excavator training simulator or OEM safety/load chart. All weights, terrain coefficients, motor torques, track force caps and braking factors are provisional gameplay calibration values.

## Real Godot physics scenarios included

### B7100 tractor with coupled single-axle trailer

`landworks/scenes/tractor_work_lab.tscn` includes an independently simulated 320 kg single-axle trailer with a rigid-body payload allowance and a **PinJoint3D** tow hitch. Wheel-to-ground raycasts provide spring, damping, rolling resistance and transverse tyre forces. The tractor's original tyre contact and force engine are retained, with an optional **15 km/h input-side working speed governor**, which does not hard-clip body velocity on downhill slopes.

| Scenario | Incline | Additional payload | Programme |
|---|---:|---:|---|
| `flat_empty` | 0° | 0 kg | Settle, pull, brake, turn |
| `flat_400` | 0° | 400 kg | Same inputs, loaded |
| `hill_400` | 6° uphill | 400 kg | Hill start, pull, brake, turn |
| `hill_800` | 6° uphill | 800 kg | Heavy hill start, pull, brake, turn |

**Outputs:** tractor/trailer speed, front–rear coupling distance, articulation, tilt and contact count, plus an automatic summary. The hitch and wheels are simulated, not cosmetic animations; the payload is a **single combined trailer rigid body** and **not shifting cargo**, and the trailer has no active service brakes. Tune brakes, tyres, slope adhesion and tongue-load distribution with measured data later.

### KX080-3 excavator with free chassis, slew and load

`landworks/scenes/excavator_work_lab.tscn` inherits the physical hinge/link test, but replaces the fixed base with two wide rigid-body track contacts and a separate **HingeJoint3D slewing 4710 kg upper assembly**. The **2200 kg lower assembly**, 650 kg boom, 400 kg stick and 210 kg bucket bring the machinery dry total to 8170 kg before test payload. Boom, stick and bucket are separately simulated `RigidBody3D`s connected by powered hinges. A physical pin attaches the test mass to the bucket.

| Scenario | Test payload | Programme |
|---|---:|---|
| `lift_250` | 250 kg | Raise, hold, slew, drive and stop |
| `lift_500` | 500 kg | Repeat with larger load |
| `lift_1000` | 1000 kg | Stress-test motor torque limit |

**Inputs:** planned boom torque cap 75 kNm, stick 45 kNm, bucket 20 kNm, slew 25 kNm. These are *assumed values only*, **not Kubota hydraulic specifications**. Godot hinge motors use a per-timestep impulse based on physics tick frequency. Track-drive force uses four contact probes and two independently applied force commands: it is a tractable crawler approximation, **not explicit linked tracks**. The tests log load lift, hold drift, slew, chassis tilt, travel and number of grounded track probes. A chassis >20° tilt is flagged for review. No digging/soil removal or hydraulic-fluid simulation yet.

### What's not tested yet

Interactive controller driving in the actual Tinybox fork, imported GLB machinery visuals, trailer jack-knife resistance on arbitrary terrain, accurate gearbox/hydrostatic control, tracked soil sinkage, secure cargo handling, OEM load charts or machine safety. This remains a standalone Landworks test yard.

## Run actual engine experiments

1. Extract the ZIP and open `project.godot` in Godot 4.6. The Godot project uses **Jolt and 120 Hz**.
2. To run a single scene visually, open the `tractor_work_lab.tscn` or `excavator_work_lab.tscn` file and press **F6**. The default tests are `flat_400` and `lift_500` respectively. They execute automatically. In the main yard, select a machine and press **D-pad down** to launch its working test. F7 launches the tractor test; F8 launches the excavator test.
3. To run **all seven physics cases**, have Python 3 installed, and use:

   ```bat
   tools/windows/RUN_FIELD_TESTS_WINDOWS.bat "C:\\path\\to\\Godot_v4.6-stable_win64_console.exe"
   ```

   Alternatively:

   ```bat
   python tools\run_work_tests.py --godot "C:\\path\\to\\godot.exe"
   python tools\analyse_work_tests.py --dir field_test_results
   ```

4. The runner checks exit status, telemetry row count, last timestamp and summary presence. It **does not create fake results** when Godot is unavailable. Output is in `field_test_results/` beside the project; each case has `*_samples.csv`, `*_summary.csv` and `*_godot.log`.
5. Run prechecks separately with `python tools/engineering_precheck.py` and `python tools/surrogate_dynamics.py`. Those are deliberately kept **separate from measured Godot results**.

## Physics acceptance conditions for the next calibration pass

- Tractor: physical hitch stays within 0.4 m of coincident coupling points, trailer stays below 30° tilt, doesn't jackknife beyond 85°, and it pulls on the incline with measurable ground speed. Track trailer wheel contacts and actual braking distance.
- Excavator: 250 and 500 kg should lift and hold (at present reach); 1000 kg may fail at maximum reach, which is an expected behaviour under the assumed 75 kNm torque cap, not automatically a broken game. The machine should be able to slew and move with a suspended load while the rigid-body chassis remains stable for reasonable loads. Assess actual trajectories and contact forces before adjusting any thresholds.

## Known items to check first in Godot

- Pin/hitch alignment, physics solver iterations, and load collision contacts. On some physics engines high mass ratios can require tighter timestep and constraint tuning.
- The effect of changing physics tick rate from Tinybox's original 45 Hz to the standalone test yard's 120 Hz. The standalone game is **not yet merged with Tinybox**.
- All `HingeJoint3D` anchor axes, motor signs, final angles and optional Euler-angle drift; do not trust an arm just because it *looks* correct.
- Low speed torque input on grass and inclines. A constant 15 km/h drive-request governor is a test convenience, **not a hydraulic transmission simulation**.
