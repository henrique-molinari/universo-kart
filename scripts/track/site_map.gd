class_name SiteMap
extends RefCounted
## Mapa do "terreno do campus": grade regular com distância até a pista, altura do terreno,
## lago e áreas bloqueadas. Serve ao terreno, à ponte e ao posicionamento do cenário.

const CELL := 4.0
const MAX_TRACK_DIST := 64.0
## Altura mínima da pista acima do terreno natural para virar viaduto/ponte.
const VIADUCT_CLEARANCE := 4.5

var origin := Vector2(-560.0, -640.0)   ## canto (x, z) mínimo
var cells := 250                        ## células por lado (vértices = cells + 1)
var res := 251
var site_center := Vector2(-30.0, -130.0)
var water_level := -1.4

var dist := PackedFloat32Array()        ## distância até a linha central da pista
var track_h := PackedFloat32Array()     ## altura da pista mais próxima
var bridge := PackedFloat32Array()      ## fator de ponte da amostra mais próxima
var height := PackedFloat32Array()      ## altura final do terreno
var sand := PackedFloat32Array()        ## fator areia (margem do lago)
var lawn := PackedFloat32Array()        ## fator gramado aparado
var near_off := PackedFloat32Array()    ## offset da amostra de pista mais próxima
var near_lat := PackedFloat32Array()    ## deslocamento lateral (horizontal) até essa amostra
var beyond := PackedFloat32Array()      ## distância além da face externa da mureta (negativo = dentro)

## Lobos elípticos do lago: (cx, cz, rx, rz).
var lakes: Array[Vector4] = []
## Zonas planas (campus): (cx, cz, meia-largura x, meia-largura z) — nivela o terreno em 0.
var flat_zones: Array[Vector4] = []
## Morros naturais: (cx, cz, raio, altura).
var hills: Array[Vector4] = []
## Áreas onde não se deve plantar vegetação: círculos (cx, cz, raio).
var blockers: Array[Vector3] = []

var _path: TrackPath
var _noise: FastNoiseLite
var _noise_big: FastNoiseLite


func _init() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = 1337
	_noise.frequency = 0.006
	_noise.fractal_octaves = 3
	_noise_big = FastNoiseLite.new()
	_noise_big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_big.seed = 4242
	_noise_big.frequency = 0.0022
	_noise_big.fractal_octaves = 4


func build(path: TrackPath) -> void:
	_path = path
	res = cells + 1
	var n := res * res
	dist.resize(n)
	track_h.resize(n)
	bridge.resize(n)
	height.resize(n)
	sand.resize(n)
	lawn.resize(n)
	near_off.resize(n)
	near_lat.resize(n)
	beyond.resize(n)
	_compute_bridge_mask()
	_rasterize_track()
	_compute_heights()


# ------------------------------------------------------------------ ponte

func _compute_bridge_mask() -> void:
	var count := _path.sample_count
	var raw := PackedFloat32Array()
	raw.resize(count)
	for i in count:
		var p := _path.get_point_at(i * _path.sample_step)
		var over_lake := lake_sdf(p.x, p.z) < 8.0
		var high := p.y - natural_height(p.x, p.z) > VIADUCT_CLEARANCE
		raw[i] = 1.0 if (over_lake or high) else 0.0
	# Remove trechos muito curtos (< 25 m) e preenche buracos curtos.
	var min_run := roundi(25.0 / _path.sample_step)
	raw = _fill_runs(raw, 0.0, min_run)
	raw = _fill_runs(raw, 1.0, min_run)
	_path.set_bridge_mask(raw)


## Troca por (1 - valor) as sequências de `value` mais curtas que `min_run`.
func _fill_runs(arr: PackedFloat32Array, value: float, min_run: int) -> PackedFloat32Array:
	var n := arr.size()
	var out := arr.duplicate()
	var start := -1
	# Começa numa amostra diferente de `value` para não cortar uma sequência na emenda.
	var s0 := 0
	while s0 < n and arr[s0] == value:
		s0 += 1
	if s0 >= n:
		return out
	for k in n + 1:
		var i := (s0 + k) % n
		var is_v := arr[i] == value and k < n
		if is_v and start < 0:
			start = k
		elif not is_v and start >= 0:
			if k - start < min_run:
				for m in range(start, k):
					out[(s0 + m) % n] = 1.0 - value
			start = -1
	return out


func is_bridge_offset(offset: float) -> bool:
	return _path.get_bridge(offset) > 0.01


# ------------------------------------------------------------------ rasterização da pista

func _rasterize_track() -> void:
	var n := res * res
	var d2 := PackedFloat32Array()
	d2.resize(n)
	d2.fill(MAX_TRACK_DIST * MAX_TRACK_DIST)
	track_h.fill(0.0)
	bridge.fill(0.0)
	near_off.fill(-1.0)
	near_lat.fill(0.0)
	var step := 2.0
	var count := ceili(_path.length / step)
	var rc := ceili(MAX_TRACK_DIST / CELL)
	var max2 := MAX_TRACK_DIST * MAX_TRACK_DIST
	for s in count:
		var off := s * step
		var p := _path.get_point_at(off)
		var r := _path.get_right(off)
		var rf := Vector2(r.x, r.z).normalized()
		var br := _path.get_bridge(off)
		var cx := roundi((p.x - origin.x) / CELL)
		var cz := roundi((p.z - origin.y) / CELL)
		for iz in range(maxi(cz - rc, 0), mini(cz + rc, res - 1) + 1):
			var dz := origin.y + iz * CELL - p.z
			var dz2 := dz * dz
			if dz2 >= max2:
				continue
			var row := iz * res
			for ix in range(maxi(cx - rc, 0), mini(cx + rc, res - 1) + 1):
				var dx := origin.x + ix * CELL - p.x
				var dd := dx * dx + dz2
				var idx := row + ix
				if dd < d2[idx]:
					d2[idx] = dd
					near_off[idx] = off
					near_lat[idx] = dx * rf.x + dz * rf.y
					bridge[idx] = br
	for i in n:
		dist[i] = sqrt(d2[i])


# ------------------------------------------------------------------ alturas

func lake_sdf(x: float, z: float) -> float:
	var best := 1e9
	for l in lakes:
		var q := Vector2((x - l.x) / l.z, (z - l.y) / l.w)
		var d := (q.length() - 1.0) * minf(l.z, l.w)
		# União suave entre lobos.
		var k := 14.0
		var h := clampf(0.5 + 0.5 * (d - best) / k, 0.0, 1.0)
		best = lerpf(d, best, h) - k * h * (1.0 - h)
	return best


func _flat_factor(x: float, z: float) -> float:
	var f := 0.0
	for z4 in flat_zones:
		var dx := absf(x - z4.x) - z4.z
		var dz := absf(z - z4.y) - z4.w
		var outside := Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()
		f = maxf(f, 1.0 - smoothstep(0.0, 30.0, outside))
	return f


func _rim_distance(x: float, z: float) -> float:
	# Distância "quadrada arredondada" a partir do centro do sítio.
	var dx := absf(x - site_center.x)
	var dz := absf(z - site_center.y)
	return pow(pow(dx, 4.0) + pow(dz, 4.0), 0.25)


## Altura "natural" (sem pista): ondulações + morros na borda + lago.
func natural_height(x: float, z: float) -> float:
	var flat := _flat_factor(x, z)
	var h := _noise.get_noise_2d(x, z) * 1.8 * (1.0 - flat)
	var r := _rim_distance(x, z)
	var rim_hills := smoothstep(300.0, 480.0, r) * (20.0 + 18.0 * _noise_big.get_noise_2d(x, z))
	h += rim_hills
	# Colinas suaves médias fora do campus.
	h += smoothstep(200.0, 330.0, r) * (_noise_big.get_noise_2d(x * 1.7 + 100.0, z * 1.7) * 6.0 + 3.0) * (1.0 - flat)
	for hl in hills:
		var hd := Vector2(x - hl.x, z - hl.y).length() / hl.z
		if hd < 1.0:
			var f := 1.0 - hd * hd
			h += hl.w * f * f * (1.0 - flat * 0.5)
	var ls := lake_sdf(x, z)
	if ls < 18.0:
		var bed := water_level - 3.0
		var shore := water_level + 0.35
		var lake_h := lerpf(shore, bed, smoothstep(0.0, 16.0, -ls))
		h = lerpf(lake_h, h, smoothstep(0.0, 18.0, ls))
	return h


## Altura "longe" (anel de montanhas) — contínua com natural_height na borda do sítio.
func far_height(x: float, z: float) -> float:
	var h := natural_height(x, z)
	var r := _rim_distance(x, z)
	var m := smoothstep(520.0, 1500.0, r)
	var ridge := 1.0 - absf(_noise_big.get_noise_2d(x * 0.45, z * 0.45))
	h += m * (50.0 + 170.0 * ridge * ridge + 60.0 * _noise.get_noise_2d(x * 0.05, z * 0.05))
	return h


func _compute_heights() -> void:
	for iz in res:
		for ix in res:
			var i := iz * res + ix
			var x := origin.x + ix * CELL
			var z := origin.y + iz * CELL
			var nat := natural_height(x, z)
			var h := nat
			var d := dist[i]
			var out_dist := 999.0
			var off := near_off[i]
			if off >= 0.0 and d < MAX_TRACK_DIST - 0.5:
				var lat := near_lat[i]
				var side := -1 if lat < 0.0 else 1
				var wl := _path.get_wall_lateral(off, side)
				var p := _path.get_point_at(off)
				var r := _path.get_right(off)
				var slope := r.y / maxf(sqrt(1.0 - r.y * r.y), 0.2)
				var alat := absf(lat)
				out_dist = alat - (wl + 1.0)
				# Plano da pista (considera a inclinação das curvas).
				var plane := p.y + slope * clampf(lat, -(wl + 1.0), wl + 1.0)
				var corr := plane - 0.45 if alat < wl + 1.1 else plane - 0.04
				var w := smoothstep(2.0, 40.0, out_dist)
				h = lerpf(corr, nat, w)
				# Sob a ponte/viaduto o terreno volta a ser o vale natural.
				h = lerpf(h, minf(nat, h), bridge[i])
				# Nunca acima do asfalto dentro das muretas.
				if alat < wl + 1.1 and bridge[i] < 0.5:
					h = minf(h, plane - 0.3)
			height[i] = h
			beyond[i] = out_dist
			var ls := lake_sdf(x, z)
			sand[i] = 1.0 - smoothstep(0.5, 4.5, ls)
			lawn[i] = _flat_factor(x, z) * 0.8 * (1.0 - sand[i])


# ------------------------------------------------------------------ consultas

func in_bounds(x: float, z: float) -> bool:
	return x >= origin.x and z >= origin.y and x <= origin.x + cells * CELL and z <= origin.y + cells * CELL


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / CELL, 0.0, float(cells) - 0.001)
	var fz := clampf((z - origin.y) / CELL, 0.0, float(cells) - 0.001)
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i00 := iz * res + ix
	var a := lerpf(arr[i00], arr[i00 + 1], tx)
	var b := lerpf(arr[i00 + res], arr[i00 + res + 1], tx)
	return lerpf(a, b, tz)


func height_at(x: float, z: float) -> float:
	if not in_bounds(x, z):
		return far_height(x, z)
	return _bilinear(height, x, z)


## Distância (m) além da face externa da mureta mais próxima (negativo = dentro da pista).
func beyond_wall_at(x: float, z: float) -> float:
	if not in_bounds(x, z):
		return 999.0
	return _bilinear(beyond, x, z)


func track_distance_at(x: float, z: float) -> float:
	if not in_bounds(x, z):
		return MAX_TRACK_DIST
	return _bilinear(dist, x, z)


func normal_at(x: float, z: float) -> Vector3:
	var e := CELL
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func add_blocker(center: Vector2, radius: float) -> void:
	blockers.append(Vector3(center.x, center.y, radius))


func is_blocked(x: float, z: float, margin: float = 0.0) -> bool:
	for b in blockers:
		var dx := x - b.x
		var dz := z - b.y
		var r := b.z + margin
		if dx * dx + dz * dz < r * r:
			return true
	return false


## Terreno livre para cenário: `min_beyond` metros além das muretas, fora do lago e das áreas bloqueadas.
func is_free(x: float, z: float, min_beyond: float, margin: float = 0.0) -> bool:
	if beyond_wall_at(x, z) < min_beyond:
		return false
	if lake_sdf(x, z) < 3.0 + margin:
		return false
	return not is_blocked(x, z, margin)
