class_name AlienDriver
extends Node3D
## Piloto ET procedural (MeshKit), fiel à referência (images/2.png): ET "chibi" com cabeça enorme em gota
## invertida, olhos pretos gigantes e reflexivos (com brilhos), pele com textura sutil (ruído na cor +
## normal map triplanar), sorriso pequeno, traje espacial na cor do kart com painel no peito (dois botões).
## Dois personagens:
##   0 "Visitante do Universo": masculino, pele verde, arcos das sobrancelhas e rugas na testa.
##   1 "Turista do Universo": feminina, pele rosa, cílios, laço vermelho de bolinhas, blush e lábios rosados.
## Articulado: Rig (pulinhos/postura) -> Body (traje, pernas, pescoço), Head (pivô no pescoço),
## ArmL/R (braço), ForearmL/R (antebraço), HandL/R (mão) -> IndexL/R e MiddleL/R (dedos do "V").
## Os braços usam IK analítico de 2 ossos até o alvo de cada pose (volante / paz e amor / mãos nos joelhos).
## Local: -Z = frente. A geometria é escrita em coordenadas do kart menos ORIGIN.

enum Character { VISITANTE, TURISTA }
enum Pose { DRIVE, VICTORY, DEFEAT }

const NAMES: Array[String] = ["Visitante do Universo", "Turista do Universo"]
const SKIN_COLORS: Array[Color] = [Color(0.34, 0.76, 0.13), Color(1.0, 0.42, 0.66)]
const LED_COLORS: Array[Color] = [Color(0.45, 1.0, 0.7), Color(1.0, 0.45, 0.85)]
const ORIGIN := Vector3(0, 0.5, 0.3)          ## posição deste nó no kart (pivô da inclinação)
const HEAD_PIVOT := Vector3(0, 0.96, 0.25)    ## pescoço (coordenadas do kart)
const HEAD_CENTER := Vector3(0, 0.36, -0.01)  ## centro da cabeça em relação ao pivô
const HEAD_R := Vector3(0.33, 0.34, 0.29)
const SHOULDER := Vector3(0.17, 0.83, 0.2)    ## ombro direito (x espelhado no esquerdo)
const L1 := 0.27                              ## braço
const L2 := 0.27                              ## antebraço
const TORSO_TILT := -0.22
const SKIN_NORMAL := preload("res://assets/materials/noise_grain_normal.tres")

var character := 0
var pose: Pose = Pose.DRIVE
var rig: Node3D
var body: MeshInstance3D
var head: Node3D
var arms: Array[Node3D] = []
var forearms: Array[Node3D] = []
var hands: Array[Node3D] = []
var fingers: Array = [[], []]   ## por lado: [indicador, médio]
var v_amount := 0.0              ## 0 = dedos no volante, 1 = "V" aberto
var hop := 0.0                   ## altura atual do pulinho
var head_pitch := 0.0
var wrist_error := 0.0           ## distância do punho ao alvo (IK); testes
var _w := Vector3(1, 0, 0)       ## pesos das poses (volante, vitória, derrota)
var _t := 0.0
var _fx: GPUParticles3D


# ------------------------------------------------------------------ materiais

static func _mat(rough: float, clearcoat: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	if clearcoat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = clearcoat
		m.clearcoat_roughness = 0.25
	return m


static func _skin_mat() -> StandardMaterial3D:
	var m := _mat(0.46, 0.35)
	m.normal_enabled = true
	m.normal_texture = SKIN_NORMAL
	m.normal_scale = 0.28
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(7, 7, 7)
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.6
	return m


static func _fabric_mat() -> StandardMaterial3D:
	var m := _mat(0.62)
	m.normal_enabled = true
	m.normal_texture = SKIN_NORMAL
	m.normal_scale = 0.45
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(14, 14, 14)
	m.rim_enabled = true
	m.rim = 0.2
	return m


static func _unshaded() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# ------------------------------------------------------------------ geometria auxiliar

static func _basis_y(d: Vector3, ref: Vector3 = Vector3.FORWARD) -> Basis:
	var y := d.normalized()
	var r := ref if absf(y.dot(ref.normalized())) < 0.95 else Vector3.RIGHT
	var x := r.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _seg(k: MeshKit, a: Vector3, b: Vector3, r0: float, r1: float, segs: int, c: Color) -> void:
	k.cylinder(Transform3D(_basis_y(b - a), a), r0, r1, a.distance_to(b), segs, c)


## Elipsoide com eixos (x, y, z) e semi-eixos `sc`.
static func _ell(k: MeshKit, center: Vector3, b: Basis, sc: Vector3, c: Color, rings: int = 10, segs: int = 16, ao: float = 0.0) -> void:
	k.sphere(Transform3D(b * Basis.from_scale(sc), center), 1.0, rings, segs, c, ao)


## Largura da cabeça em função da altura (gota invertida: crânio largo, queixo estreito).
static func _head_w(y: float) -> float:
	return lerpf(0.4, 1.0, smoothstep(-1.05, 0.4, y))


## Ponto da superfície da cabeça na direção unitária `d` (em relação a HEAD_CENTER).
static func _head_pt(d: Vector3) -> Vector3:
	var w := _head_w(d.y)
	var yk := 1.12 if d.y < 0.0 else 1.0
	return Vector3(d.x * HEAD_R.x * w, d.y * HEAD_R.y * yk, d.z * HEAD_R.z * w)


static func _head_n(d: Vector3) -> Vector3:
	d = d.normalized()
	var t1 := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var t2 := d.cross(t1).normalized()
	var e := 0.01
	var a := _head_pt((d + t1 * e).normalized()) - _head_pt((d - t1 * e).normalized())
	var b := _head_pt((d + t2 * e).normalized()) - _head_pt((d - t2 * e).normalized())
	var n := a.cross(b).normalized()
	return n if n.dot(_head_pt(d)) >= 0.0 else -n


## Base tangente à cabeça no ponto `d`: z = normal, x ~ direita.
static func _face_basis(d: Vector3, roll: float = 0.0) -> Basis:
	var n := _head_n(d)
	var x := (Vector3.RIGHT - n * n.x).normalized()
	var y := n.cross(x)
	if roll != 0.0:
		x = x.rotated(n, roll)
		y = y.rotated(n, roll)
	return Basis(x, y, n)


# ------------------------------------------------------------------ construção

func build(char_id: int, suit: Color) -> void:
	character = clampi(char_id, 0, 1)
	name = "Driver"
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	var skin := SKIN_COLORS[character]
	var skin_mat := _skin_mat()
	var fabric := _fabric_mat()
	_build_body(suit, skin, skin_mat, fabric)
	_build_head(skin, skin_mat)
	_build_arms(suit, skin, skin_mat, fabric)


func _build_body(kc: Color, skin: Color, skin_mat: Material, fabric: Material) -> void:
	var o := -ORIGIN
	var tb := Basis(Vector3.RIGHT, TORSO_TILT)
	var t := MeshKit.new()
	# Tronco primeiro (o 1º vértice tem exatamente a cor do kart).
	_ell(t, o + Vector3(0, 0.7, 0.3), tb, Vector3(0.19, 0.23, 0.155), kc, 14, 20)
	_ell(t, o + Vector3(0, 0.5, 0.32), Basis.IDENTITY, Vector3(0.18, 0.12, 0.16), kc, 10, 18, 0.25)      # quadril
	_ell(t, o + Vector3(0, 0.56, 0.31), Basis.IDENTITY, Vector3(0.188, 0.035, 0.166), kc.darkened(0.45), 6, 20)  # cinto
	_ell(t, o + Vector3(0, 0.9, 0.255), Basis.IDENTITY, Vector3(0.105, 0.04, 0.095), kc.darkened(0.2), 6, 18)  # gola
	for s: float in [-1.0, 1.0]:
		t.sphere(Transform3D(Basis.IDENTITY, o + Vector3(s * SHOULDER.x, SHOULDER.y, SHOULDER.z)), 0.07, 8, 12, kc)
		var hip := o + Vector3(s * 0.09, 0.5, 0.28)
		var knee := o + Vector3(s * 0.16, 0.645, -0.36)
		var ankle := o + Vector3(s * 0.15, 0.4, -0.56)
		_seg(t, hip, knee, 0.075, 0.068, 12, kc)
		t.sphere(Transform3D(Basis.IDENTITY, knee), 0.074, 8, 12, kc.darkened(0.18))                      # joelheira
		_seg(t, knee, ankle, 0.066, 0.06, 12, kc)
		_ell(t, o + Vector3(s * 0.15, 0.36, -0.62), Basis.IDENTITY, Vector3(0.07, 0.07, 0.1), kc.darkened(0.35), 6, 12)  # bota
	var mesh := t.commit(null, fabric)
	# Painel no peito (placa clara com moldura e dois botões redondos) + LEDs.
	var n := tb * Vector3(0, 0, -1)
	var up := tb * Vector3.UP
	var pb := Basis(Vector3.RIGHT, n, Vector3.RIGHT.cross(n))
	var pc := o + Vector3(0, 0.7, 0.3) + up * 0.035 + n * 0.128
	var p := MeshKit.new()
	p.rounded_prism(Transform3D(pb, pc), 0.16, 0.105, 0.03, 0.028, 3, Color(0.42, 0.45, 0.47), Color(0.72, 0.76, 0.76), false)
	var led := MeshKit.new()
	for bx: float in [-0.036, 0.036]:
		p.cylinder(Transform3D(pb, pc + Vector3(bx, 0, 0) + n * 0.029), 0.027, 0.027, 0.008, 18, Color(0.88, 0.9, 0.9))
		p.cylinder(Transform3D(pb, pc + Vector3(bx, 0, 0) + n * 0.03), 0.019, 0.019, 0.012, 18, Color(0.08, 0.1, 0.11))
		led.cylinder(Transform3D(pb, pc + Vector3(bx, 0, 0) + n * 0.041), 0.009, 0.009, 0.002, 10, LED_COLORS[character])
	p.commit(mesh, _mat(0.35, 0.6))
	led.commit(mesh, _unshaded())
	var neck := MeshKit.new()
	_seg(neck, o + Vector3(0, 0.86, 0.26), o + HEAD_PIVOT + Vector3(0, 0.08, 0), 0.056, 0.05, 12, skin.darkened(0.08))
	neck.commit(mesh, skin_mat)
	body = MeshInstance3D.new()
	body.name = "Suit"
	body.mesh = mesh
	rig.add_child(body)


func _skin_color(d: Vector3, skin: Color, noise: FastNoiseLite) -> Color:
	var v := noise.get_noise_3d(d.x * 40.0, d.y * 40.0, d.z * 40.0)
	var v2 := noise.get_noise_3d(d.x * 9.0 + 50.0, d.y * 9.0, d.z * 9.0)
	var shade := 0.94 + 0.05 * v + 0.05 * v2
	shade += 0.07 * clampf(-d.z, 0.0, 1.0) - 0.08 * clampf(d.y, 0.0, 1.0) * clampf(d.z + 0.3, 0.0, 1.0)
	if character == Character.VISITANTE and d.y > 0.3 and d.z < -0.2:
		# Rugas sutis na testa (como na referência).
		var stripe := 0.5 + 0.5 * sin(d.y * 58.0 + d.x * 6.0)
		shade -= 0.07 * stripe * smoothstep(0.3, 0.55, d.y) * clampf(-d.z, 0.0, 1.0)
	var c := skin * shade
	c.a = 1.0
	return c


## Olho: `eye` = [direção central, eixo x, eixo y, lado, raio angular x, raio angular y].
## (u, v) no disco unitário; o lado interno (nariz) afina, formando a gota.
static func _eye_dir(eye: Array, u: float, v: float) -> Vector3:
	var side: float = eye[3]
	var taper := lerpf(1.0, 0.55, clampf(-side * u, 0.0, 1.0))
	var d0: Vector3 = eye[0]
	var ex: Vector3 = eye[1]
	var ey: Vector3 = eye[2]
	return (d0 + ex * (u * float(eye[4])) + ey * (v * taper * float(eye[5]))).normalized()


static func _eye_pt(eye: Array, u: float, v: float, bulge: float) -> Vector3:
	var d := _eye_dir(eye, u, v)
	var off := -0.004 + bulge * sqrt(maxf(1.0 - u * u - v * v, 0.0))
	return _head_pt(d) + _head_n(d) * off


## Casca do olho colada à cabeça (malha polar), normais numéricas.
func _eye_shell(k: MeshKit, eye: Array, bulge: float, c: Color) -> void:
	var rings := 9
	var segs := 30
	var e := 0.01
	var base_i := k.verts.size()
	for r in rings + 1:
		var rho := float(r) / float(rings)
		for j in segs + 1:
			var th := TAU * float(j) / float(segs)
			var u := rho * cos(th)
			var v := rho * sin(th)
			var p := _eye_pt(eye, u, v, bulge)
			var du := _eye_pt(eye, u + e, v, bulge) - _eye_pt(eye, u - e, v, bulge)
			var dv := _eye_pt(eye, u, v + e, bulge) - _eye_pt(eye, u, v - e, bulge)
			var n := du.cross(dv).normalized()
			var hn := _head_n(_eye_dir(eye, u, v))
			if n.dot(hn) < 0.0:
				n = -n
			if r == rings:
				n = (n + hn).normalized()
			k.add_vertex(HEAD_CENTER + p, n, Vector2(u, v), c)
	var stride := segs + 1
	for r in rings:
		for j in segs:
			var a0 := base_i + r * stride + j
			k.quad(a0, a0 + 1, a0 + stride, a0 + stride + 1)


func _build_head(skin: Color, skin_mat: Material) -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = HEAD_PIVOT - ORIGIN
	rig.add_child(head)
	var hc := HEAD_CENTER
	var noise := FastNoiseLite.new()
	noise.seed = 7 + character
	noise.frequency = 0.05
	var k := MeshKit.new()
	var rings := 28
	var segs := 40
	var base_i := k.verts.size()
	for r in rings + 1:
		var phi := PI * float(r) / float(rings)
		for s in segs + 1:
			var th := TAU * float(s) / float(segs)
			var d := Vector3(cos(th) * sin(phi), cos(phi), sin(th) * sin(phi))
			if r == 0 or r == rings:
				d = Vector3(0, signf(d.y), 0)
			k.add_vertex(hc + _head_pt(d), _head_n(d), Vector2(float(s) / segs, float(r) / rings), _skin_color(d, skin, noise))
	var stride := segs + 1
	for r in rings:
		for s in segs:
			var a0 := base_i + r * stride + s
			var b0 := a0 + stride
			if r > 0:
				k.tri(a0, a0 + 1, b0)
			if r < rings - 1:
				k.tri(a0 + 1, b0 + 1, b0)
	var fem := character == Character.TURISTA
	var dark := skin.darkened(0.72)
	var eyes := MeshKit.new()
	var glint := MeshKit.new()
	for s: float in [-1.0, 1.0]:
		# Olho enorme em gota (ponta para o nariz), inclinado e colado à curvatura da cabeça.
		var d0 := Vector3(s * 0.5, -0.05, -1.0).normalized()
		var eb := _face_basis(d0, -s * 0.38)
		var eye := [d0, eb.x, eb.y, s, 0.42 if fem else 0.4, 0.3 if fem else 0.28]
		_eye_shell(eyes, eye, 0.03, Color(0.01, 0.012, 0.016))
		for g: Array in [[-0.3, 0.45, 0.028, 0.02], [0.45, -0.4, 0.012, 0.009]]:
			var gd := _eye_dir(eye, float(g[0]), float(g[1]))
			var gp := hc + _eye_pt(eye, float(g[0]), float(g[1]), 0.03) + _head_n(gd) * 0.001
			_ell(glint, gp, _face_basis(gd, -s * 0.38), Vector3(g[2], g[3], 0.004), Color(0.95, 0.97, 1.0), 6, 10)
		# Arco da sobrancelha / maçã do rosto.
		var bd := Vector3(s * 0.44, 0.24, -1.0).normalized()
		_ell(k, hc + _head_pt(bd) - _head_n(bd) * 0.02, _face_basis(bd, -s * 0.3), Vector3(0.09, 0.03, 0.035), skin * 1.02, 6, 12)
		var cd := Vector3(s * 0.55, -0.3, -1.0).normalized()
		var cheek := Color(1.0, 0.36, 0.5) if fem else skin * 1.04
		_ell(k, hc + _head_pt(cd) - _head_n(cd) * 0.018, _face_basis(cd), Vector3(0.055, 0.035, 0.03), cheek, 6, 12)
		# Narinas.
		var nd := Vector3(s * 0.05, -0.23, -1.0).normalized()
		_ell(k, hc + _head_pt(nd) - _head_n(nd) * 0.001, _face_basis(nd), Vector3(0.008, 0.005, 0.004), dark, 4, 8)
		if fem:
			# Cílios: três fios curvos no canto externo superior de cada olho.
			for j in 3:
				var ang := 0.3 + float(j) * 0.38
				var u := s * cos(ang)
				var v := sin(ang)
				var base := hc + _eye_pt(eye, u * 0.97, v * 0.97, 0.03)
				var en := _head_n(_eye_dir(eye, u, v))
				var dir := ((eb.x * u + eb.y * v).normalized() * 0.75 + en * 0.3 + eb.y * 0.35).normalized()
				var ln := 0.05 + 0.012 * float(j)
				_seg(k, base, base + dir * ln, 0.009, 0.0025, 6, Color(0.04, 0.02, 0.04))
	# Narizinho.
	var nd0 := Vector3(0, -0.18, -1.0).normalized()
	_ell(k, hc + _head_pt(nd0) - _head_n(nd0) * 0.012, _face_basis(nd0), Vector3(0.035, 0.022, 0.022), skin * 1.03, 6, 10)
	# Sorriso pequeno (cantos para cima).
	var lip := Color(0.75, 0.12, 0.32) if fem else skin.darkened(0.6)
	for j in 13:
		var tt := -1.0 + 2.0 * float(j) / 12.0
		var md := Vector3(tt * 0.2, -0.44 + 0.08 * tt * tt, -1.0).normalized()
		k.sphere(Transform3D(Basis.IDENTITY, hc + _head_pt(md) - _head_n(md) * 0.002), 0.009 if fem else 0.0075, 4, 6, lip)
	var mesh := k.commit(null, skin_mat)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.vertex_color_use_as_albedo = true
	eye_mat.roughness = 0.03
	eye_mat.metallic_specular = 1.0
	eye_mat.clearcoat_enabled = true
	eye_mat.clearcoat = 1.0
	eye_mat.clearcoat_roughness = 0.0
	eye_mat.rim_enabled = true
	eye_mat.rim = 0.4
	eyes.commit(mesh, eye_mat)
	glint.commit(mesh, _unshaded())
	if fem:
		# Laço vermelho de bolinhas brancas no alto da cabeça (inclinado para a direita).
		var bow := MeshKit.new()
		var dd := Vector3(0.38, 0.9, 0.08).normalized()
		var bn := _head_n(dd)
		var bt := (Vector3(1, -0.2, 0) - bn * bn.dot(Vector3(1, -0.2, 0))).normalized()
		var bb := bn.cross(bt)
		var bp := hc + _head_pt(dd) + bn * 0.02
		var red := Color(0.9, 0.06, 0.2)
		_ell(bow, bp + bn * 0.02, Basis(bt, bn, bb), Vector3(0.034, 0.034, 0.03), red.darkened(0.1), 8, 12)
		for s: float in [-1.0, 1.0]:
			var lb := Basis(bt, bn, bb).rotated(bb, s * 0.25)
			var lc := bp + bn * 0.03 + bt * s * 0.075
			_ell(bow, lc, lb, Vector3(0.07, 0.05, 0.034), red, 10, 16)
			for q: Array in [[0.35, 0.3], [0.65, -0.15], [0.2, -0.45]]:
				var qp: Vector3 = lc + lb.x * s * 0.07 * float(q[0]) + lb.y * 0.05 * float(q[1]) - bb * 0.029
				_ell(bow, qp, lb, Vector3(0.011, 0.011, 0.006), Color(1, 0.97, 0.97), 4, 8)
				_ell(bow, qp + bb * 0.058, lb, Vector3(0.011, 0.011, 0.006), Color(1, 0.97, 0.97), 4, 8)
		var bmat := _mat(0.25, 1.0)
		bow.commit(mesh, bmat)
	var mi := MeshInstance3D.new()
	mi.name = "HeadMesh"
	mi.mesh = mesh
	head.add_child(mi)


func _build_arms(kc: Color, skin: Color, skin_mat: Material, fabric: Material) -> void:
	var ua := MeshKit.new()
	ua.cylinder(Transform3D.IDENTITY, 0.056, 0.05, L1, 12, kc)
	ua.sphere(Transform3D(Basis.IDENTITY, Vector3(0, L1, 0)), 0.053, 6, 12, kc.darkened(0.12))
	var ua_mesh := ua.commit(null, fabric)
	var fa := MeshKit.new()
	fa.cylinder(Transform3D.IDENTITY, 0.05, 0.045, L2, 12, kc)
	fa.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, L2 - 0.05, 0)), 0.056, 0.058, 0.05, 14, kc.darkened(0.35))  # punho da luva
	var fa_mesh := fa.commit(null, fabric)
	var finger := MeshKit.new()
	finger.sphere(Transform3D.IDENTITY, 0.0145, 5, 8, skin)
	finger.cylinder(Transform3D.IDENTITY, 0.0135, 0.0125, 0.058, 8, skin, false)
	finger.sphere(Transform3D(Basis.IDENTITY, Vector3(0, 0.064, 0)), 0.0185, 6, 10, skin * 1.04)    # ponta arredondada de ET
	var finger_mesh := finger.commit(null, skin_mat)
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
		# Mão: palma (dorso para +Z local, dedos para +Y), anelar dobrado e polegar.
		var h := MeshKit.new()
		_ell(h, Vector3(0, 0.045, 0), Basis.IDENTITY, Vector3(0.043, 0.05, 0.027), skin, 8, 14)
		_ell(h, Vector3(s * 0.03, 0.082, -0.018), Basis(Vector3.RIGHT, -0.9), Vector3(0.014, 0.024, 0.017), skin, 6, 8)
		var tb := Vector3(-s * 0.032, 0.03, -0.012)
		var tt := Vector3(-s * 0.018, 0.075, -0.04)
		_seg(h, tb, tt, 0.016, 0.014, 8, skin)
		h.sphere(Transform3D(Basis.IDENTITY, tt), 0.017, 5, 8, skin)
		var hand := MeshInstance3D.new()
		hand.name = "Hand" + suffix
		hand.mesh = h.commit(null, skin_mat)
		rig.add_child(hand)
		hands.append(hand)
		for j in 2:
			var fi := MeshInstance3D.new()
			fi.name = ("Index" if j == 0 else "Middle") + suffix
			fi.mesh = finger_mesh
			fi.position = Vector3(-s * 0.013 if j == 0 else s * 0.014, 0.086, 0.0)
			hand.add_child(fi)
			fingers[i].append(fi)


# ------------------------------------------------------------------ animação

func set_pose(p: Pose) -> void:
	if p == pose:
		return
	pose = p
	_t = 0.0
	if p == Pose.VICTORY and _fx == null:
		_fx = _make_fx()
		rig.add_child(_fx)
	if _fx != null:
		_fx.emitting = p == Pose.VICTORY


## Comemoração própria: corações (Turista) ou estrelinhas (Visitante) subindo.
func _make_fx() -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.name = "CelebrationFx"
	fx.amount = 14
	fx.lifetime = 1.8
	fx.position = HEAD_PIVOT - ORIGIN + Vector3(0, 0.45, 0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = Vector3.UP
	pm.spread = 35.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.25, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.15, 1))
	curve.add_point(Vector2(0.8, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	fx.process_material = pm
	var k := MeshKit.new()
	var mat := _unshaded()
	if character == Character.TURISTA:
		var c := Color(1.0, 0.3, 0.55)
		for s: float in [-1.0, 1.0]:
			k.sphere(Transform3D(Basis.IDENTITY, Vector3(s * 0.035, 0.03, 0)), 0.042, 6, 10, c)
		k.cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0.035, 0)), 0.068, 0.0, 0.09, 12, c)
	else:
		var c := Color(1.0, 0.92, 0.35)
		k.sphere(Transform3D(Basis.from_scale(Vector3(1, 1, 0.35)), Vector3.ZERO), 0.06, 2, 4, c)
		k.sphere(Transform3D(Basis(Vector3.FORWARD, PI * 0.25) * Basis.from_scale(Vector3(1, 1, 0.35)), Vector3.ZERO), 0.06, 2, 4, c.lightened(0.3))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	fx.draw_pass_1 = k.commit(null, mat)
	return fx


## Atualiza a pose (grips = pontos de pega no volante, no espaço deste nó).
func animate_rig(delta: float, steer: float, grip_l: Vector3, grip_r: Vector3) -> void:
	_t += delta
	var target := Vector3(1, 0, 0) if pose == Pose.DRIVE else (Vector3(0, 1, 0) if pose == Pose.VICTORY else Vector3(0, 0, 1))
	_w = _w.move_toward(target, delta * 3.5) if delta > 0.0 else target
	var wsum := maxf(_w.x + _w.y + _w.z, 0.001)
	var wd := _w.x / wsum
	var wv := _w.y / wsum
	var wl := _w.z / wsum
	var fem := character == Character.TURISTA
	# Pulinhos na vitória.
	var hz := 1.45 if fem else 1.1
	hop = absf(sin(_t * PI * hz)) * (0.09 if fem else 0.13) * wv
	rig.position = Vector3(0, hop, 0)
	# Cabeça: acompanha a curva / comemora / baixa balançando.
	var hd := Vector3(0.0, -steer * 0.22, steer * 0.05)
	var hv := Vector3(0.12 + 0.1 * sin(_t * 7.0), 0.0, 0.0)
	if fem:
		hv = Vector3(0.1, 0.0, sin(_t * 3.4) * 0.24)
	var hl := Vector3(-0.5 + 0.04 * sin(_t * 2.0), sin(_t * 4.6) * 0.38, 0.0)
	head.rotation = hd * wd + hv * wv + hl * wl
	head_pitch = head.rotation.x
	# Braços (IK) e mãos.
	var grips: Array[Vector3] = [grip_l, grip_r]
	wrist_error = 0.0
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var fd := Vector3(-s * 0.35, -0.25, -1.0).normalized()
		var pd := Vector3(s, 0.3, 0.0)
		var wdr := grips[i] + pd.normalized() * 0.03 - fd * 0.045
		var wvw: Vector3
		var fv: Vector3
		if fem:
			wvw = Vector3(s * 0.42, 1.1 + 0.03 * sin(_t * 6.0), -0.02) - ORIGIN
			fv = Vector3(s * 0.45, 1.0, -0.2)
		else:
			wvw = Vector3(s * 0.4, 1.22 + 0.05 * sin(_t * 7.0 + (PI if s > 0.0 else 0.0)), 0.1) - ORIGIN
			fv = Vector3(s * 0.25, 1.0, -0.1)
		var wlw := Vector3(s * 0.17, 0.73, -0.24) - ORIGIN
		var fl := Vector3(s * 0.1, -0.35, -1.0)
		var wrist := wdr * wd + wvw * wv + wlw * wl
		var fdir := (fd * wd + fv.normalized() * wv + fl.normalized() * wl).normalized()
		var back := (pd.normalized() * wd + Vector3(0, 0, 1) * wv + Vector3.UP * wl).normalized()
		wrist_error = maxf(wrist_error, _solve_arm(i, s, wrist, fdir, back))
	v_amount = wv
	var curl := -1.55 * wd - 0.45 * wl
	var spread := 0.24 * wv
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		(fingers[i][0] as Node3D).basis = Basis(Vector3.BACK, s * spread) * Basis(Vector3.RIGHT, curl)
		(fingers[i][1] as Node3D).basis = Basis(Vector3.BACK, -s * spread) * Basis(Vector3.RIGHT, curl)


## IK de 2 ossos (ombro -> cotovelo -> punho), cotovelo para fora/baixo. Devolve o erro de alcance.
func _solve_arm(i: int, s: float, wrist: Vector3, fdir: Vector3, back: Vector3) -> float:
	var sh := Vector3(s * SHOULDER.x, SHOULDER.y, SHOULDER.z) - ORIGIN
	var to := wrist - sh
	var dist := to.length()
	var d := clampf(dist, 0.08, (L1 + L2) * 0.999)
	var u := to / maxf(dist, 0.0001)
	var ca := clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0)
	var sa := sqrt(1.0 - ca * ca)
	var pole := Vector3(s, -0.7, 0.3)
	var pp := pole - u * pole.dot(u)
	pp = pp.normalized() if pp.length_squared() > 1e-6 else Vector3.DOWN
	var e := sh + u * (L1 * ca) + pp * (L1 * sa)
	var wr := sh + u * d
	arms[i].transform = Transform3D(_basis_y(e - sh, pp), sh)
	forearms[i].transform = Transform3D(_basis_y(wr - e, pp), e)
	var y := fdir
	var z := (back - y * back.dot(y))
	z = z.normalized() if z.length_squared() > 1e-6 else Vector3.BACK
	hands[i].transform = Transform3D(Basis(y.cross(z), y, z), wr)
	return absf(dist - d)
