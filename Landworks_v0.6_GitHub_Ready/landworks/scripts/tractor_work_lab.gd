# Physical tow-hitch field trials. A dynamic single-axle trailer follows the original
# tractor under gravity on level ground or a 6-degree hill.
# All reported dynamic measurements must come from an actual Godot physics run.
extends Node3D

const M = preload("res://landworks/scripts/mesh_factory.gd")
const TRACTOR = preload("res://landworks/scripts/tractor.gd")
const TRAILER = preload("res://landworks/scripts/work_trailer.gd")

const SCENARIOS := {
    "flat_empty": {"slope_deg": 0.0, "load_kg": 0.0},
    "flat_400": {"slope_deg": 0.0, "load_kg": 400.0},
    "hill_400": {"slope_deg": 6.0, "load_kg": 400.0},
    "hill_800": {"slope_deg": 6.0, "load_kg": 800.0}
}
const PERIODS := [2.0, 12.0, 6.0, 8.0]
const PHASE_NAMES := ["SETTLE", "PULL", "BRAKE", "TURN", "DONE"]

var tractor: RigidBody3D
var trailer: RigidBody3D
var hitch: PinJoint3D
var label: Label
var telemetry: FileAccess
var scenario := "flat_400"
var output_dir := ""
var elapsed := 0.0
var phase := 0
var phase_time := 0.0
var log_clock := 0.0
var furthest_m := 0.0
var peak_kmh := 0.0
var peak_roll_deg := 0.0
var worst_hitch_error_m := 0.0
var brake_start := Vector3.ZERO
var brake_distance_m := 0.0
var peak_articulation_deg := 0.0
var tipped := false
var finished := false
var batch := false

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--scenario="):
            scenario = arg.trim_prefix("--scenario=")
        elif arg.begins_with("--output-dir="):
            output_dir = arg.trim_prefix("--output-dir=")
        elif arg == "--batch":
            batch = true
    if not SCENARIOS.has(scenario):
        push_error("Unknown tractor scenario: " + scenario)
        get_tree().quit(3)
        return
    if output_dir != "":
        DirAccess.make_dir_recursive_absolute(output_dir)
    _build_ground(float(SCENARIOS[scenario]["slope_deg"]))
    _build_rig(float(SCENARIOS[scenario]["slope_deg"]), float(SCENARIOS[scenario]["load_kg"]))
    _build_view()
    var path := _out("tractor_" + scenario + "_samples.csv")
    telemetry = FileAccess.open(path, FileAccess.WRITE)
    if telemetry == null:
        push_error("Could not open telemetry: " + path)
        get_tree().quit(4)
        return
    telemetry.store_csv_line(PackedStringArray(["time_s", "phase", "slope_deg", "payload_kg",
        "tractor_x_m", "tractor_y_m", "tractor_z_m", "tractor_speed_kmh", "trailer_speed_kmh",
        "hitch_error_m", "articulation_deg", "tractor_roll_deg", "trailer_roll_deg",
        "trailer_wheels_contacting"]))

func _out(filename: String) -> String:
    return "user://" + filename if output_dir == "" else output_dir.path_join(filename)

func _ground_height(z: float, slope: float) -> float:
    return tan(slope) * (16.0 - z)

func _build_ground(slope_deg: float) -> void:
    var angle := deg_to_rad(slope_deg)
    var floor := StaticBody3D.new()
    floor.name = "Field_Test_Grass_Ramp"
    floor.add_to_group("Grass")
    floor.set_meta("material", "grass")
    add_child(floor)
    var shape := BoxShape3D.new()
    shape.size = Vector3(70, 0.7, 100.0)
    var col := CollisionShape3D.new()
    col.shape = shape
    floor.add_child(col)
    floor.rotation.x = angle
    floor.position = Vector3(0, sin(angle) * 50.0 - cos(angle) * 0.35, 16.0 - cos(angle) * 50.0)
    var mat := PhysicsMaterial.new()
    mat.friction = 0.90
    floor.physics_material_override = mat
    M.block(floor, shape.size, Vector3.ZERO, Color("#637b49"))
    for z in range(-65, 15, 5):
        # Visual markers only; the actual collision is the inclined box.
        M.block(self, Vector3(3.5, 0.02, 0.14),
            Vector3(-2.8, _ground_height(float(z), angle) + 0.04, float(z)), Color("#d2c9a4"))

func _build_rig(slope_deg: float, load_kg: float) -> void:
    var angle := deg_to_rad(slope_deg)
    tractor = TRACTOR.new()
    tractor.name = "B7100_HST_baseline_with_towbar"
    tractor.set("benchmark_enabled", true)
    tractor.set("work_speed_limit_kmh", 15.0)  # proxy B7100 HST working speed
    tractor.position = Vector3(0, _ground_height(8.0, angle) + 0.76, 8)
    tractor.rotation.x = angle
    add_child(tractor)
    var tractor_hitch_local := Vector3(0, -0.20, 1.30)
    var hitch_world: Vector3 = tractor.to_global(tractor_hitch_local)
    trailer = TRAILER.new()
    trailer.set("payload_kg", load_kg)
    trailer.rotation.x = angle
    add_child(trailer)
    var trailer_tongue := Vector3(0, -0.15, -1.80)
    trailer.global_position = hitch_world - trailer.global_transform.basis * trailer_tongue
    hitch = PinJoint3D.new()
    hitch.name = "PhysicalTowHitch"
    add_child(hitch)
    hitch.global_position = hitch_world
    hitch.node_a = hitch.get_path_to(tractor)
    hitch.node_b = hitch.get_path_to(trailer)
    hitch.exclude_nodes_from_collision = true

func _build_view() -> void:
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -38, 0)
    add_child(sun)
    var cam := Camera3D.new()
    add_child(cam)
    cam.position = Vector3(24, 16, 23)
    cam.look_at(Vector3(0, 2, -8))
    cam.current = true
    var canvas := CanvasLayer.new()
    add_child(canvas)
    label = Label.new()
    label.position = Vector2(24, 24)
    label.add_theme_font_size_override("font_size", 20)
    canvas.add_child(label)

func _physics_process(delta: float) -> void:
    if finished or telemetry == null:
        return
    elapsed += delta
    phase_time += delta
    if phase < PERIODS.size() and phase_time >= PERIODS[phase]:
        phase_time -= PERIODS[phase]
        phase += 1
        if phase == 2:
            brake_start = tractor.global_position
    var throttle := 0.0
    var brake := 0.0
    var steer := 0.0
    if phase == 1:
        throttle = 0.80
    elif phase == 2:
        brake = 1.0
    elif phase == 3:
        throttle = 0.50
        steer = 0.30
    tractor.set("benchmark_throttle", throttle)
    tractor.set("benchmark_brake", brake)
    tractor.set("benchmark_steer", steer)
    var speed := Vector2(tractor.linear_velocity.x, tractor.linear_velocity.z).length() * 3.6
    peak_kmh = maxf(peak_kmh, speed)
    furthest_m = maxf(furthest_m, 8.0 - tractor.global_position.z)
    var error := tractor.to_global(Vector3(0, -0.20, 1.30)).distance_to(
        trailer.to_global(Vector3(0, -0.15, -1.80)))
    worst_hitch_error_m = maxf(worst_hitch_error_m, error)
    var rel_rotation: Basis = tractor.global_transform.basis.inverse() * trailer.global_transform.basis
    var articulation_deg := absf(rad_to_deg(atan2(rel_rotation.z.x, rel_rotation.z.z)))
    peak_articulation_deg = maxf(peak_articulation_deg, articulation_deg)
    var t_roll := absf(rad_to_deg(acos(clampf(tractor.global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0))))
    var tr_roll := absf(rad_to_deg(acos(clampf(trailer.global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0))))
    peak_roll_deg = maxf(peak_roll_deg, maxf(t_roll, tr_roll))
    tipped = tipped or peak_roll_deg > 30.0
    if phase == 2:
        var d: Vector3 = tractor.global_position - brake_start
        brake_distance_m = Vector2(d.x, d.z).length()
    log_clock += delta
    if log_clock >= 0.10:
        log_clock -= 0.10
        telemetry.store_csv_line(PackedStringArray([
            "%.3f" % elapsed, PHASE_NAMES[phase], "%.1f" % float(SCENARIOS[scenario]["slope_deg"]),
            "%.0f" % float(SCENARIOS[scenario]["load_kg"]),
            "%.3f" % tractor.global_position.x, "%.3f" % tractor.global_position.y,
            "%.3f" % tractor.global_position.z, "%.3f" % speed,
            "%.3f" % (Vector2(trailer.linear_velocity.x, trailer.linear_velocity.z).length() * 3.6),
            "%.3f" % error, "%.3f" % articulation_deg, "%.3f" % t_roll,
            "%.3f" % tr_roll, str(int(trailer.get("last_contact_count")))
        ]))
    label.text = "LANDWORKS | TRACTOR + LIVE TRAILER PHYSICS\n"
    label.text += "%s | %s | %4.1f km/h | payload %.0f kg\n" % [scenario, PHASE_NAMES[phase], speed, float(SCENARIOS[scenario]["load_kg"])]
    label.text += "Distance %.1f m | hitch separation %.3f m | peak pitch/roll %.1f°\n" % [furthest_m, error, peak_roll_deg]
    if phase == 4:
        _finish()

func _finish() -> void:
    finished = true
    telemetry.close()
    var path := _out("tractor_" + scenario + "_summary.csv")
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f != null:
        f.store_csv_line(PackedStringArray(["scenario", "slope_deg", "load_kg", "peak_kmh", "forward_distance_m",
            "brake_displacement_m", "max_articulation_deg", "max_tilt_deg", "max_hitch_error_m", "tipped"]))
        f.store_csv_line(PackedStringArray([scenario,
            "%.1f" % float(SCENARIOS[scenario]["slope_deg"]), "%.0f" % float(SCENARIOS[scenario]["load_kg"]),
            "%.3f" % peak_kmh, "%.3f" % furthest_m, "%.3f" % brake_distance_m,
            "%.3f" % peak_articulation_deg, "%.3f" % peak_roll_deg,
            "%.3f" % worst_hitch_error_m, str(int(tipped))]))
        f.close()
    print("LANDWORKS_TRACTOR_TEST_COMPLETE ", scenario, " ", path)
    if batch:
        get_tree().quit(0)
