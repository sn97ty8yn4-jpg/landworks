# Render the original artwork through eight compass bearings at two heights.
extends SceneTree
const SCENE = preload("res://landworks/scenes/sandbox_world.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _no_collision(node: Node) -> bool:
    if node is CollisionObject3D or node is CollisionShape3D:
        return false
    for child in node.get_children():
        if not _no_collision(child):
            return false
    return true

func _run() -> void:
    var world: Node3D = SCENE.instantiate()
    root.add_child(world)
    await process_frame
    world.set_process(false)
    world.get_node("GameHUD").hide()
    var decor: Node3D = world.get_node("PaintedCountryside_VisualOnly/OriginalIllustratedLandscape")
    if not _no_collision(decor) or decor.get_child_count() != 4:
        push_error("Landscape must have three belts and a skirt, with no collision nodes")
        quit(1)
        return
    var output := "res://validation/landscape/compass"
    DirAccess.make_dir_recursive_absolute(output)
    for height in [1.7,30.0]:
        for bearing in range(8):
            var angle := float(bearing)*TAU/8.0
            var direction := Vector3(sin(angle),-0.08,-cos(angle)).normalized()
            # Elevated pass also samples the map edge to expose parallax gaps.
            world.camera.position = Vector3(60 if height > 2 else 20,height,10)
            world.camera.look_at(world.camera.position+direction,Vector3.UP)
            for frame in range(3):
                await process_frame
            await RenderingServer.frame_post_draw
            var shot: Image = world.camera.get_viewport().get_texture().get_image()
            if shot == null or shot.is_empty():
                push_error("No rendered landscape frame")
                quit(2)
                return
            var destination: String = output.path_join("h%02d_%03d.png" % [int(height),bearing*45])
            if shot.save_png(destination) != OK:
                quit(3)
                return
    print("LANDSCAPE PASS bearings=8 heights=2 original_images=4 collision_nodes=0")
    quit(0)
