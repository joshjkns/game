// Temporal armour: a shimmering fresnel shell with scrolling bands. Additive.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.6, 0.7, 0.9, 1.0);
uniform float energy = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float bands = 0.55 + 0.45 * sin(UV.y * 70.0 - TIME * 4.0);
	ALBEDO = tint.rgb * (rim * (0.6 + bands * 0.8) + 0.03) * energy;
}
