# Run with: godot --headless --path . --script res://landworks/scripts/hydraulic_smoke.gd
extends SceneTree
const H = preload("res://landworks/scripts/hydraulic_model.gd")
const S = preload("res://landworks/scripts/ground_response.gd")

func _initialize() -> void:
    var peak := {"boom": 75000.0, "stick": 45000.0, "bucket": 20000.0}
    # "Busy" means every service asking for its own rated speed at once. Take
    # those from the model rather than copying numbers, which is how this test
    # came to request less than full flow once the ratings were raised.
    var busy := H.allocate({"boom": float(H.NOMINAL_RADS["boom"]),
            "stick": float(H.NOMINAL_RADS["stick"]),
            "bucket": float(H.NOMINAL_RADS["bucket"])},
        peak, {"boom": 75000.0, "stick": 45000.0, "bucket": 20000.0})
    var alone := H.allocate({"boom": 0.10, "stick": 0.0, "bucket": 0.0},
        peak, {"boom": 18000.0, "stick": 0.0, "bucket": 0.0})
    var ok := true
    ok = ok and float(busy["flow_scale"]) < 0.9
    ok = ok and absf(float(alone["flow_scale"]) - 1.0) < 0.001
    ok = ok and float(busy["pressure_mpa"]) <= H.MAIN_RELIEF_MPA
    ok = ok and float(busy["hydraulic_power_kw"]) <= H.ENGINE_HYDRAULIC_KW + 0.01
    ok = ok and float(busy["flow_lpm"]) <= H.MAIN_PUMP_FLOW_LPM + 0.01
    ok = ok and float(S.profile("soft_clay")["track_mu"]) < float(S.profile("hardpack")["track_mu"])
    print("HYDRAULIC_SMOKE ", "PASS" if ok else "FAIL", " busy_flow_scale=", busy["flow_scale"],
        " pressure_MPa=", busy["pressure_mpa"], " flow_LPM=", busy["flow_lpm"])
    quit(0 if ok else 1)
