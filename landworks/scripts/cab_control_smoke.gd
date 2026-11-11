# Headless visual-control regression. No physics or renderer measurements claimed.
# Godot --headless --path . --script res://landworks/scripts/cab_control_smoke.gd
extends SceneTree
const CAB = preload("res://landworks/scripts/excavator_cab.gd")

func _initialize() -> void:
    var host := Node3D.new()
    root.add_child.call_deferred(host)
    call_deferred("_exercise", host)

func _exercise(host: Node3D) -> void:
    await process_frame
    var cab := CAB.new()
    host.add_child(cab)
    cab.set_commands({"boom": 0.70, "stick": -0.60,
        "bucket": -0.50, "slew": 0.40,
        "left_track": 1.0, "right_track": -1.0})
    for n in range(48):
        await process_frame
    var pose: Dictionary = cab.get_pose()
    var good := true
    good = good and float(pose["right_joystick_pitch_rad"]) > 0.15
    good = good and float(pose["right_joystick_roll_rad"]) > 0.08
    good = good and float(pose["left_joystick_pitch_rad"]) < -0.12
    good = good and float(pose["left_joystick_roll_rad"]) < -0.08
    good = good and float(pose["left_travel_lever_rad"]) < -0.25
    good = good and float(pose["right_travel_lever_rad"]) > 0.25
    good = good and float(pose["left_travel_pedal_rad"]) < -0.17
    good = good and float(pose["right_travel_pedal_rad"]) > 0.17
    good = good and cab.seat_camera != null
    cab.set_seated(true)
    good = good and cab.seat_camera.current
    cab.adjust_look(400, -400)
    good = good and absf(cab.look_yaw_deg - 118.0) < 0.001
    good = good and absf(cab.look_pitch_deg + 65.0) < 0.001
    cab.set_seated(false)
    good = good and not cab.seat_camera.current
    cab.set_commands({})
    for n in range(48):
        await process_frame
    var neutral: Dictionary = cab.get_pose()
    for key in neutral.keys():
        good = good and absf(float(neutral[key])) < 0.008
    print("KX080_CAB_SMOKE ", "PASS" if good else "FAIL",
        " active=", pose, " neutral=", neutral)
    quit(0 if good else 1)
