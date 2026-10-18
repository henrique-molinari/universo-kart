class_name StartGate
extends Node3D
## Pórtico de largada/chegada: pilares arredondados, viga com painel UNIVERSO KART + logos
## UNIFEOB, letreiro 3D no topo e semáforo de largada (usado pela contagem regressiva).

const PROPS_MAT := preload("res://assets/materials/painted_props.tres")
const TITLE_FONT := preload("res://assets/fonts/title_font.tres")

const LAMP_COUNT := 4
const BEAM_BOTTOM := 7.6
const BEAM_HEIGHT := 3.4

var lamps: Array[MeshInstance3D] = []
var _lamp_colors: Array[Color] = [Color(1, 0.12, 0.1), Color(1, 0.12, 0.1), Color(1, 0.12, 0.1), Color(0.2, 1.0, 0.35)]


func build(path: TrackPath, brand: BrandArt) -> void:
	transform = path.get_transform_at(0.0)
	var span := path.get_wall_lateral() + 2.4
	var kit := MeshKit.new()
	var blue := Palette.BLUE
	var magenta := Palette.MAGENTA
	var white := Color(0.97, 0.97, 1.0)
	var ground := -0.8
	for sx: float in [-1.0, 1.0]:
		var base := Vector3(sx * span, ground, 0)
		kit.rounded_prism(Transform3D(Basis.IDENTITY, base), 3.4, 3.4, 1.4, 0.9, 5, magenta, magenta)
		kit.rounded_prism(Transform3D(Basis.IDENTITY, base), 2.6, 2.6, BEAM_BOTTOM + BEAM_HEIGHT + 0.6 - ground, 0.8, 6, blue, white)
		# Anéis decorativos amarelos.
		for k in 3:
			kit.rounded_prism(Transform3D(Basis.IDENTITY, base + Vector3(0, 2.2 + k * 1.6, 0)), 2.75, 2.75, 0.3, 0.85, 6, Palette.YELLOW, Palette.YELLOW)
	# Viga: prisma arredondado deitado (altura do prisma -> eixo X).
	var beam_len := span * 2.0 + 2.6
	var beam_basis := Basis(Vector3.FORWARD, PI * 0.5)
	var beam_xf := Transform3D(beam_basis, Vector3(-beam_len * 0.5, BEAM_BOTTOM + BEAM_HEIGHT * 0.5, 0))
	kit.rounded_prism(beam_xf, BEAM_HEIGHT, 2.4, beam_len, 0.9, 6, white, white)
	# Caixa do semáforo sob a viga.
	kit.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(0, BEAM_BOTTOM - 1.5, 0)), 7.0, 1.2, 1.55, 0.45, 4, Palette.GRAPHITE, Palette.GRAPHITE)
	kit.box(Transform3D(Basis.IDENTITY, Vector3(-2.0, BEAM_BOTTOM - 0.2, 0)), Vector3(0.25, 0.6, 0.25), Palette.GRAPHITE)
	kit.box(Transform3D(Basis.IDENTITY, Vector3(2.0, BEAM_BOTTOM - 0.2, 0)), Vector3(0.25, 0.6, 0.25), Palette.GRAPHITE)
	var mi := MeshInstance3D.new()
	mi.name = "Estrutura"
	mi.mesh = kit.commit(null, PROPS_MAT)
	add_child(mi)

	# Painéis dos dois lados da viga.
	var panel := QuadMesh.new()
	panel.size = Vector2(beam_len - 3.2, BEAM_HEIGHT - 0.5)
	for side: float in [1.0, -1.0]:
		var q := MeshInstance3D.new()
		q.name = "Painel" + ("Frente" if side > 0.0 else "Tras")
		q.mesh = panel
		q.material_override = brand.get_material(BrandArt.Design.GATE)
		var rot := Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
		q.transform = Transform3D(rot, Vector3(0, BEAM_BOTTOM + BEAM_HEIGHT * 0.5, side * 1.215))
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
	# Logos nos pilares (frente e trás).
	var logo_q := QuadMesh.new()
	logo_q.size = Vector2(2.3, 2.3)
	for sx: float in [-1.0, 1.0]:
		for side: float in [1.0, -1.0]:
			var lq := MeshInstance3D.new()
			lq.mesh = logo_q
			lq.material_override = brand.get_material(BrandArt.Design.SQUARE_LOGO)
			var rot2 := Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
			lq.transform = Transform3D(rot2, Vector3(sx * span, 5.6, side * 1.32))
			lq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(lq)
	_build_title()
	_build_lamps()
	_build_fill_light()


## Luz de preenchimento frontal: o sol bate de lado na face do pórtico e escurecia a marca
## (letreiro saía cáqui). Sem sombra e com alcance curto — custo desprezível.
func _build_fill_light() -> void:
	for side: float in [1.0, -1.0]:
		var spot := SpotLight3D.new()
		spot.name = "FillFrente" if side > 0.0 else "FillTras"
		spot.light_color = Color(1.0, 0.98, 0.94)
		spot.light_energy = 3.2
		spot.spot_range = 38.0
		spot.spot_angle = 28.0
		spot.spot_attenuation = 0.6
		spot.shadow_enabled = false
		spot.light_specular = 0.2
		var pos := Vector3(0.0, 4.0, side * 22.0)
		var target := Vector3(0.0, BEAM_BOTTOM + BEAM_HEIGHT + 0.6, 0.0)
		spot.transform = Transform3D(Basis.looking_at(target - pos, Vector3.UP), pos)
		add_child(spot)


func _build_title() -> void:
	var tm := TextMesh.new()
	tm.text = BrandArt.TITLE
	tm.font = TITLE_FONT
	tm.font_size = 96
	tm.pixel_size = 0.022
	tm.depth = 0.35
	tm.curve_step = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Palette.YELLOW
	mat.roughness = 0.35
	mat.metallic_specular = 0.6
	tm.material = mat
	# Placa com espessura (caixa arredondada fechada) e letreiro 3D nos DOIS lados (legível de frente e de trás).
	var y := BEAM_BOTTOM + BEAM_HEIGHT + 1.25
	var aabb := tm.get_aabb()
	var pw := aabb.size.x + 1.6
	var ph := aabb.size.y + 0.9
	var thick := 0.6
	var plate := MeshKit.new()
	plate.rounded_prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, y, -thick * 0.5)), pw, ph, thick, 0.8, 6, Palette.MAGENTA, Palette.MAGENTA, true)
	for sx: float in [-0.3, 0.3]:
		plate.box(Transform3D(Basis.IDENTITY, Vector3(pw * sx, y - ph * 0.5 - 0.3, 0.0)), Vector3(0.35, 0.8, 0.35), Palette.GRAPHITE)
	var pmi := MeshInstance3D.new()
	pmi.name = "PlacaTitulo"
	pmi.mesh = plate.commit(null, PROPS_MAT)
	add_child(pmi)
	for side: float in [1.0, -1.0]:
		var t := MeshInstance3D.new()
		t.name = "Titulo3D_" + ("Frente" if side > 0.0 else "Tras")
		t.mesh = tm
		var rot := Basis.IDENTITY if side > 0.0 else Basis(Vector3.UP, PI)
		t.transform = Transform3D(rot, Vector3(0, y, side * (thick * 0.5 + tm.depth * 0.5)))
		add_child(t)


func _build_lamps() -> void:
	var holder := Node3D.new()
	holder.name = "StartLights"
	holder.position = Vector3(0, BEAM_BOTTOM - 0.72, 0)
	add_child(holder)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 20
	sphere.rings = 10
	for i in LAMP_COUNT:
		# Lente de vidro colorido (brilhante, com leve brilho mesmo apagada).
		var m := StandardMaterial3D.new()
		m.albedo_color = _lamp_colors[i].darkened(0.75)
		m.roughness = 0.06
		m.metallic = 0.15
		m.metallic_specular = 0.9
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.05
		m.rim_enabled = true
		m.rim = 0.35
		m.emission_enabled = true
		m.emission = _lamp_colors[i]
		m.emission_energy_multiplier = 0.15
		var lamp := MeshInstance3D.new()
		lamp.name = "Lamp%d" % i
		lamp.mesh = sphere
		lamp.material_override = m
		lamp.position = Vector3((float(i) - (LAMP_COUNT - 1) * 0.5) * 1.55, 0, 0.35)
		holder.add_child(lamp)
		# Viseira sobre cada lente.
		var hood := MeshKit.new()
		hood.cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(lamp.position.x, 0.0, 0.2)), 0.56, 0.56, 0.5, 18, Palette.GRAPHITE, false)
		var hmi := MeshInstance3D.new()
		hmi.mesh = hood.commit(null, PROPS_MAT)
		holder.add_child(hmi)
		lamps.append(lamp)


## Acende as `count` primeiras luzes (0 = todas apagadas). Usado na contagem regressiva.
func set_lights(count: int) -> void:
	for i in lamps.size():
		var m := lamps[i].material_override as StandardMaterial3D
		var on := i < count
		m.emission_energy_multiplier = 6.0 if on else 0.15
		m.albedo_color = _lamp_colors[i] if on else _lamp_colors[i].darkened(0.75)
