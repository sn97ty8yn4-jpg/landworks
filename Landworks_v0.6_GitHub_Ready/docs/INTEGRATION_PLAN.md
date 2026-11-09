# Machinery integration boundary for Tinybox

## Verified upstream points (source inspected 2026-11-09)

- `src/MotorSeat.gd` handles player entry and ownership of a motor seat.
- `src/MotorController.gd` broadcasts forward / steering to attached motors.
- `src/MotorBrick.gd` modifies wheel angular velocity with no full transmission.
- `src/Brick.gd` extends `SyncedRigidbody3D`, so changing the global physics
  tick rate risks changing existing building and breakage behaviour.
- `src/World.gd` saves `.tbw` and builds worlds from registered brick/TBW objects.
- `project.godot` on Tinybox main uses Godot 4.6, GodotPhysics3D and 45 physics Hz.

## Adapter contract (not yet written)

- `MachineAdapter.enter(player, machine)` transfers input authority and camera.
- `MachineAdapter.exit(player, machine)` restores on-foot state and camera.
- `MachineAdapter.snapshot(machine)` serializes ID, transform, velocities,
  attachments, powertrain state, hydraulic positions, fuel and material load.
- `MachineAdapter.restore(snapshot)` instantiates the correct packed scene
  and reapplies physics/controls after a stable spawn step.
- Simulation runs server-authoritative for multiplayer rather than relaying
  raw impulses from multiple peers.
- Never use Tinybox brick glue joints for the excavator's main kinematic chain.
- Evaluate vehicle physics on GodotPhysics3D first to minimise regressions.

## Future machine GLB design contract

A whole-vehicle GLB is *not* enough. Import a properly segmented hierarchy:
`tractor_body`, `front_axle`, `wheel_front_L`, `wheel_front_R`,
`wheel_rear_L`, `wheel_rear_R`, `steering_wheel`, `tow_hitch`,
`seat_camera`, `driver_anchor`; all model dimensions in metres.

Excavator: `track_L`, `track_R`, `slew_upper`, `boom`, `stick`, `bucket`,
`boom_cylinder`, `stick_cylinder`, `bucket_linkage`, `hydraulic_hoses`,
`cab_camera`, `driver_anchor`. Mechanical pivot positions are supplied as
explicit scene markers, not estimated from mesh bounding boxes.

Do not silently import proprietary Rigs of Rods vehicle skins or models;
licences vary per author.
