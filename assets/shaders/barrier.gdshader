shader_type spatial;
// Muretas arredondadas em blocos alternados (cores UNIFEOB) com textura de lona, costuras e
// logo pequeno em alguns blocos.
// UV.x = parâmetro do perfil (0 base interna -> ~0.5 topo -> 1 base externa), UV.y = metros ao longo.
// COLOR.r = 1 para a mureta do lado direito (espelha o logo para ficar legível da pista).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 color_a : source_color = vec4(0.0, 0.094, 0.996, 1.0);
uniform vec4 color_b : source_color = vec4(0.9, 0.91, 0.95, 1.0);
uniform vec4 stripe_color : source_color = vec4(1.0, 0.094, 0.388, 1.0);
uniform float block_length = 4.0;
uniform float groove_width = 0.07;
uniform float logo_every = 5.0;
uniform sampler2D noise_grain : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D canvas_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D logo : source_color, filter_linear_mipmap_anisotropic;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float b = UV.y / block_length;
	float idx = floor(b);
	float f = fract(b) * block_length;
	float alt = mod(idx, 2.0);
	vec3 col = mix(color_a.rgb, color_b.rgb, alt);
	// Faixa magenta na parte baixa da face interna, só nos blocos brancos.
	float stripe = (1.0 - step(0.2, UV.x)) * step(0.11, UV.x) * alt;
	col = mix(col, stripe_color.rgb, stripe);
	// Logo pequeno na face interna de alguns blocos.
	if (mod(idx, logo_every) == 2.0 && UV.x > 0.17 && UV.x < 0.305) {
		float lu = (f - block_length * 0.5) / 2.2 + 0.5;
		if (COLOR.r > 0.5) { lu = 1.0 - lu; }
		float lv = 1.0 - (UV.x - 0.17) / 0.135;
		if (lu > 0.0 && lu < 1.0) {
			float a = texture(logo, vec2(lu, lv)).a;
			vec3 logo_col = alt > 0.5 ? color_a.rgb : vec3(1.0);
			col = mix(col, logo_col, a);
		}
	}
	// Costuras tracejadas perto das bordas da lona.
	float dash = step(0.5, fract(f * 5.0));
	float seam_line = (1.0 - smoothstep(0.0, 0.004, abs(UV.x - 0.155))) + (1.0 - smoothstep(0.0, 0.004, abs(UV.x - 0.33)));
	col *= 1.0 - seam_line * dash * 0.25;
	// Sulcos entre blocos.
	float gw = max(groove_width, fwidth(f));
	float groove = 1.0 - smoothstep(0.0, gw, f) * (1.0 - smoothstep(block_length - gw, block_length, f));
	col *= 1.0 - groove * 0.55;
	float g = texture(noise_grain, world_pos.xz * 0.8 + world_pos.y * 0.5).r;
	col *= 0.94 + g * 0.08;
	ALBEDO = col;
	ROUGHNESS = mix(0.5, 0.68, g);
	SPECULAR = 0.3;
	NORMAL_MAP = texture(canvas_normal, vec2(UV.y * 0.8, UV.x * 3.0)).rgb;
	NORMAL_MAP_DEPTH = 0.35;
}
