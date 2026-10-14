class_name ModularAppearance
extends RefCounted
## Worn equipment as visible meshes on the common character rig.
##
## The hero rig (assets/models/knight2) keeps its skeleton and every game clip; its fused armoured mesh is replaced by
## separate skinned pieces, one GLB per piece (assets/models/modular/*.glb, made by tools/art/modular_export.py). Which
## pieces show is a pure function of the equipped items (`pieces_for`) through data/appearance/equipment_visuals.json, so
## save/load restores the look from the item state alone and new equipment is a new GLB plus a table row.
##
## Binding: a piece's GLB carries its own copy of the Meshy skeleton only to name the joints. The mesh is re-parented under
## the character's Skeleton3D and given a Skin built from that skeleton's real rest poses, so it deforms with every clip.

const TABLE_PATH := "res://data/appearance/equipment_visuals.json"
const WORN_SLOTS: Array[int] = [Items.Slot.ARMOR, Items.Slot.HELM, Items.Slot.GLOVES, Items.Slot.BOOTS, Items.Slot.SHIELD]

static var _table: Dictionary = {}
static var _scenes: Dictionary = {}

var model: CharacterModel
var skeleton: Skeleton3D
var worn: Array[String] = []        # piece ids currently attached, sorted
var _nodes: Dictionary = {}         # piece id -> Array of MeshInstance3D
var bow_model: String = ""          # res:// path of the equipped bow's GLB, "" when none

static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
		_table = parsed if parsed is Dictionary else {}
	return _table

## Opt-in while the knight2 presentation stays the default: `-- --modular`.
static func enabled_for(member_id: String) -> bool:
	return member_id == "hero" and "--modular" in OS.get_cmdline_user_args()

static func _entry(item: Variant) -> Dictionary:
	if not (item is Dictionary):
		return {}
	return table().get("items", {}).get(String((item as Dictionary).get("def", "")), {})

## The pieces that show for an equipment dictionary ({Items.Slot: item}); the order is stable (sorted).
static func pieces_for(equipment: Dictionary) -> Array[String]:
	var pieces: Array[String] = []
	pieces.assign(table().get("base", []))
	var hidden: Array = []
	for slot in WORN_SLOTS:
		var entry := _entry(equipment.get(slot))
		for part in entry.get("parts", []):
			if not pieces.has(part):
				pieces.append(part)
		hidden.append_array(entry.get("hides", []))
	var result: Array[String] = []
	for piece in pieces:
		if not hidden.has(piece):
			result.append(piece)
	result.sort()
	return result

static func bow_model_for(equipment: Dictionary) -> String:
	var id: String = String(_entry(equipment.get(Items.Slot.WEAPON)).get("bow_model", ""))
	return "" if id == "" else String(table()["model_dir"]) + id + ".glb"

func _init(character_model: CharacterModel) -> void:
	model = character_model
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	# the fused armoured knight mesh of the source rig is replaced by the pieces
	for mesh in skeleton.find_children("*", "MeshInstance3D", false, false):
		skeleton.remove_child(mesh)
		mesh.queue_free()

## Brings the attached pieces in line with `equipment`. Returns true when anything changed.
func sync(equipment: Dictionary) -> bool:
	bow_model = ModularAppearance.bow_model_for(equipment)
	var wanted := ModularAppearance.pieces_for(equipment)
	if wanted == worn:
		return false
	for piece in worn:
		if not wanted.has(piece):
			for node in _nodes.get(piece, []):
				if is_instance_valid(node):
					node.get_parent().remove_child(node)   # now, so a re-added piece keeps its name
					node.queue_free()
			_nodes.erase(piece)
	for piece in wanted:
		if not worn.has(piece):
			_nodes[piece] = _attach(piece)
	worn = wanted
	return true

func _attach(piece: String) -> Array:
	var path: String = String(table()["model_dir"]) + piece + ".glb"
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var inst: Node = (_scenes[path] as PackedScene).instantiate()
	var source: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var out: Array = []
	for mesh in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		var skin := Skin.new()
		for i in mi.skin.get_bind_count():
			var bone_name: String = mi.skin.get_bind_name(i)
			if bone_name == "":
				bone_name = source.get_bone_name(mi.skin.get_bind_bone(i))
			var bone: int = skeleton.find_bone(bone_name)
			assert(bone >= 0, "piece %s binds unknown bone %s" % [piece, bone_name])
			skin.add_named_bind(bone_name, skeleton.get_bone_global_rest(bone).affine_inverse())
		mi.get_parent().remove_child(mi)
		mi.owner = null
		skeleton.add_child(mi)
		mi.skin = skin
		mi.skeleton = NodePath("..")
		mi.transform = Transform3D.IDENTITY
		mi.name = piece
		out.append(mi)
	inst.free()
	return out
