class_name CampusBuildings
extends Node3D
## Prédios estilizados do campus (cantos arredondados, janelas procedurais), praças,
## planetário "Universo", complexo esportivo e letreiros com o logo.

const BUILDING_MAT := preload("res://assets/materials/building.tres")
const PROPS_MAT := preload("res://assets/materials/painted_props.tres")
const DOME_SHADER := preload("res://assets/shaders/dome.gdshader")
const STAR_SHADER := preload("res://assets/shaders/star_band.gdshader")

const WALL := Color(1, 0, 0, 1)     # flag: parede com janelas
const PLAIN := Color(0, 0, 0, 1)    # flag: parede lisa (cor da parede)
const ACCENT := Color(0, 1, 0, 1)   # flag: cor de destaque
const ROOF := Color(0, 0, 1, 1)     # flag: cobertura

## Definição dos prédios: posição (x, z), tamanho (larg, alt, prof), rotação (graus), raio, estilo, cores.
var buildings: Array[Dictionary] = [
	{"name": "BlocoA", "pos": Vector2(-150, 98), "size": Vector3(64, 17.5, 26), "rot": 0.0, "r": 6.0, "style": "block", "wall": Color(0.96, 0.96, 0.98), "accent": Palette.BLUE, "sign": true, "fins": true, "solar": true},
	{"name": "Biblioteca", "pos": Vector2(-52, 116), "size": Vector3(52, 12, 30), "rot": 0.0, "r": 12.0, "style": "glass", "wall": Palette.LAVENDER, "accent": Palette.MAGENTA},
	{"name": "Reitoria", "pos": Vector2(58, 122), "size": Vector3(28, 46, 28), "rot": 12.0, "r": 7.0, "style": "tower", "wall": Color(0.97, 0.97, 1.0), "accent": Palette.BLUE, "sign": true},
	{"name": "BlocoC", "pos": Vector2(152, 88), "size": Vector3(44, 21, 28), "rot": -8.0, "r": 6.0, "style": "block", "wall": Color(1.0, 0.96, 0.88), "accent": Palette.MAGENTA, "fins": true},
	{"name": "BlocoD", "pos": Vector2(-215, 190), "size": Vector3(50, 14, 30), "rot": 6.0, "r": 6.0, "style": "block", "wall": Color(0.97, 0.97, 0.99), "accent": Palette.YELLOW, "solar": true},
	{"name": "Convivencia", "pos": Vector2(-70, 212), "size": Vector3(70, 10, 26), "rot": 0.0, "r": 13.0, "style": "glass", "wall": Color(0.96, 0.96, 0.98), "accent": Palette.BLUE},
	{"name": "Laboratorios", "pos": Vector2(95, 212), "size": Vector3(46, 24, 40), "rot": 0.0, "r": 8.0, "style": "block", "wall": Color(0.93, 0.95, 1.0), "accent": Palette.MAGENTA, "fins": true, "solar": true},
	{"name": "Ginasio", "pos": Vector2(218, 175), "size": Vector3(60, 13, 40), "rot": -15.0, "r": 18.0, "style": "block", "wall": Color(1.0, 0.97, 0.9), "accent": Palette.BLUE},
	{"name": "BlocoE", "pos": Vector2(262, 70), "size": Vector3(40, 16, 30), "rot": 20.0, "r": 6.0, "style": "block", "wall": Color(0.97, 0.97, 0.99), "accent": Palette.YELLOW},
	{"name": "Inovacao", "pos": Vector2(275, -150), "size": Vector3(36, 30, 36), "rot": -10.0, "r": 9.0, "style": "tower", "wall": Color(0.95, 0.95, 1.0), "accent": Palette.MAGENTA},
]

var _brand: BrandArt
var _site: SiteMap


func build(site: SiteMap, path: TrackPath, brand: BrandArt) -> void:
	_site = site
	_brand = brand
	for b in buildings:
		_build_building(b, path)
	_build_walkways()
	_build_pits(Vector3(-20.0, 0.0, -44.0), 118.0, 14.0)
	_build_planetarium(Vector3(100.0, 0.0, -82.0))
	_build_sports_complex(Vector3(-150.0, 0.0, -132.0))


func _ground(x: float, z: float) -> float:
	return _site.height_at(x, z)


func _build_building(b: Dictionary, path: TrackPath) -> void:
	var p2: Vector2 = b["pos"]
	var size: Vector3 = b["size"]
	var style: String = b["style"]
	var r: float = b["r"]
	var accent_c: Color = b["accent"]
	var gy := minf(minf(_ground(p2.x - size.x * 0.5, p2.y), _ground(p2.x + size.x * 0.5, p2.y)), _ground(p2.x, p2.y))
	var rot := Basis(Vector3.UP, deg_to_rad(b["rot"]))
	var xf := Transform3D(rot, Vector3(p2.x, gy, p2.y))
	var kit := MeshKit.new()
	# Embasamento (enterrado) + corpo + platibanda colorida.
	kit.rounded_prism(xf.translated_local(Vector3(0, -3.0, 0)), size.x + 1.2, size.z + 1.2, 3.35, r + 0.6, 5, PLAIN, ROOF)
	kit.rounded_prism(xf, size.x, size.z, size.y, r, 6, WALL, ROOF)
	kit.rounded_prism(xf.translated_local(Vector3(0, size.y, 0)), size.x + 0.8, size.z + 0.8, 1.1, r + 0.4, 6, ACCENT, ROOF)
	if style == "tower":
		# Coroa recuada no topo.
		kit.rounded_prism(xf.translated_local(Vector3(0, size.y + 1.1, 0)), size.x * 0.6, size.z * 0.6, 4.0, r * 0.6, 5, ACCENT, ROOF)
	# Equipamentos na cobertura.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(b["name"])
	var units := 2 + rng.randi() % 3
	for i in units:
		var ux := rng.randf_range(-0.3, 0.3) * size.x
		var uz := rng.randf_range(-0.25, 0.25) * size.z
		kit.box(xf.translated_local(Vector3(ux, size.y + 2.0, uz)), Vector3(rng.randf_range(3, 6), 1.8, rng.randf_range(2.5, 4)), ROOF)
	# Marquise de entrada (lado voltado para a pista).
	var to_track := _dir_to_track(Vector3(p2.x, 0, p2.y), path)
	var local_dir := rot.inverse() * to_track
	var face_z := signf(local_dir.z) if absf(local_dir.z) >= absf(local_dir.x) else 0.0
	var extra := MeshKit.new()
	var fz := face_z if face_z != 0.0 else 1.0
	# Entrada: marquise + porta de vidro com moldura + degraus.
	var canopy := xf.translated_local(Vector3(0, 4.0, fz * (size.z * 0.5 + 2.2)))
	kit.box(canopy, Vector3(minf(size.x * 0.4, 18.0), 0.45, 4.6), ACCENT)
	var door_w := minf(size.x * 0.22, 9.0)
	extra.box(xf.translated_local(Vector3(0, 1.8, fz * (size.z * 0.5 + 0.08))), Vector3(door_w, 3.6, 0.2), Color(0.1, 0.18, 0.35))
	extra.box(xf.translated_local(Vector3(0, 3.7, fz * (size.z * 0.5 + 0.15))), Vector3(door_w + 0.6, 0.3, 0.3), Color(0.92, 0.92, 0.94))
	for sx: float in [-1.0, 1.0]:
		extra.box(xf.translated_local(Vector3(sx * (door_w * 0.5 + 0.15), 1.8, fz * (size.z * 0.5 + 0.15))), Vector3(0.3, 3.8, 0.3), Color(0.92, 0.92, 0.94))
		extra.cylinder(Transform3D(rot, (xf.translated_local(Vector3(sx * minf(size.x * 0.18, 8.0), 0.0, fz * (size.z * 0.5 + 4.1)))).origin), 0.15, 0.15, 4.0, 8, Color(0.95, 0.95, 0.97), false)
	extra.box(xf.translated_local(Vector3(0, 0.1, fz * (size.z * 0.5 + 1.2))), Vector3(door_w + 3.0, 0.2, 2.4), Color(0.7, 0.7, 0.72))
	# Brises verticais nas duas fachadas longas.
	if b.get("fins", false):
		var span_x := size.x * 0.5 - r - 1.0
		var nf := int(span_x * 2.0 / 2.8)
		for side_z: float in [-1.0, 1.0]:
			for k in nf + 1:
				var fxp := -span_x + float(k) * span_x * 2.0 / float(nf)
				if absf(fxp) < door_w * 0.5 + 1.0 and side_z == fz:
					continue
				extra.box(xf.translated_local(Vector3(fxp, (size.y + 4.2) * 0.5, side_z * (size.z * 0.5 + 0.45))), Vector3(0.22, size.y - 4.6, 0.9), accent_c if k % 3 == 0 else Color(0.95, 0.95, 0.97))
	# Painéis solares na cobertura.
	if b.get("solar", false):
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(-22.0))
		for ix in 4:
			for iz in 3:
				var px := (float(ix) - 1.5) * minf(size.x * 0.18, 8.0)
				var pz := (float(iz) - 1.0) * minf(size.z * 0.22, 5.0)
				var pxf := Transform3D(rot * tilt, (xf.translated_local(Vector3(px, size.y + 1.8, pz))).origin)
				extra.box(pxf, Vector3(minf(size.x * 0.15, 6.5), 0.1, 2.2), Color(0.08, 0.14, 0.32))
				extra.box(Transform3D(rot, (xf.translated_local(Vector3(px, size.y + 1.35, pz))).origin), Vector3(0.2, 0.8, 0.2), Color(0.6, 0.6, 0.62))
	var emi := MeshInstance3D.new()
	emi.name = str(b["name"]) + "Detalhes"
	emi.mesh = extra.commit(null, PROPS_MAT)
	add_child(emi)
	var mi := MeshInstance3D.new()
	mi.name = b["name"]
	mi.mesh = kit.commit(null, BUILDING_MAT)
	add_child(mi)
	var wall: Color = b["wall"]
	var accent: Color = b["accent"]
	mi.set_instance_shader_parameter(&"wall_color", wall)
	mi.set_instance_shader_parameter(&"accent_color", accent)
	if style == "glass":
		mi.set_instance_shader_parameter(&"curtain_wall", 1.0)
		mi.set_instance_shader_parameter(&"window_params", Vector4(2.4, 3.6, 0.92, 0.88))
		mi.set_instance_shader_parameter(&"glass_color", Color(0.22, 0.42, 0.72))
	elif style == "tower":
		mi.set_instance_shader_parameter(&"curtain_wall", 1.0)
		mi.set_instance_shader_parameter(&"window_params", Vector4(2.0, 3.8, 0.92, 0.9))
		mi.set_instance_shader_parameter(&"glass_color", Color(0.12, 0.3, 0.62))
	if b.has("garage"):
		mi.set_instance_shader_parameter(&"ground_floor", 5.2)
		mi.set_instance_shader_parameter(&"lit_ratio", 0.0)
	# Praça ao redor.
	var plaza := MeshKit.new()
	plaza.rounded_prism(xf.translated_local(Vector3(0, -0.4, 0)), size.x + 14.0, size.z + 14.0, 0.5, r + 5.0, 6, Color(0.5, 0.5, 0.49), Color(0.56, 0.55, 0.53))
	var pmi := MeshInstance3D.new()
	pmi.name = str(b["name"]) + "Plaza"
	pmi.mesh = plaza.commit(null, PROPS_MAT)
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pmi)
	_site.add_blocker(p2, maxf(size.x, size.z) * 0.5 + 8.0)
	# Letreiro com o logo no topo, voltado para a pista.
	if b.get("sign", false):
		var sign_w := minf(size.x * 0.8, 30.0)
		var sign_h := sign_w * 0.25
		var dir := Vector3(to_track.x, 0, to_track.z).normalized()
		var top := Vector3(p2.x, gy + size.y + 1.1, p2.y)
		if style == "tower":
			top.y += 4.0
		var center := top + Vector3(0, sign_h * 0.5 + 1.2, 0) + dir * (minf(size.x, size.z) * 0.25)
		_add_sign(center, dir, sign_w, sign_h, BrandArt.Design.LOGO_ON_BLUE)
	if b.has("garage"):
		# Faixa grande "UNIVERSO KART" na fachada dos boxes.
		var dir2 := Vector3(to_track.x, 0, to_track.z).normalized()
		var c2 := Vector3(p2.x, gy + size.y + 3.2, p2.y) + dir2 * (size.z * 0.5 - 1.0)
		_add_sign(c2, dir2, 36.0, 4.5, BrandArt.Design.TITLE_ON_DARK)


func _dir_to_track(p: Vector3, path: TrackPath) -> Vector3:
	var off := path.get_closest_offset(p)
	return (path.get_point_at(off) - p).normalized()


## Placa retangular com moldura, voltada para `facing`.
func _add_sign(center: Vector3, facing: Vector3, w: float, h: float, design: BrandArt.Design) -> void:
	var rot := Basis.looking_at(-facing, Vector3.UP)
	var frame := MeshKit.new()
	var xf := Transform3D(rot, center)
	frame.box(xf.translated_local(Vector3(0, 0, -0.25)), Vector3(w + 0.8, h + 0.8, 0.4), Color(0.12, 0.12, 0.14))
	for sx: float in [-0.35, 0.35]:
		frame.box(xf.translated_local(Vector3(sx * w, -h * 0.5 - 1.0, -0.4)), Vector3(0.35, 2.4, 0.35), Color(0.3, 0.3, 0.33))
	var fmi := MeshInstance3D.new()
	fmi.mesh = frame.commit(null, PROPS_MAT)
	add_child(fmi)
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var qmi := MeshInstance3D.new()
	qmi.mesh = q
	qmi.material_override = _brand.get_material(design)
	qmi.transform = xf.translated_local(Vector3(0, 0, -0.03))
	# QuadMesh olha para +Z; nosso "frente" é -Z do rot (looking_at(-facing) => +Z = facing).
	add_child(qmi)


# ------------------------------------------------------------------ boxes (garagens)

func _build_pits(c: Vector3, length: float, depth: float) -> void:
	c.y = _ground(c.x, c.z)
	var front := c.z + depth * 0.5   # fachada voltada para a reta (+Z)
	var gf := 5.4                     # altura do térreo (garagens)
	var h := gf + 4.4
	var body := MeshKit.new()
	var xf := Transform3D(Basis.IDENTITY, c)
	body.rounded_prism(xf.translated(Vector3(0, -3.0, 0)), length + 1.0, depth + 1.0, 3.3, 1.2, 4, PLAIN, ROOF)
	body.rounded_prism(xf.translated(Vector3(0, 0.0, -1.2)), length, depth - 2.4, h, 1.0, 4, WALL, ROOF)
	body.rounded_prism(xf.translated(Vector3(0, h, -1.2)), length + 0.8, depth - 1.6, 1.0, 1.4, 4, ACCENT, ROOF)
	for k in 5:
		body.box(xf.translated(Vector3(-length * 0.4 + float(k) * length * 0.2, h + 1.8, -3.0)), Vector3(5.0, 1.6, 3.0), ROOF)
	var bmi := MeshInstance3D.new()
	bmi.name = "Boxes"
	bmi.mesh = body.commit(null, BUILDING_MAT)
	bmi.set_instance_shader_parameter(&"wall_color", Color(0.97, 0.97, 0.99))
	bmi.set_instance_shader_parameter(&"accent_color", Palette.BLUE)
	bmi.set_instance_shader_parameter(&"curtain_wall", 1.0)
	bmi.set_instance_shader_parameter(&"window_params", Vector4(2.4, 4.4, 0.92, 0.85))
	bmi.set_instance_shader_parameter(&"ground_floor", gf)
	bmi.set_instance_shader_parameter(&"glass_color", Color(0.2, 0.38, 0.66))
	add_child(bmi)
	# Térreo recuado: garagens com portas de enrolar, pilastras e marquise.
	var kit := MeshKit.new()
	var recess_z := front - 1.2
	var bays := 10
	var bay_w := length / float(bays)
	var door_cols: Array[Color] = [Palette.BLUE, Palette.MAGENTA, Palette.YELLOW, Color(0.1, 0.1, 0.12)]
	var open_bays: Array[int] = [2, 5, 8]
	for b in bays:
		var bx := c.x - length * 0.5 + (float(b) + 0.5) * bay_w
		var door_w := bay_w - 1.1
		if open_bays.has(b):
			# Porta aberta: interior escuro com bancadas e ferramentas.
			kit.box(Transform3D(Basis.IDENTITY, Vector3(bx, c.y + 2.2, recess_z - 0.6)), Vector3(door_w, 4.4, 0.2), Color(0.3, 0.32, 0.38))
			# Prateleiras com pneus, faixa de luz no teto e piso claro.
			for sh in 2:
				var sy := c.y + 1.3 + float(sh) * 1.4
				kit.box(Transform3D(Basis.IDENTITY, Vector3(bx, sy, recess_z - 0.35)), Vector3(door_w - 0.8, 0.08, 0.5), Color(0.85, 0.86, 0.9))
				for tk in 4:
					kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(bx - door_w * 0.3 + float(tk) * 0.75, sy + 0.34, recess_z - 0.1)), 0.3, 0.3, 0.26, 10, Color(0.08, 0.08, 0.09), true)
			kit.box(Transform3D(Basis.IDENTITY, Vector3(bx, c.y + 4.3, recess_z - 0.3)), Vector3(door_w - 1.0, 0.1, 0.4), Color(1.0, 1.0, 0.95))
			kit.box(Transform3D(Basis.IDENTITY, Vector3(bx, c.y + 0.02, recess_z + 0.4)), Vector3(door_w, 0.04, 1.8), Color(0.7, 0.72, 0.76))
			kit.box(Transform3D(Basis.IDENTITY, Vector3(bx - door_w * 0.3, c.y + 0.55, recess_z - 0.3)), Vector3(2.4, 1.1, 0.5), Palette.MAGENTA)
			kit.box(Transform3D(Basis.IDENTITY, Vector3(bx + door_w * 0.25, c.y + 0.9, recess_z - 0.3)), Vector3(1.6, 1.8, 0.5), Palette.BLUE)
			kit.box(Transform3D(Basis.IDENTITY, Vector3(bx, c.y + 4.25, recess_z + 0.02)), Vector3(door_w, 0.3, 0.2), Color(0.8, 0.8, 0.82))
		else:
			kit.box(Transform3D(Basis.IDENTITY, Vector3(bx, c.y + 2.2, recess_z)), Vector3(door_w, 4.4, 0.16), Color(0.82, 0.83, 0.86))
			for rib in 9:
				kit.box(Transform3D(Basis.IDENTITY, Vector3(bx, c.y + 0.35 + float(rib) * 0.45, recess_z + 0.1)), Vector3(door_w, 0.06, 0.05), Color(0.6, 0.62, 0.66))
			kit.box(Transform3D(Basis.IDENTITY, Vector3(bx, c.y + 3.9, recess_z + 0.1)), Vector3(door_w, 0.55, 0.06), door_cols[b % door_cols.size()])
	# Pilastras entre as baias (recuo aparente).
	for b in bays + 1:
		var px := c.x - length * 0.5 + float(b) * bay_w
		kit.box(Transform3D(Basis.IDENTITY, Vector3(px, c.y + gf * 0.5 - 0.3, front - 0.55)), Vector3(1.0, gf + 0.6, 1.4), Palette.BLUE)
	# Marquise com testeira magenta.
	kit.box(Transform3D(Basis.IDENTITY, Vector3(c.x, c.y + gf + 0.2, front + 1.0)), Vector3(length + 1.2, 0.4, 4.4), Color(0.95, 0.95, 0.97))
	kit.box(Transform3D(Basis.IDENTITY, Vector3(c.x, c.y + gf + 0.2, front + 3.25)), Vector3(length + 1.2, 0.9, 0.2), Palette.MAGENTA)
	# Brises verticais no andar de cima.
	var fins := int(length / 2.4)
	for f in fins + 1:
		var fx := c.x - length * 0.5 + float(f) * (length / float(fins))
		kit.box(Transform3D(Basis.IDENTITY, Vector3(fx, c.y + gf + 2.6, front - 1.9)), Vector3(0.16, 3.8, 0.9), Color(0.96, 0.96, 0.98))
	# Mureta dos boxes (pit wall) com faixa amarela.
	kit.box(Transform3D(Basis.IDENTITY, Vector3(c.x, c.y + 0.45, front + 6.0)), Vector3(length, 0.9, 0.5), Color(0.85, 0.85, 0.87))
	kit.box(Transform3D(Basis.IDENTITY, Vector3(c.x, c.y + 0.95, front + 6.0)), Vector3(length, 0.12, 0.55), Palette.YELLOW)
	var gmi := MeshInstance3D.new()
	gmi.name = "BoxesFachada"
	gmi.mesh = kit.commit(null, PROPS_MAT)
	add_child(gmi)
	# Placas das equipes na testeira + letreiro grande na cobertura.
	var q := QuadMesh.new()
	q.size = Vector2(4.0, 0.8)
	for b in bays:
		var bx := c.x - length * 0.5 + (float(b) + 0.5) * bay_w
		var tq := MeshInstance3D.new()
		tq.mesh = q
		tq.material_override = _brand.get_material(BrandArt.BANNER_ROTATION[b % BrandArt.BANNER_ROTATION.size()])
		tq.position = Vector3(bx, c.y + gf + 0.2, front + 3.37)
		tq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(tq)
	_add_sign(Vector3(c.x, c.y + h + 3.6, front - 3.0), Vector3(0, 0, 1), 36.0, 4.5, BrandArt.Design.TITLE_ON_DARK)
	_site.add_blocker(Vector2(c.x - length * 0.3, c.z), depth + 8.0)
	_site.add_blocker(Vector2(c.x, c.z), depth + 8.0)
	_site.add_blocker(Vector2(c.x + length * 0.3, c.z), depth + 8.0)


# ------------------------------------------------------------------ calçadas do campus

## Caminhos (polilinhas x,z) ligando arquibancada, alameda e prédios.
var walkways: Array[PackedVector2Array] = [
	PackedVector2Array([Vector2(-230, 160), Vector2(-120, 158), Vector2(0, 162), Vector2(120, 158), Vector2(235, 162)]),
	PackedVector2Array([Vector2(-1, 50), Vector2(-8, 95), Vector2(-40, 130), Vector2(-45, 160)]),
	PackedVector2Array([Vector2(-150, 118), Vector2(-150, 160)]),
	PackedVector2Array([Vector2(58, 142), Vector2(58, 160)]),
	PackedVector2Array([Vector2(150, 108), Vector2(152, 160)]),
	PackedVector2Array([Vector2(95, 160), Vector2(95, 185)]),
	PackedVector2Array([Vector2(-215, 160), Vector2(-215, 170)]),
	PackedVector2Array([Vector2(-70, 160), Vector2(-70, 196)]),
	PackedVector2Array([Vector2(200, 160), Vector2(212, 152)]),
	PackedVector2Array([Vector2(40, 52), Vector2(45, 100), Vector2(58, 108)]),
]


func _build_walkways() -> void:
	var kit := MeshKit.new()
	var col := Color(0.6, 0.58, 0.55)
	var edge := Color(0.45, 0.44, 0.42)
	var half := 2.3
	for line in walkways:
		# Reamostra a cada ~3 m.
		var pts := PackedVector2Array()
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var n := maxi(1, ceili(a.distance_to(b) / 3.0))
			for k in n:
				pts.append(a.lerp(b, float(k) / float(n)))
		pts.append(line[line.size() - 1])
		var base := kit.vertex_count()
		for i in pts.size():
			var prev := pts[maxi(i - 1, 0)]
			var next := pts[mini(i + 1, pts.size() - 1)]
			var d := (next - prev).normalized()
			var side := Vector2(-d.y, d.x)
			var p := pts[i]
			var l := p + side * half
			var r := p - side * half
			var hl := _ground(l.x, l.y) + 0.07
			var hr := _ground(r.x, r.y) + 0.07
			kit.add_vertex(Vector3(l.x, hl, l.y), Vector3.UP, Vector2.ZERO, col)
			kit.add_vertex(Vector3(r.x, hr, r.y), Vector3.UP, Vector2.ZERO, col)
			if i % 3 == 0:
				_site.add_blocker(p, half + 1.0)
		for i in pts.size() - 1:
			var a0 := base + i * 2
			kit.quad(a0, a0 + 2, a0 + 1, a0 + 3)
		# Meio-fio nas bordas.
		for s: float in [1.0, -1.0]:
			var b2 := kit.vertex_count()
			for i in pts.size():
				var prev := pts[maxi(i - 1, 0)]
				var next := pts[mini(i + 1, pts.size() - 1)]
				var d := (next - prev).normalized()
				var side := Vector2(-d.y, d.x) * s
				var p := pts[i] + side * half
				var p2 := pts[i] + side * (half + 0.35)
				var h := _ground(p.x, p.y) + 0.1
				kit.add_vertex(Vector3(p.x, h, p.y), Vector3.UP, Vector2.ZERO, edge)
				kit.add_vertex(Vector3(p2.x, _ground(p2.x, p2.y) + 0.1, p2.y), Vector3.UP, Vector2.ZERO, edge)
			for i in pts.size() - 1:
				var a0 := b2 + i * 2
				kit.quad(a0, a0 + 2, a0 + 1, a0 + 3)
	var mi := MeshInstance3D.new()
	mi.name = "Calcadas"
	mi.mesh = kit.commit(null, PROPS_MAT)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------------ planetário

func _build_planetarium(c: Vector3) -> void:
	c.y = _ground(c.x, c.z)
	var kit := MeshKit.new()
	var base_col := Color(0.86, 0.86, 0.88)
	# Plataforma em degraus.
	kit.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, -2, 0)), 23.5, 23.5, 2.3, 56, Color(0.6, 0.6, 0.62), true)
	kit.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, -2, 0)), 21.0, 21.0, 2.7, 56, base_col, true)
	kit.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, 6.1, 0)), 17.7, 17.7, 0.8, 56, Palette.YELLOW, true)
	# Entrada com marquise, voltada para a reta (+Z).
	var ent := Transform3D(Basis.IDENTITY, c + Vector3(0, 0.6, 17.6))
	kit.box(ent.translated(Vector3(0, 2.0, 1.2)), Vector3(9.0, 4.0, 2.6), Color(0.12, 0.2, 0.4))
	kit.box(ent.translated(Vector3(0, 4.3, 2.8)), Vector3(12.0, 0.5, 5.0), Palette.MAGENTA)
	for sx: float in [-5.4, 5.4]:
		kit.cylinder(Transform3D(Basis.IDENTITY, ent.origin + Vector3(sx, -0.1, 4.8)), 0.22, 0.22, 4.2, 10, Color(0.95, 0.95, 0.97), false)
	var mi := MeshInstance3D.new()
	mi.name = "Planetario"
	mi.mesh = kit.commit(null, PROPS_MAT)
	add_child(mi)
	# Tambor com faixa de constelações.
	var drum := MeshKit.new()
	drum.cylinder(Transform3D(Basis.IDENTITY, c + Vector3(0, 0.6, 0)), 17.0, 17.0, 5.5, 64, Color.WHITE, false)
	var star_mat := ShaderMaterial.new()
	star_mat.shader = STAR_SHADER
	var dmi := MeshInstance3D.new()
	dmi.name = "FaixaEstrelas"
	dmi.mesh = drum.commit(null, star_mat)
	add_child(dmi)
	# Cúpula perolada com gomos.
	var dome := MeshKit.new()
	dome.sphere(Transform3D(Basis.IDENTITY, Vector3.ZERO), 16.2, 18, 48, Color.WHITE, 0.0)
	for i in dome.verts.size():
		var v := dome.verts[i]
		if v.y < 0.0:
			dome.verts[i] = Vector3(v.x, 0.0, v.z)
	var dome_mat := ShaderMaterial.new()
	dome_mat.shader = DOME_SHADER
	var cmi := MeshInstance3D.new()
	cmi.name = "Cupula"
	cmi.mesh = dome.commit(null, dome_mat)
	cmi.position = c + Vector3(0, 6.9, 0)
	add_child(cmi)
	# Anel orbital inclinado + "planeta".
	var ring := TorusMesh.new()
	ring.inner_radius = 22.5
	ring.outer_radius = 24.0
	ring.rings = 96
	ring.ring_segments = 12
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Palette.MAGENTA
	rmat.roughness = 0.35
	rmat.metallic = 0.25
	rmat.metallic_specular = 0.4
	var rmi := MeshInstance3D.new()
	rmi.name = "AnelOrbital"
	rmi.mesh = ring
	rmi.material_override = rmat
	rmi.transform = Transform3D(Basis(Vector3(1, 0, 0.3).normalized(), deg_to_rad(16.0)), c + Vector3(0, 12.5, 0))
	add_child(rmi)
	var planet := SphereMesh.new()
	planet.radius = 2.3
	planet.height = 4.6
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Palette.YELLOW
	pmat.roughness = 0.4
	pmat.emission_enabled = true
	pmat.emission = Palette.YELLOW
	pmat.emission_energy_multiplier = 0.2
	var pmi := MeshInstance3D.new()
	pmi.mesh = planet
	pmi.material_override = pmat
	var ang := deg_to_rad(35.0)
	pmi.position = rmi.transform * Vector3(cos(ang) * 23.25, 0, sin(ang) * 23.25)
	add_child(pmi)
	_add_sign(c + Vector3(0, 7.3, 22.4), Vector3(0, 0, 1), 11.0, 2.75, BrandArt.Design.LOGO_ON_WHITE)
	_site.add_blocker(Vector2(c.x, c.z), 30.0)


# ------------------------------------------------------------------ complexo esportivo

func _build_sports_complex(c: Vector3) -> void:
	c.y = _ground(c.x, c.z) + 0.04
	var kit := MeshKit.new()
	var terracotta := Color(0.78, 0.34, 0.24)
	var white := Color(0.97, 0.97, 0.97)
	var up := Vector3.UP
	# Pista de atletismo (anel estádio).
	var outer := MeshKit.rounded_rect_outline(96.0, 64.0, 31.9, 16)
	var inner := MeshKit.rounded_rect_outline(80.0, 48.0, 23.9, 16)
	var n := outer.size()
	var base := kit.vertex_count()
	for i in n:
		kit.add_vertex(c + outer[i], up, Vector2.ZERO, terracotta)
		kit.add_vertex(c + inner[i], up, Vector2.ZERO, terracotta)
	for i in n:
		var a := base + i * 2
		var b := base + ((i + 1) % n) * 2
		kit.quad(a, b, a + 1, b + 1)
	# Linhas das raias.
	for k in 3:
		var w := 82.0 + float(k + 1) * 3.5
		var d := 50.0 + float(k + 1) * 3.5
		var ln := MeshKit.rounded_rect_outline(w, d, d * 0.5 - 0.05, 16)
		var ln2 := MeshKit.rounded_rect_outline(w - 0.3, d - 0.3, d * 0.5 - 0.2, 16)
		var b0 := kit.vertex_count()
		for i in ln.size():
			kit.add_vertex(c + ln[i] + up * 0.02, up, Vector2.ZERO, white)
			kit.add_vertex(c + ln2[i] + up * 0.02, up, Vector2.ZERO, white)
		for i in ln.size():
			var a := b0 + i * 2
			var b := b0 + ((i + 1) % ln.size()) * 2
			kit.quad(a, b, a + 1, b + 1)
	# Linhas do campo de futebol (60 x 38).
	var fw := 60.0
	var fd := 38.0
	var lw := 0.25
	var y := up * 0.02
	var lines: Array[Rect2] = [
		Rect2(-fw * 0.5, -fd * 0.5, fw, lw), Rect2(-fw * 0.5, fd * 0.5 - lw, fw, lw),
		Rect2(-fw * 0.5, -fd * 0.5, lw, fd), Rect2(fw * 0.5 - lw, -fd * 0.5, lw, fd),
		Rect2(-lw * 0.5, -fd * 0.5, lw, fd),
		Rect2(-fw * 0.5, -8.0, 9.0, lw), Rect2(-fw * 0.5, 8.0, 9.0, lw), Rect2(-fw * 0.5 + 9.0, -8.0, lw, 16.0),
		Rect2(fw * 0.5 - 9.0, -8.0, 9.0, lw), Rect2(fw * 0.5 - 9.0, 8.0, 9.0, lw), Rect2(fw * 0.5 - 9.0 - lw, -8.0, lw, 16.0),
	]
	for r in lines:
		kit.flat_quad(c + y + Vector3(r.position.x, 0, r.position.y), c + y + Vector3(r.position.x + r.size.x, 0, r.position.y),
			c + y + Vector3(r.position.x + r.size.x, 0, r.position.y + r.size.y), c + y + Vector3(r.position.x, 0, r.position.y + r.size.y), up, white)
	# Círculo central.
	var segs := 40
	var cb := kit.vertex_count()
	for i in segs:
		var a := TAU * float(i) / float(segs)
		kit.add_vertex(c + y + Vector3(cos(a), 0, sin(a)) * 6.0, up, Vector2.ZERO, white)
		kit.add_vertex(c + y + Vector3(cos(a), 0, sin(a)) * 5.75, up, Vector2.ZERO, white)
	for i in segs:
		var a := cb + i * 2
		var b := cb + ((i + 1) % segs) * 2
		kit.quad(a, b, a + 1, b + 1)
	# Traves.
	for sx: float in [-1.0, 1.0]:
		var gx := c + Vector3(sx * fw * 0.5, 0, 0)
		for sz: float in [-1.0, 1.0]:
			kit.cylinder(Transform3D(Basis.IDENTITY, gx + Vector3(0, 0, sz * 3.66)), 0.1, 0.1, 2.44, 8, white, true)
		kit.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), gx + Vector3(0, 2.44, -3.66)), 0.1, 0.1, 7.32, 8, white, true)
	var mi := MeshInstance3D.new()
	mi.name = "ComplexoEsportivo"
	mi.mesh = kit.commit(null, PROPS_MAT)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_site.add_blocker(Vector2(c.x, c.z), 50.0)
