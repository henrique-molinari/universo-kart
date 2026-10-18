class_name AIDriver
extends RefCounted
## Piloto de IA: produz exatamente as mesmas entradas que o PlayerInput dá ao kart
## (in_steer, in_throttle, in_brake, in_drift, in_item). O Kart é o mesmo para humano e IA.
##
## Custo por quadro: só consultas ao TrackPath (amostras pré-calculadas) e aritmética; a análise de
## vizinhos/perigos roda a cada THINK_STEP s. Nenhuma alocação por quadro.
##
## Comportamento: linha de corrida (entra por dentro nas curvas), velocidade pela curvatura à frente
## (aceleração lateral limitada pela habilidade), drift com mini-turbo nas curvas fechadas, desvio de
## karts e bananas, uso tático dos itens com tempo de reação, largada com boost (às vezes) e
## rubber-band leve (±4-6% na velocidade máxima), sem teletransporte nem itens garantidos.

const THINK_STEP := 0.08
const LAT_ACCEL := 27.5            ## aceleração lateral de referência (m/s²) nas curvas
const AVOID_AHEAD := 16.0          ## distância à frente (m) para desviar de karts
const HAZARD_AHEAD := 24.0         ## distância à frente (m) para desviar de bananas
const AVOID_GAP := 2.3             ## distância lateral mínima desejada (m)

var kart: Kart
var race: Race
var tp: TrackPath
var skill := 1.0                   ## 0,9..1,0: curvas, reação e velocidade máxima
var lane := 0.0                    ## faixa preferida (m, lateral)
var start_press := 3.0             ## segundos restantes da contagem em que começa a acelerar
var rng := RandomNumberGenerator.new()

var _think := 0.0
var _target_lat := 0.0
var _avoid_lat := 0.0
var _avoiding := false
var _item_hold := 0.0
var _item_wait := 0.0
var _reverse := 0.0
var _lane_timer := 0.0
var _pads: Array[Dictionary] = []  ## faixas de turbo (offset/lateral), lidas uma vez
var _pad_chance := 0.8             ## chance de mirar cada faixa (varia pela habilidade)
var _pad_roll := true
var _pad_last := -1


func setup(k: Kart, race_node: Race, ai_index: int, seed_value: int) -> void:
	kart = k
	race = race_node
	tp = k.tp
	rng.seed = seed_value
	skill = rng.randf_range(0.92, 1.0)
	var hw := tp.get_half_width()
	lane = clampf(rng.randf_range(-0.35, 0.35) * hw, -hw + 2.0, hw - 2.0)
	# Metade dos NPCs costuma acertar a largada (acelera no "3"); os outros aceleram tarde.
	start_press = rng.randf_range(2.75, 2.98) if (ai_index % 2 == 0) == (rng.randf() < 0.8) else rng.randf_range(0.6, 1.6)
	_target_lat = lane
	_pads = tp.get_boost_pads()
	_pad_chance = lerpf(0.55, 0.9, (skill - 0.92) / 0.08)
	_pad_roll = rng.randf() < _pad_chance


## Chamado pelo Kart a cada quadro de física no lugar do PlayerInput.
func drive(delta: float) -> void:
	var k := kart
	k.in_item = false
	k.in_drift = false
	if race.state == Race.State.COUNTDOWN:
		k.in_steer = 0.0
		k.in_brake = 0.0
		k.in_throttle = 1.0 if race.countdown <= start_press else 0.0
		return
	var off := k.track_offset
	_think -= delta
	if _think <= 0.0:
		_think = THINK_STEP
		_plan(off)
	_update_rubber_band()

	# Direção: mira um ponto à frente na lateral desejada (suavizada).
	var hw := tp.get_half_width()
	var want := _avoid_lat if _avoiding else _target_lat
	want = clampf(want, -hw + 1.2, hw - 1.2)
	var look := 8.0 + absf(k.speed) * 0.5
	var target := tp.to_world(off + look, want)
	var to := target - k.global_position
	var fwd := k._flat_forward()
	var right := fwd.cross(k.ground_normal)
	var ang := atan2(to.dot(right), to.dot(fwd))
	k.in_steer = clampf(ang * 2.3, -1.0, 1.0)

	# Velocidade pela curvatura à frente.
	var curv := 0.0
	var s := 5.0
	while s <= 45.0:
		curv = maxf(curv, absf(tp.get_curvature(off + s)))
		s += 5.0
	var vmax := sqrt(LAT_ACCEL * skill / maxf(curv, 0.0001))
	k.in_throttle = 1.0 if k.speed < vmax else 0.0
	k.in_brake = 0.6 if k.speed > vmax + 4.0 else 0.0

	# Drift nas curvas fechadas (mesma regra testada do piloto automático).
	if k.speed > 12.0:
		var c_near := tp.get_curvature(off + 12.0) + tp.get_curvature(off + 20.0)
		var c_hold := tp.get_curvature(off + 6.0) + tp.get_curvature(off + 14.0)
		k.in_drift = absf(c_near) > 0.03 or (k.drifting and absf(c_hold) > 0.01)

	# Destravar: ré curta com a direção invertida se ficou parado encostado.
	if k.can_act() and absf(k.speed) < 1.0:
		_reverse += delta
	elif _reverse < 1.2:
		_reverse = 0.0
	if _reverse > 1.2:
		k.in_throttle = 0.0
		k.in_brake = 1.0
		k.in_steer = -k.in_steer
		k.in_drift = false
		_reverse += delta
		if _reverse > 2.3:
			_reverse = 0.0

	_update_items(delta, off, curv)


## Linha de corrida + desvio de karts e bananas (roda a cada THINK_STEP).
func _plan(off: float) -> void:
	var hw := tp.get_half_width()
	# Linha: entra por dentro da curva à frente (curvatura > 0 = esquerda = lateral negativa).
	var c := tp.get_curvature(off + 18.0 + absf(kart.speed) * 0.4)
	var inner := -clampf(c * 22.0, -1.0, 1.0) * hw * 0.45
	_lane_timer -= THINK_STEP
	if _lane_timer <= 0.0:
		_lane_timer = rng.randf_range(4.0, 9.0)
		lane = clampf(lane + rng.randf_range(-1.5, 1.5), -hw * 0.4, hw * 0.4)
	_target_lat = clampf(lane * 0.5 + inner, -hw + 1.5, hw - 1.5)
	# Mira a faixa de turbo à frente (sorteio por faixa: nem sempre acerta).
	for pi in _pads.size():
		var pd := tp.delta_offset(off, float(_pads[pi]["offset"]))
		if pd > -2.0 and pd < 70.0:
			if pi != _pad_last:
				_pad_last = pi
				_pad_roll = rng.randf() < _pad_chance
			if _pad_roll:
				_target_lat = float(_pads[pi]["lateral"])
			break

	var my_lat := tp.get_lateral(kart.global_position, off)
	var best_d := INF
	var block_lat := 0.0
	for o in race.karts:
		if o == kart:
			continue
		var d := tp.delta_offset(off, o.track_offset)
		if d <= 0.5 or d > AVOID_AHEAD or d >= best_d:
			continue
		# Só desvia de quem está mais lento ou muito perto.
		if o.speed > kart.speed + 1.0 and d > 5.0:
			continue
		var ol := tp.get_lateral(o.global_position, o.track_offset)
		if absf(ol - _target_lat) < AVOID_GAP:
			best_d = d
			block_lat = ol
	for h in race.hazards:
		if not is_instance_valid(h):
			continue
		var d := tp.delta_offset(off, float(h.get_meta(&"off")))
		if d <= 0.0 or d > HAZARD_AHEAD or d >= best_d:
			continue
		var hl := float(h.get_meta(&"lat"))
		if absf(hl - _target_lat) < AVOID_GAP:
			best_d = d
			block_lat = hl
	_avoiding = best_d < INF
	if _avoiding:
		# Passa pelo lado com mais espaço (preferindo o lado em que já está).
		var room_l := block_lat - (-hw)
		var room_r := hw - block_lat
		var side := -1.0 if my_lat < block_lat else 1.0
		if (side < 0.0 and room_l < AVOID_GAP + 1.4) or (side > 0.0 and room_r < AVOID_GAP + 1.4):
			side = -side
		_avoid_lat = block_lat + side * (AVOID_GAP + 0.4)


## Rubber-band leve: quem abriu muita vantagem sobre o melhor humano perde até 6% da velocidade
## máxima; quem ficou muito para trás ganha até 4%. Mais a habilidade base (até -3%).
func _update_rubber_band() -> void:
	var mine := race.progress_of(kart.player_index)
	var best_h := -INF
	for o in race.karts:
		if o.ai == null:
			best_h = maxf(best_h, race.progress_of(o.player_index))
	var mul := 1.0 - (1.0 - skill) * 0.3
	if best_h > -INF:
		var gap := mine - best_h
		if gap > 40.0:
			mul -= 0.06 * clampf((gap - 40.0) / 160.0, 0.0, 1.0)
		elif gap < -60.0:
			mul += 0.04 * clampf((-gap - 60.0) / 200.0, 0.0, 1.0)
	kart.top_speed_mul = mul


func _update_items(delta: float, off: float, curv: float) -> void:
	var k := kart
	if k.item == Kart.Item.NONE:
		_item_hold = 0.0
		_item_wait = rng.randf_range(0.35, 0.9) / skill
		return
	_item_hold += delta
	if _item_hold < _item_wait or not k.can_act():
		return
	var use := false
	match k.item:
		Kart.Item.TURBO:
			use = k.slow_time <= 0.0 and ((curv < 0.012 and k.surface == TrackPath.Surface.ROAD) or _item_hold > 6.0)
		Kart.Item.ROCKET:
			use = _target_in_line(off) or _item_hold > 12.0
		Kart.Item.BANANA:
			use = _kart_behind(off) or _item_hold > 9.0
		Kart.Item.SHIELD:
			use = _item_hold > 2.5
		Kart.Item.PULSE:
			use = race.data[k.player_index]["place"] > 1
	# Borda de subida, como um botão: o kart só usa ao passar de false para true.
	k.in_item = use


## Kart à frente, perto e alinhado com a frente (o foguete voa reto).
func _target_in_line(off: float) -> bool:
	var fwd := kart._flat_forward()
	for o in race.karts:
		if o == kart or o.finished:
			continue
		var d := tp.delta_offset(off, o.track_offset)
		if d < 6.0 or d > 45.0:
			continue
		var to := o.global_position - kart.global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.1:
			continue
		# Desvio lateral do alvo em relação à linha de tiro.
		if absf(to.dot(fwd.cross(Vector3.UP))) < 1.3 and to.dot(fwd) > 0.0:
			return true
	return false


func _kart_behind(off: float) -> bool:
	var my_lat := tp.get_lateral(kart.global_position, off)
	for o in race.karts:
		if o == kart:
			continue
		var d := tp.delta_offset(o.track_offset, off)
		if d > 3.0 and d < 18.0 and absf(tp.get_lateral(o.global_position, o.track_offset) - my_lat) < 2.5:
			return true
	return false
