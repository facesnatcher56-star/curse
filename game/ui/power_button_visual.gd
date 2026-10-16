extends RefCounted
## Shared presentation only: both HUD locations read the real power state.

static func armed(hero: Player, id: String) -> bool:
	if hero == null:
		return false
	match id:
		"brutal_attack": return hero.skills != null and hero.skills.brutal_armed
		"staggering_blow": return hero.powers != null and hero.powers.staggering_armed
		"take_aim":
			return (hero.skills != null and hero.skills.take_aim_targeting) or (hero.bow != null and hero.bow.armed)
	return false

static func state(charge: float, is_armed: bool, available: bool = true) -> String:
	if is_armed: return "armed"
	if charge < 0.999: return "charging"
	return "ready" if available else "locked"

static func draw_on(canvas: CanvasItem, rect: Rect2, charge: float, is_armed: bool, available: bool = true, icon_inset: float = 0.10) -> void:
	var status := state(charge, is_armed, available)
	var inset := rect.grow(-rect.size.x * icon_inset)
	if status == "charging" or status == "locked":
		# Reveal the icon upward. No large percentage obscuring the artwork.
		var fill := clampf(charge, 0.0, 1.0) if status == "charging" else 0.0
		var points := PackedVector2Array()
		var cut_y := inset.position.y + inset.size.y * (1.0 - fill)
		for i in 97:
			var angle := -PI + TAU * i / 96.0
			var point := inset.get_center() + Vector2(cos(angle), sin(angle)) * inset.size.x * 0.5
			if point.y <= cut_y: points.append(point)
		if points.size() >= 3: canvas.draw_colored_polygon(points, Color(0, 0, 0, 0.82))
	elif status == "ready":
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		canvas.draw_arc(rect.get_center(), rect.size.x * 0.48, 0, TAU, 48, Color(0.83, 0.62, 0.29, 0.55 + 0.2 * pulse), 1.5, true)
	else:
		# Armed is a persistent double ember rim, not the ready pulse.
		canvas.draw_arc(rect.get_center(), rect.size.x * 0.48, 0, TAU, 48, Color(1.0, 0.69, 0.30), 2.5, true)
		canvas.draw_arc(rect.get_center(), rect.size.x * 0.39, 0, TAU, 48, Color(1.0, 0.85, 0.52, 0.8), 1.0, true)
		var angle := Time.get_ticks_msec() * 0.002
		canvas.draw_arc(rect.get_center(), rect.size.x * 0.48, angle, angle + 0.6, 12, Color(1.0, 0.91, 0.71), 3.0, true)
