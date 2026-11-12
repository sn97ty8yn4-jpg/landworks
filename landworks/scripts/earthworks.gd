# Bounded hybrid earthmoving terrain: conserved heightfield + moving soil parcels.
# Godot 4.6/Jolt compatible. NO full DEM/SPH or excavator attachment calibration.
extends Node3D

const BATCH = preload("res://landworks/scripts/soil/material_batch.gd")
var material_mechanics := false # Enabled by the playable sandbox; legacy fixtures remain available.
var columns: Array[MaterialBatch] = []
var bucket_inventory := MaterialBatch.new()
var offsite_inventory := MaterialBatch.new()
# The dozer blade never carries material: it holds a cut only for the tick in
# which it pushes it back out in front. Its own store keeps blade spoil from
# mixing with whatever the bucket happens to be carrying, and mass_totals()
# counts it, so a push is conserved like every other movement.
var blade_inventory := MaterialBatch.new()
var containers: Array[Dictionary] = []
var initial_mass: Dictionary = {}
var terrain_revision := 0
var last_receipt_id := 0
var rejected_cuts := 0
var partial_cuts := 0

# 81×81 heightfield / 0.225m cells. Doubles spatial resolution in each axis
# without changing the physical 18m work area or volume accounting.
const N := 81
const CELL := 0.225
const HALF := 40
# Recess the unloaded heightmap 3 cm below the flat Jolt yard.
# Previously the 45mm collision lip at the boundary could arrest rigid
# box-track edges; the inset permits a level ingress, while real banks still
# rise naturally above the yard.
const BASE_HEIGHT := -0.03
const BEDROCK_HEIGHT := -3.0
# Smaller sub-litre parcels model aggregate flow more convincingly.
# Mobile volume is conserved; particles remain non-interacting proxies.
const MAX_PARTICLES := 800
const PARCEL_M3 := 0.00075
const MAX_BUCKET_M3 := 0.24
const GRAVITY := 9.81
# Steepest in-situ face the 0.225 m grid represents (true vertical is not
# resolvable on a heightfield).
const MAX_FACE_DEG := 85.0
# Legacy (non-mechanics) cutting edge allowance kept for old fixtures only.
const LEGACY_EDGE_DROP_M := 0.045

const SOIL_TYPES := {
    "gravel": {"density": 1700.0, "repose_deg": 36.0,
        "cut_pressure_pa": 34000.0, "flow_drag": 1.3, "tint": Color("#a89a79")},
    "clay": {"density": 1850.0, "repose_deg": 48.0,
        "cut_pressure_pa": 65000.0, "flow_drag": 3.8, "tint": Color("#916047")}
}

var height_values := PackedFloat32Array()
# Thickness (m) of disturbed/loose material at the top of each column.
# Deposited spoil, slumped debris and failed faces are loose; the rest is
# undisturbed bank material that can stand on a cut face by cohesion.
var loose_depth := PackedFloat32Array()
var material_ids := PackedByteArray()
var mobile: Array[Dictionary] = []
var terrain_mesh: MeshInstance3D
var terrain_collider: CollisionShape3D
var height_shape: HeightMapShape3D
var granular: MultiMeshInstance3D
var mobile_dirty := true
var terrain_dirty := true
var dirty_clock := 0.0
var slump_clock := 0.0
var initial_ground_m3 := 0.0
var extracted_total_m3 := 0.0
var deposited_total_m3 := 0.0
var offsite_m3 := 0.0
var peak_particles := 0
var last_cut_force_n := 0.0
var peak_cut_force_n := 0.0
var cut_events := 0
var spill_events := 0

func _ready() -> void:
    _initialise_data()
    if material_mechanics:
        for id in range(N*N):
            columns.append(BATCH.bank("clay" if material_ids[id] == 1 else "gravel",
                maxf(0.0,height_values[id]-BEDROCK_HEIGHT)*CELL*CELL))
        initial_mass = mass_totals()
    _make_collision()
    _make_visuals()
    initial_ground_m3 = ground_volume_m3()
    _rebuild_terrain()

func _idx(i: int, j: int) -> int:
    return j * N + i

func _world_at(i: int, j: int) -> Vector3:
    return to_global(Vector3((i - HALF) * CELL, height_values[_idx(i, j)],
        (j - HALF) * CELL))

func _soil_type(i: int, j: int) -> String:
    return "clay" if material_ids[_idx(i, j)] == 1 else "gravel"

func _initialise_data() -> void:
    height_values.resize(N * N)
    material_ids.resize(N * N)
    loose_depth.resize(N * N)
    loose_depth.fill(0.0)
    for j in range(N):
        for i in range(N):
            var x := (i - HALF) * CELL
            var z := (j - HALF) * CELL
            # Two distinct banks within one collision-backed work pad.
            var gravel_d2 := pow((x + 1.8) / 2.55, 2) + pow((z + 1.4) / 2.15, 2)
            var clay_d2 := pow((x - 4.8) / 2.25, 2) + pow((z - 2.9) / 2.3, 2)
            var gravel_h := maxf(0.0, 1.32 * (1.0 - gravel_d2))
            var clay_h := maxf(0.0, 1.45 * (1.0 - clay_d2))
            var id := _idx(i, j)
            height_values[id] = BASE_HEIGHT + maxf(gravel_h, clay_h)
            material_ids[id] = 1 if clay_h > gravel_h else 0

func _make_collision() -> void:
    var ground := StaticBody3D.new()
    ground.name = "MutableSoilCollider"
    ground.collision_layer = 1
    ground.collision_mask = 3
    add_child(ground)
    terrain_collider = CollisionShape3D.new()
    ground.add_child(terrain_collider)
    # The shape has a one-unit grid. Uniform scaling keeps map and mesh
    # coordinates coincident under both GodotPhysics and Jolt.
    terrain_collider.scale = Vector3.ONE * CELL
    height_shape = HeightMapShape3D.new()
    height_shape.map_width = N
    height_shape.map_depth = N
    terrain_collider.shape = height_shape
    var mat := PhysicsMaterial.new()
    mat.friction = 0.80
    ground.physics_material_override = mat
    if material_mechanics:
        # Separate from the mutable surface: the bucket's soil-contact
        # exception must never permit digging through the refusal floor.
        var bedrock := StaticBody3D.new()
        bedrock.name = "RefusalSubstrate"
        add_child(bedrock)
        var base := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = Vector3((N-1)*CELL,0.30,(N-1)*CELL)
        base.shape = box
        base.position.y = BEDROCK_HEIGHT-0.15
        bedrock.add_child(base)

func _make_visuals() -> void:
    terrain_mesh = MeshInstance3D.new()
    terrain_mesh.name = "ContinuumSoilSurface"
    add_child(terrain_mesh)
    var material := StandardMaterial3D.new()
    # Material is derived from actual soil ID, surface slope and layered
    # stratification, then broken up with small-scale world-space pigment
    # variation in a cheap Compatibility-renderer spatial shader.
    var soil_shader := Shader.new()
    soil_shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;
varying vec3 soil_world;
void vertex() {
    soil_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 grain_coord = floor(soil_world.xz * 31.0);
    float grain = fract(sin(dot(grain_coord, vec2(127.1, 311.7))) * 43758.5453);
    float fine = fract(sin(dot(floor(soil_world.xz * 87.0),
        vec2(73.19, 21.71))) * 19871.331);
    ALBEDO = COLOR.rgb * (0.82 + 0.22 * grain + 0.12 * fine);
    ROUGHNESS = 1.0;
}
"""
    var soil_mat := ShaderMaterial.new()
    soil_mat.shader = soil_shader
    terrain_mesh.material_override = soil_mat
    granular = MultiMeshInstance3D.new()
    granular.name = "MovingGranularParcels"
    add_child(granular)
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    mm.instance_count = MAX_PARTICLES
    mm.visible_instance_count = 0
    var sphere := SphereMesh.new()
    sphere.radius = 0.059
    sphere.height = 0.118
    sphere.radial_segments = 7
    sphere.rings = 3
    mm.mesh = sphere
    granular.multimesh = mm
    var pmat := StandardMaterial3D.new()
    pmat.vertex_color_use_as_albedo = true
    pmat.roughness = 1.0
    sphere.material = pmat

func _rebuild_terrain() -> void:
    var v := PackedVector3Array()
    var normal := PackedVector3Array()
    var colour := PackedColorArray()
    var triangles := PackedInt32Array()
    for j in range(N):
        for i in range(N):
            var id := _idx(i, j)
            v.append(Vector3((i - HALF) * CELL, height_values[id], (j - HALF) * CELL))
            var left_h := height_values[_idx(maxi(i - 1, 0), j)]
            var right_h := height_values[_idx(mini(i + 1, N - 1), j)]
            var near_h := height_values[_idx(i, maxi(j - 1, 0))]
            var far_h := height_values[_idx(i, mini(j + 1, N - 1))]
            normal.append(Vector3(left_h - right_h, 2.0 * CELL,
                near_h - far_h).normalized())
            var tint: Color = SOIL_TYPES[_soil_type(i, j)]["tint"]
            var steepness: float = 1.0 - normal[id].y
            var band: float = 0.035 * sin(height_values[id] * 15.0)
            var mottling: float = 0.045 * sin(float(i)*1.83+float(j)*2.31)
            if material_ids[id] == 1 and steepness > 0.18:
                tint = tint.darkened(clampf(0.10 + steepness*0.35,0,0.39))
            colour.append(tint.lightened(maxf(0.0,band+mottling)).darkened(
                maxf(0.0,-band-mottling)))
    for j in range(N - 1):
        for i in range(N - 1):
            var a := _idx(i, j)
            var b := _idx(i + 1, j)
            var c := _idx(i, j + 1)
            var d := _idx(i + 1, j + 1)
            triangles.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = v
    arrays[Mesh.ARRAY_NORMAL] = normal
    arrays[Mesh.ARRAY_COLOR] = colour
    arrays[Mesh.ARRAY_INDEX] = triangles
    var result := ArrayMesh.new()
    result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    terrain_mesh.mesh = result
    var map := PackedFloat32Array()
    map.resize(N * N)
    for id in range(N * N):
        map[id] = height_values[id] / CELL
    height_shape.map_data = map
    terrain_dirty = false

func _rebuild_particles() -> void:
    var mm := granular.multimesh
    mm.visible_instance_count = mobile.size()
    for i in range(mobile.size()):
        var particle: Dictionary = mobile[i]
        var global_point: Vector3 = particle["pos"]
        var point := to_local(global_point)
        var ratio: float = clampf(float(particle["m3"]) / PARCEL_M3,0.15,1.0)
        var size: float = pow(ratio,1.0/3.0)
        var factor := Vector3.ONE * size
        mm.set_instance_transform(i,Transform3D(Basis().scaled(factor),point))
        mm.set_instance_color(i,SOIL_TYPES[str(particle["material"])]["tint"])
    mobile_dirty = false

func has_position(world_pos: Vector3) -> bool:
    var p := to_local(world_pos)
    var bound := HALF * CELL - CELL
    return absf(p.x) <= bound and absf(p.z) <= bound

func _index_from_world(pos: Vector3) -> Vector2i:
    var p := to_local(pos)
    return Vector2i(clampi(int(round(p.x / CELL)) + HALF, 0, N - 1),
        clampi(int(round(p.z / CELL)) + HALF, 0, N - 1))

func surface_height(world_pos: Vector3) -> float:
    var coordinates := _index_from_world(world_pos)
    return position.y + height_values[_idx(coordinates.x, coordinates.y)]

func ground_volume_m3() -> float:
    var volume := 0.0
    for h in height_values:
        # Include the below-grade soil inventory. Clamping at the original
        # surface would silently lose excavated volume from trench accounting.
        volume += maxf(0.0, h - BEDROCK_HEIGHT) * CELL * CELL
    return volume

func mobile_volume_m3() -> float:
    var volume := 0.0
    for p in mobile:
        volume += float(p["m3"])
    return volume

func _point_to_segment_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
    var line := b - a
    var t := clampf((p - a).dot(line) / maxf(line.length_squared(), 0.000001),
        0.0, 1.0)
    return p.distance_squared_to(a + line * t)

func cut_sweep(start: Vector3, finish: Vector3, tool_width_m: float,
        bucket_room_m3: float) -> Dictionary:
    # Compatibility entry point for controlled standalone fixtures.
    return commit_cut(propose_cut(start,finish,tool_width_m,bucket_room_m3),INF,INF)

func propose_cut(start: Vector3, finish: Vector3, tool_width_m: float,
        bucket_room_m3: float) -> Dictionary:
    # Read-only: the machine applies this reaction BEFORE the next Jolt step.
    # Sample the actual moving bucket lip; no removal if motion stalls.
    var horizontal := Vector2(finish.x - start.x, finish.z - start.z)
    var movement := finish - start
    var moved := movement.length()
    if moved < (0.00001 if material_mechanics else 0.018) or bucket_room_m3 <= 0.00001 or not has_position(finish):
        return {"volume_m3": 0.0, "force_n": 0.0}
    # Mechanics mode: start/finish ARE the steel cutting edge (the caller
    # passes the toe's lowest front edge), so cut exactly there. The legacy
    # path kept a fixed 45 mm allowance below its reference point.
    var cut_level := minf(start.y, finish.y) - position.y - (0.0 if material_mechanics else LEGACY_EDGE_DROP_M)
    var segment_a := Vector2(start.x, start.z)
    var segment_b := Vector2(finish.x, finish.z)
    var width_sq := pow(maxf(0.25, tool_width_m * 0.52), 2)
    var volume := 0.0
    var pressure_sum := 0.0
    var cut_gravel_m3 := 0.0
    var cut_clay_m3 := 0.0
    var candidate_count := 0
    var entries: Array[Dictionary] = []
    var occupied := 0.0
    var a_cell := _index_from_world(start)
    var b_cell := _index_from_world(finish)
    var margin := int(ceil(sqrt(width_sq)/CELL))+1
    for j in range(maxi(1,mini(a_cell.y,b_cell.y)-margin),mini(N-2,maxi(a_cell.y,b_cell.y)+margin)+1):
        for i in range(maxi(1,mini(a_cell.x,b_cell.x)-margin),mini(N-2,maxi(a_cell.x,b_cell.x)+margin)+1):
            var world_point := _world_at(i, j)
            var d2 := _point_to_segment_sq(Vector2(world_point.x, world_point.z),
                segment_a, segment_b)
            if d2 > width_sq:
                continue
            var id := _idx(i, j)
            var penetrated := height_values[id] - cut_level
            if penetrated <= 0.0:
                continue
            var cell_capacity := minf(minf(0.044, penetrated * 0.38),
                maxf(0.0, height_values[id] - BEDROCK_HEIGHT))
            if material_mechanics:
                cell_capacity = minf(cell_capacity,maxf(0.0,tool_width_m*minf(penetrated,0.5)*moved-volume)/(CELL*CELL))
            var swell := 1.0
            if material_mechanics:
                swell = (1.0+maxf(columns[id].void_ratio,columns[id].weighted("void_ratio_loose")))/(1.0+columns[id].void_ratio)
            var removed := minf(cell_capacity, (bucket_room_m3 - occupied) / (CELL * CELL*swell))
            if removed <= 0.0:
                break
            var parcel_volume := removed * CELL * CELL
            entries.append({"id":id,"m3":parcel_volume})
            volume += parcel_volume
            occupied += parcel_volume*swell
            if material_ids[id] == 1:
                cut_clay_m3 += parcel_volume
            else:
                cut_gravel_m3 += parcel_volume
            var soil: Dictionary = SOIL_TYPES[_soil_type(i, j)]
            pressure_sum += (columns[id].resistance(tool_width_m,minf(penetrated,0.5)) if material_mechanics else float(soil["cut_pressure_pa"]) * removed * tool_width_m)
            candidate_count += 1
    var force := pressure_sum/maxf(1.0,float(candidate_count)*(1.0 if material_mechanics else 0.25))
    if not material_mechanics: force = minf(22000.0,force)
    return {"volume_m3":volume,"loose_m3":occupied,"force_n":force,
        "gravel_m3":cut_gravel_m3,"clay_m3":cut_clay_m3,
        "entries":entries,"revision":terrain_revision,"travel_m":moved}

func commit_cut(proposal: Dictionary, available_force: float, available_work: float,
        receipt_id: int = 0, sink: MaterialBatch = null) -> Dictionary:
    var empty := {"volume_m3":0.0,"loose_m3":0.0,"force_n":float(proposal.get("force_n",0.0))}
    if not proposal.has("entries"): return empty
    if receipt_id == 0: receipt_id = last_receipt_id+1
    var force := float(proposal["force_n"])
    last_cut_force_n = force
    peak_cut_force_n = maxf(peak_cut_force_n,force)
    if receipt_id <= last_receipt_id or int(proposal["revision"]) != terrain_revision or available_work <= 0.0 or available_force <= 0.0:
        rejected_cuts += 1
        return empty
    if not material_mechanics and available_force < force:
        rejected_cuts += 1
        return empty
    last_receipt_id = receipt_id
    var fraction := minf(1.0,available_work/maxf(force*float(proposal["travel_m"]),1e-9))
    # Short of force the tooth takes a thinner slice rather than refusing the
    # whole cut. Removed volume scales with the force actually mobilised.
    var force_fraction := clampf(available_force/maxf(force,1e-9),0.0,1.0)
    if force_fraction < 1.0: partial_cuts += 1
    fraction = minf(fraction,force_fraction)
    var volume := 0.0
    var loose := 0.0
    for entry in proposal["entries"]:
        var id := int(entry["id"])
        var amount := float(entry["m3"])*fraction
        if material_mechanics:
            var extracted := columns[id].split(amount)
            extracted.loosen()
            loose += extracted.volume()
            (sink if sink != null else bucket_inventory).absorb(extracted)
            _sync_column(id)
        else:
            height_values[id] -= amount/(CELL*CELL)
            loose += amount
        # Cutting removes from the top: any loose cover goes first.
        loose_depth[id] = clampf(loose_depth[id]-amount/(CELL*CELL),0.0,maxf(0.0,height_values[id]-BEDROCK_HEIGHT))
        volume += amount
    if volume > 0.0:
        terrain_dirty = true
        extracted_total_m3 += volume
        cut_events += 1
        terrain_revision += 1
    return {"volume_m3": volume, "loose_m3":loose,"force_n": force*fraction,
        "fraction":fraction,
        "work_j":force*float(proposal["travel_m"])*fraction,
        "gravel_m3":float(proposal["gravel_m3"])*fraction,
        "clay_m3":float(proposal["clay_m3"])*fraction}

func _sync_column(id: int) -> void:
    height_values[id] = BEDROCK_HEIGHT+columns[id].volume()/(CELL*CELL)
    material_ids[id] = 1 if columns[id].kind() == "clay" else 0

func mass_totals() -> Dictionary:
    var totals := {"water":0.0}
    var batches: Array = columns.duplicate()
    batches.append(bucket_inventory)
    batches.append(offsite_inventory)
    batches.append(blade_inventory)
    for container in containers:
        batches.append(container["inventory"])
    for parcel in mobile:
        if parcel.has("batch"): batches.append(parcel["batch"])
    for batch in batches:
        totals["water"] += batch.water+batch.free_water
        for key in batch.dry:
            totals[key] = float(totals.get(key,0.0))+float(batch.dry[key])
    return totals

func mass_error_kg() -> float:
    var current := mass_totals()
    var largest := 0.0
    for key in initial_mass:
        largest = maxf(largest,absf(float(current.get(key,0.0))-float(initial_mass[key])))
    return largest

func release_soil(world_tip: Vector3, direction: Vector3,
        amount_m3: float, kind: String = "gravel",
        source: MaterialBatch = null) -> float:
    var store: MaterialBatch = source if source != null else bucket_inventory
    if amount_m3 <= 0.0:
        return 0.0
    if material_mechanics:
        amount_m3 = minf(amount_m3,store.volume())
        if amount_m3 < 1e-10: return 0.0
        kind = store.kind()
    var available := MAX_PARTICLES - mobile.size()
    if available <= 0:
        return 0.0
    var requested := mini(available, maxi(1, int(ceil(amount_m3 / PARCEL_M3))))
    var released := minf(amount_m3, float(requested) * PARCEL_M3)
    for n in range(requested):
        var volume := minf(PARCEL_M3, released - float(n) * PARCEL_M3)
        if volume <= 0.0000001:
            continue
        var phase := float(n) * 2.3999632
        var radial := 0.13 * sqrt(float(n) / float(maxi(requested, 1)))
        var point := world_tip + Vector3(cos(phase) * radial, 0.08,
            sin(phase) * radial)
        var velocity := direction * 0.8 + Vector3(sin(phase) * 0.32,
            0.40 + float(n % 4) * 0.08, cos(phase) * 0.32)
        mobile.append({"pos": point, "vel": velocity, "m3": volume,
            "material": kind, "age": 0.0, "bounces": 0})
        if material_mechanics:
            mobile.back()["batch"] = store.split(volume)
    peak_particles = maxi(peak_particles, mobile.size())
    spill_events += 1
    mobile_dirty = true
    return released

# Open containers that catch falling material instead of the ground, such as
# the trailer tray. Each holds its own batch and is counted in mass_totals().
func register_container(node: Node3D, size: Vector3, centre: Vector3) -> int:
    containers.append({"node":node,"size":size,"centre":centre,
        "inventory":BATCH.new()})
    return containers.size()-1

func container_volume_m3(index: int) -> float:
    if index < 0 or index >= containers.size(): return 0.0
    return float(containers[index]["inventory"].volume())

# Tip material back out of a container. Returns the volume actually released.
func discharge_container(index: int, world_point: Vector3, direction: Vector3,
        amount_m3: float) -> float:
    if index < 0 or index >= containers.size(): return 0.0
    var store: MaterialBatch = containers[index]["inventory"]
    return release_soil(world_point,direction,minf(amount_m3,store.volume()),
        store.kind(),store)

func _catching_container(world_pos: Vector3) -> int:
    # Containers hold a material batch, which only the mechanics path creates.
    # Catching in the legacy path would drop the parcel's mass on the floor.
    if not material_mechanics:
        return -1
    for n in range(containers.size()):
        var node: Node3D = containers[n]["node"]
        if not is_instance_valid(node): continue
        var local: Vector3 = node.to_local(world_pos)-Vector3(containers[n]["centre"])
        var half: Vector3 = Vector3(containers[n]["size"])*0.5
        if absf(local.x)<half.x and absf(local.z)<half.z and absf(local.y)<half.y:
            return n
    return -1

func _deposit_particle(p: Dictionary) -> void:
    var volume: float = p["m3"]
    var caught := _catching_container(p["pos"])
    if caught >= 0:
        if material_mechanics and p.has("batch"):
            containers[caught]["inventory"].absorb(p["batch"])
        deposited_total_m3 += volume
        return
    var coords := _index_from_world(p["pos"])
    if has_position(p["pos"]):
        var id := _idx(coords.x, coords.y)
        if material_mechanics:
            # Height and material ID are derived from the column inventory.
            columns[id].absorb(p["batch"])
            _sync_column(id)
        else:
            height_values[id] += volume / (CELL * CELL)
            # Deposited clay must turn the receiving cell into clay.
            material_ids[id] = 1 if str(p["material"]) == "clay" else 0
        loose_depth[id] += volume / (CELL * CELL)
        deposited_total_m3 += volume
        terrain_dirty = true
    else:
        offsite_m3 += volume
        if material_mechanics: offsite_inventory.absorb(p["batch"])
    terrain_revision += 1

func _step_mobile(dt: float) -> void:
    for n in range(mobile.size() - 1, -1, -1):
        var p: Dictionary = mobile[n]
        var v: Vector3 = p["vel"]
        var point: Vector3 = p["pos"]
        var soil: Dictionary = SOIL_TYPES[str(p["material"])]
        v.y -= GRAVITY * dt
        v.x *= maxf(0.0, 1.0 - float(soil["flow_drag"]) * dt * 0.14)
        v.z *= maxf(0.0, 1.0 - float(soil["flow_drag"]) * dt * 0.14)
        point += v * dt
        # A parcel that enters an open container is caught there and never
        # reaches the ground, so it must be tested on the way through.
        if _catching_container(point) >= 0:
            p["pos"] = point
            _deposit_particle(p)
            mobile.remove_at(n)
            mobile_dirty = true
            continue
        var contact_height := surface_height(point) + 0.06
        if point.y <= contact_height:
            if int(p["bounces"]) < (2 if str(p["material"]) == "gravel" else 0) and v.length() > 1.8:
                point.y = contact_height + 0.02
                v.y = absf(v.y) * 0.16
                v.x *= 0.57
                v.z *= 0.57
                p["bounces"] = int(p["bounces"]) + 1
            else:
                p["pos"] = point
                _deposit_particle(p)
                mobile.remove_at(n)
                terrain_dirty = true
                mobile_dirty = true
                continue
        p["pos"] = point
        p["vel"] = v
        p["age"] = float(p["age"]) + dt
        mobile[n] = p
    mobile_dirty = true

func _strength(id: int) -> Dictionary:
    # Drained c-phi and bulk unit weight for the in-situ column. Disturbance
    # degrades peak toward residual cohesion, matching cut resistance.
    if material_mechanics:
        var col: MaterialBatch = columns[id]
        if col.volume() <= 1e-9:
            return {"c":0.0,"phi":deg_to_rad(33.0),"gamma":17000.0,"repose":deg_to_rad(37.0)}
        var c := lerpf(col.weighted("effective_cohesion_peak_pa"),
            col.weighted("effective_cohesion_residual_pa"),col.damage)
        return {"c":c,"phi":deg_to_rad(col.weighted("phi_peak_deg")),
            "gamma":col.mass()/col.volume()*GRAVITY,
            "repose":deg_to_rad(col.weighted("repose_static_deg"))}
    BATCH.setup()
    var key := "moist_silty_clay" if material_ids[id] == 1 else "loose_gravel"
    var p: Dictionary = BATCH.profiles[key]
    var soil: Dictionary = SOIL_TYPES["clay" if material_ids[id] == 1 else "gravel"]
    return {"c":float(p["effective_cohesion_peak_pa"]),"phi":deg_to_rad(float(p["phi_peak_deg"])),
        "gamma":float(soil["density"])*GRAVITY,"repose":deg_to_rad(float(soil["repose_deg"]))}

static func culmann_critical_height(c: float, phi: float, gamma: float, beta: float) -> float:
    # Culmann planar-wedge critical height of a face at angle beta.
    if beta <= phi + 1e-4: return INF
    return 4.0*c/gamma*sin(beta)*cos(phi)/maxf(1.0-cos(beta-phi),1e-9)

static func stable_face_angle(c: float, phi: float, gamma: float, height: float) -> float:
    # Steepest face (rad) that stands at this height. Hc falls monotonically
    # with beta, so bisect between phi and the grid's steepest face.
    var top := deg_to_rad(MAX_FACE_DEG)
    if c <= 0.0 or height <= 0.0: return phi if c <= 0.0 else top
    if culmann_critical_height(c,phi,gamma,top) >= height: return top
    var lo := phi
    var hi := top
    for _n in range(18):
        var mid := 0.5*(lo+hi)
        if culmann_critical_height(c,phi,gamma,mid) >= height: lo = mid
        else: hi = mid
    return lo

func _face_height(high: int, low: int, step: int, threshold: float) -> float:
    # Measure the whole steep face, not one 0.225 m cell step: walk uphill
    # from the high cell and downhill from the low cell while the gradient
    # stays steeper than the friction angle.
    var top := high
    var toe := low
    for _n in range(24):
        var nxt := top - step
        if nxt < 0 or nxt >= N*N or absi((nxt % N) - (top % N)) > 1: break
        if height_values[nxt] - height_values[top] <= threshold: break
        top = nxt
    for _n in range(24):
        var nxt := toe + step
        if nxt < 0 or nxt >= N*N or absi((nxt % N) - (toe % N)) > 1: break
        if height_values[toe] - height_values[nxt] <= threshold: break
        toe = nxt
    return height_values[top] - height_values[toe]

func _slump(dt: float) -> void:
    # Two-state slope stability, evaluated on a snapshot and applied at once
    # so the result does not depend on sweep order (no corner drift).
    #  * Loose material (spoil, debris, failed faces) runs to its static
    #    angle of repose.
    #  * Undisturbed bank stands on a cut face by cohesion up to the Culmann
    #    critical height for that face angle; beyond it the face fails and
    #    the failed material becomes loose and runs to repose.
    var rate := clampf(dt * 2.2, 0.0, 0.25)
    var flows: Array[Vector2i] = []      # (donor, receiver)
    var amounts := PackedFloat32Array()
    var from_loose := PackedFloat32Array()
    var outflow := PackedFloat32Array()
    outflow.resize(N*N)
    outflow.fill(0.0)
    var strength_cache: Dictionary = {}
    for j in range(1, N - 1):
        for i in range(1, N - 1):
            var source_id := _idx(i, j)
            for k in range(2):
                if (k == 0 and i >= N - 2) or (k == 1 and j >= N - 2): continue
                var step := 1 if k == 0 else N
                var neighbor := source_id + step
                var dh := height_values[source_id] - height_values[neighbor]
                if absf(dh) < 1e-6: continue
                var high := source_id if dh > 0.0 else neighbor
                var low := neighbor if dh > 0.0 else source_id
                var walk := step if high == source_id else -step
                dh = absf(dh)
                if not strength_cache.has(high): strength_cache[high] = _strength(high)
                var st: Dictionary = strength_cache[high]
                var repose_excess := dh - tan(float(st["repose"])) * CELL
                if repose_excess <= 0.0: continue
                var available := maxf(0.0, height_values[high] - BEDROCK_HEIGHT)
                var loose_here := minf(loose_depth[high], available)
                var phi: float = st["phi"]
                var face := _face_height(high, low, walk, tan(phi) * CELL)
                var beta := stable_face_angle(float(st["c"]), phi, float(st["gamma"]), face)
                var face_fails := dh > tan(beta) * CELL
                var move_h := 0.0
                var loose_part := 0.0
                if face_fails:
                    move_h = repose_excess * rate
                    loose_part = minf(move_h, loose_here)
                else:
                    move_h = minf(repose_excess, loose_here) * rate
                    loose_part = move_h
                if move_h < 0.000001: continue
                flows.append(Vector2i(high, low))
                amounts.append(move_h)
                from_loose.append(loose_part)
                outflow[high] += move_h
    if flows.is_empty(): return
    # Never drain a column below bedrock or its loose layer below zero when
    # several neighbours pull from it in the same pass.
    for n in range(flows.size()):
        var donor := flows[n].x
        var cap := maxf(0.0, height_values[donor] - BEDROCK_HEIGHT)
        var factor := 1.0 if outflow[donor] <= cap else cap / outflow[donor]
        amounts[n] *= factor
        from_loose[n] = minf(from_loose[n] * factor, amounts[n])
    var moved := false
    for n in range(flows.size()):
        var donor := flows[n].x
        var receiver := flows[n].y
        var move_h := amounts[n]
        if move_h < 0.000001: continue
        var arrived := move_h
        if material_mechanics:
            var piece := columns[donor].split(move_h*CELL*CELL)
            # Failed bank is disturbed material once it has moved; it bulks.
            piece.loosen()
            arrived = piece.volume()/(CELL*CELL)
            columns[receiver].absorb(piece)
            _sync_column(donor)
            _sync_column(receiver)
        else:
            height_values[donor] -= move_h
            height_values[receiver] += move_h
        loose_depth[donor] = maxf(0.0, loose_depth[donor] - from_loose[n])
        loose_depth[receiver] += arrived
        moved = true
    for n in range(flows.size()):
        var d := flows[n].x
        loose_depth[d] = minf(loose_depth[d], maxf(0.0, height_values[d] - BEDROCK_HEIGHT))
    if moved:
        terrain_dirty = true
        terrain_revision += 1

func _physics_process(delta: float) -> void:
    _step_mobile(delta)
    slump_clock += delta
    dirty_clock += delta
    if slump_clock >= 0.12:
        _slump(slump_clock)
        slump_clock = 0.0
    if terrain_dirty and dirty_clock >= 0.18:
        _rebuild_terrain()
        dirty_clock = 0.0
    if mobile_dirty:
        _rebuild_particles()

# Dozer blade. The blade cuts below grade and pushes what it cuts straight
# ahead as a surface pile; it never carries material. Volume moves from the
# bank, through the blade's own store, to loose material in a single tick,
# so mass accounting never sees a gap and nothing is created or destroyed.
func blade_push(start: Vector3, finish: Vector3, blade_width_m: float,
        available_force: float, available_work: float,
        release_point: Vector3, direction: Vector3) -> Dictionary:
    var proposal := propose_cut(start,finish,blade_width_m,MAX_BUCKET_M3)
    if float(proposal.get("force_n",0.0)) <= 0.0:
        return {"volume_m3":0.0,"force_n":0.0}
    var result := commit_cut(proposal,available_force,available_work,0,blade_inventory)
    if float(result["volume_m3"]) > 0.0:
        release_soil(release_point,direction,blade_inventory.volume(),"gravel",blade_inventory)
    return result
