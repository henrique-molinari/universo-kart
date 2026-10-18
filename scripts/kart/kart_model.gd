class_name KartModel
extends Node3D
## Modelo procedural do kart (MeshKit), fiel à foto de referência (kart de competição baixo e aberto):
## para-choque frontal inteiriço, bico largo e "nariz" subindo até o volante pequeno em coluna, pontões
## arredondados, chassi tubular cromado aparente, banco concha preto, aerofólio alto e para-choque
## traseiro na cor do kart, slicks largos (traseiros mais largos) com aro escuro. Piloto com traje e
## capacete da MESMA cor do kart, luvas brancas e viseira escura reflexiva. PBR: verniz, cromo,
## borracha fosca e banco fosco com textura sutil.
## Local: -Z = frente, +X = direita, +Y = cima. Origem no chão, centro do kart.

const FRONT_R := 0.25
const REAR_R := 0.3
const SEAT_NORMAL := preload("res://assets/materials/noise_grain_normal.tres")

## Rodas: pivô (posição no eixo + esterço em Y, só dianteiras) -> nó de giro (só X local) -> malha centrada.
var wheels: Array[Node3D] = []          ## nós de giro (rotação só em X local)
var wheel_pivots: Array[Node3D] = []
var wheel_radius: Array[float] = []
var front_wheels: Array[Node3D] = []    ## pivôs que esterçam
var body_root: Node3D                   ## pulinho (tudo que é visível, inclusive rodas e efeitos)
var tilt_root: Node3D                   ## rolagem da carroceria/piloto (as rodas NÃO rolam junto)
var _spin: Array[float] = []
var driver: Node3D                      ## inclina nas curvas
var steering_wheel: Node3D
var paint_color: Color                  ## cor do kart
var suit_color: Color                   ## cor usada no traje (== paint_color)
var helmet_color: Color                 ## cor usada no capacete (== paint_color)
## Pontos (locais ao body_root) para efeitos.
var exhaust_points: Array[Vector3] = [Vector3(-0.2, 0.42, 1.36), Vector3(0.2, 0.42, 1.36)]
var rear_wheel_points: Array[Vector3] = [Vector3(-0.8, 0.06, 1.0), Vector3(0.8, 0.06, 1.0)]

var _hop_t := 1.0
var _roll := 0.0
var _lean := 0.0


static func _mat(rough: float, metal: float = 0.0, clearcoat: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.metallic = metal
	if clearcoat:
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.06
	return m


## Base com eixo Y apontando para `d`.
static func _basis_y(d: Vector3) -> Basis:
	var y := d.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Cilindro (ou cone) de `a` até `b`.
static func _seg(k: MeshKit, a: Vector3, b: Vector3, r0: float, r1: float, segs: int, c: Color) -> void:
	k.cylinder(Transform3D(_basis_y(b - a), a), r0, r1, a.distance_to(b), segs, c)


static func _blob(k: MeshKit, center: Vector3, sc: Vector3, c: Color, ao: float = 0.0, rings: int = 12, segs: int = 20) -> void:
	k.sphere(Transform3D(Basis.IDENTITY.scaled(sc), center), 1.0, rings, segs, c, ao)


func build(cfg: PlayerConfig) -> void:
	var kc := cfg.kart_color
	paint_color = kc
	suit_color = kc
	helmet_color = kc
	var paint := _mat(0.22, 0.05, true)
	var plastic := _mat(0.5)
	var rubber := _mat(0.92)
	rubber.metallic_specular = 0.2
	var chrome := _mat(0.22, 1.0)
	var fabric := _mat(0.68)
	var dark := Color(0.07, 0.07, 0.08)
	var trim := Color(0.16, 0.16, 0.18)
	var white := Palette.WHITE
	var steel := Color(0.78, 0.8, 0.84)

	body_root = Node3D.new()
	body_root.name = "Body"
	add_child(body_root)
	tilt_root = Node3D.new()
	tilt_root.name = "Tilt"
	body_root.add_child(tilt_root)

	# Referência: kart de competição baixo e aberto (foto do usuário). Carenagem em plástico com verniz
	# na cor do jogador, chassi tubular cromado aparente, banco concha preto, aerofólio alto.
	var seat_mat := _mat(0.85)
	seat_mat.normal_enabled = true
	seat_mat.normal_texture = SEAT_NORMAL
	seat_mat.normal_scale = 0.35
	seat_mat.uv1_triplanar = true
	seat_mat.uv1_scale = Vector3(3, 3, 3)

	# ---------------- carenagem (pintura com verniz)
	var p := MeshKit.new()
	# Para-choque frontal inteiriço: cobre a frente e a entrada das rodas dianteiras.
	p.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(0, 0.08, -1.13)), 1.96, 0.4, 0.2, 0.17, 6, kc, kc.lightened(0.06), true)
	for s: float in [-1.0, 1.0]:
		_blob(p, Vector3(s * 0.8, 0.2, -1.08), Vector3(0.2, 0.12, 0.24), kc, 0.2)          # pontas elevadas
		_blob(p, Vector3(s * 0.3, 0.2, -1.2), Vector3(0.28, 0.09, 0.16), kc.lightened(0.05), 0.2)  # lábio central
	# Bico largo e arredondado + "nariz" subindo até o volante.
	_blob(p, Vector3(0, 0.2, -0.86), Vector3(0.44, 0.13, 0.36), kc, 0.25)
	p.sphere(Transform3D(Basis(Vector3.RIGHT, -0.42).scaled(Vector3(0.27, 0.2, 0.56)), Vector3(0, 0.36, -0.62)), 1.0, 12, 20, kc, 0.2)
	p.sphere(Transform3D(Basis(Vector3.RIGHT, -0.42).scaled(Vector3(0.09, 0.205, 0.565)), Vector3(0, 0.365, -0.62)), 1.0, 10, 12, kc.lightened(0.18))
	# Pontões laterais arredondados entre as rodas.
	for s: float in [-1.0, 1.0]:
		_blob(p, Vector3(s * 0.72, 0.24, 0.04), Vector3(0.17, 0.14, 0.42), kc, 0.3)
		_blob(p, Vector3(s * 0.72, 0.33, 0.04), Vector3(0.12, 0.05, 0.34), kc.lightened(0.1))
	# Para-choque traseiro.
	p.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 1.24)), 1.72, 0.2, 0.18, 0.09, 4, kc, kc.lightened(0.06), true)
	# Aerofólio traseiro alto com placas laterais.
	p.rounded_prism(Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.94, 1.16)), 1.5, 0.34, 0.06, 0.08, 4, kc, kc.lightened(0.08), true)
	for s: float in [-1.0, 1.0]:
		p.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(s * 0.76, 0.84, 1.16)), 0.05, 0.44, 0.26, 0.02, 2, kc.darkened(0.1), kc, true)
	var paint_mi := MeshInstance3D.new()
	paint_mi.name = "Paint"
	paint_mi.mesh = p.commit(null, paint)
	tilt_root.add_child(paint_mi)

	# ---------------- chassi tubular cromado + eixos, coluna, suportes, motor e escapamentos
	var m := MeshKit.new()
	var tube := 0.035
	for s: float in [-1.0, 1.0]:
		_seg(m, Vector3(s * 0.34, 0.13, -1.02), Vector3(s * 0.42, 0.13, -0.4), tube, tube, 8, steel)
		_seg(m, Vector3(s * 0.42, 0.13, -0.4), Vector3(s * 0.46, 0.13, 1.1), tube, tube, 8, steel)
		_seg(m, Vector3(s * 0.42, 0.13, -0.3), Vector3(s * 0.62, 0.16, -0.1), tube, tube, 8, steel)   # apoio do pontão
		_seg(m, Vector3(s * 0.44, 0.13, 0.35), Vector3(s * 0.62, 0.16, 0.2), tube, tube, 8, steel)
		_seg(m, Vector3(s * 0.46, 0.13, 1.1), Vector3(s * 0.6, 0.1, 1.2), tube, tube, 8, steel)       # apoio do para-choque
		_seg(m, Vector3(s * 0.28, 0.2, 0.95), Vector3(s * 0.34, 0.88, 1.12), 0.03, 0.03, 8, steel)    # suportes do aerofólio
		m.sphere(Transform3D(Basis.IDENTITY, Vector3(s * 0.42, 0.13, -0.4)), tube * 1.3, 4, 8, steel)
	for z: float in [-0.95, -0.45, 0.2, 0.65, 1.05]:
		_seg(m, Vector3(-0.44, 0.13, z), Vector3(0.44, 0.13, z), tube, tube, 8, steel)
	_seg(m, Vector3(-0.74, FRONT_R, -0.7), Vector3(0.74, FRONT_R, -0.7), 0.03, 0.03, 8, steel)      # eixo dianteiro
	_seg(m, Vector3(-0.78, REAR_R, 0.8), Vector3(0.78, REAR_R, 0.8), 0.045, 0.045, 10, steel)       # eixo traseiro
	_seg(m, Vector3(0, 0.3, -0.5), Vector3(0, 0.8, -0.3), 0.025, 0.025, 8, steel)                   # coluna de direção
	# Motor lateral (direita) e escapamentos saindo por baixo do aerofólio.
	m.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(0.44, 0.2, 0.62)), 0.26, 0.3, 0.3, 0.08, 3, steel.darkened(0.3), steel, true)
	m.cylinder(Transform3D(Basis.IDENTITY, Vector3(0.44, 0.5, 0.62)), 0.1, 0.07, 0.12, 12, steel)
	for s: float in [-1.0, 1.0]:
		var a := Vector3(0.4, 0.4, 0.75) if s > 0.0 else Vector3(0.1, 0.3, 0.85)
		var b := Vector3(s * 0.2, 0.42, 1.3)
		_seg(m, a, b, 0.05, 0.065, 12, steel)
		_seg(m, b, b + (b - a).normalized() * 0.05, 0.065, 0.055, 12, Color(0.05, 0.05, 0.05))
	var metal_mi := MeshInstance3D.new()
	metal_mi.name = "Chassis"
	metal_mi.mesh = m.commit(null, chrome)
	tilt_root.add_child(metal_mi)

	# ---------------- banco concha preto (fosco, textura sutil) e piso
	var d := MeshKit.new()
	d.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0.1)), 0.7, 1.9, 0.03, 0.2, 4, dark, trim, true)
	var seat := MeshKit.new()
	var sc := Color(0.06, 0.06, 0.065)
	_blob(seat, Vector3(0, 0.3, 0.3), Vector3(0.3, 0.1, 0.3), sc)                                    # assento
	seat.sphere(Transform3D(Basis(Vector3.RIGHT, 0.38).scaled(Vector3(0.33, 0.36, 0.1)), Vector3(0, 0.58, 0.58)), 1.0, 12, 18, sc)  # encosto
	for s: float in [-1.0, 1.0]:
		seat.sphere(Transform3D(Basis(Vector3.RIGHT, 0.3).scaled(Vector3(0.07, 0.24, 0.3)), Vector3(s * 0.3, 0.46, 0.42)), 1.0, 8, 12, sc)  # abas laterais
	var dark_mi := MeshInstance3D.new()
	dark_mi.name = "Floor"
	dark_mi.mesh = d.commit(null, plastic)
	tilt_root.add_child(dark_mi)
	var seat_mi := MeshInstance3D.new()
	seat_mi.name = "Seat"
	seat_mi.mesh = seat.commit(null, seat_mat)
	tilt_root.add_child(seat_mi)

	# ---------------- volante pequeno em coluna (gira com a direção)
	steering_wheel = Node3D.new()
	steering_wheel.name = "SteeringWheel"
	steering_wheel.position = Vector3(0, 0.8, -0.3)
	steering_wheel.basis = Basis(Vector3.RIGHT, deg_to_rad(-62.0))
	tilt_root.add_child(steering_wheel)
	var sw := MeshKit.new()
	sw.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.015, 0)), 0.13, 0.13, 0.03, 18, dark)
	sw.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), 0.04, 0.04, 0.04, 10, kc)
	sw.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0)), Vector3(0.24, 0.018, 0.035), trim)
	var sw_mi := MeshInstance3D.new()
	sw_mi.mesh = sw.commit(null, plastic)
	steering_wheel.add_child(sw_mi)

	# ---------------- placa de número presa na face frontal do para-choque (P1 = 1, P2 = 2)
	var plate := MeshKit.new()
	plate.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.18, -1.342)), 0.085, 0.085, 0.012, 20, white)
	var plate_mi := MeshInstance3D.new()
	plate_mi.name = "NumberPlate"
	plate_mi.mesh = plate.commit(null, paint)
	tilt_root.add_child(plate_mi)
	var num := Label3D.new()
	num.name = "Number"
	num.text = str(cfg.player_index + 1) if cfg.player_index >= 0 else ""
	num.font = UiKit.FONT
	num.font_size = 48
	num.pixel_size = 0.0028
	num.outline_size = 0
	num.modulate = Palette.GRAPHITE
	num.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	num.double_sided = false
	num.position = Vector3(0, 0.18, -1.35)
	num.rotation = Vector3(0, PI, 0)
	tilt_root.add_child(num)

	# ---------------- adesivo UNIFEOB discreto nos pontões
	for s: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "UNIFEOB"
		l.font_size = 40
		l.pixel_size = 0.0019
		l.outline_size = 8
		l.modulate = white
		l.outline_modulate = Palette.BLUE if kc != Palette.BLUE else Palette.MAGENTA
		l.position = Vector3(s * 0.893, 0.24, 0.04)
		l.rotation = Vector3(0, s * PI * 0.5, 0)
		l.double_sided = false
		tilt_root.add_child(l)

	_build_driver(kc, fabric, paint)
	_build_wheels(rubber, chrome)


func _build_driver(kc: Color, fabric: StandardMaterial3D, paint: StandardMaterial3D) -> void:
	driver = Node3D.new()
	driver.name = "Driver"
	driver.position = Vector3(0, 0.55, 0.36)
	tilt_root.add_child(driver)
	var o := -driver.position  # constrói em coordenadas do kart
	var white := Palette.WHITE
	var black := Color(0.06, 0.06, 0.07)
	var t := MeshKit.new()
	_blob(t, o + Vector3(0, 0.8, 0.36), Vector3(0.25, 0.3, 0.2), kc, 0.15)            # tronco
	_blob(t, o + Vector3(0, 0.62, 0.36), Vector3(0.255, 0.05, 0.205), black)          # cinto
	_blob(t, o + Vector3(0, 0.88, 0.165), Vector3(0.1, 0.1, 0.03), white)              # emblema
	_blob(t, o + Vector3(0, 0.8, 0.16), Vector3(0.03, 0.2, 0.02), white)               # zíper/faixa
	for s: float in [-1.0, 1.0]:
		var sh := o + Vector3(s * 0.24, 0.98, 0.34)
		var el := o + Vector3(s * 0.31, 0.84, 0.06)
		var ha := o + Vector3(s * 0.12, 0.84, -0.27)
		t.sphere(Transform3D(Basis.IDENTITY, sh), 0.1, 8, 12, kc)
		_seg(t, sh, el, 0.08, 0.072, 10, kc)
		t.sphere(Transform3D(Basis.IDENTITY, el), 0.072, 6, 10, kc)
		_seg(t, el, ha, 0.07, 0.062, 10, kc)
		_seg(t, ha.lerp(el, 0.22), ha.lerp(el, 0.12), 0.075, 0.075, 10, white)     # punho da luva
		t.sphere(Transform3D(Basis.IDENTITY, ha), 0.078, 8, 12, white)             # luva
		t.sphere(Transform3D(Basis.IDENTITY, o + Vector3(s * 0.14, 0.62, -0.42)), 0.09, 6, 10, kc.darkened(0.15))  # joelhos
	_seg(t, o + Vector3(0, 1.0, 0.36), o + Vector3(0, 1.12, 0.33), 0.075, 0.07, 10, black)  # pescoço
	var tm := MeshInstance3D.new()
	tm.name = "Suit"
	tm.mesh = t.commit(null, fabric)
	driver.add_child(tm)

	# Capacete fechado e brilhante (mesma cor do kart) com faixa branca.
	var h := MeshKit.new()
	var hc := o + Vector3(0, 1.31, 0.3)
	_blob(h, hc, Vector3(0.3, 0.3, 0.325), kc, 0.12, 14, 24)
	_blob(h, hc, Vector3(0.07, 0.307, 0.332), white, 0.0, 14, 16)
	_blob(h, hc + Vector3(0, -0.2, 0.02), Vector3(0.24, 0.1, 0.26), black)              # base/colar
	var hm := MeshInstance3D.new()
	hm.name = "Helmet"
	hm.mesh = h.commit(null, paint)
	driver.add_child(hm)
	# Viseira escura reflexiva.
	var vk := MeshKit.new()
	_blob(vk, hc + Vector3(0, -0.01, -0.13), Vector3(0.245, 0.14, 0.2), Color(0.02, 0.03, 0.07), 0.0, 12, 20)
	var vmat := StandardMaterial3D.new()
	vmat.vertex_color_use_as_albedo = true
	vmat.metallic = 1.0
	vmat.roughness = 0.04
	vmat.clearcoat_enabled = true
	vmat.clearcoat = 1.0
	vmat.clearcoat_roughness = 0.0
	var vm := MeshInstance3D.new()
	vm.name = "Visor"
	vm.mesh = vk.commit(null, vmat)
	driver.add_child(vm)


func _wheel_mesh(r: float, w: float, rubber: Material, chrome: Material) -> ArrayMesh:
	# Pneu slick liso e arredondado: banda central + ombros com raio menor.
	var tire := MeshKit.new()
	var tc := Color(0.06, 0.06, 0.065)
	var ax := Basis(Vector3.FORWARD, PI * 0.5)  # eixo Y do cilindro -> +X (cresce a partir da origem)
	tire.cylinder(Transform3D(ax, Vector3(-w * 0.5, 0, 0)), r * 0.82, r * 0.82, w, 24, tc)
	tire.cylinder(Transform3D(ax, Vector3(-w * 0.47, 0, 0)), r * 0.93, r * 0.93, w * 0.94, 24, tc, false)
	tire.cylinder(Transform3D(ax, Vector3(-w * 0.4, 0, 0)), r, r, w * 0.8, 24, tc, false)
	var mesh := tire.commit(null, rubber)
	# Aro escuro com raios (mostram o giro).
	var rim := MeshKit.new()
	var rc := Color(0.16, 0.16, 0.18)
	rim.cylinder(Transform3D(ax, Vector3(-w * 0.5 - 0.01, 0, 0)), r * 0.58, r * 0.58, w + 0.02, 18, rc)
	for s: float in [-1.0, 1.0]:
		for i in 5:
			var a := TAU * float(i) / 5.0
			var bb := Basis(Vector3.RIGHT, a)
			rim.box(Transform3D(bb, Vector3(s * (w * 0.5 + 0.018), 0, 0) + bb * Vector3(0, r * 0.3, 0)), Vector3(0.02, r * 0.46, 0.05), Color(0.3, 0.3, 0.33))
		rim.cylinder(Transform3D(ax, Vector3(s * (w * 0.5 + 0.03) - 0.015, 0, 0)), r * 0.16, r * 0.16, 0.03, 10, Color(0.55, 0.56, 0.6))
	rim.commit(mesh, chrome)
	return mesh


func _build_wheels(rubber: Material, chrome: Material) -> void:
	var front := _wheel_mesh(FRONT_R, 0.26, rubber, chrome)
	var rear := _wheel_mesh(REAR_R, 0.4, rubber, chrome)
	var wpos: Array[Vector3] = [Vector3(-0.74, FRONT_R, -0.7), Vector3(0.74, FRONT_R, -0.7), Vector3(-0.8, REAR_R, 0.8), Vector3(0.8, REAR_R, 0.8)]
	for i in 4:
		var pivot := Node3D.new()
		pivot.name = "Wheel%d" % i
		pivot.position = wpos[i]
		body_root.add_child(pivot)
		var spin := Node3D.new()
		spin.name = "Spin"
		pivot.add_child(spin)
		var w := MeshInstance3D.new()
		w.mesh = front if i < 2 else rear
		spin.add_child(w)
		wheels.append(spin)
		wheel_pivots.append(pivot)
		_spin.append(0.0)
		wheel_radius.append(FRONT_R if i < 2 else REAR_R)
		if i < 2:
			front_wheels.append(pivot)


## Pulinho curto (início do drift).
func hop() -> void:
	_hop_t = 0.0


## Anima rodas (giro pela velocidade, esterço), volante, rolagem da carroceria, inclinação do piloto e pulinho.
func animate(speed: float, steer: float, delta: float, drift_dir: float = 0.0) -> void:
	for i in wheels.size():
		_spin[i] = fmod(_spin[i] - speed * delta / wheel_radius[i], TAU)
		wheels[i].basis = Basis(Vector3.RIGHT, _spin[i])
	var st := steer
	if drift_dir != 0.0:
		st = clampf(drift_dir * 0.6 + steer * 0.4, -1.0, 1.0)
	for p in front_wheels:
		p.rotation.y = -st * 0.45
	steering_wheel.basis = Basis(Vector3.RIGHT, deg_to_rad(-62.0)) * Basis(Vector3.UP, -st * 1.2)
	var k := 1.0 - exp(-8.0 * delta) if delta > 0.0 else 1.0
	var fast := clampf(absf(speed) / 12.0, 0.0, 1.0)
	_roll = lerpf(_roll, st * 0.06 * fast, k)
	_lean = lerpf(_lean, -st * 0.2 * fast, k)
	var y := 0.0
	if _hop_t < 1.0:
		_hop_t = minf(_hop_t + delta / 0.3, 1.0)
		y = sin(_hop_t * PI) * 0.32
	body_root.position = Vector3(0, y, 0)
	tilt_root.rotation = Vector3(0, 0, _roll)
	driver.rotation = Vector3(0, 0, _lean)
