shader_type spatial;
// Vegetação estilizada (árvores, arbustos, grama, flores) para MultiMesh.
// Vértice: COLOR.rgb = cor base (com AO pintado), COLOR.a = máscara de folhagem (1 folha, 0 tronco).
// Instância: INSTANCE_CUSTOM.rgb = tonalidade da folhagem, INSTANCE_CUSTOM.a = fase do vento.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert_wrap, specular_schlick_ggx;

uniform float wind_strength = 0.06;
uniform float wind_speed = 1.3;
uniform float sway_start = 1.0;
uniform bool use_instance_tint = true;
uniform vec4 backlight_color : source_color = vec4(0.30, 0.42, 0.10, 1.0);
uniform sampler2D noise_soft : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 tint;
varying float leaf;
varying vec3 world_pos;

vec3 srgb_to_linear(vec3 c) {
	c = clamp(c, vec3(0.0), vec3(1.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	leaf = COLOR.a;
	tint = use_instance_tint ? srgb_to_linear(INSTANCE_CUSTOM.rgb) : vec3(1.0);
	float phase = INSTANCE_CUSTOM.a * 6.2831 + MODEL_MATRIX[3].x * 0.07 + MODEL_MATRIX[3].z * 0.05;
	float h = max(VERTEX.y - sway_start, 0.0);
	float s = sin(TIME * wind_speed + phase) * 0.7 + sin(TIME * wind_speed * 2.3 + phase * 1.7) * 0.3;
	VERTEX.x += s * wind_strength * h * leaf;
	VERTEX.z += cos(TIME * wind_speed * 0.8 + phase) * wind_strength * 0.5 * h * leaf;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = srgb_to_linear(COLOR.rgb);
	vec3 col = mix(base, base * tint, leaf);
	float n = texture(noise_soft, world_pos.xz * 0.35 + world_pos.y * 0.3).r;
	col *= mix(1.0, 0.85 + n * 0.3, leaf);
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.72, leaf);
	SPECULAR = 0.25;
	BACKLIGHT = backlight_color.rgb * leaf;
}
