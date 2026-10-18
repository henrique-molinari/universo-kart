shader_type spatial;
// Pintura do capacete do piloto, por pixel (faixas nítidas e sem serrilhado, ao contrário da cor por vértice).
// d = direção do ponto em relação ao centro do casco, normalizada pelos semi-eixos (esfera unitária).
// As cores são lineares, como as cores de vértice do resto do modelo (mesmo tom do macacão).
render_mode specular_schlick_ggx;

uniform vec3 center = vec3(0.0, 0.3, 0.0);
uniform vec3 radii = vec3(0.28, 0.29, 0.305);
uniform vec3 helmet = vec3(0.1, 0.4, 0.9);
uniform vec3 stripe = vec3(0.15, 0.88, 1.0);
uniform vec3 accent = vec3(0.97);
uniform vec3 rubber = vec3(0.06, 0.06, 0.07);
uniform bool rainbow = false;
uniform vec3 rainbow_colors[6];

varying vec3 d;

void vertex() {
	d = (VERTEX - center) / radii;
}

// 0 abaixo de e, 1 acima, com transição de ~1 pixel.
float over(float x, float e) {
	float w = max(fwidth(x), 1e-4);
	return smoothstep(e - w, e + w, x);
}

void fragment() {
	vec3 n = normalize(d);
	float ax = abs(n.x);
	vec3 col = helmet;
	if (rainbow) {
		float f = clamp((n.x * 0.5 + 0.5) * 6.0, 0.0, 5.999);
		int i = int(floor(f));
		float w = max(fwidth(f), 1e-4);
		col = mix(rainbow_colors[i], rainbow_colors[min(i + 1, 5)], smoothstep(1.0 - w, 1.0, fract(f)));
		col = mix(col, accent, over(n.y, -0.2) * (1.0 - over(ax, 0.06)));
	} else {
		float up = over(n.y, -0.25);
		// Filete lateral com bordas de acabamento claras.
		float side = up * over(n.z, -0.2);
		col = mix(col, accent, side * over(ax, 0.405) * (1.0 - over(ax, 0.515)));
		col = mix(col, stripe, side * over(ax, 0.42) * (1.0 - over(ax, 0.5)));
		// Faixa central (testa -> nuca) com filetes.
		col = mix(col, accent, up * (1.0 - over(ax, 0.15)));
		col = mix(col, stripe, up * (1.0 - over(ax, 0.1)));
	}
	// Barrado inferior e borda emborrachada.
	col = mix(col, accent, 1.0 - over(n.y, -0.54));
	col = mix(col, stripe, 1.0 - over(n.y, -0.62));
	float rub = 1.0 - over(n.y, -0.86);
	col = mix(col, rubber, rub);
	ALBEDO = col;
	ROUGHNESS = mix(0.16, 0.7, rub);
	CLEARCOAT = 1.0 - rub;
	CLEARCOAT_ROUGHNESS = 0.25;
}
