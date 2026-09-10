extends "res://tests/roguelite_ships_smoke.gd"
const EditorPanel = preload("res://addons/roguelite_maps/map_panel.gd")

func fixture(ship_id := "surveyor") -> void:
	fresh_ship(ship_id)
	var map := load(MapCatalog.default_path("roguelite_01")).duplicate(true) as MapDefinition
	map.override_enemies = true
	map.enemies.assign([{"kind": "siege", "cell": Vector2i(92, 57)}, {"kind": "sniper", "cell": Vector2i(80, 50)}])
	map.field_zones.resize(160 * 104)
	for y in range(26, 32):
		for x in range(77, 84): map.field_zones[y * 160 + x] = 1
	for y in range(43, 49):
		for x in range(60, 69): map.field_zones[y * 160 + x] = 2
	assert(map.problems().is_empty())
	MapCatalog.testing[map.map_id] = map
	rogue.start_level()
	MapCatalog.testing.clear()
	rogue.phase = "run"
	rogue.state = Game.State.PLAYING
	rogue.freeze_time = 0
	rogue.invuln = 0
	rogue.nodes.clear()
	rogue.drafts_taken = rogue.draft_capture.size()
	assert(rogue.field_features.snipers.size() == 1 and rogue.qixes.size() == 1)
	assert(not rogue.draft_exclusions().has("harvest"), "An uncaptured sniper enables Void Harvest offers")

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
	rogue.progress.ships = {"surveyor": true, "lancer": true, "bulwark": true}
	await check_editor()
	for ship_id in Progress.SHIPS:
		fixture(ship_id)
		var f = rogue.field_features
		rogue.p = Vector2i(80, 26)
		rogue.vis = rogue.center(rogue.p)
		rogue.die("SNIPER BEAM")
		assert(rogue.state == Game.State.PLAYING and not rogue.tether_hit(rogue.p) and not rogue.wire_hit(), "Shield pockets protect each ship")
		rogue.p = Vector2i(64, 46)
		rogue.vis = rogue.center(rogue.p)
		f.zone_time = 3.5
		f.zone_contact(rogue)
		assert(rogue.state == Game.State.PLAYING and f.zone_phase() == "warn")
		f.zone_time = 4.1
		f.zone_contact(rogue)
		assert(rogue.state != Game.State.PLAYING, "Live zones hit all ships")
	fixture()
	var f = rogue.field_features
	rogue.p = Vector2i(80, 70)
	rogue.vis = rogue.center(rogue.p)
	var sniper: Dictionary = f.snipers[0]
	f.update(rogue, 2.01)
	assert(sniper.phase == "warn")
	var direction: Vector2 = sniper.direction
	rogue.p = Vector2i(60, 70)
	rogue.vis = rogue.center(rogue.p)
	f.update(rogue, 0.5)
	assert(sniper.direction == direction, "Aim locks before the shot")
	await shot("sniper-warning-zones")
	var clock_before: float = sniper.clock
	rogue.freeze_time = 1
	f.update(rogue, 0.5)
	assert(sniper.clock == clock_before)
	rogue.freeze_time = 0
	rogue.pause_run()
	var zone_before: float = f.zone_time
	rogue.update(0.5)
	assert(sniper.clock == clock_before and f.zone_time == zone_before, "Pause freezes enemy and zone clocks")
	rogue.phase = "run"
	rogue.state = Game.State.PLAYING
	f.update(rogue, 0.8)
	assert(sniper.phase == "fire" and rogue.state == Game.State.PLAYING, "Dodging the locked line avoids the beam")
	await shot("sniper-firing")
	# Claimed territory does not stop this beam; rock does.
	rogue.p = Vector2i(80, 70)
	rogue.vis = rogue.center(rogue.p)
	rogue.cells[rogue.idx(80, 70)] = Game.CLAIMED
	rogue.cells[rogue.idx(80, 60)] = Game.ROCK
	f.sniper_contact(rogue, sniper)
	assert(rogue.state == Game.State.PLAYING)
	rogue.cells[rogue.idx(80, 60)] = Game.CLAIMED
	f.sniper_contact(rogue, sniper)
	assert(rogue.state != Game.State.PLAYING, "Beam crosses land and hits a parked ship")
	fixture()
	f = rogue.field_features
	sniper = f.snipers[0]
	# Capture the sniper with the real enclosure flood, leaving the Siege enemy outside.
	rogue.p = Vector2i(83, 26)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in 51: assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(sniper.captured and rogue.salvage_fraction > 0)
	rogue.p = sniper.cell
	rogue.vis = rogue.center(rogue.p)
	f.sniper_contact(rogue, sniper)
	assert(rogue.state == Game.State.PLAYING, "A destroyed Sniper cannot hit the player")
	await shot("sniper-destroyed")
	var paid: float = rogue.earned_salvage + rogue.salvage_fraction
	f.on_claim(rogue)
	assert(is_equal_approx(rogue.earned_salvage + rogue.salvage_fraction, paid), "Sniper capture pays once")
	assert(rogue.draft_exclusions().has("harvest"), "A captured sniper stops enabling new Harvest offers")
	assert(rogue.cells[rogue.idx(92, 57)] == Game.FREE, "Siege preserves its region of void")
	# Siege seeks a nearby captured coast and warns before changing it.
	var q: Game.QixBody = rogue.qixes[0]
	q.c = rogue.center(Vector2i(86, 50))
	var behavior: Dictionary = rogue.authored_behaviors[q]
	behavior.clock = 0
	rogue.update_qix(q, 0.01, 0)
	assert(behavior.phase == "warn" and f.lost_land.is_empty())
	var first_before: int = rogue.first_claims
	var captured_before: float = rogue.capture_percent
	var free_before: int = rogue.free_count
	await shot("siege-warning")
	rogue.update_qix(q, 1.6, 0)
	assert(not f.lost_land.is_empty() and f.lost_land.size() <= 13)
	assert(rogue.free_count == free_before + f.lost_land.size() and rogue.capture_percent < captured_before)
	assert(rogue.first_claims == first_before and rogue.draft_progress() > rogue.capture_percent)
	await shot("siege-territory-loss")
	var lost: Array = f.lost_land.keys()
	for i in lost: rogue.cells[i] = Game.CLAIMED
	rogue.free_count -= lost.size()
	rogue.on_claim(lost.size(), 0)
	assert(f.lost_land.is_empty() and rogue.first_claims == first_before and is_equal_approx(rogue.capture_percent, captured_before), "Reclaim restores territory without duplicate milestone credit")
	# The original arena rim and a hardened, completed Bulwark wall survive a blast.
	assert(not f.breakable(rogue, Vector2i(54, 50)))
	fixture("bulwark")
	f = rogue.field_features
	var wall: Array[Vector2i] = []
	for y in range(27, 77):
		var cell := Vector2i(85, y)
		wall.append(cell)
		rogue.cells[rogue.idx(cell.x, cell.y)] = Game.HARD
	rogue.claim_cells(wall, Vector2i(85, 26))
	assert(f.fortified.has(rogue.idx(85, 50)))
	f.break_patch(rogue, Vector2i(85, 50))
	assert(rogue.cells[rogue.idx(85, 50)] == Game.CLAIMED, "Bulwark's finished wall remains reinforced")
	rogue.start_level()
	assert(rogue.field_features.lost_land.is_empty() and rogue.field_features.fortified.is_empty(), "Restart clears runtime erosion and reinforcement")
	print("FIELD FEATURES PASS: editor paint/erase/undo/save, all-ship shields/hazards, sniper warning/dodge/rock/capture, siege erosion/reclaim/reinforcement, pause and restart")
	get_tree().quit()

func check_editor() -> void:
	var panel := EditorPanel.new()
	add_child(panel)
	panel.restore_default()
	var c := Vector2i(70, 45)
	var i := c.y * 160 + c.x
	panel.canvas.tool = "shield_zone"
	panel.canvas.brush_size = 3
	panel.begin_change()
	panel.canvas.apply_at(c)
	panel.finish_change()
	assert(panel.canvas.map.field_zones.count(1) == 9)
	panel.undo()
	assert(panel.canvas.map.field_zones.is_empty())
	panel.redo()
	assert(panel.canvas.map.field_zones[i] == 1)
	panel.canvas.tool = "hazard_zone"
	panel.begin_change()
	panel.canvas.apply_at(Vector2i(80, 45))
	panel.finish_change()
	panel.canvas.erasing = true
	panel.canvas.brush_size = 1
	panel.begin_change()
	panel.canvas.apply_at(Vector2i(80, 45))
	panel.finish_change()
	assert(panel.canvas.map.field_zones[45 * 160 + 80] == 0)
	var path := "res://.godot/field-zones-roundtrip.tres"
	assert(ResourceSaver.save(panel.canvas.map, path) == OK)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MapDefinition
	assert(loaded.field_zones == panel.canvas.map.field_zones and loaded.problems().is_empty())
	for kind in ["sniper", "siege"]:
		var option := MapCatalog.ENEMY_KINDS.find(kind)
		panel.enemy_input.select(option)
		panel.enemy_input.item_selected.emit(option)
		assert(panel.canvas.enemy_kind == kind)
	if not shot_dir.is_empty():
		main.hide()
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_dir.path_join("field-tools-editor.png"))
		main.show()
	panel.free()
