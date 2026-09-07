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
		for rim in [0, 4]:
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
	assert(game.sector_layout(Galaxies.LIST[0], 9, 0).arena.is_empty())
	assert(game.sector_layout(Galaxies.LIST[2], 1, 0).arena.is_empty())
	assert(SectorArena.anomaly_size_mult("belt", 1) == 1.0)
	assert(SectorArena.enemy_mult("helix", 9) == 1.0)
	# Turret Belt: carved outlines, and every pylon wears a one-cell rail of coast (an inner rail).
	game.gal = Galaxies.LIST[1]
	for sector in range(1, 10):
		save.data.upgrades.bulk = 0
		game.level = sector
		game.start_level()
		var lay := game.sector_layout(game.gal, sector, 0)
		assert(not lay.arena.is_empty(), "The Belt is carved at every sector")
		assert(game.cells[game.idx(game.p.x, game.p.y)] == Game.CLAIMED and game.border[game.idx(game.p.x, game.p.y)] == 1)
		assert(not lay.shape.is_empty() or sector == 3 or sector == 4, "Sectors carry pylons")
		for rc in lay.shape:
			var rr: Rect2i = rc
			for y in range(rr.position.y - 1, rr.end.y + 1):
				for x in range(rr.position.x - 1, rr.end.x + 1):
					var inside := rr.has_point(Vector2i(x, y))
					assert(game.cells[game.idx(x, y)] == (Game.ROCK if inside else Game.CLAIMED), "Rock inside, rail around")
			for y in range(rr.position.y - 2, rr.end.y + 2):
				for x in range(rr.position.x - 2, rr.end.x + 2):
					if not rr.grow(1).has_point(Vector2i(x, y)):
						assert(game.cells[game.idx(x, y)] == Game.FREE, "The rail is exactly one cell thick")
		# Claimed cells are the outer coast (walkable from the start) or a pylon rail, nothing else.
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
			if game.cells[i] != Game.CLAIMED:
				continue
			var c := Vector2i(i % Game.N, i / Game.N)
			var on_rail := false
			for rc in lay.shape:
				if (rc as Rect2i).grow(1).has_point(c):
					on_rail = true
			assert(reached.has(c) or on_rail, "Every claimed cell is coast or a rail")
		for q in game.qixes:
			assert(not game.qix_blocked(q.c, q.theta, q.len), "Anomaly starts inside void")
		for node in game.nodes:
			assert(game.cells[game.idx(node.cell.x, node.cell.y)] == Game.FREE)
		print("belt sector %d: base area %d, pylons %d" % [sector, lay.arena.base_free, lay.shape.size()])
	# A trail from the outer coast to the moat's core rail encloses nothing: it becomes a bridge and
	# the core rail joins the coast you can walk.
	game.level = 5
	game.start_level()
	game.state = Game.State.PLAYING
	game.draw_armed = true
	for q in game.qixes:
		q.c = game.center(Vector2i(12, 52))
	var before := game.free_count
	var walked := 0
	for step in Game.N:
		assert(game.try_step(Vector2i.DOWN, true, false))
		if game.drawing:
			walked += 1
		else:
			break
	assert(not game.drawing and walked > 10)
	assert(before - game.free_count == walked, "Bridge to an island claims only the trail")
	var core: Rect2i = game.field_shape[0]
	assert(game.cells[game.idx(core.position.x - 1, core.position.y - 1)] == Game.CLAIMED)
	var coast_start: Vector2i = game.sector_layout(game.gal, 5, 0).start
	var reached2 := {coast_start: true}
	var pending2 := [coast_start]
	while not pending2.is_empty():
		var c: Vector2i = pending2.pop_back()
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if game.in_bounds(n) and game.cells[game.idx(n.x, n.y)] == Game.CLAIMED and not reached2.has(n):
				reached2[n] = true
				pending2.append(n)
	assert(reached2.has(Vector2i(core.position.x - 1, core.position.y - 1)), "The bridge connects the core rail to the coast")
	print("PASS: enemy scaling and upgrade refunds, growing areas, spawn validity, connected rims, capture accounting, carved Belt with railed pylons, bridge to an island")
	get_tree().quit()
