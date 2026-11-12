# Runtime homogeneous mixture. Profile values are unverified game tunings.
# Dry constituents and water are authoritative; density is derived.
class_name MaterialBatch
extends RefCounted

static var profiles: Dictionary = {}
var dry: Dictionary = {}
var water := 0.0
var free_water := 0.0
var void_ratio := 0.0
var damage := 0.0

static func setup() -> void:
    if profiles.is_empty():
        profiles = JSON.parse_string(FileAccess.get_file_as_string(
            "res://landworks/data/soil/material_profiles_v1_1.json"))["materials"]

static func bank(kind: String, volume: float) -> MaterialBatch:
    setup()
    var batch := MaterialBatch.new()
    var key := "moist_silty_clay" if kind == "clay" else "loose_gravel"
    var p: Dictionary = profiles[key]
    batch.void_ratio = p["void_ratio_bank"]
    batch.dry[key] = maxf(volume,0.0)/(1.0+batch.void_ratio)*float(p["grain_density"])
    batch.water = float(batch.dry[key])*float(p["gravimetric_water"])
    batch._partition_water()
    return batch

func solids() -> float:
    var result := 0.0
    for key in dry: result += float(dry[key])/float(profiles[key]["grain_density"])
    return result

func volume() -> float:
    return solids()*(1.0+void_ratio)

func dry_mass() -> float:
    var result := 0.0
    for value in dry.values(): result += float(value)
    return result

func mass() -> float:
    return dry_mass()+water+free_water

func weighted(key: String) -> float:
    var result := 0.0
    for kind in dry:
        result += float(dry[kind])/float(profiles[kind]["grain_density"])*float(profiles[kind][key])
    return result/maxf(solids(),1e-12)

func _partition_water() -> void:
    var excess := maxf(0.0,water-solids()*void_ratio*1000.0)
    water -= excess
    free_water += excess

func loosen() -> void:
    void_ratio = maxf(void_ratio,weighted("void_ratio_loose"))
    damage = maxf(damage,0.25)
    _partition_water()

func split(amount: float) -> MaterialBatch:
    var result := MaterialBatch.new()
    var fraction := clampf(amount/maxf(volume(),1e-12),0.0,1.0)
    for key in dry:
        result.dry[key] = float(dry[key])*fraction
        dry[key] = float(dry[key])-float(result.dry[key])
    result.water = water*fraction
    result.free_water = free_water*fraction
    water -= result.water
    free_water -= result.free_water
    result.void_ratio = void_ratio
    result.damage = damage
    return result

func absorb(other: MaterialBatch) -> void:
    # Consume the donor so a repeated merge cannot duplicate inventory.
    assert(other != self)
    var own_solid := solids()
    var other_solid := other.solids()
    var combined_volume := volume()+other.volume()
    damage = (damage*own_solid+other.damage*other_solid)/maxf(own_solid+other_solid,1e-12)
    for key in other.dry: dry[key] = float(dry.get(key,0.0))+float(other.dry[key])
    water += other.water
    free_water += other.free_water
    void_ratio = maxf(0.0,combined_volume/maxf(own_solid+other_solid,1e-12)-1.0)
    other.dry.clear()
    other.water = 0.0
    other.free_water = 0.0
    _partition_water()

func kind() -> String:
    return "clay" if float(dry.get("moist_silty_clay",0.0)) > float(dry.get("loose_gravel",0.0)) else "gravel"

func resistance(width: float, depth: float) -> float:
    if volume() <= 1e-12: return 0.0
    var cohesion := lerpf(weighted("effective_cohesion_peak_pa"),weighted("effective_cohesion_residual_pa"),damage)
    return width*(mass()/volume()*9.81*depth*depth*1.4+cohesion*depth*1.8+weighted("steel_adhesion_pa")*depth*0.5)

func save() -> Dictionary:
    return {"dry":dry.duplicate(),"water":water,"free_water":free_water,"void_ratio":void_ratio,"damage":damage}

static func restore(data: Dictionary) -> MaterialBatch:
    setup()
    var batch := MaterialBatch.new()
    batch.dry = data["dry"].duplicate()
    batch.water = float(data["water"])
    batch.free_water = float(data["free_water"])
    batch.void_ratio = float(data["void_ratio"])
    batch.damage = float(data["damage"])
    return batch
