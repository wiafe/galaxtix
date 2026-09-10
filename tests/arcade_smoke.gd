extends "res://tests/roguelite_ships_smoke.gd"

func fresh_arcade() -> void:
	rogue.transit_skip = true
	rogue.start_run()
	rogue.state = Game.State.PLAYING
	rogue.phase = "run"
	rogue.invuln = 0.0
	rogue.freeze_time = 1000.0
	rogue.sparxes.clear()
	rogue.sparx_to_spawn = 0
	rogue.mites.clear()
	for q in rogue.qixes:
		q.c = rogue.center(rogue.field_arena.free_cells.back())
		q.len = 1.0
		q.v = Vector2.ZERO

func take(id: String) -> void:
	var found := false
	for pickup in rogue.pickups:
		if pickup.id != id: continue
		found = true
		pickup.cell = rogue.p
		rogue.collect_pickups()
		assert(pickup.taken)
	assert(found)

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	for stage in range(1, 9): MapCatalog.testing["roguelite_%02d" % stage] = null
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			shot_dir = arg.substr(14)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var save_before: Dictionary = Save.data.duplicate(true)
	main.game.start_roguelite()
	var profile_before: int = main.game.roguelite.progress.runs
	main.game.go_title()
	assert(main.game.TITLE_ITEMS.size() == main.game.TITLE_DESCS.size())
	main.game.title_sel = main.game.TITLE_ITEMS.find("ARCADE")
	main.game.title_t = 2.0
	main.game.update_title(0.016)
	await shot("arcade-title")
	main.game.activate_title_item()
	main.game.update_title(0.6)
	assert(main.game.state == Game.State.ARCADE)
	rogue = main.game.arcade
	assert(rogue.phase == "arcade_menu")
	await shot("arcade-menu")
	fresh_arcade()
	assert(rogue.lives == 0 and rogue.owned_cards.is_empty() and rogue.ship.id == "surveyor")
	assert(rogue.pickups.size() == 6 and rogue.nodes.is_empty() and rogue.draft_capture.is_empty())
	await shot("arcade-field")
	rogue.phase = "briefing"
	rogue.update(1.0)
	assert(rogue.remaining == 90.0)
	await shot("arcade-briefing")
	rogue.phase = "run"
	rogue.pause_run()
	rogue.update(1.0)
	assert(rogue.remaining == 90.0)
	rogue.resume_run()
	rogue.update(0.25)
	assert(is_equal_approx(rogue.remaining, 89.75))
	# Capturing a pickup's tile grants it, and health is consumed exactly once.
	take("health")
	assert(rogue.lives == 1)
	rogue.collect_pickups()
	assert(rogue.lives == 1)
	rogue.die("TEST")
	assert(rogue.state == Game.State.DYING and rogue.lives == 0)
	rogue.update(1.4)
	assert(rogue.state == Game.State.PLAYING and not rogue.settled)
	fresh_arcade()
	rogue.die("TEST")
	rogue.update(1.4)
	assert(rogue.phase == "result" and rogue.lives == -1)
	# Each former ship movement is optional, activated with the same ability action.
	for id in ["charge", "leap", "lance", "hardening", "dash"]:
		fresh_arcade()
		var free_cell: Vector2i = rogue.field_arena.free_cells[0]
		rogue.p = free_cell + Vector2i.UP
		rogue.vis = rogue.center(rogue.p)
		rogue.last_dir = Vector2i.DOWN
		rogue.activate_ability(id)
		assert(not rogue.sap_live and not rogue.leap_building and not rogue.tether_active and rogue.dash_time == 0.0)
		take(id)
		assert(rogue.equipped == id and rogue.owned_cards == [id])
		if id == "hardening":
			rogue.draw_armed = true
			for step in 4: assert(rogue.try_step(Vector2i.DOWN, true, false))
		rogue.activate_ability(id)
		match id:
			"charge": assert(rogue.sap_live)
			"leap": assert(rogue.leap_building)
			"lance": assert(rogue.tether_active)
			"hardening": assert(rogue.hardening_time > 0)
			"dash": assert(rogue.dash_time > 0)
	await check_capture_and_tally()
	await check_failures()
	check_progression()
	await check_controller()
	assert(Save.data == save_before and main.game.roguelite.progress.runs == profile_before, "Arcade never changes other modes' progression")
	rogue.leave_mode()
	assert(main.game.state == Game.State.TITLE)
	MapCatalog.testing.clear()
	print("ARCADE PASS: title/menu, capture pickups, five abilities, health, hidden progress, timed tally, retries, eight-map progression, controller, isolated saves")
	get_tree().quit()

func set_claims(count: int) -> void:
	for pickup in rogue.pickups: pickup.taken = true
	var left := count
	for i in rogue.cells.size():
		if rogue.field_arena.mask[i] != 2: continue
		rogue.cells[i] = Game.CLAIMED if left > 0 else Game.FREE
		left -= 1
	rogue.free_count = rogue.base_free - count
	rogue.grid_changed()
	rogue.on_claim(count, 0)

func buzzer() -> void:
	rogue.phase = "run"
	rogue.state = Game.State.PLAYING
	rogue.remaining = 0.0
	rogue.update(0.01)
	assert(rogue.phase == "arcade_tally" and not rogue.tally_settled)

func reveal() -> void:
	rogue.update(rogue.choice_delay() + 0.1)
	assert(rogue.tally_settled)

func check_capture_and_tally() -> void:
	fresh_arcade()
	var first: Vector2i = rogue.field_arena.free_cells[0]
	var last: Vector2i = rogue.field_arena.free_cells.back()
	# Moving through a pickup leaves it uncollected until a loop claims that tile.
	for pickup in rogue.pickups: pickup.cell = first + Vector2i(5, 5)
	rogue.p = first + Vector2i(5, 5)
	rogue.collect_pickups()
	assert(rogue.owned_cards.is_empty() and rogue.lives == 0)
	rogue.p = Vector2i(first.x + 27, first.y - 1)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in last.y - first.y + 2: assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.live_percent() > rogue.map_goal() and rogue.phase == "run" and not rogue.pending_clear)
	assert(rogue.owned_cards.size() == 5 and rogue.lives == 1, "A loop collects every covered pickup")
	assert(not rogue.msg.contains("%") and rogue.capture_flights.is_empty(), "Capture feedback cannot reveal percentages")
	var equipped: String = rogue.equipped
	rogue.cycle_ability()
	assert(rogue.equipped != equipped and rogue.owned_cards.size() == 5)
	var time_before: float = rogue.remaining
	rogue.update(0.1)
	assert(rogue.phase == "run" and rogue.remaining < time_before, "Beating the target never clears early")
	await shot("arcade-hidden-progress")
	var scores_before: int = rogue.arcade_score
	var board: PackedByteArray = rogue.cells.duplicate()
	buzzer()
	assert(rogue.round_result.passed and rogue.arcade_score == scores_before)
	assert(rogue.tally_percent() == 0.0 and rogue.tally_duration() == 3.2, "A close round gets a suspenseful count")
	rogue.activate_choice(0)
	assert(rogue.phase == "arcade_tally", "Held confirmation cannot skip the tally")
	rogue.update(1.0)
	assert(not rogue.tally_settled and rogue.tally_percent() < rogue.round_result.percent)
	await shot("arcade-counting")
	reveal()
	assert(rogue.cells == board and rogue.run_sectors == 1)
	var awarded: int = rogue.arcade_score
	assert(awarded == rogue.round_result.bonus)
	rogue.settle_tally()
	assert(rogue.arcade_score == awarded, "Score settles once")
	await shot("arcade-clear")
	rogue.activate_choice(0)
	assert(rogue.level == 2 and rogue.lives == 1 and rogue.owned_cards.is_empty() and not rogue.health_spent)
	# Full capture also waits for the buzzer.
	fresh_arcade()
	set_claims(rogue.base_free)
	rogue.update(0.1)
	assert(rogue.phase == "run" and rogue.live_percent() == 100.0)

func check_failures() -> void:
	fresh_arcade()
	take("health")
	var original_pickups: Array = rogue.pickups.duplicate(true)
	# One cell under the target must fail, without rounding up to a displayed pass.
	set_claims(ceili(rogue.base_free * rogue.map_goal() / 100.0) - 1)
	buzzer()
	assert(not rogue.round_result.passed)
	reveal()
	assert(rogue.lives == 0 and rogue.arcade_score == 0)
	await shot("arcade-miss")
	rogue.activate_choice(0)
	assert(rogue.level == 1 and rogue.remaining == 90.0 and rogue.health_spent)
	assert(rogue.lives == 0 and rogue.owned_cards.is_empty())
	for i in rogue.pickups.size():
		if rogue.pickups[i].id == "health":
			assert(rogue.pickups[i].taken, "A failed attempt cannot farm the same health pickup")
		else: assert(rogue.pickups[i].cell == original_pickups[i].cell)
	buzzer()
	reveal()
	assert(rogue.lives == -1)
	rogue.activate_choice(0)
	assert(rogue.phase == "result" and rogue.settled and not rogue.run_victory)
	# Live scoring excludes rails, unfinished trails and eroded territory.
	fresh_arcade()
	set_claims(30)
	var first: Vector2i = rogue.field_arena.free_cells[0]
	rogue.cells[rogue.idx(first.x, first.y)] = Game.FREE
	var last: Vector2i = rogue.field_arena.free_cells.back()
	rogue.cells[rogue.idx(last.x, last.y)] = Game.TRAIL
	buzzer()
	assert(rogue.round_result.cells == 29)

func check_progression() -> void:
	fresh_arcade()
	for depth in range(1, 9):
		assert(rogue.level == depth)
		assert(rogue.remaining == 90.0 and rogue.draft_capture.is_empty() and not rogue.corruption_active)
		var needed := ceili(rogue.base_free * rogue.map_goal() / 100.0)
		set_claims(needed)
		buzzer()
		reveal()
		assert(rogue.round_result.passed and rogue.run_sectors == depth)
		rogue.activate_choice(0)
	assert(rogue.phase == "result" and rogue.run_victory and rogue.run_sectors == 8)

func pad(code: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 3
	event.button_index = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func check_controller() -> void:
	fresh_arcade()
	take("charge")
	take("dash")
	await get_tree().process_frame
	pad(JOY_BUTTON_X, true)
	rogue.update(0.016)
	pad(JOY_BUTTON_X, false)
	assert(rogue.equipped == "dash")
	await get_tree().process_frame
	rogue.last_dir = Vector2i.DOWN
	pad(JOY_BUTTON_Y, true)
	rogue.update(0.016)
	pad(JOY_BUTTON_Y, false)
	assert(rogue.dash_time > 0.0)
	await get_tree().process_frame
	pad(JOY_BUTTON_B, true)
	rogue.update(0.016)
	pad(JOY_BUTTON_B, false)
	assert(rogue.phase == "paused")
	var remaining: float = rogue.remaining
	rogue.update(0.5)
	assert(rogue.remaining == remaining)
	rogue.resume_run()
	set_claims(rogue.base_free)
	buzzer()
	reveal()
	await get_tree().process_frame
	pad(JOY_BUTTON_A, true)
	rogue.update(0.016)
	pad(JOY_BUTTON_A, false)
	assert(rogue.level == 2, "Controller confirms the next map after the tally")
