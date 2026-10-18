shader_type spatial;
// Água estilizada: cor por profundidade, espuma na margem, ondas por normal map animado.
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.22, 0.78, 0.82, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.24, 0.52, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float depth_scale = 0.45;
uniform float foam_distance = 0.7;
uniform float wave_speed = 0.035;
uniform sampler2D wave_normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_soft : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 uv_a = p * 0.045 + vec2(TIME * wave_speed, TIME * wave_speed * 0.6);
	vec2 uv_b = p * 0.07 - vec2(TIME * wave_speed * 0.7, -TIME * wave_speed * 0.9);
	vec3 na = texture(wave_normal_a, uv_a).rgb;
	vec3 nb = texture(wave_normal_b, uv_b).rgb;
	NORMAL_MAP = normalize(mix(na, nb, 0.5));
	NORMAL_MAP_DEPTH = 0.45;

	// Profundidade linear do fundo atrás da água.
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float water_depth = scene_depth - (-VERTEX.z);
	float t = clamp(1.0 - exp(-max(water_depth, 0.0) * depth_scale), 0.0, 1.0);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, t);

	// Espuma na margem, recortada por ruído animado.
	float foam_noise = texture(noise_soft, p * 0.25 + vec2(TIME * 0.02)).r;
	float foam = 1.0 - smoothstep(0.0, foam_distance, water_depth);
	foam = smoothstep(0.35, 0.55, foam * (0.6 + foam_noise * 0.8));
	col = mix(col, foam_color.rgb, foam);

	ALBEDO = col;
	ALPHA = clamp(mix(0.72, 0.97, t) + foam, 0.0, 1.0);
	ROUGHNESS = mix(0.04, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
