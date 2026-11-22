# The gamepad mapping, checked without a gamepad.
#
# Every pad control is read through the bindings object, so the bindings can be
# driven directly here and the machine asked what it did. That tests the thing
# that actually matters — which service each control works, and which way —
# without needing a pad plugged into the build machine or into CI.
extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
const PAD = preload("res://landworks/scripts/pad_bindings.gd")
var failures: Array[String] = []

func check(value: bool, reason: String) -> void:
	if not value: failures.append(reason)

func _initialize() -> void:
	call_deferred("_run")

func _settle(ticks: int) -> void:
	for _n in range(ticks):
		await physics_frame

# Stands in for the pad: every reading is whatever the test puts here, so the
# machine cannot tell the difference between this and a real controller.
class FakePad:
	extends RefCounted
	var held := {}
	func value(action: String) -> float:
		return float(held.get(action, 0.0))
	func pressed(action: String) -> bool:
		return value(action) > 0.5

func _run() -> void:
	var world = WORLD.instantiate()
	root.add_child(world)
	await process_frame
	var digger = world.digger
	world._select_machine(1)
	await _settle(240)

	# 1. The shipped defaults must cover every control the setup screen walks,
	# or a fresh install would have something silently unbound.
	var shipped: Dictionary = PAD.defaults()
	for action in PAD.ACTIONS:
		check(shipped.has(str(action["id"])),
			"No default binding for %s" % str(action["id"]))
	print("PAD_DEFAULTS actions=", PAD.ACTIONS.size(), " bound=", shipped.size())

	# 2. Each stick must work the service it was asked to, the way it was
	# asked to. Held one at a time, so a crossed binding cannot hide.
	var fake := FakePad.new()
	digger.pad_bindings = fake
	digger.operated = true
	var moves := {}
	for probe in [["arm", "stick"], ["boom", "boom"], ["bucket", "bucket"]]:
		var action: String = probe[0]
		var service: String = probe[1]
		var before := {}
		for id in ["boom", "stick", "bucket"]:
			before[id] = float(digger.target_angles[id])
		fake.held = {action: 1.0}
		await _settle(60)
		fake.held = {}
		var worked := ""
		var amount := 0.0
		for id in ["boom", "stick", "bucket"]:
			var moved: float = float(digger.target_angles[id]) - float(before[id])
			if absf(moved) > absf(amount):
				amount = moved
				worked = id
		moves[action] = amount
		print("PAD_STICK %-7s worked %-7s by %+.3f" % [action, worked, amount])
		check(worked == service,
			"Pushing %s worked the %s, not the %s" % [action, worked, service])

	# Direction, in the terms they were asked for: pulling the boom stick back
	# raises, pushing the arm stick away sends it out, pushing the bucket
	# stick left curls. The bindings carry the sign, so a positive reading
	# must mean the wanted direction for every one of them.
	check(float(moves["boom"]) > 0.0, "A positive boom reading lowered the boom")
	check(float(moves["arm"]) > 0.0, "A positive arm reading crowded the arm in")
	check(float(moves["bucket"]) < 0.0, "A positive bucket reading dumped instead of curling")

	# 3. The four track controls must drive one track each, and reverse the
	# same track. Measured as the tracks the machine ends up commanding.
	for probe in [["track_left_fwd", 1.0, 0.0], ["track_right_fwd", 0.0, 1.0],
			["track_left_rev", -1.0, 0.0], ["track_right_rev", 0.0, -1.0]]:
		fake.held = {str(probe[0]): 1.0}
		await _settle(30)
		var left: float = digger.cab_commands.get("left_track", 0.0)
		var right: float = digger.cab_commands.get("right_track", 0.0)
		fake.held = {}
		await _settle(20)
		print("PAD_TRACK %-16s left %+.2f right %+.2f" % [str(probe[0]), left, right])
		check(signf(left) == signf(float(probe[1])) or absf(float(probe[1])) < 0.01,
			"%s did not drive the left track the right way" % str(probe[0]))
		check(signf(right) == signf(float(probe[2])) or absf(float(probe[2])) < 0.01,
			"%s did not drive the right track the right way" % str(probe[0]))

	# 4. The D-pad works the blade and the offset on the excavator.
	for probe in [["blade_up", "blade"], ["offset_left", "offset"]]:
		var service: String = probe[1]
		var before: float = float(digger.target_angles.get(service, 0.0))
		fake.held = {str(probe[0]): 1.0}
		await _settle(60)
		fake.held = {}
		var moved: float = float(digger.target_angles.get(service, 0.0)) - before
		print("PAD_AUX %-12s moved %s by %+.3f" % [str(probe[0]), service, moved])
		check(absf(moved) > 0.001, "%s did not work the %s" % [str(probe[0]), service])

	# 5. Swing must go the way it is pushed. A positive yaw about +Y swings the
	# house to the operator's LEFT, so every control that works it was slewing
	# the wrong way until this was measured in world terms rather than read
	# off the sign of the command.
	digger.slew_target_rad = 0.0
	await _settle(120)
	var yaw_before: float = digger._relative_slew_rad()
	fake.held = {"swing": 1.0}
	await _settle(180)
	fake.held = {}
	var swung: float = digger._relative_slew_rad() - yaw_before
	# The operator faces -Z with +X to their right, so swinging right is a
	# NEGATIVE yaw about +Y.
	print("PAD_SWING pushed right, yaw moved ", String.num(swung, 4),
		" (", "right" if swung < 0.0 else "left", ")")
	check(swung < -0.01, "Pushing the swing stick right slewed the house left")

	# 6. The tractor must actually drive from the pad. Its throttle used to
	# come only from the analog triggers, which this pad does not have, so the
	# wheels turned but it went nowhere.
	digger.pad_bindings = null
	world._select_machine(0)
	world.tractor.pad_bindings = fake
	await _settle(120)
	for probe in [["forward", 1.0], ["back", -1.0]]:
		var from: Vector3 = world.tractor.global_position
		var facing: Vector3 = -world.tractor.global_transform.basis.z
		fake.held = {"arm": float(probe[1])}
		await _settle(240)
		fake.held = {}
		var along: float = (world.tractor.global_position - from).dot(facing)
		await _settle(90)
		print("PAD_TRACTOR %-8s moved %+.3f m along its own forward" % [
			str(probe[0]), along])
		check(signf(along) == signf(float(probe[1])) and absf(along) > 0.15,
			"The tractor would not drive %s from the pad: %+.2f m" % [
				str(probe[0]), along])

	for failure in failures: push_error(failure)
	print("PAD_MAPPING ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
