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
	# Respec refunds every level at its purchase price; reset wipes to factory defaults.
	save.data.flux = 0.0
	save.data.upgrades = {"thrust": 2}
	save.data.ships = {"leaper": true}
	save.data.ship_upgrades = {"leaper:stride": 1, "bogus:thing": 3}
	var expect: float = round(float(save.def("thrust").base)) + round(float(save.def("thrust").base) * float(save.def("thrust").growth)) + round(float(Ships.up_def("leaper", "stride").base))
	assert(is_equal_approx(save.respec(), expect), "Respec refunds each purchased level")
	assert(is_equal_approx(float(save.data.flux), expect) and save.data.upgrades.is_empty() and save.data.ship_upgrades.is_empty())
	assert(save.data.ships.has("leaper"), "Ships are kept on respec")
	save.data.isotope = 7
	save.data.galaxy_best = {"helix": 5}
	save.reset_data()
	assert(int(save.data.isotope) == 0 and save.data.galaxy_best.is_empty() and save.data.ships.is_empty() and float(save.data.flux) == 0.0)
	game.go_dock()
	# Every ship's complete upgrade list remains reachable and visible.
	for ship in Ships.LIST:
		save.data.ship = ship.id
		for row in range(game.dock_rows() - 1):
			game.dock_tab = 1 if row >= Game.DOCK_FIXED_ROWS and row < game.dock_rows() - 1 else 0
			game.dock_sel = row
			main.display.begin_draw()
			game.draw_dock_panel()
			assert(main.display.lines.count < ScopeLines.MAX_SEGS)
			if row >= Game.DOCK_FIXED_ROWS and row < game.dock_rows() - 1:
				var upgrade := row - Game.DOCK_FIXED_ROWS
				assert(upgrade >= game.dock_upgrade_scroll)
				assert(upgrade < game.dock_upgrade_scroll + 6)
	# Sector selection stops at the next unsecured sector.
	game.dock_tab = 0
	game.dock_sel = 1
	save.data.galaxy = "helix"
	save.data.galaxy_best.helix = 3
	save.data.start_sector = 3
	await press_dock(game, "move_right")
	assert(int(save.data.start_sector) == 4 and game.dock_sel == 1)
	await press_dock(game, "move_right")
	assert(int(save.data.start_sector) == 4)
	main.display.begin_draw()
	game.draw_dock_field()
	assert(main.display.lines.count < ScopeLines.MAX_SEGS)
	save.data.galaxy_clear.helix = true
	save.data.galaxy_best.helix = 8
	save.data.start_sector = 8
	await press_dock(game, "move_right")
	assert(int(save.data.start_sector) == 9)
	main.display.begin_draw()
	game.draw_dock_field()
	save.data.galaxy_clear.clear()
	save.data.galaxy_best.clear()
	save.data.start_sector = 1
	# Enter advances, Escape reverses, and Space cannot skip earlier decisions.
	game.dock_sel = 0
	await press_dock(game, "launch")
	assert(game.dock_sel == 0 and game.state == Game.State.DOCK)
	save.data.galaxy = "deep"
	await press_dock(game, "confirm")
	assert(game.dock_sel == 0)
	save.data.galaxy = "helix"
	await press_dock(game, "confirm")
	assert(game.dock_sel == 1)
	await press_dock(game, "confirm")
	assert(game.dock_sel == 2)
	await press_dock(game, "abort")
	assert(game.dock_sel == 1 and save.data.galaxy == "helix")
	await press_dock(game, "abort")
	assert(game.dock_sel == 0)
	await press_dock(game, "tab")
	assert(game.dock_tab == 0 and game.dock_sel == 0)
	# Tabs preserve each selection and exclude upgrades from the launch flow.
	game.dock_tab = 0
	game.dock_sel = 2
	await press_dock(game, "move_down")
	assert(game.dock_sel == 2)
	await press_dock(game, "tab")
	assert(game.dock_tab == 1 and game.dock_sel >= Game.DOCK_FIXED_ROWS)
	game.dock_sel = game.dock_rows() - 2
	await press_dock(game, "abort")
	assert(game.dock_tab == 0 and game.state == Game.State.DOCK)
	assert(game.dock_sel == 2)
	await press_dock(game, "tab")
	assert(game.dock_sel == game.dock_rows() - 2)
	# Progress guidance changes at the galaxy unlock and boss milestones.
	save.data.galaxy = "helix"
	assert(game.dock_progress_hint().is_empty())
	save.data.galaxy_best.helix = Galaxies.UNLOCK_AT
	assert(Galaxies.unlocked("belt"))
	assert(game.dock_progress_hint().contains("TWIN HELIX"))
	save.data.galaxy_clear.helix = true
	assert(game.dock_progress_hint().contains("ENDLESS"))
	save.data.galaxy_clear.clear()
	save.data.galaxy_best.clear()
	# Unlocking a ship does not launch it until the next confirmation.
	game.dock_tab = 0
	game.dock_sel = 2
	save.data.ship = "sapper"
	await press_dock(game, "launch")
	assert(game.state == Game.State.DOCK and not Ships.owned("sapper"))
	save.data.isotope = 8
	await press_dock(game, "confirm")
	assert(Ships.owned("sapper") and game.state == Game.State.DOCK)
	await press_dock(game, "confirm")
	assert(game.state == Game.State.TRANSIT)
	game.go_dock()
	game.dock_sel = 2
	game.switch_dock_tab()
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
	# A locked destination blocks launch; an owned ship in an open galaxy launches.
	game.dock_tab = 0
	game.dock_sel = 2
	save.data.ship = "surveyor"
	save.data.galaxy = "deep"
	await press_dock(game, "launch")
	assert(game.state == Game.State.DOCK)
	save.data.galaxy = "helix"
	game.dock_sel = 2
	await press_dock(game, "confirm")
	assert(game.state == Game.State.TRANSIT)
	game.go_dock()
	assert(game.dock_tab == 0 and game.dock_sel == 0)
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
	# Result actions preserve the wallet and skip straight to the requested destination.
	var balance: float = save.data.flux
	game.activate_result(0)
	assert(game.state == Game.State.DOCK and game.dock_tab == 1 and game.dock_loadout_sel == 2)
	save.data.start_sector = 1
	game.level = 4
	game.state = Game.State.OUTRO
	game.seq_t = Game.OUTRO_CARD_T + 2.0
	var click := InputEventMouseButton.new()
	click.position = game.result_button(1).get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	game._input(click)
	assert(game.state == Game.State.TRANSIT or game.state == Game.State.INTRO)
	assert(game.run_flux == 0 and save.data.flux == balance)
	assert(game.level == 4 and save.data.start_sector == 1, "Restart retries the lost sector")
	game.level = 12
	game.activate_result(1)
	assert(game.level == 12 and game.endless, "Endless retries preserve the lost sector too")
	print("PASS: step navigation, backtracking, unlock-before-launch, tabs, progression milestones, dock rows, locked launch, purchase, preview invalidation, text geometry and cache bound")
	get_tree().quit()

func press_dock(game: Game, action: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_press(action)
	game.update_dock()
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame
