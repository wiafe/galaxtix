extends "res://tests/roguelite_ships_smoke.gd"

func prepared_run() -> void:
	rogue.progress.apply_profile({"version": 8, "salvage": 10, "salvage_fraction": 0.25, "runs": 2, "wins": 1, "best_sector": 3, "containment_unlocked": false})
	fresh_ship("surveyor")
	rogue.earned_salvage = 7
	rogue.salvage_fraction = 0.9
	rogue.progress.best_sector = 12
	rogue.progress.containment_unlocked = true
	rogue.owned_cards.assign(["hardlight"])
	rogue.card_ranks = {"hardlight": 1}

func press(action: String) -> void:
	await get_tree().process_frame
	rogue.ui_time = rogue.choice_delay() + 1.0
	Input.action_press(action)
	rogue.update_choices()
	Input.action_release(action)
	await get_tree().process_frame

func assert_forfeited() -> void:
	assert(rogue.settled and rogue.run_abandoned and not rogue.run_victory)
	assert(rogue.phase == "result" and rogue.banked_salvage == 0 and rogue.earned_salvage == 0)
	assert(rogue.progress.salvage == 10 and is_equal_approx(rogue.progress.salvage_fraction, 0.25), "Prior balance and fractional earnings survive; this run adds nothing")
	assert(rogue.progress.best_sector == 3 and not rogue.progress.containment_unlocked, "Abandonment cannot unlock later-run progression")
	assert(rogue.owned_cards.is_empty() and rogue.card_ranks.is_empty())
	assert(rogue.progress.runs == 3 and rogue.progress.wins == 1)
	rogue.end_run()
	rogue.abandon_run()
	assert(rogue.progress.salvage == 10 and rogue.progress.runs == 3, "Repeated exit cannot pay or settle twice")

func pad_press(code: JoyButton) -> void:
	await get_tree().process_frame
	rogue.ui_time = rogue.choice_delay() + 1.0
	var pad := InputEventJoypadButton.new()
	pad.device = 3
	pad.button_index = code
	pad.pressed = true
	Input.parse_input_event(pad)
	Input.flush_buffered_events()
	rogue.update_choices()
	var release := pad.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			shot_dir = arg.substr(14)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	for source in ["paused", "chart", "sector_clear"]:
		prepared_run()
		rogue.phase = source
		rogue.ui_time = 5.0
		if source == "paused": rogue.activate_choice(1)
		else: await press("abort")
		assert(rogue.phase == "abandon" and rogue.selection == 0 and not rogue.settled)
		assert(rogue.progress.salvage == 10 and rogue.earned_salvage == 7)
		var position: Vector2 = rogue.qixes[0].c
		rogue.update(0.1)
		assert(rogue.qixes[0].c == position, "Confirmation cannot advance the encounter")
		await press("abort")
		assert(rogue.phase == source and rogue.earned_salvage == 7 and rogue.owned_cards == ["hardlight"])
		rogue.request_abandon()
		await shot("abandon-confirmation")
		rogue.ui_time = 1.0
		if source == "paused":
			click(rogue.choice_rect(1).get_center())
		else:
			await press("move_right")
			await press("confirm")
		assert_forfeited()
		await shot("abandon-result")
	# An unfinished race loses earnings from earlier sectors too.
	prepared_run()
	rogue.active_destination = {"depth": 1, "kind": "race", "stage": 1}
	rogue.abandon_run()
	assert_forfeited()
	prepared_run()
	rogue.phase = "paused"
	rogue.request_abandon()
	await pad_press(JOY_BUTTON_B)
	assert(rogue.phase == "paused" and not rogue.settled)
	rogue.request_abandon()
	await pad_press(JOY_BUTTON_DPAD_RIGHT)
	await pad_press(JOY_BUTTON_A)
	assert_forfeited()
	# Failed saves may be retried without restoring forfeited currency.
	prepared_run()
	var failed := FailedProfile.new()
	failed.apply_profile({"version": 8, "salvage": 10, "salvage_fraction": 0.25, "runs": 2, "wins": 1, "best_sector": 12, "containment_unlocked": true})
	rogue.progress = failed
	rogue.abandon_run()
	assert(rogue.save_failed)
	rogue.ui_time = 1.0
	rogue.activate_choice(0)
	assert(rogue.save_failed and rogue.progress.salvage == 10 and rogue.progress.runs == 3)
	rogue.progress = Progress.new()
	# Legitimate death and victory still settle their rewards exactly once.
	for won in [false, true]:
		prepared_run()
		rogue.run_victory = won
		rogue.lives = 2 if won else -1
		rogue.end_run()
		assert(not rogue.run_abandoned and rogue.banked_salvage == 7 and rogue.progress.salvage == 17)
		assert(is_equal_approx(rogue.progress.salvage_fraction, 0.9))
		assert(rogue.progress.wins == (2 if won else 1))
		rogue.abandon_run()
		rogue.end_run()
		assert(rogue.progress.salvage == 17 and rogue.progress.runs == 3)
	print("ABANDON PASS: pause/chart/sector-clear exits, cancel, frozen confirmation, mouse/keyboard/controller, full forfeiture, failed save, death/victory payouts")
	get_tree().quit()
