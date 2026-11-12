# Standalone asset inspection stage. Displays unmodified donor GLBs.
# It is intentionally NOT a Kubota simulator or a rigged model export.
extends Node3D

const CI = preload("res://landworks/scripts/machine_input.gd")
const M = preload("res://landworks/scripts/mesh_factory.gd")
const FILES = [
    "res://landworks/assets/source/garden-tractor-with-trailer.glb",
    "res://landworks/assets/source/compact-tracked-excavator.glb"
]
const NAMES = ["Garden tractor + trailer donor", "Compact tracked excavator donor"]

var selected: int = 0
var holder: Node3D
var camera: Camera3D
var hud: Label
var toggle_latched: bool = false
var focus: Vector3 = Vector3(0, 1, 0)
var orbit_distance: float = 8.0
var orbit_yaw: float = 0.65
var orbit_height: float = 0.34

func _ready() -> void:
    var floor_body := StaticBody3D.new()
    add_child(floor_body)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(38, 0.2, 38)
    shape.shape = box
    shape.position.y = -0.2
    floor_body.add_child(shape)
    M.block(self, Vector3(38, 0.09, 38), Vector3(0, -0.07, 0), Color("#728368"))
    for i in range(-8, 9):
        M.block(self, Vector3(0.015, 0.006, 17), Vector3(float(i), 0.006, 0), Color("#83937a"))
        M.block(self, Vector3(17, 0.006, 0.015), Vector3(0, 0.006, float(i)), Color("#83937a"))
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -35, 0)
    light.light_energy = 1.7
    add_child(light)
    var ambient := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#bed2da")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#e4e7e9")
    env.ambient_light_energy = 0.7
    ambient.environment = env
    add_child(ambient)
    camera = Camera3D.new()
    camera.fov = 60
    add_child(camera)
    camera.current = true
    var ui := CanvasLayer.new()
    add_child(ui)
    var back := ColorRect.new()
    back.position = Vector2(20, 20)
    back.size = Vector2(1120, 108)
    back.color = Color(0.08, 0.12, 0.12, 0.75)
    ui.add_child(back)
    hud = Label.new()
    hud.position = Vector2(36, 29)
    hud.add_theme_font_size_override("font_size", 20)
    ui.add_child(hud)
    _show_asset()

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_F1:
            selected = 0
            _show_asset()
        elif event.keycode == KEY_F2:
            selected = 1
            _show_asset()

func _show_asset() -> void:
    if holder != null:
        remove_child(holder)
        holder.queue_free()
    holder = Node3D.new()
    holder.name = "DonorAssetPreview"
    add_child(holder)
    var path: String = FILES[selected]
    if not ResourceLoader.exists(path):
        hud.text = "LANDWORKS — " + NAMES[selected] + " | MODEL NOT DOWNLOADED\n"
        hud.text += "Run tools/windows/DOWNLOAD_MODELS_WINDOWS.bat or read docs/ASSET_SOURCES.md\n"
        hud.text += "F1 tractor · F2 excavator · Triangle swap · left stick orbit · triggers zoom"
        focus = Vector3(0, 1.1, 0)
        orbit_distance = 8.0
        return
    var resource := ResourceLoader.load(path)
    if not (resource is PackedScene):
        hud.text = "Cannot import " + path + "; check Godot Import dock / source GLB"
        return
    var scene: Node = resource.instantiate()
    if not (scene is Node3D):
        scene.free()
        hud.text = "Imported scene root is not Node3D; inspect GLB"
        return
    holder.add_child(scene)
    var bounds := _get_world_bounds(scene)
    if bounds.size.length() > 0.001:
        # Shift into the preview stage without changing source units or scaling.
        holder.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
        focus = Vector3(0, bounds.size.y * 0.5, 0)
        orbit_distance = maxf(5.0, bounds.size.length() * 1.3)
    hud.text = "LANDWORKS — " + NAMES[selected] + " | ORIGINAL CC0 DONOR GLB\n"
    hud.text += "Raw mesh preview, not a playable/segmented Kubota model\n"
    hud.text += "F1 tractor · F2 excavator · Triangle swap · A/D or left stick orbit · W/S or triggers zoom"

func _get_world_bounds(root: Node) -> AABB:
    var nodes: Array[Node] = [root]
    var total := AABB()
    var found := false
    while not nodes.is_empty():
        var node: Node = nodes.pop_back()
        for c in node.get_children():
            nodes.append(c)
        if node is MeshInstance3D:
            var mesh := node as MeshInstance3D
            if mesh.mesh == null:
                continue
            var aabb: AABB = mesh.get_aabb()
            for i in range(8):
                var point: Vector3 = mesh.to_global(aabb.get_endpoint(i))
                if not found:
                    total = AABB(point, Vector3.ZERO)
                    found = true
                else:
                    total = total.expand(point)
    return total

func _process(delta: float) -> void:
    var next := CI.switch_machine()
    if next and not toggle_latched:
        selected = 1 - selected
        _show_asset()
    toggle_latched = next
    var orbit_input := CI.steering()
    orbit_yaw += orbit_input * delta * 1.1
    var up := float(Input.is_key_pressed(KEY_W))
    var down := float(Input.is_key_pressed(KEY_S))
    var id := CI.joy_id()
    var joy_zoom := CI.trigger(id, JOY_AXIS_TRIGGER_RIGHT) - CI.trigger(id, JOY_AXIS_TRIGGER_LEFT)
    orbit_distance = clampf(orbit_distance - (up - down + joy_zoom) * delta * 5.0, 2.0, 45.0)
    var position3 := focus + Vector3(sin(orbit_yaw) * orbit_distance, orbit_distance * orbit_height, cos(orbit_yaw) * orbit_distance)
    camera.global_position = position3
    camera.look_at(focus, Vector3.UP)
