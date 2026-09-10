extends Node
## Real joypad events exercise the engine InputMap and the menus, without hardware.
const PAD := 3 # Bindings must work on devices other than player zero.

func _ready() -> void:
	call_deferred("check")

func button(code: JoyButton, pressed := true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = PAD
	event.button_index = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func axis(code: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = PAD
	event.axis = code
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: JoyButton) -> void:
	button(code)
	button(code, false)

func check() -> void:
	assert(not Save.enabled, "Run with --nosave")
	assert(not Input.ignore_joypad_on_unfocused_application, "Keep Godot's default controller focus policy for embedded play")
	var main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var game: Game = main.game
	var options = main.options
	var binding_count := InputMap.action_get_events("draw").size()
	Controls.setup_actions()
	assert(InputMap.action_get_events("draw").size() == binding_count)
	print("CONNECTED CONTROLLERS: ", Input.get_connected_joypads())
	await get_tree().process_frame
	game.title_t = 2.0
	game.title_sel = 0
	button(JOY_BUTTON_DPAD_DOWN)
	game.update_title(0.016)
	assert(game.title_sel == 1, "D-pad navigates the title")
	button(JOY_BUTTON_DPAD_DOWN, false)
	await get_tree().process_frame
	game.title_sel = game.TITLE_ITEMS.find("OPTIONS")
	button(JOY_BUTTON_A)
	game.update_title(0.016)
	button(JOY_BUTTON_A, false)
	assert(options.is_open and not options.settings_focused, "Opening options does not also enter settings")
	tap(JOY_BUTTON_DPAD_DOWN)
	assert(options.category == 1)
	tap(JOY_BUTTON_A)
	assert(options.settings_focused and options.preferences.values.glow)
	tap(JOY_BUTTON_A)
	assert(not options.preferences.values.glow)
	tap(JOY_BUTTON_A)
	assert(options.preferences.values.glow)
	tap(JOY_BUTTON_DPAD_LEFT)
	assert(not options.settings_focused and options.preferences.values.glow)
	await get_tree().process_frame
	axis(JOY_AXIS_LEFT_Y, 0.1)
	assert(options.category == 1, "Stick drift does not navigate")
	axis(JOY_AXIS_LEFT_Y, 0.8)
	assert(options.category == 2, "Stick enters the next category once")
	axis(JOY_AXIS_LEFT_Y, 0.9)
	assert(options.category == 2, "Repeated motion while held does not skip rows")
	await get_tree().process_frame
	axis(JOY_AXIS_LEFT_Y, 0.85)
	assert(options.category == 2, "Holding across frames does not repeat")
	axis(JOY_AXIS_LEFT_Y, 0.0)
	tap(JOY_BUTTON_A)
	tap(JOY_BUTTON_A)
	assert(options.adjusting_value)
	var volume: int = options.preferences.values.volume
	axis(JOY_AXIS_LEFT_X, -0.8)
	assert(options.preferences.values.volume == volume - 5)
	axis(JOY_AXIS_LEFT_X, 0.0)
	tap(JOY_BUTTON_A)
	tap(JOY_BUTTON_DPAD_LEFT)
	tap(JOY_BUTTON_DPAD_DOWN)
	assert(options.category == 3 and not options.settings_focused)
	tap(JOY_BUTTON_A)
	tap(JOY_BUTTON_A)
	assert(options.pending_action.is_valid() and options.confirm_selection == 0)
	tap(JOY_BUTTON_B)
	assert(not options.pending_action.is_valid() and options.settings_focused)
	tap(JOY_BUTTON_B)
	tap(JOY_BUTTON_B)
	assert(not options.is_open)
	await get_tree().process_frame
	axis(JOY_AXIS_LEFT_X, 0.45)
	axis(JOY_AXIS_LEFT_Y, -0.9)
	assert(game.read_input().dir == Vector2i.UP, "Dominant stick axis determines cardinal movement")
	button(JOY_BUTTON_A)
	button(JOY_BUTTON_LEFT_SHOULDER)
	assert(game.read_input().draw and game.read_input().slow)
	button(JOY_BUTTON_A, false)
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	assert(not game.read_input().draw and not game.read_input().slow)
	for trigger in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		axis(trigger, 0.1)
		assert(not game.read_input().draw)
		axis(trigger, 1.0)
		assert(game.read_input().draw)
		axis(trigger, 0.0)
		assert(not game.read_input().draw, "Releasing a trigger releases charge/draw")
	var royale := BattleRoyale.new()
	royale.start(123)
	button(JOY_BUTTON_Y)
	button(JOY_BUTTON_X)
	royale.poll_local_input()
	assert(royale.racer(0).intent_dir == Vector2i.UP)
	assert(royale.racer(0).want_harden and royale.racer(0).want_drive)
	assert(game.read_input().special)
	button(JOY_BUTTON_Y, false)
	button(JOY_BUTTON_X, false)
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	assert(game.read_input().dir == Vector2i.ZERO)
	await get_tree().process_frame
	game.go_dock()
	button(JOY_BUTTON_A)
	game.update_dock()
	button(JOY_BUTTON_A, false)
	assert(game.dock_sel == 1, "Controller advances the dock flow")
	await get_tree().process_frame
	button(JOY_BUTTON_B)
	game.update_dock()
	button(JOY_BUTTON_B, false)
	assert(game.dock_sel == 0)
	game.start_roguelite()
	var rogue = game.roguelite
	rogue.transit_skip = true
	rogue.start_run()
	rogue.launch_destination(0)
	rogue.state = Game.State.PLAYING
	rogue.phase = "run"
	await get_tree().process_frame
	button(JOY_BUTTON_START)
	rogue.update(0.016)
	button(JOY_BUTTON_START, false)
	assert(rogue.phase == "paused", "Start pauses roguelite gameplay")
	rogue.ui_time = 1.0
	await get_tree().process_frame
	button(JOY_BUTTON_B)
	rogue.update(0.016)
	button(JOY_BUTTON_B, false)
	assert(rogue.phase == "run", "Back resumes the paused run")
	rogue.phase = "draft"
	rogue.opening_draft_pending = false
	rogue.ui_time = 10.0
	rogue.rerolls_left = 1
	tap(JOY_BUTTON_Y)
	assert(rogue.rerolls_left == 0 and rogue.ui_time == 0.0, "Controller can rescan a draft")
	await check_jump_ships(game)
	await check_roguelite_ships(game)
	await check_royale_round(game)
	Controls.using_controller = true
	Controls.controller_family = "xbox"
	assert(Controls.hint("ARROWS ENTER SPACE SHIFT ESC") == "D-PAD/STICK A A LB B")
	Controls.controller_family = "playstation"
	assert(Controls.hint("ENTER ESC") == "CROSS CIRCLE")
	Controls.controller_family = "nintendo"
	assert(Controls.hint("ENTER ESC") == "B A")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_UP
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	assert(not Controls.using_controller and Input.is_action_pressed("move_up"))
	var released := key.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	Input.flush_buffered_events()
	assert(Controls.hint("ENTER ESC") == "ENTER ESC")
	Controls.use_controller(PAD)
	Controls._controller_connection_changed(PAD, false)
	assert(not Controls.using_controller)
	royale = null
	if OS.get_cmdline_user_args().has("--visual"):
		Controls.using_controller = true
		Controls.controller_family = "playstation"
		options.open()
		options.select_category(1)
		options.settings_focused = true
		main.fill.visible = false
		await shot(main, options.draw, "controller-options")
		options.close()
		rogue.phase = "draft"
		rogue.ui_time = 10.0
		rogue.rerolls_left = 1
		await shot(main, rogue.draw_draft, "controller-draft")
	print("CONTROLLER SMOKE PASS")
	get_tree().quit()

func shot(main: Node, draw_frame: Callable, name: String) -> void:
	for frame in 12:
		main.display.tick(0.016)
		main.display.begin_draw()
		draw_frame.call()
		main.display.end_draw()
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/" + name + ".png")

func prepare_coast(game: Game) -> void:
	game.state = Game.State.PLAYING
	game.invuln = 100.0
	game.qixes.clear()
	game.sparxes.clear()
	game.sparx_to_spawn = 0
	game.mites.clear()
	game.spawners.clear()
	game.draw_armed = true
	game.last_dir = Vector2i.DOWN
	var x := game.grid_width / 2
	for y in range(1, game.grid_height - 1):
		if game.cells[game.idx(x, y)] == Game.CLAIMED and game.cells[game.idx(x, y + 1)] == Game.FREE:
			game.p = Vector2i(x, y)
			game.vis = game.center(game.p)
			return
	assert(false, "Fixture needs a coast facing down into free space")

func check_jump_ships(game: Game) -> void:
	for ship in Ships.LIST:
		await get_tree().process_frame
		Save.data.ships[ship.id] = true
		Save.data.ship = ship.id
		game.transit_skip = true
		game.start_run()
		prepare_coast(game)
		var start := game.p
		axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
		if ship.id in ["surveyor", "bulwark"]:
			button(JOY_BUTTON_DPAD_DOWN)
		for step in 6:
			game.update(0.05)
		match ship.id:
			"surveyor", "bulwark":
				assert(game.drawing and game.p != start, "Trigger + D-pad must draw in Jump with " + ship.id)
			"leaper": assert(game.leap_building, "Trigger must aim the Jump Leaper")
			"lancer": assert(game.tether_active, "Trigger must fire the Jump Lancer")
			"sapper": assert(game.sap_live, "Trigger must charge the Jump Sapper")
		axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		button(JOY_BUTTON_DPAD_DOWN, false)
		game.update(0.05)
		if ship.id == "leaper": assert(game.wall_building, "Trigger release must launch the Leaper wall")
		if ship.id == "sapper": assert(not game.sap_live, "Trigger release must detonate the Sapper")
		if ship.id == "bulwark": assert(game.braced, "Trigger release must brace the Bulwark")
	await get_tree().process_frame
	button(JOY_BUTTON_B)
	game.update(0.016)
	button(JOY_BUTTON_B, false)
	assert(game.state == Game.State.OUTRO, "Controller can end a Jump run")
	game.seq_t = game.OUTRO_CARD_T + 1.1
	game.result_selection = 0
	await get_tree().process_frame
	button(JOY_BUTTON_A)
	game.update(0.016)
	button(JOY_BUTTON_A, false)
	assert(game.state == Game.State.DOCK, "Controller can return from Jump results to upgrades")
	print("CONTROLLER JUMP: all five ship actions, release behavior and results PASS")

func check_roguelite_ships(game: Game) -> void:
	game.start_roguelite()
	var rogue = game.roguelite
	for id in ["surveyor", "lancer", "bulwark"]:
		await get_tree().process_frame
		rogue.progress.ships[id] = true
		rogue.progress.selected_ship = id
		rogue.start_run()
		# Start the selected chart destination through the real controller path.
		rogue.ui_time = 10.0
		button(JOY_BUTTON_A)
		rogue.update(0.016)
		button(JOY_BUTTON_A, false)
		assert(rogue.phase == "run", "Controller launches a roguelite destination")
		prepare_coast(rogue)
		rogue.opening_draft_pending = false
		rogue.owned_cards.assign(["leap", "afterburner"])
		rogue.card_ranks = {"leap": 1, "afterburner": 1}
		await get_tree().process_frame
		button(JOY_BUTTON_A)
		if id in ["surveyor", "bulwark"]: button(JOY_BUTTON_DPAD_DOWN)
		for step in 5: rogue.update(0.05)
		match id:
			"surveyor": assert(rogue.drawing, "Controller draws with roguelite Surveyor")
			"lancer": assert(rogue.tether_active, "Controller fires roguelite Lancer")
			"bulwark": assert(rogue.drawing, "Controller draws with roguelite Bulwark")
		button(JOY_BUTTON_A, false)
		button(JOY_BUTTON_DPAD_DOWN, false)
		rogue.update(0.05)
		# Reset the arena before testing a coast-launched movement ability.
		rogue.start_level()
		prepare_coast(rogue)
		await get_tree().process_frame
		button(JOY_BUTTON_Y)
		rogue.update(0.2)
		assert(rogue.leap_building and not rogue.sap_live and not rogue.tether_active, "Opening ability must stay separate from native action on " + id)
		button(JOY_BUTTON_Y, false)
		rogue.update(0.05)
		assert(rogue.wall_building, "Opening ability releases correctly on " + id)
		await get_tree().process_frame
		button(JOY_BUTTON_RIGHT_SHOULDER)
		rogue.update(0.016)
		button(JOY_BUTTON_RIGHT_SHOULDER, false)
		assert(rogue.boost_time > 0, "Controller activates the secondary ability on " + id)
		rogue.start_level()
		prepare_coast(rogue)
		rogue.owned_cards.assign(["charge"])
		await get_tree().process_frame
		button(JOY_BUTTON_Y)
		for step in 15: rogue.update(0.1)
		assert(rogue.sap_live and not rogue.drawing and not rogue.tether_active)
		button(JOY_BUTTON_Y, false)
		rogue.update(0.05)
		assert(not rogue.sap_live and rogue.capture_percent > 0 and rogue.cooldowns.charge > 0, "Controller charge releases into capture on " + id)
	print("CONTROLLER ROGUELITE: chart launch, all three ships and ability separation PASS")

func check_royale_round(game: Game) -> void:
	game.start_battle_royale()
	await get_tree().process_frame
	button(JOY_BUTTON_A)
	game.update(0.016)
	button(JOY_BUTTON_A, false)
	assert(game.battle.phase == "playing", "Controller starts a Royale round")
	var player = game.battle.racer(0)
	player.pos = player.rail[1]
	var start: Vector2i = player.pos
	var direction: Vector2i = player.rail[2] - start
	axis(JOY_AXIS_LEFT_X, direction.x)
	axis(JOY_AXIS_LEFT_Y, direction.y)
	for step in 3: game.update(0.05)
	assert(player.pos != start, "Controller actually moves the Royale player")
	axis(JOY_AXIS_LEFT_X, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	await get_tree().process_frame
	button(JOY_BUTTON_Y)
	button(JOY_BUTTON_X)
	game.update(0.016)
	button(JOY_BUTTON_Y, false)
	button(JOY_BUTTON_X, false)
	assert(player.harden > 0 and player.drive > 0, "Royale abilities are applied by the real game loop")
	game.battle.remaining = 0.0
	game.update(0.016)
	assert(game.battle.phase == "results")
	game.battle.phase_time = 0.5
	await get_tree().process_frame
	button(JOY_BUTTON_A)
	game.update(0.016)
	button(JOY_BUTTON_A, false)
	assert(game.battle.reveal_complete(), "Controller skips Royale standings reveal")
	await get_tree().process_frame
	button(JOY_BUTTON_A)
	game.update(0.016)
	button(JOY_BUTTON_A, false)
	assert(game.battle.phase == "ready", "Controller continues or restarts after Royale results")
	await get_tree().process_frame
	button(JOY_BUTTON_B)
	game.update(0.016)
	button(JOY_BUTTON_B, false)
	assert(game.state == Game.State.TITLE, "Controller leaves Royale")
	print("CONTROLLER ROYALE: start, movement, both abilities, results and exit PASS")
