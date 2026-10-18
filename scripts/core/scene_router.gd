extends CanvasLayer
## Autoload "SceneRouter": troca de cenas com fade.

signal scene_changed(path: String)

var _fade: ColorRect
var _busy := false
var _queued := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_fade = ColorRect.new()
	_fade.color = Color(Palette.GRAPHITE, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


## Troca de cena com fade. Se já houver uma troca em andamento, a nova fica na fila (a última vence).
func goto(path: String, fade_time: float = 0.35) -> void:
	if _busy:
		_queued = path
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, fade_time)
	tw.tween_callback(_swap.bind(path, fade_time))


func _swap(path: String, fade_time: float) -> void:
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
