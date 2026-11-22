# Throwaway, for four things reported from play that my earlier measurements
# did not reproduce: the machine still being pushed by the tractor, it lifting
# itself too easily, the boom being unresponsive and unpredictable, and the
# bucket knuckle looking detached.
extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
var world
var digger

func _initialize() -> void:
	call_deferred("_run")

func _settle(ticks: int) -> void:
	for _n in range(ticks):
		await physics_frame

func _run() -> void:
	world = WORLD.instantiate()
	root.add_child(world)
	await process_frame
	digger = world.digger
	world._select_machine(1)
	await _settle(300)

	# 1. Pushed where it is actually hit. The earlier check shoved the
	# undercarriage; the tractor is far more likely to meet the house, the
	# counterweight or the boom, and those reach the ground only through the
	# slew bearing.
	for target in [["undercarriage", digger.undercarriage], ["upper/house", digger.upper],
			["boom", digger.boom]]:
		world.reset_machines()
		await _settle(420)
		var body: RigidBody3D = target[1]
		var start: Vector3 = digger.undercarriage.global_position
		var sideways: Vector3 = digger.undercarriage.global_transform.basis.x
		for _n in range(600):
			body.apply_central_force(sideways * 3400.0)
			await physics_frame
		print("PUSH on %-12s moved the machine %.3f m in 5 s" % [
			str(target[0]), start.distance_to(digger.undercarriage.global_position)])

	# 2. Does it lift itself? Drive the bucket hard into the ground and watch
	# the tracks: a machine this size should push the tooth in, not stand up.
	world.reset_machines()
	await _settle(420)
	var resting: float = digger.undercarriage.global_position.y
	var highest := resting
	digger.target_angles["boom"] = -1.047
	digger.target_angles["stick"] = -0.30
	for _n in range(600):
		await physics_frame
		highest = maxf(highest, digger.undercarriage.global_position.y)
	print("SELF_LIFT chassis rose %.3f m while pressing the bucket down" % (highest - resting))

	# 3. Boom lift: is it quick, and is it the same every time? Three runs
	# from the same place, timed to the same angle.
	for attempt in range(3):
		world.reset_machines()
		await _settle(420)
		var from: float = digger._joint_angle("boom")
		digger.target_angles["boom"] = 1.05
		var ticks := 0
		while ticks < 900 and digger._joint_angle("boom") < 0.95:
			await physics_frame
			ticks += 1
		print("BOOM_LIFT run %d: %+.3f -> 0.95 in %.2f s%s" % [attempt + 1, from,
			float(ticks) / float(Engine.physics_ticks_per_second),
			"" if ticks < 900 else "  (NEVER GOT THERE)"])

	# 4. The bucket knuckle: which modelled parts ended up bound, and is
	# anything in the linkage still sitting with the arm?
	var art = world.rig_visuals
	print("LINKAGE bound=", art.bound_parts, " missing=", art.missing_parts)
	for name in ["Bucket", "Arm", "Cyl_Bucket_Barrel", "Cyl_Bucket_Rod",
			"Pin_HLink_Q", "H_Link", "Knuckle", "Link_H", "Bucket_Link"]:
		var found := world.rig_visuals.machine_root.find_child(name, true, false) if \
			world.rig_visuals.machine_root != null else null
		if found == null:
			continue
		var owner_body := found
		while owner_body != null and not (owner_body is RigidBody3D):
			owner_body = owner_body.get_parent()
		print("   %-20s rides %s" % [name,
			str(owner_body.name) if owner_body != null else "NOTHING (still loose)"])
	quit(0)
