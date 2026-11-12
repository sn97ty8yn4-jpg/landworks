shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D source_paint : source_color;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform bool has_texture = true;
uniform bool orange_paint = false;
uniform float wear = 0.0;
varying vec3 part_position;
void vertex() { part_position = VERTEX; }
float grain(vec3 p) {
    return fract(sin(dot(floor(p),vec3(127.1,311.7,74.7)))*43758.5453);
}
void fragment() {
    vec3 colour = base_tint.rgb;
    if (has_texture) colour *= texture(source_paint,UV).rgb;
    // Keep the source's pigment detail; shift its red cast toward the warm
    // orange in the user's illustrated reference without replacing the map.
    if (orange_paint) colour.g = mix(colour.g,max(colour.g,colour.r*0.27),0.65);
    float fleck = step(0.88,grain(part_position*115.0));
    float patch = smoothstep(0.42,0.85,grain(part_position*9.0));
    float mud = fleck*patch*wear;
    ALBEDO = mix(colour,vec3(0.19,0.115,0.053),mud);
    ROUGHNESS = mix(orange_paint ? 0.53 : 0.72,0.96,mud);
    METALLIC = orange_paint ? 0.08 : 0.35;
}
