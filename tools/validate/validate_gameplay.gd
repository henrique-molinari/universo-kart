extends Node
## Teste de jogabilidade headless: corrida 2P completa com piloto automático + eventos de item forçados.
## Uso (rápido, tempo simulado):
##   Godot_console.exe --headless --fixed-fps 60 --path <projeto> res://tools/validate/validate_gameplay.tscn
## Verifica: karts andam e passam checkpoints, não caem, não atravessam muretas, caixas coletadas,
## os 4 itens com efeito (turbo acelera, banana derruba, foguete reto de 3 s atordoa/explode na mureta,
## escudo bloqueia banana e foguete), drift com mini-turbo por nível,
## faixas de turbo aceleram, voltas contam e a corrida termina. Sai com código 0 se tudo passar.

const RACE_SCENE := "res://scenes/race.tscn"

var race: Race
var _checks := 0
var _done := false
var _fails := 0
var _wall_viol := [0, 0]
var _fall_viol := [0, 0]
var _events_done := {}
var _pending: Array[Dictionary] = []   ## {t, fn}
var _pads_seen := [0, 0]
var _pad_ok := 0
var _stun_seen := false
var _spin_seen := false
var _lap_marks := [[], []]
var _prev_lap := [0, 0]
var _pads: Array[Dictionary] = []
var _grace := [0.0, 0.0]
var _saved: Array = []
var _rockets := {}


func _ready() -> void:
	get_tree().create_timer(900.0, true, true, true).timeout.connect(func() -> void:
		if _done:
			return
		printerr("[gameplay] TIMEOUT")
		get_tree().quit(3))
	var packed := load(RACE_SCENE) as PackedScene
	race = packed.instantiate() as Race
	race.build_scenery = false
	race.autopilot = true
	add_child(race)
	race.race_finished.connect(_on_finished)
	while race.karts.size() < 2:
		await get_tree().physics_frame
	race.forced_item = Kart.Item.TURBO
	_test_wheels()
	_pads = race.tp.get_boost_pads()


## Rodas do modelo: simétricas, centradas no eixo, encostando no chão, giro só no X local,
## esterço só nas dianteiras e sem rolar junto com a carroceria.
func _test_wheels() -> void:
	var m := KartModel.new()
	var cfg := PlayerConfig.new()
	cfg.set_color(Palette.MAGENTA)
	m.build(cfg)
	add_child(m)
	var p := m.wheel_pivots
	var sym := true
	for pair: Array in [[0, 1], [2, 3]]:
		var a: Vector3 = p[pair[0]].position
		var b: Vector3 = p[pair[1]].position
		sym = sym and is_equal_approx(a.x, -b.x) and is_equal_approx(a.y, b.y) and is_equal_approx(a.z, b.z) and a.x < 0.0
	_check(sym and p.size() == 4, "rodas simétricas esquerda/direita")
	var grounded := true
	var centered := true
	for i in 4:
		grounded = grounded and absf(p[i].position.y - m.wheel_radius[i]) < 0.02
		var mi := m.wheels[i].get_child(0) as MeshInstance3D
		var bb := mi.mesh.get_aabb()
		centered = centered and absf(bb.get_center().x) < 0.02 and absf(bb.get_center().y) < 0.02 and absf(bb.get_center().z) < 0.02
		grounded = grounded and absf(bb.size.y * 0.5 - m.wheel_radius[i]) < 0.03
	_check(grounded, "rodas encostam no chão (centro na altura do raio)")
	_check(centered, "malha de cada roda centrada no eixo (sem bamboleio)")
	for n in 30:
		m.animate(18.0, 1.0, 1.0 / 60.0, 0.0)
	var axis_ok := true
	for i in 4:
		var bs := m.wheels[i].basis
		axis_ok = axis_ok and bs.x.is_equal_approx(Vector3.RIGHT) and bs.is_conformal() and m.wheels[i].position == Vector3.ZERO
	_check(axis_ok and m.wheels[0].basis.y.dot(Vector3.UP) < 0.99, "rodas giram só no eixo X local")
	var steer_ok := absf(p[0].rotation.y) > 0.1 and absf(p[1].rotation.y) > 0.1 and p[2].rotation.y == 0.0 and p[3].rotation.y == 0.0
	_check(steer_ok, "esterço só nas rodas dianteiras")
	_check(p[0].get_parent() == m.body_root and m.tilt_root.rotation.z != 0.0, "carroceria inclina sem arrastar as rodas")
	m.queue_free()


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("[gameplay] OK   ", msg)
	else:
		_fails += 1
		printerr("[gameplay] FALHA ", msg)


func _later(dt: float, fn: Callable) -> void:
	_pending.append({"t": race.race_time + dt, "fn": fn})


func _physics_process(_delta: float) -> void:
	if race == null or race.karts.size() < 2 or race.state == Race.State.COUNTDOWN:
		return
	var tp := race.tp
	var t := race.race_time
	for i in 2:
		var k := race.karts[i]
		var off := k.track_offset
		var lat := tp.get_lateral(k.global_position, off)
		var side := -1 if lat < 0.0 else 1
		var checking: bool = t > _grace[i] and k._pending_teleport == null
		if checking and absf(lat) > tp.get_wall_lateral(off, side) + 0.25:
			_wall_viol[i] += 1
		if checking and k.global_position.y < tp.get_height(off) - 4.0:
			_fall_viol[i] += 1
		if k.stun_time > 0.0:
			_stun_seen = true
		if k.spin_time > 0.0:
			_spin_seen = true
		# Mira as faixas de turbo (o piloto automático passa por cima delas).
		k.autopilot_lateral = -1.75 if i == 0 else 1.75
		for pad in _pads:
			var d := tp.delta_offset(off, pad["offset"])
			if d > 0.0 and d < 70.0:
				k.autopilot_lateral = pad["lateral"]
		if k.stats["pads"] > _pads_seen[i]:
			_pads_seen[i] = k.stats["pads"]
			var kk := k
			_later(0.7, func() -> void:
				if kk.speed > Kart.MAX_SPEED + 2.0:
					_pad_ok += 1)
		var lap: int = race.data[i]["lap"]
		if lap != _prev_lap[i]:
			_prev_lap[i] = lap
			_lap_marks[i].append(t)

	for j in range(_pending.size() - 1, -1, -1):
		if t >= _pending[j]["t"]:
			var fn: Callable = _pending[j]["fn"]
			_pending.remove_at(j)
			fn.call()

	if race.karts[0].boost_time <= 0.0 and race.karts[0].speed < Kart.MAX_SPEED + 0.5:
		_event(8.0, "turbo", _test_turbo)
	_event(14.0, "banana", _test_banana)
	_event(24.0, "shield_banana", _test_shield_banana)
	_event(20.0, "drift_levels", _test_drift_levels)
	_event(34.0, "rocket", _test_rocket)
	_event(48.0, "shield_rocket", _test_shield_rocket)
	# Drift real (piloto automático com drift) no P2 durante a 2ª volta: turbos por nível + física intacta.
	if t >= 60.0 and not _events_done.has("drift_on"):
		_events_done["drift_on"] = true
		race.karts[1].autopilot_drift = true
	if t >= 140.0 and race.karts[1].autopilot_drift:
		race.karts[1].autopilot_drift = false


func _event(at: float, key: String, fn: Callable) -> void:
	if race.race_time >= at and not _events_done.has(key):
		_events_done[key] = true
		fn.call()


func _test_turbo() -> void:
	var k := race.karts[0]
	var v0 := k.speed
	k.give_item(Kart.Item.TURBO)
	k.use_item()
	_later(0.7, func() -> void:
		_check(k.speed > v0 + 3.0 and k.speed > Kart.MAX_SPEED + 2.0, "turbo (item) acelera: %.1f -> %.1f m/s" % [v0, k.speed]))


func _banana_ahead(k: Kart) -> Area3D:
	var tp := race.tp
	var off := k.track_offset + 14.0
	var lat := tp.get_lateral(k.global_position, k.track_offset)
	var b := RaceObjects.make_banana(tp.to_world(off, lat, 0.0), tp.get_up(off), null)
	race.objects_root.add_child(b)
	return b


func _test_banana() -> void:
	var k := race.karts[1]
	var h0: int = k.stats["hits"]
	_spin_seen = false
	var dropper := race.karts[0]
	var n0 := race.objects_root.get_child_count()
	dropper.give_item(Kart.Item.BANANA)
	dropper.use_item()
	_check(race.objects_root.get_child_count() == n0 + 1, "usar BANANA larga uma casca atrás do kart")
	var bid := _banana_ahead(k).get_instance_id()
	_later(2.0, func() -> void:
		_check(k.stats["hits"] == h0 + 1 and _spin_seen, "banana derruba o kart (rodopio + perde velocidade)")
		_check(not is_instance_id_valid(bid), "banana some após atingir"))


func _test_shield_banana() -> void:
	var k := race.karts[1]
	var h0: int = k.stats["hits"]
	var b0: int = k.stats["blocked"]
	k.give_item(Kart.Item.SHIELD)
	k.use_item()
	var bid := _banana_ahead(k).get_instance_id()
	_later(2.0, func() -> void:
		_check(k.stats["hits"] == h0 and k.stats["blocked"] == b0 + 1, "escudo bloqueia a banana")
		_check(not is_instance_id_valid(bid), "banana some ao bater no escudo"))


func _teleport(k: Kart, off: float, lat: float) -> void:
	k._pending_teleport = race.tp.get_transform_at(off, lat, 0.0)
	k.track_offset = race.tp.wrap_offset(off)
	k.speed = 0.0
	_grace[k.player_index] = race.race_time + 0.4


func _freeze(on: bool) -> void:
	for k in race.karts:
		k.control_enabled = not on


## Trecho reto à frente de `from_off` (curvatura baixa por 50 m).
func _find_straight(from_off: float) -> float:
	var tp := race.tp
	var best := from_off
	var best_c := INF
	var o := from_off
	while o < from_off + 600.0:
		var c := 0.0
		var s := 0.0
		while s <= 50.0:
			c = maxf(c, absf(tp.get_curvature(o + s)))
			s += 5.0
		if c < best_c:
			best_c = c
			best = o
		if c < 0.003:
			break
		o += 10.0
	return tp.wrap_offset(best)


func _newest_rocket() -> Rocket:
	var r: Rocket = null
	for c in race.objects_root.get_children():
		if c is Rocket and not c.is_queued_for_deletion():
			r = c
	return r


func _track_rocket(r: Rocket, key: String) -> void:
	_rockets[key] = {"reason": "", "age": -1.0, "turn": 0.0, "id": r.get_instance_id()}
	r.exploded.connect(func(reason: String, age: float) -> void:
		_rockets[key] = {"reason": reason, "age": age, "turn": r.max_turn})


func _rk(key: String, field: String, def: Variant) -> Variant:
	var d: Dictionary = _rockets.get(key, {})
	if field == "turn" and d.has("id") and is_instance_id_valid(d["id"]):
		return (instance_from_id(d["id"]) as Rocket).max_turn
	return d.get(field, def)


## Foguete: vai reto (sem homing), dura 3 s, acerta kart em linha reta, explode na mureta.
func _test_rocket() -> void:
	var shooter := race.karts[0]
	var target := race.karts[1]
	for k in race.karts:
		_saved.append([k.track_offset, race.tp.get_lateral(k.global_position, k.track_offset)])
	var o := _find_straight(shooter.track_offset)
	_freeze(true)
	target.shield_time = 0.0
	_teleport(shooter, o, 0.0)
	_teleport(target, o + 16.0, 4.6)   # fora da linha de tiro: não pode ser perseguido
	var h0: int = target.stats["hits"]
	_later(0.3, func() -> void:
		shooter.give_item(Kart.Item.ROCKET)
		shooter.use_item()
		var r := _newest_rocket()
		_check(r != null, "usar FOGUETE dispara um foguete")
		if r != null:
			_check(r.direction.dot(shooter._flat_forward()) > 0.999, "foguete sai na direção do kart")
			_track_rocket(r, "offline"))
	_later(1.6, func() -> void:
		var turn: float = _rk("offline", "turn", 1.0)
		_check(target.stats["hits"] == h0, "foguete NÃO persegue kart fora da linha (sem homing)")
		_check(turn < 0.01, "foguete voa reto (desvio máx. %.4f rad, fim: %s)" % [turn, _rk("offline", "reason", "?")])
		_teleport(target, o + 26.0, 0.0))
	_later(1.9, func() -> void:
		shooter.give_item(Kart.Item.ROCKET)
		shooter.use_item()
		var r := _newest_rocket()
		if r != null:
			_track_rocket(r, "inline"))
	_later(3.2, func() -> void:
		_check(target.stats["hits"] == h0 + 1 and target.stun_time > 0.0 and target.speed < 1.0,
			"foguete acerta kart em linha reta (atordoado, velocidade %.1f)" % target.speed)
		var turn: float = _rk("inline", "turn", 1.0)
		_check(_rk("inline", "reason", "") == "kart" and turn < 0.01, "impacto no kart: %s após %.2f s" % [_rk("inline", "reason", "?"), _rk("inline", "age", -1.0)])
		# Mureta: disparo lateral.
		var r := Rocket.new()
		r.setup(shooter, race.karts, shooter.global_position + race.tp.get_right(o) * 1.5 + Vector3.UP * 0.2, race.tp.get_right(o))
		race.objects_root.add_child(r)
		_track_rocket(r, "wall")
		# Duração: área aberta sem muretas.
		var lane := _open_lane()
		_check(not lane.is_empty(), "achou área aberta para o teste de duração")
		if not lane.is_empty():
			var r2 := Rocket.new()
			r2.setup(null, race.karts, lane[0], lane[1])
			race.objects_root.add_child(r2)
			_track_rocket(r2, "open"))
	_later(7.0, func() -> void:
		var wage: float = _rk("wall", "age", 9.0)
		_check(_rk("wall", "reason", "") == "wall" and wage < 0.8, "foguete explode na mureta (%s, %.2f s)" % [_rk("wall", "reason", "?"), wage])
		var oage: float = _rk("open", "age", 0.0)
		var oturn: float = _rk("open", "turn", 1.0)
		_check(_rk("open", "reason", "") == "timeout" and absf(oage - Rocket.LIFETIME) < 0.1 and oturn < 0.01,
			"foguete dura %.1f s e some (%s após %.2f s, desvio %.4f)" % [Rocket.LIFETIME, _rk("open", "reason", "?"), oage, oturn])
		_restore())


func _restore() -> void:
	for i in 2:
		var sv: Array = _saved[i]
		_teleport(race.karts[i], sv[0], sv[1])
	_saved.clear()
	_later(0.3, func() -> void: _freeze(false))


## Ponto + direção horizontais em que 160 m de voo não cruzam muretas nem a pista.
func _open_lane() -> Array:
	var tp := race.tp
	var space := race.get_viewport().world_3d.direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for trial in 300:
		var off := rng.randf_range(0.0, tp.length)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var start := tp.to_world(off, side * (tp.get_max_wall_lateral() + rng.randf_range(15.0, 40.0)))
		var ang := rng.randf_range(0.0, TAU)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var ok := true
		var prev := Vector3.INF
		var first := Vector3.INF
		var dist := 0.0
		while dist <= 160.0 and ok:
			var p := start + dir * dist
			var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 60.0, p - Vector3.UP * 80.0, PhysicsLayers.WORLD_ALL))
			if g.is_empty():
				ok = false
				break
			var col: Object = g["collider"]
			if not (col is CollisionObject3D) or ((col as CollisionObject3D).collision_layer & PhysicsLayers.WORLD_TERRAIN) == 0:
				ok = false
				break
			var gp: Vector3 = g["position"]
			gp += Vector3.UP * Rocket.HOVER
			if first == Vector3.INF:
				first = gp
			if prev != Vector3.INF:
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(prev, gp, Rocket.WALL_MASK | PhysicsLayers.WORLD_ROAD)).is_empty():
					ok = false
			prev = gp
			dist += 4.0
		if ok:
			return [first, dir]
	return []


func _test_shield_rocket() -> void:
	var shooter := race.karts[0]
	var target := race.karts[1]
	for k in race.karts:
		_saved.append([k.track_offset, race.tp.get_lateral(k.global_position, k.track_offset)])
	var o := _find_straight(shooter.track_offset)
	_freeze(true)
	_teleport(shooter, o, 0.0)
	_teleport(target, o + 24.0, 0.0)
	var h0: int = target.stats["hits"]
	var b0: int = target.stats["blocked"]
	_later(0.3, func() -> void:
		target.give_item(Kart.Item.SHIELD)
		target.use_item()
		shooter.give_item(Kart.Item.ROCKET)
		shooter.use_item())
	_later(1.8, func() -> void:
		_check(target.stats["hits"] == h0 and target.stats["blocked"] >= b0 + 1, "escudo bloqueia o foguete")
		_restore())


## Drift: cada nível solta o turbo certo (0,7 / 1,2 / 1,8 s); nível 0 não dá turbo.
func _test_drift_levels() -> void:
	var k := race.karts[0]
	var ok := true
	var got: Array[String] = []
	for lvl in range(1, 4):
		k.boost_time = 0.0
		k.drifting = true
		k.drift_dir = 1.0
		k.drift_charge = Kart.DRIFT_LEVEL_CHARGE[lvl] + 0.01
		k.drift_level = lvl
		k._end_drift(true)
		got.append("%.1f" % k.boost_time)
		ok = ok and is_equal_approx(k.boost_time, Kart.DRIFT_BOOST_TIME[lvl]) and not k.drifting
	k.drifting = true
	k.drift_level = 0
	k.boost_time = 0.0
	k._end_drift(true)
	ok = ok and k.boost_time == 0.0
	_check(ok, "drift: turbo por nível 1/2/3 = %s s (nível 0 não dá turbo)" % ", ".join(got))


func _on_finished() -> void:
	# Deixa os avaliadores pendentes rodarem.
	await get_tree().create_timer(0.5).timeout
	for i in 2:
		var k := race.karts[i]
		var d := race.data[i]
		var marks: Array = _lap_marks[i]
		var lap_times: Array[String] = []
		for j in range(1, marks.size()):
			lap_times.append("%.1f" % (float(marks[j]) - float(marks[j - 1])))
		lap_times.append("%.1f (última)" % (float(d["finish_time"]) - float(marks[marks.size() - 1])))
		print("[gameplay] P%d: %dº em %s | voltas: %s | checkpoints %d | caixas %d | itens usados %s | acertos %d | bloqueios %d | turbos de pista %d | respawns %d | vmáx %.1f m/s" % [
			i + 1, d["place"], Race.format_time(d["finish_time"]), ", ".join(lap_times), d["count"], k.stats["pickups"],
			str(k.stats["used"]), k.stats["hits"], k.stats["blocked"], k.stats["pads"], k.stats["respawns"], k.stats["max_speed"]])
		_check(k.finished, "P%d terminou as %d voltas" % [i + 1, race.laps])
		_check(d["count"] == race.laps * race.cps.size() + 1, "P%d passou todos os checkpoints em ordem (%d)" % [i + 1, d["count"]])
		_check(_wall_viol[i] == 0, "P%d não atravessou muretas (%d quadros fora)" % [i + 1, _wall_viol[i]])
		_check(_fall_viol[i] == 0 and k.stats["respawns"] <= 1, "P%d não caiu do mundo (respawns %d)" % [i + 1, k.stats["respawns"]])
		_check(k.stats["pickups"] > 0 and k.stats["used"][Kart.Item.TURBO] > 1, "P%d coletou caixas e usou itens" % (i + 1))
		_check(k.stats["pads"] > 0, "P%d passou por faixas de turbo" % (i + 1))
	_check(_pad_ok > 0, "faixa de turbo aumenta a velocidade (%d confirmações)" % _pad_ok)
	var k2 := race.karts[1]
	var db: Array = k2.stats["drift_boosts"]
	_check(k2.stats["drifts"] > 0 and db[1] + db[2] + db[3] > 0, "drift real gera mini-turbos (drifts %d, turbos por nível %s)" % [k2.stats["drifts"], str(db)])
	for key: String in ["turbo", "banana", "shield_banana", "rocket", "shield_rocket", "drift_levels"]:
		_check(_events_done.has(key), "evento '%s' executado" % key)
	var used := [0, 0, 0, 0, 0]
	for k in race.karts:
		for it in 5:
			used[it] += k.stats["used"][it]
	_check(used[1] > 0 and used[2] > 0 and used[3] > 0 and used[4] > 0, "itens usados por tipo: %s" % str(used))
	print("[gameplay] %d verificações, %d falhas (tempo de corrida %.1f s)" % [_checks, _fails, race.race_time])
	_done = true
	AudioManager.quit_clean(0 if _fails == 0 else 1)
