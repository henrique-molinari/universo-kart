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
##   --closeup              câmera de perto no P1 (com drift automático); a captura espera um drift nível 2+
##
## A pista vem de GameState.ensure_track() (construída uma vez na splash e reaproveitada).

signal race_finished

enum State { COUNTDOWN, RACING, RESULTS }

const COUNTDOWN_TIME := 3.0
const CP_WINDOW := 35.0
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
var forced_item: int = -1         ## testes: força o item das caixas
var _results: Control
var _confirm_prev := [true, true]
var _cancel_prev := [true, true]
var _closeup := false
var _demo_items := PackedStringArray()  ## captura do HUD: itens fixos (índices de Kart.Item) sem usar
var _closeup_both := false  ## --closeup-still também no P2 (captura dos dois karts)
var _closeup_cam2: Camera3D
var _cam_view := ""  ## --closeup: front | side | top | (padrão 3/4)
var _closeup_still := false  ## captura do kart parado (3/4 de frente) durante a contagem
var _closeup_cam: Camera3D
var _last_lap_music := false
var _shot_path := ""
var _shot_time := 6.0
var _last_go := -1


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
		elif a == "--closeup-still":
			_closeup = true
			_closeup_still = true
	GameState.num_local_players = 2
	laps = GameState.laps
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

	for i in 2:
		var k := Kart.new()
		k.setup(GameState.get_player(i), i, tp, self)
		add_child(k)
		k.place(tp.get_grid_transform(i))
		k.autopilot = autopilot
		k.autopilot_lateral = -1.75 if i == 0 else 1.75
		karts.append(k)
		data.append({"next": 0, "lap": 0, "count": 0, "finish_time": 0.0, "place": i + 1})

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
		hud.build(karts[i])
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
	for box in item_boxes:
		var s := box.get_node("Spin") as Node3D
		s.rotate_y(delta * 1.6)
	for i in karts.size():
		huds[i].update_hud(data[i]["lap"], laps, data[i]["place"])
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
	if state == State.RESULTS:
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
	if _shot_path != "" and shot_ready:
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
			var n := ceili(countdown)
			if n != _last_go and n > 0:
				_last_go = n
				for h in huds:
					h.show_message(str(n))
				AudioManager.sfx(&"count")
			if countdown <= 0.0:
				state = State.RACING
				for k in karts:
					k.control_enabled = true
				for h in huds:
					h.show_message("GO!", "", 0.8)
				AudioManager.sfx(&"go")
		State.RACING, State.RESULTS:
			race_time += delta
			for i in karts.size():
				_update_checkpoints(i)
			_update_places()


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
		if d["lap"] > 1:
			huds[i].show_message("VOLTA %d/%d" % [d["lap"], laps] if d["lap"] < laps else "ÚLTIMA VOLTA!", "", 1.5)
		if d["lap"] == laps and laps > 1 and not _last_lap_music:
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


func _update_places() -> void:
	var order: Array[int] = [0, 1]
	order.sort_custom(func(a: int, b: int) -> bool: return progress_of(a) > progress_of(b))
	for p in order.size():
		if not karts[order[p]].finished:
			data[order[p]]["place"] = p + 1


func _finish(i: int) -> void:
	var d := data[i]
	var k := karts[i]
	d["lap"] = laps
	finish_count += 1
	d["place"] = finish_count
	d["finish_time"] = race_time
	k.finished = true
	k.autopilot_use_items = false
	huds[i].show_message("%dº LUGAR" % finish_count, "Tempo %s" % format_time(race_time))
	print("[Race] P%d terminou em %dº (%s)" % [i + 1, finish_count, format_time(race_time)])
	if finish_count >= karts.size():
		_show_results()


func _show_results() -> void:
	state = State.RESULTS
	_confirm_prev = [true, true]
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.3, 0.9)
	sb.border_color = Palette.YELLOW
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(40)
	panel.add_theme_stylebox_override(&"panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	_results.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 16)
	panel.add_child(v)
	var lines: Array[String] = ["RESULTADO"]
	var idx: Array[int] = [0, 1]
	idx.sort_custom(func(a: int, b: int) -> bool: return data[a]["place"] < data[b]["place"])
	for i in idx:
		lines.append("%dº  JOGADOR %d   %s" % [data[i]["place"], i + 1, format_time(data[i]["finish_time"])])
	lines.append("A: correr de novo    B: voltar à seleção")
	for j in lines.size():
		var l := Label.new()
		l.text = lines[j]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override(&"font", PlayerHud.FONT)
		l.add_theme_font_size_override(&"font_size", 64 if j == 0 else (30 if j == lines.size() - 1 else 44))
		l.add_theme_color_override(&"font_color", Palette.YELLOW if j == 0 else Palette.WHITE)
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
	var it := forced_item
	if it < 0:
		var pool: Array[int]
		if data[k.player_index]["place"] == 1:
			pool = [Kart.Item.SHIELD, Kart.Item.BANANA, Kart.Item.BANANA, Kart.Item.TURBO, Kart.Item.ROCKET]
		else:
			pool = [Kart.Item.ROCKET, Kart.Item.ROCKET, Kart.Item.TURBO, Kart.Item.TURBO, Kart.Item.SHIELD, Kart.Item.BANANA]
		it = pool.pick_random()
	k.give_item(it)


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
	return b
