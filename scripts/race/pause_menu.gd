class_name PauseMenu
extends CanvasLayer
## Menu de pausa da corrida. Aberto pela Race (Esc/P ou Start do controle de qualquer jogador):
## pausa a árvore inteira (física, karts, IA, sons dos karts) e roda em PROCESS_MODE_ALWAYS.
## Opções: CONTINUAR, MÚSICA e EFEITOS SONOROS (volumes independentes, ◀ ▶ em passos de 10%,
## salvos entre sessões), REINICIAR CORRIDA, VOLTAR AO INÍCIO.
## Qualquer jogador navega (▲ ▼), A ou Enter confirma, Start/Esc/B fecham.

signal closed

enum Item { RESUME, MUSIC, SFX, RESTART, TITLE }

const TITLE_SCENE := "res://scenes/title.tscn"
const LABELS := ["CONTINUAR", "MÚSICA", "EFEITOS SONOROS", "REINICIAR CORRIDA", "VOLTAR AO INÍCIO"]
const STEP := 0.1

const ROW_SIZE := Vector2(820, 54)   ## toda linha tem tamanho fixo: o painel nunca muda de largura

var selected := 0
var _rows: Array[Label] = []         ## rótulo principal de cada linha (cor = seleção)
var _marks: Array = []               ## [‹, ›] de cada linha (só a visibilidade muda)
var _bars := {}                      ## Item -> VolumeBar
var _values := {}                    ## Item -> rótulo do valor (largura fixa)


## Barra de volume de largura fixa: só o preenchimento interno muda com o valor.
class VolumeBar extends Control:
	var value := 1.0:
		set(v):
			value = clampf(v, 0.0, 1.0)
			queue_redraw()
	var active := false:
		set(v):
			active = v
			queue_redraw()

	func _draw() -> void:
		var h := size.y
		var track := StyleBoxFlat.new()
		track.bg_color = Color(1, 1, 1, 0.12)
		track.set_corner_radius_all(int(h * 0.5))
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var c := Palette.UI_ACCENT if active else Palette.UI_TEXT.darkened(0.2)
		if value > 0.0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = c
			fill.set_corner_radius_all(int(h * 0.5))
			draw_style_box(fill, Rect2(Vector2.ZERO, Vector2(maxf(size.x * value, h), h)))
		for k in range(1, 10):
			var x := size.x * k / 10.0
			draw_line(Vector2(x, h * 0.3), Vector2(x, h * 0.7), Color(0, 0, 0, 0.25), 2.0)
		draw_circle(Vector2(clampf(size.x * value, h * 0.5, size.x - h * 0.5), h * 0.5), h * 0.62, Palette.UI_TEXT if active else Palette.UI_MUTED)
var _prev := {}          ## borda das entradas por jogador: "pause0", "ok1", "ny0"...
var _leaving := false
var panel: PanelContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	var sb := UiKit.panel_style(Palette.UI_ACCENT, 18, 44)
	panel.add_theme_stylebox_override(&"panel", sb)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 18)
	panel.add_child(v)
	v.add_child(UiKit.label("PAUSA", 68, Palette.UI_TEXT))
	for i in LABELS.size():
		v.add_child(_build_row(i))
	v.add_child(UiKit.label("▲ ▼ escolher    ◀ ▶ ajustar    A / ENTER confirmar    START / ESC continuar", 22, Palette.UI_MUTED))
	# Quem abriu ainda está segurando o botão: só aceita entradas depois de soltar.
	for i in 2:
		_prev["pause%d" % i] = true
		_prev["ok%d" % i] = true
		_prev["back%d" % i] = true
		_prev["ny%d" % i] = PlayerInput.nav_y(i)  # direção já segurada ao abrir não conta
		_prev["nx%d" % i] = PlayerInput.nav_x(i)
	_prev["enter"] = true
	_refresh()


func _fixed(c: Control, w: float) -> Control:
	c.custom_minimum_size = Vector2(w, ROW_SIZE.y)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if c is Label:
		(c as Label).clip_text = true
	return c


## Linha de tamanho fixo: ‹ conteúdo ›. Volume: nome | barra | valor (cada parte com largura fixa).
func _build_row(i: int) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = ROW_SIZE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 0)
	var left := _fixed(UiKit.label("›", 40, Palette.UI_ACCENT), 40)
	var right := _fixed(UiKit.label("‹", 40, Palette.UI_ACCENT), 40)
	row.add_child(left)
	if i == Item.MUSIC or i == Item.SFX:
		var name_l := _fixed(UiKit.label(LABELS[i], 36), 330) as Label
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name_l)
		_rows.append(name_l)
		row.add_child(_fixed(Control.new(), 30))
		var holder := _fixed(CenterContainer.new(), 260)
		var bar := VolumeBar.new()
		bar.custom_minimum_size = Vector2(260, 20)
		holder.add_child(bar)
		row.add_child(holder)
		_bars[i] = bar
		var val := _fixed(UiKit.label("", 34), 120) as Label
		row.add_child(val)
		_values[i] = val
	else:
		var l := _fixed(UiKit.label(LABELS[i], 40), ROW_SIZE.x - 80.0) as Label
		row.add_child(l)
		_rows.append(l)
	row.add_child(right)
	_marks.append([left, right])
	return row


func _process(_delta: float) -> void:
	if _leaving:
		return
	# Enter do teclado (principal ou numérico) também confirma; borda lida todo quadro.
	var confirm := _edge("enter", Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER))
	for i in 2:
		if _edge("pause%d" % i, PlayerInput.pause(i)) or _edge("back%d" % i, PlayerInput.cancel(i)):
			close()
			return
		var ny := PlayerInput.nav_y(i)
		if ny != 0 and ny != _prev["ny%d" % i]:
			selected = wrapi(selected + ny, 0, LABELS.size())
			AudioManager.sfx(&"move")
			_refresh()
		_prev["ny%d" % i] = ny
		var nx := PlayerInput.nav_x(i)
		if nx != 0 and nx != _prev["nx%d" % i]:
			if selected == Item.MUSIC:
				change_music(nx)
			elif selected == Item.SFX:
				change_sfx(nx)
		_prev["nx%d" % i] = nx
		if _edge("ok%d" % i, PlayerInput.accept(i)):
			confirm = true
	if confirm:
		activate()


func _edge(key: String, now: bool) -> bool:
	var was: bool = _prev[key]
	_prev[key] = now
	return now and not was


func change_music(dir: int) -> void:
	AudioManager.set_music_volume(snappedf(AudioManager.music_volume + STEP * dir, STEP))
	AudioManager.sfx(&"move")
	_refresh()


func change_sfx(dir: int) -> void:
	AudioManager.set_sfx_volume(snappedf(AudioManager.sfx_volume + STEP * dir, STEP))
	AudioManager.sfx(&"move")
	_refresh()


func activate() -> void:
	match selected:
		Item.RESUME:
			close()
		Item.MUSIC:
			# A no volume: alterna mudo / volume cheio.
			AudioManager.set_music_volume(1.0 if AudioManager.music_volume <= 0.001 else 0.0)
			AudioManager.sfx(&"confirm")
			_refresh()
		Item.SFX:
			AudioManager.set_sfx_volume(1.0 if AudioManager.sfx_volume <= 0.001 else 0.0)
			AudioManager.sfx(&"confirm")
			_refresh()
		Item.RESTART:
			_leave(Race.RACE_SCENE)
		Item.TITLE:
			_leave(TITLE_SCENE)


func close() -> void:
	AudioManager.sfx(&"back")
	get_tree().paused = false
	closed.emit()
	queue_free()


## Sai da corrida: a árvore continua pausada durante o fade; o SceneRouter despausa ao trocar a cena.
func _leave(path: String) -> void:
	_leaving = true
	AudioManager.sfx(&"confirm")
	SceneRouter.goto(path)


func _refresh() -> void:
	for i in _rows.size():
		var on := i == selected
		for m: Label in _marks[i]:
			m.modulate.a = 1.0 if on else 0.0
		_rows[i].add_theme_color_override(&"font_color", Palette.UI_ACCENT if on else Palette.UI_TEXT.darkened(0.12))
		if _bars.has(i):
			var vol := AudioManager.music_volume if i == Item.MUSIC else AudioManager.sfx_volume
			var pct := roundi(vol * 100.0)
			_bars[i].value = vol
			_bars[i].active = on
			_values[i].text = "MUDO" if pct == 0 else "%d%%" % pct
			_values[i].add_theme_color_override(&"font_color", Palette.UI_ACCENT if on else Palette.UI_MUTED)
