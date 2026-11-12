# Exercise the shipped pad using player keyboard input, without moving terrain.
extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
var world: Node3D
var maximum_gap := 0.0
var maximum_speed := 0.0
func _initialize() -> void: call_deferred("_run")
func key(code: int, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = pressed
    Input.parse_input_event(event)
func exercise(codes: Array, frames: int, label: String) -> void:
    for code in codes: key(code,true)
    for frame in range(frames):
        await physics_frame
        var e = world.digger
        var gap: float = e.stick.to_global(Vector3(0,0,-e.STICK_LENGTH)).distance_to(e.bucket.global_position)
        maximum_gap = maxf(maximum_gap,gap)
        maximum_speed = maxf(maximum_speed,e.bucket.linear_velocity.length())
    for code in codes: key(code,false)
    if DisplayServer.get_name() != "headless":
        for frame in range(4): await process_frame
        await RenderingServer.frame_post_draw
        DirAccess.make_dir_recursive_absolute("res://validation/playable-dig")
        root.get_texture().get_image().save_png("res://validation/playable-dig/"+label+".png")
    var e = world.digger
    var lip: Vector3 = e.bucket.to_global(e.BUCKET_TIP)
    print("PLAYER_DIG ",label," lip=",lip," ground=",world.earth.surface_height(lip),
        " cut=",world.maximum_excavated_m3," gap=",maximum_gap," speed=",maximum_speed,
        " targets=",e.target_angles)
func _run() -> void:
    world = WORLD.instantiate()
    root.add_child(world)
    world._select_machine(1)
    world.inspection_view = true
    world.orbit_yaw = -1.95
    await exercise([],120,"settle")
    await exercise([KEY_I],180,"raise")
    await exercise([KEY_W],840,"approach")
    await exercise([KEY_K],480,"lower")
    await exercise([KEY_L,KEY_P],240,"curl")
    await exercise([KEY_I],180,"lift")
    var good: bool = world.maximum_excavated_m3 > 0.01 and maximum_gap < 0.04
    print("PLAYABLE_DIG ","PASS" if good else "FAIL")
    quit(0 if good else 1)
