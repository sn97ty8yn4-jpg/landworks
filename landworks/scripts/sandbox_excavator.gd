# Physically articulated KX080-3-inspired excavator integrated into the farm
# sandbox. Reuses the same Jolt rigid-body links, contact-track solver, motor
# constraints and hydraulic allocator as the 13 measured field trials.
extends "res://landworks/scripts/excavator_work_lab.gd"

const INPUTS = preload("res://landworks/scripts/machine_input.gd")

var operated := false
var scripted_test := false
var access_test := false
var test_clock := 0.0
var slew_target_rad := 0.0
var total_slew_command_deg := 0.0
var attached_load: RigidBody3D
var load_hook_joint: PinJoint3D
var cab_commands: Dictionary = {}
var hydraulics_enabled := true
var blade_cutting_edge_y := 0.0

func _drive_hydraulics(delta: float) -> void:
    if hydraulics_enabled:
        super._drive_hydraulics(delta)
        return
    hydraulic_state = {"speeds":{},"torque_caps":{},"hydraulic_power_kw":0.0}
    for key in ["boom","stick","bucket"]:
        var joint: HingeJoint3D = hinges[key]["joint"]
        joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE,0.0)
        joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,0.0)

func _boom_base_pin() -> Vector3:
    # Taken from the rigged KX080-3: the boom foot pin sits 1.36 m up, 1.30 m
    # ahead of the swing centre and 100 mm right of it, on the king post.
    return Vector3(0.10,1.36,-1.30)

func _joint_angle(id: String) -> float:
    # The base measurement resolves rotation about the pitch axis only. The
    # king post turns on a vertical pin, so it needs the yaw component.
    if hinges.has(id) and Vector3(hinges[id]["axis"]) == Vector3.UP:
        var a: PhysicsBody3D = hinges[id]["a"]
        var b: PhysicsBody3D = hinges[id]["b"]
        var relative: Basis = a.global_transform.basis.inverse()*b.global_transform.basis
        return atan2(relative.z.x,relative.z.z)
    return super._joint_angle(id)

func _control_aux(_delta: float) -> void:
    # Dozer blade and boom offset run on their own motors rather than through
    # the hydraulic allocator, which stays tuned to the three measured arm
    # services. Angles still come from the solver, never from a set transform.
    # The Jolt hinge-motor sign is opposite to the measured angle sign here,
    # the same inversion the slew drive already carries.
    for id in ["blade","offset"]:
        if not hinges.has(id):
            continue
        var joint: HingeJoint3D = hinges[id]["joint"]
        var error: float = float(target_angles.get(id,0.0)) - _joint_angle(id)
        joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,
            -clampf(2.4*error, -0.55, 0.55))
    blade_cutting_edge_y = (dozer_blade.to_global(Vector3(0,-0.23,-0.90)).y
        if is_instance_valid(dozer_blade) else 0.0)

func toggle_hook(candidates: Array[RigidBody3D]) -> String:
    # Actual Jolt pin constraint, not a scripted lift or teleport. A heavy
    # object may remain grounded while the machine pushes/pulls against it.
    if is_instance_valid(load_hook_joint):
        load_hook_joint.queue_free()
        load_hook_joint = null
        attached_load = null
        return "Hook released"
    var hook_world: Vector3 = bucket.to_global(BUCKET_TIP)
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
    # The playable machine carries the modelled king post and dozer blade.
    fit_blade_and_offset = true
    _build_machine()
    target_angles["blade"] = 0.0
    target_angles["offset"] = 0.0
    # The older laboratory proxy reached down from a roof-height boom pin.
    # With the real sandbox pin lower, keep ground contact at the visible
    # bucket lip instead of retaining a hidden 1.2m-wide pushing block.
    # The generic limb proxy lays a box straight down -Z from the pin, which
    # for this bucket puts its mass well outside the real shell and loads the
    # bucket pin with a longer lever than the steel actually has. Re-centre
    # the shell on the pin-to-tooth line it is really built around.
    for child in bucket.get_children():
        if child is CollisionShape3D and child.name != "GroundHandlingToe":
            var shell := BoxShape3D.new()
            shell.size = Vector3(BUCKET_WIDTH,0.55,0.80)
            (child as CollisionShape3D).shape = shell
            (child as CollisionShape3D).position = BUCKET_TIP*0.5
            break
    var toe := bucket.get_node_or_null("GroundHandlingToe") as CollisionShape3D
    if toe != null:
        var lip_shape := BoxShape3D.new()
        lip_shape.size = Vector3(BUCKET_WIDTH,0.22,0.22)
        toe.shape = lip_shape
        # Sit the contact lip just behind the modelled tooth tip, which is
        # 500 mm below and 800 mm ahead of the bucket pin, not radial on -Z.
        toe.position = BUCKET_TIP - BUCKET_TIP.normalized()*0.11
    name = "KX080_Physical_Excavator"

func _physics_process(delta: float) -> void:
    var travel := 0.0
    var turn := 0.0
    var boom_cmd := 0.0
    var stick_cmd := 0.0
    var bucket_cmd := 0.0
    var slew_cmd := 0.0
    var blade_cmd := 0.0
    var offset_cmd := 0.0
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
        blade_cmd = float(Input.is_key_pressed(KEY_T)) - float(Input.is_key_pressed(KEY_Y))
        offset_cmd = (float(Input.is_key_pressed(KEY_BRACKETLEFT))
            - float(Input.is_key_pressed(KEY_BRACKETRIGHT)))
    # Ranges are the rigged model's own rig limits.
    target_angles["boom"] = clampf(float(target_angles["boom"]) + boom_cmd * delta * 0.38,
        -1.047, 1.100)
    target_angles["stick"] = clampf(float(target_angles["stick"]) + stick_cmd * delta * 0.47,
        -2.094, 0.0)
    target_angles["bucket"] = clampf(float(target_angles["bucket"]) + bucket_cmd * delta * 0.58,
        -0.698, 1.833)
    target_angles["blade"] = clampf(float(target_angles.get("blade",0.0)) + blade_cmd * delta * 0.30,
        -0.314, 0.314)
    target_angles["offset"] = clampf(float(target_angles.get("offset",0.0)) + offset_cmd * delta * 0.35,
        -1.047, 1.222)
    _drive_hydraulics(delta)
    _control_aux(delta)
    slew_target_rad = clampf(slew_target_rad + slew_cmd * delta * 0.50, -PI, PI)
    total_slew_command_deg = rad_to_deg(slew_target_rad)
    _control_slew(slew_target_rad)
    var left_speed := clampf((travel - turn) * 0.70, -0.80, 0.80)
    var right_speed := clampf((travel + turn) * 0.70, -0.80, 0.80)
    _drive_tracks(left_speed, right_speed)
    cab_commands = {"boom":boom_cmd,"stick":stick_cmd,"bucket":bucket_cmd,
        "slew":slew_cmd,"left_track":left_speed/0.8,"right_track":right_speed/0.8}
