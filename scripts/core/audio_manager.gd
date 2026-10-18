extends Node
## Autoload "AudioManager": barramentos (Master/Music/SFX), pool de players 2D, músicas e efeitos
## sintetizados por código (Synth). A síntese roda numa thread (WorkerThreadPool) — a splash chama
## generate() cedo; quem pedir música antes de ficar pronta a ouve assim que terminar.
## Músicas: &"title" (splash/título/seleção) e &"race" (mais rápida; a última volta acelera via tempo).

signal audio_ready

const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const POOL_SIZE := 12
const MUSIC_DB := -5.0
const FADE := 0.8

var _pool: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []   ## 2 players para crossfade
var _cur := 0
var _music_name := &""
var _pending_music := &""
var _streams := {}      ## nome -> AudioStreamWAV (músicas)
var _sfx := {}          ## nome -> AudioStreamWAV
var _task := -1
var _result := {}
var _ready_flag := false
var _tempo := 1.0
var _quitting := false
var _quit_at_ms := -1
var _quit_code := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	_ensure_bus(BUS_MUSIC, -6.0)
	_ensure_bus(BUS_SFX, -2.0)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = BUS_MUSIC
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)


func _ensure_bus(bus_name: StringName, volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
	AudioServer.set_bus_volume_db(idx, volume_db)


# ------------------------------------------------------------------ síntese

## Inicia a síntese (músicas + efeitos) numa thread. Idempotente.
func generate() -> void:
	if _task >= 0 or _ready_flag:
		return
	_task = WorkerThreadPool.add_task(_render_all, true, "Synth")


func _render_all() -> void:
	var t0 := Time.get_ticks_msec()
	var r := {}
	r["sfx"] = Synth.render_sfx()
	r["title"] = Synth.render_song(Synth.title_song())
	r["race"] = Synth.render_song(Synth.race_song())
	r["ms"] = Time.get_ticks_msec() - t0
	_result = r


func is_audio_ready() -> bool:
	return _ready_flag


func _process(_delta: float) -> void:
	if _quit_at_ms > 0:
		if Time.get_ticks_msec() >= _quit_at_ms:
			_quit_at_ms = -1
			get_tree().quit(_quit_code)
		return
	if _task >= 0 and not _quitting and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_finish_generation()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_clean(0)


## Para todos os sons (inclusive motores dos karts), dá tempo ao mixer de liberar os playbacks
## e encerra o jogo — evita "ObjectDB instances leaked" no encerramento.
func quit_clean(code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	for n in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		(n as AudioStreamPlayer).stop()
		(n as AudioStreamPlayer).stream = null
	for n in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		(n as AudioStreamPlayer3D).stop()
	# Espera em tempo REAL (com --fixed-fps os quadros podem ser instantâneos) o mixer soltar os playbacks.
	_quit_code = code
	_quit_at_ms = Time.get_ticks_msec() + 300


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	# Para tudo ao sair (evita playbacks vazando no encerramento).
	for p in _pool + _music:
		p.stop()
		p.stream = null
	_sfx.clear()
	_streams.clear()


static func _wav(bytes: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = Synth.RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = bytes.size() >> 1
	return w


func _finish_generation() -> void:
	var fx: Dictionary = _result["sfx"]
	for k: String in fx:
		var e: Array = fx[k]
		_sfx[StringName(k)] = _wav(e[0], e[1])
	_streams[&"title"] = _wav(_result["title"], true)
	_streams[&"race"] = _wav(_result["race"], true)
	_ready_flag = true
	print("[Audio] músicas e efeitos sintetizados em %d ms (thread)" % int(_result.get("ms", 0)))
	_result = {}
	audio_ready.emit()
	if _pending_music != &"":
		var n := _pending_music
		_pending_music = &""
		play_music(n)


# ------------------------------------------------------------------ efeitos

func get_sfx(sfx_name: StringName) -> AudioStream:
	return null if _quitting else _sfx.get(sfx_name, null)


## Toca um efeito sintetizado pelo nome (silencioso se ainda não gerado).
func sfx(sfx_name: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	play_sfx(get_sfx(sfx_name), volume_db, pitch)


## Toca um som não posicional (UI, contagem regressiva...).
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null or _quitting:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


## Toca um som posicional temporário na cena atual.
func play_sfx_3d(stream: AudioStream, world_pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null or get_tree().current_scene == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = BUS_SFX
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 12.0
	p.max_distance = 180.0
	get_tree().current_scene.add_child(p)
	p.global_position = world_pos
	p.finished.connect(p.queue_free)
	p.play()


# ------------------------------------------------------------------ música

## Troca de música com crossfade. Aceita um nome (&"title"/&"race"); se a síntese ainda não
## terminou, começa assim que ficar pronta.
func play_music(music_name: StringName) -> void:
	if _quitting:
		return
	if not _ready_flag:
		_pending_music = music_name
		generate()
		return
	if music_name == _music_name and _music[_cur].playing:
		return
	var stream: AudioStream = _streams.get(music_name, null)
	if stream == null:
		return
	_music_name = music_name
	var old := _music[_cur]
	_cur = 1 - _cur
	var nw := _music[_cur]
	nw.stream = stream
	nw.pitch_scale = 1.0
	_tempo = 1.0
	nw.volume_db = -40.0
	nw.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(nw, "volume_db", MUSIC_DB, FADE)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, FADE)
		tw.chain().tween_callback(old.stop)


## Acelera/desacelera a música atual (última volta).
func set_music_tempo(t: float) -> void:
	if is_equal_approx(t, _tempo):
		return
	_tempo = t
	create_tween().tween_property(_music[_cur], "pitch_scale", t, 1.2)


func stop_music(fade: float = FADE) -> void:
	_music_name = &""
	_pending_music = &""
	for m in _music:
		if m.playing:
			var tw := create_tween()
			tw.tween_property(m, "volume_db", -60.0, fade)
			tw.tween_callback(m.stop)


func current_music() -> StringName:
	return _music_name if _ready_flag else _pending_music


func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
