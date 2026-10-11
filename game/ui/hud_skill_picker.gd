class_name HudSkillPicker
extends RefCounted
## The hotbar's skill picker. Click a hotbar slot (the numbered ones or the right mouse button) and every skill appears above it as an icon;
## click one and it goes on that key. A skill that was on another key trades places with what was here, so nothing is ever lost (see
## HotbarLayout). It draws on the HUD's own canvas, from Hud._draw.

var hud: Hud
var open_slot: int = HotbarLayout.NONE   # the slot it is open for (HotbarLayout.NONE: closed)
var _picker_anchor: Rect2 = Rect2()
const PICKER_CELL := 62.0
const PICKER_GAP := 8.0
const PICKER_PAD := 12.0

func is_open() -> bool:
	return open_slot != HotbarLayout.NONE

func open(slot: int, anchor: Rect2) -> void:
	open_slot = slot
	_picker_anchor = anchor

func close() -> void:
	open_slot = HotbarLayout.NONE

## The slot number a hotbar slot's action stands for: 0.. for skill_1.., HotbarLayout.ALT for the mouse button, NONE for the dodge.
static func slot_of_action(action: String) -> int:
	if action == "alt_skill":
		return HotbarLayout.ALT
	if action.begins_with("skill_"):
		return int(action.substr(6)) - 1
	return HotbarLayout.NONE

## The change-able hotbar slot under a point, as {slot, rect}; {} when there is none.
func slot_at(point: Vector2) -> Dictionary:
	for hit in hud._slot_hits:
		var rect: Rect2 = hit["rect"]
		var slot: int = slot_of_action(String(hit["action"]))
		if slot != HotbarLayout.NONE and rect.has_point(point):
			return {"slot": slot, "rect": rect}
	return {}

func panel_rect(size_px: Vector2) -> Rect2:
	var count: int = HotbarLayout.ASSIGNABLE.size()
	var width: float = PICKER_PAD * 2.0 + PICKER_CELL * count + PICKER_GAP * (count - 1)
	var height: float = PICKER_PAD * 2.0 + PICKER_CELL + 30.0
	var x: float = clampf(_picker_anchor.get_center().x - width * 0.5, 8.0, maxf(size_px.x - width - 8.0, 8.0))
	return Rect2(x, _picker_anchor.position.y - height - 16.0, width, height)

## Every skill's icon cell in the open picker: [{rect, id}].
func cells(size_px: Vector2) -> Array[Dictionary]:
	var panel: Rect2 = panel_rect(size_px)
	var cells: Array[Dictionary] = []
	for i in HotbarLayout.ASSIGNABLE.size():
		cells.append({"rect": Rect2(panel.position + Vector2(PICKER_PAD + i * (PICKER_CELL + PICKER_GAP), PICKER_PAD + 26.0), Vector2.ONE * PICKER_CELL),
			"id": HotbarLayout.ASSIGNABLE[i]})
	return cells

## A left click on a hotbar slot opens the picker; with it open, a click on a skill chooses it, on another slot moves the picker there,
## anywhere else (or the right button) closes it. Returns true when the click was used.
func handle_click(click: InputEventMouseButton) -> bool:
	var size_px: Vector2 = hud.get_viewport_rect().size
	if is_open():
		if click.button_index != MOUSE_BUTTON_LEFT:
			close()
			return true
		for cell in cells(size_px):
			if (cell["rect"] as Rect2).has_point(click.position):
				hud.player.skills.assign_slot(open_slot, String(cell["id"]))
				close()
				return true
		var other: Dictionary = slot_at(click.position)
		if not other.is_empty() and int(other["slot"]) != open_slot:
			open(int(other["slot"]), other["rect"])
		else:
			close()
		return true
	if click.button_index == MOUSE_BUTTON_LEFT:
		var hit: Dictionary = slot_at(click.position)
		if not hit.is_empty():
			open(int(hit["slot"]), hit["rect"])
			return true
	return false

func draw(font: Font, size_px: Vector2) -> void:
	var panel: Rect2 = panel_rect(size_px)
	var mouse: Vector2 = hud.get_viewport().get_mouse_position() if hud.mouse_override.x < 0.0 else hud.mouse_override
	UiTheme.draw_panel(hud, panel, 0.95)
	var here: String = HotbarLayout.skill_at(hud.player.skills.hotbar, hud.player.skills.right_click_skill, open_slot)
	var title: String = "Put on %s" % (GameSettings.short_binding_text("alt_skill") if open_slot == HotbarLayout.ALT else GameSettings.short_binding_text("skill_%d" % (open_slot + 1)))
	var hovered_id: String = ""
	for cell in cells(size_px):
		if (cell["rect"] as Rect2).has_point(mouse):
			hovered_id = String(cell["id"])
	UiTheme.text(hud, font, panel.position + Vector2(PICKER_PAD, 24.0), title, 16, UiTheme.BRONZE_LIGHT.lightened(0.25))
	if hovered_id != "":
		UiTheme.text(hud, font, panel.position + Vector2(panel.size.x - PICKER_PAD, 24.0), String(SkillDb.all()[hovered_id]["name"]), 16, UiTheme.TEXT,
			HORIZONTAL_ALIGNMENT_RIGHT, panel.size.x * 0.6)
	for cell in cells(size_px):
		var rect: Rect2 = cell["rect"]
		var id: String = cell["id"]
		hud.draw_rect(rect, UiTheme.INK)
		var icon: Texture2D = hud._icon(id)
		if icon != null:
			hud.draw_texture_rect(icon, rect.grow(-3.0), false)
		else:
			hud.draw_string(font, rect.position + Vector2(2, PICKER_CELL * 0.5 + 4), String(SkillDb.all()[id]["name"]), HORIZONTAL_ALIGNMENT_CENTER, PICKER_CELL - 4, 11, Color(1, 1, 1))
		var border: Color = Color(0.32, 0.30, 0.26)
		if id == here:
			border = UiTheme.ACCENT
		elif id == hovered_id:
			border = Color(1.0, 0.95, 0.8)
		hud.draw_rect(rect, border, false, 3.0 if id == hovered_id or id == here else 1.5)
		# Which key it is on now, so a swap is no surprise.
		var where: int = HotbarLayout.where(hud.player.skills.hotbar, hud.player.skills.right_click_skill, id)
		var tag: String = ""
		if where == HotbarLayout.ALT:
			tag = GameSettings.short_binding_text("alt_skill")
		elif where != HotbarLayout.NONE:
			tag = GameSettings.short_binding_text("skill_%d" % (where + 1))
		if tag != "":
			UiTheme.text(hud, font, rect.position + Vector2(5, 15), tag, 13, Color(1, 0.95, 0.7))
