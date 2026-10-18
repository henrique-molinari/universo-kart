class_name PilotDriver
extends AlienDriver
## Piloto humano procedural (MeshKit), modelo próprio e reaproveitável: cada esquema de cores (SCHEMES)
## é um piloto escolhível (ids em Characters, a partir de Characters.FIRST_PILOT).
## Visual: macacão de corrida na cor do capacete (faixas laterais, dragonas, zíper, patches no peito),
## colar HANS, capacete integral pintado (faixa central com filetes, barrado inferior), viseira bolha
## espelhada com reflexo, dobradiças e aerofólio, luvas com punho longo e botas.
## Herda de AlienDriver só o rig/IK/interface (Rig -> Body/Head/Arm/Forearm/Hand -> Index/Middle).
## Comemoração própria: socos no ar alternados (mão direita apontando o "nº 1"), quique no banco,
## capacete balançando e chuva de confete nas cores do piloto. Derrota: mãos no capacete, cabeça baixa.

## helmet = casco, suit = macacão (mesma família do capacete), stripe = faixa central/barrado, accent = filetes/detalhes, visor = tom da viseira,
## glove = luvas/botas; rainbow = casco em faixas de arco-íris.
const SCHEMES: Array[Dictionary] = [
	{"helmet": Color(0.88, 0.08, 0.1), "suit": Color(0.8, 0.07, 0.09), "stripe": Color(1.0, 0.84, 0.08), "accent": Color(0.97, 0.97, 0.97),
		"visor": Color(0.22, 0.15, 0.02), "glove": Color(0.1, 0.1, 0.11), "rainbow": false},
	{"helmet": Color(0.08, 0.36, 0.9), "suit": Color(0.07, 0.32, 0.82), "stripe": Color(0.15, 0.88, 1.0), "accent": Color(0.97, 0.97, 0.97),
		"visor": Color(0.02, 0.08, 0.22), "glove": Color(0.06, 0.2, 0.55), "rainbow": false},
	{"helmet": Color(0.05, 0.55, 0.28), "suit": Color(0.05, 0.5, 0.25), "stripe": Color(0.07, 0.07, 0.08), "accent": Color(1.0, 0.78, 0.18),
		"visor": Color(0.02, 0.14, 0.07), "glove": Color(0.07, 0.07, 0.08), "rainbow": false},
	{"helmet": Color(0.97, 0.97, 0.97), "suit": Color(0.95, 0.95, 0.95), "stripe": Color(0.55, 0.2, 0.85), "accent": Color(0.97, 0.97, 0.97),
		"visor": Color(0.12, 0.04, 0.16), "glove": Color(0.55, 0.2, 0.85), "rainbow": true},
]
const RAINBOW: Array[Color] = [
	Color(0.92, 0.12, 0.15), Color(1.0, 0.55, 0.05), Color(1.0, 0.88, 0.1),
	Color(0.15, 0.75, 0.3), Color(0.1, 0.45, 0.95), Color(0.55, 0.2, 0.85),
]
const HELMET_SHADER := preload("res://assets/shaders/helmet_paint.gdshader")
const SUIT_SHADER := preload("res://assets/shaders/suit_paint.gdshader")
const HELMET_C := Vector3(0, 0.3, 0.0)        ## centro do capacete em relação ao pivô do pescoço
const HELMET_R := Vector3(0.28, 0.29, 0.305)

var scheme: Dictionary = {}


static func scheme_of(char_id: int) -> Dictionary:
	return SCHEMES[clampi(char_id - Characters.FIRST_PILOT, 0, SCHEMES.size() - 1)]


# ------------------------------------------------------------------ construção

func build(char_id: int, suit: Color) -> void:
	character = clampi(char_id, Characters.FIRST_PILOT, Characters.count() - 1)
	scheme = scheme_of(character)
	name = "Driver"
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var fabric := _fabric_mat()
	var glove_mat := _mat(0.48, 0.15)
	_build_suit(suit, fabric)
	_build_helmet()
	_build_pilot_arms(suit, fabric, glove_mat)


func _build_suit(kc: Color, fabric: Material) -> void:
	var o := -ORIGIN
	var tb := Basis(Vector3.RIGHT, TORSO_TILT)
	var stripe: Color = scheme["stripe"]
	var rainbow: bool = scheme["rainbow"]
	var t := MeshKit.new()
	# Quadril primeiro (o 1º vértice tem exatamente a cor do traje).
	_ell(t, o + Vector3(0, 0.5, 0.32), Basis.IDENTITY, Vector3(0.17, 0.12, 0.155), kc, 10, 18, 0.25)
	_ell(t, o + Vector3(0, 0.56, 0.31), Basis.IDENTITY, Vector3(0.18, 0.033, 0.16), Color(0.08, 0.08, 0.09), 6, 20)  # cinto
	_ell(t, o + Vector3(0, 0.555, 0.15), Basis(Vector3.RIGHT, -0.15), Vector3(0.05, 0.03, 0.012), Color(0.75, 0.76, 0.78), 4, 10)  # fivela
	for s: float in [-1.0, 1.0]:
		var sh := o + Vector3(s * SHOULDER.x, SHOULDER.y, SHOULDER.z)
		t.sphere(Transform3D(Basis.IDENTITY, sh), 0.068, 8, 12, kc)
		_ell(t, sh + Vector3(-s * 0.02, 0.05, 0.0), Basis(Vector3.BACK, s * 0.35), Vector3(0.075, 0.016, 0.045), stripe, 6, 12)  # dragona
		var hip := o + Vector3(s * 0.09, 0.5, 0.28)
		var knee := o + Vector3(s * 0.16, 0.645, -0.36)
		var ankle := o + Vector3(s * 0.15, 0.42, -0.56)
		_limb_ab(t, hip, knee, PackedFloat32Array([0.075, 0.08, 0.075, 0.066]), 14, kc, 0.09)
		_seg(t, hip + Vector3(s * 0.062, 0.0, 0.0), knee + Vector3(s * 0.058, 0.0, 0.0), 0.016, 0.015, 6, stripe)  # faixa da perna
		t.sphere(Transform3D(Basis.IDENTITY, knee), 0.07, 8, 12, kc.darkened(0.12))
		_limb_ab(t, knee, ankle, PackedFloat32Array([0.063, 0.066, 0.058, 0.052]), 14, kc, 0.09)
		# Bota de piloto: cano, biqueira e sola.
		var gl: Color = scheme["glove"]
		_seg(t, ankle + Vector3(0, 0.05, 0.03), ankle + Vector3(0, -0.04, 0), 0.062, 0.066, 12, gl)
		_ell(t, o + Vector3(s * 0.15, 0.365, -0.63), Basis.IDENTITY, Vector3(0.066, 0.06, 0.1), gl, 8, 12)
		_ell(t, o + Vector3(s * 0.15, 0.33, -0.63), Basis.IDENTITY, Vector3(0.07, 0.022, 0.105), Color(0.95, 0.95, 0.95), 6, 12)
	var mesh := t.commit(null, fabric)
	# Tronco: faixas laterais (filete + faixa), zíper e patches no peito, pintados por pixel (SUIT_SHADER).
	var torso_c := o + Vector3(0, 0.69, 0.3)
	var torso_r := Vector3(0.175, 0.225, 0.15)
	var torso := MeshKit.new()
	_ell(torso, torso_c, tb, torso_r, kc, 24, 40)
	var tp := ShaderMaterial.new()
	tp.shader = SUIT_SHADER
	tp.set_shader_parameter(&"center", torso_c)
	tp.set_shader_parameter(&"to_local", tb.inverse())
	tp.set_shader_parameter(&"radii", torso_r)
	tp.set_shader_parameter(&"suit", Vector3(kc.r, kc.g, kc.b))
	for key: String in ["stripe", "accent"]:
		var c: Color = scheme[key]
		tp.set_shader_parameter(StringName(key), Vector3(c.r, c.g, c.b))
	tp.set_shader_parameter(&"rainbow", rainbow)
	var rb := PackedVector3Array()
	for c in RAINBOW:
		rb.append(Vector3(c.r, c.g, c.b))
	tp.set_shader_parameter(&"rainbow_colors", rb)
	torso.commit(mesh, tp)
	# Colar HANS (preto fosco) e pescoço com balaclava.
	var h := MeshKit.new()
	_ell(h, o + Vector3(0, 0.895, 0.29), Basis(Vector3.RIGHT, -0.15), Vector3(0.15, 0.04, 0.13), Color(0.07, 0.07, 0.08), 8, 20)
	for s: float in [-1.0, 1.0]:
		_ell(h, o + Vector3(s * 0.06, 0.93, 0.36), Basis.IDENTITY, Vector3(0.025, 0.035, 0.02), Color(0.07, 0.07, 0.08), 6, 10)
	_seg(h, o + Vector3(0, 0.86, 0.26), o + HEAD_PIVOT + Vector3(0, 0.1, 0), 0.055, 0.05, 12, Color(0.12, 0.12, 0.13))
	h.commit(mesh, _mat(0.7))
	body = MeshInstance3D.new()
	body.name = "Suit"
	body.mesh = mesh
	rig.add_child(body)


func _build_helmet() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = HEAD_PIVOT - ORIGIN
	rig.add_child(head)
	var hc := HELMET_C
	var hr := HELMET_R
	var shell := MeshKit.new()
	_ell(shell, hc, Basis.IDENTITY, hr, Color.WHITE, 32, 56)
	var paint := ShaderMaterial.new()
	paint.shader = HELMET_SHADER
	paint.set_shader_parameter(&"center", hc)
	paint.set_shader_parameter(&"radii", hr)
	for key: String in ["helmet", "stripe", "accent"]:
		var c: Color = scheme[key]
		paint.set_shader_parameter(StringName(key), Vector3(c.r, c.g, c.b))
	paint.set_shader_parameter(&"rainbow", scheme["rainbow"])
	var rb := PackedVector3Array()
	for c in RAINBOW:
		rb.append(Vector3(c.r, c.g, c.b))
	paint.set_shader_parameter(&"rainbow_colors", rb)
	var mesh := shell.commit(null, paint)
	var k := MeshKit.new()
	# Abertura da viseira (interior escuro, logo atrás da bolha).
	_ell(k, hc + Vector3(0, -0.01, -0.17), Basis.IDENTITY, Vector3(0.205, 0.085, 0.115), Color(0.03, 0.03, 0.035), 10, 24)
	var accent: Color = scheme["accent"]
	var stripe: Color = scheme["stripe"]
	for s: float in [-1.0, 1.0]:
		# Dobradiça da viseira + respiros do queixo.
		var hp := hc + Vector3(s * hr.x * 0.93, -0.03, -0.06)
		_seg(k, hp, hp + Vector3(s * 0.035, 0, 0), 0.036, 0.032, 16, accent)
		_seg(k, hp + Vector3(s * 0.035, 0, 0), hp + Vector3(s * 0.042, 0, 0), 0.02, 0.016, 12, Color(0.3, 0.3, 0.32))
		var vd := Vector3(s * 0.16, -0.62, -0.77).normalized()
		_ell(k, hc + vd * hr * 0.99, Basis.looking_at(-vd, Vector3.UP), Vector3(0.026, 0.012, 0.012), Color(0.05, 0.05, 0.06), 4, 10)
	# Aerofólio na nuca.
	_ell(k, hc + Vector3(0, 0.19, 0.25), Basis(Vector3.RIGHT, 0.85), Vector3(0.14, 0.022, 0.07), stripe, 8, 18)
	for s: float in [-1.0, 1.0]:
		_ell(k, hc + Vector3(s * 0.13, 0.19, 0.25), Basis(Vector3.RIGHT, 0.85), Vector3(0.012, 0.04, 0.07), accent, 4, 10)
	k.commit(mesh, _mat(0.16, 1.0))
	# Viseira bolha: patch sobre a frente, mais saliente no meio (bordas encostam no casco).
	var v := MeshKit.new()
	var tint: Color = scheme["visor"]
	var cols := MeshKit.seg_count(36)
	var rows := MeshKit.seg_count(18)
	var base_i := 0
	for r in rows + 1:
		var fv := float(r) / float(rows)
		var el := lerpf(-0.36, 0.26, fv)
		var yy := absf(fv * 2.0 - 1.0)
		var half_w := 1.12 * (0.74 + 0.26 * sqrt(maxf(1.0 - pow(yy, 3.0), 0.0)))  # cantos arredondados
		for c in cols + 1:
			var fu := float(c) / float(cols)
			var az := lerpf(-half_w, half_w, fu)
			var d := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
			var edge := minf(minf(fu, 1.0 - fu) * 4.0, minf(fv, 1.0 - fv) * 3.0)
			var bulge := 1.006 + 0.04 * smoothstep(0.0, 1.0, edge)
			var col := tint.lerp(Color(0.6, 0.62, 0.66), clampf(fv - 0.55, 0.0, 1.0) * 0.5)
			v.add_vertex(hc + d * hr * bulge, Vector3(d.x / hr.x, d.y / hr.y, d.z / hr.z).normalized(), Vector2(fu, fv), col)
	for r in rows:
		for c in cols:
			var a0 := base_i + r * (cols + 1) + c
			v.tri(a0, a0 + 1, a0 + cols + 1)
			v.tri(a0 + 1, a0 + cols + 2, a0 + cols + 1)
	var vmat := StandardMaterial3D.new()
	vmat.vertex_color_use_as_albedo = true
	vmat.roughness = 0.04
	vmat.metallic = 0.7
	vmat.clearcoat_enabled = true
	vmat.clearcoat = 1.0
	vmat.clearcoat_roughness = 0.0
	vmat.rim_enabled = true
	vmat.rim = 0.5
	vmat.rim_tint = 0.3
	vmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	v.commit(mesh, vmat)
	# Reflexos da viseira.
	var glint := MeshKit.new()
	for band: Array in [[0.15, -0.85, -0.15, 0.007], [0.07, -0.8, -0.5, 0.0035]]:
		var prev := Vector3.ZERO
		var n := 32
		for j in n + 1:
			var f := float(j) / float(n)
			var az := lerpf(float(band[1]), float(band[2]), f)
			var el := float(band[0])
			var gd := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
			var gp := hc + gd * hr * 1.047
			if j > 0:
				var r := float(band[3]) * sin((f - 0.5 / float(n)) * PI)  # afina nas pontas
				_seg(glint, prev, gp, r, r, 8, Color.WHITE)
				glint.sphere(Transform3D(Basis.IDENTITY, gp), r, 4, 8, Color.WHITE)
			prev = gp
	var glint_mat := StandardMaterial3D.new()
	glint_mat.albedo_color = Color.BLACK
	glint_mat.emission_enabled = true
	glint_mat.emission = Color.WHITE
	glint_mat.emission_energy_multiplier = 1.4
	glint.commit(mesh, glint_mat)
	var mi := MeshInstance3D.new()
	mi.name = "HeadMesh"
	mi.mesh = mesh
	head.add_child(mi)


func _build_pilot_arms(kc: Color, fabric: Material, glove_mat: Material) -> void:
	var stripe: Color = scheme["stripe"]
	var gl: Color = scheme["glove"]
	var accent: Color = scheme["accent"]
	var ua := MeshKit.new()
	_limb(ua, Transform3D.IDENTITY, L1, PackedFloat32Array([0.055, 0.058, 0.053, 0.047]), 14, kc, 0.09)
	ua.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, L1 * 0.55, 0)), 0.0535, 0.0525, 0.028, 12, stripe)   # braçadeira
	ua.sphere(Transform3D(Basis.IDENTITY, Vector3(0, L1, 0)), 0.051, 6, 12, kc.darkened(0.1))
	var ua_mesh := ua.commit(null, fabric)
	var fa := MeshKit.new()
	_limb(fa, Transform3D.IDENTITY, L2 - 0.07, PackedFloat32Array([0.048, 0.05, 0.045, 0.042]), 14, kc, 0.09)
	var fa_mesh := fa.commit(null, fabric)
	var cuff := MeshKit.new()
	cuff.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, L2 - 0.085, 0)), 0.05, 0.06, 0.085, 14, gl)   # punho longo da luva
	cuff.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, L2 - 0.06, 0)), 0.0575, 0.0595, 0.016, 14, accent)
	cuff.commit(fa_mesh, glove_mat)
	var finger := MeshKit.new()
	finger.sphere(Transform3D.IDENTITY, 0.0135, 5, 8, gl)
	finger.cylinder(Transform3D.IDENTITY, 0.0128, 0.0118, 0.05, 8, gl, false)
	finger.sphere(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), 0.0122, 6, 10, gl)
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
		# Mão enluvada: palma, anelar e mínimo dobrados, polegar e reforço nos nós dos dedos.
		var h := MeshKit.new()
		_ell(h, Vector3(0, 0.045, 0), Basis.IDENTITY, Vector3(0.042, 0.048, 0.025), gl, 8, 14)
		_ell(h, Vector3(0, 0.06, 0.022), Basis.IDENTITY, Vector3(0.034, 0.02, 0.008), stripe, 6, 10)
		for j in 2:
			var fx := s * (0.012 + 0.02 * float(j))
			_ell(h, Vector3(fx, 0.08, -0.016), Basis(Vector3.RIGHT, -0.9), Vector3(0.012, 0.022, 0.015), gl, 6, 8)
		var tb := Vector3(-s * 0.032, 0.03, -0.012)
		var tt := Vector3(-s * 0.018, 0.072, -0.038)
		_seg(h, tb, tt, 0.015, 0.013, 8, gl)
		h.sphere(Transform3D(Basis.IDENTITY, tt), 0.015, 5, 8, gl)
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


# ------------------------------------------------------------------ comemoração / animação

## Chuva de confete nas cores do piloto.
func _make_fx() -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.name = "CelebrationFx"
	fx.amount = 60
	fx.lifetime = 2.4
	fx.position = HEAD_PIVOT - ORIGIN + Vector3(0, 0.75, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(0, -2.0, 0)
	pm.damping_min = 0.8
	pm.damping_max = 1.6
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var cs: Array[Color] = [scheme["helmet"], scheme["stripe"], scheme["accent"], Color(1.0, 0.82, 0.2), Color(0.2, 0.8, 1.0)]
	if scheme["rainbow"]:
		cs = RAINBOW.duplicate()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for j in cs.size():
		offs.append(float(j) / float(cs.size()))
		cols.append(cs[j])
	g.offsets = offs
	g.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	fx.process_material = pm
	var k := MeshKit.new()
	_ell(k, Vector3.ZERO, Basis.IDENTITY, Vector3(0.032, 0.018, 0.004), Color.WHITE, 2, 4)
	var mat := _unshaded()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	fx.draw_pass_1 = k.commit(null, mat)
	return fx


## Volante (IK nas pegas) / vitória (socos no ar alternados, direita apontando o "nº 1") /
## derrota (mãos no capacete, cabeça baixa).
func animate_rig(delta: float, steer: float, grip_l: Vector3, grip_r: Vector3) -> void:
	_t += delta
	_gesture = maxf(_gesture - delta, 0.0)
	var pw := _pose_weights(delta)
	var wd := pw.x
	var wv := pw.y
	var wl := pw.z
	var pump := _t * TAU * 1.15
	hop = absf(sin(pump)) * 0.075 * wv
	rig.position = Vector3(0, hop - 0.02 * wl, 0)
	rig.rotation = Vector3(-0.08 * wl + 0.012 * sin(_t * 1.5) * wl, 0.0, sin(pump * 0.5) * 0.05 * wv)
	var hd := Vector3(0.0, -steer * 0.22, steer * 0.05)
	var hv := Vector3(0.2 + 0.08 * sin(pump * 2.0), sin(_t * 2.3) * 0.22, sin(_t * 2.3) * 0.06)
	var hl := Vector3(-0.45 + 0.03 * sin(_t * 1.7), sin(_t * 1.4) * 0.07, 0.0)
	head.rotation = hd * wd + hv * wv + hl * wl
	head_pitch = head.rotation.x
	var grips: Array[Vector3] = [grip_l, grip_r]
	wrist_error = 0.0
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var fd := Vector3(-s * 0.35, -0.25, -1.0).normalized()
		var pd := Vector3(s, 0.3, 0.0).normalized()
		var wdr := grips[i] + pd * 0.03 - fd * 0.045
		var a := 0.5 + 0.5 * sin(pump + (PI if i == 1 else 0.0))
		var wvw := Vector3(s * lerpf(0.36, 0.28, a), lerpf(1.06, 1.32, a), lerpf(0.02, 0.12, a)) - ORIGIN
		var fv := Vector3(s * 0.15, 1.0, lerpf(-0.45, 0.0, a)).normalized()
		var wlw := Vector3(s * 0.34, 1.2, 0.12) - ORIGIN
		var fl := Vector3(-s * 0.35, 1.0, -0.15).normalized()
		var wrist := wdr * wd + wvw * wv + wlw * wl
		var fdir := (fd * wd + fv * wv + fl * wl).normalized()
		var back := (pd * wd + Vector3(0, 0, -1) * wv + Vector3(s, 0, 0) * wl).normalized()
		var gw := _apply_gesture(i, wrist, fdir)
		wrist_error = maxf(wrist_error, _solve_arm(i, s, gw[0], gw[1], back))
	v_amount = wv
	for i in 2:
		var index_curl := -1.55 * wd + (-1.6 if i == 0 else 0.0) * wv - 0.25 * wl
		var middle_curl := -1.55 * wd - 1.6 * wv - 0.25 * wl
		(fingers[i][0] as Node3D).basis = Basis(Vector3.RIGHT, index_curl)
		(fingers[i][1] as Node3D).basis = Basis(Vector3.RIGHT, middle_curl)
