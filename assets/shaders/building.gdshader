shader_type spatial;
// Fachadas estilizadas de campus com janelas procedurais.
// UV.x = perímetro (m), UV.y = altura (m) nas paredes. COLOR.r = 1 parede com janelas, 0 superfície lisa.
// COLOR.g = 1 usa cor de destaque, COLOR.b = 1 cobertura (cinza). Parâmetros por instância (um material para todos os prédios).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

instance uniform vec4 wall_color : source_color = vec4(0.93, 0.93, 0.95, 1.0);
instance uniform vec4 accent_color : source_color = vec4(0.0, 0.094, 0.996, 1.0);
instance uniform vec4 glass_color : source_color = vec4(0.16, 0.34, 0.62, 1.0);
instance uniform vec4 window_params = vec4(3.2, 3.6, 0.62, 0.55); // largura célula, altura andar, fração larg., fração alt.
instance uniform float ground_floor = 4.2;
instance uniform float lit_ratio = 0.05;
instance uniform float curtain_wall = 0.0;

uniform vec4 roof_color : source_color = vec4(0.5, 0.5, 0.51, 1.0);
uniform vec4 sky_reflect : source_color = vec4(0.62, 0.8, 1.0, 1.0);
uniform vec4 blind_color : source_color = vec4(0.92, 0.88, 0.78, 1.0);
uniform sampler2D noise_grain : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float g = texture(noise_grain, world_pos.xz * 0.3 + world_pos.y * 0.21).r;
	vec3 wall = mix(wall_color.rgb, accent_color.rgb, COLOR.g);
	wall = mix(wall, roof_color.rgb, COLOR.b);
	vec3 col = wall * (0.94 + g * 0.1);
	// Cobertura com textura de brita/manta.
	col *= mix(1.0, 0.78 + 0.42 * g, COLOR.b);
	float rough = 0.7;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float spec = 0.4;

	if (COLOR.r > 0.5) {
		float cw = window_params.x;
		float fh = window_params.y;
		vec2 cell = vec2(UV.x / cw, (UV.y - ground_floor) / fh);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float wx = window_params.z;
		float wy = window_params.w;
		if (curtain_wall > 0.5) { wx = 0.94; wy = 0.9; }
		vec2 lo = vec2((1.0 - wx) * 0.5, (1.0 - wy) * 0.45);
		vec2 aa = fwidth(cell) * 1.2;
		float win = smoothstep(lo.x - aa.x, lo.x + aa.x, f.x) * (1.0 - smoothstep(1.0 - lo.x - aa.x, 1.0 - lo.x + aa.x, f.x));
		win *= smoothstep(lo.y - aa.y, lo.y + aa.y, f.y) * (1.0 - smoothstep(lo.y + wy - aa.y, lo.y + wy + aa.y, f.y));
		// Térreo: vidraças altas.
		if (UV.y < ground_floor) {
			float gx = fract(UV.x / (cw * 1.5));
			float gaa = fwidth(UV.x / (cw * 1.5)) * 1.2;
			win = smoothstep(0.05 - gaa, 0.05 + gaa, gx) * (1.0 - smoothstep(0.95 - gaa, 0.95 + gaa, gx));
			win *= smoothstep(0.25, 0.35, UV.y) * (1.0 - smoothstep(ground_floor - 0.75, ground_floor - 0.6, UV.y));
		}
		// Janelas: vidro com variação por janela, reflexo do céu (Fresnel), persianas e caixilhos.
		float r = hash12(id + floor(world_pos.xz * 0.01) * 17.0);
		float r2 = hash12(id * 1.37 + 5.1);
		// Interior falso ("interior mapping"): raio da câmera entra numa sala-caixa atrás do vidro.
		float wy_rel = (f.y - lo.y) / max(wy, 0.001);
		float wx_rel = (f.x - lo.x) / max(wx, 0.001);
		vec3 nw = normalize(world_nrm);
		float det = dFdx(UV.x) * dFdy(UV.y) - dFdy(UV.x) * dFdx(UV.y);
		vec3 tw = (dFdx(world_pos) * dFdy(UV.y) - dFdy(world_pos) * dFdx(UV.y)) * sign(det);
		tw = tw - nw * dot(tw, nw);
		tw = length(tw) > 1e-5 ? normalize(tw) : normalize(cross(vec3(0.0, 1.0, 0.0), nw));
		vec3 bw = normalize(cross(nw, tw)) * sign(dot(cross(nw, tw), vec3(0.0, 1.0, 0.0)) + 1e-4);
		vec3 vw = normalize(world_pos - CAMERA_POSITION_WORLD);
		vec3 rd = vec3(dot(vw, tw), dot(vw, bw), max(dot(vw, -nw), 0.06));
		vec3 hs = vec3(cw * wx * 0.5, fh * wy * 0.5, 2.8 + r * 1.6);
		vec3 ro = vec3((wx_rel * 2.0 - 1.0) * hs.x, (wy_rel * 2.0 - 1.0) * hs.y, 0.0);
		vec3 tb = (sign(rd) * hs - ro) / rd;
		tb.z = hs.z / rd.z;
		float th = min(min(tb.x, tb.y), tb.z);
		vec3 hit = ro + rd * th;
		vec3 room_tint = mix(vec3(0.95, 0.86, 0.72), vec3(0.78, 0.84, 0.92), r2);
		vec3 room;
		if (th == tb.z) {
			room = room_tint * 0.85;
			// Quadro/estante no fundo de algumas salas.
			room = mix(room, mix(vec3(0.25, 0.32, 0.5), vec3(0.55, 0.3, 0.22), r), step(0.5, r) * step(abs(hit.x - (r - 0.5) * hs.x), hs.x * 0.35) * step(abs(hit.y + 0.1 * hs.y), hs.y * 0.3));
		} else if (th == tb.y) {
			room = rd.y < 0.0 ? vec3(0.3, 0.25, 0.2) * (0.8 + 0.4 * r) : vec3(1.1, 1.08, 1.02);
		} else {
			room = room_tint * 0.68;
		}
		room *= mix(1.0, 0.55, clamp(hit.z / hs.z, 0.0, 1.0));
		room *= mix(0.45, 1.0, step(1.0 - lit_ratio * 4.0, r));
		vec3 glass = room * mix(vec3(1.0), glass_color.rgb * 1.8, 0.45);
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		glass = mix(glass, sky_reflect.rgb, clamp(fres * 0.6 + 0.07, 0.0, 0.65));
		// Persianas em parte das janelas (faixa clara no topo).
		float blind = step(0.55, r2) * step(1.0 - (0.25 + 0.5 * r), wy_rel);
		glass = mix(glass, blind_color.rgb * 0.8, blind * (1.0 - curtain_wall * 0.6));
		// Caixilho central.
		float mull = 1.0 - smoothstep(0.0, aa.x * 1.5 + 0.01, abs(f.x - 0.5));
		glass = mix(glass, wall_color.rgb * 0.9, mull * 0.8);
		float lit = step(1.0 - lit_ratio, r);
		col = mix(col, glass, win);
		// Moldura de destaque sob as janelas (peitoril).
		float sill = (1.0 - step(0.08, abs(f.y - (lo.y - 0.04)))) * (1.0 - win) * step(ground_floor, UV.y) * step(0.5, 1.0 - curtain_wall);
		col = mix(col, accent_color.rgb, sill * 0.85);
		rough = mix(rough, mix(0.04, 0.2, r2) + blind * 0.5, win);
		metal = mix(metal, 0.15, win);
		spec = mix(spec, 0.7, win);
		emit = vec3(1.0, 0.86, 0.6) * lit * win * 0.06;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = emit;
}
