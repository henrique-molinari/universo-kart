extends Node3D
## Cena de verificação de cores da marca: carrega a pista e coloca amostras (painéis verticais
## voltados para o sol) de cada cor oficial em três pipelines de material:
##   - StandardMaterial3D (albedo_color)
##   - cor de vértice (painted_props.tres)
##   - material de arte de marca (BrandArt, textura gerada + emissão)
## Uso (não-headless):
##   Godot_console.exe --path <projeto> res://tools/capture/capture.tscn -- --scene=res://tools/validate/color_check.tscn --shot=colors --out=<pasta>
## A saída imprime "[swatch] nome x y #hex" com a posição em pixels de cada amostra para medição.

const PROPS_MAT := preload("res://assets/materials/painted_props.tres")

var track: Track
var _swatches: Array[Dictionary] = []


func _ready() -> void:
	var packed := load("res://scenes/tracks/campus_circuit.tscn") as PackedScene
	track = packed.instantiate() as Track
	add_child(track)
	if not track.is_ready:
		await track.track_ready
	_build_swatches()


func _sun_flat() -> Vector3:
	var to_sun := track.sun.global_transform.basis.z
	return Vector3(to_sun.x, 0.0, to_sun.z).normalized()


func _origin() -> Vector3:
	return Vector3(75.0, 0.0, 45.0)


func _build_swatches() -> void:
	var facing := _sun_flat()
	var rot := Basis.looking_at(-facing, Vector3.UP)
	var side := rot.x
	var colors := {"azul": Palette.BLUE, "magenta": Palette.MAGENTA, "amarelo": Palette.YELLOW, "grafite": Palette.GRAPHITE}
	var designs := {"azul": BrandArt.Design.FLAG_BLUE, "magenta": BrandArt.Design.FLAG_MAGENTA, "amarelo": BrandArt.Design.FLAG_YELLOW, "grafite": BrandArt.Design.TITLE_ON_DARK}
	var brand := track.scenery.brand if track.scenery else null
	var i := 0
	for key: String in colors:
		var c: Color = colors[key]
		var base := _origin() + side * (float(i) - 1.5) * 3.2
		base.y = track.site.height_at(base.x, base.z) + 3.0
		# 1) StandardMaterial3D.
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.6
		m.metallic_specular = 0.25
		_panel("std_" + key, base + Vector3(0, 2.4, 0), rot, m, c)
		# 2) Cor de vértice.
		var kit := MeshKit.new()
		kit.box(Transform3D(rot, base), Vector3(2.4, 2.0, 0.2), c)
		var mi := MeshInstance3D.new()
		mi.mesh = kit.commit(null, PROPS_MAT)
		add_child(mi)
		_swatches.append({"name": "vtx_" + key, "pos": base + facing * 0.11, "color": c})
		# 3) Material de marca (fundo da arte).
		if brand:
			var q := QuadMesh.new()
			q.size = Vector2(2.4, 2.0)
			var qmi := MeshInstance3D.new()
			qmi.mesh = q
			qmi.material_override = brand.get_material(designs[key])
			qmi.transform = Transform3D(rot, base + Vector3(0, -2.4, 0))
			add_child(qmi)
			# A arte de bandeira tem faixa no topo; amostra no terço inferior.
			_swatches.append({"name": "brand_" + key, "pos": base + Vector3(0, -2.3, 0) - side * 0.75 + facing * 0.02 if key != "grafite" else base + Vector3(0, -1.72, 0) - side * 1.02 + facing * 0.02, "color": c})
		i += 1


func _panel(n: String, pos: Vector3, rot: Basis, mat: Material, c: Color) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2.4, 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.transform = Transform3D(rot, pos)
	add_child(mi)
	_swatches.append({"name": n, "pos": pos + rot.z * 0.02, "color": c})


func get_capture_view(view_name: String) -> Dictionary:
	if view_name != "colors":
		return {}
	var facing := _sun_flat()
	var center := _origin() + Vector3(0, track.site.height_at(_origin().x, _origin().z) + 3.0, 0)
	var pos := center + facing * 13.0 + Vector3(0, 1.0, 0)
	var view := {"pos": pos, "target": center, "fov": 60.0}
	# Projeta as amostras com uma câmera auxiliar idêntica à de captura.
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	cam.look_at_from_position(pos, center, Vector3.UP)
	for s in _swatches:
		var px := cam.unproject_position(s["pos"])
		var col: Color = s["color"]
		print("[swatch] %s %d %d #%s" % [s["name"], roundi(px.x), roundi(px.y), col.to_html(false)])
	cam.queue_free()
	return view
