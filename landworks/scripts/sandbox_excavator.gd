# Physically articulated KX080-3-inspired excavator integrated into the farm
# sandbox. Reuses the same Jolt rigid-body links, contact-track solver, motor
# constraints and hydraulic allocator as the 13 measured field trials.
extends "res://landworks/scripts/excavator_work_lab.gd"

const INPUTS = preload("res://landworks/scripts/machine_input.gd")

var operated := false
# Which international control pattern the levers follow. ISO, the default,
# puts the arm on the left lever and the boom on the right; SAE is the other
# way round. Real machines carry a valve to swap them, so this is a setting
# rather than a rewrite, and F6 flips it in the sandbox.
var sae_pattern := false
var scripted_test := false
var access_test := false
var test_clock := 0.0
var slew_target_rad := 0.0
var total_slew_command_deg := 0.0
const COUPLER = preload("res://landworks/scripts/coupler.gd")

var strap: Node3D
# Read-through views of the strap's real constraint, so callers and tests see
# the live joint rather than a cached copy that could disagree with it.
var load_hook_joint: PinJoint3D:
    get: return strap.joint if strap != null else null
var attached_load: RigidBody3D:
    get: return strap.partner if strap != null else null
var cab_commands: Dictionary = {}
var hydraulics_enabled := true
var blade_cutting_edge_y := 0.0
# Set by the sandbox: true while the operator is seated, so the arrow keys
# steer the head in the cab instead of driving the tracks and blade.
var arrows_look := false

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

# Moves a service's target by `step`, held inside the band its own joint
# enforces, so a lever can never ask for an angle the machine does not have.
func _advance_target(id: String, step: float) -> void:
    var band := joint_limits(id)
    target_angles[id] = clampf(float(target_angles.get(id, 0.0)) + step,
        band.x, band.y)

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
        if absf(error) < 0.004:
            joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, 0.0)
            continue
        joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,
            -clampf(2.4*error, -0.70, 0.70))
    blade_cutting_edge_y = (dozer_blade.to_global(Vector3(0,-0.23,-0.90)).y
        if is_instance_valid(dozer_blade) else 0.0)

func hook_point() -> Vector3:
    return bucket.to_global(BUCKET_TIP)

# Called every tick with the loose loads. The strap takes hold on its own once
# the tooth is in the capture zone and nearly at rest against the load.
func update_strap(candidates: Array) -> void:
    if strap == null:
        return
    var targets: Array = []
    for body in candidates:
        if not is_instance_valid(body) or body == undercarriage or body == upper:
            continue
        targets.append({"body":body,"point":body.global_position})
    strap.update_capture(hook_point(),bucket,targets)

func toggle_hook(candidates: Array[RigidBody3D]) -> String:
    # Actual Jolt pin constraint, not a scripted lift or teleport. A heavy
    # object may remain grounded while the machine pushes/pulls against it.
    # The button is primarily the release; pressed with nothing held it
    # re-arms and tries immediately, so an operator can insist rather than
    # wait for the automatic capture.
    if strap.is_coupled():
        return "Strap released: %s" % strap.release()
    strap.armed = true
    update_strap(candidates)
    if strap.is_coupled():
        return "Hooked %s: lifting torque still limits movement" % strap.partner.name
    return "No loose load within %.2f m of the bucket" % strap.capture_radius


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
    # Lifting strap: forgiving to line up with, released on command.
    strap = COUPLER.new()
    strap.name = "BucketLiftingStrap"
    strap.capture_radius = 0.95
    strap.capture_speed = 2.2
    strap.draw_strap = true
    # The sandbox spawns a test crate within reach of the parked bucket, and
    # an armed strap hooked it on the first tick. Nothing then moved: the pin
    # tied the bucket to a load sitting on the ground, so the boom held still
    # under full flow and full torque. The hook must be brought to a load, so
    # it stays disarmed until the bucket has been clear of one. The strap key
    # still arms it on demand for an operator who wants to insist.
    strap.start_disarmed = true
    add_child(strap)
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
        # Every axis is sampled independently each tick and every target is
        # integrated independently, so any number of movements run at once.
        # The hydraulic allocator shares pump flow between them, which is why
        # three services together move slower than one, but none is blocked.
        #
        # Right keypad:  8/2 boom, 4/6 bucket curl/dump, 7/9 boom offset.
        # Left cluster:  W/X arm out/in, A/D slew, S stop tracks.
        # Arrows:        left/right track levers, up/down dozer blade.
        # The original I/K, O/L, P/; and Q/E keys still work alongside these.
        var joy := INPUTS.joy_id()
        # The two lever clusters are read first and assigned to services after,
        # because which service a lever works is the whole difference between
        # the two control patterns. Both put swing on the left lever sideways
        # and the bucket on the right lever sideways; they disagree only about
        # boom and arm, and swapping those two is the entire change.
        #
        #   ISO (default):  left lever = arm,   right lever = boom
        #   SAE:            left lever = boom,  right lever = arm
        #
        # Real machines carry a valve to swap them, which is why this is a
        # setting and not a rewrite.
        var left_hand := clampf(
            float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_X)) -
            INPUTS.stick_y(false), -1.0, 1.0)
        var right_hand := clampf(
            float(Input.is_key_pressed(KEY_KP_8)) - float(Input.is_key_pressed(KEY_KP_2)) +
            INPUTS.trigger(joy, JOY_AXIS_TRIGGER_RIGHT) -
            INPUTS.trigger(joy, JOY_AXIS_TRIGGER_LEFT), -1.0, 1.0)
        # The older single-purpose keys stay bound to their own service, so they
        # mean the same thing whichever pattern is selected.
        var legacy_boom := float(Input.is_key_pressed(KEY_I)) - float(
            Input.is_key_pressed(KEY_K))
        var legacy_stick := float(Input.is_key_pressed(KEY_O)) - float(
            Input.is_key_pressed(KEY_L))
        boom_cmd = clampf((left_hand if sae_pattern else right_hand)
            + legacy_boom, -1.0, 1.0)
        stick_cmd = clampf((right_hand if sae_pattern else left_hand)
            + legacy_stick, -1.0, 1.0)
        bucket_cmd = clampf(
            float(Input.is_key_pressed(KEY_KP_4) or Input.is_key_pressed(KEY_P)) -
            float(Input.is_key_pressed(KEY_KP_6) or Input.is_key_pressed(KEY_SEMICOLON)) +
            INPUTS.stick_x(false), -1.0, 1.0)
        slew_cmd = clampf(
            float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)) +
            INPUTS.slew(), -1.0, 1.0)
        offset_cmd = clampf(
            float(Input.is_key_pressed(KEY_KP_7) or Input.is_key_pressed(KEY_BRACKETLEFT)) -
            float(Input.is_key_pressed(KEY_KP_9) or Input.is_key_pressed(KEY_BRACKETRIGHT)),
            -1.0, 1.0)
        blade_cmd = float(Input.is_key_pressed(KEY_T)) - float(Input.is_key_pressed(KEY_Y))
        # Arrows drive the machine unless the operator is seated in the cab,
        # where they still steer the head.
        if not arrows_look:
            blade_cmd = clampf(blade_cmd
                + float(Input.is_key_pressed(KEY_UP))
                - float(Input.is_key_pressed(KEY_DOWN)), -1.0, 1.0)
            # Two travel levers, one per track, as on the real machine.
            # Hold Shift for reverse on either.
            var reverse := -1.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
            var left_lever := float(Input.is_key_pressed(KEY_LEFT)) * reverse
            var right_lever := float(Input.is_key_pressed(KEY_RIGHT)) * reverse
            if Input.is_key_pressed(KEY_S):
                left_lever = 0.0
                right_lever = 0.0
            travel = (left_lever + right_lever) * 0.5 - INPUTS.stick_y(true)
            turn = (right_lever - left_lever) * 0.5 + INPUTS.stick_x(true)
        travel = clampf(travel, -1.0, 1.0)
        turn = clampf(turn, -1.0, 1.0)
    # Ranges are the rigged model's own rig limits. The command rates are
    # scaled to those wider ranges: at the old rates a full boom sweep took
    # 5.7 s and a full bucket curl 4.4 s, which is what felt unresponsive.
    # These give roughly 3.5 s, 3.0 s and 2.5 s end to end.
    # Clamp against the band the joint itself enforces. These used to be typed
    # out again here, and because the stops were being set in a different frame
    # the levers could ask for angles that did not physically exist.
    _advance_target("boom", boom_cmd * delta * 0.62)
    _advance_target("stick", stick_cmd * delta * 0.70)
    _advance_target("bucket", bucket_cmd * delta * 1.00)
    _advance_target("blade", blade_cmd * delta * 0.30)
    _advance_target("offset", offset_cmd * delta * 0.35)
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
