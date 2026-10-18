class_name ShowcaseCamera
extends Camera3D
## Câmera de apresentação que percorre a pista (usada na tela inicial/atração).

@export var track: Track
@export var speed: float = 22.0
@export var height: float = 5.5
@export var look_ahead: float = 28.0
@export var lateral: float = 0.0

var _offset: float = 0.0


func _ready() -> void:
	far = 6000.0
	if track and not track.is_ready:
		await track.track_ready
	_offset = 0.0


func _process(delta: float) -> void:
	if track == null or not track.is_ready:
		return
	var tp := track.track_path
	_offset = tp.wrap_offset(_offset + speed * delta)
	var sway := sin(_offset * 0.01) * 3.0
	var pos := tp.to_world(_offset, lateral + sway, height)
	var target := tp.to_world(_offset + look_ahead, lateral * 0.5, 1.5)
	global_transform = global_transform.interpolate_with(Transform3D().looking_at(target - pos, Vector3.UP).translated(pos), minf(1.0, delta * 6.0))
