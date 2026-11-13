# Regressions for what playing the excavator turned up: a camera that held a
# fixed world bearing instead of following the machine, levers that worked the
# wrong service for the selected international pattern, and arm and bucket
# ranges that did not exist because the joint stops were set in a different
# frame from the commands, so driving to them only stretched the pins.
extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
var failures: Array[String] = []

func check(value: bool, reason: String) -> void:
	if not value: failures.append(reason)

func _initialize() -> void:
	call_deferred("_run")

func _settle(ticks: int) -> void:
	for _n in range(ticks):
		await physics_frame

func _run() -> void:
	var world = WORLD.instantiate()
	root.add_child(world)
	await process_frame
	var digger = world.digger
	world._select_machine(1)
	await _settle(180)

	# 1. Every service's stop must land where its command band says it does.
	# Jolt measures a hinge limit from the pose the bodies were built in, while
	# the commands are in _joint_angle terms; the two differ by the limb's build
	# angle. Unshifted, the arm's rest pose WAS its stop, so pulling it out
	# stretched the pin instead of moving it, and the bottom of the boom's
	# lever and the top of the bucket's curl asked for angles with no stop
	# behind them.
	for id in ["boom", "stick", "bucket"]:
		var band: Vector2 = digger.joint_limits(id)
		var joint: HingeJoint3D = digger.hinges[id]["joint"]
		var build: float = float(digger.hinges[id]["build_angle"])
		var stop_lo: float = joint.get_param(HingeJoint3D.PARAM_LIMIT_LOWER) + build
		var stop_hi: float = joint.get_param(HingeJoint3D.PARAM_LIMIT_UPPER) + build
		print("STOPS %-7s band %+.3f..%+.3f  backstop %+.3f..%+.3f  build %+.3f" % [
			id, band.x, band.y, stop_lo, stop_hi, build])
		# The backstop is symmetric, because this engine's hinge cannot hold an
		# asymmetric limit, so it only has to be no narrower than the band it
		# is backing. If it bites inside the band, the service loses travel the
		# lever still offers and the motor grinds against it.
		check(stop_lo <= band.x + 0.01 and stop_hi >= band.y - 0.01,
			"%s backstop %+.3f..%+.3f bites inside its band %+.3f..%+.3f" % [
				id, stop_lo, stop_hi, band.x, band.y])
		# A lever must not be able to ask for an angle outside that band.
		digger.target_angles[id] = band.y + 1.0
		digger._advance_target(id, 0.0)
		check(float(digger.target_angles[id]) <= band.y + 0.001,
			"%s target was allowed past its stop" % id)
		digger.target_angles[id] = clampf(build, band.x, band.y)
	await _settle(120)

	# 2. Sweeping a service across its whole band must not pull its pin apart.
	# Measured between the same material point in each body, which is what
	# shows on screen as the arm coming away from the boom.
	var anchors := {}
	for id in ["boom", "stick", "bucket"]:
		var joint: HingeJoint3D = digger.hinges[id]["joint"]
		var a: RigidBody3D = digger.hinges[id]["a"]
		var b: RigidBody3D = digger.hinges[id]["b"]
		anchors[id] = [a, b, a.to_local(joint.global_position),
			b.to_local(joint.global_position)]
	# Two cases. Working the mechanism in clear air is what "the arm breaks
	# when used" was about, and it is held strictly. Sweeping the boom down as
	# well drives the arm into ground it cannot shift, which genuinely loads
	# the pins, so that one is allowed more — but it still has to stay well
	# clear of the 100 mm it showed before the stops were put in the right
	# frame, and of the 183 mm it reached while the solver was under-stepped.
	digger.target_angles["boom"] = 0.85
	await _settle(300)
	var air: Dictionary = await _sweep(digger, anchors, ["stick", "bucket"])
	print("PIN_SWEEP_AIR worst_gap_m=", String.num(air["gap"], 4), " at ", air["name"])
	# Measured 34 mm. It has been 204 with the solver under-stepped, 104 with
	# the bucket band asking for curl the cylinder could not reach, and 66
	# before the sideways track grip stopped dragging the whole chain about.
	# The limit catches a return to any of those, with margin over what is
	# measured now.
	check(float(air["gap"]) < 0.060,
		"Working the arm in clear air pulls the %s pin %.0f mm apart" % [
			air["name"], float(air["gap"]) * 1000.0])
	var loaded: Dictionary = await _sweep(digger, anchors, ["boom", "stick", "bucket"])
	print("PIN_SWEEP_GROUND worst_gap_m=", String.num(loaded["gap"], 4),
		" at ", loaded["name"])
	check(float(loaded["gap"]) < 0.090,
		"Driving the arm into the ground pulls the %s pin %.0f mm apart" % [
			loaded["name"], float(loaded["gap"]) * 1000.0])

	# 3. With the arm held clear of the ground the bucket must have a usable
	# curl, not the 54 degrees it managed when its stop was misplaced.
	digger.target_angles["boom"] = 0.85
	digger.target_angles["stick"] = -1.20
	await _settle(360)
	var curl: Vector2 = digger.joint_limits("bucket")
	var lo := 99.0
	var hi := -99.0
	for step in range(7):
		digger.target_angles["bucket"] = curl.x + (curl.y - curl.x) * float(step) / 6.0
		await _settle(90)
		lo = minf(lo, digger._joint_angle("bucket"))
		hi = maxf(hi, digger._joint_angle("bucket"))
	print("BUCKET_CURL reached ", String.num(lo, 3), "..", String.num(hi, 3),
		" = ", String.num(rad_to_deg(hi - lo), 1), " deg")
	# Measured 91 degrees here. The band is geometrically 180, and how much of
	# it the cylinder can hold depends on pose and load, so this gate is set to
	# catch the misplaced stop that left only 54 rather than to pin the figure.
	check(rad_to_deg(hi - lo) > 75.0,
		"The bucket only curls %.0f degrees in free air" % rad_to_deg(hi - lo))

	# 4. The camera must follow the machine round rather than hold a world
	# bearing, measured as the angle from the machine's forward to the camera.
	var lower: RigidBody3D = digger.undercarriage
	var before := _bearing(lower, world.camera)
	var yaw_before: float = lower.global_rotation.y
	var spun := 0
	# Allow longer than it used to need: the tracks grip properly now and the
	# slew is ramped, so a neutral turn takes real time rather than snapping.
	while spun < 3600 and absf(angle_difference(lower.global_rotation.y, yaw_before)) < 0.8:
		digger._drive_tracks(-0.7, 0.7)
		await physics_frame
		spun += 1
	var turned: float = absf(angle_difference(lower.global_rotation.y, yaw_before))
	await _settle(180)
	var after := _bearing(lower, world.camera)
	var drift: float = absf(angle_difference(after, before))
	print("CAMERA turned_rad=", String.num(turned, 3), " bearing_drift_rad=",
		String.num(drift, 3))
	check(turned > 0.4, "Test fault: the undercarriage did not turn far enough")
	check(drift < 0.35,
		"The camera holds a world bearing: the view moved %.2f rad while the machine turned %.2f"
			% [drift, turned])

	# 5. Which lever works which service, per the selected pattern. Driven
	# through the scene's own input handling rather than read off the source.
	for sae in [false, true]:
		digger.sae_pattern = sae
		var left: String = await _service_for(digger, KEY_W)
		var right: String = await _service_for(digger, KEY_KP_8)
		print("PATTERN ", "SAE" if sae else "ISO", " left=", left, " right=", right)
		if sae:
			check(left == "boom", "SAE left lever worked %s, not the boom" % left)
			check(right == "stick", "SAE right lever worked %s, not the arm" % right)
		else:
			check(left == "stick", "ISO left lever worked %s, not the arm" % left)
			check(right == "boom", "ISO right lever worked %s, not the boom" % right)

	# 5b. The bucket must curl further than it dumps, and curl to a bucket that
	# is actually shut. Curl is the negative direction, measured at the pin as
	# the angle between the tooth and the arm closing. The band was mirrored,
	# giving 125 degrees of dump against 55 of curl, and the curl side bottomed
	# out at 83 degrees of closure — a bucket that never shuts.
	var curl_band: Vector2 = digger.joint_limits("bucket")
	var bucket_rest: float = float(digger.hinges["bucket"]["build_angle"])
	check(bucket_rest - curl_band.x > curl_band.y - bucket_rest,
		"The bucket dumps further than it curls: %.0f deg curl against %.0f dump" % [
			rad_to_deg(bucket_rest - curl_band.x),
			rad_to_deg(curl_band.y - bucket_rest)])
	digger.target_angles["boom"] = 0.85
	digger.target_angles["stick"] = -1.20
	digger.target_angles["bucket"] = curl_band.x
	await _settle(420)
	var shut: float = _closure_deg(digger)
	digger.target_angles["bucket"] = curl_band.y
	await _settle(420)
	var open: float = _closure_deg(digger)
	digger.target_angles["bucket"] = bucket_rest
	await _settle(420)
	var resting: float = _closure_deg(digger)
	print("BUCKET_CLOSURE rest ", String.num(resting, 1), " curled ",
		String.num(shut, 1), " dumped ", String.num(open, 1), " deg")
	# Measured in what the bucket actually reaches, not just what the band
	# offers: from rest it must close further than it opens. Reversed, it had
	# 125 degrees of dump against 55 of curl.
	check(resting - shut > open - resting,
		"The bucket opens %.0f degrees from rest but only closes %.0f" % [
			open - resting, resting - shut])
	check(shut < 70.0, "Fully curled the bucket is still %.0f degrees open" % shut)
	digger.target_angles["bucket"] = bucket_rest
	await _settle(180)

	# 5c. The machine must have mass. A tractor leaning on it at 3400 N used to
	# push 8.8 tonnes nearly a metre in five seconds, because the sideways
	# track resistance was purely viscous and so resisted speed, not a shove.
	digger.target_angles["boom"] = 0.24
	await _settle(300)
	var stood: Vector3 = digger.undercarriage.global_position
	for _n in range(600):
		digger.undercarriage.apply_central_force(
			digger.undercarriage.global_transform.basis.x * 3400.0)
		await physics_frame
	var shoved: float = stood.distance_to(digger.undercarriage.global_position)
	print("STEADY_PUSH moved_m=", String.num(shoved, 3))
	check(shoved < 0.25,
		"A steady 3400 N shoved the machine %.2f m in five seconds" % shoved)
	# ...and must still be able to drive itself out of its own tracks.
	await _settle(120)
	var parked: Vector3 = digger.undercarriage.global_position
	digger.scripted_test = true
	digger.access_test = true
	await _settle(600)
	var drove: float = parked.distance_to(digger.undercarriage.global_position)
	print("STILL_DRIVES travelled_m=", String.num(drove, 3))
	check(drove > 1.0,
		"Gripping the tracks left the machine unable to drive: %.2f m in five seconds" % drove)
	digger.scripted_test = false
	digger.access_test = false
	await _settle(120)

	# 6. The trailer must roll on the modelled wheels, not the procedural ones.
	# Both were present: the hide pass only looked one level down, so the old
	# tyres kept drawing, and the modelled wheels sat rigid inside the chassis.
	var art = world.rig_visuals
	check(art.wheel_art.size() == 2,
		"Expected two modelled trailer wheels bound, got %d" % art.wheel_art.size())
	var still_showing := 0
	for index in range(world.trailer.wheel_visuals.size()):
		var hub: Node3D = world.trailer.wheel_visuals[index]
		var modelled: Node3D = art.wheel_art[index] if index < art.wheel_art.size() else null
		for mesh in _meshes_under(hub):
			# Anything still drawing on the hub that did not come from the model.
			if modelled != null and (mesh == modelled or modelled.is_ancestor_of(mesh)):
				continue
			if mesh.visible:
				still_showing += 1
	print("TRAILER_WHEELS bound=", art.wheel_art.size(),
		" procedural_meshes_still_visible=", still_showing)
	check(still_showing == 0,
		"%d procedural tyre meshes are still drawing under the modelled wheels"
			% still_showing)
	for index in range(art.wheel_art.size()):
		var wheel: Node3D = art.wheel_art[index]
		var spinner: Node3D = world.trailer.wheel_visuals[index]
		check(spinner.is_ancestor_of(wheel),
			"Modelled wheel %d is not on the root the trailer rolls" % index)
		var offset: float = wheel.global_position.distance_to(spinner.global_position)
		check(offset < 0.05,
			"Modelled wheel %d sits %.3f m off its hub" % [index, offset])
	# Rolling the trailer must turn them.
	var turned_before: float = world.trailer.wheel_visuals[0].rotation.x
	world.trailer.apply_central_impulse(
		-world.trailer.global_transform.basis.z * 2600.0)
	await _settle(150)
	var rolled: float = absf(angle_difference(
		world.trailer.wheel_visuals[0].rotation.x, turned_before))
	print("TRAILER_WHEELS rolled_rad=", String.num(rolled, 3))
	check(rolled > 0.08, "The trailer wheels do not turn when it rolls")

	for failure in failures: push_error(failure)
	print("MACHINE_CONTROLS ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

# Sweeps each named service across its whole band, watching every pin the
# while, and reports the worst separation seen and where.
func _sweep(digger, anchors: Dictionary, ids: Array) -> Dictionary:
	var worst := 0.0
	var worst_name := ""
	for id in ids:
		var band: Vector2 = digger.joint_limits(id)
		for step in range(7):
			digger.target_angles[id] = band.x + (band.y - band.x) * float(step) / 6.0
			await _settle(60)
			for pid in anchors:
				var s: Array = anchors[pid]
				var gap: float = (s[0] as Node3D).to_global(s[2]).distance_to(
					(s[1] as Node3D).to_global(s[3]))
				if gap > worst:
					worst = gap
					worst_name = str(pid)
		digger.target_angles[id] = clampf(float(digger.hinges[id]["build_angle"]),
			band.x, band.y)
		await _settle(60)
	return {"gap": worst, "name": worst_name}

# How far shut the bucket is: the angle at its pin between the tooth and the
# arm. Curling closes the bucket, so this falls.
func _closure_deg(digger) -> float:
	var pin: Vector3 = digger.bucket.global_position
	var tooth: Vector3 = digger.bucket.to_global(digger.BUCKET_TIP)
	return rad_to_deg((tooth - pin).normalized().angle_to(
		(digger.stick.global_position - pin).normalized()))

func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_meshes_under(child))
	return found

func _bearing(body: Node3D, camera: Camera3D) -> float:
	var forward: Vector3 = -body.global_transform.basis.z
	var out: Vector3 = camera.global_position - body.global_position
	var a := Vector2(out.x, out.z)
	var b := Vector2(forward.x, forward.z)
	return atan2(a.cross(b), a.dot(b))

# Holds one key and reports which service target it moved.
func _service_for(digger, key: int) -> String:
	digger.operated = true
	var before := {}
	for id in ["boom", "stick", "bucket"]:
		before[id] = float(digger.target_angles[id])
	var press := InputEventKey.new()
	press.keycode = key
	press.physical_keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	await _settle(30)
	var release := InputEventKey.new()
	release.keycode = key
	release.physical_keycode = key
	release.pressed = false
	Input.parse_input_event(release)
	await physics_frame
	var best := "none"
	var best_move := 0.02
	for id in ["boom", "stick", "bucket"]:
		var moved: float = absf(float(digger.target_angles[id]) - float(before[id]))
		if moved > best_move:
			best_move = moved
			best = id
	return best
