extends Node
## godot --headless --path . res://tests/arena_smoke.tscn -- --nosave
func _ready() -> void:
	call_deferred("check_arenas")

func check_arenas() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	assert(not get_tree().root.get_node("Save").enabled)
	var game: Game = main.game
	var save = get_tree().root.get_node("Save")
	game.gal = Galaxies.LIST[0]
	save.data.flux = 0.0
	save.data.upgrades = {"damp": 2, "jam": 2}
	save.refund_retired_upgrades()
	assert(save.data.flux == 18.0, "Refund each purchased level at its original price")
	save.refund_retired_upgrades()
	assert(save.data.flux == 18.0, "Refund must only happen once")
	assert(not save.can_buy("damp") and not save.can_buy("jam"))
	var previous_speed := 0.0
	var previous_size := 0.0
	var previous := 0
	for sector in range(1, 9):
		var size_mult := SectorArena.anomaly_size_mult("helix", sector)
		var speed_mult := SectorArena.enemy_mult("helix", sector)
		assert(size_mult > previous_size and speed_mult > previous_speed)
		previous_size = size_mult
		previous_speed = speed_mult
		var arena := SectorArena.build(sector, 0)
		assert(arena.base_free > previous, "Areas must grow each sector")
		previous = arena.base_free
		for rim in [0, 12]:
			save.data.upgrades.bulk = rim
			game.level = sector
			game.start_level()
			var lay := game.sector_layout(game.gal, sector, rim)
			assert(game.p == lay.start)
			assert(game.cells[game.idx(game.p.x, game.p.y)] == Game.CLAIMED)
			assert(game.border[game.idx(game.p.x, game.p.y)] == 1)
			assert(game.base_free == arena.base_free)
			if rim == 0:
				assert(is_zero_approx(game.claimed_frac()))
			for node in game.nodes:
				assert(game.cells[game.idx(node.cell.x, node.cell.y)] == Game.FREE)
			for i in Game.N * Game.N:
				assert(game.cells[i] != Game.ROCK or lay.arena.mask[i] == 0)
			game.spawn_sparx()
			assert(game.sparxes.size() == 1)
			assert(game.border[game.idx(game.sparxes[0].c.x, game.sparxes[0].c.y)] == 1)
			for q in game.qixes:
				assert(not game.qix_blocked(q.c, q.theta, q.len), "Anomaly starts inside void")
				assert(is_equal_approx(q.len, 80.0 * size_mult))
				game.update_qix(q, 1.0 / 60.0, game.qix_speed())
				assert(q.len >= 40.0 * size_mult and q.len <= 100.0 * size_mult)
				assert(is_equal_approx(q.v.length(), game.qix_speed()))
			# Every initial rim cell can be reached with the player's four-direction movement.
			var reached := {game.p: true}
			var pending := [game.p]
			while not pending.is_empty():
				var c: Vector2i = pending.pop_back()
				for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var n: Vector2i = c + d
					if game.in_bounds(n) and game.cells[game.idx(n.x, n.y)] == Game.CLAIMED and not reached.has(n):
						reached[n] = true
						pending.append(n)
			for i in Game.N * Game.N:
				if game.cells[i] == Game.CLAIMED:
					assert(reached.has(Vector2i(i % Game.N, i / Game.N)))
			if rim == 0:
				game.state = Game.State.PLAYING
				game.draw_armed = true
				for q in game.qixes:
					q.c = game.center(Vector2i(44, 52))
				for step in Game.N:
					assert(game.try_step(Vector2i.DOWN, true, false))
					if not game.drawing:
						break
				assert(not game.drawing and game.claimed_frac() > 0)
				var counted := 0
				for cell in game.cells:
					if cell == Game.FREE:
						counted += 1
				assert(counted == game.free_count, "Capture scoring excludes outside cells")
		print("sector %d: base area %d" % [sector, arena.base_free])
	assert(game.sector_layout(Galaxies.LIST[1], 1, 0).arena.is_empty())
	assert(game.sector_layout(Galaxies.LIST[0], 9, 0).arena.is_empty())
	assert(SectorArena.anomaly_size_mult("belt", 1) == 1.0)
	assert(SectorArena.enemy_mult("helix", 9) == 1.0)
	print("PASS: enemy scaling and upgrade refunds, growing areas, spawn validity, connected rims, capture accounting, other galaxies/endless unchanged")
	get_tree().quit()
