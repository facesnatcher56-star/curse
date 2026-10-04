class_name FlickerLight
extends Node
## Makes its parent OmniLight3D flicker like a flame.

var _base: float = 1.0
var _time: float = randf() * 10.0

func _ready() -> void:
	_base = (get_parent() as OmniLight3D).light_energy

func _process(delta: float) -> void:
	_time += delta
	var light := get_parent() as OmniLight3D
	light.light_energy = _base * (0.85 + 0.15 * sin(_time * 13.0) + 0.1 * sin(_time * 31.0 + 1.7))
