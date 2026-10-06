class_name Chronicle
extends RefCounted
## The record of what has happened, so the player can look back at it (banners vanish): a line per event with the day it happened, kept in
## `TownState.chronicle` and shown by the Chronicle page (key J, and Warden Hale's board). Kinds: "quest", "event", "monster", "town".

const MAX_ENTRIES := 150
const KIND_COLORS := {
	"quest": Color(0.92, 0.84, 0.62),
	"event": Color(0.62, 0.78, 0.9),
	"monster": Color(0.95, 0.5, 0.35),
	"town": Color(0.8, 0.78, 0.74),
}

static func add(kind: String, text: String) -> void:
	TownState.chronicle.append({"day": TownState.day, "kind": kind, "text": text})
	while TownState.chronicle.size() > MAX_ENTRIES:
		TownState.chronicle.pop_front()

## Newest first.
static func recent(count: int = 40) -> Array:
	var out: Array = []
	for i in range(TownState.chronicle.size() - 1, maxi(TownState.chronicle.size() - 1 - count, -1), -1):
		out.append(TownState.chronicle[i])
	return out

static func color_of(kind: String) -> Color:
	return KIND_COLORS.get(kind, Color(0.8, 0.78, 0.74))
