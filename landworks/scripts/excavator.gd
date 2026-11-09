# Stage 1: separate articulated excavator visual kinematics + rigid-body
# crawler locomotion. Hydraulic joints and soil cutting are NEXT milestones.
extends RigidBody3D

const M = preload("res://landworks/scripts/mesh_factory.gd")
const CI = preload("res://landworks/scripts/machine_input.gd")
const VIS = preload("res://landworks/scripts/model_swap.gd")

var controlled: bool = false
var upper: Node3D
var boom: Node3D
var stick: Node3D
var bucket: Node3D
var track_roots: Array[Node3D] = []
var boom_angle: float = 0.32
var stick_angle: float = -0.78
var bucket_angle: float = -0.32
var slewing_angle: float = 0.0

func _ready() -> void:
    mass = 8170.0
    linear_damp = 1.1
    angular_damp = 3.0
    can_sleep = false
    _build_geometry()

func _build_geometry() -> void:
    var cs := CollisionShape3D.new()
    var sh := BoxShape3D.new()
    sh.size = Vector3(2.25, 0.95, 2.90)
    cs.shape = sh
    cs.position = Vector3(0, -0.30, 0)
    add_child(cs)
    var lower_art := Node3D.new()
    lower_art.name = "LowerFrameVisual"
    add_child(lower_art)
    M.block(lower_art, Vector3(1.65, 0.50, 2.45), Vector3(0, -0.23, 0), Color("#3e4144"))
    # Track visual roots do not control crawler forces (yet).
    for x in [-0.88, 0.88]:
        var track_root := Node3D.new()
        track_root.name = "TrackVisual"
        track_root.position = Vector3(x, -0.43, 0)
        add_child(track_root)
        track_roots.append(track_root)
        var track_art := Node3D.new()
        track_art.name = "PlaceholderTrack"
        track_root.add_child(track_art)
        M.block(track_art, Vector3(0.44, 0.69, 3.00), Vector3.ZERO, Color("#22282a"))
        for j in range(13):
            M.block(track_art, Vector3(0.47, 0.09, 0.20),
                Vector3(0, -0.31, -1.36 + float(j) * 0.23), Color("#424747"))
        VIS.place_visual(track_root, track_art, "res://landworks/assets/rigged/kx080_track.glb")
    upper = Node3D.new()
    upper.name = "SlewPlatform"
    upper.position = Vector3(0, 0.28, 0)
    add_child(upper)
    var upper_art := Node3D.new()
    upper_art.name = "PlaceholderUpper"
    upper.add_child(upper_art)
    M.cylinder(upper_art, 0.82, 0.14, Vector3.ZERO, Color("#292a2a"))
    M.block(upper_art, Vector3(2.01, 0.54, 2.27), Vector3(0, 0.38, 0.16), Color("#e67b15"))
    M.block(upper_art, Vector3(0.83, 1.20, 0.99), Vector3(-0.54, 0.99, -0.20), Color("#28313a"))
    M.block(upper_art, Vector3(0.80, 0.14, 1.10), Vector3(-0.54, 1.62, -0.20), Color("#e67b15"))
    M.block(upper_art, Vector3(0.14, 1.12, 1.06), Vector3(-0.98, 1.02, -0.20), Color("#ef8d1a"))
    M.block(upper_art, Vector3(1.54, 0.19, 0.66), Vector3(0, 0.66, 0.94), Color("#e0831a"))
    boom = Node3D.new()
    boom.name = "BoomPivot"
    boom.position = Vector3(0.59, 0.82, -0.73)
    upper.add_child(boom)
    var boom_art := Node3D.new()
    boom_art.name = "PlaceholderBoom"
    boom.add_child(boom_art)
    M.block(boom_art, Vector3(0.32, 0.52, 3.10), Vector3(0, 0, -1.55), Color("#e67c14"))
    M.cylinder(boom_art, 0.26, 0.45, Vector3(0, 0, 0), Color("#5a5852"), true)
    stick = Node3D.new()
    stick.name = "StickPivot"
    stick.position = Vector3(0, 0, -3.00)
    boom.add_child(stick)
    var stick_art := Node3D.new()
    stick_art.name = "PlaceholderStick"
    stick.add_child(stick_art)
    M.block(stick_art, Vector3(0.27, 0.40, 2.36), Vector3(0, 0, -1.18), Color("#dc7010"))
    M.cylinder(stick_art, 0.19, 0.42, Vector3.ZERO, Color("#424545"), true)
    bucket = Node3D.new()
    bucket.name = "BucketPivot"
    bucket.position = Vector3(0, 0, -2.28)
    stick.add_child(bucket)
    var bucket_art := Node3D.new()
    bucket_art.name = "PlaceholderBucket"
    bucket.add_child(bucket_art)
    M.block(bucket_art, Vector3(0.97, 0.63, 0.80), Vector3(0, -0.31, -0.37), Color("#4d4a3f"))
    for i in range(5):
        M.block(bucket_art, Vector3(0.13, 0.13, 0.31),
            Vector3(-0.36 + float(i) * 0.18, -0.63, -0.75), Color("#89867b"))
    VIS.place_visual(upper, upper_art, "res://landworks/assets/rigged/kx080_upper.glb")
    VIS.place_visual(boom, boom_art, "res://landworks/assets/rigged/kx080_boom.glb")
    VIS.place_visual(stick, stick_art, "res://landworks/assets/rigged/kx080_stick.glb")
    VIS.place_visual(bucket, bucket_art, "res://landworks/assets/rigged/kx080_bucket.glb")
    _update_arm()

func _update_arm() -> void:
    upper.rotation.y = slewing_angle
    boom.rotation.x = boom_angle
    stick.rotation.x = stick_angle
    bucket.rotation.x = bucket_angle

func _physics_process(delta: float) -> void:
    var input_boom := 0.0
    var input_stick := 0.0
    var input_bucket := 0.0
    var input_slew := 0.0
    var travel := 0.0
    var steering := 0.0
    if controlled:
        input_boom = -CI.stick_y(true) + float(Input.is_key_pressed(KEY_I)) - float(Input.is_key_pressed(KEY_K))
        input_stick = -CI.stick_y(false) + float(Input.is_key_pressed(KEY_O)) - float(Input.is_key_pressed(KEY_L))
        input_bucket = CI.stick_x(false) + float(Input.is_key_pressed(KEY_P)) - float(Input.is_key_pressed(KEY_SEMICOLON))
        input_slew = CI.slew()
        travel = CI.throttle()
        steering = CI.steering()
    boom_angle = clampf(boom_angle + clampf(input_boom, -1.0, 1.0) * 0.40 * delta, -0.38, 1.05)
    stick_angle = clampf(stick_angle + clampf(input_stick, -1.0, 1.0) * 0.57 * delta, -1.65, 0.05)
    bucket_angle = clampf(bucket_angle + clampf(input_bucket, -1.0, 1.0) * 0.79 * delta, -1.50, 0.60)
    slewing_angle += input_slew * 0.48 * delta
    _update_arm()
    # Simplified crawler propulsion with force limits. Not a per-track contact sim.
    if controlled:
        var desired := -global_transform.basis.z * travel * 1.7
        var diff := desired - linear_velocity
        diff.y = 0.0
        apply_central_force(diff * 22000.0)
        apply_torque(Vector3.UP * steering * -90000.0)
