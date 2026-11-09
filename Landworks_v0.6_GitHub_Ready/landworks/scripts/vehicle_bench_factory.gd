# Assembles apples-to-apples tractor test chassis using the downloaded MIT addons.
# Model mass/axles/tyre sizes are common; handling *algorithms* intentionally differ.
# Addons are optional and NEVER preloaded by the base project.
extends RefCounted

const M = preload("res://landworks/scripts/mesh_factory.gd")
const GEVP_VEHICLE := "res://addons/gevp/scripts/vehicle.gd"
const GEVP_WHEEL := "res://addons/gevp/scripts/wheel.gd"
const KV_VEHICLE := "res://addons/kv-vehicle/scene/instantiable/kv-vehicle.tscn"
const KV_WHEEL := "res://addons/kv-vehicle/scene/instantiable/kv-wheel.tscn"

const MASS := 573.0
const FRONT_RADIUS := 0.26035
const REAR_RADIUS := 0.36830
const FRONT_WIDTH := 0.2032
const REAR_WIDTH := 0.3048
const AXLE_POSITIONS := [
    Vector3(-0.35, -0.14, -0.69), Vector3(0.35, -0.14, -0.69),
    Vector3(-0.37, -0.24, 0.70), Vector3(0.37, -0.24, 0.70)
]

static func ready_for(variant: String) -> bool:
    if variant == "GEVP":
        return ResourceLoader.exists(GEVP_VEHICLE) and ResourceLoader.exists(GEVP_WHEEL)
    if variant == "KV":
        return ResourceLoader.exists(KV_VEHICLE) and ResourceLoader.exists(KV_WHEEL)
    return false

static func add_geometry(body: RigidBody3D) -> void:
    var cs := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(0.86, 0.46, 2.05)
    cs.position = Vector3(0, 0.07, 0)
    cs.shape = box
    body.add_child(cs)
    var art := Node3D.new()
    body.add_child(art)
    M.block(art, Vector3(0.77, 0.32, 1.26), Vector3(0, 0.30, -0.32), Color("#df751c"))
    M.block(art, Vector3(0.75, 0.14, 0.68), Vector3(0, 0.35, 0.46), Color("#3c3d3c"))
    M.block(art, Vector3(0.59, 0.18, 0.37), Vector3(0, 0.68, 0.42), Color("#22292d"))
    M.block(art, Vector3(0.06, 1.24, 0.06), Vector3(-0.42, 0.91, 0.68), Color("#25292b"))
    M.block(art, Vector3(0.06, 1.24, 0.06), Vector3(0.42, 0.91, 0.68), Color("#25292b"))
    M.block(art, Vector3(0.90, 0.06, 0.06), Vector3(0, 1.53, 0.68), Color("#25292b"))

static func _curve(y0: float = 0.4, y1: float = 1.0) -> Curve:
    var c := Curve.new()
    c.add_point(Vector2(0.0, y0))
    c.add_point(Vector2(0.6, y1))
    c.add_point(Vector2(1.0, 0.8 * y1))
    return c

static func create_gevp() -> RigidBody3D:
    if not ready_for("GEVP"):
        return null
    var body := RigidBody3D.new()
    body.set_script(load(GEVP_VEHICLE))
    body.name = "GEVP_RealEngine"
    body.set("vehicle_mass", MASS)
    body.set("max_torque", 52.0)
    body.set("max_rpm", 3200.0)
    body.set("idle_rpm", 850.0)
    body.set("clutch_out_rpm", 1250.0)
    body.set("front_tire_radius", FRONT_RADIUS)
    body.set("rear_tire_radius", REAR_RADIUS)
    body.set("front_tire_width", FRONT_WIDTH * 1000.0) # GEVP uses mm
    body.set("rear_tire_width", REAR_WIDTH * 1000.0)
    body.set("front_torque_split", 0.35)
    body.set("max_steering_angle", 0.50)
    var gevp_gears: Array[float] = [3.9, 2.4, 1.4]
    body.set("gear_ratios", gevp_gears)
    body.set("final_drive", 7.0)
    body.set("automatic_transmission", true)
    body.set("torque_curve", _curve(0.8, 1.0))
    body.set("enable_stability", false)
    body.set("traction_control_max_slip", -1.0)
    body.set("front_spring_length", 0.24)
    body.set("rear_spring_length", 0.24)
    body.set("front_arb_ratio", 0.0)
    body.set("rear_arb_ratio", 0.0)
    add_geometry(body)
    var names := ["front_left_wheel", "front_right_wheel", "rear_left_wheel", "rear_right_wheel"]
    for i in range(4):
        var wheel := RayCast3D.new()
        wheel.set_script(load(GEVP_WHEEL))
        wheel.name = names[i]
        wheel.position = AXLE_POSITIONS[i]
        var tyre := Node3D.new()
        tyre.name = "WheelArt"
        wheel.add_child(tyre)
        M.tyre(tyre, FRONT_RADIUS if i < 2 else REAR_RADIUS,
            FRONT_WIDTH if i < 2 else REAR_WIDTH, Vector3.ZERO, true)
        wheel.set("wheel_node", tyre)
        body.add_child(wheel)
        body.set(names[i], wheel)
    return body

static func create_kv() -> RigidBody3D:
    if not ready_for("KV"):
        return null
    var body: RigidBody3D = load(KV_VEHICLE).instantiate()
    body.name = "KV_RealEngine"
    body.mass = MASS
    body.set("substeps", 4)
    add_geometry(body)
    var response = load("res://addons/kv-vehicle/TireResponseKV.gd").new()
    response.set("materialName", "grass")
    response.set("coeficientOfFriction", 0.86)
    response.set("gripXCurve", _curve(1.0, 1.0))
    response.set("gripZCurve", _curve(0.7, 1.0))
    response.set("feedbackCurve", _curve(0.0, 0.3))
    response.set("relativeZSpeedBegin", 0.0)
    response.set("relativeZSpeedEnd", 5.0)
    response.set("useSlipRatio", false)
    var wheels: Array = []
    for i in range(4):
        var wheel: Node3D = load(KV_WHEEL).instantiate()
        wheel.name = "kv_wheel_%d" % i
        wheel.position = AXLE_POSITIONS[i]
        wheel.set("radius", FRONT_RADIUS if i < 2 else REAR_RADIUS)
        wheel.set("width", FRONT_WIDTH if i < 2 else REAR_WIDTH)
        wheel.set("momentOfInertia", 0.8 if i < 2 else 2.0)
        # Correct nullable defaults shipped in this older KV wheel scene.
        wheel.set("overCompressionBegin", 0.0)
        wheel.set("dampOverCompressionRebound", false)
        wheel.set("steer", i < 2)
        wheel.set("maxSteerAngle", 0.5)
        wheel.set("stiffness", 5.0)
        wheel.set("defaultTireResponse", response)
        wheel.get("tireResponses").append(response)
        wheel.set("suspensionGeometry", load("res://addons/kv-vehicle/SuspensionGeometryStraight.tres"))
        var steering_node: Node3D = wheel.get_node("wheelSteerPivot")
        steering_node.set("restExtension", -0.16)
        steering_node.set("maxExtension", -0.34)
        M.tyre(wheel.get_node("wheelSteerPivot/wheelRollPivot"),
            FRONT_RADIUS if i < 2 else REAR_RADIUS,
            FRONT_WIDTH if i < 2 else REAR_WIDTH, Vector3.ZERO, true)
        body.add_child(wheel)
        wheels.append(wheel)
    var engine: Node = load("res://addons/kv-vehicle/scene/instantiable/kv-engine.tscn").instantiate()
    engine.set("torqueCurve", _curve(0.8, 1.0))
    engine.set("peakTorque", 52.0)
    engine.set("maxRevsPerMinute", 3200.0)
    engine.set("idleRevsPerMinute", 850.0)
    engine.set("internalFrictionTorque", 3.0)
    engine.set("breakTorque", 3.0)
    engine.set("momentOfInertia", 0.7)
    body.add_child(engine)
    var drivetrain: Node = load("res://addons/kv-vehicle/scene/instantiable/kv-drivetrain.tscn").instantiate()
    drivetrain.set("engine", engine)
    var kv_gears: Array[float] = [-0.18, 0.0, 0.18, 0.26]
    drivetrain.set("gearRatios", kv_gears)
    drivetrain.set("finalRatio", 0.18)
    drivetrain.set("clutchMaxTorque", 180.0)
    for w in wheels:
        drivetrain.get("poweredWheels").append(w)
    body.add_child(drivetrain)
    var brakes: Node = load("res://addons/kv-vehicle/scene/instantiable/kv-breaks.tscn").instantiate()
    brakes.set("strength", 650.0)
    for w in wheels:
        brakes.get("wheels").append(w)
    body.add_child(brakes)
    return body
