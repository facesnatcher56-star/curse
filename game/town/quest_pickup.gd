class_name QuestPickup
extends Node3D
## A quest item lying on the road (see Quests, kind "fetch"): a satchel, a ledger, whatever the quest asks for. It glows with a marker
## that stays one size on screen, and picking it up is walking over it. It is not an item for the bag: it only counts for its quest.

signal found(uid: int)

const PICKUP_RADIUS := 1.7

var uid: int = 0
var item_name: String = ""
var _age: float = 0.0
var _marker: Sprite3D

static func spawn(parent: Node, at: Vector3, quest_uid: int, name_of_item: String) -> QuestPickup:
	var pickup := QuestPickup.new()
	pickup.uid = quest_uid
	pickup.item_name = name_of_item
	parent.add_child(pickup)
	pickup.global_position = Vector3(at.x, 0.0, at.z)
	return pickup

func _ready() -> void:
	add_to_group("quest_pickups")
	# A small worn bundle on the ground: a leather satchel with a strap.
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.38, 0.2, 0.26)
	body.mesh = box
	body.position = Vector3(0, 0.1, 0)
	body.rotation.y = 0.5
	body.material_override = _material(Color(0.26, 0.17, 0.09))
	add_child(body)
	var strap := MeshInstance3D.new()
	var strap_box := BoxMesh.new()
	strap_box.size = Vector3(0.06, 0.22, 0.28)
	strap.mesh = strap_box
	strap.position = Vector3(0, 0.11, 0)
	strap.rotation.y = 0.5
	strap.material_override = _material(Color(0.12, 0.08, 0.05))
	add_child(strap)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.position = Vector3(0, 1.2, 0)
	light.shadow_enabled = false
	add_child(light)
	_marker = Sprite3D.new()
	_marker.texture = _diamond()
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.fixed_size = true
	_marker.no_depth_test = true
	_marker.shaded = false
	_marker.modulate = Color(1.0, 0.82, 0.3)
	_marker.pixel_size = 0.0006
	_marker.position = Vector3(0, 1.4, 0)
	_marker.render_priority = 5
	add_child(_marker)

static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat

static var _tex: ImageTexture

static func _diamond() -> ImageTexture:
	if _tex == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d: float = (absf(x - 15.5) + absf(y - 15.5)) / 15.5
				if d <= 1.0:
					var core: float = 1.0 if d > 0.6 else 0.5
					img.set_pixel(x, y, Color(core, core, core, clampf((1.0 - d) * 6.0, 0.0, 1.0)))
		_tex = ImageTexture.create_from_image(img)
	return _tex

func _process(delta: float) -> void:
	_age += delta
	_marker.modulate.a = 0.75 + 0.25 * sin(_age * 4.0)
	for node in get_tree().get_nodes_in_group("player"):
		var hero := node as Node3D
		if hero == null or bool(hero.get("dead")):
			continue
		var offset: Vector3 = hero.global_position - global_position
		offset.y = 0.0
		if offset.length() <= PICKUP_RADIUS:
			found.emit(uid)
			queue_free()
			return
