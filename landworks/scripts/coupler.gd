# Forgiving automatic coupling, used by the tow hitch and the lifting strap.
#
# Capture is deliberately generous about WHERE the two points are and strict
# about WHAT the machine is doing: the points must fall inside the capture
# radius and be nearly at rest relative to each other. That lets you reverse
# a tractor onto a drawbar without lining it up to the millimetre, while still
# refusing to snatch something you are driving past.
#
# A released pair is disarmed until it has moved clear of the radius again, so
# a machine can always drive away from what it just dropped. The coupling is a
# real Jolt pin constraint: a heavy load may still refuse to lift or follow.
extends Node3D

signal coupled(partner: RigidBody3D)
signal released(partner: RigidBody3D)

var capture_radius := 0.55
var capture_speed := 1.8
# Where the pin lands between the two points: 0 puts it on the machine's own
# anchor (a strap hangs the load from the hook), 0.5 splits the difference so
# neither body is yanked the whole way (a drawbar meeting a ball).
var engage_mix := 0.0
# A pair must separate past radius * this before it can capture again.
var clear_factor := 1.7
var draw_strap := false
var strap_colour := Color("#2b2f33")

var joint: PinJoint3D
var partner: RigidBody3D
var carrier: RigidBody3D
var armed := true
var attach_count := 0
var release_count := 0
var last_gap := INF
var strap: MeshInstance3D
var anchor_point := Vector3.ZERO
var partner_point := Vector3.ZERO

func is_coupled() -> bool:
	return is_instance_valid(joint) and is_instance_valid(partner)

# `targets` is an array of {"body": RigidBody3D, "point": Vector3 (world)}.
# Call every physics tick with the carrier's own anchor point in world space.
func update_capture(anchor: Vector3, machine: RigidBody3D, targets: Array) -> void:
	anchor_point = anchor
	carrier = machine
	if is_coupled():
		partner_point = partner.to_global(partner.get_meta("coupler_point", Vector3.ZERO))
		_update_strap()
		return
	var best: Dictionary = {}
	var best_gap := INF
	for candidate in targets:
		var body: RigidBody3D = candidate["body"]
		if not is_instance_valid(body) or body == machine:
			continue
		var gap: float = anchor.distance_to(Vector3(candidate["point"]))
		if gap < best_gap:
			best_gap = gap
			best = candidate
	last_gap = best_gap
	_update_strap()
	if best.is_empty():
		armed = true
		return
	if not armed:
		# Stay disarmed until this pair has genuinely moved apart.
		if best_gap > capture_radius * clear_factor:
			armed = true
		return
	if best_gap > capture_radius:
		return
	var body: RigidBody3D = best["body"]
	var relative: float = (machine.linear_velocity - body.linear_velocity).length()
	if relative > capture_speed:
		return
	_engage(machine, body, Vector3(best["point"]), Vector3(best.get("local", Vector3.ZERO)))

func _engage(machine: RigidBody3D, body: RigidBody3D, at: Vector3, local: Vector3) -> void:
	joint = PinJoint3D.new()
	joint.name = name + "_pin"
	add_child(joint)
	joint.global_position = anchor_point.lerp(at, engage_mix)
	joint.node_a = joint.get_path_to(machine)
	joint.node_b = joint.get_path_to(body)
	joint.exclude_nodes_from_collision = true
	partner = body
	partner.set_meta("coupler_point", local)
	partner_point = at
	attach_count += 1
	armed = false
	coupled.emit(body)

# Releases on command. Returns the partner's name, or "" if nothing was held.
func release() -> String:
	if not is_coupled():
		return ""
	var was := partner
	joint.queue_free()
	joint = null
	partner = null
	release_count += 1
	armed = false
	_update_strap()
	released.emit(was)
	return was.name

# True when a capture would happen right now if the pair were armed: used for
# the on-screen prompt, so the hint matches the rule rather than guessing.
func in_zone() -> bool:
	return last_gap <= capture_radius

func _update_strap() -> void:
	if not draw_strap:
		return
	if strap == null:
		strap = MeshInstance3D.new()
		strap.name = "LiftingStrap"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.07, 1.0, 0.025)
		strap.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = strap_colour
		material.roughness = 0.95
		strap.material_override = material
		add_child(strap)
	strap.visible = is_coupled()
	if not strap.visible:
		return
	var span := partner_point - anchor_point
	var length := span.length()
	if length < 0.02:
		strap.visible = false
		return
	var up := span / length
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	strap.global_transform = Transform3D(
		Basis(side, up, side.cross(up).normalized()).scaled(Vector3(1.0, length, 1.0)),
		anchor_point + span * 0.5)
