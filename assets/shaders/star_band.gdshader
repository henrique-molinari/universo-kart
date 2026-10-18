shader_type spatial;
// Faixa de constelações do tambor do planetário: azul profundo com estrelas e linhas brilhantes.
// UV.x = volta (0..1), UV.y = altura (0..1).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base : source_color = vec4(0.0, 0.06, 0.55, 1.0);
uniform vec4 star : source_color = vec4(1.0, 0.97, 0.75, 1.0);
uniform float cells_x = 90.0;
uniform float cells_y = 6.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float seg(vec2 p, vec2 a, vec2 b, float w) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return 1.0 - smoothstep(w * 0.5, w, length(pa - ba * h));
}

vec2 star_pos(vec2 cell) {
	return cell + vec2(hash12(cell), hash12(cell + 17.0)) * 0.7 + 0.15;
}

void fragment() {
	vec2 g = vec2(UV.x * cells_x, UV.y * cells_y);
	vec2 id = floor(g);
	float s = 0.0;
	float lines = 0.0;
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			vec2 c = id + vec2(float(dx), float(dy));
			vec2 sp = star_pos(c);
			float r = 0.06 + 0.1 * hash12(c + 5.0);
			s = max(s, 1.0 - smoothstep(r * 0.4, r, length(g - sp)));
			// Algumas estrelas ligadas à vizinha (constelações).
			if (hash12(c + 9.0) > 0.55) {
				vec2 n = star_pos(c + vec2(1.0, hash12(c + 3.0) > 0.5 ? 1.0 : 0.0));
				lines = max(lines, seg(g, sp, n, 0.05));
			}
		}
	}
	float edge = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y));
	vec3 col = mix(base.rgb, star.rgb, max(s, lines * 0.5) * edge);
	ALBEDO = col;
	EMISSION = star.rgb * (s * 1.6 + lines * 0.5) * edge;
	ROUGHNESS = 0.35;
	METALLIC = 0.2;
}
