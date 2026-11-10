# Bounded hybrid earthmoving terrain: conserved heightfield + moving soil parcels.
# Godot 4.6/Jolt compatible. NO full DEM/SPH or excavator attachment calibration.
extends Node3D

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
# Smaller sub-litre parcels model aggregate flow more convincingly.
# Mobile volume is conserved; particles remain non-interacting proxies.
const MAX_PARTICLES := 800
const PARCEL_M3 := 0.00075
const MAX_BUCKET_M3 := 0.24
const GRAVITY := 9.81

const SOIL_TYPES := {
    "gravel": {"density": 1700.0, "repose_deg": 36.0,
        "cut_pressure_pa": 34000.0, "flow_drag": 1.3, "tint": Color("#a89a79")},
    "clay": {"density": 1850.0, "repose_deg": 48.0,
        "cut_pressure_pa": 65000.0, "flow_drag": 3.8, "tint": Color("#916047")}
}

var height_values := PackedFloat32Array()
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
        volume += maxf(0.0, h - BASE_HEIGHT) * CELL * CELL
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
    # Sample the actual moving bucket lip; no removal if motion stalls.
    var horizontal := Vector2(finish.x - start.x, finish.z - start.z)
    var movement := finish - start
    var moved := movement.length()
    if moved < 0.018 or bucket_room_m3 <= 0.00001 or not has_position(finish):
        return {"volume_m3": 0.0, "force_n": 0.0}
    var cut_level := minf(start.y, finish.y) - position.y - 0.045
    var segment_a := Vector2(start.x, start.z)
    var segment_b := Vector2(finish.x, finish.z)
    var width_sq := pow(maxf(0.25, tool_width_m * 0.52), 2)
    var volume := 0.0
    var pressure_sum := 0.0
    var cut_gravel_m3 := 0.0
    var cut_clay_m3 := 0.0
    var candidate_count := 0
    for j in range(1, N - 1):
        for i in range(1, N - 1):
            var world_point := _world_at(i, j)
            var d2 := _point_to_segment_sq(Vector2(world_point.x, world_point.z),
                segment_a, segment_b)
            if d2 > width_sq:
                continue
            var id := _idx(i, j)
            var penetrated := height_values[id] - cut_level
            if penetrated <= 0.0:
                continue
            var cell_capacity := minf(0.044, penetrated * 0.38)
            var removed := minf(cell_capacity, (bucket_room_m3 - volume) / (CELL * CELL))
            if removed <= 0.0:
                break
            height_values[id] -= removed
            var parcel_volume := removed * CELL * CELL
            volume += parcel_volume
            if material_ids[id] == 1:
                cut_clay_m3 += parcel_volume
            else:
                cut_gravel_m3 += parcel_volume
            var soil: Dictionary = SOIL_TYPES[_soil_type(i, j)]
            pressure_sum += float(soil["cut_pressure_pa"]) * removed * tool_width_m
            candidate_count += 1
    if volume > 0.00001:
        terrain_dirty = true
        extracted_total_m3 += volume
        cut_events += 1
    var force := minf(22000.0, pressure_sum / maxf(1.0, float(candidate_count) * 0.25))
    last_cut_force_n = force
    peak_cut_force_n = maxf(peak_cut_force_n, force)
    return {"volume_m3": volume, "force_n": force,
        "gravel_m3": cut_gravel_m3, "clay_m3": cut_clay_m3}

func release_soil(world_tip: Vector3, direction: Vector3,
        amount_m3: float, kind: String = "gravel") -> float:
    if amount_m3 <= 0.0:
        return 0.0
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
    peak_particles = maxi(peak_particles, mobile.size())
    spill_events += 1
    mobile_dirty = true
    return released

func _deposit_particle(p: Dictionary) -> void:
    var volume: float = p["m3"]
    var coords := _index_from_world(p["pos"])
    if has_position(p["pos"]):
        var id := _idx(coords.x, coords.y)
        height_values[id] += volume / (CELL * CELL)
        # Deposited cohesive clay must actually turn the receiving cell
        # into clay; volume and material appearance must stay coupled.
        material_ids[id] = 1 if str(p["material"]) == "clay" else 0
        deposited_total_m3 += volume
        terrain_dirty = true
    else:
        offsite_m3 += volume

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

func _slump(dt: float) -> void:
    # Pairwise locally conservative height transfer. The repose threshold
    # stops movement on shallow gradients; clay can hold steeper slopes.
    for j in range(1, N - 2):
        for i in range(1, N - 2):
            var source_id := _idx(i, j)
            for neighbor in [_idx(i + 1, j), _idx(i, j + 1)]:
                var left: int = source_id if height_values[source_id] > height_values[neighbor] else neighbor
                var right: int = neighbor if left == source_id else source_id
                var mat: Dictionary = SOIL_TYPES["clay" if material_ids[left] == 1 else "gravel"]
                var max_slope := tan(deg_to_rad(float(mat["repose_deg"]))) * CELL
                var excess := height_values[left] - height_values[right] - max_slope
                if excess <= 0.0:
                    continue
                var move_h := minf(excess * clampf(dt * 2.2, 0.0, 0.25),
                    maxf(0.0, height_values[left] - BASE_HEIGHT))
                if move_h < 0.000001:
                    continue
                height_values[left] -= move_h
                height_values[right] += move_h
                terrain_dirty = true

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
