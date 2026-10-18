shader_type spatial;
// Caixa de item iridescente: arco-íris que gira com o tempo e muda com o ângulo de visão (fresnel),
// arestas brilhantes e miolo translúcido. UV do BoxMesh: atlas 3x2 (uma face por célula).
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

uniform float alpha_base = 0.26;

vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	vec2 f = fract(UV * vec2(3.0, 2.0));
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float edge = 1.0 - smoothstep(0.02, 0.1, d);
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	vec3 rainbow = hue(fract(TIME * 0.22 + (f.x + f.y) * 0.3 + fres * 0.6));
	ALBEDO = mix(vec3(0.75, 0.88, 1.0), rainbow, 0.5) * 0.35;
	EMISSION = rainbow * (0.35 + fres * 1.5) + vec3(1.0) * edge * 1.3;
	ROUGHNESS = 0.05;
	SPECULAR = 0.8;
	ALPHA = clamp(alpha_base + fres * 0.45 + edge * 0.6, 0.0, 0.95);
}
