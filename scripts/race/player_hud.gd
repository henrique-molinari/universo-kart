class_name PlayerHud
extends Control
## HUD mínimo de um jogador (dentro da sua SubViewport): item, volta, posição, velocímetro, mensagens.

const FONT := preload("res://assets/fonts/title_font.tres")

var kart: Kart
var lap_label: Label
var pos_label: Label
var speed_label: Label
var item_panel: PanelContainer
var item_icon: ItemIcon
var msg_label: Label
var sub_label: Label
var pad_label: Label


func build(k: Kart) -> void:
	kart = k
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := _label(18, Palette.WHITE)
	tag.text = "P%d" % (k.player_index + 1)
	tag.position = Vector2(24, 14)
	tag.add_theme_color_override(&"font_color", k.config.kart_color.lightened(0.35))
	lap_label = _label(34, Palette.WHITE)
	lap_label.position = Vector2(24, 36)
	pos_label = _label(72, Palette.YELLOW)
	pos_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pos_label.position = Vector2(-190, 6)
	pos_label.size = Vector2(170, 90)
	pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_label = _label(30, Palette.WHITE)
	speed_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_label.position = Vector2(-240, -56)
	speed_label.size = Vector2(220, 44)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	item_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.25, 0.75)
	sb.border_color = Palette.WHITE
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	item_panel.add_theme_stylebox_override(&"panel", sb)
	sb.set_corner_radius_all(24)
	sb.set_content_margin_all(8)
	item_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	item_panel.position = Vector2(-56, 10)
	item_panel.custom_minimum_size = Vector2(112, 112)
	add_child(item_panel)
	# Ícone do item (sem texto).
	item_icon = ItemIcon.new()
	item_icon.custom_minimum_size = Vector2(96, 96)
	item_panel.add_child(item_icon)

	msg_label = _label(84, Palette.YELLOW)
	msg_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_constant_override(&"outline_size", 18)
	sub_label = _label(34, Palette.WHITE)
	sub_label.set_anchors_preset(Control.PRESET_CENTER)
	sub_label.position = Vector2(-300, 60)
	sub_label.size = Vector2(600, 50)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pad_label = _label(18, Color(1, 1, 1, 0.8))
	pad_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	pad_label.position = Vector2(24, -40)


func _label(size_px: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", FONT)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", c)
	l.add_theme_color_override(&"font_outline_color", Color(0.02, 0.03, 0.2))
	l.add_theme_constant_override(&"outline_size", maxi(int(size_px / 6.0), 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func update_hud(lap: int, laps: int, place: int) -> void:
	lap_label.text = "VOLTA %d/%d" % [clampi(lap, 1, laps), laps]
	pos_label.text = "%dº" % place
	speed_label.text = "%d km/h" % roundi(absf(kart.speed) * 3.6)
	item_icon.item = kart.item
	var dev := PlayerInput.device_of(kart.player_index)
	pad_label.text = ("Controle %d" % dev) if dev >= 0 else ("Teclado (WASD)" if kart.player_index == 0 else "Teclado (setas)")


func show_message(text: String, sub: String = "", duration: float = -1.0) -> void:
	msg_label.text = text
	sub_label.text = sub
	if duration > 0.0:
		var t := text
		get_tree().create_timer(duration).timeout.connect(func() -> void:
			if msg_label.text == t:
				msg_label.text = ""
				sub_label.text = "")
