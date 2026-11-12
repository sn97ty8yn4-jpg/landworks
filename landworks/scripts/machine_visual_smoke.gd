# Exercise the imported model parts on the REAL powered rig, including
# linkage closure, telescoping barrels, wheel origins and circulating tracks.
extends SceneTree

const SCENE = preload("res://landworks/scenes/sandbox_world.tscn")

func _initialize() -> void:
    root.add_child.call_deferred(SCENE.instantiate())
    call_deferred("_exercise")

func _exercise() -> void:
    await process_frame
    var sandbox: Node3D = root.get_child(root.get_child_count()-1)
    var art: Node3D = sandbox.machine_visuals
    var digger: Node3D = sandbox.digger
    var errors: Array[String] = []
    if art.custom_parts_loaded != 10:
        errors.append("Expected ten attached imported parts")
    if art.track_multimeshes.size() != 2:
        errors.append("Missing circulating track belts")
    for wheel in sandbox.tractor.wheel_data:
        var mount: Node3D = wheel["visual"]
        var part: Node3D = mount.get_child(mount.get_child_count()-1)
        if part.position.length() > 0.00001 or part.scale.distance_to(Vector3.ONE) > 0.00001:
            errors.append("Imported wheel is not centred at its actual spin origin")
    var before: float = art.track_phase[0]
    digger.scripted_test = true
    digger.access_test = true
    for n in range(220):
        await physics_frame
    digger.scripted_test = false
    digger.access_test = false
    var track_motion: float = absf(art.track_phase[0]-before)
    if track_motion < 0.1:
        errors.append("Track shoes did not follow measured chassis movement")
    for target in [Vector3(-0.35,-0.95,-0.90),Vector3(0.72,-0.12,0.62),Vector3(0.24,-0.72,-0.24)]:
        digger.target_angles["boom"] = target.x
        digger.target_angles["stick"] = target.y
        digger.target_angles["bucket"] = target.z
        for n in range(340):
            await physics_frame
    if art.maximum_linkage_error_m > 0.005:
        errors.append("Bucket four-bar no longer closes")
    if art.minimum_ram_extension_m < -0.02:
        errors.append("Fixed hydraulic barrel overran an endpoint")
    art.update_bucket_fill(0.12,"clay")
    if not art.bucket_fill.visible:
        errors.append("Captured soil not visible inside the bucket")
    art.update_bucket_fill(0.0,"clay")
    if art.bucket_fill.visible:
        errors.append("Empty bucket still displays captured soil")
    print("MACHINE_VISUAL_TEST parts=",art.custom_parts_loaded,
        " track_motion_m=",track_motion,
        " linkage_error_m=",art.maximum_linkage_error_m,
        " minimum_ram_extension_m=",art.minimum_ram_extension_m)
    for error in errors:
        push_error(error)
    print("MACHINE_VISUAL ","PASS" if errors.is_empty() else "FAIL")
    quit(0 if errors.is_empty() else 1)
