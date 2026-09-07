extends Node
## godot --headless --path . res://tests/leaper_smoke.tscn -- --nosave
## The Leaper's JezzBall wall: the first side to land hardens, a hit on the running side after
## that only drops it, a hit while both run hurts, and a wall that lands both sides splits.
func _ready() -> void:
	call_deferred("check")

func fresh(game: Game) -> void:
	game.level = 3
	game.start_level()
	game.state = Game.State.PLAYING
	game.invuln = 0.0
	game.lives = 2
	for q in game.qixes:
		q.c = game.center(Vector2i(20, 52))   # out of the wall's column
	game.last_dir = Vector2i.DOWN
	game.start_leap()
	assert(game.leap_building)
	game.leap_aim(10.0, Vector2i.ZERO)
	game.finish_leap(false)
	assert(game.wall_building and game.drawing)

func running_cell(game: Game, side: int) -> Vector2i:
	assert(not game.wall_cells[side].is_empty())
	return game.wall_cells[side][game.wall_cells[side].size() / 2]

func check() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var game: Game = main.game
	assert(not get_tree().root.get_node("Save").enabled)
	game.gal = Galaxies.LIST[0]
	game.ship = Ships.get_ship("leaper")
	# 1. Grow until exactly one side has landed: that side is coast, the other still a trail.
	fresh(game)
	var guard := 0
	while not (game.wall_done[0] or game.wall_done[1]) and guard < 400:
		game.wall_grow(0.05)
		guard += 1
	assert(game.wall_building, "One side landed, the wall is still building")
	var hard := 0 if game.wall_done[0] else 1
	var soft := 1 - hard
	assert(game.wall_cells[hard].is_empty(), "Hardened side left the trail")
	assert(not game.wall_cells[soft].is_empty())
	for c in game.trail:
		assert(game.cells[game.idx(c.x, c.y)] == Game.TRAIL)
	var island: Vector2i = game.leap_tip
	var toward: Vector2i = game.wall_dirs[hard]
	assert(game.cells[game.idx(island.x + toward.x, island.y + toward.y)] == Game.CLAIMED, "Hardened side is coast")
	assert(game.cells[game.idx(island.x, island.y)] == Game.CLAIMED, "The tip hardens with the first side")
	# 2. A hit on the running side now drops it and hurts nobody.
	var lives := game.lives
	var hit := running_cell(game, soft)
	assert(not game.tether_hit(hit), "Hit after one side hardened is harmless")
	assert(game.cells[game.idx(hit.x, hit.y)] == Game.FREE)
	assert(not game.wall_building and not game.drawing and game.trail.is_empty())
	assert(game.lives == lives and game.state == Game.State.PLAYING)
	assert(game.cells[game.idx(island.x, island.y)] == Game.CLAIMED, "The tip stays as coast")
	assert(game.p == island and game.border[game.idx(game.p.x, game.p.y)] == 1, "The ship stands on coast")
	# 3. A hit while both sides are still running hurts.
	fresh(game)
	game.wall_grow(0.05)
	game.wall_grow(0.05)
	assert(not (game.wall_done[0] or game.wall_done[1]))
	assert(game.tether_hit(running_cell(game, 0)), "Hit with both sides running is lethal")
	game.die("TEST")
	assert(game.lives == 1 and game.state == Game.State.DYING)
	# 4. Left alone, both sides land and the flood fill splits the void.
	fresh(game)
	var before := game.claimed_frac()
	guard = 0
	while game.wall_building and guard < 800:
		game.wall_grow(0.05)
		guard += 1
	assert(not game.wall_building and not game.drawing)
	assert(game.claimed_frac() > before + 0.05, "A finished wall claims a real region")
	var counted := 0
	for cell in game.cells:
		if cell == Game.FREE:
			counted += 1
	assert(counted == game.free_count, "Free-cell accounting survives hardening and claiming")
	# 5. Leaping is only allowed from the coast, and from where the ship stands.
	game.level = 3
	game.start_level()
	game.state = Game.State.PLAYING
	game.p = game.p + Vector2i(0, -1)   # one step into the rim's interior
	assert(game.border[game.idx(game.p.x, game.p.y)] == 0)
	game.last_dir = Vector2i.DOWN
	game.start_leap()
	assert(not game.leap_building, "No leap from off the coast")
	game.p = game.p + Vector2i(0, 1)
	game.start_leap()
	assert(game.leap_building and game.anchor == game.p, "The aim starts under the ship")
	# 6. Held to the far coast: the aim touches land and the ship leaps to the end of it.
	get_tree().root.get_node("Save").data.ship_upgrades = {"leaper:arm": 10}
	game.leap_aim(0.05, Vector2i.ZERO)
	assert(not game.leap_reached_coast())
	var reach := game.ray_len(game.anchor, game.leap_dir)
	if reach <= game.leap_max():
		game.leap_aim(100.0, Vector2i.ZERO)
		assert(game.leap_reached_coast(), "A full hold reaches the far coast")
		game.finish_leap(true)
		assert(game.p == game.anchor + game.leap_dir * reach)
	print("PASS: first side hardens, harmless cut after that, lethal cut while both run, full wall splits, coast-only leaps, hold to the far coast")
	get_tree().quit()
