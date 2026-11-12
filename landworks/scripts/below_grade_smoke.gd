# Real Jolt ray tests: no yard collider may remain over excavated soil.
extends SceneTree

const WORLD = preload("res://landworks/scripts/sandbox_world.gd")
const EARTH = preload("res://landworks/scripts/earthworks.gd")

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    # Construct only the production collision layout and soil, without
    # machines masking the ray or moving the ground during this test.
    var world := Node3D.new()
    root.add_child(world)
    var builder = WORLD.new()
    builder._build_terrain()
    var floor_node: Node = builder.get_child(0)
    builder.remove_child(floor_node)
    world.add_child(floor_node)
    builder.free()
    var soil: Node3D = EARTH.new()
    soil.position = Vector3(0, 0, -12)
    world.add_child(soil)
    soil.set_physics_process(false)
    var initial: float = soil.ground_volume_m3()
    var removed := 0.0
    for step in range(80):
        var cut: Dictionary = soil.cut_sweep(Vector3(-6.3,-1.55,-18),
            Vector3(-5.7,-1.55,-18),0.76,10.0)
        removed += float(cut["volume_m3"])
    soil._rebuild_terrain()
    await physics_frame
    await physics_frame
    var ok := true
    var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
    var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
        Vector3(-6,3,-18),Vector3(-6,-4,-18),1))
    if hit.is_empty() or float(hit.position.y) > -1.45:
        ok = false
        push_error("Below-grade ray found a hidden floor or missing trench: " + str(hit))
    for point in [Vector2(-9.1,-18),Vector2(-8.9,-18),
            Vector2(9.1,-18),Vector2(8.9,-18),Vector2(0,-21.1),
            Vector2(0,-20.9),Vector2(0,-3.1),Vector2(0,-2.9)]:
        var seam: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(
            Vector3(point.x,3,point.y),Vector3(point.x,-4,point.y),1))
        if seam.is_empty() or absf(float(seam.position.y)) > 0.04:
            ok = false
            push_error("Pad entry seam is unsupported at " + str(point))
    var error_m3: float = absf(soil.ground_volume_m3() + removed - initial)
    ok = ok and removed > 0.1 and error_m3 < 0.001
    for step in range(100):
        soil.cut_sweep(Vector3(-6.3,-8,-18),Vector3(-5.7,-8,-18),0.76,10.0)
    for height in soil.height_values:
        ok = ok and height >= soil.BEDROCK_HEIGHT - 0.00001
    print("BELOW_GRADE ", "PASS" if ok else "FAIL", " cut_m3=",removed,
        " balance_error_m3=",error_m3," hit=",hit.get("position",Vector3.ZERO))
    quit(0 if ok else 1)
