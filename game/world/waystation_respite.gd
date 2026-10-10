class_name WaystationRespite
extends Node3D
## Field respite / rest point at the Hearthward Waystation on Crypt Road.
## Located inside the ruined east tollhouse (x = 11.0, z = 124.2).
##
## Mechanics:
##   - Single use per road visit / expedition.
##   - Restores partial HP (+35) and partial Mana (+25) when out of combat.
##   - Does not refill potions, charge ultimates, or trivialize road attrition.
##   - Blocked while in combat (player combat timer active or nearby enemies alert).
##   - Guarded against accidental consumption when already at full strength.
##   - Supports rebound keyboard/controller interaction with screen-space prompt.
##   - Tangible feedback: rest animation, floating numbers, ember burst, light flare, rumble, compact HUD feedback.

signal rested(hp_gained: float, mana_gained: float)

const MODEL_PATH := "res://assets/models/brazier/model.glb"
const HEAL_AMOUNT := 35.0
const MANA_AMOUNT := 25.0
const INTERACT_RADIUS := 2.8
const DISCOVERY_RADIUS := 8.5
const REST_COOLDOWN := 1.2

var is_used: bool = false
var _resting: bool = false
var _player_ref: Player = null
var _road_ref: CryptRoad = null
## Session-only respite state follows authoritative expedition/day, surviving road recreation.
static var _visit_state: Dictionary = {}

var _model: Node3D = null
var _light: OmniLight3D = null
var _feedback: Label = null
var _feedback_serial: int = 0
var _tag: Label = null
var _particles: CPUParticles3D = null

func _ready() -> void:
	_setup_visuals()
	_setup_prompt_tag()
	_setup_particles()
	if is_used:
		_cool_embers()
	_update_prompt()

func setup(road: CryptRoad, existing_brazier: Node3D = null) -> void:
	_road_ref = road
	_track_road_visit()
	if existing_brazier != null and _model == null:
		# If an existing brazier model was placed by CryptRoad._prop, we can adopt or align with it
		_model = existing_brazier

func _setup_visuals() -> void:
	# Light: warm hearth ember glow
	if _light == null:
		_light = OmniLight3D.new()
		_light.name = "HearthLight"
		_light.light_color = Color(1.0, 0.55, 0.2)
		_light.light_energy = 2.0
		_light.omni_range = 7.5
		_light.position = Vector3(0.0, 1.3, 0.0)
		add_child(_light)
		var flicker := FlickerLight.new()
		_light.add_child(flicker)

func _setup_prompt_tag() -> void:
	if _tag != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_tag = Label.new()
	_tag.name = "RespitePrompt"
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.add_theme_font_size_override("font_size", 24)
	_tag.add_theme_constant_override("outline_size", 4)
	_tag.add_theme_color_override("font_outline_color", Color(0.04, 0.04, 0.05))
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.035, 0.03, 0.025, 0.94)
	plate.content_margin_left = 14
	plate.content_margin_right = 14
	plate.content_margin_top = 7
	plate.content_margin_bottom = 7
	_tag.add_theme_stylebox_override("normal", plate)
	_tag.visible = false
	layer.add_child(_tag)

func _setup_particles() -> void:
	if _particles != null:
		return
	_particles = CPUParticles3D.new()
	_particles.name = "EmberParticles"
	_particles.amount = 8
	_particles.lifetime = 1.2
	_particles.preprocess = 0.5
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = 0.35
	_particles.direction = Vector3.UP
	_particles.spread = 25.0
	_particles.initial_velocity_min = 0.4
	_particles.initial_velocity_max = 1.1
	_particles.gravity = Vector3(0.0, 0.6, 0.0)
	_particles.position = Vector3(0.0, 1.1, 0.0)

	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.65, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	_particles.mesh = mesh

	add_child(_particles)

func _physics_process(_delta: float) -> void:
	_track_road_visit()
	_find_player()
	_update_prompt()

func _unhandled_input(event: InputEvent) -> void:
	if _resting:
		return
	if event.is_action_pressed("interact"):
		if _player_ref != null and _player_ref.global_position.distance_to(global_position) <= INTERACT_RADIUS:
			attempt_rest(_player_ref)
			return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		if _player_ref != null and _player_ref.global_position.distance_to(global_position) <= INTERACT_RADIUS:
			var cam := get_viewport().get_camera_3d()
			if cam != null:
				var from := cam.project_ray_origin(click.position)
				var dir := cam.project_ray_normal(click.position)
				var to_hearth := global_position - from
				var proj := to_hearth.dot(dir)
				if proj > 0.0:
					var nearest := from + dir * proj
					if nearest.distance_to(global_position + Vector3(0.0, 0.7, 0.0)) <= 1.4:
						attempt_rest(_player_ref)

func _find_player() -> void:
	if _player_ref != null and is_instance_valid(_player_ref) and not _player_ref.is_queued_for_deletion():
		return
	var nodes := get_tree().get_nodes_in_group("player")
	if not nodes.is_empty():
		_player_ref = nodes[0] as Player

func _track_road_visit() -> void:
	if _road_ref == null:
		return
	var state: Dictionary = _visit_state
	if state.is_empty():
		state = {"used": false, "expedition": TownState.expedition, "day": TownState.day}
	elif int(state.day) != TownState.day or (TownState.expedition and not bool(state.expedition)):
		state.used = false
	state.expedition = TownState.expedition
	state.day = TownState.day
	_visit_state = state
	var was_used := is_used
	is_used = bool(state.used)
	if was_used and not is_used:
		reset_visit()

## Explicit regrow reset, including zero-progress road refreshes.
static func reset_road(road: CryptRoad) -> void:
	_visit_state = {"used": false, "expedition": TownState.expedition, "day": TownState.day}
	var respite := get_from_road(road)
	if respite != null:
		respite.reset_visit()

func _update_prompt() -> void:
	if _tag == null:
		return
	if _player_ref == null or not is_instance_valid(_player_ref):
		_tag.visible = false
		return

	var dist: float = _player_ref.global_position.distance_to(global_position)
	if dist <= INTERACT_RADIUS:
		if is_used:
			_tag.text = "Hearthward Waystation\n(Embers cold — rested this visit)"
			_tag.modulate = Color(0.62, 0.62, 0.68)
		else:
			var check := can_rest(_player_ref)
			if not check.allowed and check.reason == "in_combat":
				_tag.text = "Hearthward Waystation\n[Threatened — cannot rest in combat]"
				_tag.modulate = Color(0.92, 0.38, 0.32)
			elif not check.allowed and check.reason == "already_full":
				_tag.text = "Hearthward Waystation\n(Already at full strength)"
				_tag.modulate = Color(0.75, 0.85, 0.75)
			else:
				var binding: String = GameSettings.pad_binding_text("interact") if Gamepad.active else GameSettings.binding_text("interact")
				var button_str: String = "[%s]" % binding
				_tag.text = "Hearthward Waystation\n%s Rest at Hearth (+35 HP, +25 MP)" % button_str
				_tag.modulate = Color(0.98, 0.86, 0.45)
		_tag.visible = true
	elif dist <= DISCOVERY_RADIUS:
		if is_used:
			_tag.text = "Hearthward Waystation\n(Spent Hearth)"
			_tag.modulate = Color(0.55, 0.55, 0.6, 0.7)
		else:
			_tag.text = "Hearthward Waystation\nWarm Embers"
			_tag.modulate = Color(0.92, 0.78, 0.45, 0.85)
		_tag.visible = true
	else:
		_tag.visible = false

	# Native font size is independent of gameplay camera zoom.
	var viewport_size := get_viewport().get_visible_rect().size
	_tag.size = _tag.get_minimum_size()
	_tag.position = Vector2((viewport_size.x - _tag.size.x) * 0.5, 90.0)

func can_rest(p: Player) -> Dictionary:
	_track_road_visit()
	if is_used:
		return {"allowed": false, "reason": "already_used", "message": "The embers are cold. You have already rested here this visit."}
	if p == null or p.dead:
		return {"allowed": false, "reason": "dead", "message": ""}
	if is_in_combat(p):
		return {"allowed": false, "reason": "in_combat", "message": "Cannot rest while threatened by enemies."}
	var missing_hp: float = p.max_health - p.health
	var missing_mp: float = (p.stats.max_mana - p.stats.mana) if p.stats != null else 0.0
	if missing_hp <= 0.01 and missing_mp <= 0.01:
		return {"allowed": false, "reason": "already_full", "message": "You are already at full strength."}
	return {"allowed": true, "reason": "ok", "message": ""}

func is_in_combat(p: Player) -> bool:
	if p == null or p.dead:
		return false
	if p.combat_timer > 0.0:
		return true
	if p.attack_target != null and is_instance_valid(p.attack_target) and not p.attack_target.dead:
		return true
	# Check for living, alert enemies within 22m of either player or hearth
	var tree := get_tree()
	if tree != null:
		var enemies := tree.get_nodes_in_group("enemies")
		for node in enemies:
			var e := node as Enemy
			if is_instance_valid(e) and not e.dead:
				var dist: float = minf(e.global_position.distance_to(p.global_position), e.global_position.distance_to(global_position))
				if dist <= 22.0 and (e.is_aggro() or e._aggro):
					return true
	return false

func attempt_rest(p: Player) -> bool:
	if _resting:
		return false
	var check := can_rest(p)
	if not check.allowed:
		if p != null and not String(check.message).is_empty():
			p._say(check.message)
			_show_feedback(check.message, 2.0)
		return false

	_resting = true
	is_used = true
	if _road_ref != null:
		var state: Dictionary = _visit_state
		state.used = true
		_visit_state = state

	var prev_hp: float = p.health
	var prev_mp: float = p.stats.mana if p.stats != null else 0.0

	# Modest partial restoration capped at max
	p.health = minf(p.health + HEAL_AMOUNT, p.max_health)
	var healed_hp: float = p.health - prev_hp
	var restored_mp: float = 0.0
	if p.stats != null:
		p.stats.mana = minf(p.stats.mana + MANA_AMOUNT, p.stats.max_mana)
		restored_mp = p.stats.mana - prev_mp

	# Rest animation on hero
	p.face(global_position, 0.25)
	if p.model != null:
		p.model.once("idle_rest", 0.0, 1.0, 0.2)

	# Tangible feedback: floating text
	var heal_text: String = "+%d HP" % int(round(healed_hp))
	if restored_mp > 0.5:
		heal_text += "  +%d MP" % int(round(restored_mp))
	Fx.text_at(p, p.global_position + Vector3(0.0, 2.4, 0.0), heal_text, Color(0.4, 1.0, 0.5), 52)

	# Ember VFX and light pulse
	Fx.burst(self, global_position + Vector3(0.0, 1.2, 0.0), Vector3.UP, Color(1.0, 0.72, 0.35), 18, 3.2, 0.03, true)
	Fx.ring(self, global_position + Vector3(0.0, 0.1, 0.0), 2.5, Color(1.0, 0.65, 0.2))
	Gamepad.rumble(0.2, 0.35, 0.25)

	# Use the town message feed, keeping the interaction plate and minimap clear.
	var banner_msg := "Hearthward Respite: Rested by the tollhouse embers (+%d HP, +%d MP)" % [int(round(healed_hp)), int(round(restored_mp))]
	_show_feedback(banner_msg, 3.0)

	_cool_embers()
	rested.emit(healed_hp, restored_mp)

	var tree := get_tree()
	if tree != null:
		var timer := tree.create_timer(REST_COOLDOWN)
		timer.timeout.connect(func() -> void: _resting = false)
	else:
		_resting = false
	return true

func _cool_embers() -> void:
	if _light != null:
		var tween := create_tween()
		tween.tween_property(_light, "light_energy", 0.8, 1.0)
		tween.parallel().tween_property(_light, "light_color", Color(0.82, 0.35, 0.18), 1.0)
	if _particles != null:
		_particles.amount = 4
	_update_prompt()

func reset_visit() -> void:
	if _road_ref != null:
		_visit_state = {"used": false, "expedition": TownState.expedition, "day": TownState.day}
	is_used = false
	_resting = false
	if _light != null:
		_light.light_energy = 2.0
		_light.light_color = Color(1.0, 0.55, 0.2)
	if _particles != null:
		_particles.amount = 8
	_update_prompt()

func _show_feedback(text: String, seconds: float) -> void:
	# TownHud is not in the combat HUD group. Resolve the owning scene's feed
	# explicitly instead of selecting an arbitrary group member's large banner.
	var owner_node: Node = get_parent()
	while owner_node != null:
		if owner_node is TownScene:
			var town_hud: TownHud = (owner_node as TownScene).hud
			if is_instance_valid(town_hud):
				town_hud.show_banner(text, seconds)
				return
		owner_node = owner_node.get_parent()
	# Standalone road/test scenes have no TownHud: a bounded, wrapped plate
	# below the interaction prompt provides the same feedback without a full HUD.
	if _tag == null:
		return
	if _feedback == null:
		_feedback = Label.new()
		_feedback.name = "RespiteFeedback"
		_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_feedback.add_theme_font_size_override("font_size", 18)
		_feedback.add_theme_color_override("font_color", Color(0.96, 0.88, 0.7))
		_feedback.add_theme_stylebox_override("normal", _tag.get_theme_stylebox("normal"))
		_tag.get_parent().add_child(_feedback)
	var width := minf(520.0, get_viewport().get_visible_rect().size.x - 28.0)
	_feedback.size = Vector2(width, 0.0)
	_feedback.text = text
	_feedback.size.y = _feedback.get_minimum_size().y
	_feedback.position = Vector2((get_viewport().get_visible_rect().size.x - width) * 0.5, 180.0)
	_feedback.visible = true
	_feedback_serial += 1
	var serial := _feedback_serial
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if serial == _feedback_serial and is_instance_valid(_feedback):
			_feedback.visible = false)

static func get_from_road(road: Node) -> WaystationRespite:
	if road == null:
		return null
	for child in road.get_children():
		if child is WaystationRespite and not child.is_queued_for_deletion():
			return child as WaystationRespite
	return null
