extends Node
## Isolated test: run with --nosave. Optional --rogue-shots=<absolute directory>.
var main
var rogue
var shot_dir := ""

func _ready() -> void:
	call_deferred("check")

func fresh() -> void:
	rogue.transit_skip = true
	rogue.start_run()
	rogue.launch_destination(0)
	rogue.state = Game.State.PLAYING
	rogue.surv_scale = 1.0
	rogue.invuln = 0.0
	rogue.sparxes.clear()
	rogue.sparx_to_spawn = 0
	rogue.mites.clear()
	rogue.spawners.clear()
	for q in rogue.qixes:
		q.c = rogue.center(Vector2i(98, 73))
		q.len = 10.0

func cut_at(y: int, wait_for_feedback := true, slow := false) -> void:
	rogue.p = Vector2i(54, 27 + int(y * 50.0 / 102.0))
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for x in range(55, 106):
		assert(rogue.try_step(Vector2i.RIGHT, true, slow), "Shared Surveyor movement closes a cut")
	assert(not rogue.drawing)
	if wait_for_feedback:
		finish_reward()

func finish_reward() -> void:
	for i in 40:
		if rogue.phase != "reward":
			return
		rogue.update(0.05)
	assert(rogue.phase != "reward", "XP delivery always resolves into a draft")

func shot(name: String) -> void:
	if shot_dir.is_empty():
		return
	for frame in 12:
		main.display.tick(0.016)
		main.display.begin_draw()
		main.game.draw()
		main.display.end_draw()
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join(name + ".png"))

func check() -> void:
	assert(not Save.enabled, "Run tests with --nosave")
	Save.set_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			shot_dir = arg.substr(14)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	Save.data.flux = 987.0
	Save.data.isotope = 123
	Save.data.upgrades = {"thrust": 15, "hull": 6, "bulk": 4, "prospect": 8}
	Save.data.ship = "lancer"
	Save.data.ships = {"lancer": true}
	Save.data.ship_upgrades = {"surveyor:slip": 5}
	var campaign := Save.data.duplicate(true)
	main.game.go_title()
	main.game.title_t = 3.0
	main.game.update(0.016)
	assert(main.game.TITLE_ITEMS.has("JUMP") and main.game.TITLE_ITEMS.has("ROGUELITE") and main.game.TITLE_ITEMS.has("BATTLE ROYALE"))
	await shot("title")
	# Use the real menu route, including the transition.
	main.game.title_sel = main.game.TITLE_ITEMS.find("ROGUELITE")
	main.game.activate_title_item()
	main.game.update_title(0.6)
	assert(main.game.state == Game.State.ROGUELITE)
	rogue = main.game.roguelite
	rogue.sector_limit = 1 # Capture/settlement fixtures; the expedition suite checks the full three sectors.
	for card in preload("res://scripts/roguelite_cards.gd").LIST:
		var rows: Array[String] = rogue.paragraph_lines(card.desc, 34 * 16 * 0.65, 16)
		assert(rows.size() <= 2, "Card effects stay concise")
		assert(VectorFont.width(card.stats, 13) < 392, "Stats fit the card")
		for row in rows:
			assert(VectorFont.width(row, 16) < 392, "Card copy fits its panel")
	await shot("hangar")
	await check_upgrade_tracks()
	# Exercise the real transit/intro and live enemy update before fixture captures.
	rogue.start_run()
	rogue.launch_destination(0)
	for i in 120:
		rogue.update(0.05)
	assert(rogue.state == Game.State.PLAYING and rogue.spawners.is_empty())
	rogue.invuln = 10.0
	for i in 120:
		rogue.update(0.05)
	assert(rogue.sparxes.size() > 0 and rogue.mites.is_empty())
	assert(not rogue.corruption_active and rogue.corruption.count(1) == 0)
	assert(rogue.draft_exclusions().has("clean") and rogue.draft_exclusions().has("containment") and rogue.draft_exclusions().has("harvest"))
	await shot("field")
	await check_clean_hud()
	fresh()
	rogue.nodes.clear()
	cut_at(10)
	assert(rogue.phase == "run" and rogue.capture_flights.size() > 0 and rogue.displayed_capture == 0.0)
	rogue.update_capture_feedback(1.2)
	assert(is_equal_approx(rogue.displayed_capture, rogue.capture_percent) and rogue.capture_flights.is_empty())
	assert(rogue.earned_salvage == 0, "Territory without pickups grants no currency")
	await shot("capture-partial")
	fresh()
	rogue.nodes.resize(1)
	rogue.nodes[0].cell = Vector2i(68, 30)
	cut_at(10, true, true)
	assert(rogue.earned_salvage == 1 and is_equal_approx(rogue.salvage_fraction, 0.25) and rogue.nodes[0].captured, "A pickup grants one salvage plus the fractional slow bonus")
	cut_at(14)
	assert(rogue.earned_salvage == 1, "Captured pickups cannot pay twice")
	fresh()
	rogue.nodes.clear()
	cut_at(32)
	assert(rogue.phase == "run" and rogue.capture_percent < 35.0)
	cut_at(35)
	assert(rogue.phase == "draft" and rogue.capture_percent >= 35.0, "The small arena offers its one card at 35 percent")
	fresh()
	assert(rogue.ship.id == "surveyor" and rogue.lives == 2)
	assert(is_equal_approx(rogue.movement_mult(), 1.0) and rogue.run_rim() == 0)
	assert(rogue.up("slip") == 0 and rogue.prospect_interval() == 0.0)
	assert(rogue.nodes.size() == 3)
	assert(rogue.base_free == 50 * 50, "Roguelite starts with Jump's small square")
	assert(SectorArena.build(1, 0, "helix").base_free == 2500, "Jump retains its square opening")
	var pickup_cells := [Vector2i(64, 30), Vector2i(78, 44), Vector2i(88, 58)]
	for i in 3:
		rogue.nodes[i].cell = pickup_cells[i]
		assert(not rogue.nodes[i].rare and rogue.cells[rogue.idx(pickup_cells[i].x, pickup_cells[i].y)] == Game.FREE)
	assert(rogue.displayed_capture == 0.0 and rogue.capture_flights.is_empty(), "New runs clear visual capture progress")
	cut_at(36, false)
	assert(rogue.phase == "reward" and rogue.capture_percent >= 35 and rogue.offers.is_empty())
	var position: Vector2 = rogue.qixes[0].c
	var invulnerability: float = rogue.invuln
	var spread: float = rogue.spread_clock
	rogue.cooldowns.afterburner = 4.0
	rogue.update(0.35)
	assert(rogue.phase == "reward" and rogue.capture_flights.size() > 0)
	assert(rogue.qixes[0].c == position and rogue.invuln == invulnerability and rogue.cooldowns.afterburner == 4.0, "XP reveal freezes enemies and gameplay timers")
	await shot("capture_percent-delivery")
	finish_reward()
	assert(rogue.phase == "draft" and rogue.capture_flights.is_empty())
	assert(is_equal_approx(rogue.displayed_capture, rogue.capture_percent))
	rogue.update(0.1)
	assert(rogue.qixes[0].c == position and rogue.invuln == invulnerability and rogue.spread_clock == spread, "Draft freezes simulation and timers")
	assert(rogue.offers.size() == 3)
	for card in rogue.offers:
		assert(not rogue.draft_exclusions().has(card.id), "Opening drafts contain only useful cards")
	rogue.activate_choice(0)
	assert(rogue.phase == "draft" and rogue.owned_cards.is_empty(), "Reveal blocks accidental picks")
	await shot("draft-entrance")
	rogue.update(0.85)
	await shot("draft")
	rogue.activate_choice(0)
	assert(rogue.phase == "install" and rogue.owned_cards.is_empty())
	rogue.update(0.2)
	assert(rogue.qixes[0].c == position and rogue.cooldowns.afterburner == 4.0, "Install flourish keeps gameplay paused")
	await shot("draft-install")
	rogue.activate_choice(1)
	rogue.update(0.3)
	assert(rogue.phase == "run" and rogue.owned_cards.size() == 1)
	cut_at(50)
	assert(rogue.phase == "run" and rogue.drafts_taken == 1, "The opening offers no second draft")
	cut_at(78)
	assert(rogue.phase == "result" and rogue.progress.wins == 1 and rogue.drafts_taken == 1)
	assert(rogue.banked_salvage == rogue.run_nodes and rogue.banked_salvage == 3, "Only enclosed pickups fund this win")
	var bank: int = rogue.progress.salvage
	rogue.end_run()
	assert(rogue.progress.salvage == bank and rogue.progress.runs == 1, "Settlement cannot pay twice")
	assert(rogue.reward_audio.stream == rogue.victory_cue)
	assert(rogue.victory_salvage_shown() == 0)
	rogue.activate_choice(0)
	assert(rogue.phase == "result", "Winning capture input cannot dismiss the celebration")
	rogue.update(0.25)
	await shot("victory-burst")
	rogue.update(0.7)
	assert(rogue.victory_salvage_shown() > 0 and rogue.victory_salvage_shown() < rogue.banked_salvage)
	await shot("victory-count")
	rogue.update(1.3)
	assert(rogue.victory_salvage_shown() == rogue.banked_salvage and rogue.progress.salvage == bank, "Animated count never repays rewards")
	await shot("result")
	rogue.activate_choice(0)
	assert(rogue.phase == "hangar", "Hangar unlocks after the victory reveal")
	assert(Save.data == campaign, "Winning cannot change Jump's save")
	assert(rogue.progress.buy("engines"))
	assert(rogue.progress.rank_of("engines") == 1 and rogue.progress.salvage == bank - 2)
	assert(not rogue.progress.buy("missing"))
	fresh()
	assert(rogue.owned_cards.is_empty() and rogue.capture_percent == 0)
	assert(is_equal_approx(rogue.movement_mult(), 1.02), "Only Roguelite meta affects its movement")
	# A giant opening capture grants its one draft, then settles.
	cut_at(80)
	assert(rogue.capture_percent >= rogue.capture_target() * 100 and rogue.pending_clear)
	for i in rogue.draft_capture.size():
		assert(rogue.phase == "draft")
		rogue.choose_card(0)
	assert(rogue.phase == "result" and rogue.drafts_taken == rogue.draft_capture.size())
	fresh()
	rogue.nodes.clear()
	rogue.drafts_taken = rogue.draft_capture.size()
	cut_at(80, false)
	assert(rogue.phase == "reward" and rogue.pending_clear and rogue.offers.is_empty())
	finish_reward()
	assert(rogue.phase == "result" and rogue.drafts_taken == rogue.draft_capture.size() and rogue.banked_salvage == 0, "Final capture fills the bar, adds no fourth draft, and gives no automatic victory currency")
	fresh()
	# Opt into the deferred system only for its unit checks.
	rogue.corruption_active = true
	rogue.seed_corruption()
	# Corruption spreads only into free cells and cannot erase the coast.
	var before: PackedByteArray = rogue.corruption.duplicate()
	rogue.spread_corruption()
	var growth := 0
	for i in rogue.grid_width * rogue.grid_height:
		if rogue.cells[i] == Game.CLAIMED:
			assert(rogue.corruption[i] == 0)
		if rogue.corruption[i] > before[i]:
			growth += 1
	assert(growth > 0)
	rogue.p = Vector2i(54, 30)
	rogue.draw_armed = true
	rogue.try_step(Vector2i.RIGHT, true, false)
	rogue.corruption[rogue.idx(55, 30)] = 1
	rogue.update_corruption(3.9)
	assert(rogue.exposure > 3.8 and rogue.lives == 2)
	rogue.update_corruption(0.2)
	assert(rogue.lives == 1 and rogue.state == Game.State.DYING)
	# Cards exercise actual capture, cooldown, protection and retreat behavior.
	fresh()
	assert(not rogue.corruption_active and rogue.corruption.count(1) == 0, "Next launch always restores the gentle opening")
	rogue.owned_cards.assign(["afterburner", "hardlight", "anchor"])
	rogue.activate_ability("afterburner")
	rogue.activate_ability("hardlight")
	rogue.p = Vector2i(54, 30)
	rogue.draw_armed = true
	rogue.try_step(Vector2i.RIGHT, true, false)
	assert(rogue.movement_mult() > 1.8)
	assert(not rogue.tether_hit(rogue.p))
	rogue.die("TEST")
	assert(rogue.lives == 2 and not rogue.drawing and rogue.p == Vector2i(54, 30))
	assert(rogue.cooldowns.anchor == 24.0)
	fresh()
	rogue.owned_cards.assign(["ion", "phase", "loop"])
	rogue.cut_time = 0.5
	assert(not rogue.tether_hit(Vector2i(1, 1)))
	assert(rogue.cooldowns.ion == 0.0, "Phase does not spend Ion")
	rogue.cut_time = 2.0
	assert(not rogue.tether_hit(Vector2i(1, 1)))
	assert(rogue.freeze_time == 1.5 and rogue.cooldowns.ion == 10.0)
	rogue.cooldowns.afterburner = 14.0
	# Small cuts do not hit draft thresholds; the third triggers Reactor Loop.
	cut_at(2)
	cut_at(4)
	cut_at(6)
	assert(rogue.cooldowns.afterburner == 8.0)
	fresh()
	rogue.owned_cards.assign(["compression", "clean", "containment", "stasis", "harvest"])
	rogue.corruption_active = true
	cut_at(2)
	assert(rogue.small_chain == 1 and rogue.freeze_time == 1.0)
	# A corruption cell immediately beyond a cut is cleansed by Clean Sweep.
	rogue.corruption[rogue.idx(68, 36)] = 1
	cut_at(13)
	assert(rogue.small_chain == 0 and rogue.containment_time == 8.0)
	assert(rogue.corruption[rogue.idx(68, 36)] == 0)
	var unchanged_capture: float = rogue.capture_percent
	rogue.on_claim(100, 0)
	assert(rogue.capture_percent == unchanged_capture, "Repeated claimed cells award no progress")
	rogue.end_run()
	assert(Save.data == campaign, "Deaths, retreats, upgrades and aborts preserve campaign state")
	fresh()
	rogue.owned_cards.assign(["harvest", "slipstream"])
	var nest := Game.Spawner.new()
	nest.cell = Vector2i(68, 32)
	rogue.spawners.append(nest)
	cut_at(13)
	assert(rogue.bonus_salvage == 1.25, "Void Harvest rewards actual enclosed enemies")
	rogue.p = Vector2i(54, 45)
	rogue.safe_motion = 2.1
	rogue.draw_armed = true
	rogue.try_step(Vector2i.RIGHT, true, false)
	assert(rogue.hot_entry and rogue.movement_mult() > 1.3)
	rogue.cut_time = 2.1
	assert(is_equal_approx(rogue.movement_mult(), 1.02), "Slipstream expires during the cut")
	rogue.progress.ranks.hull = 5
	rogue.progress.ranks.reactor = 5
	rogue.progress.ranks.engines = 5
	fresh()
	assert(rogue.lives == 3 and rogue.up("shield") == 5)
	rogue.cooldowns.afterburner = 10.0
	cut_at(2)
	assert(rogue.cooldowns.afterburner == 9.0, "Reactor milestone refunds on capture without a card")
	rogue.end_run()
	rogue.go_dock()
	rogue.leave_mode()
	assert(main.game.state == Game.State.TITLE)
	main.game.go_dock()
	main.game.transit_skip = true
	main.game.start_run()
	assert(main.game.ship.id == "lancer" and main.game.lives == 8)
	assert(is_equal_approx(main.game.movement_mult(), 2.5))
	assert(Save.data == campaign, "Jump resumes using its original upgrades")
	# Profile input validation and milestone caps.
	var profile = preload("res://scripts/roguelite_progress.gd").new()
	profile.apply_profile({"salvage": -2, "ranks": {"engines": 999, "hull": "bad"}})
	assert(profile.salvage == 0 and profile.rank_of("engines") == 10 and profile.rank_of("hull") == 0)
	if OS.get_cmdline_user_args().has("--rogue-save-test"):
		var storage := ProjectSettings.globalize_path("user://").replace("\\", "/")
		var test_root := ProjectSettings.globalize_path("res://.godot/test-user").replace("\\", "/")
		assert(storage.begins_with(test_root + "/"), "Persistence tests must use isolated APPDATA")
		Save.enabled = true
		profile.salvage = 37
		profile.ships.lancer = true
		profile.selected_ship = "lancer"
		profile.ranks.scanner = 5
		profile.ranks.extractor = 2
		profile.best_sector = 3
		profile.containment_unlocked = true
		profile.salvage_fraction = 0.72
		assert(profile.write_profile())
		profile.salvage = 38
		assert(profile.write_profile(), "Atomic save replaces an existing profile")
		var reloaded = preload("res://scripts/roguelite_progress.gd").new()
		reloaded.read_profile()
		assert(reloaded.salvage == 38 and reloaded.rank_of("engines") == 10)
		assert(reloaded.rank_of("scanner") == 5 and reloaded.rank_of("extractor") == 2)
		assert(reloaded.best_sector == 3 and reloaded.track_available("containment"))
		assert(is_equal_approx(reloaded.salvage_fraction, 0.72), "Fractional Extractor rewards survive disk reload")
		assert(reloaded.owns_ship("lancer") and reloaded.selected_ship == "lancer", "Purchased ships and selection survive disk reload")
		Save.enabled = false
	print("ROGUELITE SMOKE OK: capture, drafts, cards, corruption, settlement, meta and mode isolation")
	get_tree().quit()

func check_clean_hud() -> void:
	var runs_before: int = rogue.progress.runs
	var field := Rect2(rogue.FIELD_X, Game.FY + 18 * Game.CELL, rogue.grid_width * Game.CELL, 68 * Game.CELL)
	assert(not field.intersects(rogue.CAPTURE_BAR))
	for i in 3:
		assert(not field.intersects(rogue.run_card_rect(i)), "Equipped icons stay outside the largest field")
	assert(rogue.capture_bar_point(0).x < rogue.capture_bar_point(20).x)
	assert(rogue.capture_bar_point(20).x < rogue.capture_bar_point(60).x)
	assert(rogue.CAPTURE_BAR.has_point(rogue.capture_bar_point(75)))
	fresh()
	rogue.owned_cards.assign(["afterburner", "hardlight", "compression"])
	rogue.drafts_taken = rogue.draft_capture.size()
	rogue.cooldowns.afterburner = 7.0
	rogue.p = Vector2i(54, 40)
	rogue.draw_armed = true
	rogue.try_step(Vector2i.RIGHT, true, false)
	var trail_before: Array[Vector2i] = rogue.trail.duplicate()
	var position: Vector2 = rogue.qixes[0].c
	var timer: float = rogue.cut_time
	rogue.pause_run()
	rogue.update(0.6)
	assert(rogue.phase == "paused" and rogue.qixes[0].c == position)
	assert(rogue.trail == trail_before and rogue.cut_time == timer and rogue.cooldowns.afterburner == 7.0, "Pause preserves the cut, enemy positions, and gameplay timers")
	await shot("pause")
	rogue.activate_choice(0)
	assert(rogue.phase == "run" and rogue.drawing and rogue.trail == trail_before)
	rogue.pause_run()
	rogue.activate_choice(1)
	assert(rogue.phase == "result" and rogue.settled and not rogue.run_victory)
	assert(rogue.progress.runs == runs_before + 1)
	rogue.progress.runs = runs_before # Keep this pause fixture isolated from settlement checks.
	fresh()
	rogue.state = Game.State.INTRO
	rogue.seq_t = 1.2
	await shot("entry")
	var previous_area := 0
	for sector in range(1, 4):
		rogue.level = sector
		rogue.start_level()
		assert(rogue.base_free > previous_area, "Opening arenas grow while introducing blockers and notches")
		previous_area = rogue.base_free
		assert(rogue.cells.size() == 160 * 104 and rogue.fill_img.get_size() == Vector2i(160, 104))
		assert(rogue.border[rogue.idx(rogue.p.x, rogue.p.y)] == 1)
		for node in rogue.nodes:
			assert(rogue.cells[rogue.idx(node.cell.x, node.cell.y)] == Game.FREE)
		for q in rogue.qixes:
			assert(not rogue.qix_blocked(q.c, q.theta, q.len))
		for point in rogue.coast:
			assert(field.has_point(point), "Every growing arena stays between the HUD bands")
	rogue.level = 8
	rogue.start_level()
	assert(rogue.base_free == rogue.cells.count(Game.FREE), "Island rails do not count toward first-time capture")
	assert(rogue.cells[rogue.idx(118, 50)] == Game.FREE, "Later arenas extend past Jump's 104 columns")
	assert(not rogue.in_bounds(Vector2i(160, 50)) and not rogue.in_bounds(Vector2i(100, 104)))
	assert(rogue.in_bounds(Vector2i(159, 103)))
	rogue.state = Game.State.PLAYING
	rogue.owned_cards.assign(["afterburner", "hardlight", "stasis"])
	rogue.drafts_taken = rogue.draft_capture.size()
	rogue.cooldowns.afterburner = 6.2
	await shot("field-full")
	# Close a vertical cut beyond the old right edge; flood-fill, texture and capture credit
	# must all use the rectangular row stride, including the final column of playable cells.
	for q in rogue.qixes:
		q.c = rogue.center(Vector2i(60, 60))
		q.len = 10.0
	rogue.p = Vector2i(105, 18)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in 67:
		assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(not rogue.drawing and rogue.p == Vector2i(105, 85))
	assert(rogue.cells[rogue.idx(118, 80)] == Game.CLAIMED)
	assert(rogue.credited[rogue.idx(118, 80)] == 1 and rogue.capture_percent > 18)
	assert(rogue.fill_img.get_pixel(118, 80).a > 0)
	await shot("field-wide-capture")
	fresh()

func check_upgrade_tracks() -> void:
	rogue.ui_time = 1.0
	rogue.progress.salvage = 200
	assert(rogue.selection == 1 and rogue.viewed_ranks == [1, 1, 1, 1, 1, 1])
	assert(rogue.node_state(0, 1) == "NEXT" and rogue.node_state(0, 5) == "LOCKED")
	# Inspecting any node is free; only the separate purchase action spends salvage.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = rogue.track_node_position(0, 5)
	rogue._input(click)
	assert(rogue.viewed_ranks[0] == 5 and rogue.progress.salvage == 200)
	rogue.activate_choice(1)
	assert(rogue.progress.rank_of("engines") == 0, "Future ranks cannot bypass the track")
	await shot("track-locked")
	rogue.browse_track(0, -4)
	assert(rogue.viewed_ranks[0] == 1)
	click.position = rogue.track_node_position(0, 1)
	rogue._input(click)
	assert(rogue.progress.salvage == 200, "Clicking a node only inspects it")
	click.position = rogue.upgrade_button_rect().get_center()
	rogue._input(click)
	assert(rogue.progress.rank_of("engines") == 1 and rogue.progress.salvage == 198)
	assert(rogue.viewed_ranks[0] == 2 and rogue.node_state(0, 1) == "OWNED")
	for i in 3:
		rogue.activate_choice(1)
	assert(rogue.progress.rank_of("engines") == 4 and rogue.progress.salvage == 186)
	assert(rogue.viewed_ranks[0] == 5 and rogue.node_state(0, 5) == "NEXT")
	rogue.progress.ranks.hull = 2
	rogue.progress.ranks.reactor = 7
	await shot("track-milestone")
	rogue.activate_choice(1)
	assert(rogue.progress.rank_of("engines") == 5 and rogue.viewed_ranks[0] == 6)
	rogue.browse_track(1, 0)
	assert(rogue.selection == 2 and rogue.viewed_track == 1)
	rogue.viewed_ranks[1] = 3
	rogue.progress.salvage = 0
	rogue.activate_choice(2)
	assert(rogue.progress.rank_of("hull") == 2, "Unaffordable nodes stay locked to purchase")
	for track in rogue.progress.ranks:
		rogue.progress.ranks[track] = 10
	rogue.go_dock()
	assert(rogue.viewed_ranks == [10, 10, 10, 10, 10, 10])
	rogue.activate_choice(1)
	assert(rogue.progress.rank_of("engines") == 10)
	await shot("track-maxed")
	for i in 3:
		for rank in range(1, 11):
			for effect in rogue.node_effect_lines(i, rank):
				assert(VectorFont.width(effect, 15) <= 315, "Node details fit the inspector")
	await check_scroll_list()
	# Restore the fresh profile for the existing gameplay/economy tests.
	for track in rogue.progress.ranks:
		rogue.progress.ranks[track] = 0
	rogue.progress.salvage = 0
	rogue.go_dock()

func check_scroll_list() -> void:
	for track in rogue.progress.ranks: rogue.progress.ranks[track] = 0
	rogue.progress.salvage = 200
	rogue.go_dock()
	rogue.ui_time = 1.0
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = rogue.track_node_position(3, 1)
	rogue._input(click)
	assert(rogue.viewed_track == 0, "Rows outside the scroll viewport cannot be clicked")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = rogue.TRACK_VIEW.get_center()
	wheel.factor = 3.0
	rogue._input(wheel)
	assert(rogue.track_scroll == 144 and rogue.viewed_track == 0, "Wheel scroll keeps the inspector anchored")
	await shot("upgrades-scroll-middle")
	click.position = rogue.scrollbar_thumb().get_center()
	rogue._input(click)
	assert(rogue.scroll_dragging)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(click.position.x, 1000)
	rogue._input(motion)
	assert(rogue.track_scroll == rogue.max_track_scroll())
	click.pressed = false
	click.position = motion.position
	rogue._input(click)
	assert(not rogue.scroll_dragging)
	click.pressed = true
	click.position = rogue.track_node_position(4, 1)
	rogue._input(click)
	assert(rogue.viewed_track == 4 and rogue.viewed_ranks[4] == 1)
	var balance: int = rogue.progress.salvage
	click.position = rogue.upgrade_button_rect().get_center()
	rogue._input(click)
	assert(rogue.progress.rank_of("extractor") == 1 and rogue.progress.salvage == balance - 2, "Scrolled nodes buy the intended track")
	await shot("upgrades-scroll-bottom")
	rogue.focus_track(0)
	assert(rogue.track_scroll == 0)
	for i in range(1, 6):
		rogue.browse_track(1, 0)
		assert(rogue.viewed_track == i)
		assert(rogue.TRACK_VIEW.has_point(rogue.track_node_position(i, 10)))
	assert(rogue.track_scroll == rogue.max_track_scroll(), "Keyboard navigation traverses all six rows without tabs")
