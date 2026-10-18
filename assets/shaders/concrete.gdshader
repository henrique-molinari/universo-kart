shader_type spatial;
// Concreto/pedra estilizado: cor de vértice (sRGB) + ruído triplanar, manchas e juntas de fôrma.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_soft : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float joint_spacing = 1.5;
uniform float joint_strength = 0.12;

varying vec3 wp;
varying vec3 wn;

vec3 srgb_to_linear(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}


void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float grain = texture(noise_grain, wp.yz * 0.55).r * w.x + texture(noise_grain, wp.xz * 0.55).r * w.y + texture(noise_grain, wp.xy * 0.55).r * w.z;
	float mottle = texture(noise_soft, wp.yz * 0.06).r * w.x + texture(noise_soft, wp.xz * 0.06).r * w.y + texture(noise_soft, wp.xy * 0.06).r * w.z;
	vec3 base = srgb_to_linear(COLOR.rgb);
	vec3 col = base * (0.86 + 0.22 * grain) * (0.9 + 0.2 * mottle);
	// Juntas horizontais de fôrma nas faces verticais.
	float vert = 1.0 - abs(wn.y);
	float jy = abs(fract(wp.y / joint_spacing) - 0.5) * 2.0;
	float line = smoothstep(0.93, 0.985, jy) * vert;
	col *= 1.0 - line * joint_strength;
	ALBEDO = col;
	ROUGHNESS = 0.82 - grain * 0.1;
	SPECULAR = 0.3;
	NORMAL_MAP = texture(grain_normal, (wp.xz + wp.yy) * 0.4).rgb;
	NORMAL_MAP_DEPTH = 0.35;
}
