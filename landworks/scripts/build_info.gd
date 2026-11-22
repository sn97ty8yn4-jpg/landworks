# Which build is this? Shown on screen, in the window title and in the log.
#
# Asked twice whether the game was opening an older copy, there was no way to
# tell from inside the game. A hand-written version number would not have
# answered it either, because it only changes when somebody remembers to
# change it. So the commit this build came from is read LIVE out of the
# repository whenever the game runs from source — which is how it is played
# here — and only an exported copy, with no repository beside it, falls back
# to the stamp file written when it was packaged.
# Deliberately NOT a global class_name: a brand-new class_name is not in the
# script class cache when the engine is started with --script, so every
# headless check would fail to parse its callers. Callers preload it.
extends RefCounted

# Bumped by hand for a release. project.godot carries the same string and
# build_stamp_smoke holds the two together, because a version number copied
# into two files drifts.
const VERSION := "0.9.0"
const STAMP_PATH := "res://landworks/build_stamp.txt"

# The short commit, e.g. "9b33c42", or "" if neither the repository nor a
# stamp can be read. Never invented: an unknown build says so.
static func commit() -> String:
	var live := _commit_from_repository()
	if live != "":
		return live
	return _stamp_field("commit")

# ISO date, e.g. "2026-11-23". For a source build this is when the checked-out
# commit last moved, which is what "how old is what I am running" means.
static func commit_date() -> String:
	var ref := _head_ref_path()
	if ref != "" and FileAccess.file_exists(ref):
		return _local_date(FileAccess.get_modified_time(ref))
	var git_head := _git_dir().path_join("HEAD")
	if FileAccess.file_exists(git_head):
		return _local_date(FileAccess.get_modified_time(git_head))
	return _stamp_field("date")

# In the operator's own day, not UTC. Godot reads a timestamp back as UTC, so
# east of Greenwich a build made this morning printed yesterday's date —
# which is precisely the doubt this whole line exists to remove.
static func _local_date(unix_time: int) -> String:
	var zone: Dictionary = Time.get_time_zone_from_system()
	return Time.get_date_string_from_unix_time(
		unix_time + int(zone.get("bias", 0)) * 60)

# "repository" when read from the checkout beside the game, "stamp" when read
# from a packaged copy, "unknown" when neither was there.
static func source() -> String:
	if _commit_from_repository() != "":
		return "repository"
	if _stamp_field("commit") != "":
		return "stamp"
	return "unknown"

# One line for the corner of the screen and the title bar.
static func describe() -> String:
	var text := "Landworks v" + VERSION
	var id := commit()
	text += "  •  build " + (id if id != "" else "unknown")
	var when := commit_date()
	if when != "":
		text += "  •  " + when
	return text

static func _git_dir() -> String:
	var beside := ProjectSettings.globalize_path("res://").path_join(".git")
	# In a LINKED WORKTREE — and in a submodule — .git is a file holding
	# "gitdir: <the real git directory>" rather than being that directory.
	# Without this the game reports an unknown build from any worktree, which
	# is where a second copy of the game tends to be run from.
	if FileAccess.file_exists(beside):
		var pointer := _read_text(beside)
		if pointer.begins_with("gitdir:"):
			var pointed := pointer.substr(7).strip_edges()
			if pointed.is_relative_path():
				pointed = ProjectSettings.globalize_path("res://").path_join(pointed)
			return pointed.simplify_path()
	return beside

static func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()

# The file holding the commit the checkout is on, or "" if there is no
# repository. A detached HEAD holds the commit itself and has no ref file.
static func _head_ref_path() -> String:
	var head := _read_text(_git_dir().path_join("HEAD"))
	if head == "" or not head.begins_with("ref:"):
		return ""
	return _git_dir().path_join(head.substr(4).strip_edges())

static func _commit_from_repository() -> String:
	var head := _read_text(_git_dir().path_join("HEAD"))
	if head == "":
		return ""
	if not head.begins_with("ref:"):
		# Detached: HEAD is the commit.
		return head.substr(0, 7)
	var ref_name := head.substr(4).strip_edges()
	var loose := _read_text(_head_ref_path())
	if loose != "":
		return loose.substr(0, 7)
	# A branch whose ref has been packed away: one line per ref, "<sha> <name>".
	for line in _read_text(_git_dir().path_join("packed-refs")).split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 2 and parts[1] == ref_name:
			return str(parts[0]).substr(0, 7)
	return ""

static func _stamp_field(field: String) -> String:
	for line in _read_text(STAMP_PATH).split("\n"):
		var pair := line.strip_edges().split("=", false, 1)
		if pair.size() == 2 and str(pair[0]).strip_edges() == field:
			return str(pair[1]).strip_edges()
	return ""
