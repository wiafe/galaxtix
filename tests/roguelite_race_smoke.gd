extends "res://tests/roguelite_objectives_smoke.gd"

func race_fixture(depth := 3, stage := 2, ship_id := "surveyor") -> void:
	seed(4200 + depth * 10 + stage)
	fresh_ship(ship_id)
	rogue.active_destination = {"depth": depth, "stage": stage, "kind": "race"}
	rogue.route[depth - 1][0] = rogue.active_destination
	rogue.route_path.clear()
	for row in depth: rogue.route_path.append(0)
	rogue.level = depth
	rogue.start_level()
	rogue.phase = "run"
	rogue.state = Game.State.PLAYING
	rogue.freeze_time = 0
	rogue.invuln = 10000
	rogue.drafts_taken = rogue.draft_capture.size()
	assert(rogue.race_opponent != null)
	lo = Vector2i(999, 999)
	hi = Vector2i.ZERO
	for cell in rogue.field_arena.free_cells:
		lo = lo.min(cell)
		hi = hi.max(cell)

func give_area(board: Game, percent: int) -> void:
	var amount := ceili(board.base_free * percent / 100.0)
	for cell in board.field_arena.free_cells:
		if amount <= 0: break
		board.cells[board.idx(cell.x, cell.y)] = Game.CLAIMED
		amount -= 1
	board.free_count = board.cells.count(Game.FREE)
	board.grid_changed()

func check_interruptions() -> void:
	race_fixture()
	var ai = rogue.race_opponent
	for phase in ["briefing", "paused", "draft", "replace", "rival_tally", "reward"]:
		rogue.phase = phase
		rogue.ui_time = 0
		var before: Vector2i = ai.p
		var clock: float = ai.time
		rogue.update(0.1)
		assert(ai.p == before and ai.time == clock, "Both boards pause during " + phase)
	rogue.phase = "run"
	rogue.state = Game.State.DYING
	rogue.state_t = 0
	var before: float = ai.time
	rogue.update(0.1)
	assert(ai.time == before, "Player death animation pauses the racer")
	ai.owned_cards.assign(["charge"])
	Input.action_press("br_harden")
	ai.simulate(0.05)
	Input.action_release("br_harden")
	assert(not ai.sap_live, "Human ability input never controls the racer")

func check_settlement() -> void:
	for ship_id in ["surveyor", "lancer", "bulwark"]:
		race_fixture(3, 2, ship_id)
		give_area(rogue, 61)
		assert(rogue.race_scores().y == 0, "Player captures leave the AI arena unchanged")
		var salvage: int = rogue.earned_salvage
		rogue.check_race_finish()
		assert(rogue.rival_tally.outcome == "win" and rogue.earned_salvage == salvage + 3)
		rogue.check_race_finish()
		assert(rogue.earned_salvage == salvage + 3, "Finish cannot pay twice")
		rogue.ui_time = 2
		rogue.accept_rival_tally()
		assert(rogue.phase == "chart" and rogue.race_opponent == null)
	race_fixture()
	var hull: int = rogue.lives
	var original: Dictionary = rogue.rival_entry.duplicate(true)
	rogue.owned_cards.append("afterburner")
	rogue.card_ranks.afterburner = 3
	rogue.earned_salvage += 20
	rogue.award_flux(7.0)
	assert(rogue.race_pending_salvage == 7.0)
	give_area(rogue.race_opponent, 60)
	rogue.check_race_finish()
	rogue.ui_time = 2
	rogue.accept_rival_tally()
	assert(rogue.phase == "briefing" and rogue.lives == hull - 1 and rogue.race_scores() == Vector2i.ZERO)
	assert(rogue.owned_cards == original.owned_cards and rogue.earned_salvage == original.earned_salvage)
	assert(rogue.race_pending_salvage == 0.0, "Losing discards held salvage")
	race_fixture()
	hull = rogue.lives
	give_area(rogue, 60)
	give_area(rogue.race_opponent, 60)
	rogue.check_race_finish()
	assert(rogue.rival_tally.outcome == "tie")
	rogue.ui_time = 2
	rogue.accept_rival_tally()
	assert(rogue.lives == hull and rogue.phase == "briefing")
	race_fixture()
	rogue.lives = 0
	give_area(rogue.race_opponent, 60)
	rogue.check_race_finish()
	rogue.ui_time = 2
	rogue.accept_rival_tally()
	assert(rogue.phase == "result" and rogue.lives == -1 and rogue.race_opponent == null)
	race_fixture()
	var bank_before: int = rogue.progress.salvage
	var earned_before: int = rogue.earned_salvage
	rogue.award_flux(9.0)
	rogue.end_run()
	assert(rogue.progress.salvage == bank_before + earned_before, "Ending an unfinished race cannot bank its rewards")

func check_finishing_cut() -> void:
	MapCatalog.testing["roguelite_01"] = null
	race_fixture(3, 1)
	bare_field()
	rogue.drafts_taken = 0
	park_anomalies(hi - Vector2i(2, 2))
	var earned_before: int = rogue.earned_salvage
	var build_before: Array = rogue.owned_cards.duplicate()
	cut_column(lo.x + int((hi.x - lo.x) * 0.42))
	rogue.award_flux(2.5)
	assert(rogue.draft_progress() >= rogue.draft_capture[0] and rogue.capture_percent < Sectors.RACE_GOAL)
	assert(rogue.phase == "run" and not rogue.draft_ready(), "Capture milestones never interrupt an unfinished race")
	var ai_clock: float = rogue.race_opponent.time
	rogue.update(0.05)
	assert(rogue.phase == "run" and rogue.race_opponent.time > ai_clock, "Both competitors continue past the milestone")
	assert(rogue.earned_salvage == earned_before and rogue.owned_cards == build_before and rogue.drafts_taken == 0)
	cut_column(lo.x + int((hi.x - lo.x) * 0.7))
	var held: float = rogue.race_pending_salvage
	rogue.check_race_finish()
	assert(rogue.phase == "rival_tally" and rogue.rival_tally.outcome == "win", "A real completed loop wins")
	assert(rogue.earned_salvage == earned_before + floori(held + 3.0) and rogue.race_pending_salvage == 0.0, "Winning releases held salvage once")
	rogue.ui_time = 2
	rogue.accept_rival_tally()
	assert(rogue.phase == "reward" and rogue.pending_clear, "Winning cut still awards its draft")
	resolve_to_clear()
	assert(rogue.phase == "sector_clear")
	assert(rogue.drafts_taken > 0, "Held draft choices arrive after winning")
	MapCatalog.testing.clear()

func check_routes() -> void:
	var positions := {}
	for seed_value in 200:
		var random := RandomNumberGenerator.new()
		random.seed = seed_value
		var route: Array = Sectors.make_route(random)
		for row in route:
			for side in row.size():
				if row[side].kind == "race":
					assert(row[side].depth >= 3 and row[side].depth < 8)
					positions["middle" if row.size() == 1 else str(side)] = true
	assert(positions.size() == 3, "Race appears on upper/lower routes and the shared middle")

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			shot_dir = arg.substr(14)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var campaign: Dictionary = Save.data.duplicate(true)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	rogue.progress.apply_profile({"version": 6, "ships": {"surveyor": true, "lancer": true, "bulwark": true}})
	check_routes()
	check_interruptions()
	check_settlement()
	check_finishing_cut()
	race_fixture()
	var ai = rogue.race_opponent
	assert(rogue.cells == ai.cells and rogue.base_free == ai.base_free and rogue.p == ai.p)
	assert(rogue.race_scores() == Vector2i.ZERO)
	for i in rogue.qixes.size():
		assert(rogue.qixes[i] != ai.qixes[i] and rogue.qixes[i].c == ai.qixes[i].c)
	assert(rogue.field_features != ai.field_features)
	assert(ai.fill.get_parent() == rogue.fill.get_parent(), "Both fills use the same post-processing viewport")
	rogue.phase = "briefing"
	await shot("race-briefing")
	rogue.phase = "run"
	await shot("race-start")
	seed(9001)
	for frame in 600:
		rogue.update(1.0 / 60.0)
	print("RACE 10s: ", rogue.race_scores(), " ai pos ", ai.p, " plan ", ai.brain.plan.size())
	await shot("race-playing")
	seed(9002)
	assert(ai.p != rogue.p, "The racer moves without human input")
	assert(rogue.race_scores().x == 0, "AI captures cannot alter player territory")
	for frame in 21600:
		if rogue.phase == "rival_tally": break
		rogue.update(1.0 / 60.0)
	print("RACE SIM: ", rogue.race_elapsed, " scores ", rogue.race_scores(), " ai captures ", ai.capture_count, " deaths ", ai.sector_deaths)
	assert(rogue.phase == "rival_tally" and rogue.rival_tally.outcome == "loss", "A real AI must finish an unattended race")
	await shot("race-loss")
	for stage in range(2, 8):
		race_fixture(7, stage)
		ai = rogue.race_opponent
		var untouched: PackedByteArray = rogue.cells.duplicate()
		for frame in 2400:
			ai.simulate(1.0 / 60.0)
		assert(ai.capture_count > 0, "Racer can capture on authored stage %d" % stage)
		assert(rogue.cells == untouched, "No shared board mutations on stage %d" % stage)
		print("RACE MAP ", stage, " captures ", ai.capture_count, " claimed ", ai.race_claimed)
	assert(Save.data == campaign, "Race never writes the Jump profile")
	print("ROGUELITE RACE OK")
	get_tree().quit()
