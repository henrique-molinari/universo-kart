extends SceneTree
## QA do F11 (não-headless): abre a corrida e, para várias resoluções de janela, aperta F11 (tela cheia),
## confere que a janela cobre a tela e que as duas telas do split-screen mantêm a proporção, aperta F11
## de novo e confere a volta ao tamanho original.
## Uso: Godot_console.exe --path <projeto> -s res://tools/capture/fullscreen_probe.gd [-- --out=<pasta>]

var _out := ""
var _fails := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	change_scene_to_file.call_deferred("res://scenes/race.tscn")
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await process_frame


func _f11() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_F11
	e.physical_keycode = KEY_F11
	e.pressed = true
	Input.parse_input_event(e)
	await _wait(2)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await _wait(25)


func _check(ok: bool, msg: String) -> void:
	print("[tela] %s %s" % ["OK  " if ok else "FALHA", msg])
	if not ok:
		_fails += 1


## Proporções das telas do split-screen (cada metade = largura x metade da altura da janela).
func _split_ok() -> String:
	var race = current_scene
	var ws := Vector2(root.get_visible_rect().size)
	var res := ""
	for vp: SubViewport in race.viewports:
		var want := ws.x / (ws.y * 0.5)
		var got := float(vp.size.x) / float(vp.size.y)
		res += "%dx%d(%.2f/%.2f) " % [vp.size.x, vp.size.y, got, want]
		if absf(got - want) > 0.03:
			res = "ERRO " + res
	return res


func _run() -> void:
	while current_scene == null or not current_scene.has_method("open_pause") or current_scene.karts.is_empty():
		await process_frame
	await _wait(30)
	var screen := DisplayServer.screen_get_size()
	for sz: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 768)]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(sz)
		await _wait(20)
		var before := DisplayServer.window_get_size()
		var s0 := _split_ok()
		await _f11()
		var full := DisplayServer.window_get_size()
		var mode := DisplayServer.window_get_mode()
		var s1 := _split_ok()
		_check(mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN and full == screen and not s1.begins_with("ERRO"),
			"janela %s -> F11 tela cheia %s (tela %s), split %s" % [str(before), str(full), str(screen), s1])
		if _out != "" and sz.x == 1024:
			root.get_texture().get_image().save_png(_out.path_join("fullscreen.png"))
		await _f11()
		var back := DisplayServer.window_get_size()
		var s2 := _split_ok()
		_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and back == before and not s0.begins_with("ERRO") and not s2.begins_with("ERRO"),
			"F11 de novo -> janela %s (antes %s), split %s" % [str(back), str(before), s2])
		if _out != "" and sz.x == 1024:
			root.get_texture().get_image().save_png(_out.path_join("windowed_4x3.png"))
	print("[tela] %d falhas" % _fails)
	quit(1 if _fails > 0 else 0)
