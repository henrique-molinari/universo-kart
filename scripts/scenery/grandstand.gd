class_name Grandstand
extends Node3D
## Arquibancada coberta com público animado (MultiMesh), junto à reta principal.

const PROPS_MAT := preload("res://assets/materials/painted_props.tres")
const CROWD_SHADER := preload("res://assets/shaders/crowd.gdshader")

const SHIRTS: Array[Color] = [
	Color(0.0, 0.094, 0.996), Color(1.0, 0.094, 0.388), Color(0.957, 0.906, 0.153),
	Color(0.97, 0.97, 1.0), Color(0.1, 0.1, 0.12), Color(0.2, 0.75, 0.4),
	Color(1.0, 0.5, 0.1), Color(0.0, 0.094, 0.996), Color(1.0, 0.094, 0.388),
]

@export var length: float = 96.0
@export var rows: int = 12
@export var row_depth: float = 0.85
@export var row_rise: float = 0.5
@export var first_row_height: float = 2.4

var crowd_material: ShaderMaterial
var crowd_count: int = 0


## `xf`: base local (X = ao longo da pista, +Z = para longe da pista, origem = centro da frente, no chão).
func build(xf: Transform3D, brand: BrandArt, site: SiteMap) -> void:
	transform = xf
	var kit := MeshKit.new()
	var concrete := Color(0.84, 0.84, 0.86)
	var blue := Palette.BLUE
	var half := length * 0.5
	var seat_cols: Array[Color] = [Palette.BLUE, Palette.MAGENTA, Palette.BLUE, Palette.YELLOW]
	# Muro frontal.
	kit.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0.3)), Vector3(length, 3.8, 0.6), blue)
	# Degraus + assentos.
	var z0 := 0.6
	for r in rows:
		var y := first_row_height + r * row_rise
		var zr := z0 + r * row_depth
		kit.box(Transform3D(Basis.IDENTITY, Vector3(0, (y - 1.0) * 0.5, zr + row_depth * 0.5)), Vector3(length, y + 1.0, row_depth), concrete)
		var sections := 8
		var sw := length / float(sections)
		for s in sections:
			var sx := -half + (float(s) + 0.5) * sw
			kit.box(Transform3D(Basis.IDENTITY, Vector3(sx, y + 0.14, zr + row_depth * 0.62)), Vector3(sw - 1.3, 0.28, 0.36), seat_cols[s % seat_cols.size()])
	var top_y := first_row_height + (rows - 1) * row_rise
	var back_z := z0 + rows * row_depth
	# Parede de fundo e laterais.
	kit.box(Transform3D(Basis.IDENTITY, Vector3(0, (top_y + 3.0 - 1.0) * 0.5, back_z + 0.25)), Vector3(length + 1.0, top_y + 4.0, 0.5), blue)
	# Laterais em rampa acompanhando os degraus, com friso azul no topo e pilastras.
	var side_poly := PackedVector2Array([Vector2(-0.1, -0.8), Vector2(back_z + 0.5, -0.8), Vector2(back_z + 0.5, top_y + 3.4), Vector2(-0.1, 3.1)])
	var side_col := Color(0.86, 0.88, 1.0)
	for sx: float in [-1.0, 1.0]:
		_side_panel(kit, sx * (half + 0.3), 0.6, side_poly, side_col)
		var a := Vector3(sx * (half + 0.3), 3.1, -0.1)
		var b := Vector3(sx * (half + 0.3), top_y + 3.4, back_z + 0.5)
		var d := b - a
		kit.box(Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), (a + b) * 0.5 + Vector3(0, 0.15, 0)), Vector3(0.8, 0.35, d.length() + 0.4), blue)
		for k in 3:
			var pz := lerpf(0.8, back_z - 0.4, float(k) / 2.0)
			var ph := lerpf(3.1, top_y + 3.4, pz / (back_z + 0.5)) + 0.7
			kit.box(Transform3D(Basis.IDENTITY, Vector3(sx * (half + 0.62), (ph - 0.8) * 0.5 - 0.4, pz)), Vector3(0.12, ph + 0.4, 0.7), blue)
	# Pilares traseiros e cobertura em balanço (inclinada para a pista).
	var roof_front_y := top_y + 6.2
	var roof_back_y := top_y + 5.0
	var roof_depth := back_z + 3.0
	var ang := atan2(roof_front_y - roof_back_y, roof_depth)
	var roof_c := Vector3(0, (roof_front_y + roof_back_y) * 0.5, back_z + 0.5 - roof_depth * 0.5)
	kit.box(Transform3D(Basis(Vector3.RIGHT, ang), roof_c), Vector3(length + 4.0, 0.45, roof_depth), Palette.LAVENDER)
	var col_count := 9
	for i in col_count:
		var cx := -half + length * float(i) / float(col_count - 1)
		kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(cx, -0.5, back_z + 0.7)), 0.35, 0.3, roof_back_y + 0.6, 10, Color(0.9, 0.9, 0.93), false)
	# Forro sob a cobertura com gradiente de oclusão (mais escuro junto ao fundo).
	var roof_xf := Transform3D(Basis(Vector3.RIGHT, ang), roof_c)
	var under_n := (roof_xf.basis * Vector3.DOWN).normalized()
	var hl := (length + 4.0) * 0.5
	var hd := roof_depth * 0.5
	var dark := Color(0.46, 0.48, 0.6)
	var light := Color(0.8, 0.82, 0.95)
	var u0 := kit.add_vertex(roof_xf * Vector3(-hl, -0.24, -hd), under_n, Vector2.ZERO, light)
	var u1 := kit.add_vertex(roof_xf * Vector3(hl, -0.24, -hd), under_n, Vector2.ZERO, light)
	var u2 := kit.add_vertex(roof_xf * Vector3(hl, -0.24, hd), under_n, Vector2.ZERO, dark)
	var u3 := kit.add_vertex(roof_xf * Vector3(-hl, -0.24, hd), under_n, Vector2.ZERO, dark)
	kit.tri(u0, u1, u2)
	kit.tri(u0, u2, u3)
	# Treliças: vigas em balanço sobre cada pilar + tirantes + terças longitudinais.
	var steel := Color(0.3, 0.36, 0.48)
	for i in col_count:
		var cx := -half + length * float(i) / float(col_count - 1)
		var beam_a := roof_xf * Vector3(cx, -0.75, hd - 0.2)
		var beam_b := roof_xf * Vector3(cx, -0.55, -hd + 0.4)
		var bd := beam_b - beam_a
		var bb := Basis.looking_at(bd.normalized(), Vector3.UP)
		kit.box(Transform3D(bb, (beam_a + beam_b) * 0.5), Vector3(0.35, 0.9 - 0.0, bd.length()), steel)
		var tie_a := Vector3(cx, roof_back_y - 3.5, back_z + 0.7)
		var tie_b := roof_xf * Vector3(cx, -0.8, -hd * 0.25)
		var td := tie_b - tie_a
		kit.cylinder(Transform3D(Basis.looking_at(td.normalized(), Vector3.RIGHT) * Basis(Vector3.RIGHT, -PI * 0.5), tie_a), 0.09, 0.09, td.length(), 6, steel, false)
	for k in 4:
		var zz := lerpf(-hd + 1.0, hd - 1.0, float(k) / 3.0)
		kit.box(roof_xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.45, zz)), Vector3(length + 3.0, 0.28, 0.28), steel)
	# Fundo: pilastras, faixa de janelas, portões de acesso.
	for i in 9:
		var px := -half + length * float(i) / 8.0
		kit.box(Transform3D(Basis.IDENTITY, Vector3(px, (top_y + 3.0) * 0.5 - 0.5, back_z + 0.62)), Vector3(1.0, top_y + 4.0, 0.3), Palette.BLUE.darkened(0.25))
	kit.box(Transform3D(Basis.IDENTITY, Vector3(0, top_y + 1.0, back_z + 0.52)), Vector3(length - 2.0, 1.2, 0.1), Color(0.12, 0.2, 0.4))
	# Painéis de fachada: faixa branca com juntas, faixa magenta e rodapé cinza.
	kit.box(Transform3D(Basis.IDENTITY, Vector3(0, top_y - 4.6, back_z + 0.54)), Vector3(length - 1.0, 1.6, 0.12), Color(0.93, 0.94, 0.98))
	kit.box(Transform3D(Basis.IDENTITY, Vector3(0, top_y - 5.6, back_z + 0.55)), Vector3(length - 1.0, 0.35, 0.14), Palette.MAGENTA)
	kit.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, back_z + 0.56)), Vector3(length + 1.0, 1.0, 0.16), Color(0.55, 0.56, 0.6))
	for j in 24:
		var jx := -half + (float(j) + 0.5) * length / 24.0
		kit.box(Transform3D(Basis.IDENTITY, Vector3(jx, top_y - 4.6, back_z + 0.61)), Vector3(0.06, 1.6, 0.04), Color(0.7, 0.72, 0.8))
	kit.box(Transform3D(Basis.IDENTITY, Vector3(0, top_y + 1.75, back_z + 0.55)), Vector3(length - 2.0, 0.18, 0.14), Palette.YELLOW)
	for gx: float in [-half * 0.5, half * 0.5]:
		kit.box(Transform3D(Basis.IDENTITY, Vector3(gx, 1.4, back_z + 0.53)), Vector3(6.0, 3.6, 0.1), Color(0.1, 0.1, 0.12))
		kit.box(Transform3D(Basis.IDENTITY, Vector3(gx, 3.4, back_z + 0.75)), Vector3(7.4, 0.5, 1.4), Palette.MAGENTA)
		for fx: float in [-3.3, 3.3]:
			kit.box(Transform3D(Basis.IDENTITY, Vector3(gx + fx, 1.4, back_z + 0.7)), Vector3(0.5, 3.8, 0.4), Palette.MAGENTA)
	# Praça de acesso atrás da arquibancada.
	var plaza := MeshKit.new()
	plaza.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(0, -0.45, back_z + 7.0)), length + 6.0, 12.0, 0.5, 3.0, 5, Color(0.55, 0.54, 0.52), Color(0.62, 0.6, 0.57))
	kit.append_kit(plaza)
	# Canteiros com árvores na praça de acesso.
	for i in 8:
		var tx := -half + 6.0 + float(i) * (length - 12.0) / 7.0
		if absf(absf(tx) - half * 0.5) < 5.0:
			continue
		var tp := Vector3(tx, -0.3, back_z + 10.5)
		kit.cylinder(Transform3D(Basis.IDENTITY, tp), 1.6, 1.6, 0.7, 16, Color(0.8, 0.8, 0.82), true)
		kit.cylinder(Transform3D(Basis.IDENTITY, tp + Vector3(0, 0.7, 0)), 1.45, 1.45, 0.05, 16, Color(0.36, 0.26, 0.18), true)
		kit.cylinder(Transform3D(Basis.IDENTITY, tp + Vector3(0, 0.7, 0)), 0.22, 0.16, 3.2, 8, Color(0.42, 0.28, 0.17), false)
		var leaf := Color(0.3, 0.6, 0.2) if i % 3 != 1 else Color(1.0, 0.56, 0.74)
		kit.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.9, 1)), tp + Vector3(0, 4.6, 0)), 2.2, 6, 10, leaf, 0.45)
		kit.sphere(Transform3D(Basis.IDENTITY, tp + Vector3(1.1, 4.0, 0.4)), 1.4, 5, 8, leaf, 0.45)
	# Testeira frontal da cobertura.
	var front_z := back_z + 0.5 - roof_depth
	kit.box(Transform3D(Basis(Vector3.RIGHT, ang), Vector3(0, roof_front_y - 0.3, front_z + 0.2)), Vector3(length + 4.0, 1.8, 0.4), Palette.MAGENTA)
	var mi := MeshInstance3D.new()
	mi.name = "Estrutura"
	mi.mesh = kit.commit(null, PROPS_MAT)
	add_child(mi)
	# Banners na testeira e no muro frontal (voltados para a pista: -Z local).
	var n_roof := 6
	var bw := (length + 2.0) / float(n_roof)
	for i in n_roof:
		var bx := -half - 1.0 + (float(i) + 0.5) * bw
		var d := BrandArt.Design.TITLE_ON_DARK if i % 2 == 0 else BrandArt.Design.LOGO_ON_BLUE
		_banner(Vector3(bx, roof_front_y - 0.3, front_z - 0.02), Vector2(bw - 1.2, 1.5), brand.get_material(d), ang)
	var n_front := 12
	var fw := length / float(n_front)
	for i in n_front:
		var fx := -half + (float(i) + 0.5) * fw
		var d2 := BrandArt.Design.LOGO_ON_WHITE if i % 3 != 1 else BrandArt.Design.LOGO_ON_YELLOW
		_banner(Vector3(fx, 1.95, -0.02), Vector2(fw - 0.8, 1.45), brand.get_material(d2), 0.0)
	# Logos nas laterais externas.
	for sx: float in [-1.0, 1.0]:
		var q := QuadMesh.new()
		q.size = Vector2(6.0, 6.0)
		var lq := MeshInstance3D.new()
		lq.mesh = q
		lq.material_override = brand.get_material(BrandArt.Design.SQUARE_LOGO)
		lq.transform = Transform3D(Basis(Vector3.UP, sx * PI * 0.5), Vector3(sx * (half + 0.52), top_y * 0.5 + 1.5, back_z * 0.5))
		lq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lq)
	# Banner grande no fundo, voltado para o campus.
	var back_q := QuadMesh.new()
	back_q.size = Vector2(24.0, 6.0)
	var bq := MeshInstance3D.new()
	bq.mesh = back_q
	bq.material_override = brand.get_material(BrandArt.Design.TITLE_ON_MAGENTA)
	bq.transform = Transform3D(Basis.IDENTITY, Vector3(0, top_y - 2.2, back_z + 0.8))
	bq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bq)
	for gx: float in [-half * 0.5, half * 0.5]:
		var lq2 := MeshInstance3D.new()
		var q2 := QuadMesh.new()
		q2.size = Vector2(9.0, 2.25)
		lq2.mesh = q2
		lq2.material_override = brand.get_material(BrandArt.Design.LOGO_ON_BLUE)
		lq2.transform = Transform3D(Basis.IDENTITY, Vector3(gx, 5.2, back_z + 0.62))
		add_child(lq2)
	_build_crowd()
	var c := global_transform * Vector3(0, 0, back_z * 0.5)
	site.add_blocker(Vector2(c.x, c.z), length * 0.5 + 6.0)


## Painel prismático: polígono convexo no plano (z, y) extrudado em X com espessura `thick`.
func _side_panel(kit: MeshKit, x: float, thick: float, poly: PackedVector2Array, c: Color) -> void:
	for face: float in [-1.0, 1.0]:
		var fx := x + face * thick * 0.5
		var nrm := Vector3(face, 0, 0)
		var first := kit.vertex_count()
		for q in poly:
			kit.add_vertex(Vector3(fx, q.y, q.x), nrm, Vector2.ZERO, c)
		for k in range(1, poly.size() - 1):
			kit.tri(first, first + k, first + k + 1)
	for k in poly.size():
		var a := poly[k]
		var b := poly[(k + 1) % poly.size()]
		var d := (b - a).normalized()
		var n2 := Vector2(d.y, -d.x)
		var ctr := Vector2.ZERO
		for q in poly:
			ctr += q
		ctr /= float(poly.size())
		if n2.dot((a + b) * 0.5 - ctr) < 0.0:
			n2 = -n2
		var nrm := Vector3(0, n2.y, n2.x)
		kit.flat_quad(Vector3(x - thick * 0.5, a.y, a.x), Vector3(x + thick * 0.5, a.y, a.x), Vector3(x + thick * 0.5, b.y, b.x), Vector3(x - thick * 0.5, b.y, b.x), nrm, c)


func _banner(pos: Vector3, size: Vector2, mat: Material, tilt: float) -> void:
	var q := QuadMesh.new()
	q.size = size
	var qmi := MeshInstance3D.new()
	qmi.mesh = q
	qmi.material_override = mat
	# QuadMesh olha para +Z; giramos 180° para olhar para -Z (pista).
	qmi.transform = Transform3D(Basis(Vector3.RIGHT, tilt) * Basis(Vector3.UP, PI), pos)
	qmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(qmi)


## Torcedor arredondado. pose: 0 = braços para cima, 1 = um braço acenando, 2 = batendo palmas, 3 = LOD distante.
func _person_mesh(pose: int) -> ArrayMesh:
	var kit := MeshKit.new()
	var body := Color(1, 1, 1, 1)
	var skin := Color(1, 1, 1, 0)
	if pose == 3:
		kit.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(0.9, 1.7, 0.75)), Vector3(0, 0.62, 0)), 0.3, 4, 6, body, 0.3)
		kit.sphere(Transform3D(Basis.IDENTITY, Vector3(0, 1.3, 0)), 0.2, 3, 5, skin, 0.0, 0.0)
		return kit.commit()
	# Tronco (cápsula achatada) + quadril + cabeça grande estilizada.
	kit.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(0.95, 1.25, 0.72)), Vector3(0, 0.78, 0)), 0.3, 6, 9, body, 0.35)
	kit.sphere(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 0.8, 0.8)), Vector3(0, 0.36, 0)), 0.26, 5, 9, body, 0.45)
	kit.sphere(Transform3D(Basis.IDENTITY, Vector3(0, 1.36, 0)), 0.22, 6, 9, skin, 0.15, 0.0)
	# Braços (cápsulas) conforme a pose.
	var arms: Array[Vector3] = []   # (lado, ângulo em torno de -Z, dobra à frente)
	match pose:
		0:
			arms = [Vector3(-1, 2.6, 0.0), Vector3(1, 2.6, 0.0)]
		1:
			arms = [Vector3(-1, 2.8, 0.0), Vector3(1, 0.35, 0.0)]
		_:
			arms = [Vector3(-1, 1.2, 0.9), Vector3(1, 1.2, 0.9)]
	for a in arms:
		var sd := a.x
		var rot := Basis(Vector3.FORWARD, -sd * a.y) * Basis(Vector3.RIGHT, -a.z)
		var shoulder := Vector3(sd * 0.27, 1.02, 0.0)
		var arm_xf := Transform3D(rot, shoulder)
		kit.sphere(arm_xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.36, 1.0, 0.36)), Vector3(0, -0.28, 0)), 0.3, 4, 7, body, 0.2)
		kit.sphere(arm_xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.58, 0)), 0.085, 3, 6, skin, 0.0, 0.0)
	return kit.commit()


func _build_crowd() -> void:
	crowd_material = ShaderMaterial.new()
	crowd_material.shader = CROWD_SHADER
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var poses := 3
	var xfs: Array = []
	var customs: Array = []
	for k in poses:
		xfs.append([])
		customs.append([])
	var all_xf: Array[Transform3D] = []
	var all_c: Array[Color] = []
	var half := length * 0.5
	for r in rows:
		var y := first_row_height + r * row_rise
		var z := 0.6 + r * row_depth + row_depth * 0.45
		var x := -half + 0.6
		while x < half - 0.6:
			var section_pos := fposmod(x + half, length / 8.0)
			if section_pos > 0.65 and section_pos < length / 8.0 - 0.65 and rng.randf() < 0.86:
				var s := rng.randf_range(0.9, 1.08)
				var b := Basis(Vector3.UP, rng.randf_range(-0.35, 0.35)).scaled(Vector3.ONE * s)
				var xf := Transform3D(b, Vector3(x + rng.randf_range(-0.08, 0.08), y, z))
				var sh := SHIRTS[rng.randi() % SHIRTS.size()]
				var c := Color(sh.r, sh.g, sh.b, rng.randf())
				var pose := rng.randi() % poses
				(xfs[pose] as Array).append(xf)
				(customs[pose] as Array).append(c)
				all_xf.append(xf)
				all_c.append(c)
			x += 0.62
	for k in poses:
		var mesh := _person_mesh(k)
		mesh.surface_set_material(0, crowd_material)
		_crowd_mmi("Publico_pose%d" % k, mesh, xfs[k], customs[k], 0.0, 80.0)
	var far := _person_mesh(3)
	far.surface_set_material(0, crowd_material)
	var far_xf: Array = []
	var far_c: Array = []
	for i in all_xf.size():
		far_xf.append(all_xf[i])
		far_c.append(all_c[i])
	_crowd_mmi("Publico_LOD", far, far_xf, far_c, 65.0, 450.0)
	crowd_count = all_xf.size()


func _crowd_mmi(node_name: String, mesh: Mesh, xfs: Array, customs: Array, begin: float, end: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_begin = begin
	mmi.visibility_range_begin_margin = 15.0 if begin > 0.0 else 0.0
	mmi.visibility_range_end = end
	mmi.visibility_range_end_margin = 15.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	# O público fica sob a cobertura: sombra própria é imperceptível e custa caro.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Nível de animação do público (0 = parado, 1 = eufórico). Usado na largada/chegada.
func set_excitement(v: float) -> void:
	if crowd_material:
		crowd_material.set_shader_parameter(&"excitement", v)
