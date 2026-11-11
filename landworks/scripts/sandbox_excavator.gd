# Physically articulated KX080-3-inspired excavator integrated into the farm
# sandbox. Reuses the same Jolt rigid-body links, contact-track solver, motor
# constraints and hydraulic allocator as the 13 measured field trials.
extends "res://landworks/scripts/excavator_work_lab.gd"

const INPUTS = preload("res://landworks/scripts/machine_input.gd")

var cab_input := {"boom": 0.0, "stick": 0.0, "bucket": 0.0,
    "slew": 0.0, "left_track": 0.0, "right_track": 0.0}
var operated := false
var scripted_test := false
var access_test := false
var test_clock := 0.0
var slew_target_rad := 0.0
var total_slew_command_deg := 0.0
var attached_load: RigidBody3D
var load_hook_joint: PinJoint3D

func toggle_hook(candidates: Array[RigidBody3D]) -> String:
    # Actual Jolt pin constraint, not a scripted lift or teleport. A heavy
    # object may remain grounded while the machine pushes/pulls against it.
    if is_instance_valid(load_hook_joint):
        load_hook_joint.queue_free()
        load_hook_joint = null
        attached_load = null
        return "Hook released"
    var hook_world: Vector3 = bucket.to_global(Vector3(0, 0, -BUCKET_LENGTH))
    var nearest: RigidBody3D
    var nearest_distance := 1.6
    for body in candidates:
        if not is_instance_valid(body) or body == undercarriage or body == upper:
            continue
        var distance := hook_world.distance_to(body.global_position)
        if distance < nearest_distance:
            nearest = body
            nearest_distance = distance
    if nearest == null:
        return "No loose load within 1.6 m of the bucket"
    var joint := PinJoint3D.new()
    joint.name = "SandboxPhysicalLoadHook"
    add_child(joint)
    joint.global_position = hook_world
    joint.node_a = joint.get_path_to(bucket)
    joint.node_b = joint.get_path_to(nearest)
    joint.exclude_nodes_from_collision = true
    load_hook_joint = joint
    attached_load = nearest
    return "Hooked %s: lifting torque still limits movement" % nearest.name


func _ready() -> void:
    # Deliberately do NOT call the timed laboratory _ready(). It creates CSV
    # files and auto-quits; this remains a continuous player-operated machine.
    # The free 1500 kg crate is a genuine collided, movable test object.
    case_name = "push_1500"
    initial_payload_mass = 1500.0
    surface_profile = SOIL.profile("hardpack")
    _build_machine()
    name = "KX080_Physical_Excavator"

func _physics_process(delta: float) -> void:
    var travel := 0.0
    var turn := 0.0
    var boom_cmd := 0.0
    var stick_cmd := 0.0
    var bucket_cmd := 0.0
    var slew_cmd := 0.0
    if scripted_test and access_test:
        test_clock += delta
        travel = 0.82
    elif scripted_test:
        test_clock += delta
        # Lift/return to prove real boom actuation, then push with the toe
        # at its original contact height. The previous smoke program left
        # the bucket raised and only moved the grounded crate by 17 mm.
        # These commands move motors, never rigid-body transforms.
        if test_clock > 2.0 and test_clock < 5.0:
            boom_cmd = 0.23
        elif test_clock >= 5.0 and test_clock < 10.0:
            boom_cmd = -0.138
        if test_clock >= 12.0 and test_clock < 20.0:
            travel = 0.68
    elif operated:
        var joy := INPUTS.joy_id()
        travel = clampf(
            float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)) -
            INPUTS.stick_y(true), -1.0, 1.0)
        turn = clampf(
            float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)) +
            INPUTS.stick_x(true), -1.0, 1.0)
        boom_cmd = clampf(
            float(Input.is_key_pressed(KEY_I)) - float(Input.is_key_pressed(KEY_K)) +
            INPUTS.trigger(joy, JOY_AXIS_TRIGGER_RIGHT) -
            INPUTS.trigger(joy, JOY_AXIS_TRIGGER_LEFT), -1.0, 1.0)
        stick_cmd = clampf(
            float(Input.is_key_pressed(KEY_O)) - float(Input.is_key_pressed(KEY_L)) -
            INPUTS.stick_y(false), -1.0, 1.0)
        bucket_cmd = clampf(
            float(Input.is_key_pressed(KEY_P)) -
            float(Input.is_key_pressed(KEY_SEMICOLON)) +
            INPUTS.stick_x(false), -1.0, 1.0)
        slew_cmd = INPUTS.slew()
    target_angles["boom"] = clampf(float(target_angles["boom"]) + boom_cmd * delta * 0.38,
        -0.50, 1.05)
    target_angles["stick"] = clampf(float(target_angles["stick"]) + stick_cmd * delta * 0.47,
        -1.45, 0.0)
    target_angles["bucket"] = clampf(float(target_angles["bucket"]) + bucket_cmd * delta * 0.58,
        -0.95, 0.65)
    _drive_hydraulics(delta)
    slew_target_rad = clampf(slew_target_rad + slew_cmd * delta * 0.50, -PI, PI)
    total_slew_command_deg = rad_to_deg(slew_target_rad)
    _control_slew(slew_target_rad)
    var left_speed := clampf((travel - turn) * 0.70, -0.80, 0.80)
    var right_speed := clampf((travel + turn) * 0.70, -0.80, 0.80)
    _drive_tracks(left_speed, right_speed)
    # Publish the exact same control demands used by the machine solver.
    # Decorative cab levers must not sample a second, divergent input path.
    cab_input = {"boom": boom_cmd, "stick": stick_cmd,
        "bucket": bucket_cmd, "slew": slew_cmd,
        "left_track": left_speed / 0.80, "right_track": right_speed / 0.80}
