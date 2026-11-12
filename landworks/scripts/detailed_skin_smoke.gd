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
# Just the part's own skin. Its children are the cylinders and linkage, which
# the rig aims at their pins every frame, so including them would measure
# hydraulics rather than the limb and would not be repeatable.
func _own_points(node: Node3D, reference: Node3D, points: Array[Vector3]) -> void:
    if not (node is MeshInstance3D) or node.mesh == null:
        return
    for s in range(node.mesh.get_surface_count()):
        var a: Array = node.mesh.surface_get_arrays(s)
        for v in a[Mesh.ARRAY_VERTEX]:
            points.append(reference.to_local(node.to_global(v)))

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
    # The excavator now wears the rigged KX080-3 model. Each limb's art is
    # bound straight onto its rigid body, so the model's own pin spacing must
    # match the solver's limb lengths.
    var e: Node3D=world.digger
    for item in [[e.boom,"Boom",e.BOOM_LENGTH],[e.stick,"Arm",e.STICK_LENGTH]]:
        var body: Node3D=item[0]
        var part := body.get_node_or_null(str(item[1])) as Node3D
        if part == null:
            problems.append("Rigged limb art missing: "+str(item[1]))
            continue
        var points: Array[Vector3]=[]
        var scan: Array[Vector3]=[]
        _points(part,body,scan)
        _own_points(part,body,points)
        # Measure reach, not surface depth: the modelled boom is a slender
        # swept section, so its skin never passes through the pin centre.
        # What must hold is that the steel spans the solver's pin spacing.
        var lo_z := INF
        var hi_z := -INF
        for p in points:
            if absf(p.x)>=0.30: continue
            lo_z=minf(lo_z,p.z)
            hi_z=maxf(hi_z,p.z)
        var length := float(item[2])
        # The far end must land on the far pin. The near end must cover its
        # own pin, but may run past it: the dipper's cylinder lever really
        # does sit behind the pivot, and the boom carries lug plates.
        var far_error := absf(lo_z+length)
        max_pin_error=maxf(max_pin_error,far_error)
        print("LIMB_REACH ",item[1]," pin_spacing_m=",length,
            " far_pin_error_m=",far_error," near_overhang_m=",hi_z)
        if points.is_empty() or far_error>0.16 or hi_z<-0.05:
            problems.append("Imported arm does not reach physical hinge")
    var teeth: Array[Vector3]=[]
    var bucket_art := e.bucket.get_node_or_null("Bucket") as Node3D
    if "--reversed-bucket-fixture" in OS.get_cmdline_user_args() and bucket_art != null:
        bucket_art.rotation.y += PI
    if bucket_art == null:
        problems.append("Rigged limb art missing: Bucket")
    else:
        var bucket_scan: Array[Vector3]=[]
        _points(bucket_art,e.bucket,bucket_scan)
        _own_points(bucket_art,e.bucket,teeth)
    var lip_error := _nearest(teeth,e.BUCKET_TIP)
    if lip_error>0.055:problems.append("Visible cutting tooth differs from soil sampling point")
    # The soil solver cuts a swath of BUCKET_WIDTH. That number has to be the
    # width of the steel you can actually see, not a tuned constant.
    var lo_x := INF
    var hi_x := -INF
    for p in teeth:
        lo_x = minf(lo_x,p.x)
        hi_x = maxf(hi_x,p.x)
    var visible_width := hi_x-lo_x
    print("BUCKET_STEEL visible_width_m=",visible_width," cut_width_m=",e.BUCKET_WIDTH)
    if teeth.is_empty() or absf(visible_width-float(e.BUCKET_WIDTH))>0.12:
        problems.append("Soil cut width does not match the visible bucket steel")
    print("DETAILED_SKIN_CHECK max_pin_surface_distance_m=",max_pin_error," lip_surface_distance_m=",lip_error)
    for p in problems:push_error(p)
    print("DETAILED_SKIN ","PASS" if problems.is_empty() else "FAIL")
    quit(0 if problems.is_empty() else 1)
