extends "res://tests/roguelite_ships_smoke.gd"

const Reference = preload("res://tests/fixtures/grid_reference.gd")

func compare_grid(game: Game) -> void:
	var reference := Reference.new()
	reference.grid_width = game.grid_width
	reference.grid_height = game.grid_height
	reference.FX = game.FX
	reference.gal = game.cur_gal()
	reference.state = Game.State.PLAYING
	reference.cells = game.cells.duplicate()
	reference.border.resize(game.cells.size())
	reference.fill = Sprite2D.new()
	reference.fill_img = Image.create(game.grid_width, game.grid_height, false, Image.FORMAT_RGBA8)
	reference.fill_tex = ImageTexture.create_from_image(reference.fill_img)
	reference.grid_changed()
	game.grid_changed()
	assert(game.border == reference.border and game.border_cells == reference.border_cells, "Optimized border preserves all eight neighbours and stable ordering")
	assert(game.coast == reference.coast, "Optimized coast preserves exact segment coordinates and order")
	assert(game.fill_img.get_data() == reference.fill_img.get_data(), "Territory dither pixels must remain byte-identical")
	reference.fill.free()
	reference.free()

func reference_spread() -> PackedByteArray:
	var next: PackedByteArray = rogue.corruption.duplicate()
	for i in rogue.cells.size():
		if rogue.corruption[i] == 0 or rogue.cells[i] != Game.FREE: continue
		var c := Vector2i(i % rogue.grid_width, i / rogue.grid_width)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if rogue.in_bounds(n) and rogue.cells[rogue.idx(n.x, n.y)] == Game.FREE:
				next[rogue.idx(n.x, n.y)] = 1
	return next

func expected_strokes() -> PackedVector2Array:
	var strokes := PackedVector2Array()
	for y in range(1, rogue.grid_height - 1):
		var start := -1
		for x in range(1, rogue.grid_width):
			var active: bool = x < rogue.grid_width - 1 and rogue.corruption[rogue.idx(x, y)] != 0 and rogue.cells[rogue.idx(x, y)] in [Game.FREE, Game.TRAIL]
			if active and start < 0: start = x
			elif not active and start >= 0:
				strokes.append(rogue.center(Vector2i(start, y)) - Vector2(rogue.FX + 3, rogue.FY))
				strokes.append(rogue.center(Vector2i(x - 1, y)) - Vector2(rogue.FX - 3, rogue.FY))
				start = -1
	return strokes

func check_strokes() -> void:
	main.display.begin_draw()
	rogue.draw_play()
	assert(not rogue.corruption_visual_dirty)
	assert(rogue.corruption_strokes == expected_strokes(), "Cached strokes must match uncached rendering after every mutation")

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	var random := RandomNumberGenerator.new()
	random.seed = 71031
	for game in [main.game, rogue]:
		for sector in range(1, 9):
			if game == rogue: fresh_ship("surveyor")
			game.level = sector
			game.start_level()
			compare_grid(game)
			# Include coast edges, diagonal contacts, live lines and hardened cells.
			for i in 500: game.cells[random.randi_range(0, game.cells.size() - 1)] = random.randi_range(0, 4)
			compare_grid(game)
		var saved_gal: Dictionary = game.gal
		var saved_state: Game.State = game.state
		game.state = Game.State.PLAYING
		for galaxy in Galaxies.LIST:
			game.gal = galaxy
			compare_grid(game)
		game.gal = saved_gal
		game.state = saved_state
		for state in [Game.CLAIMED, Game.FREE, Game.ROCK, Game.HARD]:
			game.cells.fill(state)
			compare_grid(game)
	fresh_ship("surveyor")
	rogue.level = 8
	rogue.start_level()
	rogue.state = Game.State.PLAYING
	rogue.phase = "run"
	rogue.corruption_active = true
	check_strokes()
	for step in 20:
		var expected := reference_spread()
		rogue.spread_corruption()
		assert(rogue.corruption == expected, "Spread cannot jump rows, cross walls, or grow multiple cells per tick")
		check_strokes()
	# Clean Sweep and claimed territory both invalidate the visual cache.
	var claims: Array[int] = []
	for i in rogue.cells.size():
		if rogue.corruption[i] != 0:
			rogue.cells[i] = Game.CLAIMED
			claims.append(i)
			if claims.size() >= 25: break
	rogue.grid_changed()
	rogue.on_claim(claims.size(), 0)
	check_strokes()
	rogue.clean_near_claim(claims, 6)
	check_strokes()
	# Hardening can alter visibility between captures, without grid_changed().
	var c := Vector2i(100, 60)
	rogue.cells[rogue.idx(c.x, c.y)] = Game.TRAIL
	rogue.cells[rogue.idx(c.x + 1, c.y)] = Game.TRAIL
	rogue.corruption[rogue.idx(c.x, c.y)] = 1
	rogue.corruption_visual_dirty = true
	rogue.trail.assign([c, c + Vector2i.RIGHT])
	rogue.drawing = true
	rogue.wall_building = false
	rogue.hardening_time = 3
	rogue.harden_len = 0
	check_strokes()
	rogue.update_movement_module(0.2)
	assert(rogue.cells[rogue.idx(c.x, c.y)] == Game.HARD)
	check_strokes()
	rogue.owned_cards.assign(["anchor"])
	rogue.invuln = 0
	rogue.cooldowns.anchor = 0
	rogue.die("TEST RECOVERY")
	check_strokes()
	fresh_ship("surveyor")
	assert(not rogue.corruption_active)
	rogue.rebuild_corruption_strokes()
	assert(rogue.corruption_strokes.is_empty(), "Restart cannot retain prior-sector corruption visuals")
	print("ROGUELITE OPTIMIZATION OK: exact border/coast/pixel parity, one-step spread, cache invalidation after capture/cleansing/hardening/recovery/restart")
	get_tree().quit()
