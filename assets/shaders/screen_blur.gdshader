shader_type canvas_item;
// Desfoque da imagem 3D de fundo (tela de título): amostra a textura da tela com mipmaps
// (gaussiano 5x5 sobre um nível já reduzido), leve tinta azul e vinheta.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lod = 2.2;
uniform float radius_px = 5.0;
uniform vec4 tint : source_color = vec4(0.0, 0.06, 0.45, 0.22);
uniform float vignette = 0.45;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * radius_px;
	vec3 c = vec3(0.0);
	float w = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float k = exp(-float(x * x + y * y) / 4.5);
			c += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px, lod).rgb * k;
			w += k;
		}
	}
	c /= w;
	c = mix(c, tint.rgb, tint.a);
	float v = smoothstep(0.95, 0.25, distance(UV, vec2(0.5)));
	c *= mix(1.0 - vignette, 1.0, v);
	COLOR = vec4(c, 1.0);
}
