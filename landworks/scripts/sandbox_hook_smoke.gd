# Exercise the same hook joint used by G / PlayStation Square in the
# playable sandbox. No teleporting or fake scripted pickup is involved.
extends SceneTree

const SANDBOX = preload("res://landworks/scenes/sandbox_world.tscn")

func _initialize() -> void:
    var sandbox := SANDBOX.instantiate()
    root.add_child.call_deferred(sandbox)
    call_deferred("_run", sandbox)

func _run(sandbox: Node3D) -> void:
    await process_frame
    # The initial 1500kg crate is deliberately within 1.6 m of the bucket
    # hook. Being attachable does not imply the arm has sufficient lifting torque.
    # Hook smoke separately stages a load within capture range. The playable
    # entry lane is left clear of the permanent 1500kg sandbox crate.
    sandbox.digger.test_mass.global_position = sandbox.digger.bucket.to_global(
        sandbox.digger.BUCKET_TIP) + Vector3.DOWN * 0.50
    var status: String = sandbox.digger.toggle_hook(sandbox.props)
    if not is_instance_valid(sandbox.digger.load_hook_joint):
        push_error("SANDBOX_HOOK_FAIL: " + status)
        quit(1)
        return
    if sandbox.digger.attached_load == null:
        push_error("SANDBOX_HOOK_FAIL: connected joint has no physical load")
        quit(2)
        return
    await create_timer(0.4).timeout
    if not is_instance_valid(sandbox.digger.load_hook_joint):
        push_error("SANDBOX_HOOK_FAIL: joint failed during physics simulation")
        quit(3)
        return
    var released: String = sandbox.digger.toggle_hook(sandbox.props)
    await process_frame
    if is_instance_valid(sandbox.digger.load_hook_joint):
        push_error("SANDBOX_HOOK_FAIL: joint did not release")
        quit(4)
        return
    print("SANDBOX_HOOK_PASS attached=", status, " released=", released)
    quit(0)
