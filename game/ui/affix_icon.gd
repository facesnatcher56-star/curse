class_name AffixIcon
extends RefCounted
## The small drawn icon of a champion affix (Champion.AFFIXES key): chevrons for Swift, a shield for Warded, a skull for Summoning, a burst for
## Volatile. One drawing routine for the target banner's chips and the world marker over the champion.

static func draw(ci: CanvasItem, id: String, c: Vector2, r: float, color: Color, alpha: float = 1.0) -> void:
	ci.draw_circle(c, r + 1.5, Color(0.02, 0.02, 0.03, 0.88 * alpha))
	ci.draw_arc(c, r + 1.0, 0.0, TAU, 20, Color(color, alpha), maxf(1.5, r * 0.16))
	var col := Color(color.lightened(0.25), alpha)
	var w: float = maxf(1.6, r * 0.2)
	match id:
		"fast":
			for dx in [-0.32, 0.18]:
				var x: float = c.x + r * dx
				ci.draw_polyline(PackedVector2Array([Vector2(x - r * 0.25, c.y - r * 0.5), Vector2(x + r * 0.25, c.y), Vector2(x - r * 0.25, c.y + r * 0.5)]), col, w)
		"shielded":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.5, c.y - r * 0.5), Vector2(c.x + r * 0.5, c.y - r * 0.5),
				Vector2(c.x + r * 0.5, c.y + r * 0.05), Vector2(c.x, c.y + r * 0.62), Vector2(c.x - r * 0.5, c.y + r * 0.05)]), col)
		"summoner":
			ci.draw_circle(c + Vector2(0, -r * 0.12), r * 0.46, col)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.24, r * 0.24), Vector2(r * 0.48, r * 0.34)), col)
			ci.draw_circle(c + Vector2(-r * 0.18, -r * 0.14), r * 0.12, Color(0.05, 0.05, 0.05, alpha))
			ci.draw_circle(c + Vector2(r * 0.18, -r * 0.14), r * 0.12, Color(0.05, 0.05, 0.05, alpha))
		"explodes":
			var pts := PackedVector2Array()
			for i in 16:
				var a: float = TAU * float(i) / 16.0
				pts.append(c + Vector2(cos(a), sin(a)) * r * (0.72 if i % 2 == 0 else 0.34))
			ci.draw_colored_polygon(pts, col)
		_:
			ci.draw_circle(c, r * 0.35, col)

## A control that draws one affix icon (the banner's chips).
class Badge extends Control:
	var affix_id: String = ""
	var tint: Color = Color.WHITE
	func _draw() -> void:
		AffixIcon.draw(self, affix_id, size * 0.5, minf(size.x, size.y) * 0.5 - 2.0, tint)
