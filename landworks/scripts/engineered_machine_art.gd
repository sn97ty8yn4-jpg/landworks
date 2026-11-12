# Original segmented GLBs. Cosmetic parts follow genuine rigid bodies; they
# never create collisions, set chassis transforms or animate the working pins.
extends "res://landworks/scripts/machine_art.gd"

const ASSET_DIR := "res://landworks/assets/engineered/"
const TRACK_RADIUS := 0.27
const TRACK_HALF_STRAIGHT := 1.28
const TRACK_LOOP := 4.0 * TRACK_HALF_STRAIGHT + TAU * TRACK_RADIUS
const SHOES_PER_SIDE := 54

var track_multimeshes: Array[MultiMesh] = []
var track_phase := [0.0, 0.0]
var rams: Array[Dictionary] = []
var linkage_rods: Array[MeshInstance3D] = []
var link_pin: MeshInstance3D
var bucket_ram: Dictionary
var bucket_fill: MeshInstance3D
var fill_step := -1
var fill_material := ""
var custom_parts_loaded := 0
var cab: Node3D
var maximum_linkage_error_m := 0.0
var minimum_ram_extension_m := 1000.0

func _init_materials() -> void:
    # Fine engineering parts should retain small gaps and highlights. The
    # fallback's 12mm outline would close grille openings and tyre grooves.
    super._init_materials()
    ink_mat.set_shader_parameter("line_width", 0.0015)

func _load_part(parent: Node3D, filename: String) -> Node3D:
    var asset := "kx080_upper_cab_rig" if filename == "kx080_upper" else filename
    var resource := load(ASSET_DIR + asset + ".glb") as PackedScene
    if resource == null:
        push_error("Missing engineered machine part: " + filename)
        return null
    var part := resource.instantiate() as Node3D
    part.name = "Engineered_" + filename
    if filename == "kx080_bucket":
        # The source export inverted both transverse axes. Keep the hinge-to-
        # tooth (-Z) axis, but put the shell behind the inward-facing cavity.
        # This is cosmetic only: contact, fill and linkage use the live rig.
        part.rotation.z = PI
    if filename.begins_with("kx080_"):
        _refine_finish(part,filename)
    parent.add_child(part)
    custom_parts_loaded += 1
    return part

func _refine_finish(node: Node, part_name: String) -> void:
    if node is MeshInstance3D:
        for surface in range(node.mesh.get_surface_count()):
            var original := node.mesh.surface_get_material(surface) as StandardMaterial3D
            if original == null: continue
            var paint := "Orange" in original.resource_name
            var worn := part_name in ["kx080_bucket","kx080_undercarriage"] and (
                "Graphite" in original.resource_name or "Track_Steel" in original.resource_name)
            if not paint and not worn: continue
            var finish := ShaderMaterial.new()
            finish.shader = preload("res://landworks/assets/engineered/field_finish.gdshader")
            finish.set_shader_parameter("source_paint",original.albedo_texture)
            finish.set_shader_parameter("has_texture",original.albedo_texture != null)
            finish.set_shader_parameter("base_tint",original.albedo_color)
            finish.set_shader_parameter("orange_paint",paint)
            finish.set_shader_parameter("wear",0.65 if worn else 0.0)
            node.set_surface_override_material(surface,finish)
    for child in node.get_children(): _refine_finish(child,part_name)

func _dress_tractor() -> void:
    # Respect any licensed user model installed at the existing import boundary.
    if tractor.get_node_or_null("LicensedGLBVisual") != null:
        return
    tractor.body_visual.visible = false
    _load_part(tractor, "b7100_body")
    for wheel in tractor.wheel_data:
        var mount: Node3D = wheel["visual"]
        if mount.get_node_or_null("LicensedGLBVisual") != null:
            continue
        for child in mount.get_children():
            if child is Node3D:
                child.visible = false
        var axle := "front" if bool(wheel["steering"]) else "rear"
        var side := "l" if Vector3(wheel["mount"]).x < 0.0 else "r"
        _load_part(mount, "b7100_wheel_"+axle+"_"+side)

func _dress_excavator() -> void:
    var bodies := [excavator.undercarriage, excavator.upper,
        excavator.boom, excavator.stick, excavator.bucket]
    var files := ["kx080_undercarriage", "kx080_upper", "kx080_boom",
        "kx080_stick", "kx080_bucket"]
    for i in range(bodies.size()):
        _hide_primitive_art(bodies[i])
        _load_part(bodies[i], files[i])
    cab = preload("res://landworks/scripts/detailed_cab.gd").new()
    cab.name = "DetailedOperatorStation"
    excavator.upper.add_child(cab)
    cab.attach(excavator.upper.get_node("Engineered_kx080_upper"))
    # Bridge the source slew-bearing stack to the existing physical slew plane.
    _cyl(excavator.undercarriage,0.58,0.18,Vector3(0,0.86,0),DARK)
    # Actual linkage attachment ears follow the bucket; no free-floating pins.
    for side in [-1.0,1.0]:
        _rod(excavator.bucket,Vector3(side*0.19,0.02,0),
            Vector3(side*0.19,0.23,-0.23),0.034,DARK)
    _cyl(excavator.bucket,0.065,0.46,Vector3(0,0.23,-0.23),STEEL,true)
    _build_tracks()
    # One central boom ram, one dipper ram and a four-bar bucket linkage.
    # Fixed barrel lengths; only the EXPOSED chrome rod length changes.
    _make_ram(excavator.upper, Vector3(0.48,1.20,-0.49),
        excavator.boom, Vector3(0,0.40,-0.80), 0.58, 0.080)
    _make_ram(excavator.boom, Vector3(0,0.75,-1.18),
        excavator.stick, Vector3(0,0.32,-0.37), 0.96, 0.066)
    bucket_ram = _make_ram(excavator.stick, Vector3(0,0.27,-0.63),
        excavator.bucket, Vector3(0,0.23,-0.23), 0.91, 0.053)
    for i in range(4):
        linkage_rods.append(_cyl(self,0.026,0.1,Vector3.ZERO,ORANGE_SHADOW))
    link_pin = _cyl(self,0.046,0.48,Vector3.ZERO,STEEL,true)
    bucket_fill = MeshInstance3D.new()
    bucket_fill.name = "ActualStoredSoilVisual"
    excavator.bucket.add_child(bucket_fill)
    bucket_fill.visible = false
    print("ENGINEERED_MACHINES_READY parts=",custom_parts_loaded,
        " moving_track_shoes=",SHOES_PER_SIDE*2,
        " bucket_linkage=four_bar barrels=fixed_length")

func _first_mesh(node: Node) -> Mesh:
    if node is MeshInstance3D:
        return node.mesh
    for child in node.get_children():
        var found := _first_mesh(child)
        if found != null:
            return found
    return null

func _build_tracks() -> void:
    var source := (load(ASSET_DIR+"kx080_track_shoe.glb") as PackedScene).instantiate()
    var shoe := _first_mesh(source)
    for side in [-1.0,1.0]:
        var instance := MultiMeshInstance3D.new()
        instance.name = "CirculatingTrackShoes_Left" if side < 0 else "CirculatingTrackShoes_Right"
        var multi := MultiMesh.new()
        multi.transform_format = MultiMesh.TRANSFORM_3D
        multi.mesh = shoe
        multi.instance_count = SHOES_PER_SIDE
        instance.multimesh = multi
        # Includes the guides and small rounded pad thickness below the belt.
        instance.custom_aabb = AABB(Vector3(-1.13,-0.04,-1.65),Vector3(2.26,0.80,3.30))
        excavator.undercarriage.add_child(instance)
        track_multimeshes.append(multi)
    source.free()
    _update_track_transforms()

func _track_sample(distance: float, side: float) -> Transform3D:
    # Stadium path, tangent-continuous around the idler and final drive.
    var s := fposmod(distance, TRACK_LOOP)
    var y := 0.31
    var z := 0.0
    var angle := 0.0
    var straight := TRACK_HALF_STRAIGHT*2.0
    var arc := PI*TRACK_RADIUS
    if s < straight:
        z = -TRACK_HALF_STRAIGHT+s
        y -= TRACK_RADIUS
        angle = PI
    elif s < straight+arc:
        var t := (s-straight)/TRACK_RADIUS
        z = TRACK_HALF_STRAIGHT+sin(t)*TRACK_RADIUS
        y -= cos(t)*TRACK_RADIUS
        angle = PI-t
    elif s < straight*2.0+arc:
        z = TRACK_HALF_STRAIGHT-(s-straight-arc)
        y += TRACK_RADIUS
    else:
        var t := (s-straight*2.0-arc)/TRACK_RADIUS
        z = -TRACK_HALF_STRAIGHT-sin(t)*TRACK_RADIUS
        y += cos(t)*TRACK_RADIUS
        angle = -t
    return Transform3D(Basis(Vector3.RIGHT,angle),Vector3(side*0.86,y,z))

func _update_track_transforms() -> void:
    for index in range(track_multimeshes.size()):
        var side := -1.0 if index == 0 else 1.0
        for n in range(SHOES_PER_SIDE):
            track_multimeshes[index].set_instance_transform(n,
                _track_sample(float(n)*TRACK_LOOP/float(SHOES_PER_SIDE)+track_phase[index],side))

func _make_ram(a_body: Node3D, a_local: Vector3, b_body: Node3D,
        b_local: Vector3, barrel_length: float, radius: float) -> Dictionary:
    var ram := {"a":a_body,"p":a_local,"b":b_body,"q":b_local,
        "length":barrel_length,"barrel":_cyl(self,radius,barrel_length,Vector3.ZERO,ORANGE_SHADOW),
        "rod":_cyl(self,radius*0.52,0.1,Vector3.ZERO,STEEL),
        "gland":_cyl(self,radius*1.09,0.055,Vector3.ZERO,DARK),
        "eye_a":_cyl(self,radius*0.82,0.12,Vector3.ZERO,STEEL,true),
        "eye_b":_cyl(self,radius*0.71,0.11,Vector3.ZERO,STEEL,true)}
    rams.append(ram)
    return ram

func _draw_ram(ram: Dictionary, p: Vector3, q: Vector3) -> void:
    var direction := (q-p).normalized()
    var length: float = ram["length"]
    var start := p+direction*0.065
    var end := start+direction*length
    _position_rod(ram["barrel"],start,end)
    _position_rod(ram["gland"],end-direction*0.025,end+direction*0.025)
    _position_rod(ram["rod"],end-direction*0.015,q-direction*0.035)
    var extension := p.distance_to(q)-length-0.10
    minimum_ram_extension_m = minf(minimum_ram_extension_m,extension)
    var eye_axis: Vector3 = excavator.stick.global_basis.x.normalized()
    _position_rod(ram["eye_a"],p-eye_axis*0.065,p+eye_axis*0.065)
    _position_rod(ram["eye_b"],q-eye_axis*0.060,q+eye_axis*0.060)

func _update_bucket_linkage() -> Vector3:
    var stick: Node3D = excavator.stick
    var bucket: Node3D = excavator.bucket
    var a: Vector3 = stick.to_global(Vector3(0,0.23,-2.10))
    var d: Vector3 = bucket.to_global(Vector3(0,0.23,-0.23))
    var axis: Vector3 = stick.global_basis.x.normalized()
    var delta := d-a
    var distance := maxf(delta.length(),0.0001)
    var direction := delta/distance
    # Two-circle construction retains both link lengths over all working
    # bucket angles. No mesh stretching or detached pretend hinge.
    var length_a := 0.40
    var length_d := 0.34
    var along := (length_a*length_a-length_d*length_d+distance*distance)/(2.0*distance)
    var height := sqrt(maxf(0.0,length_a*length_a-along*along))
    var normal := axis.cross(direction).normalized()
    if normal.dot(stick.global_basis.y) < 0.0:
        normal = -normal
    var elbow := a+direction*along+normal*height
    var error := maxf(absf(elbow.distance_to(a)-length_a),absf(elbow.distance_to(d)-length_d))
    maximum_linkage_error_m = maxf(maximum_linkage_error_m,error)
    for side in [-1.0,1.0]:
        var offset: Vector3 = axis*float(side)*0.19
        var i := 0 if side < 0 else 2
        _position_rod(linkage_rods[i],a+offset,elbow+offset)
        _position_rod(linkage_rods[i+1],elbow+offset,d+offset)
    _position_rod(link_pin,elbow-axis*0.24,elbow+axis*0.24)
    return elbow

func update_bucket_fill(volume_m3: float, soil_type: String) -> void:
    if bucket_fill == null:
        return
    var level := clampi(int(round(volume_m3/0.24*24.0)),0,24)
    if level == fill_step and soil_type == fill_material:
        return
    fill_step = level
    fill_material = soil_type
    bucket_fill.visible = level > 0
    if level == 0:
        return
    var fill := float(level)/24.0
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    # Corrected detailed shell is behind +Y; its mouth faces -Y. Fill grows
    # from the curved back toward the mouth, not outside the reversed shell.
    var points: Array[Vector3] = []
    for row in range(10):
        var t := float(row)/9.0
        for col in range(14):
            var s := float(col)/13.0
            var y := lerpf(0.50-fill*0.30,0.23-fill*0.10,t)
            y -= sin(s*PI)*sin(t*PI)*0.035*fill
            y += sin(float(row*17+col*31))*0.008*sin(s*PI)*sin(t*PI)
            var half_width := 0.30*(0.84+0.16*sin(t*PI))
            points.append(Vector3((s*2.0-1.0)*half_width,y,lerpf(-0.10,-0.70,t)))
    for row in range(9):
        for col in range(13):
            var a := row*14+col
            for i in [a,a+14,a+1,a+1,a+14,a+15]: surface.add_vertex(points[i])
    surface.generate_normals()
    bucket_fill.mesh = surface.commit()
    var material := ShaderMaterial.new()
    material.shader = preload("res://landworks/assets/engineered/bucket_soil.gdshader")
    material.set_shader_parameter("soil_colour",Color("#8d5c36") if soil_type == "clay" else Color("#8c795c"))
    bucket_fill.material_override = material

func _process(delta: float) -> void:
    if excavator == null or track_multimeshes.is_empty():
        return
    cab.commands = excavator.cab_commands
    var under: RigidBody3D = excavator.undercarriage
    var forward: Vector3 = -under.global_basis.z.normalized()
    # Measured body point velocity, including the differential yaw component.
    # Track shoes therefore reverse and pivot with actual machine motion.
    for index in range(2):
        var side := -1.0 if index == 0 else 1.0
        var arm := under.global_basis*Vector3(side*0.86,0.23,0)
        var velocity := under.linear_velocity+under.angular_velocity.cross(arm)
        track_phase[index] = fposmod(track_phase[index]+velocity.dot(forward)*delta,TRACK_LOOP)
    _update_track_transforms()
    var elbow := _update_bucket_linkage()
    for ram in rams:
        var a: Node3D = ram["a"]
        var b: Node3D = ram["b"]
        var p: Vector3 = a.to_global(ram["p"])
        var q: Vector3 = b.to_global(ram["q"])
        if ram == bucket_ram:
            q = elbow
        _draw_ram(ram,p,q)
