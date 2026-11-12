# The rigged KX080-3 and tipping trailer, checked against the live solver.
# Every angle below is read back from a Jolt hinge or from the bodies' own
# transforms; nothing here sets a transform or asserts on a baked animation.
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
	var e = world.digger
	var art = world.rig_visuals
	check(art.bound_parts >= 9,"Rigged art did not bind every limb")
	check(art.missing_parts.is_empty(),"Rigged model is missing parts: "+str(art.missing_parts))
	# The limb lengths the solver uses must be the model's own pin spacing.
	check(absf(float(e.BOOM_LENGTH)-3.6)<0.001,"Boom length is not the modelled pin spacing")
	check(absf(float(e.STICK_LENGTH)-1.75)<0.001,"Arm length is not the modelled pin spacing")
	check(e.BUCKET_TIP.distance_to(Vector3(0,-0.5,-0.8))<0.001,"Bucket tip is not the modelled tooth")
	# The soil solver must sample the same steel the model draws.
	var tip_local: Vector3 = art.bucket_tip_local()
	check(tip_local.distance_to(e.BUCKET_TIP)<0.02,
		"Model tooth socket and solver cutting edge disagree: "+str(tip_local))
	check(is_instance_valid(e.king_post),"King post is not a real body")
	check(is_instance_valid(e.dozer_blade),"Dozer blade is not a real body")
	check(e.hinges.has("offset") and e.hinges.has("blade"),"New mechanisms have no powered pins")
	check(is_instance_valid(world.trailer.tray),"Tipping tray is not a real body")
	# Drive the three new services and read the solved angles back.
	var blade_start: float = e._joint_angle("blade")
	var offset_start: float = e._joint_angle("offset")
	# Raise the blade: downward travel is correctly stopped by ground contact
	# a few degrees below level, so lifting is what exercises the motor.
	e.target_angles["blade"] = 0.28
	e.target_angles["offset"] = 0.75
	world.trailer.tip_target = 0.70
	for _n in range(600):
		await physics_frame
	var blade_now: float = e._joint_angle("blade")
	var offset_now: float = e._joint_angle("offset")
	var tip_now: float = world.trailer.tip_angle_rad()
	print("MECHANISMS blade=",blade_now," offset=",offset_now," tray_tip=",tip_now)
	check(blade_now > blade_start+0.15,"Dozer blade did not lift under its own motor")
	check(blade_now <= 0.33,"Dozer blade passed its upper stop")
	check(offset_now > offset_start+0.15,"Boom offset did not swing on the king post")
	check(tip_now > 0.30,"Tipping tray did not lift on its ram")
	check(tip_now <= 0.80,"Tipping tray passed its 45 degree stop")
	# The blade pushes spoil instead of carrying it: cut, release, conserve.
	var earth = world.earth
	var before: float = earth.mass_error_kg()
	var pad: Vector3 = earth.global_position
	var from := Vector3(pad.x-1.0,earth.surface_height(pad)-0.12,pad.z)
	var to := Vector3(pad.x+0.25,earth.surface_height(pad)-0.12,pad.z)
	var pushed: Dictionary = earth.blade_push(from,to,2.20,90000.0,90000.0,
		to+Vector3(0.55,0,0),Vector3.RIGHT)
	var moved := float(pushed["volume_m3"])
	print("BLADE_PUSH volume_m3=",moved," blade_store_m3=",earth.blade_inventory.volume(),
		" mass_error_kg=",earth.mass_error_kg())
	check(moved > 0.0005,"Blade below grade removed nothing from the bank")
	check(earth.blade_inventory.volume() < 0.05,"Blade is carrying spoil instead of pushing it")
	check(earth.mass_error_kg() < maxf(before,0.0)+1.0,"Blade push did not conserve mass")
	# The tray catches what is dumped into it and tips it back out over the
	# tailgate. Nothing is teleported: spoil is cut, released as parcels,
	# caught on the way down and released again at the rear sill.
	check(world.trailer_bin >= 0,"Trailer tray is not registered as a container")
	world.trailer.tip_target = 0.0
	for _n in range(360):
		await physics_frame
	var load_from := Vector3(pad.x-0.6,earth.surface_height(pad)-0.10,pad.z+1.0)
	var load_to := Vector3(pad.x+0.3,earth.surface_height(pad)-0.10,pad.z+1.0)
	earth.commit_cut(earth.propose_cut(load_from,load_to,0.65,0.24),90000.0,90000.0)
	var carried: float = earth.bucket_inventory.volume()
	check(carried > 0.001,"Could not load the bucket for the tray test")
	earth.release_soil(world.trailer.tray.to_global(Vector3(0,1.0,-1.0)),
		Vector3.DOWN,carried)
	for _n in range(300):
		await physics_frame
	var in_tray: float = earth.container_volume_m3(world.trailer_bin)
	print("TRAY_LOAD carried_m3=",carried," caught_m3=",in_tray)
	check(in_tray > 0.001,"Tray did not catch spoil dumped into it")
	world.trailer.tip_target = 0.70
	for _n in range(480):
		await physics_frame
	print("TRAY_DISCHARGE out_m3=",world.tray_discharged_m3,
		" left_m3=",earth.container_volume_m3(world.trailer_bin),
		" mass_error_kg=",earth.mass_error_kg())
	check(world.tray_discharged_m3 > 0.001,"Tipped tray did not discharge its load")
	check(earth.container_volume_m3(world.trailer_bin) < in_tray,"Tray did not empty")
	check(earth.mass_error_kg() < 1.0,"Tray transfer did not conserve mass")
	for failure in failures: push_error(failure)
	print("RIGGED_MODEL ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
