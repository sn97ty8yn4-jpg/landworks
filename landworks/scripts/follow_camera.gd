extends Camera3D
const CI = preload("res://landworks/scripts/machine_input.gd")

var target: Node3D
var yaw_offset: float = 0.0
var distance: float = 8.0
var height: float = 3.7

func _process(delta: float) -> void:
    if target == null:
        return
    # Tractors: close follow; excavators: larger stand-off for boom visibility.
    var wanted_dist := 11.7 if target.name == "Excavator" else 6.9
    var wanted_height := 5.3 if target.name == "Excavator" else 2.9
    distance = lerpf(distance, wanted_dist, clampf(delta * 2.5, 0, 1))
    height = lerpf(height, wanted_height, clampf(delta * 2.5, 0, 1))
    var id := CI.joy_id()
    yaw_offset -= CI.axis(id, JOY_AXIS_RIGHT_X) * delta * 1.2
    var rear := target.global_transform.basis.z.rotated(Vector3.UP, yaw_offset)
    var focus := target.global_position + Vector3.UP * (1.0 if target.name == "Excavator" else 0.45)
    var wanted := focus + rear * distance + Vector3.UP * height
    global_position = global_position.lerp(wanted, clampf(delta * 4.7, 0, 1))
    look_at(focus, Vector3.UP)
