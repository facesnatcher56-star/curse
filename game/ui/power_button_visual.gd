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

static func draw_on(canvas: CanvasItem, rect: Rect2, charge: float, is_armed: bool, available: bool = true, icon_inset: float = 0.10, ready_flash: float = 0.0, activation_flash: float = 0.0) -> void:
	var status := state(charge, is_armed, available)
	var centre := rect.get_center()
	var radius: float = rect.size.x * 0.455
	var clamped_charge := clampf(charge, 0.0, 1.0)
	# High contrast, clockwise progress ring with a dark track so the remaining amount is obvious.
	canvas.draw_arc(centre, radius, 0.0, TAU, 64, Color(0.025, 0.018, 0.012, 0.96), 4.5, true)
	for notch in 12:
		var angle := -PI * 0.5 + TAU * float(notch) / 12.0
		var direction := Vector2(cos(angle), sin(angle))
		var notch_color := Color(0.83, 0.64, 0.37, 0.92) if status == "armed" else Color(0.36, 0.27, 0.17, 0.9)
		canvas.draw_line(centre + direction * (radius - 3.5), centre + direction * (radius + 2.5), notch_color, 1.4, true)
	if status == "charging" or status == "locked":
		var ring_color := Color(1.0, 0.59, 0.19, 1.0) if status == "charging" else Color(0.52, 0.46, 0.39, 0.85)
		if clamped_charge > 0.001:
			canvas.draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * clamped_charge, 64, ring_color.darkened(0.20), 6.0, true)
			canvas.draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * clamped_charge, 64, ring_color, 2.5, true)
	elif status == "ready":
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.004)
		canvas.draw_arc(centre, radius, 0.0, TAU, 64, Color(1.0, 0.72, 0.28, 0.9), 4.0 + pulse, true)
		canvas.draw_arc(centre, radius - 4.0, 0.0, TAU, 64, Color(1.0, 0.91, 0.63, 0.48 + pulse * 0.3), 1.5, true)
	else:
		# Armed is persistent; a moving gleam distinguishes it from the full-charge ready state.
		canvas.draw_arc(centre, radius, 0.0, TAU, 64, Color(1.0, 0.49, 0.12, 1.0), 5.0, true)
		canvas.draw_arc(centre, radius - 4.0, 0.0, TAU, 64, Color(1.0, 0.86, 0.48, 0.92), 1.5, true)
		var angle := Time.get_ticks_msec() * 0.002
		canvas.draw_arc(centre, radius, angle, angle + 0.72, 16, Color(1.0, 1.0, 0.86), 3.5, true)
		canvas.draw_arc(centre, radius, angle + PI, angle + PI + 0.72, 16, Color(1.0, 0.72, 0.32, 0.95), 2.5, true)
	# One-shot expanding ring at full charge, followed by a separate activation flash.
	var elapsed := clampf(ready_flash / 0.72, 0.0, 1.0)
	if ready_flash > 0.0:
		var t := 1.0 - elapsed
		canvas.draw_arc(centre, radius * (0.66 + 0.52 * t), 0.0, TAU, 64, Color(1.0, 0.91, 0.57, 0.82 * elapsed), 2.0 + 2.0 * elapsed, true)
		canvas.draw_circle(centre, rect.size.x * 0.24 * elapsed, Color(1.0, 0.76, 0.34, 0.17 * elapsed))
	var active := clampf(activation_flash / 0.62, 0.0, 1.0)
	if activation_flash > 0.0:
		canvas.draw_rect(rect.grow(-1.5), Color(1.0, 0.87, 0.48, 0.28 * active), false, 3.0 + 2.0 * active)
		canvas.draw_arc(centre, radius * (0.82 + 0.22 * (1.0 - active)), 0.0, TAU, 64, Color(1.0, 0.97, 0.75, 0.9 * active), 2.0 + 2.0 * active, true)
