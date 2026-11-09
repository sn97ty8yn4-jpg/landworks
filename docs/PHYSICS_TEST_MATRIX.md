# Machinery physics comparison — test matrix

*Run each test once with baseline, then with Jolt 120 Hz; record expected vs observed. This sheet has NO measured outcomes yet.*

| ID | Machine | Scenario | What to measure | Pass criterion |
|---|---|---|---|---|
| T01 | Tractor | Idle on level gravel, 60 s | Chassis drift / physics frame time | No visible creeping / instability |
| T02 | Tractor | Full-lock low-speed circle | Radius and tyre slip | Stable and reproducible |
| T03 | Tractor | Reverse with 0.5 t trailer | Hitch impulse and oscillation | No explosion / uncontrollable oscillation |
| T04 | Tractor | 10° side-slope idle, turn and drive | Roll angle, contact loss | Physically plausible, no teleport |
| T05 | Tractor | Move from bitumen to wet soil | Longitudinal/lateral slip | Lower grip, appropriately reduced traction |
| E01 | Excavator | Idle hydraulics at 20° boom | Joint angle drift | No unexpected movement under gravity |
| E02 | Excavator | Lift physical 250 kg bucket payload | Velocity, joint impulse, reaction torque | Slows under load, no unconstrained animation |
| E03 | Excavator | Neutral turn with tracks on flat | Yaw rate and translation drift | Turns about centre without large translation |
| E04 | Excavator | Slew while carrying 250 kg | Moment, chassis sway | Physically consistent rocking |
| E05 | Excavator | Digging: bucket vs rigid obstacle | Joint torque and contacts | Bucket resists obstruction, cannot pass through |
| SYS01 | Both | 10 min simulation | 99th percentile frame time, crashes | Target 60 fps render and stable sim |

The 250 kg payload, 0.5 t trailer and 10° test slope are **initial test cases**, not validated machine rated capacities.
