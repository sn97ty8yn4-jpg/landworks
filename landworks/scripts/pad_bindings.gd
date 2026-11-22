# What each control on the gamepad does, and where it is bound.
#
# The defaults are the PowerA Advantage wired pad for Switch 2: two Hall-effect
# sticks, D-pad, ABXY, L/R and ZL/ZR, two rear paddles, minus and plus. It has
# no rumble and no motion sensing, so neither is used.
#
# Windows does not always report a Switch pad's buttons where an Xbox pad's
# would be, so every binding here can be replaced at runtime by the setup
# screen and is then remembered in user://pad_bindings.cfg. Nothing in the game
# reads a raw joypad index; it all comes through here.
extends RefCounted

const SAVE_PATH := "user://pad_bindings.cfg"
# Hall-effect sticks do not wander, so this can be tighter than the 0.12 the
# keyboard-era helper used, which makes slow, precise work possible.
const DEADZONE := 0.06

# An axis binding reads a stick; `dir` says which way counts as positive for
# the service. A button binding reads one button. A pair binding makes an axis
# out of two buttons, which is how the tracks run.
enum { BIND_AXIS, BIND_BUTTON, BIND_PAIR }

# Order matters: the setup screen walks this list.
const ACTIONS := [
	{"id": "arm", "label": "Arm: push the stick AWAY to send it out", "kind": BIND_AXIS},
	{"id": "swing", "label": "Swing: push the stick RIGHT to slew right", "kind": BIND_AXIS},
	{"id": "boom", "label": "Boom: pull the stick BACK to raise", "kind": BIND_AXIS},
	{"id": "bucket", "label": "Bucket: push the stick LEFT to curl", "kind": BIND_AXIS},
	{"id": "track_left_fwd", "label": "Left track forward", "kind": BIND_BUTTON},
	{"id": "track_left_rev", "label": "Left track reverse", "kind": BIND_BUTTON},
	{"id": "track_right_fwd", "label": "Right track forward", "kind": BIND_BUTTON},
	{"id": "track_right_rev", "label": "Right track reverse", "kind": BIND_BUTTON},
	{"id": "blade_up", "label": "Dozer blade up", "kind": BIND_BUTTON},
	{"id": "blade_down", "label": "Dozer blade down", "kind": BIND_BUTTON},
	{"id": "offset_left", "label": "Boom offset left", "kind": BIND_BUTTON},
	{"id": "offset_right", "label": "Boom offset right", "kind": BIND_BUTTON},
	{"id": "couple", "label": "Strap on the excavator, hitch on the tractor", "kind": BIND_BUTTON},
	{"id": "swap_machine", "label": "Change machine", "kind": BIND_BUTTON},
	{"id": "reset_machines", "label": "Reset the machines to their start", "kind": BIND_BUTTON},
]

# The pad as it is meant to be held. Tracks are four buttons rather than an
# axis pair because that is how they were asked for: L and R drive each track
# forward, ZL and ZR reverse the same track.
static func defaults() -> Dictionary:
	return {
		"arm": {"type": BIND_AXIS, "axis": JOY_AXIS_LEFT_Y, "dir": -1.0},
		"swing": {"type": BIND_AXIS, "axis": JOY_AXIS_LEFT_X, "dir": 1.0},
		# Pulling a stick back reads positive on Y in Godot, and pulling back
		# raises the boom on a real machine, so this one is not inverted.
		"boom": {"type": BIND_AXIS, "axis": JOY_AXIS_RIGHT_Y, "dir": 1.0},
		"bucket": {"type": BIND_AXIS, "axis": JOY_AXIS_RIGHT_X, "dir": -1.0},
		"track_left_fwd": {"type": BIND_BUTTON, "button": JOY_BUTTON_LEFT_SHOULDER},
		# ZL and ZR come through as trigger AXES rather than buttons, even on a
		# pad whose triggers only click. Read as axes and treated as pressed
		# past half travel, which works either way.
		"track_left_rev": {"type": BIND_AXIS, "axis": JOY_AXIS_TRIGGER_LEFT, "dir": 1.0},
		"track_right_fwd": {"type": BIND_BUTTON, "button": JOY_BUTTON_RIGHT_SHOULDER},
		"track_right_rev": {"type": BIND_AXIS, "axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1.0},
		"blade_up": {"type": BIND_BUTTON, "button": JOY_BUTTON_DPAD_UP},
		"blade_down": {"type": BIND_BUTTON, "button": JOY_BUTTON_DPAD_DOWN},
		"offset_left": {"type": BIND_BUTTON, "button": JOY_BUTTON_DPAD_LEFT},
		"offset_right": {"type": BIND_BUTTON, "button": JOY_BUTTON_DPAD_RIGHT},
		# A on the Nintendo face layout. Godot names buttons by position, so
		# the right-hand button is JOY_BUTTON_B; the setup screen exists for
		# exactly this kind of disagreement.
		"couple": {"type": BIND_BUTTON, "button": JOY_BUTTON_B},
		"swap_machine": {"type": BIND_BUTTON, "button": JOY_BUTTON_START},
		"reset_machines": {"type": BIND_BUTTON, "button": JOY_BUTTON_BACK},
	}

var bindings: Dictionary = defaults()
var saved := false

func _init() -> void:
	load_saved()

static func pad_id() -> int:
	var found := Input.get_connected_joypads()
	return int(found[0]) if found.size() > 0 else -1

static func connected() -> bool:
	return pad_id() >= 0

# -1..1 for an axis action, 0 or 1 for a button action.
func value(id: String) -> float:
	var pad := pad_id()
	if pad < 0 or not bindings.has(id):
		return 0.0
	var bind: Dictionary = bindings[id]
	match int(bind.get("type", BIND_BUTTON)):
		BIND_AXIS:
			var raw := Input.get_joy_axis(pad, int(bind["axis"]))
			if absf(raw) < DEADZONE:
				return 0.0
			# Rescale past the deadzone so the first movement off centre is
			# not a step, which is what makes fine work possible.
			var scaled := (absf(raw) - DEADZONE) / (1.0 - DEADZONE)
			return clampf(scaled, 0.0, 1.0) * signf(raw) * float(bind.get("dir", 1.0))
		BIND_PAIR:
			return float(Input.is_joy_button_pressed(pad, int(bind["plus"]))) \
				- float(Input.is_joy_button_pressed(pad, int(bind["minus"])))
		_:
			return float(Input.is_joy_button_pressed(pad, int(bind["button"])))

func pressed(id: String) -> bool:
	return value(id) > 0.5

func label_for(id: String) -> String:
	if not bindings.has(id):
		return "unbound"
	var bind: Dictionary = bindings[id]
	match int(bind.get("type", BIND_BUTTON)):
		BIND_AXIS:
			return "axis %d%s" % [int(bind["axis"]),
				"" if float(bind.get("dir", 1.0)) > 0.0 else " (inverted)"]
		BIND_PAIR:
			return "buttons %d/%d" % [int(bind["plus"]), int(bind["minus"])]
		_:
			return "button %d" % int(bind["button"])

func bind_button(id: String, button: int) -> void:
	bindings[id] = {"type": BIND_BUTTON, "button": button}

# Captured by pushing the stick the way the prompt asks, so the direction is
# recorded along with the axis and nothing has to be guessed or inverted later.
func bind_axis(id: String, axis: int, pushed_value: float) -> void:
	bindings[id] = {"type": BIND_AXIS, "axis": axis,
		"dir": 1.0 if pushed_value > 0.0 else -1.0}

func save() -> void:
	var file := ConfigFile.new()
	for id in bindings:
		file.set_value("pad", str(id), bindings[id])
	if file.save(SAVE_PATH) == OK:
		saved = true

func load_saved() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	for id in file.get_section_keys("pad"):
		var stored = file.get_value("pad", id)
		if stored is Dictionary and stored.has("type"):
			bindings[id] = stored
	saved = true

func forget() -> void:
	bindings = defaults()
	saved = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
