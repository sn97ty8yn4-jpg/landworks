# Walks through every pad control, asks for it, and remembers what was pressed.
#
# This exists because Windows does not reliably report a Switch pad's buttons
# where an Xbox pad's would be, so the shipped defaults may land on the wrong
# physical buttons. Rather than guess at a mapping, the game asks.
#
# F7 opens it. Each step names a control; press or push the one you want.
# Space keeps whatever is already bound and moves on, Escape closes and keeps
# everything set so far, and Backspace restores the shipped defaults.
extends CanvasLayer

const PAD = preload("res://landworks/scripts/pad_bindings.gd")

signal closed

var pad
var step := 0
var panel: ColorRect
var title: Label
var body: Label
# Axes have to settle back to centre before the next one is read, or one shove
# of a stick answers two questions at once.
var armed := false

func _init(bindings) -> void:
	pad = bindings
	layer = 80

func _ready() -> void:
	panel = ColorRect.new()
	panel.color = Color(0.05, 0.06, 0.07, 0.93)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	title = Label.new()
	title.position = Vector2(60, 70)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#f9ecd5"))
	panel.add_child(title)
	body = Label.new()
	body.position = Vector2(60, 130)
	body.add_theme_font_size_override("font_size", 18)
	body.add_theme_color_override("font_color", Color("#cfd6cc"))
	panel.add_child(body)
	_refresh()

func _refresh() -> void:
	if step >= PAD.ACTIONS.size():
		title.text = "Controller set up"
		body.text = "Every control is bound and saved.\n\nEnter or Escape to close."
		return
	var action: Dictionary = PAD.ACTIONS[step]
	var kind := "Push the stick" if int(action["kind"]) == PAD.BIND_AXIS else "Press the button"
	title.text = "%s  (%d of %d)" % [str(action["label"]), step + 1, PAD.ACTIONS.size()]
	var lines := [
		"%s you want for this." % kind,
		"",
		"Now bound to: %s" % pad.label_for(str(action["id"])),
		"",
		"Space: keep it and skip        Escape: close",
		"Backspace: restore the shipped defaults",
	]
	if not PAD.connected():
		lines.insert(0, "No controller is connected. Plug one in.")
		lines.insert(1, "")
	body.text = "\n".join(lines)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER:
				pad.save()
				closed.emit()
				queue_free()
			KEY_SPACE:
				step += 1
				armed = false
				_refresh()
			KEY_BACKSPACE:
				pad.forget()
				step = 0
				_refresh()
		return
	if step >= PAD.ACTIONS.size():
		return
	var action: Dictionary = PAD.ACTIONS[step]
	if int(action["kind"]) == PAD.BIND_AXIS:
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			# Ignore the D-pad and triggers, which some pads report as axes:
			# this step wants a stick.
			if absf(motion.axis_value) < 0.25:
				armed = true
				return
			if not armed:
				return
			pad.bind_axis(str(action["id"]), motion.axis, motion.axis_value)
			_advance()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		pad.bind_button(str(action["id"]), (event as InputEventJoypadButton).button_index)
		_advance()

func _advance() -> void:
	pad.save()
	step += 1
	armed = false
	_refresh()
