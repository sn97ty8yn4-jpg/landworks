# Original, self-contained temporary geometry. Replace with properly licensed GLB parts.
extends RefCounted

static func paint(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 0.78
    mat.metallic = metallic
    return mat

static func block(parent: Node3D, dim: Vector3, at: Vector3, color: Color, angle: Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var mesh_node := MeshInstance3D.new()
    var shape := BoxMesh.new()
    shape.size = dim
    mesh_node.mesh = shape
    mesh_node.material_override = paint(color)
    mesh_node.position = at
    mesh_node.rotation = angle
    parent.add_child(mesh_node)
    return mesh_node

static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, color: Color, along_x: bool = false) -> MeshInstance3D:
    var mesh_node := MeshInstance3D.new()
    var shape := CylinderMesh.new()
    shape.top_radius = radius
    shape.bottom_radius = radius
    shape.height = height
    shape.radial_segments = 24
    mesh_node.mesh = shape
    mesh_node.material_override = paint(color)
    mesh_node.position = at
    if along_x:
        mesh_node.rotation.z = PI * 0.5
    parent.add_child(mesh_node)
    return mesh_node

static func tyre(parent: Node3D, radius: float, width: float, at: Vector3, turf: bool = true) -> Node3D:
    var support := Node3D.new()
    support.position = at
    parent.add_child(support)
    cylinder(support, radius, width, Vector3.ZERO, Color("#242629"), true)
    cylinder(support, radius * 0.46, width + 0.007, Vector3.ZERO, Color("#8c8f8b"), true)
    cylinder(support, radius * 0.21, width + 0.015, Vector3.ZERO, Color("#353a3c"), true)
    # Small, numerous turf lugs; intentionally NOT agricultural chevron tyres.
    if turf:
        for index in range(20):
            var angle := float(index) * TAU / 20.0
            var lug := block(support, Vector3(width * 0.85, 0.042, 0.11),
                Vector3(0.0, sin(angle) * radius, cos(angle) * radius), Color("#333638"))
            lug.rotation.x = -angle
    return support

static func beam(parent: Node3D, length: float, thickness: float, color: Color) -> void:
    block(parent, Vector3(thickness, thickness, length), Vector3(0, 0, -length * 0.5), color)
