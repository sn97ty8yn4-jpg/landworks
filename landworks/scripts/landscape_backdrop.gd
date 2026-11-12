# Original November 11 artwork: immutable source textures, runtime seam blending.
# Three world-anchored cylindrical belts provide positional parallax without
# collisions. The sky is infinitely distant and always behind real geometry.
extends Node3D

const ASSETS := "res://landworks/assets/landscape/assets/"
const SEGMENTS := 192
const LAYERS := [
    ["03_parallax_far_wooded_hills.png", 1400.0, 210.0, -260.0, 0.16],
    ["02_parallax_middle_pastures.png", 850.0, 85.0, -150.0, 0.09],
    ["01_parallax_near_farms_treelines.png", 450.0, 45.0, -75.0, 0.03]
]

static func make_sky() -> Sky:
    var shader := Shader.new()
    shader.code = """
shader_type sky;
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_disable;
void sky() {
    vec2 uv = SKY_COORDS;
    uv.y *= 0.88;
    float edge = min(uv.x, 1.0-uv.x);
    float blend = 0.5*(1.0-smoothstep(0.0,0.035,edge));
    vec3 original = texture(panorama,uv).rgb;
    vec3 opposite = texture(panorama,vec2(1.0-uv.x,uv.y)).rgb;
    vec3 painted = mix(original,opposite,blend);
    // These concept images are not polar projections. Fade the last few
    // degrees to a uniform colour to prevent a pinwheel at either pole.
    vec3 zenith = texture(panorama,vec2(0.5,0.02)).rgb;
    painted = mix(zenith,painted,smoothstep(0.0,0.08,uv.y));
    COLOR = mix(painted,vec3(0.24,0.27,0.13),smoothstep(0.90,1.0,uv.y));
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("panorama", load(ASSETS + "00_far_sky_panorama_2to1.png"))
    var result := Sky.new()
    result.sky_material = material
    return result

func _ready() -> void:
    for settings in LAYERS:
        _add_belt(settings)
    _add_transition()
    print("LANDSCAPE_READY original_assets=4 parallax_layers=3 colliders=0")

func _add_belt(settings: Array) -> void:
    var radius: float = settings[1]
    var top: float = settings[2]
    var bottom: float = settings[3]
    var mesh_builder := SurfaceTool.new()
    mesh_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
    for segment in range(SEGMENTS):
        var u0 := float(segment)/SEGMENTS
        var u1 := float(segment+1)/SEGMENTS
        for point in [Vector2(u0,0),Vector2(u0,1),Vector2(u1,1),
                Vector2(u0,0),Vector2(u1,1),Vector2(u1,0)]:
            var angle: float = point.x*TAU
            mesh_builder.set_uv(point)
            mesh_builder.add_vertex(Vector3(sin(angle)*radius,
                lerpf(top,bottom,point.y),-cos(angle)*radius))
    var belt := MeshInstance3D.new()
    belt.name = str(settings[0]).get_basename()
    belt.mesh = mesh_builder.commit()
    belt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform sampler2D artwork : source_color, filter_linear_mipmap, repeat_disable;
uniform float haze = 0.0;
void fragment() {
    // The supplied strips are 3:1 concept art, not full spherical maps.
    // Six curved sectors retain plausible tree/building proportions. This
    // repeats motifs, a documented limitation of the existing prototype art.
    vec2 uv = vec2(fract(UV.x*6.0+haze),UV.y);
    vec4 a = texture(artwork,uv);
    vec4 b = texture(artwork,vec2(1.0-uv.x,uv.y));
    float weight = 0.5*(1.0-smoothstep(0.0,0.035,min(uv.x,1.0-uv.x)));
    // Alpha-weighted blend avoids dark RGB fringes in transparent texels.
    float alpha = mix(a.a,b.a,weight);
    vec3 colour = mix(a.rgb*a.a,b.rgb*b.a,weight)/max(alpha,0.0001);
    ALBEDO = mix(colour,vec3(0.64,0.69,0.64),haze);
    ALPHA = alpha;
    ALPHA_SCISSOR_THRESHOLD = 0.12;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("artwork",load(ASSETS + str(settings[0])))
    material.set_shader_parameter("haze",float(settings[4]))
    belt.material_override = material
    add_child(belt)

func _add_transition() -> void:
    # A visual skirt starts outside the existing yard. It cannot cover the
    # diggable pad and is not an expansion of the playable collision terrain.
    var builder := SurfaceTool.new()
    builder.begin(Mesh.PRIMITIVE_TRIANGLES)
    var corners := [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]
    for side in range(4):
        var a: Vector2 = corners[side]
        var b: Vector2 = corners[(side+1)%4]
        var points := [Vector3(a.x*70,-0.01,a.y*70),
            Vector3(b.x*70,-0.01,b.y*70),
            Vector3(b.x*1800,-100,b.y*1800),
            Vector3(a.x*1800,-100,a.y*1800)]
        for index in [0,1,2,0,2,3]:
            builder.add_vertex(points[index])
    var skirt := MeshInstance3D.new()
    skirt.name = "VisualTerrainTransition_NoCollision"
    skirt.mesh = builder.commit()
    skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var mat := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec3 world_point;
void vertex() { world_point = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 p = world_point.xz;
    float wash = sin(p.x*0.027+cos(p.y*0.019))*cos(p.y*0.031);
    float fields = 0.5+0.5*sin(p.x*0.017+sin(p.y*0.022))*sin(p.y*0.013);
    vec3 pasture = mix(vec3(0.29,0.35,0.12),vec3(0.38,0.40,0.18),fields);
    ALBEDO = pasture*(0.92+wash*0.07);
}
"""
    mat.shader = shader
    skirt.material_override = mat
    add_child(skirt)
