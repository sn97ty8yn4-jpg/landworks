# Does the physical crawler enter the earthmoving pad without a hidden lip?
# Reuses the playable sandbox; forces come from the existing 4 track patches.
extends SceneTree

const SCENE = preload("res://landworks/scenes/sandbox_world.tscn")

func _initialize() -> void:
    var sandbox := SCENE.instantiate()
    root.add_child.call_deferred(sandbox)
    call_deferred("_exercise", sandbox)

func _exercise(sandbox: Node3D) -> void:
    await process_frame
    var machine = sandbox.digger
    machine.scripted_test = true
    machine.access_test = true
    var origin: Vector3 = machine.undercarriage.global_position
    var best_z: float = origin.z
    var maximum_tilt_deg := 0.0
    var reached_pad := false
    var positive_contacts := 0
    for i in range(2750):
        await physics_frame
        var pos: Vector3 = machine.undercarriage.global_position
        best_z = minf(best_z,pos.z)
        var up: Vector3 = machine.undercarriage.global_transform.basis.y.normalized()
        maximum_tilt_deg = maxf(maximum_tilt_deg,
            rad_to_deg(acos(clampf(up.dot(Vector3.UP),-1.0,1.0))))
        if machine.ground_contact_count >= 2:
            positive_contacts += 1
        if pos.z < -4.0 and sandbox.earth.has_position(pos):
            reached_pad = true
            break
    var progress: float = origin.z-best_z
    var ok: bool = reached_pad and progress > 3.8         and positive_contacts > 90 and maximum_tilt_deg < 16.0
    print("WORK_PAD_ACCESS ", "PASS" if ok else "FAIL",
        " distance_m=", snappedf(progress,0.01),
        " minimum_z=", snappedf(best_z,0.01),
        " contacts_frames=",positive_contacts,
        " tilt_max_deg=",snappedf(maximum_tilt_deg,0.01),
        " entered=",reached_pad)
    if not ok:
        push_error("Excavator cannot physically drive onto the excavation pad")
    quit(0 if ok else 1)
