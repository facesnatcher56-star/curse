extends SceneTree
## Lane P pacing probe: a visible 1080p run through the dungeon with live AI. The hero (invulnerable, probe only) fights whatever is within
## ENGAGE metres and otherwise walks the critical path. Reports the time from spawn to the first hit, the walking time with no living
## enemy in view, the frame rate over the run and in the busiest spot, and saves a screenshot of that spot. Run on screen 1:
##   godot --path . -s res://game/dev/pack_pacing_probe.gd -- --dungeon --atmosphere [--out=C:/dir] [--limit=420]

const ENGAGE := 9.0
const VIEW := TestDungeon.PACK_VIEW_RANGE
## The Crypt Road run (-- --crypt): down the road centre, local (x, z) points.
const ROAD_ROUTE: Array[Vector2] = [Vector2(1, 166), Vector2(0, 120), Vector2(0, 70), Vector2(0, 20), Vector2(0, -30), Vector2(0, -80), Vector2(0, -130)]
var ROUTE: Array[Vector2] = TestDungeon.CRITICAL_PATH

var _main: Node
var _frames := 0
var _t := 0.0
var _leg := 1
var _started := false
var _first_hit := -1.0
var _no_pack_run := 0.0
var _no_pack_worst := 0.0
var _fps_min := 9999.0
var _fps_samples: Array[float] = []
var _busiest := 0
var _busiest_fps := 0.0
var _out := ""
var _limit := 420.0
var _next_log := 0.0
var _shot_taken := false
var _last_health: Dictionary = {}   # enemy -> its health last frame, so only real damage counts as a hit


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--limit="):
			_limit = float(arg.substr(8))
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main


func _process(delta: float) -> bool:
	_frames += 1
	if _frames == 60:   # the game applies its own display settings while it boots, so the window is set after that
		root.mode = Window.MODE_WINDOWED
		root.borderless = true
		var screen: int = 1 if DisplayServer.get_screen_count() > 1 else 0
		root.current_screen = screen
		root.size = Vector2i(1920, 1080)
		root.position = DisplayServer.screen_get_position(screen)
	var hero: Player = _main.player
	if _frames < 240 or hero == null or _main.location == null:
		return false
	if not _started:
		_started = true
		if not (_main.location is TestDungeon):
			ROUTE = []
			for p in ROAD_ROUTE:
				var w: Vector3 = _main.location.at(p.x, p.y)
				ROUTE.append(Vector2(w.x, w.z))
		print("PROBE start %s enemies=%d window=%s screen=%d" % [hero.global_position, get_nodes_in_group("enemies").size(), root.size, root.current_screen])
	_t += delta
	hero.health = hero.max_health
	var here := Vector2(hero.global_position.x, hero.global_position.z)
	var near: Enemy = null
	var near_d: float = INF
	var in_view := false
	var awake := 0
	var around := 0
	for node in get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead:
			continue
		var d: float = e.global_position.distance_to(hero.global_position)
		if d < near_d:
			near_d = d
			near = e
		in_view = in_view or d <= VIEW
		around += 1 if d <= 22.0 else 0
		awake += 1 if e._aggro else 0
		var before: float = float(_last_health.get(e, e.health))
		_last_health[e] = e.health
		if _first_hit < 0.0 and e.health < before - 0.001:
			_first_hit = _t
			print("PROBE first hit at t=%.1f s (hero at %s)" % [_t, hero.global_position])
	if near != null and near_d <= ENGAGE:
		hero.attack_target = near
	else:
		hero.attack_target = null
		if _leg < ROUTE.size():
			var goal := Vector3(ROUTE[_leg].x, 0.0, ROUTE[_leg].y)
			hero.movement.goal = goal
			hero.movement.has_goal = true
			if here.distance_to(ROUTE[_leg]) < 3.0:
				_leg += 1
	if not in_view:
		_no_pack_run += delta
		_no_pack_worst = maxf(_no_pack_worst, _no_pack_run)
	else:
		_no_pack_run = 0.0
	var fps: float = Engine.get_frames_per_second()
	if _t > 1.0:
		_fps_min = minf(_fps_min, fps)
		_fps_samples.append(fps)
	if around > _busiest or (around == _busiest and fps < _busiest_fps):
		_busiest = around
		_busiest_fps = fps
	if around >= 12 and not _shot_taken and _t > 3.0 and _out != "":
		_shot_taken = true
		root.get_texture().get_image().save_png(_out + "/pack_probe_busy.png")
		print("PROBE screenshot at t=%.1f with %d enemies within 22 m, fps %.0f" % [_t, around, fps])
	if _t >= _next_log:
		_next_log += 5.0
		print("PROBE t=%.0f pos=(%.0f,%.0f) leg=%d living=%d awake=%d within22=%d fps=%.0f" % [_t, here.x, here.y, _leg,
			get_nodes_in_group("enemies").size(), awake, around, fps])
	var finished: bool = _leg >= ROUTE.size() and near_d > ENGAGE
	if finished or _t >= _limit:
		var sum := 0.0
		for f in _fps_samples:
			sum += f
		print("PROBE DONE finished=%s t=%.0f s first_hit=%.1f s no_pack_in_view_worst=%.1f s fps_avg=%.0f fps_min=%.0f busiest=%d within 22 m (fps %.0f)" % [
			finished, _t, _first_hit, _no_pack_worst, sum / maxf(_fps_samples.size(), 1.0), _fps_min, _busiest, _busiest_fps])
		quit(0)
		return true
	return false
