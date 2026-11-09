# Entry point can run standalone or as the Current Scene in a Tinybox fork.
extends Node3D

const M = preload("res://landworks/scripts/mesh_factory.gd")
const CI = preload("res://landworks/scripts/machine_input.gd")
const Tractor = preload("res://landworks/scripts/tractor.gd")
const Excavator = preload("res://landworks/scripts/excavator.gd")
const FollowCam = preload("res://landworks/scripts/follow_camera.gd")
const PivotDebug = preload("res://landworks/scripts/pivot_debug.gd")

var tractor: RigidBody3D
var excavator: RigidBody3D
var cam: Camera3D
var hud: Label
var selected: int = 0
var switch_latched: bool = false
var pivot_debug_tractor: Node3D
var pivot_debug_excavator: Node3D
var pivot_debug_latched: bool = false
var pivot_debug_enabled: bool = false
var scene_nav_latched: bool = false

func _ready() -> void:
    _ground()
    _farmyard()
    tractor = Tractor.new()
    tractor.name = "Tractor"
    tractor.position = Vector3(-4, 1.15, 8)
    add_child(tractor)
    excavator = Excavator.new()
    excavator.name = "Excavator"
    excavator.position = Vector3(8, 1.45, -6)
    excavator.rotation.y = -0.4
    add_child(excavator)
    pivot_debug_tractor = PivotDebug.new()
    tractor.add_child(pivot_debug_tractor)
    pivot_debug_tractor.bind_tractor(tractor)
    pivot_debug_excavator = PivotDebug.new()
    excavator.add_child(pivot_debug_excavator)
    pivot_debug_excavator.bind_excavator(excavator)
    cam = FollowCam.new()
    cam.name = "FollowCamera"
    add_child(cam)
    cam.current = true
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -35, 0)
    sun.light_energy = 1.3
    add_child(sun)
    var worldenv := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#a9c3d3")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#e1e5d9")
    env.ambient_light_energy = 0.8
    worldenv.environment = env
    add_child(worldenv)
    _hud()
    _select(0)
    cam.global_position = tractor.global_position + Vector3(1.0, 4.0, 7.0)
    cam.look_at(tractor.global_position, Vector3.UP)

func _ground() -> void:
    var ground := StaticBody3D.new()
    ground.name = "GrassTerrain"
    add_child(ground)
    var col := CollisionShape3D.new()
    var sh := BoxShape3D.new()
    sh.size = Vector3(180, 1, 180)
    col.shape = sh
    col.position.y = -0.5
    ground.add_child(col)
    M.block(ground, Vector3(180, 0.1, 180), Vector3(0, -0.07, 0), Color("#688248"))
    # Non-colliding pale track marks indicate the driving course.
    for i in range(25):
        M.block(self, Vector3(2.2, 0.011, 3.1), Vector3(-16, 0.009, -35 + i * 3), Color("#a8a17c"))
        M.block(self, Vector3(2.2, 0.011, 3.1), Vector3(18, 0.009, -35 + i * 3), Color("#a8a17c"))

func _farmyard() -> void:
    # Workshop, paddock fence, trees; low-poly environment placeholders.
    M.block(self, Vector3(11, 5.5, 10), Vector3(-21, 2.75, -21), Color("#b3aea2"))
    M.block(self, Vector3(11.9, 0.65, 10.9), Vector3(-21, 5.7, -21), Color("#414b57"))
    M.block(self, Vector3(4.2, 3.8, 0.06), Vector3(-21, 1.91, -15.94), Color("#535b5d"))
    for x in [-30.0, -27.0, -24.0, -21.0, -18.0, -15.0, -12.0, -9.0]:
        M.block(self, Vector3(0.10, 1.28, 0.10), Vector3(x, 0.63, 17), Color("#b3a27b"))
    M.block(self, Vector3(21.2, 0.07, 0.08), Vector3(-19.5, 1.0, 17), Color("#b4a680"))
    for i in range(24):
        var px := -40.0 + float(i % 8) * 11.7
        var pz := -37.0 + float(i / 8) * 33.0
        if absf(px + 4.0) < 7.0 and absf(pz - 8.0) < 10.0:
            continue
        M.cylinder(self, 0.23, 3.3, Vector3(px, 1.65, pz), Color("#685038"))
        M.cylinder(self, 1.6, 3.2, Vector3(px, 4.5, pz), Color("#537044"))
    # Three visible soil stockpiles, not yet deformable.
    for x in [-1.5, 1.0, 3.5]:
        var pile := SphereMesh.new()
        pile.radius = 1.3
        pile.height = 1.35
        var mesh := MeshInstance3D.new()
        mesh.mesh = pile
        mesh.material_override = M.paint(Color("#81694a"))
        mesh.position = Vector3(x, 0.51, -20)
        add_child(mesh)

func _hud() -> void:
    var ui := CanvasLayer.new()
    add_child(ui)
    var bg := ColorRect.new()
    bg.color = Color(0.055, 0.075, 0.075, 0.73)
    bg.size = Vector2(900, 151)
    bg.position = Vector2(22, 21)
    ui.add_child(bg)
    hud = Label.new()
    hud.position = Vector2(35, 28)
    hud.add_theme_font_size_override("font_size", 20)
    hud.add_theme_color_override("font_color", Color.WHITE)
    ui.add_child(hud)

func _select(index: int) -> void:
    selected = index
    tractor.set("controlled", selected == 0)
    excavator.set("controlled", selected == 1)
    cam.set("target", tractor if selected == 0 else excavator)
    cam.set("yaw_offset", 0.0)

func _process(_delta: float) -> void:
    var joy := CI.joy_id()
    var drag_demo := Input.is_key_pressed(KEY_F9)
    var push_demo := Input.is_key_pressed(KEY_F10)
    var roll_demo := Input.is_key_pressed(KEY_F11)
    var to_tow_work := Input.is_key_pressed(KEY_F7) or (selected == 0 and joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN))
    var to_exc_work := Input.is_key_pressed(KEY_F8) or (selected == 1 and joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_DOWN))
    var to_bench := Input.is_key_pressed(KEY_F5) or (joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_LEFT))
    var to_lift := Input.is_key_pressed(KEY_F4) or (joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_RIGHT))
    if (to_bench or to_lift or to_tow_work or to_exc_work or drag_demo or push_demo or roll_demo) and not scene_nav_latched:
        if drag_demo or push_demo or roll_demo:
            var chosen := "drag_1000" if drag_demo else ("push_1500" if push_demo else "roll_1000")
            get_tree().set_meta("landworks_work_scenario", chosen)
            get_tree().change_scene_to_file("res://landworks/scenes/excavator_work_lab.tscn")
            return
        if to_exc_work and get_tree().has_meta("landworks_work_scenario"):
            get_tree().remove_meta("landworks_work_scenario")
        var next_scene := "res://landworks/scenes/tractor_work_lab.tscn" if to_tow_work else (
            "res://landworks/scenes/excavator_work_lab.tscn" if to_exc_work else (
            "res://landworks/scenes/physics_comparison_lab.tscn" if to_bench else "res://landworks/scenes/physical_excavator_lab.tscn"))
        get_tree().change_scene_to_file(next_scene)
        return
    scene_nav_latched = to_bench or to_lift or to_tow_work or to_exc_work or drag_demo or push_demo or roll_demo
    var pivot_button := Input.is_key_pressed(KEY_F3) or (joy >= 0 and Input.is_joy_button_pressed(joy, JOY_BUTTON_DPAD_UP))
    if pivot_button and not pivot_debug_latched:
        pivot_debug_enabled = not pivot_debug_enabled
        pivot_debug_tractor.set_markers_visible(pivot_debug_enabled)
        pivot_debug_excavator.set_markers_visible(pivot_debug_enabled)
    pivot_debug_latched = pivot_button
    var currently := CI.switch_machine()
    if currently and not switch_latched:
        _select(1 - selected)
    switch_latched = currently
    if selected == 0:
        var speed: float = tractor.get("speed_kmh")
        hud.text = "LANDWORKS 0.6  |  COMPACT TRACTOR  |  %4.1f km/h\n" % speed
        hud.text += "PS: R2 drive  L2 reverse  left stick steer  right stick camera  △ switch\n"
        hud.text += "Keyboard: W/S drive  A/D steer  TAB switch  F3 pivot guides\n"
        hud.text += "D-pad Down/F7: tractor tow trial | Left/F5: physics comparison"
    else:
        hud.text = "LANDWORKS 0.6  |  8-TON EXCAVATOR  |  JOINTS = VISUAL DEMO\n"
        hud.text += "PS: left stick boom  right stick dipper/bucket  L1/R1 slew  triggers crawl  △ switch\n"
        hud.text += "Keyboard: I/K boom  O/L stick  P/; bucket  Q/E slew  W/S tracks  TAB switch\n"
        hud.text += "D-pad Down/F8: live lift trial | F9: drag 1t | F10: push 1.5t | F11: roll 1t"
