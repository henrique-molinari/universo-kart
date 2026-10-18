extends Node
## Validação automática da pista (roda em modo headless):
##  - colisão do asfalto/acostamento contínua (raios verticais ao longo de toda a volta);
##  - muretas contínuas dos dois lados (raios laterais), sem frestas;
##  - ida-e-volta da API do TrackPath (offset/lateral <-> posição);
##  - grid de largada, turbos e caixas de item sobre o asfalto;
##  - terreno com colisão fora da pista.
## Uso: Godot_console.exe --headless --path <projeto> res://tools/validate/validate_track.tscn

const TRACK_SCENE := "res://scenes/tracks/campus_circuit.tscn"

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	# Segurança: nunca travar a automação.
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		printerr("[validate] TIMEOUT")
		get_tree().quit(3))
	_run.call_deferred()


func _run() -> void:
	var packed := load(TRACK_SCENE) as PackedScene
	var track := packed.instantiate() as Track
	track.build_scenery = false
	add_child(track)
	if not track.is_ready:
		await track.track_ready
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := track.get_world_3d().direct_space_state
	var tp := track.track_path
	var hw := tp.get_half_width()
	var wl := tp.get_wall_lateral()
	var max_h := -1e9
	var min_h := 1e9
	var max_bank := 0.0
	var o_scan := 0.0
	while o_scan < tp.length:
		max_h = maxf(max_h, tp.get_height(o_scan))
		min_h = minf(min_h, tp.get_height(o_scan))
		max_bank = maxf(max_bank, absf(tp.get_bank(o_scan)))
		o_scan += 1.0
	print("[validate] volta = %.1f m, amostras = %d, largura = %.1f m, muretas nominais em ±%.1f m (máx %.1f m)" % [tp.length, tp.sample_count, tp.layout.road_width, wl, tp.get_max_wall_lateral()])
	print("[validate] altura: %.1f .. %.1f m (desnível %.1f m), inclinação máx: %.1f°" % [min_h, max_h, max_h - min_h, rad_to_deg(max_bank)])

	# 1) Superfície dirigível contínua.
	var off := 0.0
	var worst_dy := 0.0
	while off < tp.length:
		for lat: float in [-tp.get_wall_lateral(off, -1) + 0.4, -hw + 0.3, 0.0, hw - 0.3, tp.get_wall_lateral(off, 1) - 0.4]:
			var p := tp.to_world(off, lat)
			var up := tp.get_up(off)
			var hit := _ray(space, p + up * 4.0, p - up * 6.0, PhysicsLayers.WORLD_ROAD)
			_check(not hit.is_empty(), "sem colisão de pista em offset %.1f lateral %.1f" % [off, lat])
			if not hit.is_empty():
				var n: Vector3 = hit["normal"]
				var hp: Vector3 = hit["position"]
				worst_dy = maxf(worst_dy, absf(hp.y - p.y))
				_check(n.y > 0.9, "normal inclinada (%.2f) em offset %.1f" % [n.y, off])
		off += 2.5
	print("[validate] superfície: maior desvio de altura = %.3f m" % worst_dy)

	# 2) Muretas contínuas (raios do centro para os lados, em várias alturas).
	off = 0.0
	var wall_err := 0.0
	while off < tp.length:
		for side: float in [-1.0, 1.0]:
			for h: float in [0.3, 1.0, 2.5]:
				var a := tp.to_world(off, 0.0, h)
				var b := tp.to_world(off, side * (tp.get_wall_lateral(off, int(side)) + 3.0), h)
				var hit := _ray(space, a, b, PhysicsLayers.WORLD_WALL)
				_check(not hit.is_empty(), "fresta na mureta em offset %.1f lado %d altura %.1f" % [off, int(side), h])
				if not hit.is_empty():
					var lat := tp.get_lateral(hit["position"], off)
					wall_err = maxf(wall_err, absf(absf(lat) - tp.get_wall_lateral(off, int(side))))
		off += 1.7
	print("[validate] muretas: maior desvio lateral = %.3f m" % wall_err)

	# 3) Ida-e-volta da API.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst_off := 0.0
	var worst_lat := 0.0
	for i in 600:
		var o := rng.randf() * tp.length
		var l := rng.randf_range(-tp.get_wall_lateral(o, -1) + 0.5, tp.get_wall_lateral(o, 1) - 0.5)
		var p := tp.to_world(o, l, 0.8)
		var co := tp.get_closest_offset(p)
		var hinted := tp.get_closest_offset(p, o + rng.randf_range(-8.0, 8.0))
		worst_off = maxf(worst_off, absf(tp.delta_offset(o, co)))
		worst_off = maxf(worst_off, absf(tp.delta_offset(o, hinted)))
		worst_lat = maxf(worst_lat, absf(tp.get_lateral(p, co) - l))
	_check(worst_off < 1.5, "get_closest_offset impreciso (%.2f m)" % worst_off)
	_check(worst_lat < 0.5, "get_lateral impreciso (%.2f m)" % worst_lat)
	print("[validate] API: erro máx offset = %.3f m, lateral = %.3f m" % [worst_off, worst_lat])

	# 4) Pontos estratégicos.
	for s in 8:
		var g := tp.get_grid_transform(s)
		var go := tp.get_closest_offset(g.origin)
		_check(absf(tp.get_lateral(g.origin, go)) < hw - 1.0, "slot %d do grid fora do asfalto" % s)
		_check(tp.delta_offset(0.0, go) < 0.0, "slot %d do grid depois da linha de largada" % s)
	for pad in tp.get_boost_pads():
		_check(absf(float(pad["lateral"])) + 2.5 < hw, "turbo fora do asfalto em %.1f" % float(pad["offset"]))
		_check(tp.get_bridge(float(pad["offset"])) >= 0.0, "turbo inválido")
	for row in tp.get_item_rows():
		var positions: PackedVector3Array = row["positions"]
		for p in positions:
			var ro := tp.get_closest_offset(p)
			_check(absf(tp.get_lateral(p, ro)) < hw - 1.0, "caixa de item fora do asfalto")
	print("[validate] checkpoints: %d, turbos: %d, fileiras de itens: %d" % [tp.get_checkpoint_offsets().size(), tp.get_boost_pads().size(), tp.get_item_rows().size()])

	# 5) Terreno fora da pista.
	for q: Vector2 in [Vector2(300, 100), Vector2(-400, -500), Vector2(100, 300), Vector2(-150, -135)]:
		var hit := _ray(space, Vector3(q.x, 200, q.y), Vector3(q.x, -200, q.y), PhysicsLayers.WORLD_TERRAIN)
		_check(not hit.is_empty(), "terreno sem colisão em %s" % q)

	print("[validate] %d verificações, %d falhas" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, mask)
	q.hit_back_faces = false
	return space.intersect_ray(q)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		if _failures <= 25:
			printerr("[validate] FALHA: ", msg)
