# B7100 HST rigid-body prototype with raycast tyres and a power-constrained
# hydrostatic pump/motor response. This is a physics approximation, not an OEM HST model.
extends RigidBody3D

const M = preload("res://landworks/scripts/mesh_factory.gd")
const CI = preload("res://landworks/scripts/machine_input.gd")
const VIS = preload("res://landworks/scripts/model_swap.gd")

var controlled: bool = false
# Scripted benchmark input takes precedence over controller, but only when enabled.
var benchmark_enabled: bool = false
var benchmark_throttle: float = 0.0
var benchmark_steer: float = 0.0
var benchmark_brake: float = 0.0
# Optional engine-drive speed governor for low-speed working tests.
# Does NOT clamp body velocity; gravity and inertia can still exceed the limit.
var work_speed_limit_kmh: float = 0.0
var wheel_data: Array[Dictionary] = []
var body_visual: Node3D
var speed_kmh: float = 0.0
var steer_request: float = 0.0
var throttle_request: float = 0.0
# Engine throttle lever is independent of hydrostatic travel pedal. 2800 rpm
# and 11.7 kW are B7100HST D750-A published ratings; ratio losses and
# response gains below are provisional, not OEM calibration.
@export_range(900.0, 2800.0, 50.0) var engine_rpm := 2800.0
@export_enum("Low:1", "High:2") var hst_range := 2
@export_range(0.45, 0.90, 0.01) var hst_efficiency := 0.72
var last_requested_hst_force_n := 0.0
var last_hst_power_limit_n := 0.0
var last_hst_power_kw := 0.0
var tyre_grip_utilisation := 0.0

# Approximate compact tractor parameters. Adjust using real dimensions and test data.
const VEHICLE_MASS := 573.0
const REST_TRAVEL := 0.20
const SPRING_RATE := 38000.0
const DAMPER_RATE := 4600.0
const GROUND_MU := 0.86
# Sandbox surface assignment; field trials keep the original 0.86 default.
var ground_mu_override: float = GROUND_MU
const MAX_STEER := 0.50
const DRIVE_FORCE := 4250.0
const RATED_ENGINE_POWER_W := 11700.0
const HST_LOW_MAX_KMH := 5.7
const HST_HIGH_MAX_KMH := 14.5
const HST_SPEED_GAIN_N_PER_MPS := 3800.0
const HST_HYDRAULIC_BRAKING_N := 1850.0

func _ready() -> void:
    mass = VEHICLE_MASS
    linear_damp = 0.35
    angular_damp = 2.0
    continuous_cd = true
    can_sleep = false
    _build_body()

func _build_body() -> void:
    var cs := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(0.98, 0.63, 2.15)
    cs.shape = box
    cs.position = Vector3(0, 0.06, 0)
    add_child(cs)
    body_visual = Node3D.new()
    body_visual.name = "PlaceholderTractorBody"
    add_child(body_visual)
    M.block(body_visual, Vector3(0.86, 0.34, 1.40), Vector3(0, 0.29, -0.34), Color("#df6d13"))
    M.block(body_visual, Vector3(0.76, 0.08, 1.35), Vector3(0, 0.48, -0.35), Color("#f18a19"))
    M.block(body_visual, Vector3(0.65, 0.23, 0.56), Vector3(0, -0.12, -0.68), Color("#363b3b"))
    M.block(body_visual, Vector3(0.83, 0.17, 0.68), Vector3(0, 0.12, 0.48), Color("#343b40"))
    M.block(body_visual, Vector3(1.14, 0.10, 0.50), Vector3(0, 0.36, 0.48), Color("#dd6a12"))
    M.block(body_visual, Vector3(0.48, 0.13, 0.39), Vector3(0, 0.70, 0.52), Color("#333639"))
    M.block(body_visual, Vector3(0.36, 0.14, 0.17), Vector3(0, 0.84, 0.57), Color("#27282a"))
    M.cylinder(body_visual, 0.19, 0.045, Vector3(0, 0.75, -0.02), Color("#27282a"))
    M.cylinder(body_visual, 0.055, 0.42, Vector3(0.28, 0.66, -0.76), Color("#454545"))
    # Roll-over protection hoop, prominent on an open compact tractor.
    M.block(body_visual, Vector3(0.065, 1.25, 0.065), Vector3(-0.43, 0.95, 0.66), Color("#313232"))
    M.block(body_visual, Vector3(0.065, 1.25, 0.065), Vector3(0.43, 0.95, 0.66), Color("#313232"))
    M.block(body_visual, Vector3(0.94, 0.065, 0.065), Vector3(0, 1.57, 0.66), Color("#313232"))
    # Real B7100HST turf sizes: front 20.5 x 8.00-10; rear 29 x 12.00-15.
    # Mounts span the documented 1.39 m wheelbase (centre-to-centre).
    _wheel(Vector3(-0.35, -0.14, 0.70), 0.3683, 0.3048, false, 0.65)
    _wheel(Vector3(0.35, -0.14, 0.70), 0.3683, 0.3048, false, 0.65)
    _wheel(Vector3(-0.37, -0.24, -0.69), 0.26035, 0.2032, true, 0.35)
    _wheel(Vector3(0.37, -0.24, -0.69), 0.26035, 0.2032, true, 0.35)
    VIS.place_visual(self, body_visual, "res://landworks/assets/rigged/b7100_body.glb")

func _wheel(at: Vector3, radius: float, width: float, steering: bool, torque_share: float) -> void:
    var root := Node3D.new()
    add_child(root)
    root.position = at - Vector3(0, REST_TRAVEL, 0)
    var spin := Node3D.new()
    spin.name = "WheelSpin"
    root.add_child(spin)
    var fallback := M.tyre(spin, radius, width, Vector3.ZERO, true)
    var wheel_file := "b7100_wheel_front.glb" if steering else "b7100_wheel_rear.glb"
    VIS.place_visual(spin, fallback, "res://landworks/assets/rigged/" + wheel_file)
    wheel_data.append({"mount": at, "radius": radius, "steering": steering,
        "drive_share": torque_share, "root": root, "visual": spin, "rotation": 0.0})

func _physics_process(delta: float) -> void:
    var target_throttle := benchmark_throttle if benchmark_enabled else (CI.throttle() if controlled else 0.0)
    var target_steer := benchmark_steer if benchmark_enabled else (CI.steering() if controlled else 0.0)
    throttle_request = move_toward(throttle_request, target_throttle, delta * 2.1)
    steer_request = move_toward(steer_request, target_steer, delta * 2.8)
    var forward := -global_transform.basis.z
    speed_kmh = linear_velocity.dot(forward) * 3.6
    # Swashplate pedal requests travel speed, not engine torque. Available
    # wheel force decreases with speed according to the finite diesel power.
    # At zero pedal, hydrostatic resistance decelerates rather than instantly
    # freezing the physics body's velocity.
    var rated_speed_kmh := HST_LOW_MAX_KMH if hst_range == 1 else HST_HIGH_MAX_KMH
    rated_speed_kmh *= engine_rpm / 2800.0
    if work_speed_limit_kmh > 0.0:
        rated_speed_kmh = minf(rated_speed_kmh, work_speed_limit_kmh)
    var pedal_speed_mps := throttle_request * rated_speed_kmh / 3.6
    var engine_power_w := RATED_ENGINE_POWER_W * pow(engine_rpm / 2800.0, 1.6)
    var available_wheel_power_w := engine_power_w * hst_efficiency
    last_hst_power_kw = available_wheel_power_w / 1000.0
    var speed_mps := speed_kmh / 3.6
    last_hst_power_limit_n = minf(DRIVE_FORCE,
        available_wheel_power_w / maxf(absf(speed_mps), 0.70))
    var speed_error := pedal_speed_mps - speed_mps
    var requested_force := speed_error * HST_SPEED_GAIN_N_PER_MPS
    # Pump flow near zero pedal gives braking/holding, not reverse drive power.
    var drive_limit := last_hst_power_limit_n
    if absf(speed_error) > 0.01 and absf(pedal_speed_mps) < absf(speed_mps):
        drive_limit = minf(drive_limit, HST_HYDRAULIC_BRAKING_N)
    if absf(throttle_request) < 0.03:
        drive_limit = minf(drive_limit, HST_HYDRAULIC_BRAKING_N)
    last_requested_hst_force_n = clampf(requested_force, -drive_limit, drive_limit)
    tyre_grip_utilisation = 0.0
    for i in range(wheel_data.size()):
        var wheel: Dictionary = wheel_data[i]
        var mount: Vector3 = wheel["mount"]
        var rad: float = wheel["radius"]
        var is_front: bool = wheel["steering"]
        var root: Node3D = wheel["root"]
        var visual: Node3D = wheel["visual"]
        var steer_angle := -steer_request * MAX_STEER if is_front else 0.0
        root.rotation.y = steer_angle
        var contact_origin := to_global(mount)
        var ray_end := contact_origin - Vector3.UP * (rad + REST_TRAVEL + 0.14)
        var query := PhysicsRayQueryParameters3D.create(contact_origin, ray_end)
        query.exclude = [get_rid()]
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        var compression := 0.0
        var wheel_forward := -global_transform.basis.z.rotated(Vector3.UP, steer_angle)
        var wheel_right := wheel_forward.cross(Vector3.UP).normalized()
        if not hit.is_empty():
            var distance := contact_origin.distance_to(hit["position"])
            compression = clampf(REST_TRAVEL - (distance - rad), 0.0, REST_TRAVEL)
            var relative: Vector3 = hit["position"] - global_position
            var point_velocity := linear_velocity + angular_velocity.cross(relative)
            var vertical_speed := point_velocity.dot(Vector3.UP)
            var normal_force := maxf(0.0, SPRING_RATE * compression - DAMPER_RATE * vertical_speed)
            var friction_limit := normal_force * ground_mu_override
            apply_force(Vector3.UP * normal_force, relative)
            var longitudinal_speed := point_velocity.dot(wheel_forward)
            var lateral_speed := point_velocity.dot(wheel_right)
            var wheel_drive: float = wheel["drive_share"]
            var traction := last_requested_hst_force_n * wheel_drive * 0.5
            # Rolling resistance & engine braking, plus active reverse / forward input.
            traction -= longitudinal_speed * (125.0 + benchmark_brake * 1100.0)
            var lateral := clampf(-lateral_speed * VEHICLE_MASS * 2.2,
                -friction_limit, friction_limit)
            # A tyre has one shared friction budget for longitudinal drive and
            # lateral cornering; independent clamping permitted sqrt(2)*mu loads.
            var combined := Vector2(traction, lateral)
            var demand_magnitude := combined.length()
            var limit := maxf(friction_limit, 0.01)
            tyre_grip_utilisation = maxf(tyre_grip_utilisation, demand_magnitude / limit)
            if demand_magnitude > limit:
                combined *= limit / demand_magnitude
            apply_force(wheel_forward * combined.x + wheel_right * combined.y, relative)
            visual.rotation.x += longitudinal_speed / maxf(rad, 0.1) * delta
        root.position = mount - Vector3(0, REST_TRAVEL - compression, 0)
    # Resist yaw only weakly when underway; wheels supply the actual turn force.
    angular_damp = 0.7 if controlled else 2.0
