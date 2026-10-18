extends Node
## Teste headless do fluxo de telas com entrada simulada:
## splash -> título (Enter) -> seleção (P1/P2 escolhem ET e cor, B cancela PRONTO, A confirma) -> corrida
## (ET e cor chegam aos karts; traje do ET = cor do kart; NPCs com os dois ETs) -> comemoração ->
## resultado (A: correr de novo, B: seleção) -> B na seleção volta ao título.
## Uso: Godot_console.exe --headless --fixed-fps 60 --path <projeto> res://tools/validate/validate_flow.tscn

var _checks := 0
var _done := false
var _fails := 0


func _ready() -> void:
	get_tree().create_timer(300.0, true, true, true).timeout.connect(func() -> void:
		if _done:
			return
		printerr("[flow] TIMEOUT")
		get_tree().quit(3))
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if ok:
		print("[flow] OK   ", msg)
	else:
		_fails += 1
		printerr("[flow] FALHA ", msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_scene(cls: String, timeout_frames: int = 3000) -> bool:
	for i in timeout_frames:
		var cs := get_tree().current_scene
		if cs != null and cs.get_script() != null and (cs.get_script() as Script).get_global_name() == cls:
			return true
		await get_tree().process_frame
	return false


func _tap_action(action: StringName) -> void:
	Input.action_press(action)
	await _frames(3)
	Input.action_release(action)
	await _frames(3)


func _tap_key(key: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(3)


static func _mesh_color(mi: MeshInstance3D) -> Color:
	var arr := mi.mesh.surface_get_arrays(0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	return cols[0]


func _run() -> void:
	# Este nó sobrevive às trocas de cena: a "cena atual" passa a ser um nó descartável.
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	var f0 := Engine.get_process_frames()
	get_tree().change_scene_to_file("res://scenes/splash.tscn")
	await _frames(2)
	_check(await _wait_scene("SplashScreen", 60), "splash abre")
	var ok_title := await _wait_scene("TitleScreen")
	var splash_s := float(Engine.get_process_frames() - f0) / 60.0
	_check(ok_title, "splash -> título (%.1f s simulados)" % splash_s)
	_check(splash_s >= 2.5, "splash dura no mínimo 2,5 s")
	_check(GameState.has_track() and GameState.track_node.build_scenery, "pista pré-carregada na splash e mantida no GameState")
	await _frames(60)

	await _tap_key(KEY_ENTER)
	await _frames(8)
	_check(await _wait_scene("SelectScreen"), "Enter no título -> seleção")
	var sel := get_tree().current_scene as SelectScreen
	await _frames(40)
	var s0: Array[int] = sel.sel.duplicate()
	var c0: Array[int] = sel.char_sel.duplicate()
	_check(c0 == [0, 1] and sel._models[0].character == 0 and sel._models[1].character == 1, "seleção abre com os 2 ETs (P1 Visitante, P2 Turista) na prévia")
	# P1: troca o personagem (linha 0), desce para a cor e avança 2. P2: desce e volta 1 cor (mantém o ET).
	await _tap_action(&"p1_right")
	await _tap_action(&"p1_down")
	await _tap_action(&"p1_right")
	await _tap_action(&"p1_right")
	await _tap_action(&"p2_down")
	await _tap_action(&"p2_left")
	var n := Palette.SELECT_COLORS.size()
	var want: Array[int] = [(s0[0] + 2) % n, (s0[1] - 1 + n) % n]
	var want_c: Array[int] = [1 - c0[0], c0[1]]
	_check(sel.sel == want, "cada jogador troca a própria cor (P1 %d->%d, P2 %d->%d)" % [s0[0], sel.sel[0], s0[1], sel.sel[1]])
	_check(sel.char_sel == want_c, "cada jogador escolhe o próprio ET (P1 %s, P2 %s)" % [AlienDriver.NAMES[sel.char_sel[0]], AlienDriver.NAMES[sel.char_sel[1]]])
	var pm: KartModel = sel._models[0]
	_check(pm != null and pm.paint_color == Palette.SELECT_COLORS[want[0]] and pm.suit_color == pm.paint_color and pm.character == want_c[0],
		"prévia 3D do P1 mostra o ET e a cor escolhidos")
	await _tap_action(&"p1_confirm")
	_check(sel.ready_flags[0] and not sel.ready_flags[1], "P1 PRONTO (P2 ainda não)")
	await _tap_action(&"p1_cancel")
	_check(not sel.ready_flags[0], "B cancela o PRONTO do P1")
	await _tap_action(&"p1_confirm")
	await _tap_action(&"p2_confirm")
	_check(sel.ready_flags[0] and sel.ready_flags[1], "os dois PRONTOS")

	_check(await _wait_scene("Race"), "seleção -> corrida")
	var race := get_tree().current_scene as Race
	for i in 600:
		if race.karts.size() >= 2:
			break
		await _frames(1)
	for i in 2:
		var c := Palette.SELECT_COLORS[want[i]]
		var k := race.karts[i]
		var m := k.model
		var suit := _mesh_color(m.driver.body)
		_check(k.config.kart_color == c and m.paint_color == c, "P%d: kart na cor escolhida (%s)" % [i + 1, Palette.SELECT_COLOR_NAMES[want[i]]])
		var tol := 0.01
		var same := absf(suit.r - c.r) < tol and absf(suit.g - c.g) < tol and absf(suit.b - c.b) < tol
		_check(same and k.config.suit_color == c, "P%d: traje do ET = cor do kart" % (i + 1))
		_check(k.config.character == want_c[i] and m.character == want_c[i] and m.driver.character == want_c[i],
			"P%d: ET escolhido no kart (%s)" % [i + 1, AlienDriver.NAMES[want_c[i]]])
	var npc_chars: Array[int] = []
	for i in range(2, race.karts.size()):
		npc_chars.append(race.karts[i].model.character)
	_check(npc_chars.has(0) and npc_chars.has(1) and absi(npc_chars.count(0) - npc_chars.count(1)) <= 1,
		"NPCs distribuídos entre os 2 ETs %s" % str(npc_chars))
	await _frames(30)
	_check(AudioManager.current_music() == &"race", "música da corrida tocando/pedida")

	# Fim de corrida: a comemoração (vitória/derrota) toca ANTES do resultado.
	for i in 400:
		if race.state == Race.State.RACING:
			break
		await _frames(1)
	race._force_finish(1)
	await _frames(2)
	_check(race.state == Race.State.CELEBRATION and race.winner == 1 and race.karts[1].model.driver.pose == AlienDriver.Pose.VICTORY
		and race.karts[0].model.driver.pose == AlienDriver.Pose.DEFEAT and not race._results.visible,
		"fim de corrida -> comemoração (P2 vitória, P1 derrota) antes do resultado")
	await _frames(100)
	await _tap_action(&"p1_confirm")
	await _frames(4)
	_check(race.state == Race.State.RESULTS and race._results.visible, "A pula a comemoração -> resultado")
	# Resultado: A corre de novo, B volta à seleção.
	await _frames(10)
	await _frames(10)
	await _tap_action(&"p1_confirm")
	await _frames(10)
	for i in 400:
		if get_tree().current_scene != race and get_tree().current_scene is Race:
			break
		await _frames(1)
	var race2 := get_tree().current_scene
	_check(race2 is Race and race2 != race, "resultado: A -> corre de novo")
	var r2 := race2 as Race
	for i in 600:
		if r2.karts.size() >= 2:
			break
		await _frames(1)
	r2._show_results()
	await _frames(10)
	await _tap_action(&"p2_cancel")
	_check(await _wait_scene("SelectScreen"), "resultado: B -> seleção")
	await _frames(40)
	await _tap_action(&"p1_cancel")
	_check(await _wait_scene("TitleScreen"), "B na seleção -> título")

	var t0 := Time.get_ticks_msec()
	while not AudioManager.is_audio_ready() and Time.get_ticks_msec() - t0 < 30000:
		await _frames(1)
	_check(AudioManager.is_audio_ready() and AudioManager.get_sfx(&"engine") != null, "música e efeitos sintetizados")
	print("[flow] %d verificações, %d falhas" % [_checks, _fails])
	_done = true
	AudioManager.quit_clean(0 if _fails == 0 else 1)
