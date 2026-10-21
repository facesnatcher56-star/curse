extends DevSuite
## Party readability (issue #99): one colour per member shared by the ground ring, the outline pass and the bars; enemies get none of it.
## Optional 1080p capture of a crowded fight: set PARTYLOOK_SHOT to a png path.

func _settle() -> void:
	for i in 4: await get_tree().process_frame

func _test_party_look() -> void:
	expect("warrior gold and Cutter teal, one place", PartyLook.color_of("hero") == PartyLook.GOLD and PartyLook.color_of("cutter") == PartyLook.TEAL
		and PartyLook.GOLD != PartyLook.TEAL)
	expect("class icons: sword for the warrior, bow for the Cutter", PartyLook.class_icon("hero") == "sword" and PartyLook.class_icon("cutter") == "bow")
	expect("party health is green, its damage numbers orange, and neither is the enemy red", PartyLook.HEALTH_GREEN.g > PartyLook.HEALTH_GREEN.r
		and PartyLook.DAMAGE_TAKEN.r > PartyLook.DAMAGE_TAKEN.b and player._popup_tint() == PartyLook.DAMAGE_TAKEN)
	var ring := player.get_node_or_null("PartyRing") as MeshInstance3D
	expect("the hero has a ground ring in his colour, lying just above the floor",
		ring != null and (ring.material_override as ShaderMaterial).get_shader_parameter("tint") == PartyLook.GOLD and ring.position.y > 0.0 and ring.position.y < 0.3)
	expect("his outline pass is the party's, in his colour", player._base_overlay() == PartyLook.xray_material("hero")
		and (player.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_overlay == PartyLook.xray_material("hero"))
	var cutter := player.stats._cutter()
	if cutter != null:
		var cutter_ring := cutter.get_node_or_null("PartyRing") as MeshInstance3D
		expect("the Cutter's ring and outline are teal", cutter_ring != null
			and (cutter_ring.material_override as ShaderMaterial).get_shader_parameter("tint") == PartyLook.TEAL
			and (cutter._base_overlay() as ShaderMaterial).get_shader_parameter("tint") == PartyLook.TEAL)
	var enemy := _spawn_enemy(Vector3(4, 0, 4))
	await _settle()
	expect("an enemy has no ring and no outline pass", enemy.get_node_or_null("PartyRing") == null and enemy._base_overlay() == null)
	player.dead = true
	player._process(0.0)
	expect("the ring is hidden while the member is dead", not ring.visible)
	player.dead = false
	player._process(0.0)
	expect("and back when alive", ring.visible)
	var shot: String = OS.get_environment("PARTYLOOK_SHOT")
	if shot != "" and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
