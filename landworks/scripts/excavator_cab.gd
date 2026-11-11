# KX080-3 operator station visual rig. No collision or machine dynamics.
# Coordinates are a visual calibration against the existing procedural upper
# shell (front = -Z, operator's cab on negative X); not surveyed OEM CAD.
extends Node3D

const PAINT := Color("#9a9fa1")
const TRIM := Color("#555d60")
const DARK := Color("#272d31")
const RUBBER := Color("#33383a")
const GREY := Color("#c4c7c3")
const SCREEN := Color("#89a6a5")
const WARNING := Color("#ddb74d")
const SEAT_EYE := Vector3(-0.50, 2.58, -0.49)
const JOYSTICK_TILT_DEG := 16.0
const TRAVEL_LEVER_TILT_DEG := 19.0
const TRAVEL_PEDAL_TILT_DEG := 12.0

var seat_camera: Camera3D
var head: Node3D
var left_stick: Node3D
var right_stick: Node3D
var left_travel_lever: Node3D
var right_travel_lever: Node3D
var left_travel_pedal: Node3D
var right_travel_pedal: Node3D
var operator_avatar: Node3D
var front_glass: Node3D
var seated := false
var look_yaw_deg := 0.0
var look_pitch_deg := -12.0
var lean_m := 0.0
var commands := {"boom": 0.0, "stick": 0.0, "bucket": 0.0,
    "slew": 0.0, "left_track": 0.0, "right_track": 0.0}
var smoothed := {"boom": 0.0, "stick": 0.0, "bucket": 0.0,
    "slew": 0.0, "left_track": 0.0, "right_track": 0.0}
var materials: Dictionary = {}

func _ready() -> void:
    name = "KX080_3_OperatorStation"
    operator_avatar = get_parent().get_node_or_null("CabOperatorAvatar")
    front_glass = get_parent().get_node_or_null("CabFrontWindow")
    _build_station()
    _build_camera()
    set_seated(false)

func _material(tint: Color, roughness: float = 0.83) -> StandardMaterial3D:
    var key := tint.to_html() + "_" + str(roughness)
    if materials.has(key):
        return materials[key]
    var mat := StandardMaterial3D.new()
    mat.albedo_color = tint
    mat.roughness = roughness
    mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
    materials[key] = mat
    return mat

func _box(parent: Node3D, dimensions: Vector3,
        at: Vector3, tint: Color) -> MeshInstance3D:
    var result := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = dimensions
    result.mesh = box
    result.material_override = _material(tint)
    result.position = at
    parent.add_child(result)
    return result

func _cylinder(parent: Node3D, radius: float, length: float,
        at: Vector3, tint: Color) -> MeshInstance3D:
    var result := MeshInstance3D.new()
    var shape := CylinderMesh.new()
    shape.top_radius = radius
    shape.bottom_radius = radius
    shape.height = length
    shape.radial_segments = 12
    result.mesh = shape
    result.material_override = _material(tint)
    result.position = at
    parent.add_child(result)
    return result

func _rod(parent: Node3D, start: Vector3, finish: Vector3,
        radius: float, tint: Color) -> MeshInstance3D:
    var delta := finish - start
    var part := _cylinder(parent, radius, delta.length(), (start + finish) * 0.5, tint)
    if delta.length_squared() > 0.000001:
        part.quaternion = Quaternion(Vector3.UP, delta.normalized())
    return part

func _make_joystick(label: String, x: float) -> Node3D:
    # The grip, bellows and shaft share one two-axis gimbal pivot.
    var pivot := Node3D.new()
    pivot.name = label + "_JoystickGimbal"
    pivot.position = Vector3(x, 2.055, -0.56)
    add_child(pivot)
    _box(pivot, Vector3(0.20, 0.042, 0.20), Vector3(0, 0.00, 0), DARK)
    for n in range(5):
        _box(pivot, Vector3(0.142 - float(n) * 0.011,
            0.023, 0.148 - float(n) * 0.011),
            Vector3(0, 0.035 + float(n) * 0.028, 0), RUBBER)
    _rod(pivot, Vector3(0, 0.13, 0), Vector3(0.022, 0.29, -0.015), 0.026, GREY)
    _box(pivot, Vector3(0.108, 0.145, 0.085),
        Vector3(0.028, 0.315, -0.020), DARK)
    _cylinder(pivot, 0.027, 0.007, Vector3(0.048, 0.387, -0.030), WARNING)
    _box(pivot, Vector3(0.064, 0.015, 0.018),
        Vector3(0.028, 0.326, -0.069), TRIM)
    return pivot

func _make_travel(name_part: String, x: float) -> Dictionary:
    # Long hand lever and front rocker pedal tilt independently about
    # transverse shafts, driven by the identical left/right track command.
    var lever := Node3D.new()
    lever.name = name_part + "_TravelLever"
    lever.position = Vector3(x, 1.805, -0.80)
    add_child(lever)
    _cylinder(lever, 0.043, 0.065, Vector3.ZERO, DARK)
    _rod(lever, Vector3.ZERO, Vector3(0, 0.37, -0.075), 0.018, GREY)
    _box(lever, Vector3(0.155, 0.067, 0.073),
        Vector3(0, 0.387, -0.083), DARK)
    var pedal := Node3D.new()
    pedal.name = name_part + "_TravelPedal"
    pedal.position = Vector3(x, 1.79, -0.85)
    add_child(pedal)
    _box(pedal, Vector3(0.168, 0.030, 0.26),
        Vector3(0, 0.016, -0.035), RUBBER)
    for n in range(5):
        _box(pedal, Vector3(0.16, 0.007, 0.010),
            Vector3(0, 0.036, -0.137 + float(n) * 0.045), GREY)
    return {"lever": lever, "pedal": pedal}

func _build_station() -> void:
    # Seat and consoles inherit upper-carriage rigid-body transform.
    # Seat geometry is a cosmetic interior, not additional physics mass.
    _box(self, Vector3(0.44, 0.13, 0.41),
        Vector3(-0.50, 1.965, -0.10), DARK)
    _box(self, Vector3(0.44, 0.49, 0.10),
        Vector3(-0.50, 2.22, 0.105), DARK)
    _box(self, Vector3(0.37, 0.045, 0.35),
        Vector3(-0.50, 2.044, -0.12), TRIM)
    for x in [-0.815, -0.185]:
        _box(self, Vector3(0.225, 0.22, 0.64),
            Vector3(x, 1.995, -0.42), PAINT)
        _box(self, Vector3(0.22, 0.038, 0.31),
            Vector3(x, 2.095, -0.31), RUBBER)
        _box(self, Vector3(0.21, 0.045, 0.18),
            Vector3(x, 2.090, -0.60), TRIM)
    left_stick = _make_joystick("Left", -0.81)
    right_stick = _make_joystick("Right", -0.18)
    var left := _make_travel("Left", -0.625)
    var right := _make_travel("Right", -0.375)
    left_travel_lever = left["lever"]
    right_travel_lever = right["lever"]
    left_travel_pedal = left["pedal"]
    right_travel_pedal = right["pedal"]
    # KX080-3-style right instrument console: simple switches, LCD, vents
    # and the blade control beside the right joystick, kept below sightline.
    _box(self, Vector3(0.19, 0.21, 0.16),
        Vector3(-0.105, 2.19, -0.78), PAINT)
    _box(self, Vector3(0.115, 0.065, 0.018),
        Vector3(-0.103, 2.27, -0.865), SCREEN)
    for n in range(3):
        _box(self, Vector3(0.023, 0.016, 0.018),
            Vector3(-0.165 + float(n) * 0.05, 2.215, -0.875), DARK)
    _rod(self, Vector3(-0.055, 2.04, -0.61),
        Vector3(-0.028, 2.32, -0.58), 0.017, GREY)
    _box(self, Vector3(0.066, 0.079, 0.065),
        Vector3(-0.027, 2.332, -0.58), DARK)
    # Left safety-lock lever, boom-swing pedal and moulded floor mat.
    _rod(self, Vector3(-0.94, 1.95, -0.22),
        Vector3(-0.955, 2.19, -0.20), 0.018, WARNING)
    _box(self, Vector3(0.075, 0.063, 0.060),
        Vector3(-0.955, 2.205, -0.20), DARK)
    _box(self, Vector3(0.13, 0.033, 0.20),
        Vector3(-0.848, 1.80, -0.79), DARK)
    _box(self, Vector3(0.66, 0.016, 0.48),
        Vector3(-0.50, 1.761, -0.54), RUBBER)
    for n in range(7):
        _box(self, Vector3(0.64, 0.006, 0.008),
            Vector3(-0.50, 1.772, -0.74 + float(n) * 0.06), TRIM)
    # Lower windscreen rail and wiper mount, preserving forward view.
    _rod(self, Vector3(-0.865, 2.09, -0.907),
        Vector3(-0.230, 2.18, -0.907), 0.008, DARK)

func _build_camera() -> void:
    head = Node3D.new()
    head.name = "OperatorEyes_AdjustableHead"
    head.position = SEAT_EYE
    add_child(head)
    seat_camera = Camera3D.new()
    seat_camera.name = "KX080_SeatedFirstPerson"
    seat_camera.fov = 74.0
    seat_camera.near = 0.04
    seat_camera.far = 270.0
    head.add_child(seat_camera)
    _refresh_head()

func _refresh_head() -> void:
    head.position = SEAT_EYE + Vector3(lean_m, 0, 0)
    head.rotation = Vector3(deg_to_rad(look_pitch_deg),
        deg_to_rad(look_yaw_deg), 0.0)

func adjust_look(delta_yaw_deg: float, delta_pitch_deg: float) -> void:
    look_yaw_deg = clampf(look_yaw_deg + delta_yaw_deg, -118.0, 118.0)
    look_pitch_deg = clampf(look_pitch_deg + delta_pitch_deg, -65.0, 38.0)
    _refresh_head()

func reset_look() -> void:
    look_yaw_deg = 0.0
    look_pitch_deg = -12.0
    lean_m = 0.0
    _refresh_head()

func set_lean(value: float) -> void:
    lean_m = clampf(value, -0.12, 0.12)
    _refresh_head()

func set_seated(active: bool) -> void:
    seated = active
    if seat_camera != null:
        seat_camera.current = active
    if operator_avatar != null:
        operator_avatar.visible = not active
    if front_glass != null:
        # No double-rendered tinted pane across the driver's entire screen.
        # The window rails, pillars and wiper remain visible in the seat.
        front_glass.visible = not active

func set_commands(new_values: Dictionary) -> void:
    for key in commands.keys():
        commands[key] = clampf(float(new_values.get(key, 0.0)), -1.0, 1.0)

func _process(delta: float) -> void:
    var k := 1.0 - exp(-delta * 16.0)
    for key in commands.keys():
        smoothed[key] = lerpf(float(smoothed[key]), float(commands[key]), k)
    # Left joystick is arm fore/aft plus swing side-to-side.
    # Right joystick is boom fore/aft plus bucket side-to-side.
    # Controller mapping is separate: the controls always reflect actual
    # hydraulic/track commands supplied by the machine.
    left_stick.rotation.x = deg_to_rad(JOYSTICK_TILT_DEG) * float(smoothed["stick"])
    left_stick.rotation.z = -deg_to_rad(JOYSTICK_TILT_DEG) * float(smoothed["slew"])
    right_stick.rotation.x = deg_to_rad(JOYSTICK_TILT_DEG) * float(smoothed["boom"])
    right_stick.rotation.z = -deg_to_rad(JOYSTICK_TILT_DEG) * float(smoothed["bucket"])
    left_travel_lever.rotation.x = -deg_to_rad(TRAVEL_LEVER_TILT_DEG) * float(smoothed["left_track"])
    right_travel_lever.rotation.x = -deg_to_rad(TRAVEL_LEVER_TILT_DEG) * float(smoothed["right_track"])
    left_travel_pedal.rotation.x = -deg_to_rad(TRAVEL_PEDAL_TILT_DEG) * float(smoothed["left_track"])
    right_travel_pedal.rotation.x = -deg_to_rad(TRAVEL_PEDAL_TILT_DEG) * float(smoothed["right_track"])

func get_pose() -> Dictionary:
    return {
        "left_joystick_pitch_rad": left_stick.rotation.x,
        "left_joystick_roll_rad": left_stick.rotation.z,
        "right_joystick_pitch_rad": right_stick.rotation.x,
        "right_joystick_roll_rad": right_stick.rotation.z,
        "left_travel_lever_rad": left_travel_lever.rotation.x,
        "right_travel_lever_rad": right_travel_lever.rotation.x,
        "left_travel_pedal_rad": left_travel_pedal.rotation.x,
        "right_travel_pedal_rad": right_travel_pedal.rotation.x
    }
