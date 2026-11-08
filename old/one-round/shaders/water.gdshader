// Glowing dungeon water: dark and glossy (so SSR picks up the torches), with drifting
// caustic light in the room's accent colour. The emission also feeds SDFGI bounce light.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.01, 0.05, 0.05);
uniform vec3 glow : source_color = vec3(0.15, 0.9, 0.65);
uniform float glow_energy = 1.4;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float caustic(vec2 p, float t) {
	vec2 q = p;
	float v = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		q += vec2(sin(q.y * 1.3 + t * (0.7 + fi * 0.13)), cos(q.x * 1.1 - t * (0.5 + fi * 0.11)));
		v += 1.0 / (1.0 + 8.0 * abs(sin(q.x * 0.9 + q.y * 0.7)));
	}
	return v / 4.0;
}

void fragment() {
	float t = TIME * 0.5;
	vec2 p = wpos.xz * 1.6;
	float c = caustic(p, t);
	float c2 = caustic(p * 0.6 + 3.0, t * 0.7);
	ALBEDO = deep;
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
	EMISSION = glow * glow_energy * (0.15 + 0.85 * pow(c * c2 * 1.6, 2.0));
	// Gentle ripples.
	float rx = sin(wpos.x * 5.0 + TIME * 1.3) * 0.5 + sin(wpos.z * 7.0 - TIME * 1.1) * 0.5;
	float rz = cos(wpos.z * 5.0 + TIME * 1.7) * 0.5 + cos(wpos.x * 6.0 + TIME * 0.9) * 0.5;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(rx * 0.04, 0.0, rz * 0.04, 0.0)).xyz);
}
