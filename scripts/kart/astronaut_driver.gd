class_name AstronautDriver
extends PilotDriver
## Astronauta do Universo, procedural (MeshKit), no estilo do traje EMU da NASA: traje branco volumoso com
## vincos, anéis de rolamento (cintura, coxas, braços) e conectores de punho em prata e azul UNIFEOB, botas
## brancas de sola cinza, módulo de controle no peito (botões, visor, mangueiras) e mochila de suporte de vida.
## Capacete: casca branca, viseira dourada espelhada com moldura, dobradiças, luzes de EVA laterais (2 lentes
## + câmera) e anel de pescoço azul. Todos os emblemas da NASA trocados pelos da UNIFEOB: emblema redondo no
## peito, "bandeira" UNIFEOB no ombro esquerdo, plaqueta no peito direito e logo na mochila e no capacete.
## Reaproveita do PilotDriver o rig, o IK, as poses e a comemoração (socos no ar + confete).

## Cores do traje (mesmo formato dos esquemas do piloto; também usadas pela comemoração/minimapa).
const SCHEME := {"helmet": Color(0.93, 0.93, 0.92), "suit": Color(0.9, 0.9, 0.88), "stripe": Color(0.0, 0.0941, 0.9961),
	"accent": Color(0.93, 0.93, 0.92), "visor": Color(0.95, 0.68, 0.22), "glove": Color(0.88, 0.88, 0.87), "rainbow": false}
const SILVER := Color(0.72, 0.74, 0.77)
const SOLE := Color(0.32, 0.33, 0.35)
const ASTRO_HELMET_R := Vector3(0.3, 0.31, 0.3)

static var _emblem_tex: ImageTexture
static var _flag_tex: ImageTexture
static var _word_tex: ImageTexture


func build(_char_id: int, suit: Color) -> void:
	character = Characters.ASTRONAUT
	scheme = SCHEME
	name = "Driver"
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var fabric := _fabric_mat()
	var glove_mat := _mat(0.55, 0.1)
	_build_suit(suit, fabric)
	_build_gear()
	_build_astro_helmet()
	_build_astro_arms(suit, fabric, glove_mat)


static func _metal() -> StandardMaterial3D:
	var m := _mat(0.3, 0.3)
	m.metallic = 0.7
	return m


static func _decal_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Decalque que acompanha a curvatura de um elipsoide (centro `c`, base `b`, raios `r`), na face -Z local.
## (u0, v0) = centro no plano da imagem (u para a direita de quem olha, v para cima); hw/hh = meia largura/altura.
static func _surf_decal(k: MeshKit, c: Vector3, b: Basis, r: Vector3, u0: float, v0: float, hw: float, hh: float) -> void:
	var n := 6
	var base_i := k.verts.size()
	for j in n + 1:
		for i in n + 1:
			var lx := -(u0 + lerpf(-hw, hw, float(i) / n))
			var ly := v0 + lerpf(hh, -hh, float(j) / n)
			var lz := -r.z * sqrt(maxf(1.0 - (lx / r.x) * (lx / r.x) - (ly / r.y) * (ly / r.y), 0.0))
			var nl := Vector3(lx / (r.x * r.x), ly / (r.y * r.y), lz / (r.z * r.z)).normalized()
			k.add_vertex(c + b * (Vector3(lx, ly, lz) + nl * 0.004), b * nl, Vector2(float(i) / n, float(j) / n), Color.WHITE)
	for j in n:
		for i in n:
			var a0 := base_i + j * (n + 1) + i
			k.quad(a0, a0 + 1, a0 + n + 1, a0 + n + 2)


## Decalque plano: `right`/`up` = meio vetor da largura/altura da imagem, vista de frente.
static func _flat_decal(k: MeshKit, c: Vector3, right: Vector3, up: Vector3) -> void:
	var n := right.cross(up).normalized()
	var i0 := k.add_vertex(c - right + up, n, Vector2(0, 0), Color.WHITE)
	k.add_vertex(c + right + up, n, Vector2(1, 0), Color.WHITE)
	k.add_vertex(c - right - up, n, Vector2(0, 1), Color.WHITE)
	k.add_vertex(c + right - up, n, Vector2(1, 1), Color.WHITE)
	k.quad(i0, i0 + 1, i0 + 2, i0 + 3)


# ------------------------------------------------------------------ traje

## Traje EMU: tronco rígido branco, anel de cintura, pernas volumosas com anéis nas coxas e botas.
func _build_suit(kc: Color, fabric: Material) -> void:
	var o := -ORIGIN
	var tb := Basis(Vector3.RIGHT, TORSO_TILT)
	var t := MeshKit.new()
	var r := MeshKit.new()   # anéis e conectores metálicos
	# Quadril primeiro (o 1º vértice tem exatamente a cor do traje).
	_ell(t, o + Vector3(0, 0.5, 0.32), Basis.IDENTITY, Vector3(0.19, 0.13, 0.17), kc, 10, 18, 0.25)
	# Tronco rígido (HUT): branco com costura sutil na lateral.
	var torso_paint := func(d: Vector3) -> Color:
		if absf(absf(d.x) - 0.8) < 0.025:
			return kc.darkened(0.12)
		return kc.darkened(0.1 * clampf(-d.y - 0.5, 0.0, 1.0))
	_ell_paint(t, o + Vector3(0, 0.7, 0.3), tb, Vector3(0.19, 0.235, 0.165), 20, 32, torso_paint)
	_ell(t, o + Vector3(0, 0.905, 0.27), Basis.IDENTITY, Vector3(0.13, 0.035, 0.12), kc.darkened(0.08), 6, 18)  # gola
	# Anel de cintura (prata com filete azul).
	_ell(r, o + Vector3(0, 0.56, 0.31), Basis.IDENTITY, Vector3(0.198, 0.03, 0.176), SILVER, 6, 22)
	_ell(r, o + Vector3(0, 0.56, 0.31), Basis.IDENTITY, Vector3(0.201, 0.011, 0.179), Palette.BLUE, 4, 22)
	for s: float in [-1.0, 1.0]:
		var sh := o + Vector3(s * SHOULDER.x, SHOULDER.y, SHOULDER.z)
		t.sphere(Transform3D(Basis.IDENTITY, sh), 0.085, 8, 14, kc)
		var hip := o + Vector3(s * 0.09, 0.5, 0.28)
		var knee := o + Vector3(s * 0.16, 0.645, -0.36)
		var ankle := o + Vector3(s * 0.15, 0.4, -0.56)
		_limb_ab(t, hip, knee, PackedFloat32Array([0.088, 0.092, 0.086, 0.076]), 16, kc, 0.12)   # coxa
		t.sphere(Transform3D(Basis.IDENTITY, knee), 0.078, 8, 12, kc)
		_limb_ab(t, knee, ankle, PackedFloat32Array([0.074, 0.076, 0.068, 0.062]), 16, kc, 0.12) # panturrilha
		# Anel de rolamento da coxa.
		var dir := (knee - hip).normalized()
		var ring := hip + dir * 0.13
		_seg(r, ring, ring + dir * 0.022, 0.097, 0.097, 18, SILVER)
		_seg(r, ring + dir * 0.008, ring + dir * 0.014, 0.1, 0.1, 18, Palette.BLUE)
		# Bota: conector do tornozelo, corpo branco e sola cinza.
		_seg(r, ankle + Vector3(0, 0.06, 0.03), ankle + Vector3(0, 0.03, 0.02), 0.07, 0.07, 14, SILVER)
		_seg(t, ankle + Vector3(0, 0.035, 0.02), ankle + Vector3(0, -0.04, 0), 0.068, 0.072, 12, kc)
		_ell(t, o + Vector3(s * 0.15, 0.36, -0.635), Basis.IDENTITY, Vector3(0.076, 0.068, 0.115), kc, 8, 14)
		_ell(t, o + Vector3(s * 0.15, 0.322, -0.635), Basis.IDENTITY, Vector3(0.08, 0.024, 0.12), SOLE, 6, 14)
	var mesh := t.commit(null, fabric)
	r.commit(mesh, _metal())
	body = MeshInstance3D.new()
	body.name = "Suit"
	body.mesh = mesh
	rig.add_child(body)


## Mochila de suporte de vida, módulo de controle no peito, mangueiras e emblemas UNIFEOB.
func _build_gear() -> void:
	var o := -ORIGIN
	var tc := o + Vector3(0, 0.7, 0.3)
	var tb := Basis(Vector3.RIGHT, TORSO_TILT)
	var tr := Vector3(0.19, 0.235, 0.165)
	var white := Color(0.95, 0.95, 0.94)
	var k := MeshKit.new()
	var dark := MeshKit.new()
	var lit := MeshKit.new()
	# Mochila (PLSS): bloco branco no alto das costas (acima do banco), tampa cinza, faixa azul e antena.
	var pb := o + Vector3(0, 0.8, 0.53)
	k.rounded_prism(Transform3D(Basis.IDENTITY, pb), 0.34, 0.13, 0.2, 0.035, 3, white, Color(0.82, 0.83, 0.85), true)
	k.box(Transform3D(Basis.IDENTITY, pb + Vector3(0, 0.035, 0.066)), Vector3(0.3, 0.016, 0.004), Palette.BLUE)
	for s: float in [-1.0, 1.0]:
		k.box(Transform3D(Basis.IDENTITY, pb + Vector3(s * 0.172, 0.1, 0.0)), Vector3(0.006, 0.17, 0.1), SILVER)  # trilhos laterais
	_seg(k, pb + Vector3(0.12, 0.2, 0.03), pb + Vector3(0.12, 0.3, 0.05), 0.006, 0.004, 6, SILVER)               # antena
	k.sphere(Transform3D(Basis.IDENTITY, pb + Vector3(0.12, 0.3, 0.05)), 0.009, 4, 8, Color(0.9, 0.15, 0.12))
	# Módulo de controle no peito (DCM): caixa clara, visor escuro, botões e chaves.
	var dcm := tc + tb * Vector3(0, -0.12, -0.14)
	k.rounded_prism(Transform3D(tb, dcm), 0.2, 0.07, 0.09, 0.015, 3, Color(0.86, 0.87, 0.88), Color(0.78, 0.8, 0.82), true)
	var fn := tb * Vector3(0, 0, -1)
	dark.box(Transform3D(tb, dcm + tb * Vector3(-0.04, 0.05, -0.036)), Vector3(0.08, 0.032, 0.003), Color(0.04, 0.05, 0.06))   # visor
	lit.box(Transform3D(tb, dcm + tb * Vector3(-0.04, 0.05, -0.038)), Vector3(0.064, 0.008, 0.002), Color(0.3, 1.0, 0.6))
	var btn: Array[Color] = [Color(0.9, 0.15, 0.12), Color(1.0, 0.75, 0.1), Palette.BLUE]
	for b in 3:
		k.sphere(Transform3D(Basis.IDENTITY, dcm + tb * Vector3(0.025 + 0.025 * b, 0.05, -0.036)), 0.009, 4, 8, btn[b])
	for b in 2:
		_seg(k, dcm + tb * Vector3(-0.06 + 0.12 * b, 0.09, -0.02), dcm + tb * Vector3(-0.06 + 0.12 * b, 0.11, -0.03), 0.012, 0.012, 10, Color(0.25, 0.26, 0.28))
	# Mangueiras do módulo até a mochila (curvando pelas laterais do tronco).
	for s: float in [-1.0, 1.0]:
		var a := dcm + tb * Vector3(s * 0.1, 0.02, 0.0)
		var m := o + Vector3(s * 0.22, 0.7, 0.24)
		var e := o + Vector3(s * 0.16, 0.84, 0.5)
		_seg(dark, a, m, 0.015, 0.015, 8, Color(0.16, 0.17, 0.19))
		_seg(dark, m, e, 0.015, 0.015, 8, Color(0.16, 0.17, 0.19))
		dark.sphere(Transform3D(Basis.IDENTITY, m), 0.015, 4, 8, Color(0.16, 0.17, 0.19))
	var mesh := k.commit(null, _mat(0.35, 0.4))
	dark.commit(mesh, _mat(0.6))
	lit.commit(mesh, _unshaded())
	# Emblemas UNIFEOB: redondo no peito esquerdo, plaqueta no peito direito, "bandeira" no ombro esquerdo
	# e logo na mochila (o que a câmera de perseguição vê).
	var em := MeshKit.new()
	_surf_decal(em, tc, tb, tr, 0.095, 0.1, 0.048, 0.048)
	em.commit(mesh, _decal_mat(emblem_texture()))
	var fl := MeshKit.new()
	_surf_decal(fl, tc, tb, tr, -0.095, 0.1, 0.05, 0.03)
	var shb := Basis(Vector3(0, 0, -1), Vector3.UP, Vector3.RIGHT)   # -Z local = para fora do ombro esquerdo
	_surf_decal(fl, o + Vector3(-SHOULDER.x, SHOULDER.y, SHOULDER.z), shb, Vector3(0.085, 0.085, 0.085), 0.0, -0.01, 0.045, 0.028)
	fl.commit(mesh, _decal_mat(flag_texture()))
	var wd := MeshKit.new()
	_flat_decal(wd, pb + Vector3(0, 0.12, 0.0665), Vector3(0.13, 0, 0), Vector3(0, 0.03, 0))
	wd.commit(mesh, _decal_mat(wordmark_texture()))
	var mi := MeshInstance3D.new()
	mi.name = "Gear"
	mi.mesh = mesh
	body.add_child(mi)


# ------------------------------------------------------------------ capacete

func _build_astro_helmet() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = HEAD_PIVOT - ORIGIN
	rig.add_child(head)
	var hc := HELMET_C
	var hr := ASTRO_HELMET_R
	var white := Color(0.95, 0.95, 0.94)
	var k := MeshKit.new()
	var shell_paint := func(d: Vector3) -> Color:
		if d.y < -0.86:
			return Color(0.2, 0.21, 0.23)   # borda interna junto ao anel
		return white
	_ell_paint(k, hc, Basis.IDENTITY, hr, 32, 56, shell_paint)
	# Dobradiças da viseira.
	for s: float in [-1.0, 1.0]:
		var hp := hc + Vector3(s * hr.x * 0.93, 0.02, 0.03)
		_seg(k, hp, hp + Vector3(s * 0.02, 0, 0), 0.04, 0.036, 16, Color(0.86, 0.87, 0.88))
		_seg(k, hp + Vector3(s * 0.02, 0, 0), hp + Vector3(s * 0.026, 0, 0), 0.022, 0.018, 12, SILVER)
	var mesh := k.commit(null, _mat(0.22, 1.0))
	# Anel de pescoço azul com borda prata.
	var ring := MeshKit.new()
	_ell(ring, hc + Vector3(0, -hr.y * 0.93, 0.01), Basis.IDENTITY, Vector3(0.2, 0.035, 0.2), Palette.BLUE, 6, 24)
	_ell(ring, hc + Vector3(0, -hr.y * 0.93 - 0.03, 0.01), Basis.IDENTITY, Vector3(0.19, 0.015, 0.19), SILVER, 4, 24)
	ring.commit(mesh, _metal())
	# Viseira dourada: calota sobre a frente, mais saliente no meio, com moldura cinza.
	var v := MeshKit.new()
	var az_max := 1.18
	var el_min := -0.5
	var el_max := 0.42
	var cols := MeshKit.seg_count(28)
	var rows := MeshKit.seg_count(12)
	var vdir := func(az: float, el: float) -> Vector3:
		return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	for rr in rows + 1:
		var fv := float(rr) / float(rows)
		var el := lerpf(el_min, el_max, fv)
		for c in cols + 1:
			var fu := float(c) / float(cols)
			var d: Vector3 = vdir.call(lerpf(-az_max, az_max, fu), el)
			var edge := minf(minf(fu, 1.0 - fu) * 4.0, minf(fv, 1.0 - fv) * 3.0)
			var bulge := 1.012 + 0.024 * smoothstep(0.0, 1.0, edge)
			var col := Color(0.78, 0.53, 0.16).lerp(Color(1.0, 0.86, 0.52), clampf(fv * 1.2 - 0.2, 0.0, 1.0))
			v.add_vertex(hc + d * hr * bulge, Vector3(d.x / hr.x, d.y / hr.y, d.z / hr.z).normalized(), Vector2(fu, fv), col)
	for rr in rows:
		for c in cols:
			var a0 := rr * (cols + 1) + c
			v.tri(a0, a0 + 1, a0 + cols + 1)
			v.tri(a0 + 1, a0 + cols + 2, a0 + cols + 1)
	var vmat := StandardMaterial3D.new()
	vmat.vertex_color_use_as_albedo = true
	vmat.roughness = 0.05
	vmat.metallic = 0.85
	vmat.clearcoat_enabled = true
	vmat.clearcoat = 1.0
	vmat.clearcoat_roughness = 0.0
	vmat.rim_enabled = true
	vmat.rim = 0.4
	vmat.rim_tint = 0.8
	vmat.emission_enabled = true   # lê dourado mesmo sem céu refletido
	vmat.emission = Color(0.5, 0.32, 0.08)
	vmat.emission_energy_multiplier = 0.4
	vmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	v.commit(mesh, vmat)
	var frame := MeshKit.new()
	var fc := Color(0.8, 0.81, 0.83)
	var pts: Array[Vector3] = []
	var steps := 24
	for i in steps + 1:
		pts.append(vdir.call(lerpf(-az_max, az_max, float(i) / steps), el_max))
	for i in range(1, 9):
		pts.append(vdir.call(az_max, lerpf(el_max, el_min, float(i) / 8)))
	for i in range(1, steps + 1):
		pts.append(vdir.call(lerpf(az_max, -az_max, float(i) / steps), el_min))
	for i in range(1, 9):
		pts.append(vdir.call(-az_max, lerpf(el_min, el_max, float(i) / 8)))
	for i in pts.size() - 1:
		var a: Vector3 = hc + pts[i] * hr * 1.012
		var b: Vector3 = hc + pts[i + 1] * hr * 1.012
		_seg(frame, a, b, 0.012, 0.012, 8, fc)
		frame.sphere(Transform3D(Basis.IDENTITY, b), 0.012, 4, 8, fc)
	frame.commit(mesh, _mat(0.3, 0.6))
	# Reflexos na viseira.
	var glint := MeshKit.new()
	for g: Array in [[-0.5, 0.22, 0.035, 0.007], [-0.36, 0.27, 0.014, 0.005], [0.55, -0.3, 0.022, 0.004]]:
		var gd: Vector3 = vdir.call(float(g[0]), float(g[1]))
		var gp := hc + gd * hr * 1.045
		_ell(glint, gp, Basis.looking_at(-gd, Vector3.UP), Vector3(g[2], g[3], 0.002), Color(1.0, 0.98, 0.9), 6, 10)
	glint.commit(mesh, _unshaded())
	# Luzes de EVA nas laterais: carcaça branca, duas lentes e a câmera.
	var lamp := MeshKit.new()
	var lens := MeshKit.new()
	for s: float in [-1.0, 1.0]:
		var p := hc + Vector3(s * 0.225, 0.165, 0.02)
		lamp.rounded_prism(Transform3D(Basis.IDENTITY, p - Vector3(0, 0.035, 0)), 0.065, 0.17, 0.07, 0.02, 3, Color(0.9, 0.9, 0.9), Color(0.82, 0.83, 0.84), true)
		_seg(lamp, p + Vector3(0, -0.03, 0.05), hc + Vector3(s * 0.27, 0.08, 0.08), 0.012, 0.012, 8, SILVER)   # haste
		for j in 2:
			var lp := p + Vector3(s * (0.014 - 0.028 * j), 0.0, -0.087)
			_ell(lens, lp, Basis.IDENTITY, Vector3(0.012, 0.012, 0.004), Color(1.0, 0.97, 0.86), 4, 10)
		_seg(lamp, p + Vector3(0, 0.035, -0.04), p + Vector3(0, 0.035, -0.09), 0.014, 0.014, 10, Color(0.15, 0.16, 0.18))  # câmera
	lamp.commit(mesh, _mat(0.35, 0.3))
	lens.commit(mesh, _unshaded())
	# Logo UNIFEOB na nuca (visto pela câmera de perseguição).
	var lg := MeshKit.new()
	_surf_decal(lg, hc, Basis(Vector3.UP, PI), hr, 0.0, 0.1, 0.11, 0.025)
	lg.commit(mesh, _decal_mat(wordmark_texture()))
	var mi := MeshInstance3D.new()
	mi.name = "HeadMesh"
	mi.mesh = mesh
	head.add_child(mi)


# ------------------------------------------------------------------ braços

## Braços volumosos: anel de rolamento azul/prata perto do ombro, conector de punho e luvas brancas.
func _build_astro_arms(kc: Color, fabric: Material, glove_mat: Material) -> void:
	var gl: Color = scheme["glove"]
	var ua := MeshKit.new()
	_limb(ua, Transform3D.IDENTITY, L1, PackedFloat32Array([0.066, 0.068, 0.062, 0.056]), 16, kc, 0.12)
	ua.sphere(Transform3D(Basis.IDENTITY, Vector3(0, L1, 0)), 0.058, 6, 12, kc)
	var ua_mesh := ua.commit(null, fabric)
	var uar := MeshKit.new()
	uar.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), 0.075, 0.075, 0.024, 18, SILVER)
	uar.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.058, 0)), 0.078, 0.078, 0.008, 18, Palette.BLUE)
	uar.commit(ua_mesh, _metal())
	var fa := MeshKit.new()
	_limb(fa, Transform3D.IDENTITY, L2 - 0.07, PackedFloat32Array([0.057, 0.059, 0.054, 0.05]), 16, kc, 0.12)
	var fa_mesh := fa.commit(null, fabric)
	var wr := MeshKit.new()
	wr.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, L2 - 0.1, 0)), 0.06, 0.06, 0.03, 16, SILVER)       # conector do punho
	wr.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, L2 - 0.088, 0)), 0.063, 0.063, 0.01, 16, Palette.BLUE)
	wr.commit(fa_mesh, _metal())
	var cuff := MeshKit.new()
	cuff.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, L2 - 0.07, 0)), 0.05, 0.055, 0.07, 14, gl)       # punho da luva
	cuff.commit(fa_mesh, glove_mat)
	var finger := MeshKit.new()
	finger.sphere(Transform3D.IDENTITY, 0.015, 5, 8, gl)
	finger.cylinder(Transform3D.IDENTITY, 0.0142, 0.013, 0.05, 8, gl, false)
	finger.sphere(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), 0.0135, 6, 10, Color(0.55, 0.57, 0.6))   # ponta de borracha
	var finger_mesh := finger.commit(null, glove_mat)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var suffix := "L" if i == 0 else "R"
		var a := MeshInstance3D.new()
		a.name = "Arm" + suffix
		a.mesh = ua_mesh
		rig.add_child(a)
		arms.append(a)
		var f := MeshInstance3D.new()
		f.name = "Forearm" + suffix
		f.mesh = fa_mesh
		rig.add_child(f)
		forearms.append(f)
		# Luva: palma, anelar e mínimo dobrados, polegar e reforço cinza no dorso.
		var h := MeshKit.new()
		_ell(h, Vector3(0, 0.045, 0), Basis.IDENTITY, Vector3(0.045, 0.05, 0.028), gl, 8, 14)
		_ell(h, Vector3(0, 0.05, 0.024), Basis.IDENTITY, Vector3(0.034, 0.03, 0.008), Color(0.6, 0.62, 0.65), 6, 10)
		for j in 2:
			var fx := s * (0.012 + 0.02 * float(j))
			_ell(h, Vector3(fx, 0.08, -0.016), Basis(Vector3.RIGHT, -0.9), Vector3(0.013, 0.023, 0.016), gl, 6, 8)
		var tb := Vector3(-s * 0.033, 0.03, -0.012)
		var tt := Vector3(-s * 0.019, 0.072, -0.038)
		_seg(h, tb, tt, 0.016, 0.014, 8, gl)
		h.sphere(Transform3D(Basis.IDENTITY, tt), 0.0155, 5, 8, Color(0.55, 0.57, 0.6))
		var hand := MeshInstance3D.new()
		hand.name = "Hand" + suffix
		hand.mesh = h.commit(null, glove_mat)
		rig.add_child(hand)
		hands.append(hand)
		for j in 2:
			var fi := MeshInstance3D.new()
			fi.name = ("Index" if j == 0 else "Middle") + suffix
			fi.mesh = finger_mesh
			fi.position = Vector3(-s * 0.012 if j == 0 else s * 0.01, 0.086, 0.0)
			hand.add_child(fi)
			fingers[i].append(fi)


# ------------------------------------------------------------------ emblemas UNIFEOB (texturas geradas uma vez)

## Logo "unifeob." rasterizado na largura `w` (px); `tint` com alfa > 0 pinta tudo numa cor só.
static func _logo_image(w: float, tint: Color = Color(0, 0, 0, 0)) -> Image:
	var svg := FileAccess.get_file_as_string(UiKit.LOGO_PATH)
	var logo := Image.new()
	if svg == "" or logo.load_svg_from_string(svg, w / 141.0) != OK:
		return null
	logo.convert(Image.FORMAT_RGBA8)
	if tint.a > 0.0:
		for y in logo.get_height():
			for x in logo.get_width():
				logo.set_pixel(x, y, Color(tint, logo.get_pixel(x, y).a))
	return logo


static func _blit(img: Image, logo: Image, center: Vector2i) -> void:
	if logo == null:
		return
	var off := center - Vector2i(logo.get_width(), logo.get_height()) / 2
	for y in logo.get_height():
		for x in logo.get_width():
			var src := logo.get_pixel(x, y)
			var px := off + Vector2i(x, y)
			if src.a > 0.0 and px.x >= 0 and px.y >= 0 and px.x < img.get_width() and px.y < img.get_height():
				var dst := img.get_pixelv(px)
				img.set_pixelv(px, Color(dst.lerp(src, src.a), maxf(dst.a, src.a)))


static func _finish(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Emblema redondo UNIFEOB (no lugar do emblema da NASA): disco azul com borda branca, órbita magenta,
## estrelinhas e o logo em branco.
static func emblem_texture() -> Texture2D:
	if _emblem_tex != null:
		return _emblem_tex
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var stars: Array[Vector2] = [Vector2(-0.5, -0.5), Vector2(-0.15, -0.7), Vector2(0.4, -0.58), Vector2(0.62, -0.2),
		Vector2(-0.66, 0.2), Vector2(0.2, 0.64), Vector2(-0.38, 0.55), Vector2(0.6, 0.4)]
	for y in n:
		for x in n:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(n) * 2.0 - Vector2.ONE
			var r := p.length()
			var c := Color(1, 1, 1, clampf((1.0 - r) * n * 0.5, 0.0, 1.0))
			if r < 0.88:
				c = Palette.BLUE
				if absf(r - 0.8) < 0.012:
					c = Color(1, 1, 1)
				# Órbita inclinada atravessando o disco.
				var q := p.rotated(-0.35)
				var e := Vector2(q.x / 0.72, q.y / 0.26).length()
				if absf(e - 1.0) < 0.07 and r < 0.78:
					c = Palette.MAGENTA
				for s in stars:
					if p.distance_to(s) < 0.028:
						c = Color.WHITE
			img.set_pixel(x, y, c)
	_blit(img, _logo_image(0.66 * n, Color.WHITE), Vector2i(n / 2, n / 2))
	_emblem_tex = _finish(img)
	return _emblem_tex


## "Bandeira" UNIFEOB (no lugar da bandeira do ombro): retângulo branco com borda azul e o logo original.
static func flag_texture() -> Texture2D:
	if _flag_tex != null:
		return _flag_tex
	var w := 320
	var h := 192
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Palette.BLUE)
	img.fill_rect(Rect2i(14, 14, w - 28, h - 28), Color(1, 1, 1))
	img.fill_rect(Rect2i(14, h - 44, w - 28, 12), Palette.MAGENTA)
	_blit(img, _logo_image(0.78 * w), Vector2i(w / 2, int(h * 0.44)))
	_flag_tex = _finish(img)
	return _flag_tex


## Logo "unifeob." sobre fundo transparente (mochila e capacete).
static func wordmark_texture() -> Texture2D:
	if _word_tex != null:
		return _word_tex
	var w := 512
	var h := 116
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	_blit(img, _logo_image(w * 0.96), Vector2i(w / 2, h / 2))
	_word_tex = _finish(img)
	return _word_tex
