// Procedural dungeon surfaces in world space (no textures): bricks, flagstones, planks or
// rough stone. Mortar grooves and chipped edges feed a derivative bump so torchlight rakes
// across the surface; grime darkens wall bases and puddles turn floors glossy for SSR.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 color_a : source_color = vec3(0.36, 0.31, 0.26);
uniform vec3 color_b : source_color = vec3(0.22, 0.19, 0.16);
uniform vec3 mortar_color : source_color = vec3(0.07, 0.06, 0.05);
// 0 bricks, 1 flagstones, 2 planks, 3 rough stone
uniform int pattern = 0;
uniform vec2 cell = vec2(0.62, 0.3);
uniform float gap = 0.022;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.0;
uniform float bump = 1.0;
uniform float grime = 0.5;
uniform float wet = 0.0;
uniform float moss = 0.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

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

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// x: height (0 in grooves), y: tone 0..1, z: per-cell hash, w: groove mask (1 = mortar)
vec4 pat(vec2 uv) {
	if (pattern == 3) {
		float n = fbm(uv * 2.2);
		float fine = vnoise(uv * 14.0);
		return vec4(0.55 + 0.35 * n + 0.1 * fine, n, 0.5, 0.0);
	}
	vec2 cs = cell;
	vec2 c = uv / cs;
	float row = floor(c.y);
	if (pattern == 2) {
		c.x += h21(vec2(row, 3.1)) * 7.0;
	} else {
		c.x += mod(row, 2.0) * 0.5 + (pattern == 1 ? h21(vec2(row, 1.3)) * 0.35 : 0.0);
	}
	vec2 id = floor(c);
	vec2 f = fract(c);
	vec2 dm = min(f, 1.0 - f) * cs;
	float e = min(dm.x, dm.y);
	float cid = h21(id + vec2(17.0, 31.0));
	float g = gap * (0.8 + 0.5 * vnoise(uv * 6.0));
	float hgt = smoothstep(g * 0.35, g * 1.8, e);
	if (pattern == 0) {
		// Chipped, pillowed bricks.
		hgt *= 0.82 + 0.18 * vnoise(uv * 11.0 + id * 7.0);
		hgt *= 0.9 + 0.1 * smoothstep(0.0, 0.08, e);
	} else if (pattern == 1) {
		// Slightly tilted, worn flagstones with the odd crack.
		vec2 tilt = vec2(h21(id + 3.0), h21(id + 7.0)) - 0.5;
		hgt *= 0.8 + 0.12 * dot(f - 0.5, tilt) + 0.15 * vnoise(uv * 7.0 + id * 5.0);
		float crack = abs(vnoise(uv * 3.0 + id * 11.0) - 0.5);
		hgt -= (1.0 - smoothstep(0.0, 0.025, crack)) * 0.35 * step(0.6, cid);
	} else {
		// Wood grain along the plank.
		float grain = vnoise(vec2(uv.x * 1.5, uv.y * 60.0) + id * 13.0);
		hgt *= 0.9 + 0.1 * grain;
	}
	float tone = cid * 0.7 + 0.3 * vnoise(uv * 1.7);
	return vec4(hgt, tone, cid, 1.0 - smoothstep(g * 0.2, g * 1.2, e));
}

void fragment() {
	vec3 an = abs(wnrm);
	vec3 w = pow(an, vec3(8.0));
	w /= (w.x + w.y + w.z);
	vec4 p = vec4(0.0);
	vec2 uv_main = wpos.xz;
	if (w.x > 0.01) { p += w.x * pat(vec2(wpos.z, wpos.y)); }
	if (w.y > 0.01) { p += w.y * pat(vec2(wpos.x, wpos.z)); }
	if (w.z > 0.01) { p += w.z * pat(vec2(wpos.x, wpos.y)); }
	if (an.x > an.y && an.x > an.z) { uv_main = wpos.zy; } else if (an.z > an.y) { uv_main = wpos.xy; }

	float hgt = p.x;
	float big = fbm(uv_main * 0.45);
	vec3 col = mix(color_a, color_b, clamp(p.y * 0.8 + big * 0.5 - 0.15, 0.0, 1.0));
	col *= 0.75 + 0.5 * fbm(uv_main * 3.1 + 4.0);
	col = mix(col, mortar_color, p.w);
	float up = clamp(wnrm.y, 0.0, 1.0);
	// Soot and damp creeping up from the floor on walls; stains on floors.
	float base_grime = (1.0 - smoothstep(0.0, 1.6, wpos.y)) * (1.0 - up);
	col *= 1.0 - grime * (0.55 * base_grime + 0.35 * smoothstep(0.45, 0.8, big));
	if (moss > 0.0) {
		float m = smoothstep(0.55, 0.75, fbm(uv_main * 1.3 + 7.0)) * (1.0 - smoothstep(0.0, 2.5, wpos.y)) * moss;
		col = mix(col, vec3(0.06, 0.09, 0.04), m * (1.0 - up * 0.5));
	}
	float rough = roughness_base * (0.85 + 0.3 * vnoise(uv_main * 5.0));
	rough = mix(rough, 1.0, p.w * 0.5);
	float b = bump;
	if (wet > 0.0) {
		float puddle = smoothstep(0.52, 0.62, fbm(wpos.xz * 0.35 + 13.0)) * wet * up;
		puddle = max(puddle, p.w * wet * up * 0.6);
		col *= 1.0 - 0.45 * puddle;
		rough = mix(rough, 0.05, puddle);
		b *= 1.0 - 0.8 * puddle;
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.03, 1.0);
	METALLIC = metallic_base;
	AO = mix(0.55, 1.0, hgt);
	AO_LIGHT_AFFECT = 0.4;
	EMISSION = emission_color * emission_energy;

	// Bump from the height field via screen-space derivatives (surface gradient).
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhdx = dFdx(hgt) * 0.035 * b;
	float dhdy = dFdy(hgt) * 0.035 * b;
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhdx * r1 + dhdy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad);
}
