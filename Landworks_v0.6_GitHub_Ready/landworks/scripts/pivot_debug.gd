# Runtime visual alignment aids, not physics joints. Toggle using F3/D-pad up.
extends Node3D

const M = preload("res://landworks/scripts/mesh_factory.gd")

func _ready() -> void:
    visible = false

func mark(target: Node3D, title: String, size: float = 0.25) -> void:
    # Called after machine has spawned its pivots; axes remain attached as the
    # wheel/slew/boom/stick/bucket rotates. No collision shapes are added.
    var marker := Node3D.new()
    marker.name = "Pivot_Debug_" + title.replace(" ", "_")
    target.add_child(marker)
    var ball := SphereMesh.new()
    ball.radius = size * 0.13
    ball.height = size * 0.26
    var node := MeshInstance3D.new()
    node.mesh = ball
    node.material_override = M.paint(Color("#ffffc6"))
    marker.add_child(node)
    M.block(marker, Vector3(size, size * 0.07, size * 0.07),
        Vector3(size * 0.5, 0, 0), Color("#fa4747"))
    M.block(marker, Vector3(size * 0.07, size, size * 0.07),
        Vector3(0, size * 0.5, 0), Color("#55fa60"))
    M.block(marker, Vector3(size * 0.07, size * 0.07, size),
        Vector3(0, 0, size * 0.5), Color("#478afa"))
    var label := Label3D.new()
    label.text = title
    label.font_size = 32
    label.pixel_size = 0.003
    label.position = Vector3(0, size * 1.25, 0)
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    marker.add_child(label)
    marker.visible = true
    _markers.append(marker)

var _markers: Array[Node3D] = []

func set_markers_visible(show: bool) -> void:
    for marker in _markers:
        marker.visible = show

func bind_tractor(machine: RigidBody3D) -> void:
    mark(machine, "CHASSIS", 0.27)
    var wheels: Array = machine.get("wheel_data")
    for i in range(wheels.size()):
        var item: Dictionary = wheels[i]
        var mount: Node3D = item["root"]
        mark(mount, "FRONT" if item["steering"] else "REAR", 0.20)
    set_markers_visible(false)

func bind_excavator(machine: RigidBody3D) -> void:
    mark(machine, "TRACK FRAME", 0.40)
    mark(machine.get("upper") as Node3D, "SLEW", 0.50)
    mark(machine.get("boom") as Node3D, "BOOM", 0.35)
    mark(machine.get("stick") as Node3D, "STICK", 0.32)
    mark(machine.get("bucket") as Node3D, "BUCKET", 0.25)
    var tracks: Array = machine.get("track_roots")
    for track in tracks:
        mark(track as Node3D, "TRACK", 0.24)
    set_markers_visible(false)
