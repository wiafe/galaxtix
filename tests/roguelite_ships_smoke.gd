extends Node
const Progress = preload("res://scripts/roguelite_progress.gd")
const Cards = preload("res://scripts/roguelite_cards.gd")
var main
var rogue
var shot_dir := ""

class FailedProfile extends "res://scripts/roguelite_progress.gd":
	func write_profile() -> bool:
		return false

func _ready() -> void:
	call_deferred("check")

func click(pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = pos
	rogue.ui_time = 1.0
	rogue._input(event)

func tap(action: String) -> void:
	await get_tree().process_frame
	Input.action_press(action)
	rogue.ui_time = 1.0
	rogue.update(0.016)
	Input.action_release(action)
	await get_tree().process_frame

func shot(name: String) -> void:
	if shot_dir.is_empty():
		return
	main.display.lines.fx_wobble = 0
	main.display.lines.fx_slop = 0
	for frame in 12:
		main.display.tick(0.016)
		main.display.begin_draw()
		main.game.draw()
		main.display.end_draw()
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join(name + ".png"))

func fresh_ship(id: String) -> void:
	# Legacy Sapper mechanics still exercise the shared disc engine used by Charge and Jump.
	assert(rogue.progress.select_ship("surveyor" if id == "sapper" else id))
	rogue.transit_skip = true
	rogue.sector_limit = 8 # Legacy arena fixtures; act progression has its own suite.
	rogue.start_run()
	rogue.launch_destination(0)
	if id == "sapper": rogue.ship = Ships.get_ship(id)
	rogue.state = Game.State.PLAYING
	rogue.surv_scale = 1.0
	rogue.invuln = 0
	rogue.sparxes.clear()
	rogue.sparx_to_spawn = 0
	rogue.spawners.clear()
	rogue.mites.clear()
	for q in rogue.qixes:
		q.c = rogue.center(Vector2i(100, 70))
		q.len = 10.0
		q.v = Vector2.ZERO
	rogue.freeze_time = 100
	assert(rogue.ship.id == id)
	assert(not rogue.trail_slow, "Changing ships cannot inherit a slow-draw payout")

func check() -> void:
	assert(not Save.enabled)
	Save.set_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			shot_dir = arg.substr(14)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	var profile := Progress.new()
	profile.apply_profile({"version": 1, "salvage": 65, "ranks": {"hull": 3}})
	assert(profile.selected_ship == "surveyor" and profile.owns_ship("surveyor"))
	assert(profile.salvage == 16 and is_equal_approx(profile.salvage_fraction, 0.25) and profile.rank_of("hull") == 3)
	assert(not profile.select_ship("lancer") and not profile.buy_ship("unknown"))
	assert(profile.buy_ship("lancer") and profile.salvage == 6)
	assert(not profile.buy_ship("lancer") and not profile.buy_ship("bulwark"))
	assert(profile.select_ship("surveyor") and profile.salvage == 6)
	profile.apply_profile({"ships": {"leaper": true}, "selected_ship": "leaper"})
	assert(profile.selected_ship == "surveyor" and not profile.owns_ship("leaper"))
	var failed := FailedProfile.new()
	failed.salvage = 80
	assert(not failed.buy_ship("bulwark"))
	assert(failed.salvage == 80 and not failed.owns_ship("bulwark") and failed.selected_ship == "surveyor")
	failed.ships.lancer = true
	assert(not failed.select_ship("lancer") and failed.selected_ship == "surveyor")

	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var campaign: Dictionary = Save.data.duplicate(true)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	rogue.progress.salvage = 16
	await shot("upgrades")
	click(rogue.choice_rect(5).get_center())
	assert(rogue.hangar_page == "ships")
	await tap("move_right")
	assert(rogue.selection == 11)
	await tap("move_up")
	assert(rogue.selection == 5)
	await tap("move_down")
	assert(rogue.selection == 11)
	click(rogue.ship_rect(1).get_center())
	assert(rogue.progress.salvage == 16 and not rogue.progress.owns_ship("lancer"), "Previewing does not purchase")
	await shot("ships-locked")
	click(rogue.ship_action_rect(1).get_center())
	assert(rogue.progress.selected_ship == "lancer" and rogue.progress.salvage == 6)
	click(rogue.ship_action_rect(2).get_center())
	assert(not rogue.progress.owns_ship("bulwark") and rogue.progress.salvage == 6)
	assert(rogue.msg_currency == 0 and rogue.msg_amount == "4")
	await shot("ships-need-salvage")
	rogue.progress.salvage += 4
	click(rogue.ship_action_rect(2).get_center())
	assert(rogue.progress.selected_ship == "bulwark" and rogue.progress.salvage == 0)
	await shot("ships-owned")
	await tap("move_left")
	await tap("confirm")
	assert(rogue.progress.selected_ship == "lancer" and rogue.progress.salvage == 0, "Owned ships switch freely with the keyboard")
	await tap("move_right")
	await tap("confirm")
	assert(rogue.progress.selected_ship == "bulwark")
	rogue.progress.ranks = {"engines": 5, "hull": 5, "reactor": 5}
	click(rogue.choice_rect(6).get_center())
	assert(rogue.hangar_page == "upgrades")
	click(rogue.choice_rect(0).get_center())
	assert(rogue.ship.id == "bulwark" and rogue.lives == 3)
	assert(is_equal_approx(rogue.respawn_shield_duration(), 5.0))

	fresh_ship("lancer")
	rogue.p = Vector2i(54, 46)
	rogue.last_dir = Vector2i.RIGHT
	rogue.vis = rogue.center(rogue.p)
	rogue.safe_motion = 2.1
	rogue.cut_time = 9.0
	rogue.fire_lance()
	assert(rogue.tether_active and rogue.hot_entry and rogue.cut_time == 0)
	rogue.owned_cards.assign(["hardlight", "anchor", "phase"])
	assert(not rogue.tether_hit(rogue.trail[0]))
	await shot("lancer-run")
	for step in 83:
		if rogue.tether_active:
			rogue.ride_step()
	assert(not rogue.drawing and not rogue.tether_active and rogue.capture_percent >= 35)
	assert(rogue.phase == "reward", "Lance captures feed card milestones")
	fresh_ship("lancer")
	rogue.p = Vector2i(54, 40)
	rogue.last_dir = Vector2i.RIGHT
	rogue.fire_lance()
	rogue.owned_cards.assign(["anchor"])
	rogue.die("TEST")
	assert(rogue.lives == 3 and not rogue.tether_active and not rogue.drawing and rogue.trail.is_empty())
	assert(rogue.cells.count(Game.TRAIL) == 0)
	rogue.lance_cd = 5
	rogue.refund_cooldowns(1)
	assert(rogue.lance_cd == 4)
	rogue.update_play(0.1)
	assert(is_equal_approx(rogue.lance_cd, 3.885), "Reactor speeds native lance recharge")

	fresh_ship("sapper")
	rogue.p = Vector2i(54, 40)
	assert(rogue.try_step(Vector2i.RIGHT, false, false))
	assert(not rogue.drawing and rogue.cells[rogue.idx(55, 40)] == Game.FREE)
	rogue.p = Vector2i(71, 43)
	rogue.vis = rogue.center(rogue.p)
	rogue.nodes.resize(1) # Isolate one pickup from the seeded layout for exact payout checks.
	rogue.nodes[0].cell = rogue.p
	rogue.owned_cards.assign(["afterburner", "hardlight", "phase"])
	rogue.start_sapper_charge()
	var normal_rate: float = rogue.sap_rate()
	rogue.activate_ability("afterburner")
	assert(is_equal_approx(rogue.sap_rate(), normal_rate * 1.8))
	assert(not rogue.wire_hit(), "Phase protects the new disc")
	rogue.cut_time = 2.0
	assert(rogue.wire_hit(), "Disc protection expires")
	rogue.activate_ability("hardlight")
	assert(not rogue.wire_hit())
	rogue.sap_charge = 10
	await shot("sapper-run")
	rogue.detonate(10)
	assert(rogue.capture_percent > 7 and rogue.earned_salvage == 1)
	var old_capture: float = rogue.capture_percent
	rogue.sap_cell = Vector2i(71, 43)
	rogue.detonate(10)
	assert(rogue.capture_percent == old_capture and rogue.earned_salvage == 1, "Repeated disc territory cannot pay twice")
	rogue.owned_cards.assign(["anchor"])
	rogue.p = Vector2i(70, 43)
	rogue.start_sapper_charge()
	rogue.invuln = 0
	rogue.die("TEST")
	assert(not rogue.sap_live and rogue.sap_charge == 0 and rogue.p == rogue.anchor and rogue.lives == 3)
	assert(rogue.cells[rogue.idx(rogue.p.x, rogue.p.y)] == Game.CLAIMED)
	fresh_ship("sapper")
	rogue.owned_cards.assign(["ion", "slipstream", "compression"])
	rogue.safe_motion = 2.1
	rogue.start_sapper_charge()
	assert(rogue.hot_entry and rogue.cut_time == 0)
	rogue.cut_time = 2.0
	var base_rate: float = rogue.sap_rate()
	assert(not rogue.wire_hit() and rogue.cooldowns.ion == 10.0, "Ion Field protects a disc contact")
	rogue.freeze_time = 0
	rogue.sap_cell = Vector2i(71, 43)
	rogue.detonate(3)
	assert(rogue.small_chain == 1 and is_equal_approx(rogue.sap_rate(), base_rate * 1.15), "Small blasts increase charge speed")
	rogue.owned_cards.assign(["compression"])
	rogue.sap_cell = Vector2i(78, 47)
	rogue.detonate(14)
	assert(rogue.small_chain == 0, "Large blast area resets Compression, including directly captured disc cells")

	# Full Space press/hold/release route, including each ship's timing and shared capture callbacks.
	for id in ["lancer", "sapper"]:
		fresh_ship(id)
		rogue.p = Vector2i(54, 40) if id == "lancer" else Vector2i(71, 43)
		rogue.last_dir = Vector2i.RIGHT
		rogue.vis = rogue.center(rogue.p)
		rogue.draw_armed = true
		Input.action_press("draw")
		for step in 60:
			rogue.update(0.05)
		Input.action_release("draw")
		rogue.update(0.05)
		assert(rogue.capture_percent > 0, "Both ships capture through the real input loop")
		fresh_ship(id)
		for draft in 3:
			rogue.open_draft()
			assert(rogue.offers.size() == 3)
			for card in rogue.offers:
				assert(card.stats == Cards.definition(card.id, id, card.rank).stats)
				assert(rogue.paragraph_lines(card.desc, 34 * 16 * 0.65, 16).size() <= 2)
			rogue.choose_card(0)
		assert(rogue.owned_cards.size() == 3)
	rogue.end_run()
	assert(Save.data == campaign, "Purchases, ship mechanics and rewards leave Jump untouched")
	print("ROGUELITE SHIPS OK: migration, transactions, shop input, lance, disc, cards and mode isolation")
	get_tree().quit()
