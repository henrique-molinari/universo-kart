class_name TerrainBuilder
extends RefCounted
## Terreno do campus (grade do SiteMap dividida em blocos), anel de montanhas distante,
## lago e colisão (HeightMapShape3D).

const CHUNK_CELLS := 50
const SKIRT_DEPTH := 40.0
const FAR_SPACING := 90.0
const FAR_EXTENT := 4200.0

var site: SiteMap
var material: Material
var water_material: Material


func _init(p_site: SiteMap) -> void:
	site = p_site


func build(parent: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Terrain"
	parent.add_child(root)
	_build_chunks(root)
	_build_far(root)
	_build_water(root)
	_build_collision(root)


func _vertex_normal(ix: int, iz: int) -> Vector3:
	var res := site.res
	var x0 := maxi(ix - 1, 0)
	var x1 := mini(ix + 1, res - 1)
	var z0 := maxi(iz - 1, 0)
	var z1 := mini(iz + 1, res - 1)
	var hx := site.height[iz * res + x1] - site.height[iz * res + x0]
	var hz := site.height[z1 * res + ix] - site.height[z0 * res + ix]
	return Vector3(-hx / (float(x1 - x0) * SiteMap.CELL), 1.0, -hz / (float(z1 - z0) * SiteMap.CELL)).normalized()


func _build_chunks(root: Node3D) -> void:
	var res := site.res
	var chunks := ceili(float(site.cells) / float(CHUNK_CELLS))
	for cz in chunks:
		for cx in chunks:
			var kit := MeshKit.new()
			var x0 := cx * CHUNK_CELLS
			var z0 := cz * CHUNK_CELLS
			var x1 := mini(x0 + CHUNK_CELLS, site.cells)
			var z1 := mini(z0 + CHUNK_CELLS, site.cells)
			var w := x1 - x0 + 1
			for iz in range(z0, z1 + 1):
				for ix in range(x0, x1 + 1):
					var i := iz * res + ix
					var p := Vector3(site.origin.x + ix * SiteMap.CELL, site.height[i], site.origin.y + iz * SiteMap.CELL)
					kit.add_vertex(p, _vertex_normal(ix, iz), Vector2(p.x, p.z), Color(site.sand[i], site.lawn[i], 0.0, 1.0))
			for iz in z1 - z0:
				for ix in x1 - x0:
					var a := iz * w + ix
					# Diagonal alternada para relevo mais uniforme.
					if (ix + iz) % 2 == 0:
						kit.tri(a, a + w, a + w + 1)
						kit.tri(a, a + w + 1, a + 1)
					else:
						kit.tri(a, a + w, a + 1)
						kit.tri(a + 1, a + w, a + w + 1)
			_add_skirts(kit, x0, z0, x1, z1)
			var mi := MeshInstance3D.new()
			mi.name = "TerrainChunk_%d_%d" % [cx, cz]
			mi.mesh = kit.commit(null, material)
			root.add_child(mi)


## "Saia" vertical nas bordas externas do sítio (esconde frestas com o anel distante).
func _add_skirts(kit: MeshKit, x0: int, z0: int, x1: int, z1: int) -> void:
	var res := site.res
	var edges: Array = []
	if z0 == 0:
		edges.append([Vector2i(x0, 0), Vector2i(1, 0), x1 - x0, Vector3(0, 0, -1)])
	if z1 == site.cells:
		edges.append([Vector2i(x0, z1), Vector2i(1, 0), x1 - x0, Vector3(0, 0, 1)])
	if x0 == 0:
		edges.append([Vector2i(0, z0), Vector2i(0, 1), z1 - z0, Vector3(-1, 0, 0)])
	if x1 == site.cells:
		edges.append([Vector2i(x1, z0), Vector2i(0, 1), z1 - z0, Vector3(1, 0, 0)])
	for e: Array in edges:
		var start: Vector2i = e[0]
		var dir: Vector2i = e[1]
		var count: int = e[2]
		var nrm: Vector3 = e[3]
		var base := kit.vertex_count()
		for k in count + 1:
			var ix := start.x + dir.x * k
			var iz := start.y + dir.y * k
			var h := site.height[iz * res + ix]
			var p := Vector3(site.origin.x + ix * SiteMap.CELL, h, site.origin.y + iz * SiteMap.CELL)
			# Normal para cima: a saia é tingida como grama (não como rocha) onde aparecer.
			var up_n := (nrm * 0.15 + Vector3.UP).normalized()
			kit.add_vertex(p, up_n, Vector2(p.x, p.z), Color(0, 0, 0, 1))
			kit.add_vertex(p - Vector3(0, SKIRT_DEPTH, 0), up_n, Vector2(p.x, p.z), Color(0, 0, 0, 1))
		for k in count:
			var a := base + k * 2
			kit.quad(a, a + 1, a + 2, a + 3)


func _build_far(root: Node3D) -> void:
	var kit := MeshKit.new()
	var cells := ceili(FAR_EXTENT * 2.0 / FAR_SPACING)
	var w := cells + 1
	var ox := site.site_center.x - FAR_EXTENT
	var oz := site.site_center.y - FAR_EXTENT
	var in_min := site.origin + Vector2(FAR_SPACING, FAR_SPACING) * 0.6
	var in_max := site.origin + Vector2(site.cells * SiteMap.CELL, site.cells * SiteMap.CELL) - Vector2(FAR_SPACING, FAR_SPACING) * 0.6
	var heights := PackedFloat32Array()
	heights.resize(w * w)
	for iz in w:
		for ix in w:
			var x := ox + ix * FAR_SPACING
			var z := oz + iz * FAR_SPACING
			var h := site.far_height(x, z)
			if x > site.origin.x and z > site.origin.y and x < in_max.x + FAR_SPACING and z < in_max.y + FAR_SPACING:
				h -= 0.6
			heights[iz * w + ix] = h
	for iz in w:
		for ix in w:
			var x := ox + ix * FAR_SPACING
			var z := oz + iz * FAR_SPACING
			var hl := heights[iz * w + maxi(ix - 1, 0)]
			var hr := heights[iz * w + mini(ix + 1, w - 1)]
			var hd := heights[maxi(iz - 1, 0) * w + ix]
			var hu := heights[mini(iz + 1, w - 1) * w + ix]
			var nrm := Vector3(hl - hr, 2.0 * FAR_SPACING, hd - hu).normalized()
			kit.add_vertex(Vector3(x, heights[iz * w + ix], z), nrm, Vector2(x, z), Color(0, 0, 0, 1))
	for iz in cells:
		for ix in cells:
			var x0 := ox + ix * FAR_SPACING
			var z0 := oz + iz * FAR_SPACING
			# Pula células totalmente dentro do sítio (coberto pelo terreno detalhado).
			if x0 >= in_min.x and z0 >= in_min.y and x0 + FAR_SPACING <= in_max.x and z0 + FAR_SPACING <= in_max.y:
				continue
			var a := iz * w + ix
			kit.tri(a, a + w, a + w + 1)
			kit.tri(a, a + w + 1, a + 1)
	var mi := MeshInstance3D.new()
	mi.name = "FarTerrain"
	mi.mesh = kit.commit(null, material)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


func _build_water(root: Node3D) -> void:
	if site.lakes.is_empty():
		return
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for l in site.lakes:
		mn.x = minf(mn.x, l.x - l.z - 20.0)
		mn.y = minf(mn.y, l.y - l.w - 20.0)
		mx.x = maxf(mx.x, l.x + l.z + 20.0)
		mx.y = maxf(mx.y, l.y + l.w + 20.0)
	var plane := PlaneMesh.new()
	plane.size = mx - mn
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	var mi := MeshInstance3D.new()
	mi.name = "Lake"
	mi.mesh = plane
	mi.material_override = water_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3((mn.x + mx.x) * 0.5, site.water_level, (mn.y + mx.y) * 0.5)
	root.add_child(mi)


func _build_collision(root: Node3D) -> void:
	var res := site.res
	var shape := HeightMapShape3D.new()
	shape.map_width = res
	shape.map_depth = res
	var data := PackedFloat32Array()
	data.resize(res * res)
	for i in res * res:
		data[i] = site.height[i] / SiteMap.CELL
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = PhysicsLayers.WORLD_TERRAIN
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var half := site.cells * SiteMap.CELL * 0.5
	cs.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * SiteMap.CELL), Vector3(site.origin.x + half, 0.0, site.origin.y + half))
	body.add_child(cs)
	root.add_child(body)
