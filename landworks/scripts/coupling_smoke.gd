# Tow hitch and lifting strap: coupling, release, forgiveness and refusal.
#
# Bodies are STAGED by placement, the way the hook fixture already stages a
# load, but every coupling and release below is a real Jolt constraint made
# and broken by the game's own rule. Nothing asserts on a scripted attachment.
extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
var failures: Array[String] = []

func check(value: bool, reason: String) -> void:
	if not value: failures.append(reason)

# Puts the trailer's ring at `offset` from the tow ball.
func _stage_trailer(world, offset: Vector3) -> void:
	var ball: Vector3 = world.tractor.to_global(world.TRACTOR_HITCH_LOCAL)
	world.trailer.global_position = ball + offset - (
		world.trailer.global_transform.basis * world.trailer.HITCH_POINT)
	world.trailer.linear_velocity = Vector3.ZERO
	world.trailer.angular_velocity = Vector3.ZERO

func _run() -> void:
	var world = WORLD.instantiate()
	root.add_child(world)
	await process_frame
	var hitch = world.hitch_coupler
	check(hitch.is_coupled(),"Trailer did not start coupled")
	check(world.hitch != null,"Coupled hitch exposes no joint")

	# Drop it, and confirm it will not grab itself straight back while the
	# ring is still sitting on the ball.
	hitch.release()
	await process_frame
	check(not hitch.is_coupled(),"Hitch did not release on command")
	check(world.hitch == null,"Released hitch still exposes a joint")
	world._update_hitch()
	check(not hitch.is_coupled(),"Hitch re-captured without separating first")

	# Drive clear, then reverse back on with a deliberate 0.30 m miss.
	_stage_trailer(world,Vector3(0,0,2.5))
	world._update_hitch()
	check(not hitch.is_coupled(),"Hitch captured from 2.5 m away")
	_stage_trailer(world,Vector3(0.30,0.0,0.0))
	world._update_hitch()
	check(hitch.is_coupled(),"Hitch did not forgive a 0.30 m miss")
	print("HITCH forgiving_capture_gap_m=",hitch.last_gap,
		" radius_m=",hitch.capture_radius)

	# It must still refuse a trailer it is driving past.
	hitch.release()
	_stage_trailer(world,Vector3(0,0,2.5))
	world._update_hitch()
	_stage_trailer(world,Vector3(0.20,0,0))
	world.trailer.linear_velocity = Vector3(0,0,6.0)
	world._update_hitch()
	check(not hitch.is_coupled(),"Hitch snatched a trailer moving past at 6 m/s")
	world.trailer.linear_velocity = Vector3.ZERO
	world._update_hitch()
	check(hitch.is_coupled(),"Hitch refused a trailer that had come to rest")

	# Left parked, it must stand on its jockey foot rather than nose over.
	hitch.release()
	_stage_trailer(world,Vector3(0,0,2.5))
	# Staging places the trailer by its drawbar ring, which puts the body
	# 0.70 m BELOW the tractor's own origin — well under the ground. Parked
	# from there it was not standing on its jockey foot at all, it was settling
	# out of the terrain onto its nose, and reported the same 66 degrees every
	# run. Drop it in from clear air instead, which is what parking it means.
	world.trailer.global_position.y += 1.20
	world.trailer.linear_velocity = Vector3.ZERO
	world.trailer.angular_velocity = Vector3.ZERO
	world._update_hitch()
	for _n in range(360):
		await physics_frame
	var tilt := rad_to_deg(acos(clampf(
		world.trailer.global_transform.basis.y.dot(Vector3.UP),-1.0,1.0)))
	print("PARKED tilt_deg=",tilt," jockey_contact=",world.trailer.jockey_contact,
		" hitched=",world.trailer.hitched)
	check(not world.trailer.hitched,"Parked trailer still reports itself hitched")
	check(world.trailer.jockey_contact,"Jockey foot found no ground to stand on")
	check(tilt < 8.0,"Parked trailer nosed over without its jockey stand")

	# Lifting strap on the excavator.
	var digger = world.digger
	var strap = digger.strap
	check(strap != null,"Excavator has no lifting strap")
	if strap.is_coupled():
		strap.release()
	check(world.props.size() > 0,"Sandbox staged no loose loads")
	var block: RigidBody3D = world.props[0]
	block.global_position = digger.hook_point()
	block.linear_velocity = Vector3.ZERO
	digger.update_strap(world.props)
	check(strap.is_coupled(),"Strap did not take hold of a load at the tooth")
	check(digger.load_hook_joint != null,"Strap joint is not visible to callers")
	check(digger.attached_load == block,"Strap reports the wrong load")
	var message: String = digger.toggle_hook(world.props)
	check(not strap.is_coupled(),"Button press did not release the strap: "+message)
	check(digger.load_hook_joint == null,"Released strap still exposes a joint")
	block.global_position = digger.hook_point()
	block.linear_velocity = Vector3.ZERO
	digger.update_strap(world.props)
	check(not strap.is_coupled(),"Strap grabbed again without the load clearing")
	# Move the load clear and bring it back: it must take hold again.
	block.global_position = digger.hook_point() + Vector3(0,0,3.0)
	digger.update_strap(world.props)
	block.global_position = digger.hook_point()
	block.linear_velocity = Vector3.ZERO
	digger.update_strap(world.props)
	check(strap.is_coupled(),"Strap did not re-arm after the load cleared")
	print("STRAP attach_count=",strap.attach_count," release_count=",strap.release_count,
		" radius_m=",strap.capture_radius)
	for failure in failures: push_error(failure)
	print("COUPLING ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("_run")
