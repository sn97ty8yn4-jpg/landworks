# Regressions for four faults found by playing the machine: narrow-looking
# tracks, cylinders projecting the wrong way, a boom that bounced with no
# input, and controls that crawled. Every number here is measured from the
# live scene: instance transforms, mesh extents and solved joint angles.
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
	# 0. The lifting strap must not take hold of a load that is already
	# standing within reach when the scene opens. It did, and because such a
	# load rests on the ground the pin tied the bucket to the ground: the boom
	# then held perfectly still under full flow and full torque, which is what
	# the sandbox boom gate failed on.
	# Coming to a load and having it take hold is the wanted behaviour, so the
	# load must be in place before the first physics tick for this to mean
	# anything. It goes in here rather than relying on the scene's own props,
	# which sit 7.5 m away in this scene — which is why the boom checks below
	# never caught the fault.
	var squatter := RigidBody3D.new()
	squatter.name = "StrapSquatter_80kg"
	squatter.mass = 80.0
	squatter.freeze = true
	var squatter_shape := CollisionShape3D.new()
	var squatter_box := BoxShape3D.new()
	squatter_box.size = Vector3(0.3, 0.3, 0.3)
	squatter_shape.shape = squatter_box
	squatter.add_child(squatter_shape)
	world.add_child(squatter)
	squatter.global_position = world.digger.hook_point()
	world.props.append(squatter)
	await process_frame
	var digger = world.digger
	var art = world.rig_visuals
	for _n in range(180):
		await physics_frame
	print("STRAP_AT_REST coupled=", digger.strap.is_coupled(),
		" armed=", digger.strap.armed,
		" nearest_m=", String.num(digger.strap.last_gap, 3))
	check(digger.strap.last_gap <= digger.strap.capture_radius,
		"Test fault: the squatting load never entered the capture zone")
	check(not digger.strap.is_coupled(),
		"The strap hooked a load standing in the zone without being asked")
	world.props.erase(squatter)
	squatter.queue_free()
	for _n in range(10):
		await physics_frame

	# 1. Track shoes must lie square across the track, not edge-on. The plate's
	# 450 mm width is the mesh's longest axis; find it, then check where the
	# instance transform puts it. The track runs along Z, gauge along X.
	check(art.track_shoes.size() == 2, "Track belts missing")
	var belt: Array = art.track_shoes[0]
	var box: AABB = (belt[0] as MeshInstance3D).mesh.get_aabb()
	var sizes := [box.size.x, box.size.y, box.size.z]
	var widest: int = sizes.find(sizes.max())
	var plate_axis: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][widest]
	var plate_width: float = float(sizes[widest])
	var worst := 1.0
	var spread := 0.0
	for shoe in belt:
		var basis: Basis = (shoe as MeshInstance3D).transform.basis
		worst = minf(worst, absf((basis * plate_axis).normalized().x))
		spread = maxf(spread, absf((shoe as MeshInstance3D).position.z))
	print("TRACK plate_width_m=", plate_width, " across_track_min=", worst,
		" belt_half_length_m=", spread, " shoes=", belt.size())
	check(plate_width > 0.38, "Modelled shoe plate is only %.3f m wide" % plate_width)
	check(worst > 0.95, "Track shoe plates are not square across the track")

	# 2. Each barrel and rod must project toward the pin it reaches for, not
	# away from it. Compare the mesh centre's distance against the pin's own.
	check(art.cylinders.size() == 5, "Expected five aimed cylinders")
	var worst_cylinder := ""
	for cylinder in art.cylinders:
		for pair in [["barrel", "rod_pin"], ["rod", "barrel_pin"]]:
			var part: Node3D = cylinder[pair[0]]
			var target: Node3D = cylinder[pair[1]]
			if not (part is MeshInstance3D) or (part as MeshInstance3D).mesh == null:
				continue
			var centre: Vector3 = part.to_global(
				(part as MeshInstance3D).mesh.get_aabb().get_center())
			var pin_gap: float = part.global_position.distance_to(target.global_position)
			if centre.distance_to(target.global_position) >= pin_gap:
				worst_cylinder = str(part.name)
	print("CYLINDERS wrong_way=", "none" if worst_cylinder == "" else worst_cylinder)
	check(worst_cylinder == "", "Cylinder projects away from its pin: " + worst_cylinder)

	# 3. The boom must hold still with no operator input.
	for _n in range(360):
		await physics_frame
	var held: float = digger._joint_angle("boom")
	var lo := held
	var hi := held
	var previous := held
	var direction := 0
	var reversals := 0
	for _n in range(600):
		await physics_frame
		var angle: float = digger._joint_angle("boom")
		lo = minf(lo, angle)
		hi = maxf(hi, angle)
		var step := angle - previous
		# Only count reversals in motion fast enough to see: 0.0012 rad a tick
		# is 0.14 rad/s. Below that is solver jitter, not a bouncing boom.
		if absf(step) > 0.0012:
			var way: int = 1 if step > 0.0 else -1
			if direction != 0 and way != direction:
				reversals += 1
			direction = way
		previous = angle
	var drift: float = previous - held
	print("BOOM_HOLD peak_to_peak_rad=", hi - lo, " deg=", rad_to_deg(hi - lo),
		" drift_rad=", drift, " reversals=", reversals)
	# A bounce is an oscillation: the angle keeps changing direction. A slow
	# one-way settle is not what was reported and is not a fault.
	check(reversals < 12,
		"Boom oscillates with no input: %d direction reversals" % reversals)
	check(absf(drift) < 0.05, "Boom drifts %.4f rad while holding" % drift)

	# 4. A commanded extreme must be reached promptly.
	var start_angle: float = digger._joint_angle("boom")
	digger.target_angles["boom"] = 1.05
	var ticks := 0
	while ticks < 900 and digger._joint_angle("boom") < 1.00:
		await physics_frame
		ticks += 1
	var seconds := float(ticks) / float(Engine.physics_ticks_per_second)
	print("BOOM_RESPONSE from_rad=", start_angle, " reached_in_s=", seconds,
		" ticks=", ticks)
	check(ticks < 900, "Boom never reached full lift")
	check(seconds < 3.0, "Boom took %.2f s to reach full lift" % seconds)
	# 5. The coupled hitch must rest with the ring ON the ball. Pinning the
	# constraint midway between them left a standing offset that pulled the
	# tractor backwards for as long as it was hitched.
	check(world.hitch_coupler.is_coupled(), "Trailer is not coupled")
	var ball: Vector3 = world.tractor.to_global(world.TRACTOR_HITCH_LOCAL)
	var ring: Vector3 = world.trailer.to_global(world.trailer.HITCH_POINT)
	print("HITCH_REST gap_m=", ball.distance_to(ring))
	check(ball.distance_to(ring) < 0.08,
		"Hitched drawbar rests %.3f m off the ball" % ball.distance_to(ring))

	# 6. Tipping must raise the FRONT of the tray. Measured in world height at
	# the tray's front end, not from the internal angle, because a sign error
	# in that angle is exactly what let a dipping tray pass before.
	var tray: RigidBody3D = world.trailer.tray
	var front_local := Vector3(0.0, 0.10, -world.trailer.TRAY_SIZE.z + 0.15)
	var before_y: float = tray.to_global(front_local).y
	world.trailer.tip_target = 0.60
	for _n in range(540):
		await physics_frame
	var after_y: float = tray.to_global(front_local).y
	print("TIPPER front_rise_m=", after_y - before_y,
		" reported_angle_rad=", world.trailer.tip_angle_rad())
	check(after_y - before_y > 0.25, "Tipping drops the tray front instead of lifting it")
	check(world.trailer.tip_angle_rad() > 0.25,
		"Tip angle does not read positive while the front is up")

	# 6. A block dropped into the tray must stay in it: a solid slab of a tray
	# cannot be loaded at all, which is why nothing would go in.
	world.trailer.tip_target = 0.0
	for _n in range(300):
		await physics_frame
	# A load sized for a 1.25 m tray. The sandbox's own props are 1.14 m
	# across, which will not sit in a farm tipper however open it is.
	var block := RigidBody3D.new()
	block.name = "TrayLoadProbe_120kg"
	block.mass = 120.0
	var probe_shape := CollisionShape3D.new()
	var probe_box := BoxShape3D.new()
	probe_box.size = Vector3(0.45, 0.45, 0.45)
	probe_shape.shape = probe_box
	block.add_child(probe_shape)
	world.add_child(block)
	block.global_position = tray.to_global(Vector3(0.0, 0.55, -1.09))
	block.linear_velocity = Vector3.ZERO
	block.angular_velocity = Vector3.ZERO
	for _n in range(360):
		await physics_frame
	var inside: Vector3 = tray.to_local(block.global_position)
	print("TRAY_BLOCK local=", inside.snapped(Vector3(0.01, 0.01, 0.01)))
	check(absf(inside.x) < 0.75 and inside.y > -0.10 and inside.y < 1.20
			and inside.z < 0.2 and inside.z > -2.4,
		"A block dropped into the tray did not stay in it")
	# 7. Starting disarmed must not cost the operator the strap. With a load
	# actually at the hook, the strap key has to take hold, and release it.
	var hook_load := RigidBody3D.new()
	hook_load.name = "StrapProbe_60kg"
	hook_load.mass = 60.0
	hook_load.freeze = true
	var hook_shape := CollisionShape3D.new()
	var hook_box := BoxShape3D.new()
	hook_box.size = Vector3(0.3, 0.3, 0.3)
	hook_shape.shape = hook_box
	hook_load.add_child(hook_shape)
	world.add_child(hook_load)
	hook_load.global_position = digger.hook_point()
	var loads: Array[RigidBody3D] = []
	loads.append(hook_load)
	await physics_frame
	var took_hold: String = digger.toggle_hook(loads)
	print("STRAP_ON_DEMAND ", took_hold, " coupled=", digger.strap.is_coupled())
	check(digger.strap.is_coupled(),
		"The strap key would not hook a load sitting on the hook: " + took_hold)
	var let_go: String = digger.toggle_hook(loads)
	check(not digger.strap.is_coupled(),
		"The strap key would not release the load it was holding: " + let_go)

	for failure in failures: push_error(failure)
	print("MACHINE_FEEL ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
