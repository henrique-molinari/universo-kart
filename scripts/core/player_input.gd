class_name PlayerInput
extends RefCounted
## Entrada por jogador (P1 = índice 0, P2 = índice 1).
##
## Controles (Xbox) são lidos DIRETAMENTE por device (Input.get_joy_axis / is_joy_button_pressed),
## nunca pelas ações do InputMap: no Windows os IDs dos joypads nem sempre são 0 e 1.
## `refresh()` atribui os dois primeiros joypads conectados aos jogadores de forma "grudenta"
## (um jogador mantém seu controle enquanto ele estiver plugado; um controle novo ocupa a vaga livre).
## Os eventos de joypad das ações p1_*/p2_* são removidos em tempo de execução (só o teclado fica
## no InputMap), eliminando qualquer "linha cruzada" entre controles.
##
## Teclado (alternativa): P1 = WASD (+ Espaço drift, E/Q item); P2 = setas (+ Ctrl dir./Num0 drift,
## Enter numérico/Shift dir. item).

const ACCELERATE := "accelerate"
const BRAKE := "brake"
const STEER_LEFT := "steer_left"
const STEER_RIGHT := "steer_right"
const DRIFT := "drift"
const USE_ITEM := "use_item"
const LOOK_BACK := "look_back"
const UP := "up"
const DOWN := "down"
const LEFT := "left"
const RIGHT := "right"
const CONFIRM := "confirm"
const CANCEL := "cancel"
const PAUSE := "pause"

const DEADZONE := 0.18
const TRIGGER_DEADZONE := 0.08

## Device do joypad de cada jogador (-1 = nenhum).
static var slots: Array[int] = [-1, -1]
static var _stripped := false


static func action(player_index: int, action_name: String) -> StringName:
	return StringName("p%d_%s" % [player_index + 1, action_name])


## Reatribui os controles (chame no início e em Input.joy_connection_changed).
static func refresh() -> void:
	if not _stripped:
		_strip_joypad_events()
	var pads := Input.get_connected_joypads()
	pads.sort()
	for i in slots.size():
		if slots[i] >= 0 and not pads.has(slots[i]):
			slots[i] = -1
	for dev in pads:
		if slots.has(dev):
			continue
		var free := slots.find(-1)
		if free < 0:
			break
		slots[free] = dev


static func device_of(player_index: int) -> int:
	return slots[player_index] if player_index >= 0 and player_index < slots.size() else -1


static func _strip_joypad_events() -> void:
	_stripped = true
	for a in InputMap.get_actions():
		var s := String(a)
		if not (s.begins_with("p1_") or s.begins_with("p2_")):
			continue
		for ev in InputMap.action_get_events(a):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(a, ev)


static func _key(player_index: int, action_name: String) -> float:
	var a := action(player_index, action_name)
	return Input.get_action_strength(a) if InputMap.has_action(a) else 0.0


static func _btn(player_index: int, button: JoyButton) -> bool:
	var dev := device_of(player_index)
	return dev >= 0 and Input.is_joy_button_pressed(dev, button)


static func _axis(player_index: int, axis: JoyAxis, dz: float) -> float:
	var dev := device_of(player_index)
	if dev < 0:
		return 0.0
	var v := Input.get_joy_axis(dev, axis)
	if absf(v) < dz:
		return 0.0
	return signf(v) * (absf(v) - dz) / (1.0 - dz)


## Esterço em [-1, 1] (positivo = direita). Analógico esquerdo, D-pad ou teclado.
static func steer(player_index: int) -> float:
	var v := _axis(player_index, JOY_AXIS_LEFT_X, DEADZONE)
	if _btn(player_index, JOY_BUTTON_DPAD_LEFT):
		v -= 1.0
	if _btn(player_index, JOY_BUTTON_DPAD_RIGHT):
		v += 1.0
	v += _key(player_index, STEER_RIGHT) - _key(player_index, STEER_LEFT)
	return clampf(v, -1.0, 1.0)


## Acelerador 0..1: RT (analógico) ou A, ou teclado.
static func throttle(player_index: int) -> float:
	var v := maxf(_axis(player_index, JOY_AXIS_TRIGGER_RIGHT, TRIGGER_DEADZONE), 0.0)
	if _btn(player_index, JOY_BUTTON_A):
		v = 1.0
	return clampf(maxf(v, _key(player_index, ACCELERATE)), 0.0, 1.0)


## Freio/ré 0..1: LT ou teclado.
static func brake(player_index: int) -> float:
	var v := maxf(_axis(player_index, JOY_AXIS_TRIGGER_LEFT, TRIGGER_DEADZONE), 0.0)
	return clampf(maxf(v, _key(player_index, BRAKE)), 0.0, 1.0)


## Drift: B ou RB (ou teclado).
static func drift(player_index: int) -> bool:
	return _btn(player_index, JOY_BUTTON_B) or _btn(player_index, JOY_BUTTON_RIGHT_SHOULDER) \
		or _key(player_index, DRIFT) > 0.5


## Usar item: X ou LB (ou teclado). Nível; a borda é detectada por quem consome.
static func item(player_index: int) -> bool:
	return _btn(player_index, JOY_BUTTON_X) or _btn(player_index, JOY_BUTTON_LEFT_SHOULDER) \
		or _key(player_index, USE_ITEM) > 0.5


## Confirmar (menus/reinício): A ou Start (ou teclado).
static func confirm(player_index: int) -> bool:
	return _btn(player_index, JOY_BUTTON_A) or _btn(player_index, JOY_BUTTON_START) \
		or _key(player_index, CONFIRM) > 0.5


## Compatibilidade com o código antigo (somente teclado).
static func is_pressed(player_index: int, action_name: String) -> bool:
	return Input.is_action_pressed(action(player_index, action_name))


static func steer_axis(player_index: int) -> float:
	return steer(player_index)


## Voltar/cancelar (menus): B ou Back (ou teclado).
static func cancel(player_index: int) -> bool:
	return _btn(player_index, JOY_BUTTON_B) or _btn(player_index, JOY_BUTTON_BACK) \
		or _key(player_index, CANCEL) > 0.5


## Navegação horizontal de menu em {-1, 0, 1}: analógico, D-pad ou teclado (A/D, setas).
static func nav_x(player_index: int) -> int:
	var v := _axis(player_index, JOY_AXIS_LEFT_X, 0.5)
	if _btn(player_index, JOY_BUTTON_DPAD_LEFT) or _key(player_index, LEFT) > 0.5:
		v = -1.0
	if _btn(player_index, JOY_BUTTON_DPAD_RIGHT) or _key(player_index, RIGHT) > 0.5:
		v = 1.0
	return 0 if absf(v) < 0.5 else int(signf(v))


## Navegação vertical de menu em {-1, 0, 1} (-1 = cima): analógico, D-pad ou teclado (W/S, setas).
static func nav_y(player_index: int) -> int:
	var v := _axis(player_index, JOY_AXIS_LEFT_Y, 0.5)
	if _btn(player_index, JOY_BUTTON_DPAD_UP) or _key(player_index, UP) > 0.5:
		v = -1.0
	if _btn(player_index, JOY_BUTTON_DPAD_DOWN) or _key(player_index, DOWN) > 0.5:
		v = 1.0
	return 0 if absf(v) < 0.5 else int(signf(v))
