class_name MeshKit
extends RefCounted
## Construtor de malhas procedurais (arrays + índices) com primitivas arredondadas.
## A ordem dos vértices de cada triângulo é corrigida automaticamente a partir das normais,
## então os geradores não precisam se preocupar com o "winding" (Godot: horário = frente).

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var uvs := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()


func clear() -> void:
	verts.clear()
	norms.clear()
	uvs.clear()
	colors.clear()
	indices.clear()


func is_empty() -> bool:
	return indices.is_empty()


func vertex_count() -> int:
	return verts.size()


func add_vertex(p: Vector3, n: Vector3, uv: Vector2 = Vector2.ZERO, c: Color = Color.WHITE) -> int:
	verts.append(p)
	norms.append(n)
	uvs.append(uv)
	colors.append(c)
	return verts.size() - 1


## Triângulo por índices; corrige a ordem para que a face aponte para as normais dos vértices.
func tri(a: int, b: int, c: int) -> void:
	var face := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	var n := norms[a] + norms[b] + norms[c]
	if face.dot(n) > 0.0:
		indices.append(a)
		indices.append(c)
		indices.append(b)
	else:
		indices.append(a)
		indices.append(b)
		indices.append(c)


## Quad a0-a1-b1-b0 (dois triângulos).
func quad(a0: int, a1: int, b0: int, b1: int) -> void:
	tri(a0, a1, b1)
	tri(a0, b1, b0)


## Quad com vértices próprios e normal plana.
func flat_quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color, uv0: Vector2 = Vector2(0, 0), uv1: Vector2 = Vector2(1, 1)) -> void:
	var i0 := add_vertex(p0, n, Vector2(uv0.x, uv0.y), c)
	var i1 := add_vertex(p1, n, Vector2(uv1.x, uv0.y), c)
	var i2 := add_vertex(p2, n, Vector2(uv1.x, uv1.y), c)
	var i3 := add_vertex(p3, n, Vector2(uv0.x, uv1.y), c)
	tri(i0, i1, i2)
	tri(i0, i2, i3)


func append_kit(other: MeshKit, xf: Transform3D = Transform3D.IDENTITY, tint: Color = Color.WHITE) -> void:
	var base := verts.size()
	var nb := xf.basis.inverse().transposed()
	for i in other.verts.size():
		verts.append(xf * other.verts[i])
		norms.append((nb * other.norms[i]).normalized())
		uvs.append(other.uvs[i])
		colors.append(other.colors[i] * tint)
	for idx in other.indices:
		indices.append(base + idx)


func to_arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	return arr


## Adiciona uma superfície (se houver geometria) a `mesh` (ou a uma nova ArrayMesh).
func commit(mesh: ArrayMesh = null, material: Material = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if indices.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, to_arrays())
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## Triângulos (sem índice) para ConcavePolygonShape3D.
func to_collision_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		faces[i] = verts[indices[i]]
	return faces


# ------------------------------------------------------------------ primitivas

func box(xf: Transform3D, size: Vector3, c: Color) -> void:
	var h := size * 0.5
	var nb := xf.basis.inverse().transposed()
	var dirs: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for n in dirs:
		var t1 := Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
		var t2 := n.cross(t1)
		var ctr := n * h
		var e1 := t1 * h
		var e2 := t2 * h
		var wn := (nb * n).normalized()
		flat_quad(xf * (ctr - e1 - e2), xf * (ctr - e1 + e2), xf * (ctr + e1 + e2), xf * (ctr + e1 - e2), wn, c)


## Prisma com planta de retângulo arredondado (cantos verticais arredondados).
## UV das paredes: x = perímetro (m), y = altura (m). COLOR fornecido por parâmetro.
func rounded_prism(xf: Transform3D, width: float, depth: float, height: float, radius: float, segs: int, c_wall: Color, c_top: Color, bottom_cap: bool = false) -> void:
	var r := minf(radius, minf(width, depth) * 0.5 - 0.001)
	r = maxf(r, 0.0)
	var outline := rounded_rect_outline(width, depth, r, segs)
	var nb := xf.basis.inverse().transposed()
	var n := outline.size()
	# Paredes.
	var per := 0.0
	var base_i := verts.size()
	for i in n + 1:
		var p2: Vector3 = outline[i % n]
		if i > 0:
			per += p2.distance_to(outline[(i - 1) % n])
		var nrm := _outline_normal(outline, i % n)
		var wn := (nb * nrm).normalized()
		add_vertex(xf * Vector3(p2.x, 0.0, p2.z), wn, Vector2(per, 0.0), c_wall)
		add_vertex(xf * Vector3(p2.x, height, p2.z), wn, Vector2(per, height), c_wall)
	for i in n:
		var a0 := base_i + i * 2
		quad(a0, a0 + 1, a0 + 2, a0 + 3)
	# Tampa superior (leque).
	_cap(xf, outline, height, (nb * Vector3.UP).normalized(), c_top)
	if bottom_cap:
		_cap(xf, outline, 0.0, (nb * Vector3.DOWN).normalized(), c_top)


func _cap(xf: Transform3D, outline: PackedVector3Array, y: float, wn: Vector3, c: Color) -> void:
	var center := add_vertex(xf * Vector3(0.0, y, 0.0), wn, Vector2.ZERO, c)
	var first := verts.size()
	for p in outline:
		add_vertex(xf * Vector3(p.x, y, p.z), wn, Vector2(p.x, p.z), c)
	var n := outline.size()
	for i in n:
		tri(center, first + i, first + (i + 1) % n)


static func rounded_rect_outline(width: float, depth: float, r: float, segs: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var hx := width * 0.5 - r
	var hz := depth * 0.5 - r
	var corners: Array[Vector2] = [Vector2(hx, hz), Vector2(-hx, hz), Vector2(-hx, -hz), Vector2(hx, -hz)]
	var start_angles: Array[float] = [0.0, PI * 0.5, PI, PI * 1.5]
	var s := maxi(segs, 1)
	for k in 4:
		for j in s + 1:
			var a := start_angles[k] + (PI * 0.5) * float(j) / float(s)
			var pt := corners[k] + Vector2(cos(a), sin(a)) * r
			if out.size() > 0 and Vector2(out[out.size() - 1].x, out[out.size() - 1].z).distance_to(pt) < 0.0001:
				continue
			out.append(Vector3(pt.x, 0.0, pt.y))
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) < 0.0001:
		out.remove_at(out.size() - 1)
	return out


func _outline_normal(outline: PackedVector3Array, i: int) -> Vector3:
	var n := outline.size()
	var prev := outline[(i - 1 + n) % n]
	var next := outline[(i + 1) % n]
	var tangent := (next - prev).normalized()
	var nrm := Vector3(tangent.z, 0.0, -tangent.x)
	# Garante que aponta para fora do centro.
	if nrm.dot(outline[i]) < 0.0:
		nrm = -nrm
	return nrm


## Cilindro/cone (eixo Y local de 0 a h).
func cylinder(xf: Transform3D, r0: float, r1: float, h: float, segs: int, c: Color, caps: bool = true, c_cap: Color = Color(-1, 0, 0)) -> void:
	var nb := xf.basis.inverse().transposed()
	var slope := (r0 - r1) / maxf(h, 0.0001)
	var base_i := verts.size()
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		var d := Vector3(cos(a), 0.0, sin(a))
		var nrm := (nb * Vector3(d.x, slope, d.z).normalized()).normalized()
		add_vertex(xf * (d * r0), nrm, Vector2(float(i) / float(segs), 0.0), c)
		add_vertex(xf * (d * r1 + Vector3(0.0, h, 0.0)), nrm, Vector2(float(i) / float(segs), 1.0), c)
	for i in segs:
		var a0 := base_i + i * 2
		quad(a0, a0 + 1, a0 + 2, a0 + 3)
	if caps:
		var cc := c if c_cap.r < 0.0 else c_cap
		var ring := PackedVector3Array()
		for i in segs:
			var a := TAU * float(i) / float(segs)
			ring.append(Vector3(cos(a), 0.0, sin(a)))
		if r1 > 0.001:
			var top := PackedVector3Array()
			for p in ring:
				top.append(p * r1)
			_cap(xf, top, h, (nb * Vector3.UP).normalized(), cc)
		if r0 > 0.001:
			var bot := PackedVector3Array()
			for p in ring:
				bot.append(p * r0)
			_cap(xf, bot, 0.0, (nb * Vector3.DOWN).normalized(), cc)


## Esfera UV com escurecimento opcional na parte de baixo (AO estilizado).
func sphere(xf: Transform3D, radius: float, rings: int, segs: int, c: Color, ao_bottom: float = 0.0, leaf_alpha: float = -1.0) -> void:
	var nb := xf.basis.inverse().transposed()
	var base_i := verts.size()
	for r in rings + 1:
		var v := float(r) / float(rings)
		var phi := PI * v
		var y := cos(phi)
		var rr := sin(phi)
		var shade := 1.0 - ao_bottom * clampf((1.0 - y) * 0.5, 0.0, 1.0)
		var col := Color(c.r * shade, c.g * shade, c.b * shade, c.a if leaf_alpha < 0.0 else leaf_alpha)
		for s in segs + 1:
			var u := float(s) / float(segs)
			var th := TAU * u
			var d := Vector3(cos(th) * rr, y, sin(th) * rr)
			add_vertex(xf * (d * radius), (nb * d).normalized(), Vector2(u, v), col)
	var stride := segs + 1
	for r in rings:
		for s in segs:
			var a0 := base_i + r * stride + s
			var b0 := a0 + stride
			if r > 0:
				tri(a0, a0 + 1, b0)
			if r < rings - 1:
				tri(a0 + 1, b0 + 1, b0)


## Tampa plana (leque a partir do centróide) para a ponta de uma extrusão.
func cap_profile(origin: Vector3, right: Vector3, up: Vector3, profile: PackedVector2Array, normal: Vector3, c: Color) -> void:
	var center := Vector2.ZERO
	for q in profile:
		center += q
	center /= float(profile.size())
	var ci := add_vertex(origin + right * center.x + up * center.y, normal, Vector2.ZERO, c)
	var first := verts.size()
	for q in profile:
		add_vertex(origin + right * q.x + up * q.y, normal, Vector2.ZERO, c)
	for k in profile.size() - 1:
		tri(ci, first + k, first + k + 1)
	tri(ci, first + profile.size() - 1, first)


## Extruda um perfil 2D (x lateral, y altura) ao longo de uma polilinha com frames.
## `rails`: posições; `rights`/`ups`: base por ponto. Perfil com normais 2D fornecidas.
func extrude(rails: PackedVector3Array, rights: PackedVector3Array, ups: PackedVector3Array, profile: PackedVector2Array, profile_normals: PackedVector2Array, c: Color, v_coords: PackedFloat32Array, closed: bool = false) -> void:
	var np := profile.size()
	var nr := rails.size()
	# Comprimento acumulado do perfil para UV.x.
	var plen := PackedFloat32Array()
	plen.resize(np)
	plen[0] = 0.0
	for k in range(1, np):
		plen[k] = plen[k - 1] + profile[k].distance_to(profile[k - 1])
	var total := maxf(plen[np - 1], 0.0001)
	var base_i := verts.size()
	for i in nr:
		for k in np:
			var p := rails[i] + rights[i] * profile[k].x + ups[i] * profile[k].y
			var n := (rights[i] * profile_normals[k].x + ups[i] * profile_normals[k].y).normalized()
			add_vertex(p, n, Vector2(plen[k] / total, v_coords[i]), c)
	var rows := nr if closed else nr - 1
	for i in rows:
		var i1 := (i + 1) % nr
		for k in np - 1:
			var a0 := base_i + i * np + k
			var b0 := base_i + i1 * np + k
			quad(a0, a0 + 1, b0, b0 + 1)
