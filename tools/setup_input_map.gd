extends SceneTree
## Gera o Input Map completo (2 jogadores, teclado + gamepads 0/1) e grava em project.godot.
## Uso: Godot_console.exe --headless --path <projeto> -s res://tools/setup_input_map.gd

const DEADZONE := 0.25


func _init() -> void:
	var actions: Dictionary = {}

	# ---------------- Jogador 1: teclado WASD + gamepad 0 ----------------
	actions["p1_accelerate"] = [_key(KEY_W), _joy_btn(0, JOY_BUTTON_A), _joy_axis(0, JOY_AXIS_TRIGGER_RIGHT, 1.0)]
	actions["p1_brake"] = [_key(KEY_S), _joy_btn(0, JOY_BUTTON_B), _joy_axis(0, JOY_AXIS_TRIGGER_LEFT, 1.0)]
	actions["p1_steer_left"] = [_key(KEY_A), _joy_axis(0, JOY_AXIS_LEFT_X, -1.0), _joy_btn(0, JOY_BUTTON_DPAD_LEFT)]
	actions["p1_steer_right"] = [_key(KEY_D), _joy_axis(0, JOY_AXIS_LEFT_X, 1.0), _joy_btn(0, JOY_BUTTON_DPAD_RIGHT)]
	actions["p1_drift"] = [_key(KEY_SPACE), _key(KEY_SHIFT, KEY_LOCATION_LEFT), _joy_btn(0, JOY_BUTTON_RIGHT_SHOULDER)]
	actions["p1_use_item"] = [_key(KEY_E), _key(KEY_Q), _joy_btn(0, JOY_BUTTON_LEFT_SHOULDER), _joy_btn(0, JOY_BUTTON_X)]
	actions["p1_look_back"] = [_key(KEY_C), _joy_btn(0, JOY_BUTTON_Y)]
	actions["p1_up"] = [_key(KEY_W), _joy_axis(0, JOY_AXIS_LEFT_Y, -1.0), _joy_btn(0, JOY_BUTTON_DPAD_UP)]
	actions["p1_down"] = [_key(KEY_S), _joy_axis(0, JOY_AXIS_LEFT_Y, 1.0), _joy_btn(0, JOY_BUTTON_DPAD_DOWN)]
	actions["p1_left"] = [_key(KEY_A), _joy_axis(0, JOY_AXIS_LEFT_X, -1.0), _joy_btn(0, JOY_BUTTON_DPAD_LEFT)]
	actions["p1_right"] = [_key(KEY_D), _joy_axis(0, JOY_AXIS_LEFT_X, 1.0), _joy_btn(0, JOY_BUTTON_DPAD_RIGHT)]
	actions["p1_confirm"] = [_key(KEY_SPACE), _key(KEY_E), _joy_btn(0, JOY_BUTTON_A)]
	actions["p1_cancel"] = [_key(KEY_Q), _joy_btn(0, JOY_BUTTON_B)]
	actions["p1_pause"] = [_key(KEY_ESCAPE), _joy_btn(0, JOY_BUTTON_START)]

	# ---------------- Jogador 2: setas + Ctrl/Enter numérico + gamepad 1 ----------------
	actions["p2_accelerate"] = [_key(KEY_UP), _joy_btn(1, JOY_BUTTON_A), _joy_axis(1, JOY_AXIS_TRIGGER_RIGHT, 1.0)]
	actions["p2_brake"] = [_key(KEY_DOWN), _joy_btn(1, JOY_BUTTON_B), _joy_axis(1, JOY_AXIS_TRIGGER_LEFT, 1.0)]
	actions["p2_steer_left"] = [_key(KEY_LEFT), _joy_axis(1, JOY_AXIS_LEFT_X, -1.0), _joy_btn(1, JOY_BUTTON_DPAD_LEFT)]
	actions["p2_steer_right"] = [_key(KEY_RIGHT), _joy_axis(1, JOY_AXIS_LEFT_X, 1.0), _joy_btn(1, JOY_BUTTON_DPAD_RIGHT)]
	actions["p2_drift"] = [_key(KEY_CTRL, KEY_LOCATION_RIGHT), _key(KEY_KP_0), _joy_btn(1, JOY_BUTTON_RIGHT_SHOULDER)]
	actions["p2_use_item"] = [_key(KEY_KP_ENTER), _key(KEY_SHIFT, KEY_LOCATION_RIGHT), _key(KEY_KP_1), _joy_btn(1, JOY_BUTTON_LEFT_SHOULDER), _joy_btn(1, JOY_BUTTON_X)]
	actions["p2_look_back"] = [_key(KEY_KP_PERIOD), _key(KEY_KP_2), _joy_btn(1, JOY_BUTTON_Y)]
	actions["p2_up"] = [_key(KEY_UP), _joy_axis(1, JOY_AXIS_LEFT_Y, -1.0), _joy_btn(1, JOY_BUTTON_DPAD_UP)]
	actions["p2_down"] = [_key(KEY_DOWN), _joy_axis(1, JOY_AXIS_LEFT_Y, 1.0), _joy_btn(1, JOY_BUTTON_DPAD_DOWN)]
	actions["p2_left"] = [_key(KEY_LEFT), _joy_axis(1, JOY_AXIS_LEFT_X, -1.0), _joy_btn(1, JOY_BUTTON_DPAD_LEFT)]
	actions["p2_right"] = [_key(KEY_RIGHT), _joy_axis(1, JOY_AXIS_LEFT_X, 1.0), _joy_btn(1, JOY_BUTTON_DPAD_RIGHT)]
	actions["p2_confirm"] = [_key(KEY_KP_ENTER), _key(KEY_CTRL, KEY_LOCATION_RIGHT), _joy_btn(1, JOY_BUTTON_A)]
	actions["p2_cancel"] = [_key(KEY_BACKSPACE), _key(KEY_KP_0), _joy_btn(1, JOY_BUTTON_B)]
	actions["p2_pause"] = [_key(KEY_P), _joy_btn(1, JOY_BUTTON_START)]

	# ---------------- Globais ----------------
	actions["pause"] = [_key(KEY_ESCAPE), _key(KEY_P), _joy_btn(-1, JOY_BUTTON_START)]
	actions["toggle_fullscreen"] = [_key(KEY_F11)]
	actions["debug_overlay"] = [_key(KEY_F3)]

	for action_name: String in actions:
		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": DEADZONE,
			"events": actions[action_name],
		})
	var err := ProjectSettings.save()
	print("Input map salvo (%d ações). Erro: %s" % [actions.size(), error_string(err)])
	quit()


func _key(code: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.device = -1
	ev.physical_keycode = code
	ev.location = location
	return ev


func _joy_btn(device: int, button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	return ev


func _joy_axis(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = value
	return ev
