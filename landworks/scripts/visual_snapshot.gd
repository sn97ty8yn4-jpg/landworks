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
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--preview-dir="):
            output = arg.trim_prefix("--preview-dir=")
    if not output.begins_with("user://"):
        DirAccess.make_dir_recursive_absolute(output)
    for machine_id in [0,1]:
        sandbox._select_machine(machine_id)
        for n in range(20):
            await process_frame
        # Let compatibility renderer finish the submitted 3D viewport.
        await RenderingServer.frame_post_draw
        var shot := root.get_texture().get_image()
        if shot == null or shot.get_width() < 1000:
            push_error("Invalid rendered screenshot — GL compatibility context missing")
            quit(2)
            return
        var target := output.path_join("landworks_tractor.png" if machine_id==0
            else "landworks_excavator.png")
        var error := shot.save_png(target)
        if error != OK:
            push_error("Unable to write rendered preview: "+target)
            quit(3)
            return
        print("RENDERED_FRAME_OK ",target," ",shot.get_width(),"x",shot.get_height())
    # Separate real-engine seated screenshot: verifies operator eye placement,
    # cab framing, sightline and HUD without forcing photo-only rendering.
    sandbox._select_machine(1)
    sandbox._set_cab_view(true)
    for n in range(24):
        await process_frame
    await RenderingServer.frame_post_draw
    var cab_image := root.get_texture().get_image()
    if cab_image == null or cab_image.get_width() < 1000:
        push_error("Invalid seated cab screenshot")
        quit(4)
        return
    var cab_target := output.path_join("landworks_kx080_cab.png")
    if cab_image.save_png(cab_target) != OK:
        push_error("Unable to save cab screenshot")
        quit(5)
        return
    print("RENDERED_FRAME_OK ",cab_target," ",cab_image.get_width(),"x",cab_image.get_height())
    quit(0)
