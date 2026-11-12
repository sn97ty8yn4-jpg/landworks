# Capture an actual powered dig, then inspect the carried-soil graphic.
extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
func _initialize() -> void:
    call_deferred("_run")
func freeze_bodies(node: Node) -> void:
    if node is RigidBody3D: node.freeze = true
    for child in node.get_children(): freeze_bodies(child)
func isolate_bucket(node: Node, bucket: Node3D) -> void:
    if node is GeometryInstance3D and not bucket.is_ancestor_of(node): node.visible = false
    for child in node.get_children(): isolate_bucket(child,bucket)
func _run() -> void:
    var world = WORLD.instantiate()
    root.add_child(world)
    world._select_machine(1)
    world.digger.operated = false
    var lip: Vector3 = world.digger.bucket.to_global(world.digger.BUCKET_TIP)
    world.earth.position = Vector3(lip.x+1.8,0,lip.z+2.05)
    world.digger.target_angles["boom"] = -0.48
    world.digger.target_angles["stick"] = -0.70
    world.digger.target_angles["bucket"] = -0.24
    for frame in range(360): await physics_frame
    print("MATERIAL_RENDER cut_m3=",world.maximum_excavated_m3,
        " carried_kg=",world.earth.bucket_inventory.mass()," error_kg=",world.earth.mass_error_kg())
    world.set_process(false)
    world.set_physics_process(false)
    world.digger.set_physics_process(false)
    freeze_bodies(world)
    world.machine_visuals.update_bucket_fill(world.soil_bucket_m3,world.soil_bucket_material)
    var output := "res://validation/material-cab-refined"
    DirAccess.make_dir_recursive_absolute(output)
    var bucket: Node3D = world.digger.bucket
    var focus: Vector3 = bucket.to_global(Vector3(0,0.30,-0.40))
    world.camera.global_position = focus-bucket.global_basis.y*2.0+bucket.global_basis.x*1.6
    world.camera.fov = 48.0
    world.camera.look_at(focus,Vector3.UP)
    # Inspection lighting and isolated surroundings reveal the cavity even
    # when the actual digging pose puts it below the terrain surface.
    isolate_bucket(world,bucket)
    var light := OmniLight3D.new()
    world.add_child(light)
    light.global_position = world.camera.global_position
    light.omni_range = 8.0
    light.light_energy = 3.0
    for frame in range(4): await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output.path_join("loaded_bucket.png"))
    quit()
