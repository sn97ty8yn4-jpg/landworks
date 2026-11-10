# High-detail stylised visual shells around the existing VERIFIED rigid bodies.
# These meshes never become collision shapes and do not alter joints, mass,
# engine forces, track patches or soil cutting. Not OEM CAD nor exact scan.
extends Node3D

const TRACTOR_ORANGE := Color("#ed7a16")
const ORANGE_HIGHLIGHT := Color("#ff9c34")
const ORANGE_SHADOW := Color("#b95711")
const RUBBER := Color("#252a2b")
const TRACK_EDGE := Color("#42484a")
const GLASS := Color("#49696e")
const STEEL := Color("#aeb4b1")
const DARK := Color("#333c41")
const LIGHT := Color("#f3e4be")

var tractor: RigidBody3D
var excavator: Node3D
var cylinders: Array[Dictionary] = []
var parts_count := 0
var glass_mat: StandardMaterial3D
var metal_mat: StandardMaterial3D
var ink_mat: ShaderMaterial

func attach_to(tractor_machine: RigidBody3D, digger: Node3D) -> void:
    tractor = tractor_machine
    excavator = digger
    _init_materials()
    _dress_tractor()
    _dress_excavator()
    print("LANDWORKS_MACHINE_ART_READY pieces=", parts_count,
        " cylinders=", cylinders.size())

func _paint(color: Color, metallic: float = 0.0,
        roughness: float = 0.77) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = metallic
    material.roughness = roughness
    material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
    if ink_mat != null:
        material.next_pass = ink_mat
    return material

func _init_materials() -> void:
    # A thin silhouette pass gives Kubota chassis, tracks, arm and teeth a
    # coherent ink-edged 2.5D animated-film treatment.
    var ink_shader := Shader.new()
    ink_shader.code = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
uniform vec4 ink_color : source_color = vec4(0.13,0.14,0.14,1.0);
uniform float line_width = 0.012;
void vertex() {
    VERTEX += NORMAL * line_width;
}
void fragment() {
    ALBEDO = ink_color.rgb;
}
"""
    ink_mat = ShaderMaterial.new()
    ink_mat.shader = ink_shader
    glass_mat = _paint(Color("#7fadb1"), 0.12, 0.18)
    glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    glass_mat.albedo_color.a = 0.46
    metal_mat = _paint(STEEL, 0.60, 0.36)

func _box(parent: Node3D, size: Vector3, p: Vector3,
        color: Color, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var n := MeshInstance3D.new()
    var m := BoxMesh.new()
    m.size = size
    n.mesh = m
    n.material_override = glass_mat if color == GLASS else _paint(color)
    n.position = p
    n.rotation = rotation
    parent.add_child(n)
    parts_count += 1
    return n

func _sphere(parent: Node3D, pos: Vector3, size: Vector3,
        color: Color) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 15
    mesh.rings = 8
    var n := MeshInstance3D.new()
    n.mesh = mesh
    n.material_override = _paint(color)
    n.position = pos
    n.scale = size
    parent.add_child(n)
    parts_count += 1
    return n

func _cyl(parent: Node3D, radius: float, length: float, pos: Vector3,
        color: Color, along_x: bool = false) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = length
    mesh.radial_segments = 18
    var n := MeshInstance3D.new()
    n.mesh = mesh
    n.material_override = _paint(color,0.12)
    n.position = pos
    if along_x:
        n.rotation.z = PI*0.5
    parent.add_child(n)
    parts_count += 1
    return n

func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float,
        color: Color) -> MeshInstance3D:
    var distance := b - a
    var n := _cyl(parent,radius,distance.length(),(a+b)*0.5,color)
    n.quaternion = Quaternion(Vector3.UP, distance.normalized())
    return n

func _label(parent: Node3D, words: String, pos: Vector3,
        rot: Vector3, px: float = 0.004) -> void:
    var l := Label3D.new()
    l.text = words
    l.font_size = 42
    l.pixel_size = px
    l.modulate = LIGHT
    l.outline_size = 0
    l.position = pos
    l.rotation = rot
    parent.add_child(l)
    parts_count += 1

func _hide_primitive_art(body: Node3D) -> void:
    # Hide only original placeholder MeshInstance3D children. Never touch
    # CollisionShape3D, rigid bodies, pin joints or imported GLB assets.
    for child in body.get_children():
        if child is MeshInstance3D:
            child.visible = false

func _dress_tractor() -> void:
    # Respect a genuine, later installed, separately rigged licensed asset.
    var existing: Node3D = tractor.body_visual
    if existing.get_parent().get_node_or_null("LicensedGLBVisual") != null:
        return
    existing.visible = false
    var root := Node3D.new()
    root.name = "B7100HST_DetailedVisual_Proportional"
    tractor.add_child(root)
    # Separate bonnet, sloped grille, horizontal louvres and front lamp housings.
    _box(root,Vector3(0.86,0.45,1.26),Vector3(0,0.33,-0.42),TRACTOR_ORANGE)
    _box(root,Vector3(0.83,0.07,1.22),Vector3(0,0.57,-0.42),ORANGE_HIGHLIGHT)
    _box(root,Vector3(0.84,0.42,0.10),Vector3(0,0.31,-1.075),DARK)
    _box(root,Vector3(0.79,0.31,0.035),Vector3(0,0.30,-1.145),RUBBER)
    for y in [0.18,0.25,0.32,0.39]:
        _box(root,Vector3(0.70,0.028,0.038),Vector3(0,y,-1.165),STEEL)
    for x in [-0.265,0.265]:
        _cyl(root,0.16,0.070,Vector3(x,0.455,-1.16),LIGHT)
        _cyl(root,0.178,0.018,Vector3(x,0.455,-1.194),DARK)
    for x in [-0.435,0.435]:
        _box(root,Vector3(0.033,0.28,0.72),
            Vector3(x,0.32,-0.43),ORANGE_SHADOW)
        for n in range(5):
            _box(root,Vector3(0.014,0.022,0.080),
                Vector3(x+(0.01 if x>0 else -0.01),0.22+float(n)*0.055,-0.48),
                DARK)
    # Diesel engine block, axle, castings, fuel filler and steering console.
    _box(root,Vector3(0.68,0.30,0.56),Vector3(0,-0.03,-0.63),DARK)
    _box(root,Vector3(0.62,0.21,0.58),Vector3(0,-0.08,0.19),TRACK_EDGE)
    _cyl(root,0.062,0.10,Vector3(0.17,0.61,-0.55),DARK)
    _rod(root,Vector3(0.28,0.47,-0.75),Vector3(0.28,1.13,-0.76),0.065,DARK)
    _cyl(root,0.097,0.042,Vector3(0.28,1.13,-0.76),DARK)
    _box(root,Vector3(0.89,0.12,0.75),Vector3(0,0.15,0.46),ORANGE_SHADOW)
    _box(root,Vector3(0.57,0.40,0.45),Vector3(0,0.54,0.56),DARK)
    _box(root,Vector3(0.62,0.15,0.44),Vector3(0,0.77,0.60),RUBBER)
    _box(root,Vector3(0.53,0.38,0.11),Vector3(0,0.88,0.82),DARK)
    # Wheel and front cowl fenders are sized around 29 inch rear turf tyres.
    for side in [-1.0,1.0]:
        _sphere(root,Vector3(float(side)*0.42,0.42,0.69),
            Vector3(0.24,0.10,0.41),TRACTOR_ORANGE)
        _box(root,Vector3(0.11,0.11,0.35),
            Vector3(float(side)*0.50,0.32,0.69),ORANGE_SHADOW)
    # Roll-over protection structure, clearly distinct from exhaust.
    for x in [-0.48,0.48]:
        _rod(root,Vector3(x,0.28,0.82),Vector3(x,1.91,0.83),0.042,DARK)
    _rod(root,Vector3(-0.49,1.91,0.83),Vector3(0.49,1.91,0.83),0.049,DARK)
    _label(root,"B7100 HST",Vector3(0.45,0.45,-0.33),
        Vector3(0,PI*0.50,0),0.00245)
    _label(root,"KUBOTA",Vector3(0,0.51,-1.22),Vector3.ZERO,0.0029)
    for wheel in tractor.wheel_data:
        var visual: Node3D = wheel["visual"]
        if visual.get_node_or_null("LicensedGLBVisual") != null:
            continue
        for kid in visual.get_children():
            if kid is Node3D:
                kid.visible = false
        var radius: float = wheel["radius"]
        var width: float = 0.205 if bool(wheel["steering"]) else 0.305
        _cyl(visual,radius,width,Vector3.ZERO,RUBBER,true)
        _cyl(visual,radius*0.53,width+0.013,Vector3.ZERO,ORANGE_SHADOW,true)
        _cyl(visual,radius*0.37,width+0.022,Vector3.ZERO,TRACTOR_ORANGE,true)
        _cyl(visual,radius*0.13,width+0.030,Vector3.ZERO,STEEL,true)
        # Close-spaced R3-like turf bars instead of agricultural chevrons.
        for n in range(28):
            var angle := TAU*float(n)/28.0
            var lug := _box(visual,Vector3(width*0.93,0.038,0.089),
                Vector3(0,sin(angle)*radius,cos(angle)*radius),TRACK_EDGE)
            lug.rotation.x = -angle

func _dress_excavator() -> void:
    _hide_primitive_art(excavator.undercarriage)
    _hide_primitive_art(excavator.upper)
    _hide_primitive_art(excavator.boom)
    _hide_primitive_art(excavator.stick)
    _hide_primitive_art(excavator.bucket)
    var under: Node3D = excavator.undercarriage
    var upper: Node3D = excavator.upper
    var boom: Node3D = excavator.boom
    var stick: Node3D = excavator.stick
    var bucket: Node3D = excavator.bucket
    # Twin 3.1m track assemblies, separated ~1.72m (total ~2.20m).
    _box(under,Vector3(1.5,0.24,2.52),Vector3(0,0.72,0.0),DARK)
    for side in [-1.0,1.0]:
        var xx := float(side)*0.86
        _box(under,Vector3(0.49,0.46,3.1),Vector3(xx,0.32,0),RUBBER)
        for n in range(28):
            var zz := -1.49 + float(n)*0.11
            _box(under,Vector3(0.54,0.055,0.075),
                Vector3(xx,0.078,zz),TRACK_EDGE)
        for zz in [-1.12,-0.40,0.35,1.11]:
            _cyl(under,0.19,0.51,Vector3(xx,0.35,zz),DARK,true)
            _cyl(under,0.091,0.525,Vector3(xx,0.35,zz),STEEL,true)
        _box(under,Vector3(0.52,0.08,3.08),Vector3(xx,0.60,0),TRACK_EDGE)
    _cyl(under,0.63,0.13,Vector3(0,0.98,0),DARK)
    # Rear ballast, engine enclosure, counterweight bulge and service vents.
    _box(upper,Vector3(1.90,0.73,2.15),Vector3(0,1.54,0.35),TRACTOR_ORANGE)
    _sphere(upper,Vector3(0,1.54,1.10),
        Vector3(0.95,0.37,0.47),ORANGE_SHADOW)
    _box(upper,Vector3(1.84,0.13,1.90),
        Vector3(0,1.955,0.32),ORANGE_HIGHLIGHT)
    _box(upper,Vector3(1.48,0.33,0.58),
        Vector3(0,1.58,1.18),ORANGE_SHADOW)
    for side in [-1.0,1.0]:
        var xside := float(side)*0.955
        _box(upper,Vector3(0.017,0.38,0.97),
            Vector3(xside,1.55,0.66),DARK)
        for n in range(10):
            _box(upper,Vector3(0.021,0.023,0.72),
                Vector3(xside+(0.015 if side>0 else -0.015),
                    1.39+float(n)*0.035,0.71),TRACK_EDGE)
        _label(upper,"KX080-3",Vector3(xside*1.02,1.91,0.28),
            Vector3(0,-PI*0.5 if side<0 else PI*0.5,0),0.0032)
    # Operator cab left side with dark frame, segmented glass and roof beacon.
    _box(upper,Vector3(0.88,1.36,1.16),
        Vector3(-0.49,2.22,-0.34),DARK)
    _box(upper,Vector3(0.83,0.92,1.07),
        Vector3(-0.49,2.36,-0.34),GLASS)
    _box(upper,Vector3(0.82,0.91,0.12),
        Vector3(-0.49,2.34,-0.93),DARK)
    _box(upper,Vector3(0.73,0.79,0.023),
        Vector3(-0.49,2.36,-1.00),GLASS)
    _box(upper,Vector3(0.94,0.16,1.23),
        Vector3(-0.49,2.95,-0.34),TRACTOR_ORANGE)
    _box(upper,Vector3(0.05,1.05,1.15),
        Vector3(-0.94,2.27,-0.34),DARK)
    _box(upper,Vector3(0.012,0.85,0.98),
        Vector3(-0.965,2.38,-0.34),GLASS)
    for pos in [Vector3(-0.17,2.96,-0.90),Vector3(-0.82,2.96,-0.90)]:
        _box(upper,Vector3(0.24,0.17,0.16),pos,LIGHT)
    _cyl(upper,0.09,0.09,Vector3(-0.61,3.07,-0.22),
        Color("#efc254"))
    # Boom/stick are measured from original rigid-body joint origins,
    # not moved relative to their working hinge pivots.
    _box(boom,Vector3(0.51,0.54,2.95),
        Vector3(0,0,-1.53),TRACTOR_ORANGE)
    _box(boom,Vector3(0.55,0.12,2.83),
        Vector3(0,0.34,-1.57),ORANGE_HIGHLIGHT)
    for z in [-0.25,-2.72]:
        _cyl(boom,0.22,0.56,Vector3(0,0,z),DARK,true)
        _cyl(boom,0.095,0.57,Vector3(0,0,z),STEEL,true)
    _box(stick,Vector3(0.41,0.39,2.27),
        Vector3(0,0,-1.15),TRACTOR_ORANGE)
    _box(stick,Vector3(0.44,0.12,2.16),
        Vector3(0,0.26,-1.15),ORANGE_HIGHLIGHT)
    for z in [-0.06,-2.24]:
        _cyl(stick,0.20,0.49,Vector3(0,0,z),DARK,true)
    # Visual bucket has an open upper mouth, rounded back and five teeth.
    # Collision still uses the original proxy, preserving measured force tests.
    _box(bucket,Vector3(0.82,0.09,0.87),
        Vector3(0,-0.20,-0.41),DARK)
    _box(bucket,Vector3(0.85,0.43,0.11),
        Vector3(0,-0.04,-0.78),TRACK_EDGE)
    for side in [-1.0,1.0]:
        _box(bucket,Vector3(0.10,0.47,0.82),
            Vector3(float(side)*0.39,0.02,-0.40),DARK)
        _box(bucket,Vector3(0.11,0.15,0.81),
            Vector3(float(side)*0.39,-0.22,-0.40),STEEL)
    for n in range(5):
        _box(bucket,Vector3(0.105,0.085,0.23),
            Vector3(-0.33+float(n)*0.165,-0.24,-0.89),STEEL)
    _label(boom,"KUBOTA",Vector3(0.27,0.12,-1.48),
        Vector3(0,PI*0.5,0),0.005)
    # Pinned hydraulic visual cylinders and chrome rods track rigid bodies.
    _add_cylinder(upper,Vector3(0.47,1.68,-0.07),
        boom,Vector3(0.26,-0.26,-1.43),0.105)
    _add_cylinder(upper,Vector3(-0.47,1.68,-0.07),
        boom,Vector3(-0.26,-0.26,-1.43),0.105)
    _add_cylinder(boom,Vector3(0,0.45,-1.20),
        stick,Vector3(0,0.38,-0.80),0.089)
    _add_cylinder(stick,Vector3(0,0.30,-1.03),
        bucket,Vector3(0,0.32,-0.38),0.072)

func _add_cylinder(a_body: Node3D, a_local: Vector3,
        b_body: Node3D, b_local: Vector3, size: float) -> void:
    var barrel := _cyl(self,size,1.0,Vector3.ZERO,ORANGE_SHADOW)
    var chrome := _cyl(self,size*0.62,1.0,Vector3.ZERO,STEEL)
    cylinders.append({"a":a_body,"b":b_body,
        "p":a_local,"q":b_local,"barrel":barrel,"chrome":chrome})

func _position_rod(node: MeshInstance3D, a: Vector3, b: Vector3) -> void:
    var span := b-a
    if span.length() < 0.01:
        return
    node.global_position = (a+b)*0.5
    node.quaternion = Quaternion(Vector3.UP,span.normalized())
    var mesh: CylinderMesh = node.mesh
    mesh.height = span.length()

func _process(_delta: float) -> void:
    for c in cylinders:
        var a: Node3D = c["a"]
        var b: Node3D = c["b"]
        if not is_instance_valid(a) or not is_instance_valid(b):
            continue
        var p: Vector3 = a.to_global(c["p"])
        var q: Vector3 = b.to_global(c["q"])
        _position_rod(c["barrel"],p,p.lerp(q,0.64))
        _position_rod(c["chrome"],p.lerp(q,0.61),q)
