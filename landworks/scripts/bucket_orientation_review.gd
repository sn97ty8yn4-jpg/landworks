# Diagnostic views of the imported bucket in its physics-local coordinates.
extends SceneTree
func _initialize() -> void:
    call_deferred("_render")

func _render() -> void:
    var scene := Node3D.new()
    root.add_child(scene)
    var world := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("#d5dfdf")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color.WHITE
    env.ambient_light_energy = 0.7
    world.environment = env
    scene.add_child(world)
    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-35,-45,0)
    key.light_energy = 1.4
    scene.add_child(key)
    var part: Node3D = load("res://landworks/assets/engineered/kx080_bucket.glb").instantiate()
    scene.add_child(part)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 2.8
    scene.add_child(camera)
    camera.current = true
    var output := "res://validation/bucket-review/original"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
        if arg == "--flip": part.rotation.z = PI
    DirAccess.make_dir_recursive_absolute(output)
    var views := [Vector3(3,0,-0.4),Vector3(-3,0,-0.4),
        Vector3(1.6,1.5,-2.0),Vector3(1.6,-1.5,-2.0)]
    for i in range(views.size()):
        camera.position = views[i]
        camera.look_at(Vector3(0,0,-0.4),Vector3.UP)
        for frame in range(3): await process_frame
        await RenderingServer.frame_post_draw
        var shot: Image = root.get_texture().get_image()
        shot.save_png(output.path_join("bucket_%d.png" % i))
    print("BUCKET_REVIEW_RENDERED ",output)
    quit()
