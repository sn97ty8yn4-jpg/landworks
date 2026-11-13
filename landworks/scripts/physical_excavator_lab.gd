# Torque-limited physics-joint excavator proof-of-concept.
# Unlike the visual-only v0.4 scene, each steel arm link and the payload is a RigidBody3D.
# This lab anchors the lower carriage to isolate hydraulic-joint lifting; chassis
# stability, true cylinders/pressure and dynamic track contact come later.
extends Node3D

const M = preload("res://landworks/scripts/mesh_factory.gd")
const CI = preload("res://landworks/scripts/machine_input.gd")

# Measured from the rigged KX080-3 model: boom foot pin to arm pin, arm pin to
# bucket pin, and bucket pin to tooth tip. The tip is not radial on -Z, so
# BUCKET_TIP carries the real tooth position and BUCKET_LENGTH its radius.
const BOOM_LENGTH := 3.6
const STICK_LENGTH := 1.75
const BUCKET_TIP := Vector3(0.0, -0.5, -0.8)
const BUCKET_LENGTH := 0.943
# Cutting-edge width of the modelled digging bucket.
const BUCKET_WIDTH := 0.65

var undercarriage: RigidBody3D
var boom: RigidBody3D
var stick: RigidBody3D
var bucket: RigidBody3D
var test_mass: RigidBody3D
var hinges: Dictionary = {}
var target_angles := {"boom": 0.24, "stick": -0.72, "bucket": -0.24}
var labels: Label
var elapsed := 0.0
var auto_enabled := true
var auto_latched := false
var load_latched := false
var mass_initial_height := 0.0
var max_gain := 0.0

func _ready() -> void:
    _build_ground()
    _build_machine()
    _build_scene()
    mass_initial_height = test_mass.global_position.y

func _build_ground() -> void:
    var ground := StaticBody3D.new()
    ground.name = "LoadTestGround"
    add_child(ground)
    var shape := BoxShape3D.new()
    shape.size = Vector3(60, 1, 60)
    var col := CollisionShape3D.new()
    col.position.y = -0.5
    col.shape = shape
    ground.add_child(col)
    M.block(ground, Vector3(60, 0.1, 60), Vector3(0, -0.06, 0), Color("#a4a396"))

func _make_box(name: String, kg: float, pin: Vector3, rot_x: float,
        length: float, height: float, width: float, colour: Color) -> RigidBody3D:
    var body := RigidBody3D.new()
    body.name = name
    body.mass = kg
    body.can_sleep = false
    body.continuous_cd = true
    body.linear_damp = 0.06
    body.angular_damp = 0.15
    body.collision_layer = 2
    body.collision_mask = 1
    add_child(body)
    body.global_transform = Transform3D(Basis(Vector3.RIGHT, rot_x), pin)
    var c := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(width, height, length)
    c.shape = box
    c.position = Vector3(0, 0, -length * 0.5)
    body.add_child(c)
    M.block(body, Vector3(width, height, length), Vector3(0, 0, -length * 0.5), colour)
    M.cylinder(body, height * 0.60, width + 0.025, Vector3.ZERO, Color("#525859"), true)
    return body

func _make_hinge(id: String, parent: PhysicsBody3D, child: PhysicsBody3D,
        pivot_world: Vector3, axis: Vector3, lower: float, upper: float,
        max_impulse: float) -> void:
    var joint := HingeJoint3D.new()
    joint.name = id + "_powered_pin"
    add_child(joint)
    # HingeJoint3D operates about its local Z, mapped to the requested pin axis.
    joint.global_transform = Transform3D(Basis(Quaternion(Vector3.BACK, axis)), pivot_world)
    joint.node_a = joint.get_path_to(parent)
    joint.node_b = joint.get_path_to(child)
    joint.exclude_nodes_from_collision = true
    joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
    joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, lower)
    joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, upper)
    joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
    joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, max_impulse)
    hinges[id] = {"joint": joint, "a": parent, "b": child, "axis": axis,
        # Raised with the widened rig limits: the boom now sweeps 123 degrees
        # and the bucket 145, so the old ceilings made the controls crawl.
        "max_speed": 0.80 if id == "boom" else 1.05}

func _build_machine() -> void:
    undercarriage = RigidBody3D.new()
    undercarriage.name = "FixedChassis_8170kgReference"
    undercarriage.mass = 6910.0
    # Isolate load lifting from travel/tipping. Cannot use fixed-base test to claim chassis stability.
    undercarriage.freeze = true
    add_child(undercarriage)
    undercarriage.position = Vector3.ZERO
    var base_collision := CollisionShape3D.new()
    var base_shape := BoxShape3D.new()
    base_shape.size = Vector3(2.14, 1.0, 3.2)
    base_collision.shape = base_shape
    base_collision.position.y = 0.65
    undercarriage.add_child(base_collision)
    M.block(undercarriage, Vector3(2.1, 0.52, 3.05), Vector3(0, 0.68, 0), Color("#3f484a"))
    M.block(undercarriage, Vector3(1.88, 0.87, 2.22), Vector3(0, 1.35, 0.11), Color("#e77717"))
    for side in [-0.88, 0.88]:
        M.block(undercarriage, Vector3(0.42, 0.70, 3.2), Vector3(side, 0.42, 0), Color("#22292c"))

    var boom_pin := Vector3(0.52, 2.12, -0.70)
    boom = _make_box("Boom_650kg", 650.0, boom_pin, 0.24,
        BOOM_LENGTH, 0.46, 0.46, Color("#f08820"))
    var stick_pin: Vector3 = boom.to_global(Vector3(0, 0, -BOOM_LENGTH))
    stick = _make_box("Stick_400kg", 400.0, stick_pin, 0.24 - 0.72,
        STICK_LENGTH, 0.34, 0.34, Color("#e97a17"))
    var bucket_pin: Vector3 = stick.to_global(Vector3(0, 0, -STICK_LENGTH))
    bucket = _make_box("Bucket_210kg", 210.0, bucket_pin, 0.24 - 0.72 - 0.24,
        BUCKET_LENGTH, 0.44, BUCKET_WIDTH, Color("#42494a"))
    _make_hinge("boom", undercarriage, boom, boom_pin, Vector3.RIGHT, -0.7, 1.15, 1200.0)
    _make_hinge("stick", boom, stick, stick_pin, Vector3.RIGHT, -1.5, 0.15, 700.0)
    _make_hinge("bucket", stick, bucket, bucket_pin, Vector3.RIGHT, -1.0, 0.75, 350.0)

    var hook: Vector3 = bucket.to_global(BUCKET_TIP)
    test_mass = RigidBody3D.new()
    test_mass.name = "TestMass_250kg"
    test_mass.mass = 250.0
    test_mass.can_sleep = false
    test_mass.continuous_cd = true
    test_mass.collision_layer = 1
    test_mass.collision_mask = 3
    add_child(test_mass)
    test_mass.global_position = hook + Vector3.DOWN * 0.52
    var cube := CollisionShape3D.new()
    var csh := BoxShape3D.new()
    csh.size = Vector3(0.78, 0.56, 0.78)
    cube.shape = csh
    test_mass.add_child(cube)
    M.block(test_mass, csh.size, Vector3.ZERO, Color("#b0a892"))
    var load_pin := PinJoint3D.new()
    load_pin.name = "PhysicalPayloadPin"
    add_child(load_pin)
    load_pin.global_position = hook
    load_pin.node_a = load_pin.get_path_to(bucket)
    load_pin.node_b = load_pin.get_path_to(test_mass)
    load_pin.exclude_nodes_from_collision = true

func _build_scene() -> void:
    var camera := Camera3D.new()
    camera.position = Vector3(11.0, 6.0, 10.2)
    add_child(camera)
    camera.look_at(Vector3(0.0, 1.8, -2.4))
    camera.current = true
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-58, -40, 0)
    add_child(sun)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#b9cfd8")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color.WHITE
    env.ambient_light_energy = 0.70
    environment.environment = env
    add_child(environment)
    var canvas := CanvasLayer.new()
    add_child(canvas)
    labels = Label.new()
    labels.position = Vector2(26, 22)
    labels.add_theme_font_size_override("font_size", 21)
    labels.add_theme_color_override("font_color", Color.WHITE)
    canvas.add_child(labels)

func _joint_angle(id: String) -> float:
    var data: Dictionary = hinges[id]
    var a: PhysicsBody3D = data["a"]
    var b: PhysicsBody3D = data["b"]
    var relative: Basis = a.global_transform.basis.inverse() * b.global_transform.basis
    return atan2(relative.y.z, relative.y.y)

func _drive_joint(id: String, _delta: float) -> void:
    var h: Dictionary = hinges[id]
    var joint: HingeJoint3D = h["joint"]
    var a: PhysicsBody3D = h["a"]
    var b: PhysicsBody3D = h["b"]
    var axis_world: Vector3 = a.global_transform.basis * Vector3.RIGHT
    var a_vel := Vector3.ZERO
    if a is RigidBody3D:
        a_vel = (a as RigidBody3D).angular_velocity
    var b_vel := Vector3.ZERO
    if b is RigidBody3D:
        b_vel = (b as RigidBody3D).angular_velocity
    var measured: float = _joint_angle(id)
    var position_error := wrapf(float(target_angles[id]) - measured, -PI, PI)
    var relative_velocity := (b_vel - a_vel).dot(axis_world)
    # PID-style angular motor: physics joint supplies torque, not animation transforms.
    var desired_velocity := clampf(3.4 * position_error - 0.65 * relative_velocity,
        -float(h["max_speed"]), float(h["max_speed"]))
    # Motor velocity around the joint's mapped local Z has the opposite sign
    # to our positive local-X joint angle. The previous polarity drove all
    # three links away from their targets under load (confirmed in CI telemetry).
    joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, -desired_velocity)

func _physics_process(delta: float) -> void:
    elapsed += delta
    var joy := CI.joy_id()
    if Input.is_key_pressed(KEY_F4) or (joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_B)):
        get_tree().change_scene_to_file("res://landworks/scenes/test_yard.tscn")
        return
    var toggle := Input.is_key_pressed(KEY_SPACE) or (joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_A))
    if toggle and not auto_latched:
        auto_enabled = not auto_enabled
    auto_latched = toggle
    var change_load := Input.is_key_pressed(KEY_M) or (joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_X))
    if change_load and not load_latched:
        test_mass.mass = 500.0 if test_mass.mass < 400.0 else 250.0
    load_latched = change_load
    if auto_enabled:
        var desired_lift := smoothstep(2.0, 10.0, elapsed)
        target_angles["boom"] = 0.24 + desired_lift * 0.48
        target_angles["stick"] = -0.72 + desired_lift * 0.12
        target_angles["bucket"] = -0.24 - desired_lift * 0.13
    else:
        var boom_request := -CI.stick_y(true) + float(Input.is_key_pressed(KEY_I)) - float(Input.is_key_pressed(KEY_K))
        var stick_request := -CI.stick_y(false) + float(Input.is_key_pressed(KEY_O)) - float(Input.is_key_pressed(KEY_L))
        var bucket_request := CI.stick_x(false) + float(Input.is_key_pressed(KEY_P)) - float(Input.is_key_pressed(KEY_SEMICOLON))
        target_angles["boom"] = clampf(float(target_angles["boom"]) + clampf(boom_request, -1.0, 1.0) * delta * 0.38, -0.5, 1.05)
        target_angles["stick"] = clampf(float(target_angles["stick"]) + clampf(stick_request, -1.0, 1.0) * delta * 0.47, -1.45, 0.0)
        target_angles["bucket"] = clampf(float(target_angles["bucket"]) + clampf(bucket_request, -1.0, 1.0) * delta * 0.58, -0.95, 0.65)
    for part in ["boom", "stick", "bucket"]:
        _drive_joint(part, delta)
    var gain := test_mass.global_position.y - mass_initial_height
    max_gain = maxf(max_gain, gain)
    labels.text = "LANDWORKS v0.5 | FORCE-BASED EXCAVATOR LIFT TEST\n"
    labels.text += "Payload: %.0f kg   height: %.2f m   lift gain: %+.2f m   peak gain: %+.2f m\n" % [test_mass.mass, test_mass.global_position.y, gain, max_gain]
    labels.text += "Boom: %.1f°  Stick: %.1f°  Bucket: %.1f°  |  %s\n" % [rad_to_deg(_joint_angle("boom")), rad_to_deg(_joint_angle("stick")), rad_to_deg(_joint_angle("bucket")), "AUTO" if auto_enabled else "MANUAL"]
    labels.text += "SPACE / Cross: auto/manual  |  M / Square: 250/500kg  |  F4/Circle: yard\n"
    labels.text += "Actual RigidBody3D load + HingeJoint3D motors; FIXED CHASSIS test, NOT pressure-calibrated"
