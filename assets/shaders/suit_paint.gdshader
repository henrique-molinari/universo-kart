shader_type spatial;
// Pintura do tronco do macacão do piloto, por pixel: faixas laterais com filete, zíper e patches no peito
// com bordas nítidas (a cor por vértice deixava "degraus"). d = ponto no elipsoide do tronco (esfera unitária).
// Cores lineares, como as cores de vértice do resto do macacão.
render_mode specular_schlick_ggx;

uniform vec3 center;
uniform mat3 to_local;   // inversa da base do tronco
uniform vec3 radii;
uniform vec3 suit = vec3(0.1, 0.3, 0.8);
uniform vec3 stripe = vec3(0.15, 0.88, 1.0);
uniform vec3 accent = vec3(0.97);
uniform bool rainbow = false;
uniform vec3 rainbow_colors[6];

varying vec3 d;

void vertex() {
	d = (to_local * (VERTEX - center)) / radii;
}

float over(float x, float e) {
	float w = max(fwidth(x), 1e-4);
	return smoothstep(e - w, e + w, x);
}

float box(vec2 p, vec2 lo, vec2 hi) {
	return over(p.x, lo.x) * (1.0 - over(p.x, hi.x)) * over(p.y, lo.y) * (1.0 - over(p.y, hi.y));
}

void fragment() {
	vec3 n = normalize(d);
	float ax = abs(n.x);
	vec3 col = suit;
	if (rainbow) {
		float f = clamp((n.x * 0.5 + 0.5) * 6.0, 0.0, 5.999);
		int i = int(floor(f));
		float w = max(fwidth(f), 1e-4);
		col = mix(rainbow_colors[i], rainbow_colors[min(i + 1, 5)], smoothstep(1.0 - w, 1.0, fract(f)));
	}
	float front = 1.0 - over(n.z, -0.3);
	// Patches no peito (direito claro, esquerdo na cor da equipe).
	float patch = front * box(vec2(ax, n.y), vec2(0.26, 0.05), vec2(0.6, 0.42));
	col = mix(col, n.x > 0.0 ? accent : stripe, patch);
	// Zíper.
	col = mix(col, suit * 0.45, (1.0 - over(n.z, -0.25)) * (1.0 - over(ax, 0.045)) * (1.0 - over(n.y, 0.75)));
	// Faixa lateral com filete.
	col = mix(col, accent, over(ax, 0.76));
	col = mix(col, stripe, over(ax, 0.84));
	ALBEDO = col;
	ROUGHNESS = 0.68;
	RIM = 0.3;
	RIM_TINT = 0.45;
}
