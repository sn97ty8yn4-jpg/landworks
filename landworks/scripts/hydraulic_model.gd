# Three-axis hydraulic flow and power budget for a KX080-3-inspired prototype.
# This is NOT a line-by-line KYB pump/valve/cylinder simulation. The two
# 72 L/min pumps and 29.4 MPa pressure setting are service-manual reference
# ceilings; effective areas, linkages and available power remain assumptions.
extends RefCounted

const MAIN_PUMP_FLOW_LPM := 144.0
const MAIN_RELIEF_MPA := 29.4
const ENGINE_HYDRAULIC_KW := 45.0  # provisional net power to oil
const CIRCUIT_FLOW_LPM := {"boom": 78.0, "stick": 63.0, "bucket": 47.0}
# The speed each circuit's rated flow buys. These must match the joints' own
# ceilings: when they were lower, a single full-speed command over-requested
# flow and the allocator scaled it back, so one lever felt slow and three at
# once felt stuck. Raised with the wider rig limits they now serve.
const NOMINAL_RADS := {"boom": 0.80, "stick": 1.05, "bucket": 1.05}
# Effective area times perpendicular lever arm, in m3/rad equivalent;
# geometry-dependent real cylinder moment arms are not implemented yet.
const CYLINDER_MOMENT_M3 := {"boom": 0.0036, "stick": 0.0020, "bucket": 0.00095}

static func allocate(speeds: Dictionary, torques: Dictionary, load_torque: Dictionary,
        engine_factor: float = 1.0) -> Dictionary:
    var pressure_mpa := 2.0
    var requested_lpm := 0.0
    var torque_caps := {}
    for id in ["boom", "stick", "bucket"]:
        var peak_nm := float(torques.get(id, 0.0))
        var effective_moment := float(CYLINDER_MOMENT_M3[id])
        # The motor may never exceed either the test-machine torque cap or
        # the hydraulic relief pressure times assumed cylinder moment arm.
        var cap_nm: float = minf(peak_nm, MAIN_RELIEF_MPA * 1000000.0 * effective_moment)
        torque_caps[id] = maxf(0.0, cap_nm)
        if absf(float(speeds.get(id, 0.0))) > 0.005:
            var required_nm := minf(cap_nm, maxf(0.0, float(load_torque.get(id, 0.0))))
            pressure_mpa = maxf(pressure_mpa, required_nm / maxf(effective_moment, 0.00001) / 1000000.0)
        requested_lpm += absf(float(speeds.get(id, 0.0))) / float(NOMINAL_RADS[id]) * float(CIRCUIT_FLOW_LPM[id])
    pressure_mpa = minf(pressure_mpa, MAIN_RELIEF_MPA)
    var pump_lpm: float = MAIN_PUMP_FLOW_LPM * clampf(engine_factor, 0.30, 1.0)
    # P[kW] = p[MPa] Q[L/min] / 60. Higher load pressure makes the
    # horsepower control reduce pump delivery. No accumulator modeled.
    var flow_lpm: float = minf(pump_lpm, 60.0 * ENGINE_HYDRAULIC_KW * clampf(engine_factor, 0.30, 1.0) / pressure_mpa)
    var scale: float = minf(1.0, flow_lpm / maxf(requested_lpm, 0.001))
    var supplied := {}
    for id in ["boom", "stick", "bucket"]:
        supplied[id] = float(speeds.get(id, 0.0)) * scale
    var delivered_lpm: float = requested_lpm * scale
    return {"speeds": supplied, "torque_caps": torque_caps,
        "flow_scale": scale, "pressure_mpa": pressure_mpa,
        "flow_lpm": delivered_lpm,
        "requested_flow_lpm": requested_lpm,
        "hydraulic_power_kw": pressure_mpa * delivered_lpm / 60.0}
