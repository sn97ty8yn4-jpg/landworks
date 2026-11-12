# Real Godot renderer screenshots — not concept art or generated image.
# Run with xvfb-run and GL Compatibility renderer (not headless null renderer).
extends SceneTree

const SCENE = preload("res://landworks/scenes/sandbox_world.tscn")

func _initialize() -> void:
    root.size = Vector2i(1366,768)
    var sandbox := SCENE.instantiate()
    root.add_child.call_deferred(sandbox)
    call_deferred("_capture",sandbox)

func _capture(sandbox: Node3D) -> void:
    await process_frame
    var output := "user://"
    var detail_only := false
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--preview-dir="):
            output = arg.trim_prefix("--preview-dir=")
        elif arg == "--detail-only":
            detail_only = true
    if not output.begins_with("user://"):
        DirAccess.make_dir_recursive_absolute(output)
    for view_id in range(2 if detail_only else 0,4):
        var machine_id := view_id%2
        var detail := view_id >= 2
        sandbox._select_machine(machine_id)
        sandbox.inspection_view = detail
        sandbox.camera_zoom = (0.80 if machine_id == 0 else 1.12) if detail else 1.0
        if detail:
            sandbox.orbit_yaw = -2.30 if machine_id == 0 else -1.95
        for n in range(20):
            await process_frame
        # Let compatibility renderer finish the submitted 3D viewport.
        await RenderingServer.frame_post_draw
        var shot := root.get_texture().get_image()
        if shot == null or shot.get_width() < 1000:
            push_error("Invalid rendered screenshot — GL compatibility context missing")
            quit(2)
            return
        var filename := "landworks_tractor" if machine_id==0 else "landworks_excavator"
        filename += "_detail.png" if detail else ".png"
        var target := output.path_join(filename)
        var error := shot.save_png(target)
        if error != OK:
            push_error("Unable to write rendered preview: "+target)
            quit(3)
            return
        print("RENDERED_FRAME_OK ",target," ",shot.get_width(),"x",shot.get_height())
    sandbox._select_machine(1)
    sandbox.machine_visuals.cab.set_seated(true)
    for look_down in [false,true]:
        sandbox.machine_visuals.cab.pitch = -45.0 if look_down else -15.0
        sandbox.machine_visuals.cab.look(0,0)
        for frame in range(8): await process_frame
        await RenderingServer.frame_post_draw
        var name := "landworks_cab_controls.png" if look_down else "landworks_cab.png"
        root.get_texture().get_image().save_png(output.path_join(name))
        print("RENDERED_FRAME_OK ",output.path_join(name))
    quit(0)
