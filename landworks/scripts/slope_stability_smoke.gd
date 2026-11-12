# Run: godot --headless --path . --script res://landworks/scripts/slope_stability_smoke.gd
# Two-state slope stability: undisturbed clay faces stand by cohesion,
# weak gravel faces fail back, loose spoil runs to repose, and the
# order-independent update neither drifts nor loses mass.
extends SceneTree
const EARTH = preload("res://landworks/scripts/earthworks.gd")
var failures: Array[String] = []
func check(value: bool, reason: String) -> void:
    if not value: failures.append(reason)
func _initialize() -> void:
    call_deferred("_run")
func _make(kind: int):
    var soil = EARTH.new()
    soil.material_mechanics = true
    root.add_child(soil)
    soil.set_physics_process(false)
    # Level bank of one material, then rebuild columns from it.
    for id in range(soil.N*soil.N):
        soil.material_ids[id] = kind
        soil.height_values[id] = 0.0
        soil.loose_depth[id] = 0.0
        soil.columns[id] = MaterialBatch.bank("clay" if kind == 1 else "gravel",
            (0.0-soil.BEDROCK_HEIGHT)*soil.CELL*soil.CELL)
        soil._sync_column(id)
    soil.initial_mass = soil.mass_totals()
    return soil
func _trench(soil, depth: float) -> void:
    # Remove bank material (to offsite) to leave near-vertical one-cell walls.
    for id in range(soil.N*soil.N):
        var i: int = id % soil.N
        var j: int = id / soil.N
        if i >= 36 and i <= 44 and j >= 10 and j <= 70:
            soil.offsite_inventory.absorb(soil.columns[id].split(depth*soil.CELL*soil.CELL))
            soil._sync_column(id)
func _moved(soil, before: PackedFloat32Array) -> float:
    var total := 0.0
    for id in range(before.size()): total += absf(soil.height_values[id]-before[id])
    return total*soil.CELL*soil.CELL
func _run() -> void:
    var clay = _make(1)
    _trench(clay,2.5)
    var c0: PackedFloat32Array = clay.height_values.duplicate()
    for n in range(300): clay._slump(0.12)
    check(_moved(clay,c0) < 0.001,"Undisturbed 2.5 m clay trench wall collapsed")
    check(clay.mass_error_kg() < 0.001,"Clay trench lost mass")
    var gravel = _make(0)
    _trench(gravel,1.5)
    var g0: PackedFloat32Array = gravel.height_values.duplicate()
    for n in range(300): gravel._slump(0.12)
    check(_moved(gravel,g0) > 0.5,"1.5 m gravel wall stood without cohesion to hold it")
    check(gravel.mass_error_kg() < 0.001,"Gravel failure lost mass")
    # Loose spoil cone on a level gravel pad: symmetric spread, no drift.
    var heap = _make(0)
    var centre: int = heap.HALF*heap.N+heap.HALF
    # 3x3 block of loose spoil about 1.4 m proud of the pad.
    for dj in [-1,0,1]:
        for di in [-1,0,1]:
            var id: int = centre+di+dj*heap.N
            var spoil = MaterialBatch.bank("gravel",1.4*heap.CELL*heap.CELL)
            spoil.loosen()
            heap.loose_depth[id] += spoil.volume()/(heap.CELL*heap.CELL)
            heap.columns[id].absorb(spoil)
            heap._sync_column(id)
    var heap_start: float = heap.height_values[centre]
    heap.initial_mass = heap.mass_totals()
    for n in range(400): heap._slump(0.12)
    var sx := 0.0
    var sz := 0.0
    var w := 0.0
    for id in range(heap.N*heap.N):
        var lift: float = maxf(0.0,heap.height_values[id])
        sx += lift*float(id % heap.N)
        sz += lift*float(id / heap.N)
        w += lift
    var drift := Vector2(sx/w-heap.HALF,sz/w-heap.HALF).length()
    check(drift < 0.05,"Spoil heap drifted %.3f cells" % drift)
    check(heap.height_values[centre] < heap_start*0.75,"Loose spoil did not run out")
    check(heap.mass_error_kg() < 0.001,"Spoil spread lost mass")
    print("SLOPE_STABILITY clay_moved=",_moved(clay,c0)," gravel_moved=",_moved(gravel,g0),
        " heap_drift=",drift," heap_peak=",heap.height_values[centre])
    for failure in failures: push_error(failure)
    print("SLOPE_STABILITY ","PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)
