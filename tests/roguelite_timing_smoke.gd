extends "res://tests/roguelite_ships_smoke.gd"

func walk(ship_id: String, interior: bool, fps: int, engines: int) -> Dictionary:
	fresh_ship(ship_id)
	rogue.progress.ranks.engines = engines
	# A captured strip has both a coast and an interior of equal unobstructed length.
	for y in range(26, 47):
		for x in range(54, 106):
			rogue.cells[rogue.idx(x, y)] = Game.CLAIMED
	rogue.grid_changed()
	rogue.p = Vector2i(58, 34 if interior else 46)
	rogue.vis = rogue.center(rogue.p)
	rogue.move_acc = 0.0
	assert((rogue.border[rogue.idx(rogue.p.x, rogue.p.y)] == 0) == interior)
	var distances: Array[float] = []
	Input.action_press("move_right")
	for frame in fps * 2:
		var previous: Vector2 = rogue.vis
		rogue.update(1.0 / fps)
		if frame >= fps / 2:
			distances.append(rogue.vis.distance_to(previous))
	Input.action_release("move_right")
	var travel: float = rogue.p.x - 58 + rogue.move_acc
	assert(absf(travel - 22.0 * (1.0 + 0.02 * engines)) < 0.001, "Travel must match the ship's configured speed")
	distances.sort()
	var ratio := distances[-1] / distances[0]
	assert(ratio < 1.3, "Held movement should stay visually even, not ease to a halt every cell: %s/%dFPS ratio=%f" % [ship_id, fps, ratio])
	var stopped_at: Vector2i = rogue.p
	for frame in fps / 2: rogue.update(1.0 / fps)
	assert(rogue.p == stopped_at and rogue.vis.is_equal_approx(rogue.center(stopped_at)), "Releasing movement settles at the occupied cell without drift")
	return {"travel": travel, "ratio": ratio}

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	rogue.progress.ships = {"surveyor": true, "lancer": true, "sapper": true}
	var campaign: Dictionary = Save.data.duplicate(true)
	var worst_ratio := 0.0
	for ship_id in ["surveyor", "lancer", "sapper"]:
		for engines in [0, 10]:
			for fps in [30, 60, 120]:
				var coast := walk(ship_id, false, fps, engines)
				var interior := walk(ship_id, true, fps, engines)
				assert(is_equal_approx(coast.travel, interior.travel), "Interior and coast must have identical speed")
				worst_ratio = maxf(worst_ratio, maxf(coast.ratio, interior.ratio))
	# A wall must stop both the simulation and its visual follower.
	rogue.p = Vector2i(104, 26)
	rogue.vis = rogue.center(rogue.p)
	rogue.move_acc = 0.0
	Input.action_press("move_right")
	for frame in 120: rogue.update(1.0 / 60.0)
	Input.action_release("move_right")
	assert(rogue.p == Vector2i(105, 26) and rogue.vis.is_equal_approx(rogue.center(rogue.p)))
	assert(Save.data == campaign)
	print("ROGUELITE TIMING OK: coast/interior speed parity, all ships, upgraded engines, 30/60/120 FPS, stops and walls; worst visual speed ratio=", worst_ratio)
	get_tree().quit()
