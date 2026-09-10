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

func begin_test_cut(ship_id: String) -> void:
	rogue.drafts_taken = rogue.draft_capture.size()
	rogue.p = Vector2i(80, 26)
	rogue.vis = rogue.center(rogue.p)
	rogue.last_dir = Vector2i.DOWN
	rogue.draw_armed = true
	if ship_id == "lancer":
		rogue.fire_lance()
		for step in 6: rogue.ride_step()
	else:
		for step in 6: assert(rogue.try_step(Vector2i.DOWN, true, false))
	rogue.vis = rogue.center(rogue.p)
	assert(rogue.drawing)

func check_mid_cut_modules() -> void:
	for ship_id in ["surveyor", "lancer", "bulwark"]:
		for module in ["charge", "leap"]:
			install_opening(ship_id, module)
			begin_test_cut(ship_id)
			var origin: Vector2i = rogue.p
			var old_anchor: Vector2i = rogue.anchor
			var old_cell: Vector2i = rogue.trail[0]
			await get_tree().process_frame
			Input.action_press("br_harden")
			for step in (30 if module == "charge" else 5): rogue.update(0.1)
			assert(rogue.state == Game.State.PLAYING and rogue.p == origin)
			assert(rogue.anchor == old_anchor and rogue.trail.has(old_cell) and not rogue.tether_active)
			assert(rogue.sap_live if module == "charge" else rogue.leap_building)
			Input.action_release("br_harden")
			rogue.update(0.05)
			for step in 300:
				if not rogue.wall_building: break
				rogue.update(0.05)
			assert(not rogue.drawing and rogue.cooldowns[module] > 0 and rogue.capture_percent > 0)
			assert(rogue.cells[rogue.idx(old_cell.x, old_cell.y)] == Game.CLAIMED, "The approach trail joins the module capture")
			assert(rogue.cells.count(Game.TRAIL) == 0 and rogue.cells.count(Game.HARD) == 0, "%s %s orphan trail: %d soft / %d hard" % [ship_id, module, rogue.cells.count(Game.TRAIL), rogue.cells.count(Game.HARD)])
		install_opening(ship_id, "dash")
		rogue.p = Vector2i(80, 26)
		rogue.vis = rogue.center(rogue.p)
		rogue.last_dir = Vector2i.DOWN
		await tap("br_harden")
		for step in 15: rogue.update(0.02)
		assert(rogue.p == Vector2i(80, 26) and not rogue.drawing, "Dash alone never launches a cut into void")
		rogue.cooldowns.dash = 0
		begin_test_cut(ship_id)
		var origin: Vector2i = rogue.p
		await tap("br_harden")
		for step in 10: rogue.update(0.02)
		assert(rogue.p.y > origin.y + 4, "Dash still accelerates an active cut or tether")
		install_opening(ship_id, "dash")
		rogue.owned_cards.append("hardlight")
		rogue.card_ranks.hardlight = 1
		await tap("special")
		for step in 30: rogue.update(0.1)
		assert(rogue.hardlight_armed and rogue.hardlight_time == 0 and rogue.cooldowns.hardlight == 0, "Armed shield spends neither duration nor cooldown on land")
		begin_test_cut(ship_id)
		assert(not rogue.hardlight_armed and rogue.hardlight_time == 2 and rogue.cooldowns.hardlight == 18)
		assert(not rogue.tether_hit(rogue.p), "Queued shield protects the first exposed cell")
		rogue.hardlight_time = 0
		rogue.cooldowns.hardlight = 0
		rogue.activate_ability("hardlight")
		assert(rogue.hardlight_time == 2 and not rogue.hardlight_armed, "Mid-cut shield activates immediately")
	# A failed aim retains the original coast anchor and every approach cell.
	install_opening("surveyor", "leap")
	begin_test_cut("surveyor")
	var approach: Array = rogue.trail.duplicate()
	var old_anchor: Vector2i = rogue.anchor
	rogue.activate_ability("leap")
	rogue.finish_leap(false)
	assert(rogue.drawing and rogue.trail == approach and rogue.anchor == old_anchor and rogue.cooldowns.leap == 0)
	rogue.activate_ability("leap")
	rogue.leap_len = 4
	rogue.finish_leap(false)
	while not rogue.wall_done[1]: rogue.wall_grow(0.05)
	var hit_cell: Vector2i = rogue.wall_cells[0][0]
	assert(not rogue.wall_hit(hit_cell), "A landed wall side protects against losing the other side")
	assert(rogue.cells.count(Game.TRAIL) == 0 and rogue.cells.count(Game.HARD) == 0, "Interrupted leap removes the unfinished approach too")
	install_opening("surveyor", "leap")
	rogue.owned_cards.append("hardlight")
	rogue.card_ranks.hardlight = 1
	rogue.p = Vector2i(80, 26)
	rogue.last_dir = Vector2i.DOWN
	rogue.activate_ability("leap")
	rogue.activate_ability("hardlight")
	assert(rogue.hardlight_armed and rogue.hardlight_time == 0, "Aiming on land does not spend the shield")
	rogue.leap_len = 4
	rogue.finish_leap(false)
	assert(rogue.hardlight_time == 2 and not rogue.hardlight_armed)

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
	rogue.progress.ships = {"surveyor": true, "lancer": true, "bulwark": true}
	var migrated := Progress.new()
	migrated.apply_profile({"version": 6, "ships": {"sapper": true}, "selected_ship": "sapper", "salvage": 17, "ranks": {"hull": 4}})
	assert(migrated.selected_ship == "bulwark" and migrated.owns_ship("bulwark") and not migrated.owns_ship("sapper"))
	assert(migrated.salvage == 17 and migrated.rank_of("hull") == 4)
	var campaign: Dictionary = Save.data.duplicate(true)
	await check_bulwark_draft_capture()
	await check_mid_cut_modules()
	for ship_id in ["surveyor", "lancer", "bulwark"]:
		install_opening(ship_id, "charge")
		rogue.p = Vector2i(80, 26)
		rogue.vis = rogue.center(rogue.p)
		var charge_start: Vector2i = rogue.p
		await get_tree().process_frame
		Input.action_press("br_harden")
		Input.action_press("move_down")
		for step in 20: rogue.update(0.1)
		assert(rogue.sap_live and rogue.sap_charge > 4 and rogue.p == charge_start)
		assert(not rogue.drawing and not rogue.tether_active)
		await shot(ship_id + "-charge")
		Input.action_release("move_down")
		Input.action_release("br_harden")
		rogue.update(0.05)
		assert(not rogue.sap_live and rogue.capture_percent > 0 and rogue.cooldowns.charge > 0)
		rogue.activate_ability("charge")
		assert(not rogue.sap_live, "Charge cannot bypass its cooldown")
		assert(rogue.ship.id == ship_id)
		rogue.card_ranks.charge = 3
		assert(rogue.sap_radius() == 12 and rogue.sap_rate() >= 4.0, "Charge ranks increase reach and growth together")
		rogue.hardlight_time = 1
		rogue.sap_live = true
		assert(not rogue.wire_hit(), "Hardlight protects every ship's charge")
		rogue.hardlight_time = 0
		rogue.sap_live = false
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
		rogue.last_dir = Vector2i.RIGHT
		var start: Vector2i = rogue.p
		await tap("br_harden")
		for step in 15: rogue.update(0.02)
		assert(Vector2(rogue.p - start).length() >= 6, "%s Dash moves faster through the real movement loop" % ship_id)
		assert(rogue.ship.id == ship_id and rogue.cooldowns.dash > 0 and rogue.dash_time == 0)
		assert(not rogue.drawing and rogue.p.y == 26, "Coast Dash does not start a cut")
		rogue.activate_ability("dash")
		assert(rogue.dash_time == 0, "Cooldown prevents an immediate second dash")
		install_opening(ship_id, "dash")
		rogue.p = Vector2i(104, 26)
		rogue.vis = rogue.center(rogue.p)
		rogue.last_dir = Vector2i.RIGHT
		await tap("br_harden")
		for step in 15: rogue.update(0.02)
		assert(rogue.p.x <= 105 and rogue.cells[rogue.idx(rogue.p.x, rogue.p.y)] != Game.ROCK, "Dash cannot cross rock")
	fresh_ship("bulwark")
	rogue.p = Vector2i(54, 46)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in 12: assert(rogue.try_step(Vector2i.RIGHT, true, false))
	Input.action_press("draw")
	rogue.update(0.5)
	var hardened: int = rogue.cells.count(Game.HARD)
	assert(hardened > 0, "Bulwark hardens without an installed module")
	Input.action_release("draw")
	var brace_position: Vector2i = rogue.p
	rogue.update(0.5)
	assert(rogue.braced and rogue.p == brace_position and rogue.cells.count(Game.HARD) > hardened)
	await shot("bulwark-native-hardening")
	for step in 60:
		if not rogue.drawing: break
		assert(rogue.try_step(Vector2i.RIGHT, true, false))
	assert(not rogue.drawing and not rogue.seals.is_empty())
	for step in 300:
		if rogue.capture_percent > 0: break
		rogue.update(0.05)
	assert(rogue.capture_percent > 0, "Bulwark's detached wall resolves into a real capture")
	for ability in Cards.SECONDARY:
		install_opening("surveyor", "dash")
		rogue.owned_cards.append(ability)
		rogue.card_ranks[ability] = 1
		for attempt in 10:
			rogue.roll_offers()
			for card in rogue.offers:
				assert(not Cards.SECONDARY.has(card.id), "A second E ability cannot conflict with the equipped one")
		await tap("special")
		assert(rogue.cooldowns.dash == 0)
		assert(rogue.boost_time > 0 if ability == "afterburner" else rogue.hardlight_armed)
		rogue.p = Vector2i(80, 26)
		rogue.last_dir = Vector2i.RIGHT
		await tap("br_harden")
		assert(rogue.cooldowns.dash > 0, "Q movement stays independent of E")
	fresh_ship("surveyor")
	rogue.open_draft()
	rogue.ui_time = 1.0
	await shot("opening-movement-draft")
	assert(Save.data == campaign)
	print("ROGUELITE MOVEMENT OK: fixed opening choices, all-ship charge/leap/dash, native action isolation, collisions, cooldowns and silent lance")
	get_tree().quit()

func check_bulwark_draft_capture() -> void:
	MapCatalog.testing["roguelite_01"] = null
	fresh_ship("bulwark")
	rogue.nodes.clear()
	rogue.turrets.clear()
	rogue.p = Vector2i(75, 26)
	rogue.draw_armed = true
	for step in 51: assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.seals.size() == 1)
	var first_seal: Game.Seal = rogue.seals[0]
	# Start a second crossing while the detached first crossing is still sealing.
	rogue.p = Vector2i(90, 26)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in 12: assert(rogue.try_step(Vector2i.DOWN, true, false))
	rogue.harden_len = 3.0
	for cell in rogue.trail.slice(0, 3): rogue.cells[rogue.idx(cell.x, cell.y)] = Game.HARD
	rogue.fuse_on = true
	var unfinished: Array = rogue.trail.duplicate()
	var anchor_before: Vector2i = rogue.anchor
	first_seal.harden = first_seal.cells.size()
	rogue.update_seals(0.01)
	assert(rogue.phase == "reward" and not rogue.pending_clear, "The first seal opens a mid-sector draft")
	assert(rogue.drawing and rogue.trail == unfinished and rogue.anchor == anchor_before and rogue.harden_len == 3.0 and rogue.fuse_on, "Draft interruption preserves the live crossing")
	for frame in 100:
		if rogue.phase == "draft": break
		rogue.update(0.05)
	assert(rogue.phase == "draft")
	await shot("bulwark-draft-with-live-capture")
	rogue.choose_card(0)
	assert(rogue.phase == "run" and rogue.drawing and rogue.trail == unfinished)
	var captured_before: float = rogue.capture_percent
	for step in 39: assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.seals.size() == 1 and not rogue.drawing, "The resumed crossing reaches land normally")
	rogue.seals[0].harden = rogue.seals[0].cells.size()
	rogue.update_seals(0.01)
	assert(rogue.capture_percent > captured_before and rogue.pending_clear, "The resumed crossing finishes capturing")
	MapCatalog.testing.clear()
