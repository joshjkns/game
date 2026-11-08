shader_type canvas_item;
// Frosted backdrop for the hold-Tab stat sheet: a wide blur, darkened so text on top reads.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod = 2.5;
uniform float dim = 0.45;

void fragment() {
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
	COLOR = vec4(blurred * dim, 1.0);
}
