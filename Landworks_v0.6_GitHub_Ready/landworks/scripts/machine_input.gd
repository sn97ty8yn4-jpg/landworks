# Controller abstraction: PlayStation controller through Godot joypad API + keyboard fallback.
extends RefCounted

static func joy_id() -> int:
    var found := Input.get_connected_joypads()
    return int(found[0]) if found.size() > 0 else -1

static func axis(id: int, which: int, deadzone: float = 0.12) -> float:
    if id < 0:
        return 0.0
    var v := Input.get_joy_axis(id, which)
    if absf(v) < deadzone:
        return 0.0
    return clampf(v, -1.0, 1.0)

static func trigger(id: int, which: int) -> float:
    if id < 0:
        return 0.0
    # Godot typically normalizes triggers to 0...1 on mapped controllers.
    return clampf(Input.get_joy_axis(id, which), 0.0, 1.0)

static func throttle() -> float:
    var id := joy_id()
    var key := float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
    return clampf(key + trigger(id, JOY_AXIS_TRIGGER_RIGHT) - trigger(id, JOY_AXIS_TRIGGER_LEFT), -1.0, 1.0)

static func steering() -> float:
    var key := float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
    return clampf(key + axis(joy_id(), JOY_AXIS_LEFT_X), -1.0, 1.0)

static func stick_y(left: bool) -> float:
    var axis_id := JOY_AXIS_LEFT_Y if left else JOY_AXIS_RIGHT_Y
    return axis(joy_id(), axis_id)

static func stick_x(left: bool) -> float:
    var axis_id := JOY_AXIS_LEFT_X if left else JOY_AXIS_RIGHT_X
    return axis(joy_id(), axis_id)

static func slew() -> float:
    var id := joy_id()
    var left := id >= 0 and Input.is_joy_button_pressed(id, JOY_BUTTON_LEFT_SHOULDER)
    var right := id >= 0 and Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER)
    return float(right or Input.is_key_pressed(KEY_E)) - float(left or Input.is_key_pressed(KEY_Q))

static func switch_machine() -> bool:
    var id := joy_id()
    return Input.is_key_pressed(KEY_TAB) or (id >= 0 and Input.is_joy_button_pressed(id, JOY_BUTTON_Y))
