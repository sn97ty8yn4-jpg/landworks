# Independent two-wheel single-axle farm trailer with suspended tyres, physical hitch
# and a combined-body payload. The tyre model is deliberately a simple force proxy.
extends RigidBody3D

const M = preload("res://landworks/scripts/mesh_factory.gd")

@export var payload_kg := 400.0
@export var empty_mass_kg := 320.0
@export var tyre_mu := 0.80
@export var wheel_radius := 0.36
@export var wheel_travel := 0.23

var wheel_visuals: Array[Node3D] = []
var last_contact_count := 0

func _ready() -> void:
    name = "SingleAxleLoadTrailer"
    mass = empty_mass_kg + payload_kg
    can_sleep = false
    continuous_cd = true
    linear_damp = 0.05
    angular_damp = 0.12
    center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
    # Payload is carried above and slightly forward of the axle, not at ground level.
    center_of_mass = Vector3(0.0, 0.23 * payload_kg / maxf(mass, 1.0), -0.10)
    var chassis_shape := BoxShape3D.new()
    chassis_shape.size = Vector3(1.62, 0.22, 2.55)
    var c := CollisionShape3D.new()
    c.shape = chassis_shape
    c.position = Vector3(0, 0.07, -0.05)
    add_child(c)
    M.block(self, Vector3(1.62, 0.22, 2.55), Vector3(0, 0.07, -0.05), Color("#777e7a"))
    M.block(self, Vector3(0.13, 0.12, 1.32), Vector3(0, -0.13, -1.41), Color("#555d5d"))
    M.block(self, Vector3(0.10, 0.45, 2.55), Vector3(-0.80, 0.32, -0.05), Color("#77817a"))
    M.block(self, Vector3(0.10, 0.45, 2.55), Vector3(0.80, 0.32, -0.05), Color("#77817a"))
    M.block(self, Vector3(1.61, 0.43, 0.09), Vector3(0, 0.31, 1.22), Color("#77817a"))
    M.block(self, Vector3(1.35, 0.28, 1.64), Vector3(0, 0.37, -0.09), Color("#8b765a"))
    if payload_kg > 0.0:
        M.block(self, Vector3(1.24, 0.20 + 0.0004 * payload_kg, 1.44),
            Vector3(0, 0.57 + 0.0002 * payload_kg, -0.09), Color("#a48d68"))
    for side in [-0.79, 0.79]:
        var wheel_root := Node3D.new()
        wheel_root.position = Vector3(side, -0.28, 0.50)
        wheel_root.name = "TrailerWheelVisual"
        add_child(wheel_root)
        M.tyre(wheel_root, wheel_radius, 0.19, Vector3.ZERO, true)
        wheel_visuals.append(wheel_root)

func _physics_process(delta: float) -> void:
    last_contact_count = 0
    var forward := -global_transform.basis.z
    var sideways := global_transform.basis.x
    for i in range(2):
        var side := -0.79 if i == 0 else 0.79
        var local_contact := Vector3(side, -0.28, 0.50)
        var world_origin := to_global(local_contact)
        var query := PhysicsRayQueryParameters3D.create(world_origin,
            world_origin + Vector3.DOWN * (wheel_radius + wheel_travel + 0.15))
        query.exclude = [get_rid()]
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        if hit.is_empty():
            continue
        last_contact_count += 1
        var compression := clampf(wheel_travel - (world_origin.distance_to(hit["position"]) - wheel_radius),
            0.0, wheel_travel)
        var point_offset: Vector3 = hit["position"] - global_position
        var point_velocity := linear_velocity + angular_velocity.cross(point_offset)
        var vertical_speed := point_velocity.dot(Vector3.UP)
        var spring_force := maxf(0.0, 44000.0 * compression - 5500.0 * vertical_speed)
        var friction_cap := spring_force * tyre_mu
        var sideways_speed := point_velocity.dot(sideways)
        var longitudinal_speed := point_velocity.dot(forward)
        var lateral_force := clampf(-sideways_speed * mass * 2.0, -friction_cap, friction_cap)
        # Unpowered free-rolling wheels: resistance, not an invented drive motor.
        var longitudinal_drag := clampf(-longitudinal_speed * 68.0,
            -friction_cap, friction_cap)
        apply_force(Vector3.UP * spring_force + sideways * lateral_force + forward * longitudinal_drag,
            point_offset)
        wheel_visuals[i].rotate_x(longitudinal_speed * delta / wheel_radius)
