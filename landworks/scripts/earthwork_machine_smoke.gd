# Test genuine powered excavator articulation against the hybrid earthworks.
# The bank is placed below the starting bucket; we NEVER teleport the bucket.
# Headless test checks material removed through the real Jolt joint movement.
extends SceneTree

const SANDBOX = preload("res://landworks/scenes/sandbox_world.tscn")

func _initialize() -> void:
    var sandbox := SANDBOX.instantiate()
    root.add_child.call_deferred(sandbox)
    call_deferred("_exercise", sandbox)

func _exercise(sandbox: Node3D) -> void:
    await process_frame
    var digger = sandbox.digger
    var earth = sandbox.earth
    digger.operated = false
    digger.scripted_test = false
    # Relocate the soil bank, not the excavator or payload, to create a
    # reproducible site with a reachable gravel face beneath the bucket.
    var lip_at_start: Vector3 = digger.bucket.to_global(digger.BUCKET_TIP)
    # Centre the bank 0.65 m ahead of the initial lip: the previous
    # target moved the bucket down 0.31 m but forward 0.89 m, skimming
    # above the original bank without any soil contact.
    earth.position = Vector3(lip_at_start.x + 1.8, 0.0,
        lip_at_start.z + 1.4 + 0.65)
    # Seat the face just under the tooth. The rigged bucket's tip sits 0.5 m
    # below its pin, so a pad fixed at y=0 starts the bucket buried 0.7 m in
    # the bank, where it stalls instead of sweeping a cut. Drop the pad so the
    # lip begins 50 mm clear and the commanded boom motion digs into it.
    earth.position.y += (lip_at_start.y - 0.05) - earth.surface_height(lip_at_start)
    var surface_at_start: float = earth.surface_height(lip_at_start)
    var initial_m3: float = earth.ground_volume_m3()
    digger.target_angles["boom"] = -0.48
    digger.target_angles["stick"] = -0.70
    digger.target_angles["bucket"] = -0.24
    for n in range(900):
        await physics_frame
    var lip_after: Vector3 = digger.bucket.to_global(digger.BUCKET_TIP)
    var cut_m3: float = sandbox.maximum_excavated_m3
    var force_n: float = earth.peak_cut_force_n
    var cut_events: int = earth.cut_events
    var balance_m3: float = earth.ground_volume_m3() + sandbox.soil_bucket_m3 +         earth.mobile_volume_m3() + earth.offsite_m3 - initial_m3
    var mass_error: float = earth.mass_error_kg() if earth.material_mechanics else 0.0
    print("PHYSICAL_DIG_TEST lip_start=", lip_at_start,
        " bank_h=", surface_at_start,
        " lip_end=", lip_after, " cut_m3=", cut_m3,
        " cut_events=", cut_events, " last_force_n=", force_n,
        " bucket_m3=", sandbox.soil_bucket_m3,
        " bulk_swell_m3=", balance_m3," constituent_error_kg=",mass_error)
    var conserved: bool = mass_error < 0.001 if earth.material_mechanics else absf(balance_m3) < 0.006
    if cut_m3 <= 0.005 or cut_events < 2 or force_n < 100.0 or not conserved:
        push_error("PHYSICAL_DIG_FAIL powered bucket did not remove conserved bank material")
        quit(1)
        return
    # Tip the bucket to release actual captured volume as moving particles.
    digger.target_angles["bucket"] = 0.65
    # Simulate the R-key manual discharge request. The preceding test has
    # independently required a genuine powered-joint soil cut.
    sandbox.spoil_dump_request = true
    for n in range(500):
        await physics_frame
    print("PHYSICAL_DIG_DUMP soil_m3=", sandbox.soil_bucket_m3,
        " released_m3=", sandbox.maximum_dumped_m3,
        " mobile=", earth.mobile.size(),
        " deposited_m3=", earth.deposited_total_m3)
    var good: bool = sandbox.maximum_dumped_m3 > 0.002
    good = good and absf(sandbox.soil_mass_error_m3) < 0.006
    if earth.material_mechanics:
        good = good and earth.mass_error_kg() < 0.001
        good = good and absf(digger.bucket.mass-sandbox.bucket_empty_mass-earth.bucket_inventory.mass()) < 0.01
    print("PHYSICAL_DIG ", "PASS" if good else "FAIL")
    quit(0 if good else 2)
