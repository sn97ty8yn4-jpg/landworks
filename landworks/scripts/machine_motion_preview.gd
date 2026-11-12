# Native Godot renderer capture. Only powered joint targets are commanded;
# no machine transform is animated for the recording.
extends SceneTree

const SCENE = preload("res://landworks/scenes/sandbox_world.tscn")

func _initialize() -> void:
    root.size = Vector2i(1366,768)
    var sandbox := SCENE.instantiate()
    root.add_child.call_deferred(sandbox)
    call_deferred("_record",sandbox)

func _record(sandbox: Node3D) -> void:
    await process_frame
    var output := "user://motion"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--preview-dir="):
            output = arg.trim_prefix("--preview-dir=")
    DirAccess.make_dir_recursive_absolute(output)
    sandbox._select_machine(1)
    sandbox.orbit_yaw = -1.95
    sandbox.inspection_view = true
    sandbox.camera_zoom = 1.12
    for n in range(20):
        await process_frame
    for frame in range(36):
        var machine: Node3D = sandbox.digger
        machine.target_angles["boom"] = 0.74 if frame < 20 else 0.18
        machine.target_angles["stick"] = -0.98 if frame < 20 else -0.55
        machine.target_angles["bucket"] = 0.52 if frame < 20 else -0.48
        await process_frame
        await RenderingServer.frame_post_draw
        var shot := root.get_texture().get_image()
        var error := shot.save_png(output.path_join("frame_%03d.png"%frame))
        if error != OK:
            push_error("Could not save real machinery motion capture")
            quit(2)
            return
    print("MACHINE_MOTION_RENDERED frames=36 fixed_fps=8")
    quit()
