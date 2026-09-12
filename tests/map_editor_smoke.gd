extends "res://tests/roguelite_ships_smoke.gd"
const EditorPanel = preload("res://addons/roguelite_maps/map_panel.gd")

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			shot_dir = arg.substr(14)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	rogue.sector_limit = 8
	for entry in MapCatalog.entries():
		if entry.sector >= 9: continue # Authored act terrain is checked by the acts suite.
		var map := load(MapCatalog.default_path(entry.id)) as MapDefinition # Stable fixture, independent of the player's edits.
		assert(map != null and map.problems().is_empty())
		var expected := SectorArena.build(entry.sector, 0, "roguelite", rogue.Sectors.holes(entry.sector, map.grid_size), map.grid_size)
		assert(map.arena().mask == expected.mask and map.arena().base_free == expected.base_free, "Every editor terrain matches the built-in arena")
		var draft := map.duplicate(true) as MapDefinition
		draft.override_terrain = true
		draft.override_start = true
		draft.override_enemies = true
		assert(draft.problems().is_empty(), "%s: %s" % [entry.id, draft.problems()])
		MapCatalog.testing[entry.id] = draft
		for kind in rogue.Sectors.KINDS:
			if kind in ["race", "boss"]: continue # These transform arenas; their dedicated suites cover spawning.
			rogue.start_run()
			rogue.active_destination = {"depth": 5, "stage": entry.sector, "kind": kind}
			rogue.level = 5
			rogue.start_level()
			assert(rogue.p == draft.player_start and rogue.field_arena.mask == draft.arena().mask)
			assert(rogue.sparx_to_spawn == 0)
			var anomalies := 0
			var turrets := 0
			var sparx := 0
			for enemy in draft.enemies:
				match enemy.kind:
					"anomaly":
						assert(rogue.to_cell(rogue.qixes[anomalies].c) == enemy.cell, "%s %s anomaly %s expected %s" % [entry.id, kind, rogue.to_cell(rogue.qixes[anomalies].c), enemy.cell])
						anomalies += 1
					"turret":
						assert(rogue.turrets[turrets].cell == enemy.cell)
						turrets += 1
					"sparx":
						assert(rogue.sparxes[sparx].c == enemy.cell)
						sparx += 1
			assert(rogue.qixes.size() == anomalies and rogue.turrets.size() == turrets and rogue.sparxes.size() == sparx)
			for node in rogue.nodes: assert(rogue.cells[rogue.idx(node.cell.x, node.cell.y)] == Game.FREE)
			if kind == "cargo": assert(not rogue.cargo.is_empty())
			if kind == "beacon": assert(not rogue.zones.is_empty())
			if kind == "breach": assert(not rogue.breach.is_empty())
		MapCatalog.testing.clear()
	var panel = EditorPanel.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	assert(panel.current_id == "roguelite_09" and panel.act_picker.get_selected_id() == 1)
	for act in range(1, 4):
		panel.act_picker.select(panel.act_picker.get_item_index(act))
		panel.act_picker.item_selected.emit(panel.act_picker.selected)
		assert(panel.visible_maps.size() == 9 and panel.picker.item_count == 9)
		for entry in panel.visible_maps: assert(panel.map_act(entry.id) == act)
		panel.picker.item_selected.emit(7)
		assert(panel.current_id == "roguelite_%02d" % (8 + act * 5))
		assert(panel.picker.get_item_text(7).contains("[Boss]"))
		assert(panel.depth_input.value == act * 8, "Boss playtest uses the act's final depth")
		panel.select_act(0)
		assert(panel.picker.item_count == 8)
		panel.select_act(act)
		assert(panel.current_id == "roguelite_%02d" % (8 + act * 5), "Returning to an act remembers its selected map")
	for stage in [13, 18, 23, 33, 34, 35]:
		panel.open_map("roguelite_%02d" % stage)
		assert(panel.canvas.map.enemies.filter(func(e): return e.kind == "boss_relay").size() == 3)
		assert(panel.encounter_input.get_item_text(panel.encounter_input.selected).to_lower() == "boss")
		var boss_fingerprint: int = panel.fingerprint(panel.canvas.map)
		panel.begin_change()
		panel.canvas.map.enemies = panel.canvas.map.enemies.filter(func(e): return e.kind != "boss_relay")
		panel.finish_change()
		assert(panel.save_button.disabled and panel.play_button.disabled)
		var act: int = panel.map_act(panel.current_id)
		panel.select_act(0)
		assert(panel.act_picker.get_item_text(panel.act_picker.get_item_index(act)).ends_with("*"))
		panel.select_act(act)
		assert(panel.save_button.disabled, "Unsaved edits and validation survive act switching")
		panel.undo()
		assert(panel.fingerprint(panel.canvas.map) == boss_fingerprint and not panel.save_button.disabled)
		var boss_path := "res://.godot/boss-roundtrip.tres"
		assert(ResourceSaver.save(panel.canvas.map, boss_path) == OK)
		var boss_map := ResourceLoader.load(boss_path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapDefinition
		assert(panel.fingerprint(boss_map) == boss_fingerprint)
	panel.open_map("roguelite_01")
	var original: int = panel.fingerprint(panel.canvas.map)
	var cell := Vector2i(80, 50)
	var index := cell.y * 160 + cell.x
	panel.begin_change()
	panel.canvas.tool = "rock"
	panel.canvas.apply_at(cell)
	panel.finish_change()
	assert(panel.canvas.map.rock[index] == 1 and panel.canvas.map.override_terrain)
	panel.undo()
	assert(panel.fingerprint(panel.canvas.map) == original, "Undo restores terrain and automatic placement flags")
	panel.redo()
	assert(panel.canvas.map.rock[index] == 1)
	panel.open_map("roguelite_02")
	panel.open_map("roguelite_01")
	assert(panel.canvas.map.rock[index] == 1, "Switching maps keeps unsaved drafts")
	# Round trip through the same ResourceSaver/Loader format without editing shipped maps.
	var path := "res://.godot/map-roundtrip.tres"
	assert(ResourceSaver.save(panel.canvas.map, path) == OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapDefinition
	assert(panel.fingerprint(loaded) == panel.fingerprint(panel.canvas.map))
	MapCatalog.testing["roguelite_01"] = loaded
	rogue.start_run()
	rogue.transit_skip = true
	rogue.launch_destination(0)
	assert(rogue.cells[index] == Game.ROCK, "A serialized brush edit reaches the actual simulation")
	assert(rogue.field_arena.mask[(cell.y - 1) * 160 + cell.x] == 1, "Painting rock builds an inner safe rail")
	# A custom shape need not intersect the old centre-column start position.
	var off_center := loaded.duplicate(true) as MapDefinition
	off_center.rock.fill(1)
	for y in range(25, 65):
		for x in range(10, 40): off_center.rock[y * 160 + x] = 0
	off_center.invalidate()
	MapCatalog.testing["roguelite_01"] = off_center
	rogue.start_level()
	assert(rogue.border[rogue.idx(rogue.p.x, rogue.p.y)] == 1, "Automatic player start follows an off-centre painted arena")
	MapCatalog.testing.clear()
	panel.restore_default()
	panel.canvas.map.override_enemies = true
	panel.canvas.map.enemies.clear()
	panel.refresh()
	assert(panel.save_button.disabled and panel.play_button.disabled, "Invalid enemy setups cannot be saved or playtested")
	panel.restore_default()
	# Use actual canvas mouse events for placement, drag and deletion.
	panel.canvas.tool = "enemy"
	panel.canvas.enemy_kind = "turret"
	var old_count: int = panel.canvas.map.enemies.size()
	canvas_click(panel.canvas, Vector2i(75, 50), true)
	canvas_click(panel.canvas, Vector2i(75, 50), false)
	assert(panel.canvas.map.enemies.size() == old_count + 1 and panel.canvas.map.override_enemies)
	panel.canvas.tool = "select"
	canvas_click(panel.canvas, Vector2i(75, 50), true)
	var motion := InputEventMouseMotion.new()
	motion.position = panel.canvas.screen_cell(Vector2i(72, 48))
	panel.canvas._gui_input(motion)
	canvas_click(panel.canvas, Vector2i(72, 48), false)
	assert(panel.canvas.map.enemies.back().cell == Vector2i(72, 48))
	panel.change_axis(1)
	assert(panel.canvas.map.enemies.back().axis == Vector2i.RIGHT)
	canvas_click(panel.canvas, Vector2i(72, 48), true, MOUSE_BUTTON_RIGHT)
	canvas_click(panel.canvas, Vector2i(72, 48), false, MOUSE_BUTTON_RIGHT)
	assert(panel.canvas.map.enemies.size() == old_count)
	panel.undo()
	assert(panel.canvas.map.enemies.back().cell == Vector2i(72, 48), "Deleting a moved enemy is undoable")
	# Exercise the Save button's path without touching any of the eight real maps.
	var temporary_id := "smoke_editor_roundtrip"
	var temporary_path := MapCatalog.path_for(temporary_id)
	assert(not FileAccess.file_exists(temporary_path))
	panel.drafts[temporary_id] = panel.canvas.map.duplicate(true)
	panel.dirty[temporary_id] = true
	assert(panel.save_map(temporary_id))
	var saved_map := ResourceLoader.load(temporary_path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapDefinition
	assert(saved_map.enemies.back().cell == Vector2i(72, 48) and saved_map.enemies.back().axis == Vector2i.RIGHT)
	assert(DirAccess.remove_absolute(temporary_path) == OK)
	panel.restore_default()
	main.hide()
	panel.select_act(2)
	if not shot_dir.is_empty():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_dir.path_join("maps-editor.png"))
		panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		panel.size = Vector2(1080, 600)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_dir.path_join("maps-editor-compact.png"))
	panel.queue_free()
	print("MAP EDITOR PASS: all eight layouts, all six encounters, authored spawns, terrain round trip, inner rails, undo/redo, draft switching, validation")
	get_tree().quit()

func canvas_click(canvas: Control, cell: Vector2i, pressed: bool, button_index := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = canvas.screen_cell(cell)
	event.button_index = button_index
	event.pressed = pressed
	canvas._gui_input(event)
