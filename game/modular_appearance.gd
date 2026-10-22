class_name ModularAppearance
extends RefCounted
## Worn equipment as visible meshes on the common character rig.
##
## The hero rig keeps its skeleton and every game clip; what it wears is separate skinned pieces, one GLB per piece. Which
## pieces show is a pure function of the equipped items (`pieces_for`) through data/appearance/equipment_visuals.json, so
## save/load restores the look from the item state alone and new equipment is a new GLB plus a table row.
##
## Per rig (table "rigs", keyed by the rig folder): where its pieces live, which pieces it always wears, and whether item
## pieces show at all. Pieces are made to fit the rig, not the other way round; the barbarian hero has
## `equipment_pieces: false` until his item models are built (owner), so he shows only his base and CharacterModel draws no
## held weapon or bow for him (`show_items`). A rig's own meshes whose names are base piece ids (the barbarian's
## body_skin, body_hair, body_beard, clt_briefs) are built-in pieces, shown or hidden like any other piece, never
## reloaded. Any other mesh of the rig (the knight's fused armoured char1) is dropped. A rig with no entry uses the
## table's top-level model_dir and base (the knight2 kit).
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
var _dir: String = ""               # where this rig's pieces live
var _builtin: Dictionary = {}       # piece id -> the rig's own MeshInstance3D for it

static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_PATH))
		_table = parsed if parsed is Dictionary else {}
	return _table

## Modular hero is the default; opt out with `--classic`. `--modular` is accepted as a harmless no-op.
static func enabled_for(member_id: String) -> bool:
	return member_id == "hero" and not ("--classic" in OS.get_cmdline_user_args())

static func _entry(item: Variant) -> Dictionary:
	if not (item is Dictionary):
		return {}
	return table().get("items", {}).get(String((item as Dictionary).get("def", "")), {})

## The table entry for a rig folder: {model_dir, base, equipment_pieces}; falls back to the top-level knight2 kit.
static func rig(folder: String) -> Dictionary:
	var entry: Dictionary = table().get("rigs", {}).get(folder, {})
	return {"model_dir": entry.get("model_dir", table().get("model_dir", "")), "base": entry.get("base", table().get("base", [])),
		"equipment_pieces": entry.get("equipment_pieces", true)}

## The pieces that show for an equipment dictionary ({Items.Slot: item}) on a rig; the order is stable (sorted). A rig
## whose item models are not built yet shows only its base, whatever it wears.
static func pieces_for(equipment: Dictionary, folder: String = CharacterPresentation.folder("hero")) -> Array[String]:
	var pieces: Array[String] = []
	pieces.assign(rig(folder)["base"])
	if not rig(folder)["equipment_pieces"]:
		pieces.sort()
		return pieces
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
	return "" if id == "" else String(table()["model_dir"]) + id + ".glb"   # rigid prop: rig independent

func _init(character_model: CharacterModel) -> void:
	model = character_model
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var entry := ModularAppearance.rig(model.folder)
	_dir = String(entry["model_dir"])
	for mesh in skeleton.find_children("*", "MeshInstance3D", false, false):
		var piece := String(mesh.name)
		if (entry["base"] as Array).has(piece):
			_builtin[piece] = mesh   # the rig's own body, hair, beard, underwear: shown while worn
			mesh.visible = false
		else:
			skeleton.remove_child(mesh)   # e.g. the knight's fused armoured mesh, replaced by the pieces
			mesh.queue_free()

## Brings the attached pieces in line with `equipment`. Returns true when anything changed.
func sync(equipment: Dictionary) -> bool:
	bow_model = ModularAppearance.bow_model_for(equipment)
	var wanted := ModularAppearance.pieces_for(equipment, model.folder)
	if wanted == worn:
		return false
	for piece in _builtin:
		(_builtin[piece] as MeshInstance3D).visible = wanted.has(piece)
	for piece in worn:
		if not wanted.has(piece) and not _builtin.has(piece):
			for node in _nodes.get(piece, []):
				if is_instance_valid(node):
					node.get_parent().remove_child(node)   # now, so a re-added piece keeps its name
					node.queue_free()
			_nodes.erase(piece)
	for piece in wanted:
		if not worn.has(piece) and not _builtin.has(piece):
			_nodes[piece] = _attach(piece)
	worn = wanted
	return true

func _attach(piece: String) -> Array:
	var path: String = _dir + piece + ".glb"
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
