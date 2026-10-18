class_name TracksideProps
extends Node3D
## Elementos ao redor da pista: placas UNIFEOB atrás das muretas, outdoors grandes nas
## saídas de curva, postes de luz, bandeirolas (feather flags), varais de bandeirinhas
## sobre a reta e o letreiro gigante do logo na colina.

const PROPS_MAT := preload("res://assets/materials/painted_props.tres")

var _path: TrackPath
var _site: SiteMap
var _brand: BrandArt
var board_count: int = 0
var arch_count: int = 0


func build(path: TrackPath, site: SiteMap, brand: BrandArt) -> void:
	_path = path
	_site = site
	_brand = brand
	_build_boards()
	_build_billboards()
	_build_lamps()
	_build_feather_flags()
	_build_bunting()
	_build_overhead_arches()
	_build_hill_sign()


func _wl(offset: float, side: int) -> float:
	return _path.get_wall_lateral(offset, side)


func _in_tunnel(offset: float, margin: float) -> bool:
	var trange := _path.get_tunnel_range()
	if trange.x < 0.0:
		return false
	return offset > trange.x - margin and offset < trange.y + margin


## Offsets (com sinal do lado) onde não colocar placas: arquibancada e pórtico.
func _excluded(offset: float, side: int) -> bool:
	var d := _path.delta_offset(0.0, offset)
	if absf(d) < 10.0:
		return true
	if side > 0 and d > -80.0 and d < 30.0:
		return true   # arquibancada (lado direito da reta)
	if _in_tunnel(offset, 22.0) or _path.get_bridge(offset) > 0.01:
		return true
	if _path.get_wall_style(offset, side) == TrackLayout.WallStyle.FENCE:
		return true   # beira do lago: vista livre para a água
	return false


func _build_boards() -> void:
	var per_design: Dictionary = {}
	var frames := MeshKit.new()
	var step := 21.0
	var off := 5.0
	var idx := 0
	while off < _path.length:
		for side: int in [-1, 1]:
			if _excluded(off, side):
				continue
			var k := _path.get_curvature(off)
			# Nas curvas, só do lado de fora; nas retas, dos dois lados alternando.
			var outside := -1 if k > 0.0 else 1
			if absf(k) > 1.0 / 180.0 and side != outside:
				continue
			if absf(k) <= 1.0 / 180.0 and (idx + (1 if side > 0 else 0)) % 2 == 1:
				continue
			var xf := _path.get_transform_at(off, float(side) * (_wl(off, side) + 1.7))
			# Base: +Z do quad deve olhar para a pista (lado oposto a `side`).
			var right := xf.basis.x
			var facing := -right * float(side)
			var rot := Basis.looking_at(-facing, Vector3.UP)
			var ground_y := xf.origin.y
			var pos := Vector3(xf.origin.x, ground_y + 1.75, xf.origin.z)
			var design: int = BrandArt.BANNER_ROTATION[idx % BrandArt.BANNER_ROTATION.size()]
			if not per_design.has(design):
				per_design[design] = []
			(per_design[design] as Array).append(Transform3D(rot, pos))
			var fxf := Transform3D(rot, pos)
			frames.box(fxf.translated_local(Vector3(0, 0, -0.12)), Vector3(6.9, 1.62, 0.18), Color(0.14, 0.14, 0.16))
			for lx: float in [-2.9, 2.9]:
				frames.box(fxf.translated_local(Vector3(lx, -1.25, -0.12)), Vector3(0.16, 1.4, 0.16), Color(0.35, 0.35, 0.38))
			idx += 1
			board_count += 1
		off += step
	var fmi := MeshInstance3D.new()
	fmi.name = "PlacasEstrutura"
	fmi.mesh = frames.commit(null, PROPS_MAT)
	add_child(fmi)
	var quad := QuadMesh.new()
	quad.size = Vector2(6.5, 1.4)
	for design: int in per_design:
		var list: Array = per_design[design]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var q := quad.duplicate() as QuadMesh
		q.material = _brand.get_material(design as BrandArt.Design)
		mm.mesh = q
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Placas_%d" % design
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _build_billboards() -> void:
	# t (fração da volta), lado (+1 direita / -1 esquerda), design
	var spots: Array[Vector3] = [
		Vector3(0.105, 1, BrandArt.Design.TITLE_ON_MAGENTA),
		Vector3(0.22, 1, BrandArt.Design.LOGO_ON_BLUE),
		Vector3(0.36, -1, BrandArt.Design.LOGO_ON_YELLOW),
		Vector3(0.465, 1, BrandArt.Design.TITLE_ON_DARK),
		Vector3(0.69, -1, BrandArt.Design.LOGO_ON_WHITE),
		Vector3(0.76, 1, BrandArt.Design.TITLE_ON_MAGENTA),
		Vector3(0.88, 1, BrandArt.Design.LOGO_ON_BLUE),
	]
	var frames := MeshKit.new()
	for s in spots:
		var off := s.x * _path.length
		var side := int(s.y)
		# Um pouco à frente, voltado para quem se aproxima.
		var xf := _path.get_transform_at(off, float(side) * (_wl(off, side) + 6.0))
		var toward := (_path.get_point_at(off - 60.0) - xf.origin)
		toward.y = 0.0
		var rot := Basis.looking_at(-toward.normalized(), Vector3.UP)
		var gy := _site.height_at(xf.origin.x, xf.origin.z)
		var pos := Vector3(xf.origin.x, gy + 6.2, xf.origin.z)
		var bxf := Transform3D(rot, pos)
		frames.box(bxf.translated_local(Vector3(0, 0, -0.3)), Vector3(13.0, 4.6, 0.5), Color(0.13, 0.13, 0.15))
		for lx: float in [-4.0, 4.0]:
			frames.cylinder(Transform3D(rot, bxf * Vector3(lx, -2.3, -0.4) - Vector3(0, 6.0, 0)), 0.28, 0.22, 6.2, 10, Color(0.85, 0.85, 0.88), false)
		var q := QuadMesh.new()
		q.size = Vector2(12.4, 3.1)
		var qmi := MeshInstance3D.new()
		qmi.mesh = q
		qmi.material_override = _brand.get_material(int(s.z) as BrandArt.Design)
		qmi.transform = bxf.translated_local(Vector3(0, 0, -0.03))
		qmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(qmi)
		_site.add_blocker(Vector2(pos.x, pos.z), 8.0)
	var mi := MeshInstance3D.new()
	mi.name = "Outdoors"
	mi.mesh = frames.commit(null, PROPS_MAT)
	add_child(mi)


func _lamp_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	var pole := Color(0.86, 0.87, 0.9)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)), 0.34, 0.3, 0.9, 10, Palette.BLUE, true)
	k.cylinder(Transform3D(Basis.IDENTITY, Vector3.ZERO), 0.13, 0.09, 8.5, 8, pole, true)
	# Braço curvo em direção à pista (-Z local) + luminária.
	k.cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 8.3, 0)), 0.07, 0.07, 2.2, 6, pole, true)
	k.rounded_prism(Transform3D(Basis.IDENTITY, Vector3(0, 8.05, -2.2)), 0.7, 1.2, 0.3, 0.3, 3, Palette.GRAPHITE, Palette.GRAPHITE)
	k.box(Transform3D(Basis.IDENTITY, Vector3(0, 8.03, -2.2)), Vector3(0.5, 0.06, 0.95), Color(1.0, 0.98, 0.85))
	return k.commit(null, PROPS_MAT)


func _build_lamps() -> void:
	var xfs: Array[Transform3D] = []
	var off := 12.0
	while off < _path.length:
		for side: int in [-1, 1]:
			if _excluded(off, side) and absf(_path.delta_offset(0.0, off)) < 10.0:
				continue
			var on_bridge := _path.get_bridge(off) > 0.01
			if _in_tunnel(off, 6.0):
				continue
			var lat := (_wl(off, side) + 1.3) if on_bridge else (_wl(off, side) + 3.3)
			var xf := _path.get_transform_at(off, float(side) * lat)
			var right := xf.basis.x
			var facing := -right * float(side)
			var rot := Basis.looking_at(facing, Vector3.UP)
			var gy := _site.height_at(xf.origin.x, xf.origin.z)
			if on_bridge:
				gy = xf.origin.y - 0.3
			elif _site.is_blocked(xf.origin.x, xf.origin.z, 2.0):
				continue   # não tapar outdoors/prédios
			xfs.append(Transform3D(rot, Vector3(xf.origin.x, maxf(gy, xf.origin.y - 1.0), xf.origin.z)))
		off += 48.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _lamp_mesh()
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Postes"
	mmi.multimesh = mm
	add_child(mmi)


func _flag_mesh(design: BrandArt.Design) -> ArrayMesh:
	# Bandeira "pena": faixa vertical curvada presa num mastro.
	var k := MeshKit.new()
	var rows := 10
	var h := 3.6
	var base_y := 1.2
	var b0 := k.vertex_count()
	for r in rows + 1:
		var t := float(r) / float(rows)
		var y := base_y + t * h
		var w := 0.95 * sqrt(clampf(sin(PI * 0.5 * minf(1.0, (1.0 - t) * 3.0 + 0.25)), 0.0, 1.0))
		if t > 0.8:
			w *= 1.0 - (t - 0.8) * 2.2
		var bend := sin(t * PI) * 0.12
		k.add_vertex(Vector3(0.08, y, 0), Vector3(0, 0, 1), Vector2(0.0, 1.0 - t), Color.WHITE)
		k.add_vertex(Vector3(0.08 + w, y + t * 0.25, bend), Vector3(0, 0, 1), Vector2(1.0, 1.0 - t), Color.WHITE)
	for r in rows:
		var a := b0 + r * 2
		k.quad(a, a + 2, a + 1, a + 3)
	# Verso: mesma geometria com normal invertida e U espelhado (logo legível dos dois lados).
	var b1 := k.vertex_count()
	for r in rows + 1:
		var src := b0 + r * 2
		k.add_vertex(k.verts[src], Vector3(0, 0, -1), Vector2(1.0, k.uvs[src].y), Color.WHITE)
		k.add_vertex(k.verts[src + 1], Vector3(0, 0, -1), Vector2(0.0, k.uvs[src + 1].y), Color.WHITE)
	for r in rows:
		var a := b1 + r * 2
		k.quad(a, a + 2, a + 1, a + 3)
	var mesh := k.commit(null, _brand.get_material(design))
	var pole := MeshKit.new()
	pole.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.3, 0)), 0.05, 0.04, h + base_y + 0.9, 6, Color(0.9, 0.9, 0.92), true)
	pole.cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.3, 0)), 0.3, 0.3, 0.3, 10, Palette.GRAPHITE, true)
	pole.commit(mesh, PROPS_MAT)
	return mesh


func _build_feather_flags() -> void:
	var designs: Array[BrandArt.Design] = [BrandArt.Design.FLAG_BLUE, BrandArt.Design.FLAG_MAGENTA, BrandArt.Design.FLAG_YELLOW]
	var per: Dictionary = {}
	for d in designs:
		per[d] = []
	var i := 0
	var off := -90.0
	while off < 90.0:
		for side: int in [-1, 1]:
			if absf(off) < 12.0:
				continue
			if side > 0 and off > -80.0 and off < 30.0:
				continue
			var xf := _path.get_transform_at(off, float(side) * (_wl(off, side) + 4.6))
			var gy := _site.height_at(xf.origin.x, xf.origin.z)
			var rot := Basis(Vector3.UP, sin(off * 1.7 + float(side)) * 0.5) * xf.basis
			(per[designs[i % designs.size()]] as Array).append(Transform3D(rot, Vector3(xf.origin.x, gy, xf.origin.z)))
			i += 1
		off += 9.0
	# Bandeirolas também em volta do planetário e nas saídas das curvas principais.
	for t: float in [0.235, 0.385, 0.7, 0.845]:
		for k in 3:
			var o := t * _path.length + float(k) * 7.0
			var side := 1 if _path.get_curvature(o) > 0.0 else -1
			var xf := _path.get_transform_at(o, float(side) * (_wl(o, side) + 4.6))
			var gy := _site.height_at(xf.origin.x, xf.origin.z)
			if _path.get_bridge(o) > 0.01:
				continue
			(per[designs[i % designs.size()]] as Array).append(Transform3D(xf.basis, Vector3(xf.origin.x, gy, xf.origin.z)))
			i += 1
	for d in designs:
		var list: Array = per[d]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _flag_mesh(d)
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Bandeirolas_%d" % d
		mmi.multimesh = mm
		add_child(mmi)


func _build_bunting() -> void:
	var kit := MeshKit.new()
	var cord := MeshKit.new()
	var cols: Array[Color] = [Palette.BLUE, Palette.MAGENTA, Palette.YELLOW, Color(0.97, 0.97, 1.0)]
	var span := _path.get_wall_lateral() + 2.6
	for off: float in [-118.0, -58.0, 48.0, 88.0]:
		var a := _path.to_world(off, -span)
		var b := _path.to_world(off, span)
		var top := 9.5
		# Postes.
		for p: Vector3 in [a, b]:
			var gy := _site.height_at(p.x, p.z)
			kit.cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, gy - 0.3, p.z)), 0.16, 0.12, top + 0.6 - (gy - p.y), 8, Color(0.9, 0.9, 0.93), true)
		var pa := a + Vector3(0, top, 0)
		var pb := b + Vector3(0, top, 0)
		var n := 34
		var fwd := _path.get_forward(off)
		for i in n:
			var t0 := float(i) / float(n)
			var t1 := (float(i) + 0.8) / float(n)
			var p0 := pa.lerp(pb, t0) - Vector3(0, sin(t0 * PI) * 1.6, 0)
			var p1 := pa.lerp(pb, t1) - Vector3(0, sin(t1 * PI) * 1.6, 0)
			var tip := (p0 + p1) * 0.5 - Vector3(0, 0.75, 0)
			var c := cols[i % cols.size()]
			for s: float in [1.0, -1.0]:
				var nrm := fwd * s
				var i0 := kit.add_vertex(p0, nrm, Vector2.ZERO, c)
				var i1 := kit.add_vertex(p1, nrm, Vector2.ZERO, c)
				var i2 := kit.add_vertex(tip, nrm, Vector2.ZERO, c)
				kit.tri(i0, i1, i2)
			# Cordão (sem sombra: fino demais, serrilharia no asfalto).
		var cord_n := 24
		for i in cord_n:
			var t0 := float(i) / float(cord_n)
			var t1 := float(i + 1) / float(cord_n)
			var p0 := pa.lerp(pb, t0) - Vector3(0, sin(t0 * PI) * 1.6, 0)
			var p1 := pa.lerp(pb, t1) - Vector3(0, sin(t1 * PI) * 1.6, 0)
			var dir := (p1 - p0)
			var rot := Basis.looking_at(dir.normalized(), fwd if absf(dir.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
			cord.cylinder(Transform3D(rot * Basis(Vector3.RIGHT, -PI * 0.5), p0), 0.025, 0.025, dir.length(), 4, Color(0.95, 0.95, 0.95), false)
	var mi := MeshInstance3D.new()
	mi.name = "Bandeirinhas"
	mi.mesh = kit.commit(null, PROPS_MAT)
	add_child(mi)
	var cmi := MeshInstance3D.new()
	cmi.name = "Cordoes"
	cmi.mesh = cord.commit(null, PROPS_MAT)
	cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cmi)


## Pórticos com banners sobre a pista (identidade de setor).
func _build_overhead_arches() -> void:
	var kit := MeshKit.new()
	var designs: Array[BrandArt.Design] = [BrandArt.Design.TITLE_ON_DARK, BrandArt.Design.LOGO_ON_BLUE, BrandArt.Design.TITLE_ON_MAGENTA, BrandArt.Design.LOGO_ON_YELLOW]
	var q := QuadMesh.new()
	q.size = Vector2(9.6, 2.4)
	var n := 0
	for t in _path.layout.overhead_arches:
		var off := t * _path.length
		var xf := _path.get_transform_at(off)
		var lat_l := _wl(off, -1) + 1.7
		var lat_r := _wl(off, 1) + 1.7
		var top := 8.6
		for sd: float in [-1.0, 1.0]:
			var lat := lat_l if sd < 0.0 else lat_r
			var base := _path.to_world(off, sd * lat)
			var gy := minf(_site.height_at(base.x, base.z), base.y) - 1.0
			var post := Transform3D(Basis(xf.basis.x, Vector3.UP, xf.basis.x.cross(Vector3.UP)).orthonormalized(), Vector3(base.x, gy, base.z))
			kit.rounded_prism(post, 1.3, 1.3, base.y + top + 1.6 - gy, 0.5, 4, Palette.BLUE, Palette.WHITE)
			kit.rounded_prism(post, 1.9, 1.9, 1.2 + (base.y - gy), 0.7, 4, Palette.MAGENTA, Palette.MAGENTA)
		# Viga (caixa ao longo do eixo lateral do frame da pista).
		var mid := (_path.to_world(off, -lat_l) + _path.to_world(off, lat_r)) * 0.5
		var beam_basis := Basis(xf.basis.x, Vector3.UP, xf.basis.x.cross(Vector3.UP)).orthonormalized()
		var width := lat_l + lat_r + 1.3
		var center := Vector3(mid.x, _path.get_point_at(off).y + top + 1.0, mid.z)
		kit.box(Transform3D(beam_basis, center), Vector3(width, 3.0, 1.0), Color(0.95, 0.95, 0.97))
		kit.box(Transform3D(beam_basis, center + Vector3(0, 1.62, 0)), Vector3(width + 0.3, 0.25, 1.3), Palette.MAGENTA)
		kit.box(Transform3D(beam_basis, center - Vector3(0, 1.62, 0)), Vector3(width + 0.3, 0.25, 1.3), Palette.MAGENTA)
		# Três banners em cada face (frente: +Z do frame = quem se aproxima).
		for face: float in [1.0, -1.0]:
			var face_basis := beam_basis if face > 0.0 else beam_basis * Basis(Vector3.UP, PI)
			for k in 3:
				var lx := (float(k) - 1.0) * 10.2
				var pos := center + beam_basis.x * lx + beam_basis.z * (face * 0.52)
				var qmi := MeshInstance3D.new()
				qmi.mesh = q
				qmi.material_override = _brand.get_material(designs[(n + k + (0 if face > 0.0 else 1)) % designs.size()])
				qmi.transform = Transform3D(face_basis, pos)
				qmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(qmi)
		n += 1
		arch_count += 1
	if not kit.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "PorticosBanner"
		mi.mesh = kit.commit(null, PROPS_MAT)
		add_child(mi)


## Letreiro gigante do logo UNIFEOB com volume (camadas), treliça e sapatas, numa encosta
## a leste, voltado para a reta principal (legível a ~300-400 m).
func _build_hill_sign() -> void:
	var p := Vector2(350.0, -18.0)
	var look_at_pt := Vector2(0.0, 0.0)
	var to_view := Vector3(look_at_pt.x - p.x, 0.0, look_at_pt.y - p.y).normalized()
	var rot := Basis.looking_at(-to_view, Vector3.UP)   # +Z local = para a reta
	var w := 124.0
	var h := w * 32.0 / 141.0
	var depth := 2.2
	# Base: menor altura do terreno sob o letreiro, para as letras não afundarem na encosta.
	var gy := 1e9
	for k in 7:
		var lx := (float(k) / 6.0 - 0.5) * w
		var q := Vector3(p.x, 0.0, p.y) + rot.x * lx
		gy = minf(gy, _site.height_at(q.x, q.z))
	var bottom := gy + 8.0
	var center := Vector3(p.x, bottom + h * 0.5, p.y)
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	# Camadas de face única: a metade da frente só aparece de frente e a de trás só por trás,
	# então o logo nunca é visto espelhado e o volume (azul) aparece dos dois lados.
	var front_mat := _brand.make_logo_cutout_material(Color(0.98, 0.98, 1.0), false)
	var side_mat := _brand.make_logo_cutout_material(Palette.BLUE, false)
	var layers := 18
	for k in layers:
		var t := float(k) / float(layers - 1)
		var z := lerpf(depth * 0.5, -depth * 0.5, t)
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		var is_face := k == 0 or k == layers - 1
		mi.material_override = front_mat if is_face else side_mat
		# Ordem de desenho: a face branca precisa vencer as camadas azuis coplanares vizinhas.
		var b := rot if k < (layers >> 1) else rot * Basis(Vector3.UP, PI)
		mi.transform = Transform3D(b, center + rot.z * z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED if k == (layers >> 1) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "LetreiroCamada%02d" % k
		add_child(mi)
	# Treliça metálica atrás das letras + sapatas de concreto.
	var kit := MeshKit.new()
	var steel := Color(0.55, 0.57, 0.6)
	var back := center - rot.z * (depth * 0.5 + 1.2)
	var cols := 10
	for k in cols:
		var lx := (float(k) / float(cols - 1) - 0.5) * (w - 4.0)
		var base := back + rot.x * lx
		var g := _site.height_at(base.x, base.z)
		var top := center.y + h * 0.5 - 1.0
		kit.box(Transform3D(rot, Vector3(base.x, (g - 1.0 + top) * 0.5, base.z)), Vector3(0.5, top - g + 1.0, 0.5), steel)
		kit.rounded_prism(Transform3D(rot, Vector3(base.x, g - 1.0, base.z)), 2.2, 2.2, 1.6, 0.4, 3, Color(0.7, 0.68, 0.64), Color(0.7, 0.68, 0.64))
		# Diagonal até o próximo pilar.
		if k < cols - 1:
			var lx2 := (float(k + 1) / float(cols - 1) - 0.5) * (w - 4.0)
			var a := Vector3(base.x, bottom + 1.0, base.z)
			var b2 := back + rot.x * lx2
			var c := Vector3(b2.x, top - 1.0, b2.z)
			var d := c - a
			var bb := Basis.looking_at(d.normalized(), rot.z)
			kit.cylinder(Transform3D(bb * Basis(Vector3.RIGHT, -PI * 0.5), a), 0.14, 0.14, d.length(), 5, steel, false)
	for hy: float in [bottom + 1.0, center.y, center.y + h * 0.5 - 1.2]:
		var c := Vector3(back.x, hy, back.z)
		kit.box(Transform3D(rot, c), Vector3(w - 3.0, 0.4, 0.4), steel)
	var smi := MeshInstance3D.new()
	smi.name = "LetreiroTrelica"
	smi.mesh = kit.commit(null, PROPS_MAT)
	add_child(smi)
	_site.add_blocker(p, w * 0.6)
	# Limpa a encosta à frente (lado da pista) para as letras não sumirem atrás das árvores.
	for k in 3:
		var ahead := p + Vector2(to_view.x, to_view.z) * (35.0 + float(k) * 35.0)
		_site.add_blocker(ahead, w * 0.5)
