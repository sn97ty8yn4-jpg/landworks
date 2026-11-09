# Deterministic standalone Godot engine test of soil cutting, carrying,
# granular spill and conservation. Uses a swept cutting lip and does not
# assume that animated graphics imply material movement.
extends SceneTree

const EARTH = preload("res://landworks/scripts/earthworks.gd")

func _initialize() -> void:
    var soil = EARTH.new()
    root.add_child.call_deferred(soil)
    call_deferred("_run", soil)

func _run(soil: Node3D) -> void:
    await process_frame
    var start_volume: float = soil.ground_volume_m3()
    var held := 0.0
    var cutting_force_n := 0.0
    var last := Vector3(-2.8, 0.37, -1.4)
    for i in range(26):
        var here := Vector3(-2.8 + float(i + 1) * 0.11, 0.34, -1.4)
        var cut: Dictionary = soil.cut_sweep(last, here, 0.75,
            soil.MAX_BUCKET_M3 - held)
        held += float(cut["volume_m3"])
        cutting_force_n = maxf(cutting_force_n, float(cut["force_n"]))
        last = here
    var cut_volume := held
    if cut_volume < 0.025 or cutting_force_n < 100.0:
        push_error("EARTHWORK_FAIL no meaningful cutting or physical reaction: %s" %
            str([cut_volume, cutting_force_n]))
        quit(1)
        return
    var dropped := 0.0
    for n in range(9):
        var spill: float = soil.release_soil(Vector3(-1.1, 2.1, -0.6),
            Vector3(0.45, 0.0, 0.2), minf(0.035, held), "gravel")
        dropped += spill
        held -= spill
    if dropped < 0.020 or soil.mobile.size() < 3:
        push_error("EARTHWORK_FAIL insufficient moving granular parcels")
        quit(2)
        return
    var count_at_peak: int = soil.mobile.size()
    for n in range(270):
        await physics_frame
    var final_ground: float = soil.ground_volume_m3()
    var mobile_volume: float = soil.mobile_volume_m3()
    var balance: float = final_ground + mobile_volume + held + float(soil.offsite_m3) - start_volume
    var tolerance := 0.003
    var ok: bool = absf(balance) <= tolerance and float(soil.deposited_total_m3) > 0.015
    ok = ok and soil.cut_events > 0 and soil.spill_events > 0
    ok = ok and count_at_peak > soil.mobile.size()
    ok = ok and soil.peak_particles <= soil.MAX_PARTICLES
    ok = ok and soil.terrain_mesh.mesh != null and soil.height_shape.map_width == soil.N
    print("EARTHWORKS ", "PASS" if ok else "FAIL",
        " initial_m3=", snappedf(start_volume, 0.001),
        " cut_m3=", snappedf(cut_volume, 0.001),
        " deposited_m3=", snappedf(soil.deposited_total_m3, 0.001),
        " mobile=", soil.mobile.size(), " peak=", soil.peak_particles,
        " force_N=", snappedf(cutting_force_n, 1.0),
        " balance_m3=", snappedf(balance, 0.0001))
    quit(0 if ok else 3)
