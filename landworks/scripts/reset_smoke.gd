# Global reset. Disturbs every machine, load and coupling, resets, and checks
# that the sandbox really is back at its start condition without the restore
# creating or destroying soil, and without the jump home being read as a cut.
extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
var failures: Array[String] = []

func check(value: bool, reason: String) -> void:
	if not value: failures.append(reason)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world = WORLD.instantiate()
	root.add_child(world)
	await process_frame
	var digger = world.digger
	var earth = world.earth
	check(world.start_state.size() >= 9,
		"Reset snapshot covers only %d bodies" % world.start_state.size())
	# Let the scene settle first: the snapshot folds in the crate's drop and
	# the tray taking up on its hinge, so read it after that has happened.
	for _n in range(240):
		await physics_frame
	check(world.start_settled, "Start snapshot never folded in the settling")
	var snapshot: Dictionary = {}
	for body in world.start_state:
		snapshot[body] = Transform3D(world.start_state[body])

	# Disturb everything a player could disturb.
	world.hitch_coupler.release()
	digger.target_angles["boom"] = 0.9
	digger.target_angles["stick"] = -1.8
	digger.target_angles["bucket"] = 1.2
	digger.target_angles["blade"] = 0.25
	digger.target_angles["offset"] = 0.6
	digger.slew_target_rad = 1.1
	world.trailer.tip_target = 0.6
	for item in world.props:
		if is_instance_valid(item):
			item.global_position += Vector3(2.5, 0.0, 2.5)
			item.linear_velocity = Vector3.ZERO
	for _n in range(420):
		await physics_frame
	# Put soil in the bucket and in the tray so the restore has to deal with
	# carried material rather than an empty machine.
	var pad: Vector3 = earth.global_position
	var from := Vector3(pad.x - 0.6, earth.surface_height(pad) - 0.10, pad.z)
	var to := Vector3(pad.x + 0.3, earth.surface_height(pad) - 0.10, pad.z)
	earth.commit_cut(earth.propose_cut(from, to, 0.65, 0.24), 90000.0, 90000.0)
	var carried: float = earth.bucket_inventory.volume()
	check(carried > 0.0005, "Could not load the bucket before resetting")
	var moved := false
	for body in snapshot:
		if is_instance_valid(body) and body.global_position.distance_to(
				Vector3(snapshot[body].origin)) > 0.05:
			moved = true
	check(moved, "Nothing actually moved, so the reset proves nothing")
	check(not world.hitch_coupler.is_coupled(), "Hitch did not stay released")

	var dug_before: float = world.maximum_excavated_m3
	var extracted_before: float = earth.extracted_total_m3
	var mass_before: float = earth.mass_error_kg()
	var status: String = world.reset_machines()
	print("RESET status=", status, " count=", world.reset_count)

	# The restore itself must be exact, measured before any physics runs.
	var worst := 0.0
	for body in snapshot:
		if not is_instance_valid(body):
			continue
		worst = maxf(worst, body.global_position.distance_to(Vector3(snapshot[body].origin)))
	print("RESET_PLACEMENT worst_offset_m=", worst, " bodies=", snapshot.size())
	check(worst < 0.001, "A machine or load was not placed back at its start position")
	await physics_frame
	check(world.hitch_coupler.is_coupled(), "Reset did not re-couple the trailer")
	check(not digger.strap.is_coupled(), "Reset left the lifting strap attached")
	check(absf(float(world.trailer.tip_target)) < 0.001, "Reset left the tray commanded up")
	check(earth.bucket_inventory.volume() < 0.0005, "Reset left soil in the bucket")
	# The restore must not invent or destroy material, and the ground it dug
	# must still be dug: a reset is not an undo.
	print("RESET_SOIL mass_error_kg=", earth.mass_error_kg(),
		" released_m3=", carried, " dug_m3=", world.maximum_excavated_m3)
	check(earth.mass_error_kg() < maxf(mass_before, 0.0) + 1.0,
		"Reset did not conserve soil mass")
	check(earth.extracted_total_m3 >= extracted_before - 0.000001,
		"Reset rolled back the excavation record instead of leaving the ground as dug")
	# The jump home must never be read as a cut on the following ticks.
	for _n in range(240):
		await physics_frame
	var dug_after: float = world.maximum_excavated_m3
	print("RESET_AFTER dug_m3=", dug_after, " delta_m3=", dug_after - dug_before,
		" mass_error_kg=", earth.mass_error_kg())
	check(dug_after - dug_before < 0.002,
		"The reset teleport was committed as an excavation of %.4f m3" % (dug_after - dug_before))
	check(earth.mass_error_kg() < 1.0, "Soil mass drifted after the reset")
	# Settled, the machines must still be home rather than drifting off.
	# Machines must still be exactly where they were put. Loose loads may
	# settle, because some of them spawn clear of the ground and drop at
	# startup: reproducing that drop is the start condition, not a drift.
	var machines: Array = [world.tractor, world.trailer, world.trailer.tray,
		digger.undercarriage, digger.upper, digger.king_post, digger.boom,
		digger.stick, digger.bucket, digger.dozer_blade]
	var worst_machine := 0.0
	var worst_load := 0.0
	var drifter := ""
	for body in snapshot:
		if not is_instance_valid(body):
			continue
		var offset: float = body.global_position.distance_to(Vector3(snapshot[body].origin))
		if body in machines:
			if offset > worst_machine:
				worst_machine = offset
				drifter = str(body.name)
		else:
			worst_load = maxf(worst_load, offset)
	print("RESET_SETTLED machine_offset_m=", worst_machine, " body=", drifter,
		" load_settle_m=", worst_load)
	check(worst_machine < 0.12, "A machine drifted away after the reset: " + drifter)
	check(worst_load < 1.0, "A loose load did not stay near its start position")
	for failure in failures: push_error(failure)
	print("RESET ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
