extends "res://tests/roguelite_ships_smoke.gd"

func install_opening(ship_id: String, module: String) -> void:
	fresh_ship(ship_id)
	rogue.open_draft()
	assert(rogue.offers.map(func(card): return card.id) == Cards.OPENING)
	rogue.rerolls_left = 2
	rogue.ui_time = 1.0
	rogue.reroll_draft()
	assert(rogue.rerolls_left == 2 and rogue.offers.map(func(card): return card.id) == Cards.OPENING)
	rogue.choose_card(Cards.OPENING.find(module))
	assert(rogue.owned_cards == [module] and not rogue.opening_draft_pending)
	assert(rogue.ship.id == ship_id and rogue.drafts_taken == 1)
	rogue.roll_offers()
	for card in rogue.offers:
		assert(not Cards.OPENING.has(card.id) , "No duplicate movement binding while slots are filling")
	rogue.offers.clear()

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			shot_dir = arg.substr(14)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	rogue.progress.ships = {"surveyor": true, "lancer": true, "sapper": true}
	var campaign: Dictionary = Save.data.duplicate(true)
	for ship_id in ["surveyor", "lancer", "sapper"]:
		install_opening(ship_id, "hardening")
		if ship_id == "sapper":
			rogue.p = Vector2i(70, 43)
			rogue.start_sapper_charge()
			rogue.sap_charge = 3
			Input.action_press("draw")
			await tap("br_harden")
			assert(rogue.disc_braced and not rogue.wire_hit())
			assert(not rogue.disc_braced)
			rogue.hardlight_time = 0
			assert(rogue.wire_hit(), "Hardening absorbs only one disc contact")
			Input.action_release("draw")
		else:
			rogue.p = Vector2i(54, 46)
			rogue.vis = rogue.center(rogue.p)
			rogue.last_dir = Vector2i.RIGHT
			rogue.draw_armed = true
			if ship_id == "lancer":
				rogue.msg_t = 0
				rogue.fire_lance()
				assert(rogue.tether_active and rogue.msg != "LANCE", "Successful lance has no redundant popup")
				for i in 12: rogue.ride_step()
			else:
				for i in 12: assert(rogue.try_step(Vector2i.RIGHT, true, false))
			await tap("br_harden")
			rogue.update_movement_module(0.5)
			assert(rogue.cells[rogue.idx(rogue.trail[0].x, rogue.trail[0].y)] == Game.HARD)
			assert(rogue.cells[rogue.idx(rogue.trail.back().x, rogue.trail.back().y)] == Game.TRAIL)
			await shot(ship_id + "-hardening")
			for i in 60:
				if not rogue.drawing: break
				if ship_id == "lancer": rogue.ride_step()
				else: assert(rogue.try_step(Vector2i.RIGHT, true, false))
			assert(not rogue.drawing and rogue.capture_percent >= 35)
		install_opening(ship_id, "leap")
		rogue.p = Vector2i(80, 26)
		rogue.vis = rogue.center(rogue.p)
		rogue.last_dir = Vector2i.DOWN
		await get_tree().process_frame
		Input.action_press("br_harden")
		for step in 5: rogue.update(0.1)
		assert(rogue.leap_building and rogue.p == Vector2i(80, 26))
		assert(not rogue.tether_active and not rogue.sap_live, "Q aim cannot trigger the native Space action")
		await shot(ship_id + "-leap-aim")
		Input.action_release("br_harden")
		rogue.update(0.05)
		assert(rogue.wall_building and rogue.cooldowns.leap > 0)
		await shot(ship_id + "-leap-wall")
		for step in 200:
			if not rogue.wall_building: break
			rogue.update(0.05)
		assert(not rogue.wall_building and rogue.capture_percent > 35 and rogue.lives == 2)
		assert(not rogue.tether_active and not rogue.sap_live and rogue.ship.id == ship_id)
		install_opening(ship_id, "dash")
		rogue.p = Vector2i(80, 26)
		rogue.vis = rogue.center(rogue.p)
		rogue.last_dir = Vector2i.RIGHT if ship_id == "lancer" else Vector2i.DOWN
		var start: Vector2i = rogue.p
		await tap("br_harden")
		for step in 15: rogue.update(0.02)
		assert(Vector2(rogue.p - start).length() >= 6, "%s Dash moves faster through the real movement loop" % ship_id)
		assert(rogue.ship.id == ship_id and rogue.cooldowns.dash > 0 and rogue.dash_time == 0)
		rogue.activate_ability("dash")
		assert(rogue.dash_time == 0, "Cooldown prevents an immediate second dash")
		install_opening(ship_id, "dash")
		rogue.p = Vector2i(104, 26)
		rogue.vis = rogue.center(rogue.p)
		rogue.last_dir = Vector2i.RIGHT
		await tap("br_harden")
		for step in 15: rogue.update(0.02)
		assert(rogue.p.x <= 105 and rogue.cells[rogue.idx(rogue.p.x, rogue.p.y)] != Game.ROCK, "Dash cannot cross rock")
	for ability in Cards.SECONDARY:
		install_opening("surveyor", "dash")
		rogue.owned_cards.append(ability)
		rogue.card_ranks[ability] = 1
		for attempt in 10:
			rogue.roll_offers()
			for card in rogue.offers:
				assert(not Cards.SECONDARY.has(card.id), "A second E ability cannot conflict with the equipped one")
		await tap("special")
		assert(rogue.cooldowns[ability] > 0 and rogue.cooldowns.dash == 0)
		assert(rogue.boost_time > 0 if ability == "afterburner" else rogue.hardlight_time > 0)
		rogue.p = Vector2i(80, 26)
		rogue.last_dir = Vector2i.RIGHT
		await tap("br_harden")
		assert(rogue.cooldowns.dash > 0, "Q movement stays independent of E")
	fresh_ship("surveyor")
	rogue.open_draft()
	rogue.ui_time = 1.0
	await shot("opening-movement-draft")
	assert(Save.data == campaign)
	print("ROGUELITE MOVEMENT OK: fixed opening choices, all-ship hardening/leap/dash, native action isolation, collisions, cooldowns and silent lance")
	get_tree().quit()
