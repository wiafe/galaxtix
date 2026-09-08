extends Node

func _ready() -> void:
	call_deferred("check_options")

func check_options() -> void:
	assert(not Save.enabled, "Run with --nosave")
	var main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var game: Game = main.game
	var options = main.options
	assert(game.TITLE_ITEMS.has("OPTIONS"))
	assert(not game.TITLE_ITEMS.has("RESET") and not game.TITLE_ITEMS.has("RESPEC"))
	game.title_sel = game.TITLE_ITEMS.find("OPTIONS")
	game.activate_title_item()
	assert(options.is_open and not game.is_processing_input())
	assert(options.CATEGORIES.size() == 4)
	for key in options.preferences.EFFECTS:
		options._change(key, false)
	assert(not main.display.env.glow_enabled)
	assert(main.display.lines.wobble == 0.0 and main.display.lines.spike_mult == 0.0)
	assert(main.display.trail_a.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	assert(main.display.screen.material.get_shader_parameter("scan_depth") == 0.0)
	for key in options.preferences.EFFECTS:
		options._change(key, true)
	assert(main.display.settings.crt_curve == options.baseline.crt_curve)
	assert(main.display.trail_a.render_target_update_mode == SubViewport.UPDATE_ALWAYS)
	options._change("volume", 0)
	assert(AudioServer.is_bus_mute(0))
	options._change("volume", 50)
	assert(not AudioServer.is_bus_mute(0))
	assert(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.5)))
	var temporary := "/tmp/galaxtix-options-smoke.cfg"
	assert(options.preferences.write_settings(temporary) == OK)
	var reloaded = load("res://scripts/player_settings.gd").new()
	reloaded.read_settings(temporary)
	assert(reloaded.values.volume == 50)
	assert(reloaded.values == options.preferences.values)
	DirAccess.remove_absolute(temporary)
	Save.data.flux = 73
	options._confirm("Reset", "Test", func(): Save.reset_data())
	options.resolve_confirmation()
	assert(Save.data.flux == 73)
	options._confirm("Reset", "Test", func(): Save.reset_data())
	options.confirm_selection = 1
	options.resolve_confirmation()
	assert(Save.data.flux == 0)
	options.select_category(1)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_RIGHT
	key.pressed = true
	options._input(key)
	assert(not options.preferences.values.glow, "Arrow adjusts selected effect")
	options._input(key)
	assert(options.preferences.values.glow)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = options.category_rect(2).get_center()
	options._input(mouse)
	assert(options.category == 2)
	mouse.position = Vector2(1270, options.row_rect(0).get_center().y)
	options._input(mouse)
	assert(options.preferences.values.volume == 50)
	options.close()
	assert(not options.is_open and game.is_processing_input())
	if OS.get_cmdline_user_args().has("--visual"):
		options.open()
		main.fill.visible = false
		for index in 4:
			options.select_category(index)
			main.display.begin_draw()
			options.draw()
			main.display.end_draw()
			for frame in 8:
				await get_tree().process_frame
			await main.display.screenshot("/tmp/options-%d.png" % index)
		options._confirm("RESET JUMP SAVE?", "DELETE ALL JUMP CURRENCIES, UPGRADES, SHIPS AND RECORDS.\nROGUELITE AND OPTIONS ARE KEPT. THIS CANNOT BE UNDONE.", func(): pass)
		main.display.begin_draw()
		options.draw()
		main.display.end_draw()
		for frame in 8:
			await get_tree().process_frame
		await main.display.screenshot("/tmp/options-confirm.png")
	print("OPTIONS SMOKE PASS")
	get_tree().quit()
