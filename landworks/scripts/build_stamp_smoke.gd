# The build stamp: is the game able to tell you which build it is?
#
# This exists because the answer was twice "no". A version number on its own
# would not have helped — the question was whether an OLD copy was running,
# and a stale hand-written number is exactly what an old copy carries. So the
# checks below are about the live reading: the commit must come out of the
# repository beside the game, a planted stamp must not be able to override it,
# and the label must actually be on screen rather than merely constructed.
extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
const INFO = preload("res://landworks/scripts/build_info.gd")
var failures: Array[String] = []

func check(value: bool, reason: String) -> void:
	if not value: failures.append(reason)

func _initialize() -> void:
	call_deferred("_run")

func _is_hex(text: String) -> bool:
	if text.is_empty():
		return false
	for index in range(text.length()):
		if not ("0123456789abcdef".contains(text.substr(index, 1))):
			return false
	return true

func _run() -> void:
	# 1. The two places the version is written must agree. A number copied into
	#    a second file is a number that drifts.
	var declared: String = str(ProjectSettings.get_setting(
		"application/config/version", ""))
	print("VERSION script=", INFO.VERSION, " project=", declared)
	check(INFO.VERSION != "", "BuildInfo carries no version")
	check(declared == INFO.VERSION,
		"project.godot says version %s, BuildInfo says %s" % [
			declared, INFO.VERSION])

	# 2. Run from a checkout, the commit must be read out of the repository —
	#    a real short SHA, not a placeholder.
	var git_present: bool = FileAccess.file_exists(
		ProjectSettings.globalize_path("res://").path_join(".git/HEAD"))
	var id: String = INFO.commit()
	var when: String = INFO.commit_date()
	print("STAMP commit=", id, " date=", when, " source=", INFO.source(),
		" git_present=", git_present)
	if git_present:
		check(INFO.source() == "repository",
			"A checkout read its build from %s, not the repository" % INFO.source())
		check(id.length() == 7 and _is_hex(id),
			"The commit did not read back as a short SHA: '%s'" % id)
		check(when.length() == 10 and when.begins_with("20"),
			"The build date did not read back as an ISO date: '%s'" % when)

	# 3. A stamp file must not be able to speak over a live repository. This is
	#    the failure mode that matters: a packaged stamp left behind in a
	#    checkout would otherwise report a build that is not the one running.
	if git_present:
		var planted := FileAccess.open(INFO.STAMP_PATH, FileAccess.WRITE)
		check(planted != null, "Could not write a stamp file to test with")
		if planted != null:
			planted.store_string("commit=0000000\ndate=1999-01-01\n")
			planted.close()
			check(INFO.commit() == id,
				"A planted stamp overrode the live repository: %s" % INFO.commit())
			check(INFO.source() == "repository",
				"A planted stamp changed the reported source to %s" % INFO.source())
			# ... but it must still PARSE, because an exported build has
			# nothing else to go on.
			check(INFO._stamp_field("commit") == "0000000",
				"The stamp file's commit field did not parse back")
			check(INFO._stamp_field("date") == "1999-01-01",
				"The stamp file's date field did not parse back")
			DirAccess.remove_absolute(
				ProjectSettings.globalize_path(INFO.STAMP_PATH))
			check(not FileAccess.file_exists(INFO.STAMP_PATH),
				"Test left its planted stamp file behind")

	# 4. describe() is what the player reads, so it must name the version and
	#    the commit and must not claim an unknown build in a checkout.
	var text: String = INFO.describe()
	print("DESCRIBE ", text)
	check(text.contains(INFO.VERSION), "The build line omits the version")
	if git_present:
		check(text.contains(id), "The build line omits the commit")
		check(not text.contains("unknown"),
			"A checkout described itself as an unknown build")

	# 5. The label must be in the running game's HUD, visible, on screen, and
	#    saying the same thing. Constructing a label is not showing one.
	var world = WORLD.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var label: Label = null
	if world != null and "build_label" in world:
		label = world.build_label
	check(label != null, "The HUD has no build label")
	if label != null:
		var rect: Rect2 = label.get_global_rect()
		var screen: Vector2 = world.get_viewport().get_visible_rect().size
		print("LABEL text='", label.text, "' rect=", rect, " viewport=", screen,
			" visible=", label.is_visible_in_tree())
		check(label.is_visible_in_tree(), "The build label is not visible")
		check(label.text == text, "The build label and the build line disagree")
		check(rect.position.x >= 0.0 and rect.position.y >= 0.0
			and rect.end.x <= screen.x + 1.0 and rect.end.y <= screen.y + 1.0,
			"The build label sits outside the window: %s in %s" % [rect, screen])
		# It is in the corner the player was promised, not buried behind the
		# telemetry panel on the left.
		check(rect.position.x > screen.x * 0.5,
			"The build label is not in the right-hand half of the screen")

	for failure in failures: push_error(failure)
	print("BUILD_STAMP ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
