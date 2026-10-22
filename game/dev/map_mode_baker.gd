class_name MapModeBaker
extends CryptBaker
## Writes the map-mode dungeon scene (`game/world/dungeons/map_mode_01.tscn`) from the plan in MapModeLayout, with the Crypt's baker: the floor, walls,
## doorways, posts, chamfers, round boss room, torches, scatter, floor detail, chests and enemy markers are CryptBaker's, reading MapModeLayout instead of
## CryptLayout. What differs is the furniture (braziers, sarcophagi, shrine altars) and the markers' names (`Node<id>`). Developer tool:
##   godot --headless --path . -s res://tools/build_map_mode_01.gd
## The scene it writes is the source from then on (docs/MAP_MODE_DUNGEON.md).

const MAP_OUT := "res://game/world/dungeons/map_mode_01.tscn"


func _init() -> void:
	L = MapModeLayout
	out_path = MAP_OUT
	root_name = "MapMode01"


func _group_names() -> Array:
	var names: Array = super._group_names()
	names.append("Shrines")
	return names


## Breakables per room: the big rooms get more; corridors none.
func _prop_targets() -> Dictionary:
	var targets: Dictionary = {}
	for n in MapModeLayout.NODES:
		var rect: Array = n["rect"]
		var area: int = (int(rect[2]) - int(rect[0]) + 1) * (int(rect[3]) - int(rect[1]) + 1)
		targets[MapModeLayout._space_name(n)] = clampi(area / 10, 2, 9)
	return targets


## Solid furniture, laid before the props so they keep clear of it: the plan's cover pillars, braziers in the corners, sarcophagi along the north
## wall of the wide rooms, pillars in the boss room, an altar in each shrine. The middle of every room stays empty: that is where the party arrives.
func _set_pieces() -> void:
	# Cover: a pillar on every cell the plan names (MapModeLayout NODES `cover`), placed first-come so the braziers and props keep clear of them.
	for n in MapModeLayout.NODES:
		for cell in n.get("cover", []):
			_solid("SetPieces", KK % "pillar_decorated", L.world((cell as Vector2).x, (cell as Vector2).y), 0.0, 4.0, 0.75, "Cover%d" % int(n["id"]))
	for n in MapModeLayout.NODES:
		var rect: Array = n["rect"]
		var kind: String = String(n["kind"])
		var cx: float = (float(rect[0]) + float(rect[2])) * 0.5
		var cols: int = int(rect[2]) - int(rect[0]) + 1
		var rows: int = int(rect[3]) - int(rect[1]) + 1
		var id: int = int(n["id"])
		if kind != "boss":
			var inset: float = 1.5 if kind not in ["chest", "shrine"] else 1.3
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var corner := Vector2(float(rect[0]) if sx < 0.0 else float(rect[2]), float(rect[1]) if sy < 0.0 else float(rect[3]))
					var spot: Vector2 = L.world(corner.x - sx * (inset - 0.5), corner.y - sy * (inset - 0.5))
					if not _near_door(spot, 4.6) and not _near_route(spot, 3.4) and _spot_free(spot, 1.2):   # nothing on a corridor's line, in a doorway or on cover
						_brazier(spot, "Brazier%d" % id)
		if cols >= 9 and kind in ["pack", "champion", "swarm"]:
			for side in [-1.0, 1.0]:
				var at: Vector2 = L.world(cx + side * 3.2, float(rect[1]) + 0.55)
				if not _near_door(at, 4.6) and not _near_route(at, 3.4) and _spot_free(at, 1.6):
					_sarcophagus(at, 0.0, "N%d" % id)
	# The boss room: two rows of pillars either side of the middle, as the Crypt's arena has.
	var bc: Vector2 = Vector2.ZERO
	for n in MapModeLayout.NODES:
		if String(n["kind"]) == "boss":
			bc = n["centre"]
	for dx in [-4.0, -2.0, 2.0, 4.0]:
		for dy in [-1.5, 2.5]:
			_solid("SetPieces", KK % "pillar_decorated", L.world(bc.x + dx, bc.y + dy), 0.0, 4.0, 0.75, "ArenaPillar")
	for dx in [-5.2, 5.2]:
		_brazier(L.world(bc.x + dx, bc.y - 0.5), "ArenaBrazier")
	for s in MapModeLayout.SHRINES:
		var p: Vector2 = L.world((s["cell"] as Vector2).x, (s["cell"] as Vector2).y)
		_altar(p, "ShrineAltar%d" % int(s["node"]), 1.2)
		var rune_mat := _flat_material(Color(0.05, 0.1, 0.12), 1.0)
		rune_mat.emission_enabled = true
		rune_mat.emission = Color(0.35, 0.85, 1.0)
		rune_mat.emission_energy_multiplier = 0.9
		var ring := TorusMesh.new()
		ring.inner_radius = 0.93
		ring.outer_radius = 1.0
		ring.rings = 28
		ring.ring_segments = 4
		var holder := Node3D.new()
		holder.position = Vector3(p.x, 0.0, p.y)
		holder.add_child(_flat_mesh(ring, rune_mat, Vector3(2.2, 0.03, 2.2), Vector3(0, 0.04, 0), 0.0))
		holder.add_child(_flat_mesh(ring, rune_mat, Vector3(1.5, 0.03, 1.5), Vector3(0, 0.04, 0), 0.0))
		_add("Decor", holder, "ShrineRunes")
	_gateways()


## A Gateway (the Blender arch and doors, game/world/gateway.gd) across every corridor end: at the middle of the opening, its -Z pointing from the
## room into the corridor. An opening in a room's south wall faces the camera, so it gets the low one; a round room keeps its own arch.
func _gateways() -> void:
	var openings: Dictionary = {}   # "room|corridor" -> {sum (world x, z of the edges), n, out}
	for r in L.H:
		for c in L.W:
			var room: String = L.space_at(c, r)
			if room == "" or room.begins_with("c") or L.ROUNDS.has(room):
				continue
			for d in 4:
				var step: Vector2i = DIRS[d]
				var other: String = L.space_at(c + step.x, r + step.y)
				if not other.begins_with("c"):
					continue
				var key: String = "%s|%s" % [room, other]
				var row: Dictionary = openings.get(key, {"sum": Vector2.ZERO, "n": 0, "out": Vector2(step)})
				row["sum"] = (row["sum"] as Vector2) + L.world(c, r) + Vector2(step) * C * 0.5
				row["n"] = int(row["n"]) + 1
				openings[key] = row
	for key in openings:
		var row: Dictionary = openings[key]
		var at: Vector2 = (row["sum"] as Vector2) / float(row["n"])
		var out: Vector2 = row["out"]
		var gate := Node3D.new()
		gate.set_script(load("res://game/world/gateway.gd"))
		gate.set("low", out.y > 0.5)   # the corridor leaves through the room's south wall
		gate.position = Vector3(at.x, 0.0, at.y)
		gate.rotation.y = atan2(-out.x, -out.y)   # local -Z along `out`
		_add("SetPieces", gate, "Gateway")
	_counts["gateways"] = openings.size()


## True when `p` (world x, z) is within `margin` m of a link's path: the lines the party walks stay clear of furniture and props.
func _near_route(p: Vector2, margin: float) -> bool:
	for link in MapModeLayout.LINKS:
		var path: Array = link["path"]
		for i in path.size() - 1:
			var a: Vector2 = L.world((path[i] as Vector2).x, (path[i] as Vector2).y)
			var b: Vector2 = L.world((path[i + 1] as Vector2).x, (path[i + 1] as Vector2).y)
			var ab: Vector2 = b - a
			var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			if p.distance_to(a + ab * t) < margin:
				return true
	return false


## The base bakery keeps breakables off pack homes with this; here it also keeps them off the corridor lines.
func _near_pack(p: Vector2) -> bool:
	return super._near_pack(p) or _near_route(p, 2.6)


## Decor only (no collision): bone piles in the corners of the big rooms, urns, cobwebs, puddles.
func _dress() -> void:
	for n in MapModeLayout.NODES:
		if String(n["kind"]) in ["start", "boss", "shrine"]:
			continue
		var rect: Array = n["rect"]
		var cols: int = int(rect[2]) - int(rect[0]) + 1
		if cols < 7:
			_urns(L.world(float(rect[0]) + 0.8, float(rect[3]) - 0.8), 3)
			continue
		_bone_pile(L.world(float(rect[0]) + 0.9, float(rect[1]) + 2.4))
		_bone_pile(L.world(float(rect[2]) - 0.9, float(rect[3]) - 2.4))
		_urns(L.world(float(rect[2]) - 0.8, float(rect[1]) + 0.8), 3)
	_cobwebs()
	_puddles()


func _chest_nodes() -> void:
	super._chest_nodes()
	_shrine_nodes()


## One Marker3D per shrine, `Node<id>` under Shrines, standing at its altar.
func _shrine_nodes() -> void:
	for s in MapModeLayout.SHRINES:
		var p: Vector2 = L.world((s["cell"] as Vector2).x, (s["cell"] as Vector2).y)
		var marker := Marker3D.new()
		marker.name = "Node%d" % int(s["node"])
		marker.position = Vector3(p.x, 0.0, p.y)
		(_groups["Shrines"] as Node3D).add_child(marker)
		marker.owner = root
