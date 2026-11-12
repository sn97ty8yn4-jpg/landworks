# Binds the rigged KX080-3 and farm-tipping-trailer GLBs onto the live physics
# bodies. Every art node follows a genuine rigid body or a solved joint angle;
# this script never writes a body transform, creates a collision shape or
# fabricates a working angle. Cylinders are aimed at their real pin partners
# each frame, the way the source rig aims them with Damped Track.
extends Node3D

const MACHINE_GLB := "res://landworks/assets/engineered/kx080_3_machine.glb"
const TRAILER_GLB := "res://landworks/assets/engineered/farm_tipping_trailer.glb"

# Both models are authored +X forward, +Y up, machine-left -Z. The sandbox
# drives every limb along -Z, so the bound art carries a quarter turn.
const MODEL_YAW := PI * 0.5

# Undercarriage running gear, measured from the model: sprocket and idler
# centres at +/-1.07 m, 0.355 m up, 0.245 m pitch radius, 39 shoes a side.
const TRACK_RADIUS := 0.245
const TRACK_HALF_STRAIGHT := 1.07
const TRACK_CENTRE_HEIGHT := 0.355
const TRACK_GAUGE_HALF := 0.875
const TRACK_LOOP := 2.0 * (2.0 * TRACK_HALF_STRAIGHT) + TAU * TRACK_RADIUS
const SHOES_PER_SIDE := 39

var excavator: Node3D
var trailer: Node3D
var machine_root: Node3D
var trailer_root: Node3D
var bound_parts := 0
var missing_parts: Array[String] = []
var cylinders: Array[Dictionary] = []
var track_multimeshes: Array[MultiMesh] = []
var track_phase := [0.0, 0.0]
var bucket_tip: Node3D
var tray_art: Node3D
var blade_art: Node3D
var king_post_art: Node3D
var cab: Node3D
var bucket_fill: MeshInstance3D
var fill_step := -1
var fill_material := ""

func _instantiate(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Landworks: missing rigged model " + path)
		return null
	var root := packed.instantiate() as Node3D
	# The baked demo clip must never drive a part whose angle the solver owns.
	var player := root.find_child("AnimationPlayer", true, false)
	if player != null:
		player.get_parent().remove_child(player)
		player.queue_free()
	add_child(root)
	return root

func _find(root: Node, part: String) -> Node3D:
	if root == null:
		return null
	var node := root.find_child(part, true, false) as Node3D
	if node == null:
		missing_parts.append(part)
		push_error("Landworks: rigged model has no part named " + part)
	return node

# Reparents a model part onto a physics body. `offset` is the part's rest
# position in the body's own frame; limb pivots sit exactly on the origin.
func _bind(part: Node3D, body: Node3D, offset: Vector3 = Vector3.ZERO) -> Node3D:
	if part == null or body == null:
		return null
	var parent := part.get_parent()
	if parent != null:
		parent.remove_child(part)
	body.add_child(part)
	part.transform = Transform3D(Basis(Vector3.UP, MODEL_YAW), offset)
	bound_parts += 1
	return part

func _hide_primitive_art(body: Node) -> void:
	# The placeholder blocks and cylinders stay in the tree so collision shapes
	# and their positions are untouched; only their meshes stop drawing.
	for child in body.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false

func _register_cylinder(barrel: Node3D, barrel_pin: Node3D,
		rod: Node3D, rod_pin: Node3D) -> void:
	if barrel == null or rod == null or barrel_pin == null or rod_pin == null:
		return
	cylinders.append({"barrel": barrel, "barrel_pin": barrel_pin,
		"rod": rod, "rod_pin": rod_pin})

# Points a part's own +X axis at a world target, keeping it upright.
static func _aim(node: Node3D, target: Vector3) -> void:
	var origin := node.global_position
	var direction := target - origin
	if direction.length_squared() < 1e-8:
		return
	var x := direction.normalized()
	var reference := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var z := x.cross(reference).normalized()
	var y := z.cross(x).normalized()
	node.global_transform = Transform3D(Basis(x, y, z), origin)

func _aim_cylinders() -> void:
	for cylinder in cylinders:
		var barrel: Node3D = cylinder["barrel"]
		var rod: Node3D = cylinder["rod"]
		if not is_instance_valid(barrel) or not is_instance_valid(rod):
			continue
		var rod_pin: Node3D = cylinder["rod_pin"]
		var barrel_pin: Node3D = cylinder["barrel_pin"]
		_aim(barrel, rod_pin.global_position)
		_aim(rod, barrel_pin.global_position)

func _build_tracks(source: Node3D, body: Node3D) -> void:
	var shoe := _find(source, "Track_L_Shoe_00")
	var mesh: Mesh = (shoe as MeshInstance3D).mesh if shoe is MeshInstance3D else null
	# The 78 individual shoes are replaced by two MultiMeshes: the same steel
	# shoe drawn 39 times a side, circulating on the measured loop.
	for n in range(SHOES_PER_SIDE):
		for prefix in ["Track_L_Shoe_", "Track_R_Shoe_"]:
			var individual := source.find_child(prefix + "%02d" % n, true, false)
			if individual != null:
				individual.get_parent().remove_child(individual)
				individual.queue_free()
	if mesh == null:
		push_error("Landworks: rigged model has no track shoe mesh")
		return
	for side in [-1.0, 1.0]:
		var instance := MultiMeshInstance3D.new()
		instance.name = "CirculatingTrackShoes_Left" if side < 0.0 else "CirculatingTrackShoes_Right"
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = SHOES_PER_SIDE
		instance.multimesh = multi
		instance.custom_aabb = AABB(Vector3(-1.2, -0.05, -1.5), Vector3(2.4, 0.9, 3.0))
		body.add_child(instance)
		track_multimeshes.append(multi)
	_update_track_transforms()

func _track_sample(distance: float, side: float) -> Transform3D:
	# Stadium loop around the rear sprocket and front idler, tangent-continuous.
	var s := fposmod(distance, TRACK_LOOP)
	var y := TRACK_CENTRE_HEIGHT
	var z := 0.0
	var angle := 0.0
	var straight := TRACK_HALF_STRAIGHT * 2.0
	var arc := PI * TRACK_RADIUS
	if s < straight:
		z = -TRACK_HALF_STRAIGHT + s
		y -= TRACK_RADIUS
		angle = PI
	elif s < straight + arc:
		var t := (s - straight) / TRACK_RADIUS
		z = TRACK_HALF_STRAIGHT + sin(t) * TRACK_RADIUS
		y -= cos(t) * TRACK_RADIUS
		angle = PI - t
	elif s < straight * 2.0 + arc:
		z = TRACK_HALF_STRAIGHT - (s - straight - arc)
		y += TRACK_RADIUS
	else:
		var t := (s - straight * 2.0 - arc) / TRACK_RADIUS
		z = -TRACK_HALF_STRAIGHT - sin(t) * TRACK_RADIUS
		y += cos(t) * TRACK_RADIUS
		angle = -t
	return Transform3D(Basis(Vector3.RIGHT, angle), Vector3(side * TRACK_GAUGE_HALF, y, z))

func _update_track_transforms() -> void:
	for index in range(track_multimeshes.size()):
		var side := -1.0 if index == 0 else 1.0
		for n in range(SHOES_PER_SIDE):
			track_multimeshes[index].set_instance_transform(n,
				_track_sample(float(n) * TRACK_LOOP / float(SHOES_PER_SIDE) + track_phase[index], side))

func attach_excavator(machine: Node3D) -> void:
	excavator = machine
	machine_root = _instantiate(MACHINE_GLB)
	if machine_root == null:
		return
	# Collect every part before reparenting: binding a limb carries its whole
	# subtree, so the references must be taken while the rig is still intact.
	var undercarriage := _find(machine_root, "Undercarriage")
	var upper_swing := _find(machine_root, "Upper_Swing")
	var bracket := _find(machine_root, "Boom_Swing_Bracket")
	var boom := _find(machine_root, "Boom")
	var arm := _find(machine_root, "Arm")
	var bucket := _find(machine_root, "Bucket")
	var blade := _find(machine_root, "Dozer_Blade")
	bucket_tip = _find(machine_root, "Bucket_Tip")
	var pins := {}
	for pin in ["Pin_Boom_Base", "Pin_Boom_Rod", "Pin_Arm_Base", "Pin_Arm_Rod",
			"Pin_Bucket_Base", "Pin_HLink_Q", "Pin_Swing_Base", "Pin_Swing_Rod",
			"Pin_Blade_Base", "Pin_Blade_Rod"]:
		pins[pin] = _find(machine_root, pin)
	var barrels := {}
	for part in ["Cyl_Boom_Barrel", "Cyl_Boom_Rod", "Cyl_Arm_Barrel", "Cyl_Arm_Rod",
			"Cyl_Bucket_Barrel", "Cyl_Bucket_Rod", "Cyl_Swing_Barrel",
			"Cyl_Swing_Rod", "Cyl_Blade_Barrel", "Cyl_Blade_Rod"]:
		barrels[part] = _find(machine_root, part)
	_build_tracks(machine_root, excavator.undercarriage)
	for body in [excavator.undercarriage, excavator.upper, excavator.boom,
			excavator.stick, excavator.bucket]:
		_hide_primitive_art(body)
	# Upper_Swing sits 0.80 m above ground on the swing bearing; every other
	# bound limb pivots exactly on its body origin.
	_bind(undercarriage, excavator.undercarriage)
	_bind(upper_swing, excavator.upper, Vector3(0.0, 0.80, 0.0))
	var post_body: Node3D = excavator.get("king_post")
	if post_body != null:
		_hide_primitive_art(post_body)
		king_post_art = _bind(bracket, post_body)
	else:
		king_post_art = _bind(bracket, excavator.boom, Vector3(0.0, -0.26, 0.30))
	_bind(boom, excavator.boom)
	_bind(arm, excavator.stick)
	_bind(bucket, excavator.bucket)
	var blade_body: Node3D = excavator.get("dozer_blade")
	if blade_body != null:
		_hide_primitive_art(blade_body)
		blade_art = _bind(blade, blade_body)
	else:
		blade_art = _bind(blade, excavator.undercarriage, Vector3(0.0, 0.30, -0.62))
	_register_cylinder(barrels["Cyl_Boom_Barrel"], pins["Pin_Boom_Base"],
		barrels["Cyl_Boom_Rod"], pins["Pin_Boom_Rod"])
	_register_cylinder(barrels["Cyl_Arm_Barrel"], pins["Pin_Arm_Base"],
		barrels["Cyl_Arm_Rod"], pins["Pin_Arm_Rod"])
	_register_cylinder(barrels["Cyl_Bucket_Barrel"], pins["Pin_Bucket_Base"],
		barrels["Cyl_Bucket_Rod"], pins["Pin_HLink_Q"])
	_register_cylinder(barrels["Cyl_Swing_Barrel"], pins["Pin_Swing_Base"],
		barrels["Cyl_Swing_Rod"], pins["Pin_Swing_Rod"])
	_register_cylinder(barrels["Cyl_Blade_Barrel"], pins["Pin_Blade_Base"],
		barrels["Cyl_Blade_Rod"], pins["Pin_Blade_Rod"])
	# Seated operator station. The modelled cab interior is not split into
	# separate lever nodes, so the camera works and the levers stay static.
	cab = preload("res://landworks/scripts/detailed_cab.gd").new()
	cab.name = "DetailedOperatorStation"
	cab.EYE_OVERRIDE = Vector3(-0.58, 1.90, -0.05)
	excavator.upper.add_child(cab)
	cab.attach(upper_swing)
	bucket_fill = MeshInstance3D.new()
	bucket_fill.name = "ActualStoredSoilVisual"
	bucket_fill.visible = false
	excavator.bucket.add_child(bucket_fill)

# Carried soil drawn inside the bucket shell. The volume comes from the soil
# solver's own inventory; this only draws it.
func update_bucket_fill(volume_m3: float, soil_type: String) -> void:
	if bucket_fill == null:
		return
	var level := clampi(int(round(volume_m3 / 0.24 * 24.0)), 0, 24)
	if level == fill_step and soil_type == fill_material:
		return
	fill_step = level
	fill_material = soil_type
	bucket_fill.visible = level > 0
	if level == 0:
		return
	var fill := float(level) / 24.0
	var box := BoxMesh.new()
	box.size = Vector3(0.58, 0.30 * fill, 0.52)
	bucket_fill.mesh = box
	# Sit the load on the bucket floor, between the pin and the tooth tip.
	bucket_fill.position = Vector3(0.0, -0.26 + 0.15 * fill, -0.44)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#6b5636") if soil_type == "clay" else Color("#7d7566")
	material.roughness = 0.95
	bucket_fill.material_override = material

func attach_trailer(unit: Node3D) -> void:
	trailer = unit
	trailer_root = _instantiate(TRAILER_GLB)
	if trailer_root == null:
		return
	var chassis := _find(trailer_root, "Chassis")
	var tray := _find(trailer_root, "Tray_Pivot")
	_hide_primitive_art(trailer)
	for child in trailer.get_children():
		if child.name == "TrailerWheelVisual":
			_hide_primitive_art(child)
	_bind(chassis, trailer)
	var tray_body: Node3D = trailer.get("tray")
	if tray_body != null:
		_hide_primitive_art(tray_body)
		tray_art = _bind(tray, tray_body)
	else:
		tray_art = _bind(tray, trailer, Vector3(0.0, 0.725, 0.84))

# Bucket tooth tip in the bucket body's own frame: the real cutting edge the
# soil solver should use, rather than a radial point on the pivot circle.
func bucket_tip_local() -> Vector3:
	if bucket_tip == null or excavator == null:
		return Vector3.ZERO
	return excavator.bucket.to_local(bucket_tip.global_position)

func advance_tracks(left_speed: float, right_speed: float, delta: float) -> void:
	track_phase[0] = fposmod(track_phase[0] + left_speed * delta, TRACK_LOOP)
	track_phase[1] = fposmod(track_phase[1] + right_speed * delta, TRACK_LOOP)
	_update_track_transforms()

func _physics_process(delta: float) -> void:
	_aim_cylinders()
	if excavator == null or track_multimeshes.is_empty():
		return
	if cab != null:
		cab.commands = excavator.cab_commands
	# Shoe travel comes from the measured body point velocity, including the
	# differential yaw term, so the tracks reverse and pivot with real motion.
	var under: RigidBody3D = excavator.undercarriage
	var forward: Vector3 = -under.global_basis.z.normalized()
	for index in range(2):
		var side := -1.0 if index == 0 else 1.0
		var arm: Vector3 = under.global_basis * Vector3(side * TRACK_GAUGE_HALF, 0.23, 0)
		var velocity: Vector3 = under.linear_velocity + under.angular_velocity.cross(arm)
		track_phase[index] = fposmod(track_phase[index] + velocity.dot(forward) * delta, TRACK_LOOP)
	_update_track_transforms()

func report() -> String:
	return "RIGGED_ART parts=%d missing=%d shoes=%d cylinders=%d" % [
		bound_parts, missing_parts.size(), SHOES_PER_SIDE * 2, cylinders.size()]
