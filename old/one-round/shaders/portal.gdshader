// The exit portal: a swirl of amber (forward) and cyan (inverted) time. `open` fades it in.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float open : hint_range(0.0, 1.0) = 0.0;
uniform vec3 col_a : source_color = vec3(1.0, 0.6, 0.12);
uniform vec3 col_b : source_color = vec3(0.15, 0.85, 1.0);
uniform vec3 locked : source_color = vec3(1.0, 0.1, 0.14);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * 3.0 + r * 9.0 - TIME * 3.0) * 0.5 + 0.5;
	float swirl2 = sin(-a * 2.0 + r * 13.0 - TIME * 4.5) * 0.5 + 0.5;
	float disc = 1.0 - smoothstep(0.75, 1.0, r);
	float ring = smoothstep(0.7, 0.92, r) * (1.0 - smoothstep(0.92, 1.0, r));
	vec3 c = mix(col_a, col_b, swirl) * (0.4 + swirl2 * 0.8);
	vec3 openc = c * disc * (0.5 + 0.8 * (1.0 - r)) + c * ring * 2.0;
	vec3 lockc = locked * ring * (0.6 + 0.4 * sin(TIME * 3.0)) + locked * disc * 0.04;
	ALBEDO = mix(lockc, openc * 1.6, open);
}
