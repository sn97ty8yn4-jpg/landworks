# A falling, unpowered articulated bucket must not magically excavate.
extends SceneTree
const WORLD = preload("res://landworks/scenes/sandbox_world.tscn")
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var world = WORLD.instantiate()
    root.add_child(world)
    world.digger.hydraulics_enabled = false
    world.digger.operated = false
    var start: Vector3 = world.digger.bucket.to_global(world.digger.BUCKET_TIP)
    world.earth.position = Vector3(start.x+1.8,0,start.z+1.4+0.65)
    for frame in range(300): await physics_frame
    var moved: float = start.distance_to(world.digger.bucket.to_global(world.digger.BUCKET_TIP))
    var good: bool = world.maximum_excavated_m3 == 0.0 and world.earth.bucket_inventory.mass() == 0.0
    good = good and moved > 0.01 and world.earth.mass_error_kg()<0.001
    print("UNPOWERED_SOIL moved_m=",moved," cut_m3=",world.maximum_excavated_m3)
    print("UNPOWERED_SOIL ","PASS" if good else "FAIL")
    quit(0 if good else 1)
