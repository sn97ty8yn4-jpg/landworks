# Exercise the imported model parts on the REAL powered rig. The tractor still
# wears the segmented engineered art; the excavator wears the rigged KX080-3,
# whose cylinders are aimed at their own pins every tick. Nothing below reads
# a baked animation: track travel comes from measured chassis motion and the
# cylinder checks are taken from the live transforms.
extends SceneTree

const SCENE = preload("res://landworks/scenes/sandbox_world.tscn")

func _initialize() -> void:
	root.add_child.call_deferred(SCENE.instantiate())
	call_deferred("_exercise")

func _exercise() -> void:
	await process_frame
	var sandbox: Node3D = root.get_child(root.get_child_count()-1)
	var art: Node3D = sandbox.machine_visuals
	var rig: Node3D = sandbox.rig_visuals
	var digger: Node3D = sandbox.digger
	var errors: Array[String] = []
	# Tractor: body plus one part per wheel, each centred on its spin origin.
	if art.custom_parts_loaded != 5:
		errors.append("Expected five attached tractor parts, got %d" % art.custom_parts_loaded)
	for wheel in sandbox.tractor.wheel_data:
		var mount: Node3D = wheel["visual"]
		var part: Node3D = mount.get_child(mount.get_child_count()-1)
		if part.position.length() > 0.00001 or part.scale.distance_to(Vector3.ONE) > 0.00001:
			errors.append("Imported wheel is not centred at its actual spin origin")
	# Excavator: the rigged model's own running gear and hydraulics.
	if rig.track_multimeshes.size() != 2:
		errors.append("Missing circulating track belts")
	if rig.cylinders.size() != 5:
		errors.append("Expected five aimed cylinders, got %d" % rig.cylinders.size())
	var before: float = rig.track_phase[0]
	digger.scripted_test = true
	digger.access_test = true
	for _n in range(220):
		await physics_frame
	digger.scripted_test = false
	digger.access_test = false
	var track_motion: float = absf(rig.track_phase[0]-before)
	if track_motion < 0.1:
		errors.append("Track shoes did not follow measured chassis movement")
	# Work the arm through real poses and confirm every cylinder stays on its
	# own pins and keeps pointing at its partner, at every angle.
	var worst_pin := 0.0
	var worst_aim := 0.0
	for target in [Vector3(-0.35,-0.95,-0.90),Vector3(0.72,-0.12,0.62),Vector3(0.24,-0.72,-0.24)]:
		digger.target_angles["boom"] = target.x
		digger.target_angles["stick"] = target.y
		digger.target_angles["bucket"] = target.z
		for _n in range(340):
			await physics_frame
		for cylinder in rig.cylinders:
			var barrel: Node3D = cylinder["barrel"]
			var rod: Node3D = cylinder["rod"]
			var barrel_pin: Node3D = cylinder["barrel_pin"]
			var rod_pin: Node3D = cylinder["rod_pin"]
			worst_pin = maxf(worst_pin, barrel.global_position.distance_to(barrel_pin.global_position))
			worst_pin = maxf(worst_pin, rod.global_position.distance_to(rod_pin.global_position))
			var span: Vector3 = rod_pin.global_position-barrel_pin.global_position
			if span.length() > 0.01:
				worst_aim = maxf(worst_aim,
					absf(barrel.global_basis.x.normalized().dot(span.normalized())-1.0))
	if worst_pin > 0.005:
		errors.append("A cylinder drifted off its pin")
	if worst_aim > 0.0005:
		errors.append("A cylinder stopped pointing at its partner pin")
	rig.update_bucket_fill(0.12,"clay")
	if not rig.bucket_fill.visible:
		errors.append("Captured soil not visible inside the bucket")
	rig.update_bucket_fill(0.0,"clay")
	if rig.bucket_fill.visible:
		errors.append("Empty bucket still displays captured soil")
	print("MACHINE_VISUAL_TEST tractor_parts=",art.custom_parts_loaded,
		" rigged_parts=",rig.bound_parts,
		" track_motion_m=",track_motion,
		" worst_pin_drift_m=",worst_pin," worst_aim_error=",worst_aim)
	for error in errors:
		push_error(error)
	print("MACHINE_VISUAL ","PASS" if errors.is_empty() else "FAIL")
	quit(0 if errors.is_empty() else 1)
