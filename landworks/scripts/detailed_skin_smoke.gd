# Check the imported geometry against the live rig, not just export metadata.
extends SceneTree
const SCENE = preload("res://landworks/scenes/sandbox_world.tscn")
var problems: Array[String] = []
func _initialize() -> void:
    root.add_child.call_deferred(SCENE.instantiate())
    call_deferred("_check")
func _points(node: Node, reference: Node3D, points: Array[Vector3]) -> void:
    if node is CollisionObject3D or node is CollisionShape3D or node is Joint3D:
        problems.append("Physics node inside imported cosmetic mesh: "+str(node.name))
    if node is MeshInstance3D and node.mesh != null:
        for s in range(node.mesh.get_surface_count()):
            var a: Array = node.mesh.surface_get_arrays(s)
            for v in a[Mesh.ARRAY_VERTEX]:
                points.append(reference.to_local(node.to_global(v)))
    for child in node.get_children():
        _points(child,reference,points)
func _nearest(points: Array[Vector3], target: Vector3) -> float:
    var distance := INF
    for point in points:
        # Hinge/soil contact is a transverse X line through a solid surface;
        # there need not be a vertex on the centre of a pin cap or tooth.
        if absf(point.x) < 0.30:
            distance = minf(distance,Vector2(point.y,point.z).distance_to(Vector2(target.y,target.z)))
    return distance
func _check() -> void:
    await process_frame
    var world: Node3D = root.get_child(root.get_child_count()-1)
    var max_pin_error := 0.0
    for wheel in world.tractor.wheel_data:
        var spin: Node3D = wheel["visual"]
        var part := spin.get_child(spin.get_child_count()-1)
        var points: Array[Vector3] = []
        _points(part,spin,points)
        var lo := Vector3(INF,INF,INF)
        var hi := -lo
        for p in points:
            lo=lo.min(p);hi=hi.max(p)
        if absf((lo.y+hi.y)*0.5)>0.001 or absf((lo.z+hi.z)*0.5)>0.001:
            problems.append("Wheel geometry offset from live rotation axis")
        if absf((hi.y-lo.y)*0.5-float(wheel["radius"]))>0.008:
            problems.append("Tyre radius differs from physical contact radius")
    var e: Node3D=world.digger
    for item in [[e.boom,"kx080_boom",3.0],[e.stick,"kx080_stick",2.32]]:
        var body: Node3D=item[0]
        var part: Node3D=body.get_node("Engineered_"+str(item[1]))
        var points: Array[Vector3]=[]
        _points(part,body,points)
        for pin in [Vector3.ZERO,Vector3(0,0,-float(item[2]))]:
            var distance := _nearest(points,pin)
            max_pin_error=maxf(max_pin_error,distance)
            if distance>0.075:problems.append("Imported arm does not reach physical hinge")
    var teeth: Array[Vector3]=[]
    if "--reversed-bucket-fixture" in OS.get_cmdline_user_args():
        e.bucket.get_node("Engineered_kx080_bucket").rotation.z = 0.0
    _points(e.bucket.get_node("Engineered_kx080_bucket"),e.bucket,teeth)
    var lip_error := _nearest(teeth,Vector3(0,0,-e.BUCKET_LENGTH))
    if lip_error>0.035:problems.append("Visible cutting tooth differs from soil sampling point")
    # Check the actual shell, not the transform: a reversed bucket can still
    # put its hinge and teeth exactly on the two expected transverse lines.
    var shell_y := 0.0
    var shell_samples := 0
    for p in teeth:
        if absf(p.x)<0.30 and p.z < -0.20 and p.z > -0.65:
            shell_y += p.y
            shell_samples += 1
    shell_y /= maxf(float(shell_samples),1.0)
    print("BUCKET_SHELL mean_y_m=",shell_y," samples=",shell_samples)
    if shell_samples == 0 or shell_y < 0.03:
        problems.append("Bucket shell is reversed: cavity must face the negative-Y fill volume")
    print("DETAILED_SKIN_CHECK max_pin_surface_distance_m=",max_pin_error," lip_surface_distance_m=",lip_error)
    for p in problems:push_error(p)
    print("DETAILED_SKIN ","PASS" if problems.is_empty() else "FAIL")
    quit(0 if problems.is_empty() else 1)
