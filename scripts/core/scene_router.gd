extends CanvasLayer
## Autoload "SceneRouter": troca de cenas com fade e F11 (tela cheia <-> janela) em qualquer tela.

signal scene_changed(path: String)
## Emitido logo antes de trocar de cena (a cena atual ainda existe): devolva recursos reaproveitáveis.
signal scene_leaving(path: String)

var _fade: ColorRect
var _busy := false
var _queued := ""
var _win_rect := Rect2i()      ## janela antes da tela cheia (restaurada ao voltar)
var _win_maximized := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_fade = ColorRect.new()
	_fade.color = Color(Palette.GRAPHITE, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


## Troca de cena com fade. Se já houver uma troca em andamento, a nova fica na fila (a última vence).
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_F11 or k.physical_keycode == KEY_F11):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	var m := DisplayServer.window_get_mode()
	return m == DisplayServer.WINDOW_MODE_FULLSCREEN or m == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Tela cheia exclusiva (cobre a tela inteira, sem bordas do sistema) <-> janela com o mesmo tamanho,
## posição e estado (maximizada) de antes. O stretch "canvas_items" + "expand" do projeto mantém a
## proporção da interface e do split-screen em qualquer resolução (sem distorcer).
func toggle_fullscreen() -> void:
	if is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if _win_maximized else DisplayServer.WINDOW_MODE_WINDOWED)
		if not _win_maximized and _win_rect.size.x > 0:
			DisplayServer.window_set_size(_win_rect.size)
			DisplayServer.window_set_position(_win_rect.position)
	else:
		_win_maximized = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED
		_win_rect = Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	print("[Tela] %s %s" % ["tela cheia" if is_fullscreen() else "janela", str(DisplayServer.window_get_size())])


func goto(path: String, fade_time: float = 0.35) -> void:
	if _busy:
		_queued = path
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, fade_time)
	tw.tween_callback(_swap.bind(path, fade_time))


func _swap(path: String, fade_time: float) -> void:
	get_tree().paused = false  # saindo do menu de pausa: a nova cena nunca começa pausada
	scene_leaving.emit(path)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter: falha ao carregar %s (%s)" % [path, error_string(err)])
	var tw := create_tween()
	tw.tween_interval(0.06)
	tw.tween_property(_fade, "color:a", 0.0, fade_time)
	tw.tween_callback(_done.bind(path, fade_time))


func _done(path: String, fade_time: float) -> void:
	_busy = false
	scene_changed.emit(path)
	if _queued != "":
		var q := _queued
		_queued = ""
		goto(q, fade_time)
