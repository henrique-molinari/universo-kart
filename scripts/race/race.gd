class_name Race
extends Node
## Corrida 2P em split-screen (horizontal: P1 em cima, P2 embaixo), na pista do campus.
## Cria pista, karts, caixas de item, faixas de turbo, SubViewports/câmeras/HUDs, contagem,
## checkpoints (em ordem, anti-atalho), voltas, posições, chegada e tela de resultado.
##
## Argumentos de linha de comando (depois de `--`), para automação:
##   --autopilot            karts dirigidos pelo piloto automático
##   --shot=<arquivo.png>   salva a tela após --shot-time segundos de corrida e sai
##   --shot-time=<s>        (padrão 6)
##   --pause-shot           a captura é feita com o menu de pausa aberto
##   --closeup              câmera de perto no P1 (com drift automático); a captura espera um drift nível 2+
##   --celebrate=<i>        encerra a corrida logo após a largada com o kart <i> em 1º (captura da comemoração;
##                          a captura sai em --shot-time segundos de comemoração)
##
## A pista vem de GameState.ensure_track() (construída uma vez na splash e reaproveitada).

signal race_finished

enum State { COUNTDOWN, RACING, CELEBRATION, RESULTS }

const COUNTDOWN_TIME := 3.0
## Largada: nos primeiros segundos o pelotão está colado (e quem pega o boost alcança o da frente);
## trombadas aqui são macias (empurra junto, sem quicar/tremer), senão o kart dá um tranco no começo.
const START_SOFT_TIME := 2.5
const CP_WINDOW := 35.0
## Comemoração antes do resultado: plano 1 (cada tela mostra o próprio ET) e plano 2 (as duas mostram o vencedor).
const CELEBRATION_TIME := 6.0
const CELEBRATION_SHOT2 := 3.2
const SELECT_SCENE := "res://scenes/select.tscn"
const RACE_SCENE := "res://scenes/race.tscn"

@export var build_scenery: bool = true
@export var autopilot: bool = false

var track: Track
var tp: TrackPath
var karts: Array[Kart] = []
var cams: Array[ChaseCamera] = []
var huds: Array[PlayerHud] = []
var viewports: Array[SubViewport] = []
var item_boxes: Array[Area3D] = []
var boost_pads: Array[Area3D] = []
var objects_root: Node3D
var state: State = State.COUNTDOWN
var race_time := 0.0
var countdown := COUNTDOWN_TIME
var laps := 3
var cps := PackedFloat32Array()
var data: Array[Dictionary] = []  ## por kart: next, lap, count, finish_time, place, finished_order
var finish_count := 0
var forced_item: int = -1         ## testes: força o item das caixas (só dos humanos)
var human_count := 2
var hazards: Array[Area3D] = []   ## bananas na pista (meta off/lat), para a IA desviar
## true: quando os humanos terminam, os NPCs restantes recebem posição/tempo estimados.
## Os testes usam false para ver os NPCs completarem as voltas.
var end_when_humans_done := true
var _start_hold := PackedFloat32Array()  ## tempo acelerando sem soltar durante a contagem
var _prog := PackedFloat32Array()
var _order: Array[int] = []

var _humans_done_time := -1.0
var _results: Control
var _confirm_prev := [true, true]
var _cancel_prev := [true, true]
var _closeup := false
var _demo_items := PackedStringArray()  ## captura do HUD: itens fixos (índices de Kart.Item) sem usar
var _closeup_both := false  ## --closeup-still também no P2 (captura dos dois karts)
var _closeup_cam2: Camera3D
var _cam_view := ""  ## --closeup: front | side | top | (padrão 3/4)
var _pause_shot := false
var _closeup_still := false  ## captura do kart parado (3/4 de frente) durante a contagem
var _closeup_cam: Camera3D
var _last_lap_music := false
var _shot_path := ""
var _shot_time := 6.0
var _last_go := -1
var celebration_time := 0.0
var celebration_played := false
var winner := -1
var _celebrate_force := -1
var _celeb_cams: Array[Camera3D] = []
var _celeb_labels: Array[Label] = []
var _rim_lights: Array[OmniLight3D] = []
var pause_menu: PauseMenu = null
var _pause_prev := [true, true]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autopilot":
			autopilot = true
		elif a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-time="):
			_shot_time = a.substr(12).to_float()
		elif a == "--closeup":
			_closeup = true
		elif a.begins_with("--demo-items="):
			_demo_items = a.substr(13).split(",")
		elif a == "--closeup-both":
			_closeup_both = true
		elif a.begins_with("--cam="):
			_cam_view = a.substr(6)
		elif a.begins_with("--celebrate="):
			_celebrate_force = a.substr(12).to_int()
		elif a == "--pause-shot":
			_pause_shot = true
		elif a == "--closeup-still":
			_closeup = true
			_closeup_still = true
	GameState.num_local_players = 2
	laps = GameState.laps
	SceneRouter.scene_leaving.connect(_on_scene_leaving)
	PlayerInput.refresh()
	Input.joy_connection_changed.connect(_on_joy_changed)

	track = GameState.ensure_track(build_scenery)
	if not track.is_ready:
		await track.track_ready
	RenderQuality.apply_to_environment(track.world_environment.environment, GameState.quality, true)
	tp = track.track_path
	cps = tp.get_checkpoint_offsets()
	objects_root = Node3D.new()
	objects_root.name = "RaceObjects"
	add_child(objects_root)

	# Humanos largam no fim do grid (como no Mario Kart); os NPCs ocupam as primeiras vagas.
	var ai_cfgs := GameState.build_ai_configs(GameState.num_ai)
	var total := human_count + ai_cfgs.size()
	var seed_base := randi()
	var t_build := Time.get_ticks_msec()
	for i in total:
		var human := i < human_count
		var cfg: PlayerConfig = GameState.get_player(i) if human else ai_cfgs[i - human_count]
		var k := Kart.new()
		k.setup(cfg, i, tp, self)
		add_child(k)
		var slot := (ai_cfgs.size() + i) if human else (i - human_count)
		k.place(tp.get_grid_transform(slot))
		if human:
			k.autopilot = autopilot
			k.autopilot_lateral = -1.75 if i == 0 else 1.75
		else:
			k.ai = AIDriver.new()
			k.ai.setup(k, self, i - human_count, seed_base + i * 7919)
		karts.append(k)
		data.append({"next": 0, "lap": 0, "count": 0, "finish_time": 0.0, "place": i + 1, "forced": false})
		_order.append(i)
	print("[Race] %d karts prontos em %d ms" % [total, Time.get_ticks_msec() - t_build])
	_start_hold.resize(total)
	_prog.resize(total)

	for row in tp.get_item_rows():
		var off: float = row["offset"]
		for p: Vector3 in row["positions"]:
			var box := RaceObjects.make_item_box(p, tp.get_up(off), _on_box_picked)
			objects_root.add_child(box)
			item_boxes.append(box)
	for pad in tp.get_boost_pads():
		var a := RaceObjects.make_boost_pad(pad["transform"], pad["length"])
		objects_root.add_child(a)
		boost_pads.append(a)

	_build_split_screen()
	for h in huds:
		h.show_message("3")
	AudioManager.play_music(&"race")
	AudioManager.set_music_tempo(1.0)
	for i in mini(_demo_items.size(), karts.size()):
		karts[i].autopilot_use_items = false
		karts[i].give_item(_demo_items[i].to_int())
	if _closeup:
		karts[0].autopilot = true
		karts[0].autopilot_drift = true
		karts[0].autopilot_use_items = false
		_closeup_cam = Camera3D.new()
		_closeup_cam.fov = 50.0
		_closeup_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		viewports[0].add_child(_closeup_cam)
		_closeup_cam.current = true
		if _closeup_still:
			for h in huds:
				h.visible = false  # captura limpa do kart (sem a contagem do HUD)
		if _closeup_both:
			_closeup_cam2 = Camera3D.new()
			_closeup_cam2.fov = 50.0
			_closeup_cam2.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			viewports[1].add_child(_closeup_cam2)
			_closeup_cam2.current = true
	print("[Race] pronta: %d karts, %d caixas, %d turbos, %d checkpoints, %d voltas, pads=%s" % [karts.size(), item_boxes.size(), boost_pads.size(), cps.size(), laps, str(PlayerInput.slots)])


func _on_joy_changed(device: int, connected: bool) -> void:
	PlayerInput.refresh()
	print("[Race] controle %d %s -> slots %s" % [device, "conectado" if connected else "desconectado", str(PlayerInput.slots)])


# ------------------------------------------------------------------ split-screen

func _build_split_screen() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Screens"
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override(&"separation", 4)
	layer.add_child(box)
	for i in 2:
		var cont := SubViewportContainer.new()
		cont.stretch = true
		cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(cont)
		var vp := SubViewport.new()
		vp.name = "ViewP%d" % (i + 1)
		vp.audio_listener_enable_3d = i == 0
		vp.world_3d = get_viewport().world_3d
		RenderQuality.apply_to_viewport(vp, GameState.quality, true)
		cont.add_child(vp)
		var cam := ChaseCamera.new()
		cam.kart = karts[i]
		vp.add_child(cam)
		cam.current = true
		var hud := PlayerHud.new()
		vp.add_child(hud)
		hud.build(karts[i], karts.size())
		hud.setup_minimap(tp, karts)
		cams.append(cam)
		huds.append(hud)
		viewports.append(vp)
	_results = Control.new()
	_results.set_anchors_preset(Control.PRESET_FULL_RECT)
	_results.visible = false
	layer.add_child(_results)


# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	if karts.is_empty():
		return
	var bob_t := Time.get_ticks_msec() * 0.001
	for box in item_boxes:
		var s := box.get_node("Spin") as Node3D
		s.rotate_y(delta * 1.6)
		s.position.y = sin(bob_t * 2.2 + float(box.get_instance_id() % 13)) * 0.14  # flutua (só visual)
	for i in huds.size():
		huds[i].update_hud(data[i]["lap"], laps, data[i]["place"])
	if state == State.COUNTDOWN or state == State.RACING:
		for i in 2:
			var p := PlayerInput.pause(i)
			if p and not _pause_prev[i] and pause_menu == null:
				open_pause()
			_pause_prev[i] = p
	for ci in 2:
		var ccam := _closeup_cam if ci == 0 else _closeup_cam2
		if ccam == null:
			continue
		var kx := karts[ci].model.get_global_transform_interpolated()
		var off := Vector3(-2.0, 1.7, -2.4) if _closeup_still else Vector3(2.3, 1.25, -2.6)
		match _cam_view:
			"front":
				off = Vector3(0.0, 0.9, -3.6)
			"side":
				off = Vector3(3.6, 0.7, 0.05)
			"top":
				off = Vector3(0.0, 4.6, 0.3)
		var eye := kx.origin + kx.basis * off
		var up := kx.basis.y if _cam_view != "top" else -kx.basis.z
		ccam.global_transform = Transform3D(Basis.looking_at(kx.origin + kx.basis.y * 0.4 - eye, up), eye)
	if state == State.CELEBRATION or state == State.RESULTS:
		_update_celebration(delta)
	_update_rim_lights()
	if state == State.CELEBRATION:
		for i in 2:
			var c := PlayerInput.confirm(i)
			if c and not _confirm_prev[i] and celebration_time > 1.2:
				_show_results()
			_confirm_prev[i] = c
	elif state == State.RESULTS:
		for i in 2:
			var c := PlayerInput.confirm(i)
			var b := PlayerInput.cancel(i)
			if c and not _confirm_prev[i]:
				AudioManager.sfx(&"confirm")
				SceneRouter.goto(RACE_SCENE)
				return
			if b and not _cancel_prev[i]:
				AudioManager.sfx(&"back")
				SceneRouter.goto(SELECT_SCENE)
				return
			_confirm_prev[i] = c
			_cancel_prev[i] = b
	var shot_ready := race_time >= _shot_time
	if _closeup and race_time < _shot_time + 30.0:
		var need := 2 if race_time < _shot_time + 15.0 else 1
		shot_ready = shot_ready and karts[0].drifting and karts[0].drift_level >= need
	if _closeup_still:
		shot_ready = state == State.COUNTDOWN and countdown < 1.2
	if _celebrate_force >= 0:
		shot_ready = state == State.CELEBRATION and celebration_time >= _shot_time
	if _shot_path != "" and shot_ready and _pause_shot:
		_pause_shot = false
		open_pause()
		get_tree().create_timer(0.5, true).timeout.connect(func() -> void:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			AudioManager.quit_clean(0))
	elif _shot_path != "" and shot_ready and pause_menu == null:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("[Race] captura salva: %s" % _shot_path)
		_shot_path = ""
		AudioManager.quit_clean(0)


func _physics_process(delta: float) -> void:
	if karts.is_empty():
		return
	match state:
		State.COUNTDOWN:
			countdown -= delta
			# Largada com boost: conta quanto tempo cada kart acelera sem soltar.
			for i in karts.size():
				_start_hold[i] = (_start_hold[i] + delta) if karts[i].in_throttle > 0.5 else 0.0
			var n := ceili(countdown)
			if n != _last_go and n > 0:
				_last_go = n
				for h in huds:
					h.show_message(str(n))
				AudioManager.sfx(&"count")
			if countdown <= 0.0:
				state = State.RACING
				for i in karts.size():
					karts[i].control_enabled = true
					if _start_hold[i] >= COUNTDOWN_TIME - Kart.START_GRACE:
						karts[i].start_boost()
				for h in huds:
					h.show_message("GO!", "", 0.8)
				AudioManager.sfx(&"go")
		State.RACING, State.CELEBRATION, State.RESULTS:
			if state == State.RACING:
				_resolve_kart_contacts()
			race_time += delta
			if _celebrate_force >= 0 and state == State.RACING and race_time > 0.6:
				_force_finish(_celebrate_force)
			for i in karts.size():
				_update_checkpoints(i)
			_update_places()
			_check_humans_done()


func _update_checkpoints(i: int) -> void:
	var d := data[i]
	var k := karts[i]
	if k.finished:
		return
	var nxt: int = d["next"]
	var dd := tp.delta_offset(cps[nxt], k.track_offset)
	if dd < 0.0 or dd > CP_WINDOW:
		return
	d["count"] += 1
	if nxt == 0:
		d["lap"] += 1
		if d["lap"] > laps:
			_finish(i)
			return
		if d["lap"] > 1 and i < huds.size():
			huds[i].show_message("VOLTA %d/%d" % [d["lap"], laps] if d["lap"] < laps else "ÚLTIMA VOLTA!", "", 1.5)
		if d["lap"] == laps and laps > 1 and not _last_lap_music and karts[i].ai == null:
			_last_lap_music = true
			AudioManager.sfx(&"lastlap")
			AudioManager.set_music_tempo(1.07)
	d["next"] = (nxt + 1) % cps.size()


func progress_of(i: int) -> float:
	var d := data[i]
	if karts[i].finished:
		return 1e9 - float(d["place"])
	var seg := tp.length / float(cps.size())
	var prev := (int(d["next"]) - 1 + cps.size()) % cps.size()
	return float(d["count"]) * seg + tp.delta_offset(cps[prev], karts[i].track_offset)


## Sem alocação por quadro: progresso em cache + ordenação de um array reutilizado.
func _update_places() -> void:
	for i in karts.size():
		_prog[i] = progress_of(i)
	_order.sort_custom(_cmp_progress)
	for p in _order.size():
		if not karts[_order[p]].finished:
			data[_order[p]]["place"] = p + 1


## Todos os humanos chegaram: os NPCs que faltam recebem colocação e tempo estimados
## (distância restante a ~21 m/s). Nos testes (end_when_humans_done = false) eles correm até o
## fim, com limite de 90 s após os humanos.
func _check_humans_done() -> void:
	if state != State.RACING or finish_count >= karts.size():
		return
	for i in human_count:
		if not karts[i].finished:
			return
	if _humans_done_time < 0.0:
		_humans_done_time = race_time
	if not end_when_humans_done and race_time - _humans_done_time < 90.0:
		return
	var total_len := tp.length * laps + tp.length / float(cps.size())
	for i in _order.duplicate():
		if karts[i].finished:
			continue
		data[i]["forced"] = true
		var remain := maxf(total_len - _prog[i], 0.0)
		_finish(i, race_time + remain / 21.0)


func _finish(i: int, time: float = -1.0) -> void:
	var d := data[i]
	var k := karts[i]
	if time < 0.0:
		time = race_time
	d["lap"] = laps
	finish_count += 1
	d["place"] = finish_count
	d["finish_time"] = time
	k.finished = true
	k.autopilot_use_items = false
	if i < huds.size():
		huds[i].show_message("%dº LUGAR" % finish_count, "Tempo %s" % format_time(time))
	print("[Race] %s terminou em %dº (%s)%s" % [racer_name(i), finish_count, format_time(time), " (estimado)" if d["forced"] else ""])
	if finish_count >= karts.size():
		_start_celebration()
	elif finish_count == 1 and state == State.RACING and _celebrate_force < 0 and end_when_humans_done:
		_finish_rest_estimated()


## Primeiro kart cruzou a linha: os demais recebem colocação/tempo estimados (~21 m/s) e a
## comemoração do vencedor abre na hora.
func _finish_rest_estimated() -> void:
	var total_len := tp.length * laps + tp.length / float(cps.size())
	for i in _order.duplicate():
		if karts[i].finished:
			continue
		data[i]["forced"] = true
		var remain := maxf(total_len - _prog[i], 0.0)
		_finish(i, race_time + remain / 21.0)


## Captura/teste: encerra a corrida já com o kart `first` em 1º e os demais na ordem atual.
func _force_finish(first: int) -> void:
	var order: Array[int] = [clampi(first, 0, karts.size() - 1)]
	for i in _order:
		if not order.has(i):
			order.append(i)
	for j in order.size():
		if not karts[order[j]].finished:
			data[order[j]]["forced"] = true
			_finish(order[j], race_time + float(j) * 1.3)


## Todos chegaram: os karts param, o 1º comemora (pose de vitória) e os demais lamentam (derrota).
## Sequência curta de câmera (CELEBRATION_TIME) antes do resultado; A pula depois de 1,2 s.
func _start_celebration() -> void:
	state = State.CELEBRATION
	celebration_played = true
	celebration_time = 0.0
	_confirm_prev = [true, true]
	winner = 0
	for i in karts.size():
		if int(data[i]["place"]) == 1:
			winner = i
	for i in karts.size():
		karts[i].halt()
		karts[i].model.set_pose(AlienDriver.Pose.VICTORY if i == winner else AlienDriver.Pose.DEFEAT)
	for i in viewports.size():
		huds[i].visible = false
		var cam := Camera3D.new()
		cam.fov = 40.0
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# Profundidade de campo sutil: o fundo desfoca atrás do personagem em foco.
		var attr := CameraAttributesPractical.new()
		attr.dof_blur_far_enabled = true
		attr.dof_blur_far_transition = 7.0
		attr.dof_blur_amount = 0.07
		cam.attributes = attr
		viewports[i].add_child(cam)
		cam.current = true
		_celeb_cams.append(cam)
		var l := UiKit.label("", 64, Palette.UI_ACCENT, 12)
		l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		l.offset_top = 18.0
		l.offset_bottom = 100.0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		viewports[i].add_child(l)
		_celeb_labels.append(l)
	AudioManager.sfx(&"lastlap")
	print("[Race] comemoração: %s venceu (%s)" % [racer_name(winner), Characters.NAMES[karts[winner].model.character]])
	_update_celebration(0.0)


func _update_celebration(delta: float) -> void:
	celebration_time += delta
	var t := celebration_time
	var shot2 := t >= CELEBRATION_SHOT2
	for i in _celeb_cams.size():
		var target := winner if shot2 else i
		var kx := karts[target].model.get_global_transform_interpolated()
		var a: float
		var off: Vector3
		var look_h := 1.12
		if not shot2:
			a = -0.7 + t * 0.15
			off = Vector3(sin(a) * 2.3, 1.45, -cos(a) * 2.3)
		elif i == 0:
			a = 0.45 - (t - CELEBRATION_SHOT2) * 0.2
			off = Vector3(sin(a) * 2.3, 0.85, -cos(a) * 2.3)
			look_h = 1.15
		else:
			a = -0.9 + (t - CELEBRATION_SHOT2) * 0.16
			off = Vector3(sin(a) * 4.2, 2.1, -cos(a) * 4.2)
			look_h = 0.8
		var eye := kx.origin + kx.basis * off
		(_celeb_cams[i].attributes as CameraAttributesPractical).dof_blur_far_distance = off.length() + 2.5
		_celeb_cams[i].global_transform = Transform3D(Basis.looking_at(kx.origin + kx.basis.y * look_h - eye, kx.basis.y), eye)
		var l := _celeb_labels[i]
		if shot2:
			l.text = "VENCEDOR: %s" % racer_name(winner)
			l.add_theme_color_override(&"font_color", Palette.UI_ACCENT)
		elif target == winner:
			l.text = "VITÓRIA!"
			l.add_theme_color_override(&"font_color", Palette.UI_ACCENT)
		else:
			l.text = "%dº LUGAR" % int(data[target]["place"])
			l.add_theme_color_override(&"font_color", Palette.UI_TEXT)
	if state == State.CELEBRATION and t >= CELEBRATION_TIME:
		_show_results()


## Colisão kart-contra-kart pela carroceria real (Kart.body_overlap): separa os dois (metade cada) e
## troca impulso na direção do contato (restituição + empurrão mínimo ao se aproximarem), com perda de
## controle momentânea proporcional à força da batida. Correção limitada: ninguém é lançado longe.
func _resolve_kart_contacts() -> void:
	for i in karts.size():
		var a := karts[i]
		for j in range(i + 1, karts.size()):
			var b := karts[j]
			var dpos := a.global_position - b.global_position
			if absf(dpos.y) > 1.2 or dpos.x * dpos.x + dpos.z * dpos.z > 13.0:
				continue
			if a._pending_teleport != null or b._pending_teleport != null:
				continue
			var o := Kart.body_overlap(a, b)
			if o == Vector2.ZERO:
				continue
			var depth := o.length()
			var n := Vector3(o.x, 0.0, o.y) / depth
			var corr := n * minf(depth, 0.4) * 0.5
			var vrel := (a.linear_velocity - b.linear_velocity).dot(n)
			var imp := 0.0
			var strength := clampf(-vrel / 12.0, 0.0, 1.0)
			if race_time < START_SOFT_TIME:
				imp = maxf(-vrel * 0.5, 0.0) * 0.2  # inelástica e diluída em alguns frames: empurra sem tranco
				strength = 0.0
			elif vrel < -0.3:
				imp = maxf(-vrel * (1.0 + Kart.BUMP_RESTITUTION) * 0.5, Kart.BUMP_MIN_PUSH)
			a.bump(n * imp, corr, strength)
			b.bump(-n * imp, -corr, strength)


## Luz de contorno (rim light) no personagem em destaque na introdução (contagem) e na comemoração:
## atrás dele em relação à câmera de cada tela, só nas malhas dos karts (KartModel.RIM_LAYER).
## Some suavemente perto do "GO" (na corrida não há luz extra: FPS do split-screen intacto).
func _update_rim_lights() -> void:
	var on := state != State.RACING
	for i in viewports.size():
		if _rim_lights.size() <= i:
			var l := OmniLight3D.new()
			l.omni_range = 2.6
			l.omni_attenuation = 1.2
			l.light_color = Color(0.88, 0.93, 1.0)
			l.light_cull_mask = KartModel.RIM_LAYER
			l.shadow_enabled = false
			add_child(l)
			_rim_lights.append(l)
		var rl := _rim_lights[i]
		var cam := viewports[i].get_camera_3d()
		rl.visible = on and cam != null
		if not rl.visible:
			continue
		var target := i
		if state != State.COUNTDOWN and celebration_time >= CELEBRATION_SHOT2:
			target = winner
		var kx := karts[target].model.get_global_transform_interpolated()
		var head := kx.origin + kx.basis.y * 1.15
		var away := head - cam.global_position
		away.y = 0.0
		rl.global_position = head + away.normalized() * 1.1 + Vector3.UP * 0.75
		rl.light_energy = 4.0 * (clampf(countdown / 0.6, 0.0, 1.0) if state == State.COUNTDOWN else 1.0)


## Pausa tudo (árvore pausada) e abre o menu de pausa; o menu despausa ao fechar.
func open_pause() -> void:
	AudioManager.sfx(&"confirm")
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.closed.connect(_on_pause_closed)
	get_tree().paused = true


func _on_pause_closed() -> void:
	pause_menu = null
	_pause_prev = [true, true]  # o botão que fechou ainda está pressionado


## Saindo da corrida: devolve os modelos ao pool; "correr de novo" mantém o mesmo grid de NPCs
## (mesmos modelos, reaproveitados sem montar de novo).
func _on_scene_leaving(path: String) -> void:
	GameState.keep_ai_lineup = path == RACE_SCENE
	for k in karts:
		if is_instance_valid(k) and is_instance_valid(k.model):
			k.model.release()


func racer_name(i: int) -> String:
	return ("JOGADOR %d" % (i + 1)) if karts[i].ai == null else karts[i].config.display_name.to_upper()


func _show_results() -> void:
	state = State.RESULTS
	_confirm_prev = [true, true]
	var panel := PanelContainer.new()
	var sb := UiKit.panel_style(Palette.UI_ACCENT, 18, 40)
	panel.add_theme_stylebox_override(&"panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	_results.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 16)
	panel.add_child(v)
	var lines: Array[String] = ["RESULTADO"]
	var idx: Array[int] = []
	for i in karts.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool: return data[a]["place"] < data[b]["place"])
	var colors: Array[Color] = [Palette.UI_TEXT]
	for i in idx:
		lines.append("%dº  %s   %s" % [data[i]["place"], racer_name(i), format_time(data[i]["finish_time"])])
		colors.append((Palette.UI_ACCENT if data[i]["place"] == 1 else Palette.UI_TEXT) if karts[i].ai == null else Palette.UI_MUTED)
	lines.append("A: correr de novo    B: voltar à seleção")
	colors.append(Palette.UI_MUTED)
	var row_px := 44 if karts.size() <= 4 else 34
	v.add_theme_constant_override(&"separation", 16 if karts.size() <= 4 else 8)
	for j in lines.size():
		var l := Label.new()
		l.text = lines[j]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override(&"font", PlayerHud.FONT)
		l.add_theme_font_size_override(&"font_size", 64 if j == 0 else (30 if j == lines.size() - 1 else row_px))
		l.add_theme_color_override(&"font_color", colors[j])
		v.add_child(l)
	panel.reset_size()
	panel.position = -panel.size * 0.5
	_results.visible = true
	race_finished.emit()


static func format_time(t: float) -> String:
	var m := floori(t / 60.0)
	var s := t - m * 60.0
	return "%d:%06.3f" % [m, s]


# ------------------------------------------------------------------ itens

func _on_box_picked(k: Kart, box: Area3D) -> void:
	RaceObjects.consume_box(box, 3.0)
	k.stats["pickups"] += 1
	if k.item != Kart.Item.NONE or k.finished:
		return
	var it := forced_item if k.ai == null else -1
	if it < 0:
		it = roll_item(data[k.player_index]["place"])
	k.give_item(it)


## Sorteio por posição: o líder recebe itens de defesa; o Pulso só sai da metade de trás do grid.
func roll_item(place: int) -> int:
	var pool: Array[int]
	if place == 1:
		pool = [Kart.Item.SHIELD, Kart.Item.BANANA, Kart.Item.BANANA, Kart.Item.TURBO, Kart.Item.ROCKET]
	elif place * 2 <= karts.size():
		pool = [Kart.Item.ROCKET, Kart.Item.ROCKET, Kart.Item.TURBO, Kart.Item.TURBO, Kart.Item.SHIELD, Kart.Item.BANANA]
	else:
		pool = [Kart.Item.ROCKET, Kart.Item.TURBO, Kart.Item.TURBO, Kart.Item.SHIELD, Kart.Item.BANANA, Kart.Item.PULSE, Kart.Item.PULSE]
	return pool.pick_random()


## Primeiro corredor à frente de `k` (ou null se `k` lidera).
func get_kart_ahead(k: Kart) -> Kart:
	var my := progress_of(k.player_index)
	var best: Kart = null
	var best_p := INF
	for o in karts:
		if o == k or o.finished:
			continue
		var p := progress_of(o.player_index)
		if p > my and p < best_p:
			best_p = p
			best = o
	return best


## Dispara um foguete em linha reta na direção atual do kart.
func spawn_rocket(k: Kart) -> Rocket:
	var fwd := k._flat_forward()
	var r := Rocket.new()
	r.setup(k, karts, k.global_position + fwd * 2.4 + k.ground_normal * 0.2, fwd)
	objects_root.add_child(r)
	RaceObjects.explode(objects_root, k.global_position + fwd * 1.5 + Vector3.UP * 0.5, false)
	AudioManager.sfx(&"rocket")
	return r


func spawn_banana(k: Kart) -> Area3D:
	var back := k.track_offset - 3.2
	var lat := tp.get_lateral(k.global_position, k.track_offset)
	var b := RaceObjects.make_banana(tp.to_world(back, lat, 0.0), tp.get_up(back), k)
	objects_root.add_child(b)
	add_hazard(b, back, lat)
	return b


## Registra um perigo para a IA desviar (a lista se limpa sozinha quando ele some).
func add_hazard(h: Area3D, off: float, lat: float) -> void:
	h.set_meta(&"off", tp.wrap_offset(off))
	h.set_meta(&"lat", lat)
	hazards.append(h)
	h.tree_exiting.connect(_remove_hazard.bind(h))


## Pulso UNIFEOB: onda de choque que eletriza todos os karts À FRENTE de `k` (escudo bloqueia).
## Retorna quantos foram atingidos.
func spawn_pulse(k: Kart) -> int:
	var my := progress_of(k.player_index)
	var n := 0
	for o in karts:
		if o == k or o.finished or progress_of(o.player_index) <= my:
			continue
		if o.hit("pulse"):
			n += 1
	RaceObjects.pulse_wave(objects_root, k.global_position, k.ground_normal)
	AudioManager.sfx(&"spark", -3.0, 0.5)
	return n


func _remove_hazard(h: Area3D) -> void:
	hazards.erase(h)


func _cmp_progress(a: int, b: int) -> bool:
	return _prog[a] > _prog[b]
