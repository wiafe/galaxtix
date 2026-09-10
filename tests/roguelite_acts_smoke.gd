extends "res://tests/roguelite_ships_smoke.gd"
const Acts = preload("res://scripts/roguelite_acts.gd")
const Sectors = preload("res://scripts/roguelite_sectors.gd")

func launch(stage: int, depth: int, ship_id := "surveyor", encounter := "") -> void:
	rogue.sector_limit = Acts.LENGTH
	rogue.progress.select_ship(ship_id)
	rogue.transit_skip = true
	rogue.start_run()
	rogue.chart_depth = depth
	rogue.route_path.resize(depth - 1)
	rogue.route_path.fill(0)
	var map := MapCatalog.read(stage)
	var kind := "boss" if not map.boss_id.is_empty() else "survey"
	if not encounter.is_empty(): kind = encounter
	rogue.route[depth - 1] = [{"depth": depth, "stage": stage, "kind": kind, "boss": map.boss_id}]
	rogue.open_chart()
	rogue.launch_destination(0)
	rogue.phase = "run"
	rogue.state = Game.State.PLAYING
	rogue.surv_scale = 1
	rogue.opening_draft_pending = false
	rogue.drafts_taken = rogue.draft_capture.size()
	rogue.freeze_time = 1000
	rogue.nodes.clear()
	rogue.sparxes.clear()
	rogue.sparx_to_spawn = 0
	for q in rogue.qixes:
		q.c = rogue.center(Vector2i(60, 52))
		q.len = 4
		q.v = Vector2.ZERO

func cut(start: Vector2i, direction: Vector2i, steps: int) -> void:
	assert(rogue.cells[rogue.idx(start.x, start.y)] == Game.CLAIMED)
	rogue.p = start
	rogue.vis = rogue.center(start)
	rogue.draw_armed = true
	for step in steps: assert(rogue.try_step(direction, true, false))
	for step in 600:
		if rogue.seals.is_empty(): break
		rogue.update(0.05)
	assert(rogue.seals.is_empty())

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	var profile = preload("res://scripts/roguelite_progress.gd").new()
	profile.apply_profile({"version": 6, "best_sector": 8})
	assert(profile.track_available("containment"), "Eight-sector saves retain their unlock")
	profile.apply_profile({"version": 7, "best_sector": 8})
	assert(not profile.track_available("containment"))
	profile.apply_profile({"version": 7, "best_sector": 11})
	assert(profile.track_available("containment"))
	profile.apply_profile({"version": 8, "best_sector": 16})
	assert(not profile.track_available("containment"))
	profile.apply_profile({"version": 8, "best_sector": 17})
	assert(profile.track_available("containment"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			shot_dir = arg.substr(14)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	for seed_value in 100:
		var random := RandomNumberGenerator.new()
		random.seed = seed_value
		var route := Sectors.make_route(random)
		random.seed = seed_value
		assert(route == Sectors.make_route(random) and route.size() == Acts.LENGTH)
		var counts := {"boss": 0, "race": 0, "rival": 0}
		for depth in range(1, Acts.LENGTH + 1):
			for node in route[depth - 1]:
				if counts.has(node.kind): counts[node.kind] += 1
				assert(node.act == Acts.act_at(depth))
				if node.kind == "boss":
					assert(depth % Acts.ACT_LENGTH == 0 and route[depth - 1].size() == 1)
					assert(node.boss in Acts.ACTS[node.act - 1].bosses and Acts.BOSSES[node.boss].map == node.stage)
				else: assert(node.stage == Acts.ACTS[node.act - 1].maps[Acts.step_at(depth) - 1], "Map introductions stay ordered on every branch")
		assert(counts == {"boss": 3, "race": 1, "rival": 1})
	for stage in range(Acts.FIRST_MAP, Acts.LAST_MAP + 1):
		var map := MapCatalog.read(stage)
		assert(map != null and map.problems().is_empty() and map.act_theme == Acts.map_act(stage))
		for enemy in (load(MapCatalog.default_path(map.map_id)) as MapDefinition).enemies:
			assert(enemy.kind in ["boss_core", "boss_relay"] or enemy.kind in Acts.ACTS[map.act_theme - 1].enemies)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	rogue.progress.ships = {"surveyor": true, "lancer": true, "bulwark": true}
	rogue.start_run()
	assert(rogue.route.size() == Acts.LENGTH)
	await shot("act-1-chart")
	for act in range(1, 4):
		for stage in Acts.ACTS[act - 1].maps:
			for kind in ["race", "rival", "beacon", "cargo"]:
				launch(stage, (act - 1) * Acts.ACT_LENGTH + 3, "surveyor", kind)
				assert(not rogue.boss.active())
				match kind:
					"race": assert(rogue.race_opponent != null and rogue.race_opponent.base_free == rogue.base_free)
					"rival": assert(rogue.rival != null)
					"cargo": assert(not rogue.cargo.is_empty() and rogue.cells[rogue.idx(rogue.cargo.cell.x, rogue.cargo.cell.y)] == Game.FREE)
					"beacon":
						assert(not rogue.zones.is_empty())
						for zone in rogue.zones: assert(rogue.disc_claimed_fraction(zone.cell, zone.radius) == 0)
	for act in range(1, 4):
		rogue.chart_depth = (act - 1) * Acts.ACT_LENGTH + 1
		rogue.route_path.resize(rogue.chart_depth - 1)
		rogue.route_path.fill(0)
		rogue.open_chart()
		assert(rogue.chart_bounds() == Vector2i((act - 1) * Acts.ACT_LENGTH + 1, act * Acts.ACT_LENGTH))
		rogue.move_chart_focus(Vector2i(-100, 0))
		assert(rogue.chart_focus_depth == rogue.chart_bounds().x)
		rogue.move_chart_focus(Vector2i(100, 0))
		assert(rogue.chart_focus_depth == rogue.chart_bounds().y, "Future acts cannot be browsed or selected early")
		rogue.move_chart_focus(Vector2i(-100, 0))
		await shot("act-%d-chart" % act)
		launch(Acts.ACTS[act - 1].maps[0], (act - 1) * Acts.ACT_LENGTH + 1)
		assert(rogue.current_theme() == act)
		assert(rogue.cur_gal().dither == act - 1)
		assert(rogue.coast_color() == Acts.TERRITORY[act - 1].coast)
		rogue.update_fill()
		for cell in rogue.field_arena.free_cells:
			if rogue.cells[rogue.idx(cell.x, cell.y)] == Game.FREE:
				assert(rogue.fill_img.get_pixel(cell.x, cell.y).a == 0, "Every act keeps the same untinted void")
		# Show a broad captured interior, and sample Jump's three distinct patterns.
		for cell in rogue.field_arena.free_cells:
			if cell.x < rogue.grid_width / 3: rogue.cells[rogue.idx(cell.x, cell.y)] = Game.CLAIMED
		for y in range(10, 12):
			for x in range(10, 12): rogue.cells[rogue.idx(x, y)] = Game.CLAIMED
		rogue.grid_changed()
		var bright: Array = [[true, false, false, true], [true, true, false, false], [true, false, false, false]][act - 1]
		for sample in 4:
			var pixel: Color = rogue.fill_img.get_pixel(10 + sample % 2, 10 + sample / 2)
			assert(is_equal_approx(pixel.r, 1.0) if bright[sample] else pixel.r < 0.51, "Captured interiors use the act's Jump pattern")
		var tint: Color = Acts.TERRITORY[act - 1].fill
		tint.a = 0.16
		assert(rogue.fill.modulate == tint)
		await shot("act-%d-interior" % act)
		for ship_id in ["surveyor", "lancer", "bulwark"]:
			var boss_id: String = Acts.ACTS[act - 1].bosses[0]
			# The scripted cut coordinates belong to the shipped fixture, not edited arenas.
			var map_id := "roguelite_%02d" % Acts.BOSSES[boss_id].map
			MapCatalog.testing[map_id] = load(MapCatalog.default_path(map_id))
			launch(Acts.BOSSES[boss_id].map, act * Acts.ACT_LENGTH, ship_id)
			assert(rogue.boss.active() and rogue.boss.remaining() == 3 and not rogue.objective_complete())
			rogue.capture_percent = 100
			rogue.level_clear()
			assert(not rogue.pending_clear, "Territory percentage cannot skip a boss")
			rogue.capture_percent = 0
			rogue.boss.relays[0].clock = 0.01
			rogue.freeze_time = 0
			rogue.boss.update(rogue, 0.02)
			assert(rogue.boss.relays[0].phase == "warn")
			var clock_before: float = rogue.boss.relays[0].clock
			rogue.freeze_time = 2
			rogue.boss.update(rogue, 1)
			assert(rogue.boss.relays[0].clock == clock_before, "Stasis freezes boss attacks")
			rogue.freeze_time = 0
			rogue.phase = "paused"
			rogue.boss.update(rogue, 2)
			assert(rogue.boss.relays[0].clock == clock_before)
			rogue.phase = "run"
			rogue.boss.update(rogue, 1.5)
			assert(not rogue.mites.is_empty() if act == 2 else (not rogue.bolts.is_empty() if act == 1 else rogue.boss.relays[0].phase == "fire"))
			rogue.bolts.clear()
			rogue.mites.clear()
			rogue.freeze_time = 1000
			if ship_id == "surveyor":
				await shot(boss_id + "-locked")
				rogue.phase = "briefing"
				await shot(boss_id + "-briefing")
				rogue.phase = "run"
			# Real flood captures; the boss's protected center cannot be claimed early.
			cut(Vector2i(35, 42), Vector2i.RIGHT, 89)
			assert(rogue.boss.remaining() == 1 and not rogue.boss.unlocked)
			cut(Vector2i(35, 66), Vector2i.RIGHT, 89)
			assert(rogue.boss.unlocked and not rogue.boss.defeated and rogue.boss.remaining() == 0)
			if ship_id == "surveyor": await shot(boss_id + "-exposed")
			var before: int = rogue.earned_salvage
			cut(Vector2i(74, 42), Vector2i.DOWN, 24)
			assert(rogue.boss.defeated and rogue.pending_clear)
			for step in 100:
				if rogue.phase in ["sector_clear", "result"]: break
				rogue.update(0.05)
			assert(rogue.phase == ("result" if act == 3 else "sector_clear"))
			if ship_id == "surveyor": await shot(boss_id + "-victory")
			assert(rogue.earned_salvage >= before + Acts.BOSSES[boss_id].reward)
			var after: int = rogue.earned_salvage
			rogue.finish_sector()
			assert(rogue.earned_salvage == after, "Boss reward only pays once")
			if act == 3: assert(rogue.run_victory)
			else:
				rogue.ui_time = rogue.VICTORY_REVEAL
				rogue.continue_expedition()
				assert(rogue.chart_depth == act * Acts.ACT_LENGTH + 1 and rogue.phase == "chart")
	MapCatalog.testing.clear()
	print("ROGUELITE ACTS PASS: deterministic pools, exclusive rosters, 24 maps, territory palettes/patterns, unchanged void, all-ship boss captures, phases, attacks, pause, rewards, act progression and finale")
	get_tree().quit()
