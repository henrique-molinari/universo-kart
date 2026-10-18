class_name PlayerConfig
extends Resource
## Configuração de um corredor (humano ou IA).
## O piloto ET (traje) usa SEMPRE a mesma cor do kart: use set_color().

@export var display_name: String = "Jogador"
@export var is_human: bool = true
@export var player_index: int = 0          ## 0 = P1, 1 = P2 (apenas humanos)
@export var helmet_color: Color = Palette.BLUE
@export var suit_color: Color = Palette.BLUE
@export var kart_color: Color = Palette.MAGENTA
@export var color_index: int = 0           ## índice em Palette.SELECT_COLORS
@export var character: int = 0             ## AlienDriver.Character (0 Visitante, 1 Turista)


## Aplica a mesma cor ao kart, ao traje e ao capacete.
func set_color(c: Color) -> void:
	kart_color = c
	suit_color = c
	helmet_color = c


func duplicate_config() -> PlayerConfig:
	return duplicate() as PlayerConfig
