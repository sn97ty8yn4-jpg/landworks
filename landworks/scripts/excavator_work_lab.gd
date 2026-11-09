# Free-chassis excavator working test: physically linked 8.17t machine, powered
# steel arm joints, a real 250/500/1000kg suspended load, slewing, and tracked
# travel-force proxy. All outcomes come from solver state, not visual animation.
extends "res://landworks/scripts/physical_excavator_lab.gd"

const LOADS := {"lift_250": 250.0, "lift_500": 500.0, "lift_1000": 1000.0,
    "lift_pivot_500": 500.0, "drag_1000": 1000.0,
    "push_1500": 1500.0, "roll_1000": 1000.0}
const GROUND_HANDLING_CASES := ["drag_1000", "push_1500", "roll_1000"]
# Track traction is a contact-force proxy, NOT individual rubber belt dynamics.
# 8170 kg includes chassis, carriage, boom, arm and bucket, excluding payload.
const APPROX_DRY_GRASS_TRACK_MU := 0.56
const TRACK_MACHINE_MASS_KG := 8170.0
const TRACK_SPEED_FEEDBACK_N_PER_MPS := 24000.0
const TRACK_LATERAL_SKID_N_PER_MPS := 1900.0
const BOOM_TORQUE_LIMIT_NM := 75000.0  # engineering starting assumption, NOT OEM value
const STICK_TORQUE_LIMIT_NM := 45000.0
const BUCKET_TORQUE_LIMIT_NM := 20000.0
const SLEW_TORQUE_LIMIT_NM := 25000.0
const TEST_END_S := 32.0

var case_name := "lift_500"
var output_dir := ""
var batch := false
var upper: RigidBody3D
var slew_joint: HingeJoint3D
var data_file: FileAccess
var sample_elapsed := 0.0
var peak_tilt_deg := 0.0
var peak_load_lift_m := 0.0
var peak_load_drop_m := 0.0
var max_travel_m := 0.0
var start_base_z := 0.0
var object_start_position := Vector3.ZERO
var object_position_captured := false
var object_displacement_m := 0.0
var object_roll_deg := 0.0
var hold_height := 0.0
var hold_drift_m := 0.0
var settled_height := 0.0
var max_slew_deg := 0.0
var ground_contact_count := 0
var tip_detected := false
var completed := false
var sample_at_10 := false
var initial_payload_mass := 500.0
var max_base_yaw_deg := 0.0
var last_track_left_force_n := 0.0
var last_track_right_force_n := 0.0
var start_base_xz := Vector2.ZERO
var max_base_planar_displacement_m := 0.0

func _ready() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--scenario="):
            case_name = arg.trim_prefix("--scenario=")
        elif arg.begins_with("--output-dir="):
            output_dir = arg.trim_prefix("--output-dir=")
        elif arg == "--batch":
            batch = true
    if not LOADS.has(case_name):
        push_error("Unknown excavator scenario: " + case_name)
        get_tree().quit(3)
        return
    initial_payload_mass = float(LOADS[case_name])
    if output_dir != "":
        DirAccess.make_dir_recursive_absolute(output_dir)
    super._ready()
    start_base_z = undercarriage.global_position.z
    start_base_xz = Vector2(undercarriage.global_position.x, undercarriage.global_position.z)
    settled_height = test_mass.global_position.y
    data_file = FileAccess.open(_out("excavator_" + case_name + "_samples.csv"), FileAccess.WRITE)
    if data_file == null:
        push_error("Cannot create excavator work-test CSV")
        get_tree().quit(4)
        return
    data_file.store_csv_line(PackedStringArray(["time_s", "case", "phase", "payload_kg",
        "payload_y_m", "load_lift_m", "base_z_m", "base_speed_kmh", "chassis_tilt_deg",
        "slew_deg", "boom_deg", "stick_deg", "bucket_deg", "ground_contacts", "base_yaw_deg", "left_track_force_n",
        "right_track_force_n", "base_planar_displacement_m",
        "object_displacement_m", "object_roll_deg"]))

func _out(filename: String) -> String:
    return "user://" + filename if output_dir == "" else output_dir.path_join(filename)

func _motor_impulse(max_torque_nm: float) -> float:
    return max_torque_nm / float(Engine.physics_ticks_per_second)

func _make_ground_tracks() -> void:
    undercarriage = RigidBody3D.new()
    undercarriage.name = "KX080_Lower_2200kg_Unfrozen"
    undercarriage.mass = 2200.0
    undercarriage.can_sleep = false
    undercarriage.continuous_cd = true
    undercarriage.linear_damp = 0.05
    undercarriage.angular_damp = 0.20
    undercarriage.collision_layer = 2
    undercarriage.collision_mask = 1
    add_child(undercarriage)
    var mat := PhysicsMaterial.new()
    # These are passive box-track proxies, not powered linked tracks. A high
    # static friction coefficient arrests the rigid body before contact drive
    # forces can act; drive traction is separately force-limited per side.
    mat.friction = 0.015
    mat.rough = false
    undercarriage.physics_material_override = mat
    # Wide, real rigid-body track contact area rather than a frozen chassis.
    for x in [-0.86, 0.86]:
        var shape := BoxShape3D.new()
        shape.size = Vector3(0.46, 0.54, 3.10)
        var c := CollisionShape3D.new()
        c.shape = shape
        c.position = Vector3(x, 0.27, 0.0)
        undercarriage.add_child(c)
        M.block(undercarriage, shape.size, c.position, Color("#222a2c"))
    M.block(undercarriage, Vector3(1.50, 0.28, 2.50), Vector3(0, 0.67, 0.03), Color("#43484b"))

func _build_machine() -> void:
    _make_ground_tracks()
    upper = RigidBody3D.new()
    upper.name = "KX080_UpperCounterweight_4710kg"
    upper.mass = 4710.0
    upper.can_sleep = false
    upper.continuous_cd = true
    upper.linear_damp = 0.07
    upper.angular_damp = 0.12
    upper.collision_layer = 2
    upper.collision_mask = 1
    add_child(upper)
    var c := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(1.94, 0.86, 2.45)
    c.shape = shape
    c.position = Vector3(0, 1.44, 0.20)
    upper.add_child(c)
    M.block(upper, shape.size, c.position, Color("#e77c17"))
    M.block(upper, Vector3(0.90, 1.20, 1.0), Vector3(-0.43, 2.22, -0.28), Color("#333d40"))
    M.block(upper, Vector3(1.69, 0.38, 0.73), Vector3(0, 1.52, 1.11), Color("#bf6816"))
    _make_hinge("slew", undercarriage, upper, Vector3(0, 0.97, 0),
        Vector3.UP, -PI, PI, _motor_impulse(SLEW_TORQUE_LIMIT_NM))
    slew_joint = hinges["slew"]["joint"]
    slew_joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, false)
    var boom_pin := Vector3(0.48, 2.12, -0.66)
    boom = _make_box("Boom_650kg", 650.0, boom_pin, 0.24,
        BOOM_LENGTH, 0.46, 0.46, Color("#f08820"))
    var stick_pin: Vector3 = boom.to_global(Vector3(0, 0, -BOOM_LENGTH))
    stick = _make_box("Stick_400kg", 400.0, stick_pin, -0.48,
        STICK_LENGTH, 0.34, 0.34, Color("#e97a17"))
    var bucket_pin: Vector3 = stick.to_global(Vector3(0, 0, -STICK_LENGTH))
    bucket = _make_box("Bucket_210kg", 210.0, bucket_pin, -0.72,
        BUCKET_LENGTH, 0.44, 0.76, Color("#42494a"))
    _make_hinge("boom", upper, boom, boom_pin, Vector3.RIGHT,
        -0.70, 1.15, _motor_impulse(BOOM_TORQUE_LIMIT_NM))
    _make_hinge("stick", boom, stick, stick_pin, Vector3.RIGHT,
        -1.5, 0.15, _motor_impulse(STICK_TORQUE_LIMIT_NM))
    _make_hinge("bucket", stick, bucket, bucket_pin, Vector3.RIGHT,
        -1.0, 0.75, _motor_impulse(BUCKET_TORQUE_LIMIT_NM))
    var hook: Vector3 = bucket.to_global(Vector3(0, 0, -BUCKET_LENGTH))
    var is_free_object := case_name == "push_1500" or case_name == "roll_1000"
    if is_free_object:
        # Real collision toe attached to the rigid bucket; contacts originate
        # in Jolt and the load never receives scripted movement.
        bucket.collision_mask = 3
        var toe := CollisionShape3D.new()
        var toe_shape := BoxShape3D.new()
        toe_shape.size = Vector3(1.20, 0.94, 0.40)
        toe.shape = toe_shape
        toe.position = bucket.to_local(Vector3(0.48, 0.66, -6.18))
        bucket.add_child(toe)
        M.block(bucket, toe_shape.size, toe.position, Color("#444a4d"))
    test_mass = RigidBody3D.new()
    test_mass.name = "Suspended_Test_Load"
    test_mass.mass = initial_payload_mass
    test_mass.can_sleep = false
    test_mass.continuous_cd = true
    test_mass.collision_layer = 2
    test_mass.collision_mask = 1
    add_child(test_mass)
    test_mass.global_position = hook + Vector3.DOWN * 0.52
    var load_col := CollisionShape3D.new()
    test_mass.add_child(load_col)
    if case_name == "roll_1000":
        # Free 1000 kg cylindrical drum oriented across the machine.
        var drum := CylinderShape3D.new()
        drum.radius = 0.62
        drum.height = 1.25
        load_col.shape = drum
        load_col.rotation.z = PI * 0.5
        test_mass.global_position = Vector3(0.48, 0.63, -7.10)
        var drum_mesh := CylinderMesh.new()
        drum_mesh.top_radius = 0.62
        drum_mesh.bottom_radius = 0.62
        drum_mesh.height = 1.25
        var visible_drum := MeshInstance3D.new()
        visible_drum.mesh = drum_mesh
        visible_drum.rotation.z = PI * 0.5
        var drum_mat := StandardMaterial3D.new()
        drum_mat.albedo_color = Color("#626f74")
        visible_drum.material_override = drum_mat
        test_mass.add_child(visible_drum)
    elif case_name == "push_1500":
        var crate := BoxShape3D.new()
        crate.size = Vector3(1.18, 1.26, 1.0)
        load_col.shape = crate
        test_mass.global_position = Vector3(0.48, 0.64, -7.10)
        M.block(test_mass, crate.size, Vector3.ZERO, Color("#a58e71"))
    else:
        var load_shape := BoxShape3D.new()
        load_shape.size = Vector3(0.78, 0.56, 0.78)
        load_col.shape = load_shape
        M.block(test_mass, load_shape.size, Vector3.ZERO, Color("#b0a892"))
    if case_name in GROUND_HANDLING_CASES:
        var surface := PhysicsMaterial.new()
        surface.friction = 0.75 if case_name == "roll_1000" else 0.43
        surface.rough = false
        test_mass.physics_material_override = surface
        test_mass.linear_damp = 0.03
        test_mass.angular_damp = 0.08 if case_name == "roll_1000" else 0.18
    if is_free_object:
        # Free object collides with the bucket toe and ground, no hidden motor.
        test_mass.collision_mask = 3
    else:
        var load_pin := PinJoint3D.new()
        load_pin.name = "PhysicallyAttachedLoad"
        add_child(load_pin)
        load_pin.global_position = hook
        load_pin.node_a = load_pin.get_path_to(bucket)
        load_pin.node_b = load_pin.get_path_to(test_mass)
        load_pin.exclude_nodes_from_collision = true

func _relative_slew_rad() -> float:
    var rel: Basis = undercarriage.global_transform.basis.inverse() * upper.global_transform.basis
    return atan2(rel.z.x, rel.z.z)

func _control_slew(target_rad: float) -> void:
    var error := wrapf(target_rad - _relative_slew_rad(), -PI, PI)
    var rel_ang_vel: float = (upper.angular_velocity - undercarriage.angular_velocity).dot(Vector3.UP)
    # The Jolt hinge-motor sign is opposite to the measured yaw sign here.
    # Without this inversion the carriage spins uncommanded toward 180 degrees.
    slew_joint.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,
        -clampf(2.0 * error - 0.65 * rel_ang_vel, -0.45, 0.45))

func _drive_tracks(target_left: float, target_right: float) -> void:
    # Track contact-force approximation: two longitudinal contact patches per
    # side, with independent tangential (drive) and lateral (skid) response.
    # The collision shapes retain obstacle contact but must NOT carry strong
    # isotropic friction: that would lock neutral turns and double-count grip.
    var basis: Basis = undercarriage.global_transform.basis
    var forward: Vector3 = -basis.z.normalized()
    var right: Vector3 = basis.x.normalized()
    ground_contact_count = 0
    last_track_left_force_n = 0.0
    last_track_right_force_n = 0.0
    var track_speed_commands := [target_left, target_right]
    for index in range(2):
        var side := -1.0 if index == 0 else 1.0
        var requested: float = track_speed_commands[index]
        var contact_positions: Array[Vector3] = []
        for z in [-1.08, 1.08]:
            var local := Vector3(0.86 * side, 0.23, z)
            var ray_origin: Vector3 = undercarriage.to_global(local)
            var query := PhysicsRayQueryParameters3D.create(
                ray_origin, ray_origin + Vector3.DOWN * 0.60)
            query.exclude = [undercarriage.get_rid()]
            var hit := get_world_3d().direct_space_state.intersect_ray(query)
            if not hit.is_empty():
                contact_positions.append(local)
        var contacts := contact_positions.size()
        ground_contact_count += contacts
        if contacts == 0:
            continue
        # Normal-load estimate is split over the side's two test contacts.
        # No suspension compliance yet: limits are intentionally approximate.
        var side_normal_n := (TRACK_MACHINE_MASS_KG + initial_payload_mass) * 9.81 * 0.5
        var per_patch_mu_n := APPROX_DRY_GRASS_TRACK_MU * side_normal_n / 2.0
        for local in contact_positions:
            var arm: Vector3 = basis * local
            var point_velocity: Vector3 = undercarriage.linear_velocity + undercarriage.angular_velocity.cross(arm)
            var longitudinal_mps := point_velocity.dot(forward)
            var lateral_mps := point_velocity.dot(right)
            var drive_n := clampf(
                (requested - longitudinal_mps) * TRACK_SPEED_FEEDBACK_N_PER_MPS / float(contacts),
                -per_patch_mu_n, per_patch_mu_n)
            # Sideways sliding of a rubber track is resisted, but not welded
            # to the ground. The front/rear patch arms create realistic
            # turning scrub and help damp yaw oscillations.
            var lateral_n := -lateral_mps * TRACK_LATERAL_SKID_N_PER_MPS
            var combined := Vector2(drive_n, lateral_n)
            if combined.length() > per_patch_mu_n:
                combined *= per_patch_mu_n / combined.length()
            undercarriage.apply_force(forward * combined.x + right * combined.y, arm)
            if index == 0:
                last_track_left_force_n += combined.x
            else:
                last_track_right_force_n += combined.x

func _test_phase() -> String:
    if elapsed < 2.0:
        return "SETTLE"
    if elapsed < 10.0:
        return "RAISE"
    if elapsed < 13.0:
        return "HOLD"
    if elapsed < 19.0:
        return "SLEW"
    if elapsed < 26.0:
        return "TRAVEL_WITH_LOAD"
    return "STOP_AND_HOLD"

func _physics_process(delta: float) -> void:
    if completed or data_file == null:
        return
    elapsed += delta
    var phase := _test_phase()
    # Handling keeps the bucket at its low initial pose; bodies can still
    # push, drag or roll along the ground without being lifted clear.
    var handling := case_name in GROUND_HANDLING_CASES
    var lift_frac := 0.0 if handling else smoothstep(2.0, 10.0, elapsed)
    target_angles["boom"] = 0.24 + 0.48 * lift_frac
    target_angles["stick"] = -0.72 + 0.10 * lift_frac
    target_angles["bucket"] = -0.24 - 0.12 * lift_frac
    for id in ["boom", "stick", "bucket"]:
        _drive_joint(id, delta)
    # Explicit ground handling does NOT depend on lifting capability.
    # The separate failed-lift test remains stationary by test design.
    var carry_authorised := peak_load_lift_m > 0.50
    var requested_slew := 0.0 if handling else 1.20 * smoothstep(13.0, 19.0, elapsed)
    _control_slew(requested_slew if carry_authorised else 0.0)
    if elapsed >= 19.0 and elapsed < 26.0 and (handling or carry_authorised):
        if case_name == "lift_pivot_500":
            _drive_tracks(-0.55, 0.55)
        else:
            _drive_tracks(0.66, 0.66)
    else:
        _drive_tracks(0.0, 0.0)
    var up: Vector3 = undercarriage.global_transform.basis.y.normalized()
    var tip_angle := rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
    peak_tilt_deg = maxf(peak_tilt_deg, tip_angle)
    tip_detected = tip_detected or tip_angle > 20.0
    if elapsed >= 18.9 and not object_position_captured:
        object_start_position = test_mass.global_position
        object_position_captured = true
    if object_position_captured:
        var xy_now := Vector2(test_mass.global_position.x, test_mass.global_position.z)
        var xy_start := Vector2(object_start_position.x, object_start_position.z)
        object_displacement_m = maxf(object_displacement_m, xy_now.distance_to(xy_start))
    if case_name == "roll_1000" and elapsed >= 19.0 and elapsed < 26.0:
        object_roll_deg += rad_to_deg(absf(test_mass.angular_velocity.dot(Vector3.RIGHT))) * delta
    var height_change := test_mass.global_position.y - settled_height
    peak_load_lift_m = maxf(peak_load_lift_m, height_change)
    peak_load_drop_m = minf(peak_load_drop_m, height_change)
    max_travel_m = maxf(max_travel_m, absf(undercarriage.global_position.z - start_base_z))
    var planar: Vector2 = Vector2(undercarriage.global_position.x, undercarriage.global_position.z)
    max_base_planar_displacement_m = maxf(max_base_planar_displacement_m, planar.distance_to(start_base_xz))
    var slew_deg := rad_to_deg(_relative_slew_rad())
    max_slew_deg = maxf(max_slew_deg, absf(slew_deg))
    var under_basis := undercarriage.global_transform.basis
    var base_yaw_deg := rad_to_deg(atan2(under_basis.z.x, under_basis.z.z))
    max_base_yaw_deg = maxf(max_base_yaw_deg, absf(base_yaw_deg))
    if elapsed >= 11.0 and not sample_at_10:
        hold_height = test_mass.global_position.y
        sample_at_10 = true
    if elapsed >= 11.0 and elapsed < 13.0:
        hold_drift_m = maxf(hold_drift_m, absf(test_mass.global_position.y - hold_height))
    sample_elapsed += delta
    if sample_elapsed >= 0.10:
        sample_elapsed -= 0.10
        data_file.store_csv_line(PackedStringArray([
            "%.3f" % elapsed, case_name, phase, "%.0f" % initial_payload_mass,
            "%.3f" % test_mass.global_position.y, "%.3f" % height_change,
            "%.3f" % undercarriage.global_position.z,
            "%.3f" % (Vector2(undercarriage.linear_velocity.x, undercarriage.linear_velocity.z).length() * 3.6),
            "%.3f" % tip_angle, "%.3f" % slew_deg,
            "%.3f" % rad_to_deg(_joint_angle("boom")),
            "%.3f" % rad_to_deg(_joint_angle("stick")),
            "%.3f" % rad_to_deg(_joint_angle("bucket")), str(ground_contact_count),
            "%.3f" % base_yaw_deg, "%.1f" % last_track_left_force_n,
            "%.1f" % last_track_right_force_n, "%.3f" % max_base_planar_displacement_m,
            "%.3f" % object_displacement_m, "%.3f" % object_roll_deg
        ]))
    labels.text = "LANDWORKS | FREE-CHASSIS EXCAVATOR FIELD TEST\n"
    labels.text += "%s | %s | %.0f kg load | lift %+.2f m | slew %.1f°\n" % [case_name, phase, initial_payload_mass, height_change, slew_deg]
    labels.text += "Base tilt %.1f° | travel %.2f m | track contacts %d/4\n" % [tip_angle, max_travel_m, ground_contact_count]
    if not carry_authorised and not handling and elapsed > 10.0:
        labels.text += "FAILED LIFT TEST — NO AUTOMATIC TRAVEL\n"
    if handling:
        labels.text += "GROUND HANDLING: object movement %.2f m | drum spin %.1f deg\n" % [
            object_displacement_m, object_roll_deg]
    labels.text += "Boom motor torque cap: %.0f kNm (assumed); real hydraulic circuits NOT simulated." % (BOOM_TORQUE_LIMIT_NM / 1000.0)
    if elapsed >= TEST_END_S:
        _finish()

func _finish() -> void:
    completed = true
    data_file.close()
    var path := _out("excavator_" + case_name + "_summary.csv")
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f != null:
        f.store_csv_line(PackedStringArray(["scenario", "payload_kg", "peak_lift_m", "peak_drop_m", "hold_drift_m",
            "base_travel_m", "max_slew_deg", "max_chassis_tilt_deg", "tipping_detected",
            "max_base_yaw_deg", "base_planar_displacement_m",
            "object_displacement_m", "object_roll_deg"]))
        f.store_csv_line(PackedStringArray([case_name, "%.0f" % initial_payload_mass,
            "%.3f" % peak_load_lift_m, "%.3f" % peak_load_drop_m, "%.3f" % hold_drift_m,
            "%.3f" % max_travel_m, "%.3f" % max_slew_deg, "%.3f" % peak_tilt_deg,
            str(int(tip_detected)), "%.3f" % max_base_yaw_deg,
            "%.3f" % max_base_planar_displacement_m,
            "%.3f" % object_displacement_m, "%.3f" % object_roll_deg]))
        f.close()
    print("LANDWORKS_EXCAVATOR_TEST_COMPLETE ", case_name, " ", path)
    if batch:
        get_tree().quit(0)
