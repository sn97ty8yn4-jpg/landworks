# Replaceable material-response presets for live rigid-body contacts.
# The collision solver still handles object impacts/rotation/ground friction.
# Additional sinkage/rolling drag represents sub-grid terrain losses, not
# a deforming mesh or an empirical calibrated Bekker terramechanics model.
extends RefCounted

const PROFILES := {
    "hardpack": {"object_mu": 0.43, "track_mu": 0.56,
        "rolling_coefficient": 0.014, "sinkage_drag_n": 0.0,
        "name": "Compacted farm track"},
    "soft_clay": {"object_mu": 0.68, "track_mu": 0.38,
        "rolling_coefficient": 0.13, "sinkage_drag_n": 1400.0,
        "name": "Soft silty clay"},
    "wet_clay": {"object_mu": 0.35, "track_mu": 0.24,
        "rolling_coefficient": 0.22, "sinkage_drag_n": 2350.0,
        "name": "Wet saturated clay"}
}

static func profile(id: String) -> Dictionary:
    return PROFILES.get(id, PROFILES["hardpack"]).duplicate(true)

static func apply_ground_resistance(body: RigidBody3D, material: Dictionary) -> float:
    # Applied ONLY to bodies near the existing level y=0 test surface.
    # No velocity overwrite or position teleporting: dynamics remain in Jolt.
    if body.global_position.y > 1.4:
        return 0.0
    var v := Vector3(body.linear_velocity.x, 0.0, body.linear_velocity.z)
    var speed := v.length()
    if speed < 0.015:
        return 0.0
    var normal_n := body.mass * 9.81
    var rolling_n := normal_n * float(material["rolling_coefficient"])
    var sinkage_n := float(material["sinkage_drag_n"])
    # Smooth onset avoids a discontinuous reverse kick as the object stops.
    var resistance_n := (rolling_n + sinkage_n) * clampf(speed / 0.24, 0.0, 1.0)
    body.apply_central_force(-v / speed * resistance_n)
    return resistance_n
