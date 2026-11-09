# Runnable three-way physics comparison: baseline / KV Vehicle / Easy Vehicle Physics.
# Logs PHYSICAL body state, not estimated or scripted distances.
# Vendor scripts are downloaded by SETUP_PHYSICS_WINDOWS.bat; their physics is not faked.
extends Node3D

const M = preload("res://landworks/scripts/mesh_factory.gd")
const F = preload("res://landworks/scripts/vehicle_bench_factory.gd")
const BASELINE = preload("res://landworks/scripts/tractor.gd")
const CI = preload("res://landworks/scripts/machine_input.gd")

const PHASES := ["SETTLE", "ACCELERATE", "BRAKE", "TURN", "DONE"]
const DURATIONS := [2.5, 10.0, 4.5, 6.0]
var machines: Dictionary = {}
var result: Dictionary = {}
var info: Label
var timer := 0.0
var phase := 0
var log_file: FileAccess
var ran := false
var wall_elapsed := 0.0
var unavailable: Array[String] = []

func _ready() -> void:
    if not InputMap.has_action("slowmo"):
        InputMap.add_action("slowmo")
    var floor := StaticBody3D.new()
    floor.name = "SameGrassForAllLanes"
    floor.add_to_group("Grass")
    floor.set_meta("material", "grass")
    add_child(floor)
    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(105, 1, 195)
    col.shape = shape
    col.position = Vector3(0, -0.5, -52)
    floor.add_child(col)
    M.block(floor, Vector3(105, 0.10, 195), Vector3(0, -0.07, -52), Color("#60804d"))
    _add_lane("BASELINE", -25.0)
    _add_lane("KV", 0.0)
    _add_lane("GEVP", 25.0)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -25, 0)
    add_child(sun)
    var camera := Camera3D.new()
    camera.position = Vector3(37, 28, 32)
    add_child(camera)
    camera.look_at(Vector3(0, 0, -29))
    camera.current = true
    var sky := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#b5cbda")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#ffffff")
    env.ambient_light_energy = 0.65
    sky.environment = env
    add_child(sky)
    var canvas := CanvasLayer.new()
    add_child(canvas)
    info = Label.new()
    info.position = Vector2(28, 20)
    info.add_theme_font_size_override("font_size", 20)
    info.add_theme_color_override("font_color", Color.WHITE)
    canvas.add_child(info)
    log_file = FileAccess.open("user://landworks_comparison_samples.csv", FileAccess.WRITE)
    if log_file != null:
        log_file.store_csv_line(PackedStringArray(["time_s", "phase", "engine", "x_m", "y_m", "z_m", "ground_speed_kmh", "yaw_deg", "roll_deg"]))
    else:
        push_error("Could not write bench telemetry CSV to user://")
    _update_hud()

func _add_lane(id: String, x: float) -> void:
    M.block(self, Vector3(0.12, 0.01, 130.0), Vector3(x-5.0, 0.015, -49.0), Color("#e5ddaa"))
    M.block(self, Vector3(0.12, 0.01, 130.0), Vector3(x+5.0, 0.015, -49.0), Color("#e5ddaa"))
    var label := Label3D.new()
    label.text = id
    label.font_size = 90
    label.pixel_size = 0.007
    label.position = Vector3(x, 3, 12)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(label)
    var body: RigidBody3D
    if id == "BASELINE":
        body = BASELINE.new()
        body.set("benchmark_enabled", true)
    elif id == "KV":
        body = F.create_kv()
    else:
        body = F.create_gevp()
    if body == null:
        unavailable.append(id)
        return
    body.position = Vector3(x, 0.73, 6.0)
    body.can_sleep = false
    add_child(body)
    machines[id] = body
    result[id] = {
        "max_kmh": 0.0,
        "accel_distance_m": 0.0,
        "brake_distance_m": 0.0,
        "turn_yaw_deg": 0.0,
        "turn_roll_deg": 0.0,
        "last_pos": body.global_position,
        "brake_begin": Vector3.ZERO,
        "turn_begin_yaw": 0.0
    }
    if id == "KV":
        # KVDrivetrain is in neutral until a real gear is selected.
        body.get_node("drivetrain").call_deferred("shiftIntoGear", 2)
    elif id == "GEVP":
        body.set("current_gear", 1)

func _physics_process(delta: float) -> void:
    var joy_id := CI.joy_id()
    if Input.is_key_pressed(KEY_F4) or (joy_id >= 0 and Input.is_joy_button_pressed(joy_id, JOY_BUTTON_B)):
        if log_file != null and log_file.is_open():
            log_file.close()
        get_tree().change_scene_to_file("res://landworks/scenes/test_yard.tscn")
        return
    if ran:
        return
    timer += delta
    wall_elapsed += delta
    if phase < DURATIONS.size() and timer >= DURATIONS[phase]:
        timer -= DURATIONS[phase]
        phase += 1
        _begin_phase()
    var throttle := 0.0
    var brake := 0.0
    var steer := 0.0
    if phase == 1:
        throttle = 1.0
    elif phase == 2:
        brake = 1.0
    elif phase == 3:
        throttle = 0.62
        steer = 0.62
    for id in machines:
        var body: RigidBody3D = machines[id]
        if id == "BASELINE":
            body.set("benchmark_throttle", throttle)
            body.set("benchmark_steer", steer)
            body.set("benchmark_brake", brake)
        elif id == "KV":
            body.set("accelerationInput", throttle)
            body.set("break2Input", brake)
            body.set("normalizedSteering", steer)
            body.set("clutchInput", 1.0)
            body.set("breaking", brake > 0.5)
        else:
            body.set("throttle_input", throttle)
            body.set("steering_input", steer)
            body.set("brake_input", brake)
        _record(id, body, delta)
    if phase == 4:
        _finish()
    _update_hud()

func _begin_phase() -> void:
    for id in machines:
        var body: RigidBody3D = machines[id]
        var r: Dictionary = result[id]
        if phase == 2:
            r["brake_begin"] = body.global_position
        elif phase == 3:
            r["turn_begin_yaw"] = body.rotation_degrees.y

func _record(id: String, body: RigidBody3D, delta: float) -> void:
    var r: Dictionary = result[id]
    var planar_v := Vector2(body.linear_velocity.x, body.linear_velocity.z)
    var speed := planar_v.length() * 3.6
    if phase == 1:
        r["max_kmh"] = maxf(r["max_kmh"], speed)
        var d: Vector3 = body.global_position - r["last_pos"]
        r["accel_distance_m"] += Vector2(d.x, d.z).length()
    elif phase == 2:
        var d: Vector3 = body.global_position - r["last_pos"]
        r["brake_distance_m"] += Vector2(d.x, d.z).length()
    elif phase == 3:
        r["turn_yaw_deg"] = wrapf(body.rotation_degrees.y - r["turn_begin_yaw"], -180.0, 180.0)
        r["turn_roll_deg"] = maxf(r["turn_roll_deg"], absf(body.rotation_degrees.z))
    r["last_pos"] = body.global_position
    if log_file != null:
        var p := body.global_position
        log_file.store_csv_line(PackedStringArray([
            "%.3f" % wall_elapsed, PHASES[phase], id,
            "%.3f" % p.x, "%.3f" % p.y, "%.3f" % p.z,
            "%.3f" % speed, "%.3f" % body.rotation_degrees.y,
            "%.3f" % body.rotation_degrees.z
        ]))

func _finish() -> void:
    ran = true
    if log_file != null:
        log_file.close()
    var lines := ["engine,max_speed_kmh,accel_path_m,brake_path_m,turn_yaw_deg,max_roll_deg"]
    for id in ["BASELINE", "KV", "GEVP"]:
        if not result.has(id):
            continue
        var r: Dictionary = result[id]
        lines.append("%s,%.3f,%.3f,%.3f,%.3f,%.3f" % [id, r["max_kmh"], r["accel_distance_m"], r["brake_distance_m"], r["turn_yaw_deg"], r["turn_roll_deg"]])
    var file := FileAccess.open("user://landworks_comparison_summary.csv", FileAccess.WRITE)
    if file != null:
        file.store_string("\n".join(lines) + "\n")
        file.close()
    print("LANDWORKS BENCHMARK RESULTS:\n", "\n".join(lines))
    print("Files written to: ", ProjectSettings.globalize_path("user://"))

func _update_hud() -> void:
    if info == null:
        return
    var text_out := "LANDWORKS v0.5  |  3-WAY TRACTOR PHYSICS BENCHMARK  |  120 Hz preferred\n"
    text_out += "PHASE: %s   elapsed %.1f s\n" % [PHASES[phase], timer]
    for id in ["BASELINE", "KV", "GEVP"]:
        if not machines.has(id):
            text_out += "%s: NOT INSTALLED — run SETUP_PHYSICS_WINDOWS.bat\n" % id
            continue
        var body: RigidBody3D = machines[id]
        text_out += "%s: %5.1f km/h   y=%5.2f m   roll=%5.1f deg\n" % [id, body.linear_velocity.length()*3.6, body.global_position.y, body.rotation_degrees.z]
    if ran:
        text_out += "COMPLETE — CSV samples and summary saved under user:// | F4/Circle return\n"
    else:
        text_out += "Automatic identical controls: settle / full throttle / brake / 62% throttle + steering.\n"
    info.text = text_out
