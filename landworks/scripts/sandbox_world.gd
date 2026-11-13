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
const MACHINE_ART = preload("res://landworks/scripts/engineered_machine_art.gd")
const RIGGED_ART = preload("res://landworks/scripts/rigged_machine_art.gd")
const COUPLER = preload("res://landworks/scripts/coupler.gd")
const TRACTOR_HITCH_LOCAL := Vector3(0, -0.20, 1.30)

const SMOKE_DURATION_S := 21.0
const CLAY_START_X := 18.0

var tractor: RigidBody3D
var trailer: RigidBody3D
var hitch_coupler: Node3D
var hitch: PinJoint3D:
    get: return hitch_coupler.joint if hitch_coupler != null else null
var digger: Node3D
var props: Array[RigidBody3D] = []
var prop_surfaces: Dictionary = {}
var camera: Camera3D
var status: Label
var active_machine := 0
var toggle_down := false
var legacy_down := false
var hook_down := false
var drop_down := false
var hook_status := "Strap takes hold near a load; G releases it"
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
# Boom movement restricted to the window in which the programme actually
# commands the boom. The unrestricted figure above counts any movement at all,
# and a run whose boom never responded to a command still reported 4.2 deg of
# it, earned entirely by the chassis being shoved while crawling after the
# commands had stopped. That passed a gate meant to prove the boom actuates.
# BOOM_COMMAND_WINDOW_S must stay in step with sandbox_excavator's programme.
const BOOM_COMMAND_WINDOW_S := 10.5
var max_boom_change_commanded := 0.0
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
var machine_visuals: Node3D
var rig_visuals: Node3D
const BLADE_WIDTH_M := 2.20
const BLADE_EDGE_LOCAL := Vector3(0,-0.23,-0.90)
var previous_blade_edge := Vector3.ZERO
var previous_blade_edge_valid := false
var blade_pushed_m3 := 0.0
var trailer_bin := -1
var start_state: Dictionary = {}
var start_targets: Dictionary = {}
var start_tip := 0.0
var reset_count := 0
var reset_down := false
var settle_tick := 0
var start_settled := false
var tray_discharged_m3 := 0.0
var camera_zoom := 1.0
var inspection_view := false
var inspection_down := false
var pending_soil_contact: Dictionary = {}
var bucket_empty_mass := 0.0
var bucket_empty_center := Vector3.ZERO
var material_diagnostic_clock := 0.0

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
    # Snapshot for the F8 global reset, taken once everything is placed.
    _capture_start_state()
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
    # The mutable 18 m pad is centred at (0, -12). Leave its footprint
    # open: a full yard box here would support machines above every trench.
    for region in [Rect2(-70, -70, 61, 140), Rect2(9, -70, 61, 140),
            Rect2(-9, -70, 18, 49), Rect2(-9, -3, 18, 73)]:
        var shape := BoxShape3D.new()
        shape.size = Vector3(region.size.x, 1.0, region.size.y)
        var collider := CollisionShape3D.new()
        collider.shape = shape
        var center: Vector2 = region.get_center()
        collider.position = Vector3(center.x, -0.5, center.y)
        floor.add_child(collider)
    var physics := PhysicsMaterial.new()
    physics.friction = 0.82
    floor.physics_material_override = physics
    # Outside the mutable footprint, the yard remains at exactly y=0.

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
    var hitch_world: Vector3 = tractor.to_global(TRACTOR_HITCH_LOCAL)
    trailer = TRAILER.new()
    trailer.payload_kg = 400.0
    add_child(trailer)
    trailer.global_position = hitch_world - trailer.global_transform.basis * trailer.HITCH_POINT
    # The tipping tray is a sibling rigid body on a real rear pin.
    trailer.build_tray(self)
    # The drawbar is no longer welded on. Reverse the ball under the ring and
    # it couples itself; H drops it again. Starts coupled because the trailer
    # is placed on the ball, so the first tick captures.
    hitch_coupler = COUPLER.new()
    hitch_coupler.name = "Live_Tractor_Trailer_Hitch"
    hitch_coupler.capture_radius = 0.45
    hitch_coupler.capture_speed = 1.6
    # Pin on the tow ball itself. Splitting the difference baked a permanent
    # quarter-metre offset into the constraint, so the drawbar hung off the
    # ball and dragged the tractor back: it felt like the tractor was stuck.
    hitch_coupler.engage_mix = 0.0
    add_child(hitch_coupler)
    _update_hitch()
    digger = E.new()
    digger.name = "Excavator"
    add_child(digger)
    machine_visuals = MACHINE_ART.new()
    machine_visuals.name = "CustomEngineeredMachineVisuals"
    # The tractor keeps the segmented engineered art; the excavator and the
    # trailer are now driven from their own rigged models.
    machine_visuals.dress_excavator = false
    add_child(machine_visuals)
    machine_visuals.attach_to(tractor,digger)
    rig_visuals = RIGGED_ART.new()
    rig_visuals.name = "RiggedModelMachineVisuals"
    add_child(rig_visuals)
    rig_visuals.attach_excavator(digger)
    rig_visuals.attach_trailer(trailer)
    print(rig_visuals.report())

func _build_earthworks() -> void:
    earth = EARTH.new()
    earth.material_mechanics = true
    for argument in OS.get_cmdline_user_args():
        if argument == "--legacy-soil": earth.material_mechanics = false
    earth.name = "GranularExcavationPad_GravelAndClay"
    earth.position = Vector3(0, 0, -12)
    add_child(earth)
    if earth.material_mechanics:
        # Mutable soil has its own force/work contact solver. A hard contact
        # against the same heightfield arrests the toe before it can cut.
        # Keep normal bucket collisions with yard, bedrock and loose objects.
        digger.bucket.add_collision_exception_with(earth.get_node("MutableSoilCollider"))
    earthwork_start_m3 = earth.ground_volume_m3()
    bucket_empty_mass = digger.bucket.mass
    # The tray catches what the bucket dumps into it instead of the ground.
    if is_instance_valid(trailer.tray):
        # Sits inside the open tray, above its floor and within its sides.
        trailer_bin = earth.register_container(trailer.tray,
            Vector3(1.24,0.42,2.08),Vector3(0,0.25,-1.093))
        # The tray and the tractor are one coupled unit; letting the tray
        # grind on the tractor's rear is another way the pair locks up.
        trailer.tray.add_collision_exception_with(tractor)
        trailer.tray.add_collision_exception_with(trailer)

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
    env.background_mode = Environment.BG_SKY
    env.sky = ART.BACKDROP.make_sky()
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.43
    env.fog_enabled = true
    env.fog_light_color = Color("#d3d8c2")
    env.fog_density = 0.00035
    env.fog_sky_affect = 0.0
    env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    env.adjustment_enabled = true
    env.adjustment_brightness = 1.0
    env.adjustment_saturation = 1.0
    env.adjustment_contrast = 1.0
    world.environment = env
    add_child(world)
    camera = Camera3D.new()
    camera.name = "PaintedFollowCamera"
    add_child(camera)
    camera.current = true
    camera.fov = 65.0
    camera.far = 2800.0
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
    help_panel.size = Vector2(650,212)
    help_panel.visible = false
    canvas.add_child(help_panel)
    var instructions := Label.new()
    instructions.position = Vector2(14,12)
    instructions.add_theme_font_size_override("font_size",15)
    instructions.add_theme_color_override("font_color",Color("#f9ecd5"))
    instructions.text = "LANDWORKS  •  CONTROLS\n" +         "Tab / Triangle — change machine     Z/C — orbit camera\n" +         "Tractor: W/S travel, A/D steer; PS R2/L2 travel + left stick\n" +         "Excavator: W/S tracks, A/D differential pivot\n" +         "I/K boom  |  O/L stick  |  P/; bucket  |  Q/E slew\n" +         "G / Square — bucket hook     R — dump soil     F12 — old yard\n" +         "Mouse wheel — zoom     F2 — inspection view     F1 — close help"
    instructions.text += "\nT/Y — dozer blade   [ / ] — boom offset   N/B — tip trailer"
    instructions.text += "\nExcavator: keypad 8/2 boom, 4/6 bucket, 7/9 boom offset"
    instructions.text += "\n           W/X arm   A/D slew   S stop tracks"
    instructions.text += "\n           arrows: left/right track (Shift reverses), up/down blade"
    instructions.text += "\nF8 — reset all machines to start (the ground stays as dug)"
    instructions.text += "\nH — drop the hitch; reverse the ball under the ring to re-couple"
    instructions.text += "\nG — release the strap; it takes hold on its own near a load"
    instructions.text += "\nV — cab/follow   Arrows / right-drag — look   Home — centre"
    help_panel.add_child(instructions)

func _select_machine(which: int) -> void:
    if rig_visuals != null and rig_visuals.cab != null:
        rig_visuals.cab.set_seated(false)
        camera.current = true
    active_machine = which
    # Switch to the left-front quarter when operating the excavator: it
    # shows its boom silhouette, side cab glazing and seated driver,
    # instead of an almost opaque rear counterweight.
    orbit_yaw = 0.72 if which == 0 else -0.94
    tractor.controlled = which == 0 and not smoke
    digger.operated = which == 1 and not smoke
    camera_zoom = 1.0

func _unhandled_input(event: InputEvent) -> void:
    var cab: Node3D = rig_visuals.cab
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_V and active_machine == 1:
            cab.set_seated(not cab.seated)
            if not cab.seated: camera.current = true
        if event.keycode == KEY_HOME: cab.reset_look()
    if cab.seated:
        if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
            cab.look(-event.relative.x*0.12,-event.relative.y*0.12)
        return
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            camera_zoom = clampf(camera_zoom*0.88,0.48,1.65)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            camera_zoom = clampf(camera_zoom/0.88,0.48,1.65)

func _current_surface(x: float) -> Dictionary:
    return SOIL.profile("soft_clay" if x > CLAY_START_X else "hardpack")

func _physics_process(delta: float) -> void:
    # Machine and loose-body contact forces all run in the same Jolt world.
    tractor.ground_mu_override = 0.53 if tractor.global_position.x > CLAY_START_X else T.GROUND_MU
    _update_hitch()
    digger.update_strap(props)
    digger.arrows_look = rig_visuals != null and rig_visuals.cab != null and rig_visuals.cab.seated
    if settle_tick >= 0:
        settle_tick += 1
        if settle_tick >= 180:
            _resettle_start_state()
            settle_tick = -1
    digger.surface_profile = _current_surface(digger.undercarriage.global_position.x)
    # Trailer tipping: real hinge torque, not a scripted tray transform.
    if not smoke and is_instance_valid(trailer):
        trailer.command_tip(float(Input.is_key_pressed(KEY_N))
            - float(Input.is_key_pressed(KEY_B)), delta)
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
    var boom_change: float = absf(rad_to_deg(digger._joint_angle("boom") - initial_boom))
    max_boom_change = maxf(max_boom_change, boom_change)
    if smoke_time <= BOOM_COMMAND_WINDOW_S:
        max_boom_change_commanded = maxf(max_boom_change_commanded, boom_change)
    var hitch_gap := tractor.to_global(TRACTOR_HITCH_LOCAL).distance_to(
        trailer.to_global(trailer.HITCH_POINT))
    # Only a coupled hitch has an error to report; an uncoupled trailer is
    # simply parked, not a joint that has pulled apart.
    if hitch_coupler != null and hitch_coupler.is_coupled():
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
    if earth.material_mechanics:
        _update_material_mechanics(delta)
        _update_blade_push()
        _update_tray_discharge(delta)
        return
    # Engine-driven physical lip path: no soil is excavated by an animation or
    # player pressing a magical remove-soil button. The bucket must reach an
    # actual bank and move through it while below the soil surface.
    var lip: Vector3 = digger.bucket.to_global(digger.BUCKET_TIP)
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
            soil_bucket_material = ("clay" if (
                float(result.get("clay_m3",0.0)) >
                float(result.get("gravel_m3",0.0))) else "gravel")
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

func _cut_budget(lip: Vector3, direction: Vector3, delta: float) -> Dictionary:
    var force := INF
    var power := 0.0
    var active := false
    for key in ["boom","stick","bucket"]:
        var speed := absf(float(digger.hydraulic_state.get("speeds",{}).get(key,0.0)))
        if speed < 0.005: continue
        active = true
        var body: Node3D = digger.get(key)
        var axis: Vector3 = body.global_basis.x.normalized()
        var lever := absf((lip-body.global_position).cross(direction).dot(axis))
        var torque := float(digger.hydraulic_state.get("torque_caps",{}).get(key,0.0))
        force = minf(force,torque/maxf(lever,0.15))
        power += torque*speed
    power = minf(power,float(digger.hydraulic_state.get("hydraulic_power_kw",0.0))*1000.0)
    return {"force":force if active else 0.0,"work":power*delta}

func _cutting_edge_local() -> Vector3:
    # The steel that actually meets the soil. The rigged model carries a
    # Bucket_Tip socket on the tooth line, 500 mm below and 800 mm ahead of
    # the bucket pin, so the edge is no longer a radial point on -Z.
    if rig_visuals != null:
        var tip: Vector3 = rig_visuals.bucket_tip_local()
        if tip.length_squared() > 0.0001:
            return tip
    var toe := digger.bucket.get_node_or_null("GroundHandlingToe") as CollisionShape3D
    if toe != null and toe.shape is BoxShape3D:
        var size: Vector3 = (toe.shape as BoxShape3D).size
        return toe.position + Vector3(0.0, -0.5*size.y, -0.5*size.z)
    return digger.BUCKET_TIP

func _update_material_mechanics(delta: float) -> void:
    var lip: Vector3 = digger.bucket.to_global(_cutting_edge_local())
    if not previous_bucket_lip_valid:
        var state := PhysicsServer3D.body_get_direct_state(digger.bucket.get_rid())
        if state != null: bucket_empty_center = state.center_of_mass_local
        previous_bucket_lip = lip
        previous_bucket_lip_valid = true
        return
    var movement := lip-previous_bucket_lip
    var room := maxf(0.0,earth.MAX_BUCKET_M3-earth.bucket_inventory.volume())
    # Previous tick applied resistance. Commit only the measured solved path,
    # never the predicted path, and never backward/unpowered/stalled motion.
    if not pending_soil_contact.is_empty() and movement.length()>0.00001:
        var direction: Vector3 = pending_soil_contact["direction"]
        if movement.normalized().dot(direction)>0.5:
            var proposal: Dictionary = earth.propose_cut(previous_bucket_lip,lip,digger.BUCKET_WIDTH,room)
            var result: Dictionary = earth.commit_cut(proposal,
                float(pending_soil_contact["force"]),float(pending_soil_contact["work"]))
            maximum_excavated_m3 += float(result["volume_m3"])
    # Predict only to establish the next contact reaction; nothing is removed.
    var arm: Vector3 = lip-digger.bucket.global_position
    var velocity: Vector3 = digger.bucket.linear_velocity+digger.bucket.angular_velocity.cross(arm)
    pending_soil_contact.clear()
    if velocity.length()>0.001 and earth.has_position(lip) and room>0.00001:
        var direction := velocity.normalized()
        var proposal: Dictionary = earth.propose_cut(lip,lip+velocity*delta,digger.BUCKET_WIDTH,room)
        var resistance := float(proposal.get("force_n",0.0))
        if resistance>0.0:
            pending_soil_contact = _cut_budget(lip,direction,delta)
            pending_soil_contact["direction"] = direction
            # With the arm powered, the soil can only push back with the force
            # the thinner slice it actually takes mobilises (commit_cut scales
            # the slice to the same budget). Unpowered pushing (tracks only)
            # still meets the full bank resistance, so the bucket cannot
            # ghost through a bank without cutting.
            var budget_force := float(pending_soil_contact["force"])
            var reaction := resistance if budget_force <= 0.0 else minf(resistance,budget_force)
            digger.bucket.apply_force(-direction*reaction,arm)
    previous_bucket_lip = lip
    soil_bucket_material = earth.bucket_inventory.kind()
    var manual_dump := spoil_dump_request or (not smoke and active_machine==1 and Input.is_key_pressed(KEY_R))
    var opening: Vector3 = -digger.bucket.global_basis.y.normalized()
    var gravity_release := maxf(0.0,opening.dot(Vector3.DOWN)-0.12)
    var adhesion: float = earth.bucket_inventory.weighted("steel_adhesion_pa")
    # Provisional contact area. Wet cohesive material discharges more slowly;
    # R remains an explicit debugging override for sticky carryback.
    var retained_force := adhesion*0.035
    var weight: float = earth.bucket_inventory.mass()*9.81
    var flow := 1.0 if manual_dump else gravity_release*clampf((weight-retained_force)/maxf(weight,1.0),0.0,1.0)
    if flow>0.0:
        var released: float = earth.release_soil(lip+Vector3.UP*0.14,
            velocity,minf(earth.bucket_inventory.volume(),delta*0.115*flow),soil_bucket_material)
        maximum_dumped_m3 += released
    soil_bucket_m3 = earth.bucket_inventory.volume()
    # Soil mass loads the real rigid body, preserving its instantaneous velocity.
    # Detailed shell dimensions supply an approximate local contents centre.
    var payload: float = earth.bucket_inventory.mass()
    var new_mass := bucket_empty_mass+payload
    var old_mass: float = digger.bucket.mass
    if new_mass > old_mass:
        # Captured bank soil starts at rest: conserve linear momentum when
        # attaching it. Discharged parcels inherit the bucket's velocity.
        digger.bucket.linear_velocity *= old_mass/new_mass
    digger.bucket.mass = new_mass
    if payload < 1e-6:
        digger.bucket.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_AUTO
    else:
        digger.bucket.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
        digger.bucket.center_of_mass = (bucket_empty_center*bucket_empty_mass+Vector3(0,0.20,-0.40)*payload)/new_mass
    # Compatibility diagnostic only; new tests assert constituent kg directly.
    material_diagnostic_clock += delta
    if material_diagnostic_clock >= 0.5:
        soil_mass_error_m3 = earth.mass_error_kg()/1700.0
        material_diagnostic_clock = 0.0

func _finish_smoke() -> void:
    smoke_file.close()
    var f := FileAccess.open(_out("sandbox_summary.csv"), FileAccess.WRITE)
    if f == null:
        push_error("Failed to write sandbox physical test summary")
        get_tree().quit(5)
        return
    f.store_csv_line(PackedStringArray(["tractor_travel_m", "excavator_travel_m",
        "crate_travel_m", "boom_change_deg", "boom_commanded_deg",
        "max_hitch_error_m",
        "max_chassis_tilt_deg", "peak_hydraulic_pressure_mpa", "test_duration_s"]))
    f.store_csv_line(PackedStringArray([
        "%.3f" % max_tractor_travel, "%.3f" % max_crawler_travel,
        "%.3f" % max_prop_travel, "%.3f" % max_boom_change,
        "%.3f" % max_boom_change_commanded,
        "%.3f" % max_hitch_error, "%.3f" % max_tilt,
        "%.3f" % peak_pressure, "%.3f" % smoke_time
    ]))
    f.close()
    print("LANDWORKS_SANDBOX_TEST_COMPLETE ", _out("sandbox_summary.csv"))
    get_tree().quit(0)

func _process(delta: float) -> void:
    if rig_visuals.cab.seated:
        rig_visuals.cab.look(
            (float(Input.is_key_pressed(KEY_LEFT))-float(Input.is_key_pressed(KEY_RIGHT)))*delta*65.0,
            (float(Input.is_key_pressed(KEY_UP))-float(Input.is_key_pressed(KEY_DOWN)))*delta*50.0)
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
        var reset_pressed := Input.is_key_pressed(KEY_F8)
        if reset_pressed and not reset_down:
            hook_status = reset_machines()
        reset_down = reset_pressed
        var joy := CI.joy_id()
        var hook_pressed := active_machine == 1 and (
            Input.is_key_pressed(KEY_G) or
            (joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_X)))
        if hook_pressed and not hook_down:
            hook_status = digger.toggle_hook(props)
        hook_down = hook_pressed
        var drop_pressed := Input.is_key_pressed(KEY_H)
        if drop_pressed and not drop_down and hitch_coupler != null:
            if hitch_coupler.is_coupled():
                hitch_coupler.release()
                hook_status = "Hitch dropped: drive clear, then reverse back on"
            else:
                hook_status = "Hitch open: reverse the ball under the ring"
        drop_down = drop_pressed
        if active_machine == 0:
            orbit_yaw -= CI.axis(joy, JOY_AXIS_RIGHT_X) * delta * 1.4
        orbit_yaw += (float(Input.is_key_pressed(KEY_C)) -
            float(Input.is_key_pressed(KEY_Z))) * delta * 1.2
    var target: Node3D = tractor if active_machine == 0 else digger.undercarriage
    var focus := target.global_position + (
        Vector3(0,0.65,-0.20) if active_machine == 0 else Vector3(0,1.30,-1.45))
    if inspection_view and active_machine == 1:
        focus.z -= 0.75
    var inspect_pressed := Input.is_key_pressed(KEY_F2)
    if inspect_pressed and not inspection_down:
        inspection_view = not inspection_view
        orbit_yaw = (-2.30 if active_machine == 0 else -1.95) if inspection_view else (0.72 if active_machine == 0 else -0.94)
    inspection_down = inspect_pressed
    var dist := (4.9 if active_machine == 0 else 7.9)*camera_zoom
    var height := (1.65 if active_machine == 0 else 2.6)*camera_zoom
    if inspection_view:
        height = 0.65*camera_zoom
        camera.fov = 46.0
    else:
        camera.fov = 58.0
    var wanted := focus + Vector3(sin(orbit_yaw) * dist, height, cos(orbit_yaw) * dist)
    camera.global_position = camera.global_position.lerp(wanted, clampf(delta * 4.5, 0.0, 1.0))
    camera.look_at(focus, Vector3.UP)
    rig_visuals.update_bucket_fill(soil_bucket_m3,soil_bucket_material)
    var speed: float = tractor.linear_velocity.length() * 3.6
    var ground_label: String = str(_current_surface(target.global_position.x)["name"])
    if active_machine == 0:
        status.text = "KUBOTA B7100 HST  •  FARM WORKS\n"
        status.text += "Speed %.1f km/h   |   HST %.1f kW   |   %s\n" % [
            speed, tractor.last_hst_power_kw,ground_label]
        var coupled: bool = hitch_coupler != null and hitch_coupler.is_coupled()
        var hitch_text: String = "Hitched" if coupled else (
            "READY — hold still to couple" if hitch_coupler != null and hitch_coupler.in_zone()
            else "Unhitched (H)")
        status.text += "400 kg trailer  •  %s  •  Tab switch  •  F1 controls" % hitch_text
    else:
        status.text = "KUBOTA KX080-3  •  EARTHMOVING\n"
        status.text += "Hyd %.1f MPa  |  %.1f L/min  |  Ground %d/4\n" % [
            float(digger.hydraulic_state.get("pressure_mpa",0.0)),
            float(digger.hydraulic_state.get("flow_lpm",0.0)),
            digger.ground_contact_count]
        status.text += "Bucket %.0f L  |  Dug %.0f L  |  F1 controls" % [
            soil_bucket_m3*1000.0,maximum_excavated_m3*1000.0]
        status.text += "\nV: cab/follow  |  Soil %.0f kg" % earth.bucket_inventory.mass()

func _update_blade_push() -> void:
    # The dozer blade cuts below grade and pushes the spoil ahead of itself.
    # The force available is whatever the tracks actually developed this tick,
    # so a blade load the machine cannot push simply stalls.
    if not is_instance_valid(digger.dozer_blade):
        return
    var edge: Vector3 = digger.dozer_blade.to_global(BLADE_EDGE_LOCAL)
    if not previous_blade_edge_valid:
        previous_blade_edge = edge
        previous_blade_edge_valid = true
        return
    var start := previous_blade_edge
    previous_blade_edge = edge
    var movement := edge-start
    if movement.length() < 0.0005 or not earth.has_position(edge):
        return
    var direction := movement.normalized()
    var forward: Vector3 = -digger.undercarriage.global_basis.z.normalized()
    if direction.dot(forward) < 0.3:
        return
    var force := absf(digger.last_track_left_force_n)+absf(digger.last_track_right_force_n)
    if force <= 1.0:
        return
    var result: Dictionary = earth.blade_push(start,edge,BLADE_WIDTH_M,
        force,force*movement.length(),edge+direction*0.55,direction)
    blade_pushed_m3 += float(result["volume_m3"])

func _update_tray_discharge(delta: float) -> void:
    # Spoil leaves the tray over the tailgate once it is tipped far enough.
    # Nothing is teleported: the load becomes loose material at the rear sill
    # and falls under the same particle solver as every other dump.
    if trailer_bin < 0 or not is_instance_valid(trailer.tray):
        return
    var held: float = earth.container_volume_m3(trailer_bin)
    if held <= 0.000001:
        return
    var tip: float = trailer.tip_angle_rad()
    if tip < 0.30:
        return
    var rate := 0.16*clampf((tip-0.30)/0.45,0.0,1.0)
    var sill: Vector3 = trailer.tray.to_global(Vector3(0,0.12,0.12))
    var direction: Vector3 = (trailer.tray.global_basis.z-Vector3.UP*0.35).normalized()
    tray_discharged_m3 += earth.discharge_container(trailer_bin,sill,direction,
        minf(held,rate*delta))

func _update_hitch() -> void:
    # The tow ball looks for the trailer's ring every tick. Capture is wide
    # enough to forgive a rough reverse and still refuses a load you are
    # driving past, because the pair must be near rest relative to each other.
    if hitch_coupler == null or not is_instance_valid(trailer):
        return
    hitch_coupler.update_capture(tractor.to_global(TRACTOR_HITCH_LOCAL), tractor,
        [{"body":trailer,"point":trailer.to_global(trailer.HITCH_POINT)}])
    trailer.hitched = hitch_coupler.is_coupled()

func _resettable_bodies() -> Array[RigidBody3D]:
    var bodies: Array[RigidBody3D] = []
    for body in [tractor, trailer, trailer.tray, digger.undercarriage,
            digger.upper, digger.king_post, digger.boom, digger.stick,
            digger.bucket, digger.dozer_blade]:
        if is_instance_valid(body):
            bodies.append(body)
    for item in props:
        if is_instance_valid(item):
            bodies.append(item)
    return bodies

func _capture_start_state() -> void:
    start_state.clear()
    for body in _resettable_bodies():
        start_state[body] = body.global_transform
    start_targets = digger.target_angles.duplicate()
    start_tip = trailer.tip_target

func reset_machines() -> String:
    # A deliberate restore, not a physics path: every machine body is placed
    # back where it started and its velocities cleared. Two things make that
    # safe rather than a cheat. Anything the machines were carrying is first
    # released as loose material where it actually stood, so the reset cannot
    # create or destroy soil; and the solver's cutting-edge history is dropped,
    # so the jump home is never mistaken for an enormous cut on the next tick.
    # The ground itself is left exactly as dug.
    if digger.strap != null:
        digger.strap.release()
    if hitch_coupler != null:
        hitch_coupler.release()
    if earth != null:
        var carried: float = earth.bucket_inventory.volume()
        if carried > 0.0:
            earth.release_soil(digger.hook_point(), Vector3.DOWN, carried)
        if trailer_bin >= 0 and is_instance_valid(trailer.tray):
            var held: float = earth.container_volume_m3(trailer_bin)
            if held > 0.0:
                earth.discharge_container(trailer_bin,
                    trailer.tray.to_global(Vector3(0, 0.45, -1.0)), Vector3.DOWN, held)
    for body in start_state:
        if not is_instance_valid(body):
            continue
        body.global_transform = start_state[body]
        body.linear_velocity = Vector3.ZERO
        body.angular_velocity = Vector3.ZERO
        body.force_update_transform()
    digger.target_angles = start_targets.duplicate()
    digger.slew_target_rad = 0.0
    trailer.tip_target = start_tip
    previous_bucket_lip_valid = false
    previous_blade_edge_valid = false
    previous_blade_edge = Vector3.ZERO
    pending_soil_contact.clear()
    # Releasing leaves the coupling disarmed until the pair separates, which
    # is right for a dropped trailer but wrong here: the restore puts the ring
    # straight back on the ball, so without re-arming it could never couple.
    if hitch_coupler != null:
        hitch_coupler.armed = true
    _update_hitch()
    reset_count += 1
    return "Machines reset to start condition (the ground stays as you dug it)"

func _resettle_start_state() -> void:
    # Machines and loads settle in the first moments: the crate drops onto the
    # ground, the tray takes up on its hinge. Fold that into the snapshot so
    # F8 restores the scene as it looks when you take the controls, rather
    # than a pre-settle pose that immediately sags again. A body that has
    # already moved more than a metre was moved by the player, so its spawn
    # pose stays the thing to restore.
    for body in start_state:
        if not is_instance_valid(body):
            continue
        if body.global_position.distance_to(Vector3(start_state[body].origin)) <= 1.0:
            start_state[body] = body.global_transform
    start_settled = true
