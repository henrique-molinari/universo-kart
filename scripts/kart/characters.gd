class_name Characters
extends RefCounted
## Elenco de personagens escolhíveis (id = PlayerConfig.character):
##   0..1  ETs (AlienDriver): Visitante e Turista do Universo.
##   2..5  Pilotos (PilotDriver): o mesmo modelo de piloto humano com capacete, cada esquema de cores
##         (PilotDriver.SCHEMES, na mesma ordem) é um piloto diferente.
##   6     Astronauta do Universo (AstronautDriver): traje espacial estilo NASA com emblemas UNIFEOB.

const FIRST_PILOT := 2
const ASTRONAUT := 6
const NAMES: Array[String] = [
	"Visitante do Universo", "Turista do Universo",
	"Piloto Relâmpago", "Piloto Oceano", "Piloto Esmeralda", "Piloto Arco-Íris",
	"Astronauta do Universo",
]


static func count() -> int:
	return NAMES.size()


static func is_pilot(id: int) -> bool:
	return id >= FIRST_PILOT and id < ASTRONAUT


static func is_astronaut(id: int) -> bool:
	return id == ASTRONAUT


static func pilot_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in range(FIRST_PILOT, ASTRONAUT):
		ids.append(id)
	return ids


## Cor do traje: a do capacete nos pilotos, a cor própria de cada ET.
static func suit_color(id: int) -> Color:
	if is_astronaut(id):
		return AstronautDriver.SCHEME["suit"]
	if is_pilot(id):
		return PilotDriver.scheme_of(id)["suit"]
	return AlienDriver.SUIT_COLORS[clampi(id, 0, AlienDriver.SUIT_COLORS.size() - 1)]


static func make_driver(id: int) -> AlienDriver:
	if is_astronaut(id):
		return AstronautDriver.new()
	return PilotDriver.new() if is_pilot(id) else AlienDriver.new()
