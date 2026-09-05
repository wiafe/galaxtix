extends Node
## godot --headless --path . res://tests/dock_smoke.tscn -- --nosave

func _ready() -> void:
	call_deferred("check_dock")

func check_dock() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var game: Game = main.game
	var save = get_tree().root.get_node("Save")
	assert(not save.enabled, "Run with --nosave")
	game.go_dock()
	# Every ship's complete upgrade list remains reachable and visible.
	for ship in Ships.LIST:
		save.data.ship = ship.id
		for row in game.dock_rows():
			game.dock_sel = row
			main.display.begin_draw()
			game.draw_dock_panel()
			assert(main.display.lines.count < ScopeLines.MAX_SEGS)
			if row >= Game.DOCK_FIXED_ROWS and row < game.dock_rows() - 1:
				var upgrade := row - Game.DOCK_FIXED_ROWS
				assert(upgrade >= game.dock_upgrade_scroll)
				assert(upgrade < game.dock_upgrade_scroll + 6)
	# Locked ships cannot silently launch as Surveyor.
	save.data.ship = "sapper"
	Input.action_press("launch")
	game.update_dock()
	Input.action_release("launch")
	assert(game.state == Game.State.DOCK)
	await get_tree().process_frame
	await get_tree().process_frame
	# The last ship-specific upgrade can still be purchased after scrolling.
	save.data.ships.sapper = true
	save.data.flux = 100
	game.dock_sel = game.dock_rows() - 2
	Input.action_press("confirm")
	game.update_dock()
	Input.action_release("confirm")
	assert(Ships.up_level("sapper", "insul") == 1)
	await get_tree().process_frame
	await get_tree().process_frame
	# Rim purchases invalidate the sector preview.
	game.update(0.016)
	var key := game.pane_key
	save.data.upgrades.bulk = 1
	game.update(0.016)
	assert(game.pane_key != key)
	# Cached text must match the original outline renderer at each alignment.
	var lines: ScopeLines = main.display.lines
	for align in 3:
		for tracking in [1.0, 1.3]:
			VectorFont.tracking = tracking
			var pos := Vector2(427, 218)
			lines.begin()
			for pts in VectorFont.paths("SURVEYOR 123", pos, 16, align):
				lines.polyline(pts, false, Palette.CYAN)
			var expected := lines.buf.slice(0, lines.count * ScopeLines.STRIDE)
			lines.begin()
			VectorFont.draw(lines, "SURVEYOR 123", pos, 16, Palette.CYAN, 0, 0, align)
			assert(expected.size() == lines.count * ScopeLines.STRIDE)
			for i in expected.size():
				assert(absf(expected[i] - lines.buf[i]) < 0.001)
	VectorFont.tracking = 1.0
	for i in VectorFont.DRAW_CACHE_LIMIT + 20:
		lines.begin()
		VectorFont.draw(lines, str(i), Vector2.ZERO, 12, Palette.WHITE)
	assert(VectorFont._draw_cache.size() <= VectorFont.DRAW_CACHE_LIMIT)
	print("PASS: dock rows, locked launch, purchase, preview invalidation, text geometry and cache bound")
	get_tree().quit()
