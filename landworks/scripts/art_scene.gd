# Landworks 'painted countryside' visual layer.
# Pure visual meshes. No new physics bodies are created by this class.
# The sandbox Jolt machinery, joint pivots, and soil mass ledger are untouched.
extends Node3D

const M = preload("res://landworks/scripts/mesh_factory.gd")
const WORK_Z := -12.0

var rng := RandomNumberGenerator.new()
var palette: Dictionary = {}
var grass_group: MultiMeshInstance3D
var flowers_group: MultiMeshInstance3D
var pebble_group: MultiMeshInstance3D
var cloud_nodes: Array[Node3D] = []
var scenery_count := 0

func _ready() -> void:
    rng.seed = 7100803
    _init_palette()
    _painted_ground()
    _distant_hills()
    _farm_buildings()
    _wooden_fence()
    _make_trees()
    _ground_detail()
    _clouds()
    _digging_site_details()
    print("LANDWORKS_ART_READY terrain=painted vegetation=instanced scenery=", scenery_count)

func _init_palette() -> void:
    for id in ["grass", "grass_light", "grass_shadow", "earth", "earth_light",
            "clay", "stone", "timber", "tin", "dark", "leaf", "leaf_light",
            "leaf_gold", "white", "flower_pink", "flower_yellow"]:
        var colors := {
            "grass": Color("#728954"), "grass_light": Color("#a1a45c"),
            "grass_shadow": Color("#526a47"), "earth": Color("#aa8e6a"),
            "earth_light": Color("#c1a783"), "clay": Color("#96684b"),
            "stone": Color("#86847b"), "timber": Color("#80654a"),
            "tin": Color("#5c716d"), "dark": Color("#393f3b"),
            "leaf": Color("#56754b"), "leaf_light": Color("#8d9e57"),
            "leaf_gold": Color("#b7a963"), "white": Color("#f9efd6"),
            "flower_pink": Color("#efa4a8"),
            "flower_yellow": Color("#eec96d")
        }
        var mat := StandardMaterial3D.new()
        mat.albedo_color = colors[id]
        mat.roughness = 0.94
        mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
        mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
        palette[id] = mat

func _p(id: String) -> StandardMaterial3D:
    return palette[id]

func _box(root: Node3D, dimensions: Vector3, at: Vector3,
        material: Material, spin: Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    node.mesh = mesh
    node.material_override = material
    node.position = at
    node.rotation = spin
    root.add_child(node)
    scenery_count += 1
    return node

func _ball(root: Node3D, center: Vector3, radius: Vector3,
        material: Material) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 10
    mesh.rings = 6
    node.mesh = mesh
    node.material_override = material
    node.position = center
    node.scale = radius
    root.add_child(node)
    scenery_count += 1
    return node

func _pole(root: Node3D, a: Vector3, b: Vector3, width: float,
        material: Material) -> MeshInstance3D:
    var vec := b - a
    var mesh := CylinderMesh.new()
    mesh.top_radius = width
    mesh.bottom_radius = width * 1.12
    mesh.height = vec.length()
    mesh.radial_segments = 7
    var node := MeshInstance3D.new()
    node.mesh = mesh
    node.material_override = material
    node.position = (a + b) * 0.5
    node.quaternion = Quaternion(Vector3.UP, vec.normalized())
    root.add_child(node)
    scenery_count += 1
    return node

func _painted_ground() -> void:
    # Colour-rich but flat ground keeps the physics floor at exactly y=0.
    # The soil pad's physically deformable surface renders ABOVE this.
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    for j in range(48):
        for i in range(48):
            var x0 := -70.0 + float(i) * (140.0 / 48.0)
            var z0 := -70.0 + float(j) * (140.0 / 48.0)
            var x1 := x0 + 140.0 / 48.0
            var z1 := z0 + 140.0 / 48.0
            var center := Vector2((x0+x1)*0.5, (z0+z1)*0.5)
            var is_work := center.x > -10.0 and center.x < 10.0                 and center.y > -23.0 and center.y < -1.6
            var is_road := absf(center.x - 0.2) < 5.8                 and center.y > -12.0 and center.y < 34.0
            var is_clay := center.x > 17.0 and center.x < 55.0                 and absf(center.y) < 35.0
            var c: Color = _p("earth").albedo_color if is_road or is_work else                 (_p("clay").albedo_color if is_clay else _p("grass").albedo_color)
            var variation := rng.randf_range(-0.085, 0.095)
            c = c.lightened(variation) if variation > 0 else c.darkened(-variation)
            if not (is_work or is_road or is_clay) and rng.randf() < 0.20:
                c = c.lerp(_p("grass_light").albedo_color, 0.35)
            for pos in [Vector3(x0, 0.009, z0), Vector3(x0, 0.009, z1),
                    Vector3(x1, 0.009, z1), Vector3(x0, 0.009, z0),
                    Vector3(x1, 0.009, z1), Vector3(x1, 0.009, z0)]:
                vertices.append(pos)
                normals.append(Vector3.UP)
                colors.append(c)
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    var terrain := ArrayMesh.new()
    terrain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var node := MeshInstance3D.new()
    node.name = "PaintedMeadow_VisualOnly"
    node.mesh = terrain
    # Broad brush bands plus stable fine speckling provide illustrated paint
    # texture without external copyrighted texture or giant photo backdrops.
    var brush := Shader.new()
    brush.code = """
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
varying vec3 painted_world;
void vertex() {
    painted_world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
float pigment(vec2 p) {
    return fract(sin(dot(floor(p),vec2(12.9898,78.233))) * 43758.5453);
}
void fragment() {
    vec2 uv = painted_world.xz;
    float wash = sin(uv.x*0.31+cos(uv.y*0.22))*cos(uv.y*0.21);
    float stipple = pigment(uv*7.0);
    float fleck = pigment(uv*21.0);
    ALBEDO = COLOR.rgb * (0.89+wash*0.105+stipple*0.16+fleck*0.06);
    ROUGHNESS = 1.0;
}
"""
    var surface := ShaderMaterial.new()
    surface.shader = brush
    node.material_override = surface
    add_child(node)
    scenery_count += 1

func _distant_hills() -> void:
    # Ring-like illustrated hills well beyond the physical 140m yard.
    var colors := [Color("#526d59"),Color("#6c835e"),
        Color("#7f936a"),Color("#a0aa80")]
    for n in range(17):
        var x := -115.0 + float(n) * 15.0
        var z := -79.0 + float(n % 3) * 6.0
        var rise := 19.0 + 7.0 * sin(float(n) * 1.17)
        _ball(self,Vector3(x,-7.5,z),
            Vector3(26.0,rise,21.0),colors[n%colors.size()])
    var village := Node3D.new()
    village.name = "Hillside_Village"
    village.position = Vector3(-21.0,5.2,-75.0)
    add_child(village)
    for i in range(8):
        var x := -13.0 + float(i) * 3.7
        var y := 3.5 + float(i%3)*1.10
        _box(village,Vector3(2.65,y,2.50),
            Vector3(x,y*0.5,0),_p("white"))
        _box(village,Vector3(3.0,0.32,2.8),
            Vector3(x,y+0.22,0),_p("clay"),
            Vector3(0,0,deg_to_rad(14 if i%2==0 else -14)))
    _box(village,Vector3(1.40,9.2,1.70),
        Vector3(4.5,5.2,0.25),_p("earth_light"))
    _box(village,Vector3(1.90,0.8,2.0),
        Vector3(4.5,10.0,0.25),_p("clay"))

func _farm_buildings() -> void:
    var b := Node3D.new()
    b.name = "Weatherboard_Barn"
    b.position = Vector3(-33.0, 0.0, -23.0)
    add_child(b)
    _box(b, Vector3(10.0, 4.6, 7.5), Vector3.ZERO + Vector3.UP*2.3, _p("timber"))
    _box(b, Vector3(9.5, 4.0, 0.12), Vector3(0, 2.12, -3.80), _p("earth_light"))
    _box(b, Vector3(4.4, 3.35, 0.15), Vector3(-1.3, 1.75, -3.88), _p("dark"))
    for x in [-4.7, -2.4, 0.0, 2.4, 4.7]:
        _box(b, Vector3(0.21, 4.8, 0.30), Vector3(x, 2.42, -3.86), _p("timber"))
    for y in [1.0, 2.2, 3.5, 4.5]:
        _box(b, Vector3(10.2, 0.19, 0.31), Vector3(0,y,-3.82), _p("earth_light"))
    # Shingled gable with actual inclined panels. No collision is needed.
    _box(b, Vector3(5.9, 0.27, 8.2), Vector3(-2.58, 5.31, 0),
        _p("tin"), Vector3(0,0,deg_to_rad(-26)))
    _box(b, Vector3(5.9, 0.27, 8.2), Vector3(2.58, 5.31, 0),
        _p("tin"), Vector3(0,0,deg_to_rad(26)))
    for x in [-4.8, 4.8]:
        for z in [-3.6, 3.6]:
            _pole(b, Vector3(x,0,z), Vector3(x,5.0,z), 0.15, _p("earth_light"))
    # Clear glazed workshop window, tool rack and warm exterior lights.
    _box(b, Vector3(2.2, 1.4, 0.16), Vector3(3.0, 2.3, -3.9), _p("dark"))
    for x in [2.28,3.72]:
        _box(b, Vector3(0.085, 1.5, 0.18), Vector3(x,2.3,-4.02), _p("timber"))
    _box(b, Vector3(1.2, 0.10, 0.5), Vector3(-3.4, 1.1,-4.2), _p("earth_light"))
    for z in [-2.5, -1.2, 0.8, 2.0]:
        _box(b, Vector3(2.4,0.08,0.30), Vector3(0.0, 3.0,z), _p("tin"))
    for pos in [Vector3(-3.9, 4.6,-3.98),Vector3(3.9,4.6,-3.98)]:
        _ball(b,pos,Vector3(0.20,0.20,0.2),_p("flower_yellow"))
    # Cascading flowering vines at the gable edge; clusters are light meshes.
    for n in range(52):
        var x := rng.randf_range(-4.9,-1.9)
        var y := rng.randf_range(3.0,5.7)
        var z := -3.99 + rng.randf_range(-0.22,0.16)
        var color_id := "flower_pink" if n%4!=0 else "white"
        _ball(b,Vector3(x,y,z),
            Vector3(0.07,0.08,0.07),_p(color_id))
    for n in range(10):
        var x := -4.85+float(n)*0.3
        _pole(b,Vector3(x,4.9,-4.03),
            Vector3(x+0.15,3.2-float(n%3)*0.16,-4.09),
            0.017,_p("leaf"))

func _wooden_fence() -> void:
    for side in [-1.0,1.0]:
        for i in range(17):
            var x: float = float(side) * 47.0
            var z := -43.0 + float(i) * 5.2
            _box(self, Vector3(0.19,1.52,0.19),Vector3(x,0.78,z),_p("timber"))
            if i<16:
                for y in [0.58,1.17]:
                    _box(self,Vector3(0.13,0.12,5.22),
                        Vector3(x, y,z+2.6),_p("earth_light"))

func _make_trees() -> void:
    for i in range(30):
        var x := rng.randf_range(-62.0, 62.0)
        var z := rng.randf_range(-63.0, 63.0)
        # Keep the active engineering site, camera and barn approach open.
        if (absf(x) < 22.0 and absf(z) < 34.0) or                 (x < -24.0 and x > -45.0 and z < -13.0 and z > -34.0):
            continue
        var h := rng.randf_range(4.8, 9.1)
        var origin := Vector3(x,0,z)
        _pole(self,origin,origin+Vector3.UP*h*0.72,
            rng.randf_range(0.18,0.35),_p("timber"))
        for n in range(9):
            var angle := float(n) * TAU / 9.0 + rng.randf_range(-0.35,0.35)
            var r := rng.randf_range(0.50,2.05)
            var yy := h * rng.randf_range(0.62,0.96)
            var pos := origin + Vector3(cos(angle)*r,yy,sin(angle)*r)
            _ball(self,pos,Vector3(rng.randf_range(1.1,2.0),
                rng.randf_range(0.85,1.65),rng.randf_range(1.1,1.9)),
                _p("leaf_light" if n % 4 == 0 else ("leaf_gold" if n%7==0 else "leaf")))
        scenery_count += 1

func _blade_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for angle in [0.0, PI/2.0]:
        var radial := Vector3(cos(angle),0,sin(angle))
        var a := -radial*0.039
        var b := radial*0.039
        var peak := Vector3(0.044,0.27,0.0)
        for v in [a,b,peak]:
            st.set_normal(Vector3.UP)
            st.add_vertex(v)
    for n in range(4):
        var t := float(n)*TAU/4.0+0.27
        var radial := Vector3(cos(t),0,sin(t))
        for v in [radial*-0.055,radial*0.050,
                Vector3(0.02,0.16+float(n%2)*0.12,0.01)]:
            st.set_normal(Vector3.UP)
            st.add_vertex(v)
    return st.commit()

func _make_instanced(mesh: Mesh, colors: Array[Color],
        positions: Array[Vector3], type_name: String, size_min: float,
        size_max: float) -> MultiMeshInstance3D:
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    mm.instance_count = positions.size()
    mm.mesh = mesh
    var node := MultiMeshInstance3D.new()
    node.name = type_name
    node.multimesh = mm
    node.custom_aabb = AABB(Vector3(-72,-1,-72),Vector3(144,16,144))
    add_child(node)
    for i in range(positions.size()):
        var angle := rng.randf_range(0.0,TAU)
        var scale_factor := rng.randf_range(size_min,size_max)
        var basis := Basis(Vector3.UP,angle).scaled(Vector3.ONE*scale_factor)
        mm.set_instance_transform(i,Transform3D(basis,positions[i]))
        mm.set_instance_color(i,colors[i%colors.size()])
    scenery_count += 1
    return node

func _ground_detail() -> void:
    var blades := _blade_mesh()
    # GPU wind bends only upper blade vertices, with a phase offset for
    # each instanced clump. The ground roots stay fixed.
    var wind := Shader.new()
    wind.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;
void vertex() {
    vec3 instance_world = (MODEL_MATRIX * vec4(0.0,0.0,0.0,1.0)).xyz;
    float wave = sin(TIME * 1.45 + instance_world.x * 0.57 +
        instance_world.z * 0.43);
    float gust = sin(TIME * 0.33 + instance_world.x * 0.094) * 0.035;
    float height = max(0.0,VERTEX.y);
    VERTEX.x += height * (wave * 0.075 + gust);
    VERTEX.z += height * cos(TIME * 1.04 + instance_world.z*0.52)*0.032;
}
void fragment() {
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 1.0;
}
"""
    var wind_material := ShaderMaterial.new()
    wind_material.shader = wind
    blades.surface_set_material(0,wind_material)
    var grass_positions: Array[Vector3] = []
    for i in range(11500):
        var x := rng.randf_range(-64.0,64.0)
        var z := rng.randf_range(-63.0,63.0)
        if (absf(x) < 13.0 and z < -0.8 and z > -23.5) or            (absf(x) < 5.0 and z > -7.0 and z < 32.0):
            continue
        grass_positions.append(Vector3(x,0.014,z))
    grass_group = _make_instanced(blades,[
        Color("#a1a85f"), Color("#688849"),Color("#547745"),
        Color("#d0bd6a"), Color("#86a65f")],
        grass_positions,"AnimatedMeadowGrass",0.62,1.48)
    var petal := SphereMesh.new()
    petal.radius = 0.060
    petal.height = 0.12
    petal.radial_segments = 6
    petal.rings = 3
    var petal_mat := StandardMaterial3D.new()
    petal_mat.vertex_color_use_as_albedo = true
    petal_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
    petal.surface_set_material(0,petal_mat)
    var flower_positions: Array[Vector3] = []
    for i in range(1750):
        var x := rng.randf_range(-57.0,57.0)
        var z := rng.randf_range(-58.0,58.0)
        if (absf(x) < 14.0 and z < 4.0 and z > -25.0):
            continue
        flower_positions.append(Vector3(x,0.31,z))
    flowers_group = _make_instanced(petal,[
        Color("#f5e9d0"),Color("#f1c69d"),Color("#e7a8a3"),Color("#f0db94")],
        flower_positions,"FloweringGrassland",0.5,1.4)
    var stone := SphereMesh.new()
    stone.radius = 0.20
    stone.height = 0.40
    stone.radial_segments = 7
    stone.rings = 4
    var stone_mat := StandardMaterial3D.new()
    stone_mat.vertex_color_use_as_albedo = true
    stone_mat.roughness = 1.0
    stone.surface_set_material(0,stone_mat)
    var pebbles: Array[Vector3] = []
    for i in range(340):
        var x := rng.randf_range(-15.0,15.0)
        var z := rng.randf_range(-29.0,18.0)
        if absf(x)<4.0 and z > -6.0 and z < 9.0:
            continue
        if absf(x)<9.2 and z > -21.0 and z < -2.7:
            continue
        pebbles.append(Vector3(x,0.025,z))
    pebble_group = _make_instanced(stone,[
        Color("#b1a491"),Color("#8f9386"),Color("#887a71"),Color("#c2b194")],
        pebbles,"GravelVerge",0.45,1.30)

func _clouds() -> void:
    for group in range(8):
        var cloud := Node3D.new()
        cloud.name = "Cotton_Cloud_%02d" % group
        cloud.position = Vector3(rng.randf_range(-62.0,62.0),
            rng.randf_range(23.0,35.0),rng.randf_range(-94.0,-58.0))
        add_child(cloud)
        for n in range(7):
            var puff := Vector3(float(n-3)*rng.randf_range(1.9,3.0),
                rng.randf_range(-0.6,2.6),rng.randf_range(-2.2,2.2))
            _ball(cloud,puff,Vector3(rng.randf_range(3.8,6.7),
                rng.randf_range(2.4,4.0),rng.randf_range(2.6,4.6)),
                _p("white"))
        cloud_nodes.append(cloud)

func _process(delta: float) -> void:
    # Slow drifting atmospheric backdrop. Pure visual transforms never
    # touch machine, payload or soil physics state.
    for cloud in cloud_nodes:
        if not is_instance_valid(cloud):
            continue
        cloud.position.x += delta * 0.21
        if cloud.position.x > 106.0:
            cloud.position.x = -106.0

func _digging_site_details() -> void:
    # Stakes and track imprints are only meshes, so they cannot block entry
    # or interfere with the excavation heightfield collision.
    for x in [-9.6, 9.6]:
        for z in [-22.2,-16.6,-10.9,-5.2,-1.0]:
            _box(self,Vector3(0.13,0.70,0.13),
                Vector3(x,0.35,z),_p("timber"))
            _box(self,Vector3(0.24,0.10,0.24),
                Vector3(x,0.68,z),_p("earth_light"))
    for side in [-0.88,0.88]:
        for i in range(21):
            var z := -2.4 + float(i) * 0.27
            _box(self,Vector3(0.41,0.011,0.13),
                Vector3(side,0.025,z),_p("clay"))
    # Wheel rut and compaction graphics along the loading approach.
    for side in [-0.58,0.58]:
        for i in range(50):
            var z := 2.2 + float(i) * 0.30
            _box(self,Vector3(0.27,0.006,0.16),
                Vector3(side,0.022,z),_p("earth"))
