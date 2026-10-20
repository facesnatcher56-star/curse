class_name HudLootCards
extends RefCounted
## What the HUD shows for loot on the ground: a name plate over every item (laid out so they never overlap; they are also what you click or
## point at to pick an item up) and the details card of the one in focus, which on the return waystone fits itself round the town's
## prompt. It draws on the HUD's own canvas, from Hud._draw, so it keeps its place in the HUD's drawing order.

var hud: Hud
var names: Array[Dictionary] = []   # [{drop, rect, anchor}] this frame's name plates over the items on the ground
var ground_card_rect := Rect2()   # actual drawn ground card, for focused layout regression checks

## Every item on the ground shows its name over it, in its rarity's colour. The plates are laid out on the screen so that they never
## overlap: they are placed from the bottom of the screen (nearest the camera) up, and any plate that would land on another is lifted
## above it, with a thin line back to its item.
const NAME_HEIGHT := 21.0
const NAME_FONT := 15
const PLATE_MARGIN := 8.0   # a name plate keeps this far inside the screen's left and right edges
const UPGRADE_COLOR := LootAppraisal.UPGRADE_COLOR
const LOCKED_COLOR := LootAppraisal.LOCKED_COLOR
## Room for the upgrade arrow or the locked cross at the left end of a name plate.
const MARK_WIDTH := 16.0

## Map mode's loot summary after a clear (show_summary): {title, gold, health, mana, rows, until_ms}; empty when none is showing.
## A row is {item, mark: Mark, who}: how the item compares with what the party wears, by LootAppraisal's own comparison.
enum Mark { LOCKED = -2, DOWN = -1, EVEN = 0, UP = 1 }
var summary: Dictionary = {}
var summary_rect := Rect2()

## The item under the mouse (or, with a controller, the nearest one within reach): what it is, what it does, and how it compares with
## what is worn in that slot, with a note on whether walking over it will put it on or send it to the bag.
func draw(size_px: Vector2, font: Font) -> void:
	ground_card_rect = Rect2()
	if hud.player != null and hud.player.dead:   # the death plate owns the screen: no loot name plates or item card showing through it
		names = []
		LootDrop.focused = null
		_hide_ground_card()
		return
	names = _layout_loot_names(font)
	_draw_loot_names(font)
	_draw_summary(size_px, font)
	var drop: LootDrop = drop_in_focus()
	LootDrop.focused = drop
	if drop == null:
		_hide_ground_card()
		return
	var pointer: Vector2 = hud.get_viewport().get_mouse_position() if hud.mouse_override.x < 0.0 else hud.mouse_override
	var anchor: Vector2 = pointer + Vector2(24, 18) if not Gamepad.active else Vector2(size_px.x * 0.5 + 40.0, size_px.y * 0.5 - 150.0)
	_draw_card(drop.item, hud.player.stats.equipment.get(int(drop.item["slot"])), anchor, size_px, font, true, true)

## An item's details card at `anchor`: the one shared card (ItemTile.card), whose action hint, for a drop on the ground, says whether walking
## over it will put it on or send it to the bag. The card keeps its full text size and grows with its content. With the return waystone
## prompt on screen it takes clear room beside that prompt; it is never shrunk to fit. It is a Control on the HUD (never in the way of the
## mouse), rebuilt only when what it shows changes.
func _draw_card(item: Dictionary, worn: Variant, anchor: Vector2, size_px: Vector2, _font: Font, with_compare: bool, for_drop: bool) -> void:
	var member: String = PartyManager.current().active_id
	var walk: Dictionary = _walk_over(item) if for_drop else {"text": "", "color": Color(0, 0, 0, 0)}
	var key := "%d|%d|%s|%s|%s|%s|%s" % [item.hash(), (worn as Dictionary).hash() if worn != null else 0, with_compare, member, walk.text, Gamepad.active, Items.hero_can_wear(item, member)]
	if _ground_card == null or not is_instance_valid(_ground_card) or key != _ground_key:
		_hide_ground_card(true)
		_ground_card = ItemTile.card(item, worn, with_compare, false, String(walk.text), walk.color)
		_ground_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in _ground_card.find_children("*", "Control", true, false):
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ground_card.z_index = 30
		hud.add_child(_ground_card)
		_ground_key = key
	_ground_card.size = _ground_card.get_combined_minimum_size()
	var card_size: Vector2 = _ground_card.size
	var return_prompt := _return_prompt_rect() if for_drop else Rect2()
	var origin: Vector2
	if return_prompt.has_area():
		origin = _return_card_origin(card_size, anchor, size_px, return_prompt)
	else:
		origin = Vector2(clampf(anchor.x, 8.0, maxf(8.0, size_px.x - card_size.x - 8.0)), clampf(anchor.y, 8.0, maxf(8.0, size_px.y - card_size.y - 110.0)))
	if for_drop:
		ground_card_rect = Rect2(origin, card_size)
	_ground_card.position = origin
	_ground_card.visible = true

var _ground_card: Control
var _ground_key := ""

func _hide_ground_card(free: bool = false) -> void:
	if _ground_card == null or not is_instance_valid(_ground_card):
		_ground_card = null
		return
	if free:
		_ground_card.queue_free()
		_ground_card = null
	else:
		_ground_card.visible = false

## What walking over a drop does, with the appraisal's verdict: worn at once, a better piece waiting in the bag, or not wearable yet.
func _walk_over(item: Dictionary) -> Dictionary:
	var stats: PlayerStats = hud.player.stats
	if MapMode.active:   # map mode collects loot by itself: no instruction to give
		return {"text": "", "color": Color(0, 0, 0, 0)}
	if stats.takes_empty_slot(item):
		return {"text": "Walk over to wear it", "color": Color(0.95, 0.8, 0.5)}
	match LootAppraisal.of(item, stats):
		LootAppraisal.Verdict.UPGRADE:
			return {"text": "Walk over to pick up (better than worn)", "color": UPGRADE_COLOR}
		LootAppraisal.Verdict.LOCKED:
			return {"text": "Walk over to pick up", "color": LOCKED_COLOR}   # the card's one "You cannot wear this yet" line says why
	return {"text": "Walk over to pick up", "color": ItemTile.HINT_COLOR}

## Restrict clearance to the active return-waystone decision; other cards retain their layout.
func _return_prompt_rect() -> Rect2:
	var node := hud.get_parent()
	while node != null:
		if node is TownScene:
			var town := node as TownScene
			if String(town.near.get("kind", "")) == "waystone" and town.hud != null:
				return town.hud.interaction_prompt_rect()
			break
		node = node.get_parent()
	return Rect2()

## Where the card goes on the return waystone: the nearest spot to its item where the whole card (at full size) is clear of the prompt, the
## HUD and the name plates. Only when no such spot exists does it stay on screen beside the item and accept the overlap, rather than shrink.
func _return_card_origin(card_size: Vector2, anchor: Vector2, screen: Vector2, prompt: Rect2) -> Vector2:
	var obstacles: Array[Rect2] = [prompt.grow(6.0), Hud.minimap_rect(screen, hud.use_ds2_ui).grow(7.0), Hud.orb_rect(screen, false).grow(7.0), Hud.orb_rect(screen, true).grow(7.0)]
	obstacles.append(Rect2(14, 14 + hud.top_offset, 250, 62 if hud.objective != "" or hud.wave > 0 else 38).grow(6.0))
	var node := hud.get_parent()
	while node != null:
		if node is TownScene:
			for overlay in (node as TownScene).hud.overlay_rects:
				obstacles.append(overlay.grow(6.0))
			break
		node = node.get_parent()
	for entry in names:
		obstacles.append((entry["rect"] as Rect2).grow(6.0))
	obstacles.append(hud.hotbar_rect(screen).grow(6.0))
	if hud.progression_hud != null:
		obstacles.append(hud.progression_hud.strip_rect(screen).grow(6.0))
	var bounds := Rect2(Vector2(8, 8), Vector2(screen.x - 16, screen.y - 118))
	var xs: Array[float] = [bounds.position.x, bounds.end.x]
	for obstacle in obstacles:
		for edge in [obstacle.position.x, obstacle.end.x]:
			var x := clampf(edge, bounds.position.x, bounds.end.x)
			if not xs.has(x):
				xs.append(x)
	xs.sort()
	var spaces: Array[Rect2] = []
	for left in xs:
		for right in xs:
			if right <= left:
				continue
			var spans: Array[Vector2] = []
			for obstacle in obstacles:
				if obstacle.position.x < right and obstacle.end.x > left and obstacle.position.y < bounds.end.y and obstacle.end.y > bounds.position.y:
					spans.append(Vector2(maxf(bounds.position.y, obstacle.position.y), minf(bounds.end.y, obstacle.end.y)))
			spans.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
			var top := bounds.position.y
			for span in spans:
				if span.x > top:
					spaces.append(Rect2(left, top, right - left, span.x - top))
				top = maxf(top, span.y)
			if top < bounds.end.y:
				spaces.append(Rect2(left, top, right - left, bounds.end.y - top))
	var best := Vector2.ZERO
	var best_score := INF
	for space in spaces:
		var room := space.grow(-4.0)   # the drawn panel has a four-pixel shadow: keep it clear too
		if room.size.x < card_size.x or room.size.y < card_size.y:
			continue
		var pos := Vector2(clampf(anchor.x, room.position.x, room.end.x - card_size.x), clampf(anchor.y, room.position.y, room.end.y - card_size.y))
		var score := pos.distance_squared_to(anchor)
		if score < best_score:
			best_score = score
			best = pos
	if best_score < INF:
		return best
	return Vector2(clampf(anchor.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - card_size.x)),
		clampf(anchor.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - card_size.y)))

## The dropped item the player is pointing at: under the mouse (by where it is on screen), or with a controller the nearest within reach.
func drop_in_focus() -> LootDrop:
	var best: LootDrop = null
	var best_d: float = 1.0e9
	if Gamepad.active:
		for node in hud.get_tree().get_nodes_in_group("loot"):
			var drop := node as LootDrop
			if drop == null or not drop.landed:
				continue
			var d: float = hud.player.global_position.distance_to(drop.global_position)
			if d < 4.0 and d < best_d:
				best_d = d
				best = drop
		return best
	var mouse: Vector2 = hud.get_viewport().get_mouse_position() if hud.mouse_override.x < 0.0 else hud.mouse_override
	if hud.mouse_over_hud(mouse):
		return null
	var camera: Camera3D = hud.get_viewport().get_camera_3d()
	if camera == null:
		return null
	for entry in names:   # a name plate under the pointer is the item
		if (entry["rect"] as Rect2).has_point(mouse):
			return entry["drop"]
	for node in hud.get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop == null or not drop.landed or camera.is_position_behind(drop.global_position):
			continue
		var d: float = minf(camera.unproject_position(drop.global_position + Vector3(0, 1.5, 0)).distance_to(mouse), camera.unproject_position(drop.global_position + Vector3(0, 0.5, 0)).distance_to(mouse))
		if d < 56.0 and d < best_d:
			best_d = d
			best = drop
	return best

## The summary's rows for a clear's items, worked out BEFORE they are picked up (an empty slot fills at once and would then compare equal): for each
## item the best mark over the party members who can wear it, with who that is; locked when none can yet.
static func summary_rows(tally: Dictionary, bodies: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in tally.get("items", []):
		var mark: int = Mark.LOCKED
		var who: String = ""
		for body in bodies:
			var member := body as Player
			if member == null or not is_instance_valid(member) or member.stats == null:
				continue
			if not Items.hero_can_wear(item, member.member_id):
				continue
			var t: int = LootAppraisal.trend(item, member.stats)
			if mark == Mark.LOCKED or t > mark:
				mark = t
				who = member.display_name
		out.append({"item": item, "mark": mark, "who": who})
	return out

## The reward screen after a clear (MapRewardPanel, a Control on the HUD over the reopened map). `guard` is the chest kind (its icon), `seconds` how
## long it may stay up unattended; it goes at Continue or when the next node is picked.
func show_summary(title: String, tally: Dictionary, rows: Array[Dictionary], seconds: float, guard: String = "") -> void:
	hide_summary()
	summary = {"title": title, "gold": int(tally.get("gold", 0)), "health": int(tally.get("health", 0)), "mana": int(tally.get("mana", 0)),
		"rows": rows, "guard": guard, "until_ms": Time.get_ticks_msec() + int(seconds * 1000.0)}
	reward_panel = MapRewardPanel.create(title, guard, tally, _party_bodies())
	reward_panel.continued.connect(hide_summary)
	hud.add_child(reward_panel)
	summary_rect = reward_panel.rect()

## The warrior and the Cutter, as far as they are in the world.
func _party_bodies() -> Array:
	var out: Array = []
	for id in ["hero", "cutter"]:
		var body: Variant = PartyManager.current().bodies.get(id)
		if body is Player and is_instance_valid(body):
			out.append(body)
	if out.is_empty() and hud.player != null:
		out.append(hud.player)
	return out

func hide_summary() -> void:
	summary = {}
	summary_rect = Rect2()
	if reward_panel != null and is_instance_valid(reward_panel):
		reward_panel.fade_out()
	reward_panel = null

var reward_panel: MapRewardPanel

## Keeps the panel's bookkeeping: gone after its time, out of sight while the inventory or character screen is open (they show the same items).
func _draw_summary(_size_px: Vector2, _font: Font) -> void:
	summary_rect = Rect2()
	if summary.is_empty():
		return
	if Time.get_ticks_msec() > int(summary["until_ms"]):
		hide_summary()
		return
	if reward_panel == null or not is_instance_valid(reward_panel):
		summary = {}
		return
	reward_panel.visible = not hud.show_gear
	if reward_panel.visible:
		summary_rect = reward_panel.rect()

## Each drop's verdict, worked out again at most every REAPPRAISE_MS (wearing something, levelling up or a new hero changes it), not every frame.
const REAPPRAISE_MS := 400
var _verdicts: Dictionary = {}   # LootDrop -> int
var _appraised_at: int = -REAPPRAISE_MS

func _verdict_of(drop: LootDrop) -> int:
	var now: int = Time.get_ticks_msec()
	if now - _appraised_at >= REAPPRAISE_MS:
		_verdicts.clear()
		_appraised_at = now
	if not _verdicts.has(drop):
		_verdicts[drop] = LootAppraisal.of(drop.item, hud.player.stats)
	return _verdicts[drop]

func _layout_loot_names(font: Font) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var camera: Camera3D = hud.get_viewport().get_camera_3d()
	if camera == null or hud.show_gear or hud.player == null:
		return out
	if MapMode.active and MapMode.current != null and MapMode.current.overlay != null and MapMode.current.overlay.is_open():
		return out   # the node map covers the world: plates for items left on the ground would float over it at meaningless spots
	var entries: Array[Dictionary] = []
	for node in hud.get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop == null or not drop.landed or camera.is_position_behind(drop.global_position):
			continue
		var anchor: Vector2 = camera.unproject_position(drop.global_position + Vector3(0, 0.4, 0))
		var width: float = font.get_string_size(String(drop.item["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT).x + 14.0
		var verdict: int = _verdict_of(drop)
		if verdict != LootAppraisal.Verdict.EVEN:
			width += MARK_WIDTH
		entries.append({"drop": drop, "anchor": anchor, "width": width, "verdict": verdict})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["anchor"].y > b["anchor"].y)
	var placed: Array[Rect2] = []
	var toast_rect: Rect2 = hud.progression_hud.toast_rect(hud.get_viewport_rect().size) if hud.progression_hud != null else Rect2()
	for entry in entries:
		var anchor: Vector2 = entry["anchor"]
		var screen_width: float = hud.get_viewport_rect().size.x
		var rect := Rect2(clampf(anchor.x - float(entry["width"]) * 0.5, PLATE_MARGIN, maxf(PLATE_MARGIN, screen_width - float(entry["width"]) - PLATE_MARGIN)),
			anchor.y - NAME_HEIGHT - 10.0, float(entry["width"]), NAME_HEIGHT)   # a plate near the screen edge slides inside it, never off it
		var original_y: float = rect.position.y
		var found: bool = false
		for step in 65:
			var distance: float = float((step + 1) / 2) * 12.0
			var offset: float = 0.0 if step == 0 else distance * (1.0 if step % 2 == 1 else -1.0)
			rect.position.y = clampf(original_y + offset, PLATE_MARGIN, hud.get_viewport_rect().size.y - NAME_HEIGHT - PLATE_MARGIN)
			if _plate_blocked(rect, toast_rect, placed):
				continue
			found = true
			break
		if not found:
			continue   # it would sit under the hotbar, the minimap or an open panel: left out, not drawn over them
		placed.append(rect)
		out.append({"drop": entry["drop"], "rect": rect, "anchor": anchor, "verdict": entry["verdict"]})
	return out

func _plate_blocked(rect: Rect2, toast_rect: Rect2, placed: Array[Rect2]) -> bool:
	if toast_rect.size != Vector2.ZERO and rect.grow(2.0).intersects(toast_rect):
		return true
	if hud.use_ds2_ui and is_instance_valid(hud.ds2_party_frame) and hud.ds2_party_frame.visible and rect.grow(6.0).intersects(hud.ds2_party_frame.get_global_rect()):
		return true
	if hud.use_ds2_ui and is_instance_valid(hud.ds2_target_banner) and hud.ds2_target_banner.visible and rect.grow(6.0).intersects(hud.ds2_target_banner.get_global_rect()):
		return true
	for other in placed:
		if rect.grow(2.0).intersects(other):
			return true
	return hud.covers(rect.position) or hud.covers(Vector2(rect.end.x, rect.position.y)) or hud.covers(Vector2(rect.position.x, rect.end.y)) or hud.covers(rect.end) or hud.covers(rect.get_center())

func _draw_loot_names(font: Font) -> void:
	var mouse: Vector2 = hud.get_viewport().get_mouse_position() if hud.mouse_override.x < 0.0 else hud.mouse_override
	for entry in names:
		var drop: LootDrop = entry["drop"]
		var rect: Rect2 = entry["rect"]
		var anchor: Vector2 = entry["anchor"]
		var colour: Color = Items.RARITY_COLORS[int(drop.item["rarity"])]
		var focus: bool = LootDrop.focused == drop or rect.has_point(mouse)
		var line_start: Vector2 = Vector2.ZERO
		var draw_connector: bool = false
		if rect.end.y < anchor.y - 12.0:   # lifted off its item: a line shows whose name it is
			line_start = Vector2(rect.get_center().x, rect.end.y)
			draw_connector = true
		elif rect.position.y > anchor.y + 12.0:   # moved below its item to clear the toast or a HUD panel
			line_start = Vector2(rect.get_center().x, rect.position.y)
			draw_connector = true
		if not draw_connector and (anchor.x < rect.position.x - 4.0 or anchor.x > rect.end.x + 4.0):   # slid sideways to stay on screen: a line shows whose it is
			line_start = Vector2(clampf(anchor.x, rect.position.x, rect.end.x), rect.get_center().y)
			draw_connector = true
		if draw_connector:
			var line_bounds := Rect2(line_start, Vector2(0.001, 0.001)).expand(anchor)
			var toast_rect: Rect2 = hud.progression_hud.toast_rect(hud.get_viewport_rect().size) if hud.progression_hud != null else Rect2()
			if toast_rect.size == Vector2.ZERO or not line_bounds.intersects(toast_rect):
				hud.draw_line(line_start, anchor, Color(colour.r, colour.g, colour.b, 0.55), 1.0)
		hud.draw_rect(rect, Color(0.03, 0.03, 0.04, 0.82 if focus else 0.62))
		hud.draw_rect(rect, Color(colour.r, colour.g, colour.b, 0.95 if focus else 0.45), false, 1.5 if focus else 1.0)
		var verdict: int = int(entry["verdict"])
		var shift: float = 0.0
		var text_colour: Color = colour.lightened(0.2 if focus else 0.0)
		if verdict != LootAppraisal.Verdict.EVEN:
			shift = MARK_WIDTH * 0.5
			_draw_mark(Vector2(rect.position.x + 9.0, rect.position.y + NAME_HEIGHT * 0.5), verdict == LootAppraisal.Verdict.UPGRADE)
			if verdict == LootAppraisal.Verdict.LOCKED:
				text_colour = text_colour.darkened(0.25)
		UiTheme.text(hud, font, rect.position + Vector2(shift, 15.5), String(drop.item["name"]), NAME_FONT, text_colour,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - shift)

## A red arrow down: worse than what is worn.
func _draw_arrow_down(at: Vector2) -> void:
	for row in 10:
		var half: float = 0.5 + float(row) * 0.5
		hud.draw_line(at + Vector2(-half, 5.0 - row), at + Vector2(half, 5.0 - row), LOCKED_COLOR, 1.0)

## A green arrow up (better than what you wear, or fills an empty slot) or a red cross (cannot be worn yet), drawn as shapes so no font is needed.
func _draw_mark(at: Vector2, upgrade: bool) -> void:
	if upgrade:
		for row in 10:   # a filled triangle as rows: no polygon to triangulate, which fails when the plate sits at an invalid screen position
			var half: float = 0.5 + float(row) * 0.5
			hud.draw_line(at + Vector2(-half, -5.0 + row), at + Vector2(half, -5.0 + row), UPGRADE_COLOR, 1.0)
	else:
		hud.draw_line(at + Vector2(-4, -4), at + Vector2(4, 4), LOCKED_COLOR, 2.0)
		hud.draw_line(at + Vector2(-4, 4), at + Vector2(4, -4), LOCKED_COLOR, 2.0)
