shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform vec4 soil_colour : source_color = vec4(0.48,0.36,0.22,1.0);
varying vec3 local_point;
void vertex() { local_point = VERTEX; }
void fragment() {
    float grain = fract(sin(dot(floor(local_point*125.0),vec3(127.1,311.7,74.7)))*43758.5453);
    float clod = fract(sin(dot(floor(local_point*29.0),vec3(51.3,31.7,91.1)))*13758.5453);
    ALBEDO = soil_colour.rgb*(0.74+0.30*grain+0.18*clod);
    ROUGHNESS = 1.0;
}
