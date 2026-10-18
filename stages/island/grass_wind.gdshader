shader_type spatial;
render_mode cull_disabled;
uniform float wind_strength = 0.035;
void vertex() {
 float tip = clamp(VERTEX.y, 0.0, 1.0);
 VERTEX.x += sin(TIME * 1.2 + NODE_POSITION_WORLD.x * 0.17 + VERTEX.z) * wind_strength * tip;
}
void fragment() { ALBEDO = vec3(0.0, 0.5569, 0.2941); ROUGHNESS = 1.0; }
