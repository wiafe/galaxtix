extends "res://tests/map_editor_smoke.gd"
const Encounters = preload("res://scripts/map_encounters.gd")
var panel

func select_kind(kind: String) -> void:
	panel.encounter_input.select(rogue.Sectors.KINDS.keys().find(kind))
	panel.update_preview()

func launch_map(map: MapDefinition, kind: String, depth := 2) -> void:
	MapCatalog.testing[map.map_id] = map
	rogue.clear_race()
	rogue.active_destination = {"depth": depth, "stage": map.sector, "kind": kind, "boss": map.boss_id}
	rogue.level = depth
	rogue.start_level()
	rogue.phase = "run"
	rogue.state = Game.State.PLAYING
	rogue.freeze_time = 1000

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	rogue.start_run()
	# Preview the same authored geometry and base upgrades used by the playtest.
	for stage in [9, 13, 24, 27, 30, 32]:
		var map := MapCatalog.read(stage).duplicate(true) as MapDefinition
		for kind in (["boss"] if not map.boss_id.is_empty() else ["survey", "salvage", "beacon", "cargo", "breach", "rival", "race"]):
			var preview := Encounters.preview(map, 2, kind)
			launch_map(map, kind)
			assert(rogue.nodes.size() == preview.nodes.size())
			for i in rogue.nodes.size(): assert(rogue.nodes[i].cell == preview.nodes[i].cell, "Preview salvage matches runtime")
			if kind == "beacon":
				for i in rogue.zones.size(): assert(rogue.zones[i].cell == preview.objectives.zones[i].cell)
			if kind == "cargo": assert(rogue.cargo.cell == preview.objectives.pod)
			if kind == "breach": assert(rogue.breach.cell == preview.objectives.breach.cell)
	MapCatalog.testing.clear()
	panel = EditorPanel.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	panel.open_map("roguelite_24")
	assert(panel.canvas.pickup_markers.size() == 3)
	select_kind("salvage")
	assert(panel.canvas.pickup_markers.size() == 5, "Encounter selection updates generated salvage")
	select_kind("survey")
	var before: int = panel.fingerprint(panel.canvas.map)
	panel.canvas.tool = "salvage"
	canvas_click(panel.canvas, Vector2i(60, 40), true)
	canvas_click(panel.canvas, Vector2i(60, 40), false)
	assert(panel.canvas.map.override_pickups and panel.canvas.map.pickups.size() == 4)
	panel.x_input.value = 64
	assert(panel.canvas.map.pickups.back().cell == Vector2i(64, 40))
	panel.remove_enemy()
	assert(panel.canvas.map.pickups.size() == 3)
	panel.undo()
	assert(panel.canvas.map.pickups.size() == 4)
	panel.undo()
	panel.undo()
	assert(panel.fingerprint(panel.canvas.map) == before, "Undo restores automatic salvage")
	# Edit per-encounter settings and markers without changing other encounters.
	select_kind("rival")
	panel.seconds_input.value = 30
	panel.canvas.selected = -1000
	panel.move_marker(0) # Inspector movement is tested separately below.
	panel.undo()
	select_kind("cargo")
	panel.runs_input.value = 4
	select_kind("beacon")
	panel.canvas.tool = "objective"
	canvas_click(panel.canvas, Vector2i(80, 52), true)
	canvas_click(panel.canvas, Vector2i(80, 52), false)
	assert(panel.canvas.objective_markers.size() == 3)
	panel.radius_input.value = 3
	assert(panel.canvas.map.encounters.beacon.objectives.back().radius == 3)
	select_kind("survey")
	panel.goal_input.value = 90
	select_kind("race")
	panel.goal_input.value = 40
	var map: MapDefinition = panel.canvas.map
	map.override_pickups = true
	map.pickups.assign([{"cell": Vector2i(60, 40)}, {"cell": Vector2i(64, 44)}])
	map.encounters.beacon.objectives = [{"cell": Vector2i(80, 52), "radius": 3}]
	assert(map.problems().is_empty(), str(map.problems()))
	var path := "res://.godot/map-content-roundtrip.tres"
	assert(ResourceSaver.save(map, path) == OK)
	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapDefinition
	assert(panel.fingerprint(saved) == panel.fingerprint(map))
	launch_map(saved, "survey")
	assert(rogue.nodes.size() == 2 and rogue.capture_target() == 0.90)
	assert(rogue.objective_label() == "CAPTURE 90%")
	rogue.sparxes.clear()
	rogue.turrets.clear()
	rogue.drafts_taken = rogue.draft_capture.size()
	rogue.earned_salvage = 0
	for q in rogue.qixes:
		q.c = rogue.center(Vector2i(103, 60))
		q.len = 1
	rogue.p = Vector2i(80, 25)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for i in 53: assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.nodes.all(func(node): return node.captured) and rogue.earned_salvage == 2, "Placed salvage pays on a real capture")
	launch_map(saved, "rival")
	assert(rogue.rival_remaining == 30 and rogue.objective_instruction().contains("30 SECONDS"))
	launch_map(saved, "cargo")
	assert(rogue.cargo.runs == 4)
	launch_map(saved, "beacon")
	assert(rogue.zones.size() == 1 and rogue.zones[0].cell == Vector2i(80, 52) and rogue.zones[0].radius == 3)
	launch_map(saved, "race")
	assert(rogue.encounter_goal() == 40 and rogue.race_opponent.encounter_goal() == 40)
	var invalid := saved.duplicate(true) as MapDefinition
	invalid.pickups[0].cell = Vector2i.ZERO
	assert(not invalid.problems().is_empty())
	MapCatalog.testing.clear()
	select_kind("beacon")
	panel.canvas.rebuild()
	main.hide()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			var directory := arg.substr(14)
			DirAccess.make_dir_recursive_absolute(directory)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(directory.path_join("map-content-editor.png"))
	panel.queue_free()
	print("MAP CONTENT PASS: preview parity, salvage placement/move/delete/undo, settings, objective markers, serialization, live awards and encounter rules")
	get_tree().quit()
