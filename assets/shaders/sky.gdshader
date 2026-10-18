shader_type sky;
// Céu estilizado ensolarado com nuvens "fofas" animadas.
// `cloud_time` é avançado por script (SkyController) para manter o modo INCREMENTAL de radiância barato.

uniform vec4 zenith_color : source_color = vec4(0.10, 0.38, 0.95, 1.0);
uniform vec4 upper_color : source_color = vec4(0.28, 0.60, 1.0, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.80, 0.91, 1.0, 1.0);
uniform vec4 ground_color : source_color = vec4(0.46, 0.47, 0.43, 1.0);
uniform vec4 cloud_light : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shadow : source_color = vec4(0.62, 0.72, 0.9, 1.0);
uniform float sun_size = 0.028;
uniform float sun_glow = 0.35;
uniform float cloud_coverage = 0.44;
uniform float cloud_softness = 0.085;
uniform float cloud_scale = 0.55;
uniform float cloud_time = 0.0;
uniform vec2 wind = vec2(0.012, 0.004);
uniform float exposure = 1.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_detail : filter_linear_mipmap, repeat_enable;

float cloud_density(vec2 uv, float detail_amount) {
	float base = texture(cloud_noise, uv).r;
	float det = texture(cloud_detail, uv * 3.1 + vec2(0.13, 0.71)).r;
	return base * (1.0 - detail_amount * 0.35) + det * detail_amount * 0.35;
}

void sky() {
	vec3 dir = EYEDIR;
	float h = dir.y;
	vec3 col;
	if (h >= 0.0) {
		float t = pow(clamp(h, 0.0, 1.0), 0.45);
		col = mix(horizon_color.rgb, upper_color.rgb, smoothstep(0.0, 0.55, t));
		col = mix(col, zenith_color.rgb, smoothstep(0.5, 1.0, t));
	} else {
		col = mix(horizon_color.rgb, ground_color.rgb, smoothstep(0.0, 0.25, -h));
	}

	// Sol (disco + halo), usando a primeira luz direcional.
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = max(dot(dir, sun_dir), 0.0);
	// Disco suave (borda larga) + halo quente em duas camadas.
	float sun_disk = smoothstep(1.0 - sun_size * 0.016, 1.0 - sun_size * 0.006, sd);
	float halo_wide = pow(sd, 10.0) * sun_glow;
	float halo_near = pow(sd, 120.0) * 0.6;
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	vec3 warm = vec3(1.0, 0.82, 0.58);
	if (LIGHT0_ENABLED) {
		col += warm * sun_col * (halo_wide * 0.35 + halo_near * 0.6);
		col = mix(col, vec3(1.0, 0.96, 0.86) * 2.2, sun_disk * step(0.0, h));
	}

	// Nuvens projetadas num plano (curvado) acima da câmera.
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.18) * cloud_scale * 0.18 + wind * cloud_time;
		float detail = AT_CUBEMAP_PASS ? 0.0 : 1.0;
		float d = cloud_density(uv, detail);
		float cov = 1.0 - cloud_coverage;
		float c = smoothstep(cov, cov + cloud_softness, d);
		// Sombreamento: amostra deslocada em direção ao sol.
		vec2 to_sun = normalize(sun_dir.xz + vec2(0.0001)) * 0.018;
		float d2 = cloud_density(uv + to_sun, detail);
		float lit = clamp(0.55 + (d - d2) * 5.0, 0.0, 1.0);
		vec3 ccol = mix(cloud_shadow.rgb, cloud_light.rgb, lit);
		ccol += sun_col * pow(sd, 6.0) * 0.25 * (1.0 - c * 0.5);
		float fade = smoothstep(0.0, 0.2, h);
		col = mix(col, ccol, c * fade * 0.96);
	}
	COLOR = col * exposure;
}
