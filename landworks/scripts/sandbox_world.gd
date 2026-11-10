# Playable physics-first farm sandbox: B7100HST with dynamic trailer,
# genuine powered-joint KX080 rig, and pushable/rollable rigid bodies.
# Material areas are flat-zone approximations, NOT deformable voxel terrain.
extends Node3D

const M = preload("res://landworks/scripts/mesh_factory.gd")
const CI = preload("res://landworks/scripts/machine_input.gd")
const T = preload("res://landworks/scripts/tractor.gd")
const E = preload("res://landworks/scripts/sandbox_excavator.gd")
const TRAILER = preload("res://landworks/scripts/work_trailer.gd")
const SOIL = preload("res://landworks/scripts/ground_response.gd")
const EARTH = preload("res://landworks/scripts/earthworks.gd")
const ART = preload("res://landworks/scripts/art_scene.gd")
const MACHINE_ART = preload("res://landworks/scripts/machine_art.gd")

const SMOKE_DURATION_S := 21.0
const CLAY_START_X := 18.0

var tractor: RigidBody3D
var trailer: RigidBody3D
var hitch: PinJoint3D
var digger: Node3D
var props: Array[RigidBody3D] = []
var prop_surfaces: Dictionary = {}
var camera: Camera3D
var status: Label
var active_machine := 0
var toggle_down := false
var legacy_down := false
var hook_down := false
var hook_status := "Press G / Square to hook the nearest loose object"
var orbit_yaw := 0.72
var show_help := false
var help_down := false
var help_panel: ColorRect
var smoke := false
var smoke_time := 0.0
var smoke_log_elapsed := 0.0
var smoke_file: FileAccess
var smoke_out := ""
var tractor_start := Vector3.ZERO
var excavator_start := Vector3.ZERO
var prop_start := Vector3.ZERO
var max_tractor_travel := 0.0
var max_crawler_travel := 0.0
var max_prop_travel := 0.0
var max_boom_change := 0.0
var max_hitch_error := 0.0
var max_tilt := 0.0
var peak_pressure := 0.0
var initial_boom := 0.0
var earth: Node3D
var soil_bucket_m3 := 0.0
var soil_bucket_material := "gravel"
var previous_bucket_lip := Vector3.ZERO
var previous_bucket_lip_valid := false
var maximum_excavated_m3 := 0.0
var maximum_dumped_m3 := 0.0
var tip_previous_m3 := 0.0
# Default false. The physics test sets this like holding R; independent of
# the bucket's automatic curl-angle spill condition.
var spoil_dump_request := false
var soil_mass_error_m3 := 0.0
var earthwork_start_m3 := 0.0

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg == "--sandbox-smoke":
            smoke = true
        elif arg.begins_with("--output-dir="):
            smoke_out = arg.trim_prefix("--output-dir=")
    if smoke_out != "":
        DirAccess.make_dir_recursive_absolute(smoke_out)
    _build_terrain()
    _build_painted_world()
    _build_machines()
    _build_earthworks()
    _build_loose_objects()
    _build_environment()
    _build_ui()
    _select_machine(0)
    tractor_start = tractor.global_position
    excavator_start = digger.undercarriage.global_position
    prop_start = digger.test_mass.global_position
    initial_boom = digger._joint_angle("boom")
    if smoke:
        tractor.set("benchmark_enabled", true)
        digger.scripted_test = true
        smoke_file = FileAccess.open(_out("sandbox_samples.csv"), FileAccess.WRITE)
        if smoke_file == null:
            push_error("Cannot write sandbox simulation telemetry")
            get_tree().quit(4)
            return
        smoke_file.store_csv_line(PackedStringArray(["time_s", "tractor_move_m",
            "crawler_move_m", "crate_move_m", "boom_delta_deg", "hitch_error_m",
            "chassis_tilt_deg", "hydraulic_pressure_mpa", "track_contacts"]))
    print("LANDWORKS_SANDBOX_READY tractors=1 excavators=1 trailer=1 props=", props.size()+1)

func _out(filename: String) -> String:
    return "user://" + filename if smoke_out == "" else smoke_out.path_join(filename)

func _build_terrain() -> void:
    var floor := StaticBody3D.new()
    floor.name = "SolidGround_140m"
    add_child(floor)
    var shape := BoxShape3D.new()
    shape.size = Vector3(140, 1.0, 140)
    var collider := CollisionShape3D.new()
    collider.shape = shape
    collider.position.y = -0.5
    floor.add_child(collider)
    var physics := PhysicsMaterial.new()
    physics.friction = 0.82
    floor.physics_material_override = physics
    # Flat Jolt supporting plane remains at exact y=0. Painterly ground is
    # purely visual and never changes the tyre or track-contact calculations.

func _build_painted_world() -> void:
    var decor: Node3D = ART.new()
    decor.name = "PaintedCountryside_VisualOnly"
    add_child(decor)

func _build_scenery() -> void:
    # A few fixed obstacles and guide markers; keep critical working space open.
    M.block(self, Vector3(8, 4.0, 7), Vector3(-37, 2.0, -27), Color("#9faaa4"))
    M.block(self, Vector3(8.6, 0.40, 7.7), Vector3(-37, 4.15, -27), Color("#494e52"))
    for n in range(10):
        var x := -55.0 + float(n % 5) * 22.0
        var z := -50.0 if n < 5 else 48.0
        M.cylinder(self, 0.18, 3.0, Vector3(x, 1.5, z), Color("#664b36"))
        M.cylinder(self, 1.2, 3.0, Vector3(x, 3.9, z), Color("#506e3a"))
    # Low raised ramp for future loaded hill-start validation.
    var ramp := StaticBody3D.new()
    ramp.name = "SixDegree_Ramp"
    add_child(ramp)
    var block := BoxShape3D.new()
    block.size = Vector3(7.0, 0.35, 8.0)
    var c := CollisionShape3D.new()
    c.shape = block
    ramp.add_child(c)
    ramp.rotation.x = deg_to_rad(6.0)
    ramp.position = Vector3(-25.0, 0.60, 20.0)
    M.block(ramp, block.size, Vector3.ZERO, Color("#8c8371"))
    for z in [-25.0, -15.0, -5.0, 5.0, 15.0, 25.0]:
        M.block(self, Vector3(0.10, 0.015, 1.2), Vector3(16.0, 0.017, z),
            Color("#d6c4a0"))

func _build_machines() -> void:
    tractor = T.new()
    tractor.name = "B7100_HST"
    tractor.position = Vector3(-10.0, 0.78, 9.0)
    tractor.work_speed_limit_kmh = 15.0
    add_child(tractor)
    var hitch_world: Vector3 = tractor.to_global(Vector3(0, -0.20, 1.30))
    trailer = TRAILER.new()
    trailer.payload_kg = 400.0
    add_child(trailer)
    trailer.global_position = hitch_world - trailer.global_transform.basis * Vector3(0, -0.15, -1.80)
    hitch = PinJoint3D.new()
    hitch.name = "Live_Tractor_Trailer_Hitch"
    add_child(hitch)
    hitch.global_position = hitch_world
    hitch.node_a = hitch.get_path_to(tractor)
    hitch.node_b = hitch.get_path_to(trailer)
    hitch.exclude_nodes_from_collision = true
    digger = E.new()
    digger.name = "Excavator"
    add_child(digger)
    var visual_shell: Node3D = MACHINE_ART.new()
    visual_shell.name = "DetailedKubotaVisuals_ArtOnly"
    add_child(visual_shell)
    visual_shell.attach_to(tractor,digger)

func _build_earthworks() -> void:
    earth = EARTH.new()
    earth.name = "GranularExcavationPad_GravelAndClay"
    earth.position = Vector3(0, 0, -12)
    add_child(earth)
    earthwork_start_m3 = earth.ground_volume_m3()

func _make_prop(name: String, kg: float, location: Vector3,
        radius: float, cylinder: bool, tint: Color) -> void:
    var body := RigidBody3D.new()
    body.name = name
    body.mass = kg
    body.can_sleep = false
    body.continuous_cd = true
    body.collision_layer = 1
    body.collision_mask = 3
    body.linear_damp = 0.035
    body.angular_damp = 0.10
    add_child(body)
    body.global_position = location
    var col := CollisionShape3D.new()
    body.add_child(col)
    if cylinder:
        var shape := CylinderShape3D.new()
        shape.radius = radius
        shape.height = 2.2
        col.shape = shape
        col.rotation.z = PI * 0.5
        M.cylinder(body, radius, 2.2, Vector3.ZERO, tint, true)
    else:
        var shape := BoxShape3D.new()
        shape.size = Vector3(radius * 2, radius * 2, radius * 2)
        col.shape = shape
        M.block(body, shape.size, Vector3.ZERO, tint)
    var mat := PhysicsMaterial.new()
    mat.friction = 0.48
    body.physics_material_override = mat
    props.append(body)

func _build_loose_objects() -> void:
    _make_prop("Timber_Log_450kg", 450.0, Vector3(-6, 0.60, -15), 0.57, true, Color("#80603a"))
    _make_prop("Rock_900kg", 900.0, Vector3(7, 0.80, -12), 0.80, false, Color("#747e7d"))
    _make_prop("Crate_650kg", 650.0, Vector3(11, 0.60, -7), 0.57, false, Color("#ad8f65"))
    _make_prop("Clay_Test_Block_650kg", 650.0, Vector3(27, 0.60, -11), 0.57, false, Color("#ab9073"))
    props.append(digger.test_mass) # Existing 1,500 kg free crate from tested rig
    if not smoke:
        # Keep the direct north-to-south crawler entrance unobstructed.
        # The 1.5t crate still exists to push and drag on the far-right pad.
        digger.test_mass.global_position = Vector3(7.0, 0.63, -8.0)

func _build_environment() -> void:
    var sun := DirectionalLight3D.new()
    sun.name = "WarmAfternoonKeyLight"
    sun.rotation_degrees = Vector3(-49, -34, 0)
    sun.light_color = Color("#fff1df")
    sun.light_energy = 1.04
    sun.shadow_enabled = true
    add_child(sun)
    var world := WorldEnvironment.new()
    var env := Environment.new()
    var painted_sky := ProceduralSkyMaterial.new()
    painted_sky.sky_top_color = Color("#478db9")
    painted_sky.sky_horizon_color = Color("#b3d4d3")
    painted_sky.ground_horizon_color = Color("#c4c2a4")
    painted_sky.ground_bottom_color = Color("#8a956c")
    painted_sky.sun_angle_max = 22.0
    var sky := Sky.new()
    sky.sky_material = painted_sky
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.43
    env.fog_enabled = true
    env.fog_light_color = Color("#d3d8c2")
    env.fog_density = 0.0012
    env.fog_sky_affect = 0.25
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    env.adjustment_enabled = true
    env.adjustment_brightness = 0.87
    env.adjustment_saturation = 1.22
    env.adjustment_contrast = 1.14
    world.environment = env
    add_child(world)
    camera = Camera3D.new()
    camera.name = "PaintedFollowCamera"
    add_child(camera)
    camera.current = true
    camera.fov = 65.0
    camera.far = 270.0
    camera.position = tractor.position + Vector3(7, 5, 8)

func _build_ui() -> void:
    var canvas := CanvasLayer.new()
    canvas.name = "GameHUD"
    add_child(canvas)
    var bg := ColorRect.new()
    bg.name = "CompactGlassHUD"
    bg.color = Color(0.045,0.085,0.084,0.76)
    bg.size = Vector2(565,111)
    bg.position = Vector2(14,14)
    canvas.add_child(bg)
    status = Label.new()
    status.name = "CompactMachineTelemetry"
    status.position = Vector2(25,23)
    status.add_theme_font_size_override("font_size",17)
    status.add_theme_color_override("font_color",Color("#fff3dc"))
    canvas.add_child(status)
    help_panel = ColorRect.new()
    help_panel.name = "ControlsHelp"
    help_panel.color = Color(0.035,0.075,0.074,0.91)
    help_panel.position = Vector2(14,138)
    help_panel.size = Vector2(600,186)
    help_panel.visible = false
    canvas.add_child(help_panel)
    var instructions := Label.new()
    instructions.position = Vector2(14,12)
    instructions.add_theme_font_size_override("font_size",15)
    instructions.add_theme_color_override("font_color",Color("#f9ecd5"))
    instructions.text = "LANDWORKS  •  CONTROLS\n" +         "Tab / Triangle — change machine     Z/C — orbit camera\n" +         "Tractor: W/S travel, A/D steer; PS R2/L2 travel + left stick\n" +         "Excavator: W/S tracks, A/D differential pivot\n" +         "I/K boom  |  O/L stick  |  P/; bucket  |  Q/E slew\n" +         "G / Square — bucket hook     R — dump soil     F12 — old yard\n" +         "F1 — close help"
    help_panel.add_child(instructions)

func _select_machine(which: int) -> void:
    active_machine = which
    tractor.controlled = which == 0 and not smoke
    digger.operated = which == 1 and not smoke

func _current_surface(x: float) -> Dictionary:
    return SOIL.profile("soft_clay" if x > CLAY_START_X else "hardpack")

func _physics_process(delta: float) -> void:
    # Machine and loose-body contact forces all run in the same Jolt world.
    tractor.ground_mu_override = 0.53 if tractor.global_position.x > CLAY_START_X else T.GROUND_MU
    digger.surface_profile = _current_surface(digger.undercarriage.global_position.x)
    for item in props:
        if not is_instance_valid(item):
            continue
        var p: Dictionary = _current_surface(item.global_position.x)
        if prop_surfaces.get(item.get_instance_id(), "") != str(p["name"]):
            var phys := PhysicsMaterial.new()
            phys.friction = float(p["object_mu"])
            item.physics_material_override = phys
            prop_surfaces[item.get_instance_id()] = str(p["name"])
        if item != digger.test_mass or item.global_position.x > CLAY_START_X:
            SOIL.apply_ground_resistance(item, p)
    _update_earthworks(delta)
    if not smoke:
        return
    smoke_time += delta
    tractor.benchmark_throttle = 0.70 if smoke_time > 2.0 and smoke_time < 13.0 else 0.0
    tractor.benchmark_brake = 0.8 if smoke_time >= 13.0 else 0.0
    var delta_tractor: Vector3 = tractor.global_position - tractor_start
    var delta_excavator: Vector3 = digger.undercarriage.global_position - excavator_start
    var delta_crate: Vector3 = digger.test_mass.global_position - prop_start
    max_tractor_travel = maxf(max_tractor_travel, Vector2(delta_tractor.x, delta_tractor.z).length())
    max_crawler_travel = maxf(max_crawler_travel, Vector2(delta_excavator.x, delta_excavator.z).length())
    max_prop_travel = maxf(max_prop_travel, Vector2(delta_crate.x, delta_crate.z).length())
    max_boom_change = maxf(max_boom_change,
        absf(rad_to_deg(digger._joint_angle("boom") - initial_boom)))
    var hitch_gap := tractor.to_global(Vector3(0, -0.20, 1.30)).distance_to(
        trailer.to_global(Vector3(0, -0.15, -1.80)))
    max_hitch_error = maxf(max_hitch_error, hitch_gap)
    var up: Vector3 = digger.undercarriage.global_transform.basis.y.normalized()
    max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0))))
    peak_pressure = maxf(peak_pressure, float(digger.hydraulic_state.get("pressure_mpa", 0.0)))
    smoke_log_elapsed += delta
    if smoke_file != null and smoke_log_elapsed >= 0.25:
        smoke_log_elapsed -= 0.25
        smoke_file.store_csv_line(PackedStringArray([
            "%.3f" % smoke_time, "%.3f" % max_tractor_travel,
            "%.3f" % max_crawler_travel, "%.3f" % max_prop_travel,
            "%.3f" % max_boom_change, "%.3f" % max_hitch_error,
            "%.3f" % max_tilt, "%.3f" % peak_pressure,
            str(digger.ground_contact_count)
        ]))
    if smoke_time >= SMOKE_DURATION_S:
        _finish_smoke()

func _update_earthworks(delta: float) -> void:
    # Engine-driven physical lip path: no soil is excavated by an animation or
    # player pressing a magical remove-soil button. The bucket must reach an
    # actual bank and move through it while below the soil surface.
    var lip: Vector3 = digger.bucket.to_global(Vector3(0, 0, -digger.BUCKET_LENGTH))
    if not previous_bucket_lip_valid:
        previous_bucket_lip = lip
        previous_bucket_lip_valid = true
        return
    var lip_motion := lip - previous_bucket_lip
    var free_volume := maxf(0.0, earth.MAX_BUCKET_M3 - soil_bucket_m3)
    if free_volume > 0.0001 and earth.has_position(lip):
        var result: Dictionary = earth.cut_sweep(previous_bucket_lip,
            lip, 0.76, free_volume)
        var cut_volume: float = result["volume_m3"]
        if cut_volume > 0.0:
            soil_bucket_m3 += cut_volume
            maximum_excavated_m3 += cut_volume
            # Choose material from the actual excavated cells, not just
            # a guessed world-X dividing line.
            soil_bucket_material = "clay" if float(result.get("clay_m3",0.0)) >
                float(result.get("gravel_m3",0.0)) else "gravel"
            var reaction_n: float = result["force_n"]
            # Push back on the REAL Jolt bucket at the tooth edge; this force
            # can oppose the cylinder motor, react through arm pins and tip
            # the chassis rather than being a cosmetic cutting effect.
            if lip_motion.length() > 0.002:
                digger.bucket.apply_force(
                    -lip_motion.normalized() * reaction_n,
                    lip - digger.bucket.global_position)
    previous_bucket_lip = lip
    var player_dump := spoil_dump_request or (not smoke and active_machine == 1 and Input.is_key_pressed(KEY_R))
    var bucket_tip_angle: float = digger._joint_angle("bucket")
    # Curling forward spills soil under gravity. Manual R provides a simple
    # discharge override until the actual bucket shell is modelled.
    var tipped_forward := bucket_tip_angle > 0.32
    if soil_bucket_m3 > 0.0001 and (player_dump or tipped_forward):
        var release_volume := minf(soil_bucket_m3, delta * 0.115)
        var released: float = earth.release_soil(
            lip + Vector3.UP * 0.14, digger.bucket.linear_velocity,
            release_volume, soil_bucket_material)
        soil_bucket_m3 -= released
        maximum_dumped_m3 += released
    soil_mass_error_m3 = earth.ground_volume_m3() + soil_bucket_m3 +         earth.mobile_volume_m3() + earth.offsite_m3 - earthwork_start_m3

func _finish_smoke() -> void:
    smoke_file.close()
    var f := FileAccess.open(_out("sandbox_summary.csv"), FileAccess.WRITE)
    if f == null:
        push_error("Failed to write sandbox physical test summary")
        get_tree().quit(5)
        return
    f.store_csv_line(PackedStringArray(["tractor_travel_m", "excavator_travel_m",
        "crate_travel_m", "boom_change_deg", "max_hitch_error_m",
        "max_chassis_tilt_deg", "peak_hydraulic_pressure_mpa", "test_duration_s"]))
    f.store_csv_line(PackedStringArray([
        "%.3f" % max_tractor_travel, "%.3f" % max_crawler_travel,
        "%.3f" % max_prop_travel, "%.3f" % max_boom_change,
        "%.3f" % max_hitch_error, "%.3f" % max_tilt,
        "%.3f" % peak_pressure, "%.3f" % smoke_time
    ]))
    f.close()
    print("LANDWORKS_SANDBOX_TEST_COMPLETE ", _out("sandbox_summary.csv"))
    get_tree().quit(0)

func _process(delta: float) -> void:
    if not smoke:
        var help_pressed := Input.is_key_pressed(KEY_F1)
        if help_pressed and not help_down:
            show_help = not show_help
            help_panel.visible = show_help
        help_down = help_pressed
        var toggle := CI.switch_machine()
        if toggle and not toggle_down:
            _select_machine(1 - active_machine)
        toggle_down = toggle
        var go_legacy := Input.is_key_pressed(KEY_F12)
        if go_legacy and not legacy_down:
            get_tree().change_scene_to_file("res://landworks/scenes/test_yard.tscn")
            return
        legacy_down = go_legacy
        var joy := CI.joy_id()
        var hook_pressed := active_machine == 1 and (
            Input.is_key_pressed(KEY_G) or
            (joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_X)))
        if hook_pressed and not hook_down:
            hook_status = digger.toggle_hook(props)
        hook_down = hook_pressed
        if active_machine == 0:
            orbit_yaw -= CI.axis(joy, JOY_AXIS_RIGHT_X) * delta * 1.4
        orbit_yaw += (float(Input.is_key_pressed(KEY_C)) -
            float(Input.is_key_pressed(KEY_Z))) * delta * 1.2
    var target: Node3D = tractor if active_machine == 0 else digger.undercarriage
    var focus := target.global_position + (
        Vector3(0,0.65,-0.20) if active_machine == 0 else Vector3(0,1.30,-1.45))
    var dist := 5.90 if active_machine == 0 else 8.75
    var height := 2.50 if active_machine == 0 else 3.50
    var wanted := focus + Vector3(sin(orbit_yaw) * dist, height, cos(orbit_yaw) * dist)
    camera.global_position = camera.global_position.lerp(wanted, clampf(delta * 4.5, 0.0, 1.0))
    camera.look_at(focus, Vector3.UP)
    var speed: float = tractor.linear_velocity.length() * 3.6
    var ground_label: String = str(_current_surface(target.global_position.x)["name"])
    if active_machine == 0:
        status.text = "KUBOTA B7100 HST  •  FARM WORKS\n"
        status.text += "Speed %.1f km/h   |   HST %.1f kW   |   %s\n" % [
            speed, tractor.last_hst_power_kw,ground_label]
        status.text += "400 kg trailer  •  Tab switch machine  •  F1 controls"
    else:
        status.text = "KUBOTA KX080-3  •  EARTHMOVING\n"
        status.text += "Hyd %.1f MPa  |  %.1f L/min  |  Ground %d/4\n" % [
            float(digger.hydraulic_state.get("pressure_mpa",0.0)),
            float(digger.hydraulic_state.get("flow_lpm",0.0)),
            digger.ground_contact_count]
        status.text += "Bucket %.0f L  |  Dug %.0f L  |  F1 controls" % [
            soil_bucket_m3*1000.0,maximum_excavated_m3*1000.0]
