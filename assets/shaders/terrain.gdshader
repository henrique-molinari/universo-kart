shader_type spatial;
// Terreno/grama estilizado com variação de cor em espaço de mundo.
// COLOR.r = areia/brita, COLOR.g = gramado aparado (listras, só de perto), COLOR.b = terra batida,
// COLOR.a = oclusão de contato (1 = nenhuma).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 grass_deep : source_color = vec4(0.16, 0.42, 0.12, 1.0);
uniform vec4 grass_mid : source_color = vec4(0.32, 0.6, 0.16, 1.0);
uniform vec4 grass_light : source_color = vec4(0.5, 0.7, 0.22, 1.0);
uniform vec4 grass_cool : source_color = vec4(0.2, 0.52, 0.28, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.68, 0.7, 0.32, 1.0);
uniform vec4 sand_color : source_color = vec4(0.86, 0.78, 0.58, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.55, 0.42, 0.28, 1.0);
uniform vec4 rock_color : source_color = vec4(0.52, 0.5, 0.47, 1.0);
uniform float mow_stripe_width = 6.0;
uniform float mow_strength = 0.16;
uniform sampler2D noise_soft : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_grain : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;
varying vec3 world_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	// Escalas não alinhadas (rotacionadas) para evitar repetição visível de cima.
	vec2 pr = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p;
	float n_big = texture(noise_soft, p * 0.0021).r * 0.6 + texture(noise_soft, pr * 0.0057 + vec2(0.31, 0.77)).r * 0.4;
	float n_mid = texture(noise_soft, pr * 0.019 + vec2(0.3, 0.7)).r;
	float n_small = texture(noise_soft, p * 0.11 + vec2(0.9, 0.2)).r;
	float n_hue = texture(noise_soft, pr * 0.0093 + vec2(0.55, 0.12)).r;
	float grain = texture(noise_grain, p * 0.6).r;
	float grain2 = texture(noise_grain, pr * 2.1).r;

	vec3 col = mix(grass_deep.rgb, grass_mid.rgb, smoothstep(0.15, 0.8, n_big) * 0.75 + 0.25);
	col = mix(col, grass_cool.rgb, smoothstep(0.55, 0.85, n_hue) * 0.45);
	col = mix(col, grass_light.rgb, smoothstep(0.4, 0.95, n_mid) * 0.4);
	col = mix(col, grass_dry.rgb, smoothstep(0.72, 0.95, n_big * 0.7 + n_small * 0.3) * 0.3);
	col *= 0.86 + 0.16 * grain + 0.1 * grain2 + (n_small - 0.5) * 0.1;

	// Listras de corte de grama (campus), suaves e só perto da câmera.
	float dist = length(VERTEX);
	float s = (p.x * 0.8 + p.y * 0.6) / (mow_stripe_width * 2.0);
	float tri = abs(fract(s) - 0.5) * 2.0;
	float aa = max(fwidth(s) * 2.0, 0.02);
	float stripe = smoothstep(0.5 - aa, 0.5 + aa, tri);
	float near_fade = 1.0 - smoothstep(90.0, 230.0, dist);
	col *= 1.0 + (stripe - 0.5) * 2.0 * mow_strength * COLOR.g * near_fade;

	col = mix(col, dirt_color.rgb * (0.85 + 0.3 * grain), COLOR.b);
	float slope = 1.0 - clamp(world_nrm.y, 0.0, 1.0);
	float rock = smoothstep(0.34, 0.52, slope + (n_small - 0.5) * 0.12);
	col = mix(col, rock_color.rgb * (0.8 + 0.4 * n_mid), rock);
	float sand = smoothstep(0.1, 0.6, COLOR.r + (n_small - 0.5) * 0.35);
	vec3 sand_col = sand_color.rgb * (0.82 + 0.3 * grain + 0.1 * grain2);
	col = mix(col, sand_col, sand);
	// Oclusão de contato (base das muretas etc.).
	col *= mix(0.5, 1.0, COLOR.a);

	ALBEDO = col;
	ROUGHNESS = mix(0.93, 0.82, sand);
	SPECULAR = 0.2;
	NORMAL_MAP = texture(grain_normal, p * 0.25).rgb;
	NORMAL_MAP_DEPTH = 0.55;
}
