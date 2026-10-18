shader_type canvas_item;
// Linhas de velocidade radiais nas bordas da tela (turbo). intensity 0..1 controlado pelo HUD.
uniform float intensity = 0.0;
uniform float aspect = 3.5;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	uv.x *= aspect * 0.5;
	float r = length(uv);
	float ang = atan(uv.y, uv.x);
	float slice = floor(ang * 70.0);
	float t = floor(TIME * 14.0);
	float on = step(0.82, hash(slice + t * 13.7));
	float start = 0.55 + 0.5 * hash(slice * 3.1 + t);
	float streak = on * smoothstep(start, start + 0.35, r);
	// Afina a linha dentro da fatia angular.
	float w = abs(fract(ang * 70.0) - 0.5) * 2.0;
	streak *= 1.0 - smoothstep(0.15, 0.6, w);
	COLOR = vec4(1.0, 1.0, 1.0, streak * intensity * 0.5);
}
