extends "res://tests/roguelite_ships_smoke.gd"

func cut_cell(x: int) -> void:
	rogue.p = Vector2i(x, 49)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.try_step(Vector2i.DOWN, true, false))

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	var goals := [60, 65, 70, 75, 80, 85, 90, 90]
	assert(is_equal_approx(main.game.capture_target(), 0.75), "Jump retains its current goal")
	for sector in range(1, 9):
		fresh_ship("surveyor")
		rogue.level = sector
		var goal: int = goals[sector - 1]
		assert(is_equal_approx(rogue.capture_target(), goal / 100.0))
		# Exactly 100 capturable cells, with safe rails above/below. Real vertical
		# cuts isolate the left side while the Anomaly keeps the right side alive.
		rogue.cells.fill(Game.ROCK)
		rogue.credited.fill(1)
		for y in range(49, 52):
			for x in range(29, 131): rogue.cells[rogue.idx(x, y)] = Game.CLAIMED
		for x in range(30, 130):
			rogue.cells[rogue.idx(x, 50)] = Game.FREE
			rogue.credited[rogue.idx(x, 50)] = 0
		rogue.base_free = 100
		rogue.free_count = 100
		rogue.first_claims = 0
		rogue.capture_percent = 0
		rogue.nodes.clear()
		rogue.turrets.clear()
		rogue.spawners.clear()
		rogue.qixes.resize(1)
		rogue.qixes[0].c = rogue.center(Vector2i(129, 50))
		rogue.qixes[0].len = 1
		rogue.grid_changed()
		rogue.drafts_taken = rogue.draft_capture.size()
		cut_cell(30 + goal - 2)
		assert(rogue.capture_percent == goal - 1 and not rogue.pending_clear and rogue.phase == "run", "The sector cannot clear below its goal")
		assert(rogue.capture_bar_point(goal - 1).x < rogue.CAPTURE_BAR.end.x - 3)
		cut_cell(30 + goal - 1)
		assert(rogue.capture_percent == goal and rogue.pending_clear and rogue.phase == "reward", "Reaching the exact target clears through the real capture path")
		assert(is_equal_approx(rogue.capture_bar_point(goal).x, rogue.CAPTURE_BAR.end.x - 3))
		assert(rogue.capture_bar_point(100) == rogue.capture_bar_point(goal), "Overshooting the goal cannot overfill the bar")
	rogue.level = 99
	assert(is_equal_approx(rogue.capture_target(), 0.9), "Targets never exceed 90 percent")
	print("ROGUELITE TARGETS OK: 60/65/70/75/80/85/90/90, exact real-capture thresholds, matching bar, 90 percent cap and Jump isolation")
	get_tree().quit()
