// Overlay that rims a mesh in a colour (enemies on the aim / recall line).
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.6, 0.1, 1.0);

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = tint.rgb * (0.03 + rim * 1.1) * tint.a;
}
