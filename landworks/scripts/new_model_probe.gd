# Development probe: prints the imported node tree and key pivot transforms of
# the new KX080-3 and tipping-trailer GLBs. Reports measurements only; it never
# writes assets. Run: godot --headless --path . --script res://landworks/scripts/new_model_probe.gd
extends SceneTree

const MACHINE := "res://landworks/assets/engineered/kx080_3_machine.glb"
const TRAILER := "res://landworks/assets/engineered/farm_tipping_trailer.glb"

func _walk(node: Node, depth: int, skip: String) -> void:
	if skip != "" and node.name.begins_with(skip):
		return
	var line := "  ".repeat(depth) + node.name + " [" + node.get_class() + "]"
	if node is Node3D:
		var t: Transform3D = node.transform
		line += " pos=" + str(t.origin.snapped(Vector3(0.001, 0.001, 0.001)))
	print(line)
	for child in node.get_children():
		_walk(child, depth + 1, skip)

func _report(path: String, skip: String) -> Node:
	var packed := load(path) as PackedScene
	if packed == null:
		print("PROBE_FAIL could not load ", path)
		return null
	var root := packed.instantiate()
	print("--- ", path, " ---")
	_walk(root, 0, skip)
	return root

func _init() -> void:
	var machine := _report(MACHINE, "Track_")
	if machine != null:
		for name in ["Upper_Swing", "Boom_Swing_Bracket", "Boom", "Arm", "Bucket",
				"Bucket_Tip", "Dozer_Blade", "Undercarriage"]:
			var found := machine.find_child(name, true, false)
			print("MACHINE_NODE ", name, " -> ",
				"MISSING" if found == null else str((found as Node3D).position))
	var trailer := _report(TRAILER, "Latch_")
	if trailer != null:
		for name in ["Chassis", "Tray_Pivot", "Tray_Body", "Drawbar_RingHitch",
				"Axle_Springs", "Wheel_L", "Wheel_R", "Tailgate"]:
			var found := trailer.find_child(name, true, false)
			print("TRAILER_NODE ", name, " -> ",
				"MISSING" if found == null else str((found as Node3D).position))
	# Free both instances so the probe exits without leaking resources.
	if machine != null:
		machine.free()
	if trailer != null:
		trailer.free()
	print("PROBE_DONE")
	quit()
