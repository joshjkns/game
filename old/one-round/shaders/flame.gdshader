// A billboarded, noise-driven flame. Additive, so it glows through the bloom.
// `fuel` (per instance) shrinks and cools the flame as a brazier burns down.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.45, 0.12);
uniform vec3 core : source_color = vec3(1.0, 0.85, 0.55);
uniform float intensity = 3.0;
instance uniform float fuel = 1.0;
instance uniform float seed = 0.0;

float h21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x),
		mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// Y-locked billboard: the flame always stands upright and faces the camera.
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
	vec3 right = normalize(cross(up, to_cam));
	vec3 fwd = cross(right, up);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	mat4 bb = mat4(vec4(right * sx, 0.0), vec4(up * sy, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float f = clamp(fuel, 0.0, 1.0);
	float t = TIME * 2.4 + seed * 17.0;
	float n = vnoise(vec2(uv.x * 4.0 + seed, uv.y * 3.0 - t * 1.7)) * 0.6
		+ vnoise(vec2(uv.x * 9.0 - seed, uv.y * 7.0 - t * 2.9)) * 0.4;
	float x = (uv.x - 0.5) * 2.0;
	x += (n - 0.5) * 0.5 * uv.y;
	float height = mix(0.25, 1.0, f);
	float y = uv.y / height;
	float body = 1.0 - smoothstep(0.15, 1.0, length(vec2(x * (1.1 + y * 1.6), (y - 0.25) * 1.25)));
	float flame = smoothstep(0.05, 0.55, body * (0.65 + n * 0.7) - y * 0.25);
	vec3 col = mix(tint, core, smoothstep(0.45, 1.0, flame));
	ALBEDO = col * flame * intensity * mix(0.3, 1.0, f);
}
