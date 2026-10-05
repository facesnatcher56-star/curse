@tool
class_name TownProp
extends Node3D
## A marker for one prop in the town layout (game/town/town_layout.tscn): which model, how tall, whether it blocks and whether it
## glows. Move and turn it in the editor like any node. In the editor it shows a preview of the model; when the town runs,
## TownScene reads these markers and hands each one to Arena.place_prop (which scales the model, builds the collision, the
## light and the navigation hole), then throws the markers away.

@export var model_name: String = "":   # a folder under res://assets/models/, e.g. "cottage" or "town/inn"
	set(value):
		model_name = value
		_preview()
@export var height: float = 1.0:   # metres, the model is scaled to this
	set(value):
		height = value
		_preview()
## Whether it blocks movement (and is cut out of the navigation mesh).
@export var collides: bool = true
## An ember light with a flicker (lamp posts, braziers).
@export var lit: bool = false

var _shown: Node3D

func _ready() -> void:
	_preview()

func _preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _shown != null:
		_shown.queue_free()
		_shown = null
	var path: String = Arena.PROP_DIR + model_name + "/model.glb"
	if model_name == "" or not ResourceLoader.exists(path):
		return
	_shown = (load(path) as PackedScene).instantiate()
	if model_name.begins_with("town/"):
		LootDrop._use_vertex_colours(_shown)
	var bounds: AABB = CharacterModel._bounds_of(_shown)
	var factor: float = height / maxf(bounds.size.y, 0.001)
	_shown.scale = Vector3.ONE * factor
	_shown.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z) * factor
	add_child(_shown)   # no owner: a preview, never saved into the scene
