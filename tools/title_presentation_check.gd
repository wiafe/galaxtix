extends Node
var main

func _ready() -> void:
	call_deferred("check")

func check() -> void:
	assert(not Save.enabled)
	main = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	if "--title-small" in OS.get_cmdline_user_args(): DisplayServer.window_set_size(Vector2i(1280, 720))
	var game: Game = main.game
	game.title_t = 3.0
	game.draw()
	assert(game.TITLE_ITEMS[0] == "ROGUELITE")
	assert(game.title_wordmark.visible and game.title_backdrop.visible and not main.fill.visible)
	var background = game.title_backdrop
	for i in game.TITLE_ITEMS.size():
		assert(game.title_item_rect(i).end.x < 800)
		assert(game.title_item_rect(i).end.y < 800)
		if i > 0: assert(not game.title_item_rect(i).intersects(game.title_item_rect(i - 1)))
	if "--title-shots" in OS.get_cmdline_user_args():
		await shot("title")
		game.title_t = 14
		await shot("title-light")
		if "--title-motifs" in OS.get_cmdline_user_args():
			for item in game.TITLE_ITEMS:
				var hover := InputEventMouseMotion.new()
				hover.position = game.title_item_rect(game.TITLE_ITEMS.find(item)).get_center()
				game._input(hover)
				assert(game.TITLE_ITEMS[game.title_sel] == item)
				await shot("title-motif-" + item.to_lower().replace(" ", "-"))
				assert(game.title_motif_weights[game.TITLE_MOTIFS.find(item)] > 0.99)
		game.title_sel = game.TITLE_ITEMS.find("LOG")
		game.open_log()
		await shot("title-log")
		game.close_log()
	# The observed left menu hit targets must launch each mode and hide all title art.
	for name in ["ROGUELITE", "JUMP", "ARCADE", "BATTLE ROYALE"]:
		game.go_title()
		game.title_t = 3.0
		game.draw()
		var click := InputEventMouseButton.new()
		click.pressed = true
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = game.title_item_rect(game.TITLE_ITEMS.find(name)).get_center()
		game._input(click)
		game.update_title(0.6)
		game.draw()
		assert(game.state != Game.State.TITLE)
		assert(not background.visible and not game.title_wordmark.visible)
	game.go_title()
	game.title_t = 3
	await check_log(game)
	game.draw()
	game.title_sel = game.TITLE_ITEMS.find("OPTIONS")
	game.activate_title_item()
	assert(main.options.is_open)
	main._process(0.016)
	assert(background.visible and not game.title_wordmark.visible)
	if "--title-shots" in OS.get_cmdline_user_args(): await shot("title-options")
	main.options.close()
	main._process(0.016)
	assert(background == game.title_backdrop and background.visible and game.title_wordmark.visible)
	print("TITLE PRESENTATION PASS: left hit targets, mode launch/cleanup, Options backdrop, logo return")
	main.queue_free()
	get_tree().quit()

func check_log(game: Game) -> void:
	Save.data.runs = 999 # Jump records must never leak into the Roguelite Log.
	var profile = game.roguelite.get("progress")
	profile.apply_profile({"version": 8, "runs": 12, "wins": 3, "salvage": 42, "best_sector": 19,
		"ships": {"surveyor": true, "lancer": true}, "ranks": {"engines": 4, "hull": 2}})
	game.title_sel = game.TITLE_ITEMS.find("LOG")
	game.activate_title_item()
	game.draw()
	assert(game.title_log_stats == {"runs": 12, "wins": 3, "salvage": 42, "best_sector": 19, "ships": 2, "upgrades": 6})
	assert(game.show_log and not game.title_wordmark.visible)
	if "--title-shots" in OS.get_cmdline_user_args(): await shot("title-log-records")
	await get_tree().process_frame
	Input.action_press("move_down")
	game.update_title(0.016)
	Input.action_release("move_down")
	assert(game.TITLE_ITEMS[game.title_sel] == "LOG" and game.title_exit == -1)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game.title_item_rect(game.TITLE_ITEMS.find("QUIT")).get_center()
	game._input(click)
	assert(game.show_log and game.title_exit == -1, "Hidden menu cannot receive clicks")
	click.position = game.log_back_rect().get_center()
	game._input(click)
	assert(not game.show_log)
	for code in [KEY_ESCAPE, KEY_ENTER]:
		await get_tree().process_frame
		game.open_log()
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.pressed = true
		Input.parse_input_event(key)
		Input.flush_buffered_events()
		game.update_title(0.016)
		var key_release := key.duplicate()
		key_release.pressed = false
		Input.parse_input_event(key_release)
		assert(not game.show_log and game.title_exit == -1)
	for code in [JOY_BUTTON_B, JOY_BUTTON_A]:
		await get_tree().process_frame
		game.open_log()
		var pad := InputEventJoypadButton.new()
		pad.device = 3
		pad.button_index = code
		pad.pressed = true
		Input.parse_input_event(pad)
		Input.flush_buffered_events()
		game.update_title(0.016)
		var pad_release := pad.duplicate()
		pad_release.pressed = false
		Input.parse_input_event(pad_release)
		assert(not game.show_log and game.title_exit == -1)
	await get_tree().process_frame
	game.draw()
	assert(game.title_wordmark.visible and game.TITLE_ITEMS[game.title_sel] == "LOG")
	print("ROGUELITE LOG PASS: profile isolation, modal input, mouse/keyboard/controller Back")

func shot(name: String) -> void:
	for frame in 45:
		main._process(1.0 / 60)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var suffix := "-small" if "--title-small" in OS.get_cmdline_user_args() else ""
	get_viewport().get_texture().get_image().save_png("res://.godot/%s%s.png" % [name, suffix])
