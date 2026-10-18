extends Node
## Teste de jogabilidade headless: corrida 2P completa com piloto automático + eventos de item forçados.
## Uso (rápido, tempo simulado):
##   Godot_console.exe --headless --fixed-fps 60 --path <projeto> res://tools/validate/validate_gameplay.tscn
## Verifica: karts andam e passam checkpoints, não caem, não atravessam muretas, caixas coletadas,
## os 4 itens com efeito (turbo acelera, banana derruba, foguete reto de 3 s atordoa/explode na mureta,
## escudo bloqueia banana e foguete), drift com mini-turbo por nível,
## faixas de turbo aceleram, voltas contam e a corrida termina. NPCs (4): completam as voltas sem
## ficar presos, usam itens; largada com boost (acelerar desde o "3"); Pulso (5º item) desacelera quem
## está à frente e é bloqueado pelo escudo. Sai com código 0 se tudo passar.

const RACE_SCENE := "res://scenes/race.tscn"

var race: Race
var _checks := 0
var _done := false
var _fails := 0
var _wall_viol: Array[int] = []
var _fall_viol: Array[int] = []
var _slow_run: Array[float] = []     ## tempo contínuo parado (s) por kart
var _max_slow_run: Array[float] = []
var _events_done := {}
var _pending: Array[Dictionary] = []   ## {t, fn}
var _pads_seen := [0, 0]
var _pad_ok := 0
var _stun_seen := false
var _spin_seen := false
var _lap_marks := [[], []]
var _prev_lap := [0, 0]
var _pads: Array[Dictionary] = []
var _grace: Array[float] = []
var _saved: Array = []
var _rockets := {}


var _celeb_frames := 0
var _celeb_ok := false
var _celeb_speed := 0.0

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
	race.end_when_humans_done = false
	add_child(race)
	race.race_finished.connect(_on_finished)
	while race.karts.size() < 2:
		await get_tree().physics_frame
	race.forced_item = Kart.Item.TURBO
	var n := race.karts.size()
	for arr: Array in [_wall_viol, _fall_viol]:
		arr.resize(n)
		arr.fill(0)
	for arr: Array in [_slow_run, _max_slow_run, _grace]:
		arr.resize(n)
		arr.fill(0.0)
	_check(n == 6 and race.karts[2].ai != null and race.karts[5].ai != null and race.karts[0].ai == null, "grid com 2 humanos + 4 NPCs (%d karts)" % n)
	# Largada: o NPC à frente do P1 acelera no "3"; o último NPC acelera tarde (sem boost).
	race.karts[4].ai.start_press = 2.95
	race.karts[5].ai.start_press = 1.0
	_test_wheels()
	_test_drivers()
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


## ETs: mãos alcançam o volante (IK) em qualquer esterço, cabem no kart e as poses de vitória/derrota funcionam.
func _test_drivers() -> void:
	for ch in 2:
		var m := KartModel.new()
		var cfg := PlayerConfig.new()
		cfg.set_color(Palette.BLUE)
		cfg.character = ch
		m.build(cfg)
		add_child(m)
		var dr := m.driver
		var werr := 0.0
		var gdist := 0.0
		for st: float in [-1.0, 0.0, 1.0]:
			for f in 20:
				m.animate(12.0, st, 1.0 / 60.0, 0.0)
			werr = maxf(werr, dr.wrist_error)
			for i in 2:
				var g := m._grip(-1.0 if i == 0 else 1.0)
				gdist = maxf(gdist, dr.hands[i].position.distance_to(g))
		var nm := AlienDriver.NAMES[ch]
		_check(werr < 0.005 and gdist < 0.08, "%s: mãos no volante em todo o esterço (IK: erro %.3f m, punho-pega %.3f m)" % [nm, werr, gdist])
		# Cabe no kart: cabeça acima/atrás do volante, dentro da largura do kart e abaixo de 1,8 m.
		var hm := dr.head.get_node("HeadMesh") as MeshInstance3D
		var hb := hm.mesh.get_aabb()
		var hx := m.tilt_root.transform.affine_inverse() * dr.head.global_transform
		var head_box := AABB()
		for c in 8:
			var p: Vector3 = (m.global_transform.affine_inverse() * dr.head.global_transform) * hb.get_endpoint(c)
			head_box = AABB(p, Vector3.ZERO) if c == 0 else head_box.expand(p)
		var sw := m.steering_wheel.position
		_check(head_box.end.y < 1.8 and head_box.size.x < 0.8 and head_box.position.z > sw.z + 0.13 and hx.origin.y > 0.0,
			"%s: cabeça cabe no kart (topo %.2f m, largura %.2f, frente z %.2f vs volante %.2f)" % [nm, head_box.end.y, head_box.size.x, head_box.position.z, sw.z])
		m.set_pose(AlienDriver.Pose.VICTORY)
		var max_hop := 0.0
		for f in 90:
			m.animate(0.0, 0.0, 1.0 / 60.0, 0.0)
			max_hop = maxf(max_hop, dr.hop)
		var hand_up := dr.hands[0].position.y > dr.head.position.y - 0.05 and dr.hands[1].position.y > dr.head.position.y - 0.05
		_check(dr.v_amount > 0.99 and max_hop > 0.05 and hand_up and (dr.fingers[1][0] as Node3D).basis.x.x < 0.999,
			"%s: vitória com pulinhos e sinal de paz nas duas mãos (pulo %.2f m)" % [nm, max_hop])
		m.set_pose(AlienDriver.Pose.DEFEAT)
		var yaw_min := 0.0
		var yaw_max := 0.0
		for f in 90:
			m.animate(0.0, 0.0, 1.0 / 60.0, 0.0)
			yaw_min = minf(yaw_min, dr.head.rotation.y)
			yaw_max = maxf(yaw_max, dr.head.rotation.y)
		_check(dr.head_pitch < -0.35 and yaw_max - yaw_min > 0.4, "%s: derrota com cabeça baixa balançando" % nm)
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


func _physics_process(delta: float) -> void:
	if race != null and race.state == Race.State.CELEBRATION:
		_celeb_frames += 1
		if _celeb_frames == 1:
			_celeb_ok = race.winner >= 0 and not race._results.visible
			for i in race.karts.size():
				var want := AlienDriver.Pose.VICTORY if i == race.winner else AlienDriver.Pose.DEFEAT
				_celeb_ok = _celeb_ok and race.karts[i].model.driver.pose == want
		_celeb_speed = maxf(_celeb_speed, absf(race.karts[race.winner].speed) if _celeb_frames > 10 else 0.0)
	if race != null and race.karts.size() >= 6 and race.state == Race.State.RACING and not _events_done.has("start"):
		_events_done["start"] = true
		_later(0.55, _test_start_boost)
	if race == null or race.karts.size() < 2 or race.state == Race.State.COUNTDOWN:
		return
	var tp := race.tp
	var t := race.race_time
	for i in race.karts.size():
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
		# "Preso": parado com controle e sem estar atordoado/rodopiando/terminado.
		if k.control_enabled and not k.finished and k.stun_time <= 0.0 and k.spin_time <= 0.0 and absf(k.speed) < 2.0:
			_slow_run[i] += delta
			_max_slow_run[i] = maxf(_max_slow_run[i], _slow_run[i])
		else:
			_slow_run[i] = 0.0
		if k.ai != null:
			continue
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
	_event(56.0, "pulse", _test_pulse)
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
	race.add_hazard(b, off, lat)  # os NPCs desviam (a casca é para o kart testado)
	return b


func _test_banana() -> void:
	var k := race.karts[1]
	# Com 6 karts, o P2 pode estar atordoado/invulnerável por um item dos NPCs: zera para o teste.
	k.stun_time = 0.0
	k.spin_time = 0.0
	k.slow_time = 0.0
	k.shield_time = 0.0
	k.invuln_time = 0.0
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
		_check(k.stats["hits"] == h0 and k.stats["blocked"] >= b0 + 1, "escudo bloqueia a banana (acertos +%d, bloqueios +%d)" % [k.stats["hits"] - h0, k.stats["blocked"] - b0])
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
		if _npc_near(o):
			o += 10.0
			continue
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


## Algum NPC no trecho [o-15, o+60] (atrapalharia a linha de tiro dos testes do foguete).
func _npc_near(o: float) -> bool:
	for k in race.karts:
		if k.ai != null:
			var d := race.tp.delta_offset(o, k.track_offset)
			if d > -15.0 and d < 60.0:
				return true
	return false


## Largada com boost: quem acelerou desde o "3" larga com turbo; quem acelerou tarde, não.
func _test_start_boost() -> void:
	var k0 := race.karts[0]
	var late := race.karts[5]
	var ok: bool = k0.stats["start_boost"] == 1 and race.karts[1].stats["start_boost"] == 1 and race.karts[4].stats["start_boost"] == 1
	_check(ok, "largada com boost para quem acelerou desde o 3 (P1, P2 e NPC)")
	_check(late.stats["start_boost"] == 0, "sem boost para quem acelerou tarde (NPC)")
	_check(k0.speed > 15.0 and late.speed < 12.0, "boost de largada acelera: %.1f m/s x %.1f m/s sem boost" % [k0.speed, late.speed])


## Pulso UNIFEOB: o último usa; todos à frente ficam eletrizados/lentos, exceto quem tem escudo.
func _test_pulse() -> void:
	var user: Kart = null
	for k in race.karts:
		if not k.finished and (user == null or race.progress_of(k.player_index) < race.progress_of(user.player_index)):
			user = k
	var ahead: Array[Kart] = []
	for k in race.karts:
		# (quem já está com escudo/invulnerável é bloqueado de qualquer jeito: fica fora da conta)
		if k != user and not k.finished and not k.is_shielded() and race.progress_of(k.player_index) > race.progress_of(user.player_index):
			ahead.append(k)
	var shielded := ahead[0]
	shielded.shield_time = 4.0
	var b0: int = shielded.stats["blocked"]
	var p0: int = shielded.stats["pulsed"]
	var n0 := race.objects_root.get_child_count()
	user.give_item(Kart.Item.PULSE)
	user.use_item()
	var slowed := 0
	for k in ahead:
		if k != shielded and k.slow_time > 0.0:
			slowed += 1
	_check(ahead.size() >= 2 and slowed == ahead.size() - 1, "Pulso eletriza os %d karts à frente sem escudo (%d)" % [ahead.size() - 1, slowed])
	_check(user.slow_time == 0.0 and race.objects_root.get_child_count() == n0 + 1, "Pulso não afeta quem usou e gera a onda de choque")
	_check(shielded.stats["pulsed"] == p0 and shielded.stats["blocked"] == b0 + 1 and shielded.slow_time == 0.0, "escudo bloqueia o Pulso")
	_later(1.4, func() -> void:
		var slow_ok := 0
		for k in ahead:
			if k != shielded and k.speed < Kart.MAX_SPEED * Kart.SLOW_FACTOR + 1.5:
				slow_ok += 1
		_check(slow_ok == ahead.size() - 1, "Pulso desacelera (%d de %d abaixo de %.0f m/s)" % [slow_ok, ahead.size() - 1, Kart.MAX_SPEED * Kart.SLOW_FACTOR + 1.5]))


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
	# NPCs.
	var ai_used := [0, 0, 0, 0, 0, 0]
	for i in range(2, race.karts.size()):
		var k := race.karts[i]
		var d := race.data[i]
		var nm := k.config.display_name
		print("[gameplay] NPC %s: %dº em %s%s | checkpoints %d | itens usados %s | acertos %d | respawns %d | parado máx %.1f s | largada %d" % [
			nm, d["place"], Race.format_time(d["finish_time"]), " (estimado)" if d["forced"] else "", d["count"],
			str(k.stats["used"]), k.stats["hits"], k.stats["respawns"], _max_slow_run[i], k.stats["start_boost"]])
		_check(k.finished and not d["forced"] and d["count"] == race.laps * race.cps.size() + 1, "NPC %s completou as %d voltas" % [nm, race.laps])
		_check(k.stats["respawns"] <= 2 and _max_slow_run[i] < 4.0 and _wall_viol[i] == 0 and _fall_viol[i] == 0,
			"NPC %s não ficou preso (respawns %d, parado máx %.1f s, fora da mureta %d)" % [nm, k.stats["respawns"], _max_slow_run[i], _wall_viol[i]])
		var u := 0
		for it in 6:
			u += k.stats["used"][it]
			ai_used[it] += k.stats["used"][it]
		_check(u >= 2, "NPC %s usou itens (%d)" % [nm, u])
	var kinds := 0
	for it in range(1, 6):
		kinds += 1 if ai_used[it] > 0 else 0
	_check(kinds >= 3, "NPCs usaram vários tipos de item: %s" % str(ai_used))
	for i in race.karts.size():
		if race.data[i]["place"] == 1:
			print("[gameplay] vencedor: %s" % race.racer_name(i))
	var chars: Array[int] = []
	for i in range(2, race.karts.size()):
		chars.append(race.karts[i].model.character)
	_check(chars.count(0) == 2 and chars.count(1) == 2, "NPCs usam os dois ETs %s" % str(chars))
	_check(race.celebration_played and _celeb_ok and _celeb_frames >= int(Race.CELEBRATION_TIME * 60.0) - 5 and _celeb_speed < 0.5,
		"comemoração tocou antes do resultado (%d quadros, 1º vitória / demais derrota, karts parados)" % _celeb_frames)
	for key: String in ["turbo", "banana", "shield_banana", "rocket", "shield_rocket", "drift_levels", "start", "pulse"]:
		_check(_events_done.has(key), "evento '%s' executado" % key)
	var used := [0, 0, 0, 0, 0, 0]
	for k in race.karts:
		for it in 6:
			used[it] += k.stats["used"][it]
	_check(used[1] > 0 and used[2] > 0 and used[3] > 0 and used[4] > 0 and used[5] > 0, "itens usados por tipo: %s" % str(used))
	print("[gameplay] %d verificações, %d falhas (tempo de corrida %.1f s)" % [_checks, _fails, race.race_time])
	_done = true
	AudioManager.quit_clean(0 if _fails == 0 else 1)
