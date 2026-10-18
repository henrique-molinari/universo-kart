extends SceneTree
## Mede o desempenho da corrida em split-screen (6 karts, piloto automático, vsync desligado).
## Uso (não-headless): Godot_console.exe --path <projeto> -s res://tools/capture/perf_probe.gd -- --autopilot
## Imprime "[perf] fps médio X | quadro médio Y ms | pior Z ms" após 6 s de amostra (começa em 8 s de corrida).

var _t := 0.0
var _frames := 0
var _sum := 0.0
var _worst := 0.0


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	change_scene_to_file.call_deferred("res://scenes/race.tscn")


func _process(delta: float) -> bool:
	var r = current_scene
	if r == null or not r.has_method("open_pause") or r.karts.is_empty():
		return false
	_t += delta
	if _t > 8.0:
		_frames += 1
		_sum += delta
		_worst = maxf(_worst, delta)
	if _t > 14.0:
		print("[perf] fps médio %.1f | quadro médio %.2f ms | pior %.2f ms" % [_frames / _sum, _sum / _frames * 1000.0, _worst * 1000.0])
		print("[perf] draw calls %d | objetos %d | primitivas %dk | memória de vídeo %d MB" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576])
		quit()
	return false
