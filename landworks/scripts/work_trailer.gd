# Single-axle farm tipping trailer, remapped onto the rigged model. The body
# origin sits on the ground under the axle centre, as the model's root does.
# Geometry below is measured from the model: 1.33 m wheel track on 730 mm
# tyres, ring hitch 2.00 m ahead of the axle at 500 mm, and a tray hinged on
# a rear pin 840 mm behind the axle at 725 mm. The tyre model stays a simple
# force proxy; the tipping tray is a genuine hinged body with a torque limit.
extends RigidBody3D

const M = preload("res://landworks/scripts/mesh_factory.gd")

# Measured from farm_tipping_trailer.glb.
const WHEEL_RADIUS := 0.365
const HALF_TRACK := 0.665
const HITCH_POINT := Vector3(0.0, 0.50, -2.00)
const TRAY_PIN := Vector3(0.0, 0.725, 0.84)
const TRAY_SIZE := Vector3(1.358, 0.44, 2.186)
const CHASSIS_SIZE := Vector3(1.32, 0.30, 2.05)
# Jockey foot under the drawbar, measured from the model.
const JOCKEY_FOOT := Vector3(-0.30, 0.0, -1.86)
const TIP_LIMIT_RAD := 0.785
const TIP_TORQUE_LIMIT_NM := 26000.0

@export var payload_kg := 400.0
@export var empty_mass_kg := 380.0
@export var tyre_mu := 0.80
@export var wheel_radius := WHEEL_RADIUS
@export var wheel_travel := 0.23

var wheel_visuals: Array[Node3D] = []
var last_contact_count := 0
var tray: RigidBody3D
var tray_joint: HingeJoint3D
var tip_target := 0.0
# Set by the sandbox each tick. An uncoupled single-axle trailer rests on its
# jockey stand; without it the drawbar simply noses into the ground.
var hitched := true
var jockey_contact := false
var jockey_shape: CollisionShape3D

func _ready() -> void:
	name = "SingleAxleTippingTrailer"
	# Until a tray is built the body carries the payload itself, so a trailer
	# used without one (the tow field trials) still loads its axle.
	mass = empty_mass_kg + payload_kg
	can_sleep = false
	continuous_cd = true
	linear_damp = 0.05
	angular_damp = 0.12
	var chassis_shape := BoxShape3D.new()
	chassis_shape.size = CHASSIS_SIZE
	var c := CollisionShape3D.new()
	c.shape = chassis_shape
	c.position = Vector3(0, 0.52, 0)
	add_child(c)
	M.block(self, CHASSIS_SIZE, c.position, Color("#2d3233"))
	# Drawbar out to the ring hitch, and the axle beam.
	M.block(self, Vector3(0.14, 0.14, 1.60), Vector3(0, 0.50, -1.25), Color("#2d3233"))
	M.block(self, Vector3(1.42, 0.16, 0.22), Vector3(0, 0.365, 0), Color("#2d3233"))
	# Jockey stand: a foot under the drawbar, deployed whenever unhitched.
	var jockey_box := BoxShape3D.new()
	jockey_box.size = Vector3(0.18, 0.10, 0.18)
	jockey_shape = CollisionShape3D.new()
	jockey_shape.name = "JockeyStandFoot"
	jockey_shape.shape = jockey_box
	jockey_shape.position = JOCKEY_FOOT + Vector3(0, 0.05, 0)
	jockey_shape.disabled = true
	add_child(jockey_shape)
	M.block(self, Vector3(0.10, 0.52, 0.10),
		JOCKEY_FOOT + Vector3(0, 0.30, 0), Color("#2d3233"))
	for side in [-HALF_TRACK, HALF_TRACK]:
		var wheel_root := Node3D.new()
		wheel_root.position = Vector3(side, WHEEL_RADIUS, 0)
		wheel_root.name = "TrailerWheelVisual"
		add_child(wheel_root)
		M.tyre(wheel_root, wheel_radius, 0.22, Vector3.ZERO, true)
		wheel_visuals.append(wheel_root)

# Called by the sandbox once the trailer is in the tree, so the tray can be a
# sibling body rather than a rigid body nested inside another one.
func build_tray(container: Node) -> void:
	# The payload moves into the tray, which is the body that actually tips.
	mass = empty_mass_kg
	tray = RigidBody3D.new()
	tray.name = "TippingTray"
	tray.mass = 240.0 + payload_kg
	tray.can_sleep = false
	tray.continuous_cd = true
	tray.linear_damp = 0.05
	tray.angular_damp = 0.20
	container.add_child(tray)
	tray.global_transform = Transform3D(global_transform.basis, to_global(TRAY_PIN))
	# An open-topped body, not a solid block: a solid tray cannot be loaded,
	# which is why blocks would not go in and spoil had nowhere to sit. Floor
	# plus four sides, hung forward of the rear hinge pin.
	var mid := -TRAY_SIZE.z * 0.5
	var wall := 0.05
	var side_h := 0.34
	for part in [
			{"size": Vector3(TRAY_SIZE.x, 0.06, TRAY_SIZE.z), "at": Vector3(0, 0.03, mid)},
			{"size": Vector3(wall, side_h, TRAY_SIZE.z),
				"at": Vector3(TRAY_SIZE.x * 0.5 - wall * 0.5, 0.20, mid)},
			{"size": Vector3(wall, side_h, TRAY_SIZE.z),
				"at": Vector3(-TRAY_SIZE.x * 0.5 + wall * 0.5, 0.20, mid)},
			{"size": Vector3(TRAY_SIZE.x, side_h, wall),
				"at": Vector3(0, 0.20, mid - TRAY_SIZE.z * 0.5 + wall * 0.5)},
			{"size": Vector3(TRAY_SIZE.x, side_h, wall),
				"at": Vector3(0, 0.20, mid + TRAY_SIZE.z * 0.5 - wall * 0.5)}]:
		var panel := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(part["size"])
		panel.shape = box
		panel.position = Vector3(part["at"])
		tray.add_child(panel)
		M.block(tray, box.size, panel.position, Color("#1f7f82"))
	tray_joint = HingeJoint3D.new()
	tray_joint.name = "TrayTipPin"
	container.add_child(tray_joint)
	tray_joint.global_transform = Transform3D(
		Basis(Quaternion(Vector3.BACK, global_transform.basis.x.normalized())),
		to_global(TRAY_PIN))
	tray_joint.node_a = tray_joint.get_path_to(self)
	tray_joint.node_b = tray_joint.get_path_to(tray)
	tray_joint.exclude_nodes_from_collision = true
	tray_joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	# The hinge's own positive direction drops the front, so the travel that
	# raises it is the negative side of the pin.
	tray_joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -TIP_LIMIT_RAD)
	tray_joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, 0.0)
	tray_joint.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
	tray_joint.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE,
		TIP_TORQUE_LIMIT_NM / float(Engine.physics_ticks_per_second))

func tip_angle_rad() -> float:
	if not is_instance_valid(tray):
		return 0.0
	# Positive is FRONT UP, the way a tipper actually works. The operand order
	# matters: reversed, this reads positive while the front dips, which is
	# exactly the fault that shipped.
	var reference: Vector3 = -tray.global_transform.basis.z
	var current: Vector3 = -global_transform.basis.z
	var axis: Vector3 = global_transform.basis.x.normalized()
	return atan2(current.cross(reference).dot(axis), current.dot(reference))

func command_tip(direction: float, delta: float) -> void:
	tip_target = clampf(tip_target + direction * delta * 0.32, 0.0, TIP_LIMIT_RAD)

func _physics_process(delta: float) -> void:
	if is_instance_valid(tray_joint):
		# Negated to match the pin's own direction: a positive tip_target has
		# to drive the hinge negative to lift the front.
		tray_joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,
			-clampf(1.8 * (tip_target - tip_angle_rad()), -0.4, 0.4))
	_support_on_jockey()
	last_contact_count = 0
	var forward := -global_transform.basis.z
	var sideways := global_transform.basis.x
	for i in range(2):
		var side := -HALF_TRACK if i == 0 else HALF_TRACK
		var local_contact := Vector3(side, WHEEL_RADIUS, 0)
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
		# Carrying the tray and its load on the same axle needs more spring.
		var spring_force := maxf(0.0, 62000.0 * compression - 7400.0 * vertical_speed)
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

func _support_on_jockey() -> void:
	# Parked on its stand, the trailer rests on the jockey foot at the
	# drawbar. This is a contact force against whatever is under the foot,
	# not a frozen transform: shunting the trailer still moves it.
	jockey_contact = false
	if hitched:
		return
	# The stand is a real collision shape, enabled only when the drawbar is
	# not on a ball. Letting the solver handle the contact avoids inventing a
	# spring, and shunting the parked trailer still moves it.
	if jockey_shape == null:
		return
	jockey_shape.disabled = hitched
	jockey_contact = not hitched
