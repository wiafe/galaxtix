extends Node
const Progress = preload("res://scripts/roguelite_progress.gd")
const Cards = preload("res://scripts/roguelite_cards.gd")
var main
var rogue
var shot_dir := ""

func _ready() -> void:
	call_deferred("check")

func shot(name: String) -> void:
	if shot_dir.is_empty(): return
	main.display.lines.fx_wobble = 0
	main.display.lines.fx_slop = 0
	for frame in 12:
		main.display.tick(0.016)
		main.display.begin_draw()
		main.game.draw()
		main.display.end_draw()
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join(name + ".png"))

func play_until_ready() -> void:
	for step in 220:
		if rogue.phase == "briefing":
			rogue.update(0.25)
			rogue.activate_choice(0)
			assert(rogue.phase == "run", "The loaded sector begins after its briefing")
			return
		rogue.update(0.05)
	assert(false, "Transit must reach the next sector briefing")

func capture_sector() -> void:
	rogue.sparxes.clear()
	rogue.sparx_to_spawn = 0
	rogue.mites.clear()
	rogue.freeze_time = 1000
	var free_cells: Array = rogue.field_arena.free_cells
	var lo := Vector2i(999, 999)
	var hi := Vector2i.ZERO
	for cell in free_cells:
		lo = lo.min(cell)
		hi = hi.max(cell)
	# Slice off the far right tip of each silhouette, keeping the Anomaly in that
	# small region. Unlike the old horizontal fixture this works around notches/core holes.
	var cut_x := hi.x - 2
	var top := 999
	var bottom := 0
	for cell in free_cells:
		if cell.x == cut_x:
			top = mini(top, cell.y)
			bottom = maxi(bottom, cell.y)
	for q in rogue.qixes:
		q.c = rogue.center(Vector2i(cut_x + 1, (top + bottom) / 2))
		q.len = 8
		assert(not rogue.qix_blocked(q.c, q.theta, q.len))
	rogue.p = Vector2i(cut_x, top - 1)
	rogue.vis = rogue.center(rogue.p)
	for i in rogue.nodes.size():
		rogue.nodes[i].cell = free_cells[i * 5]
	rogue.draw_armed = true
	for step in bottom - top + 2:
		assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.pending_clear and rogue.phase == "reward" and rogue.capture_percent >= rogue.capture_target() * 100)

func resolve_rewards() -> void:
	for step in 200:
		if rogue.phase == "reward" or rogue.phase == "install":
			rogue.update(0.1)
		elif rogue.phase == "draft":
			assert(rogue.offers.size() == 3)
			var pick := 0
			for i in rogue.offers.size():
				if rogue.has_card(rogue.offers[i].id): pick = i
			rogue.choose_card(pick)
		elif rogue.phase == "replace":
			rogue.activate_choice(0)
		else: return
	assert(false, "Queued rewards must always finish")

func check() -> void:
	assert(not Save.enabled)
	# The expedition walks the built-in arenas; player-edited maps must not change its counts.
	for stage in range(1, 9): MapCatalog.testing["roguelite_%02d" % stage] = null
	Save.set_process(false)
	# Geometry assertions exercise the original arenas, independently of editor changes.
	for stage in range(1, 9): MapCatalog.testing["roguelite_%02d" % stage] = null
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rogue-shots="):
			shot_dir = arg.substr(14)
			DirAccess.make_dir_recursive_absolute(shot_dir)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var campaign: Dictionary = Save.data.duplicate(true)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	var profile = rogue.progress
	profile.apply_profile({"version": 2, "salvage": 160, "ranks": {"engines": 3, "hull": 2, "reactor": 1}})
	assert(profile.rank_of("engines") == 3 and profile.rank_of("scanner") == 0)
	assert(not profile.buy("containment") and profile.salvage == 40)
	assert(profile.buy("scanner") and profile.buy("extractor"))
	var legacy := Progress.new()
	legacy.apply_profile({"version": 3, "best_sector": 3})
	assert(legacy.track_available("containment"), "Earlier prototype unlocks remain owned")
	legacy.apply_profile({"version": 4, "best_sector": 3})
	assert(not legacy.track_available("containment"), "New profiles unlock at the corruption sector")
	rogue.go_dock()
	rogue.focus_track(1)
	await shot("hull-before-after")
	rogue.focus_track(3)
	assert(rogue.track_scroll > 0 and rogue.viewed_track == 3)
	await shot("expedition-upgrades")
	rogue.focus_track(5)
	await shot("containment-locked")
	for id in Progress.SHIPS:
		profile.selected_ship = id
		for i in 6:
			for rank in range(1, 11):
				for line in rogue.node_effect_lines(i, rank):
					assert(VectorFont.width(line, 15) <= 315, "Before/after effects fit the inspector")
	profile.selected_ship = "surveyor"
	profile.ranks.scanner = 5
	profile.ranks.extractor = 5
	rogue.transit_skip = true
	rogue.start_run()
	assert(rogue.phase == "chart" and rogue.route_path.is_empty())
	# This capture-only fixture follows the original arenas; randomized kinds are tested below.
	for row in rogue.route:
		if row.size() == 2 and row[0].kind != "survey": row.reverse()
		row[0].kind = "survey"
	await shot("star-chart-opening")
	rogue.launch_destination(0)
	play_until_ready()
	assert(rogue.sector_limit == 8 and rogue.nodes.size() == 4)
	rogue.lives = 1
	var starting_salvage: int = profile.salvage
	var area := 0
	for sector in range(1, 9):
		assert(rogue.level == sector and rogue.phase == "run")
		if sector <= 3: assert(rogue.base_free > area)
		if sector == 1:
			assert(rogue.base_free == SectorArena.build(1, 0, "helix").base_free, "Opening field retains Jump's small square")
		assert(rogue.lives == 1)
		check_arena_geometry()
		area = rogue.base_free
		assert(rogue.drafts_taken == 0 and rogue.first_claims == 0 and rogue.rerolls_left == 1)
		assert(rogue.spawners.is_empty())
		assert(rogue.turrets.size() == (0 if sector == 1 else 1))
		assert(rogue.corruption_active == (sector == 8))
		if sector == 8: assert(rogue.corruption.count(1) > 0)
		await shot("sector-%d" % sector)
		capture_sector()
		resolve_rewards()
		assert(rogue.drafts_taken == rogue.draft_capture.size() and rogue.owned_cards.size() == mini(sector, 3))
		for id in rogue.owned_cards: assert(rogue.card_rank(id) <= 3)
		assert(rogue.run_sectors == sector)
		rogue.ui_time = rogue.VICTORY_REVEAL
		await shot("sector-%d-clear" % sector)
		if sector < 8:
			assert(rogue.phase == "sector_clear" and not rogue.settled and not rogue.run_victory)
			assert(profile.salvage == starting_salvage and profile.runs == 0)
			var build: Dictionary = rogue.card_ranks.duplicate()
			rogue.transit_skip = false
			rogue.continue_expedition()
			assert(rogue.phase == "chart" and rogue.level == sector)
			assert(rogue.route_path.size() == sector)
			if sector == 1: await shot("star-chart-first-fork")
			rogue.launch_destination(0)
			assert(rogue.state == Game.State.TRANSIT and rogue.phase == "run")
			rogue.update(0.05)
			assert(rogue.phase == "run", "Previous sector's clear flag cannot interrupt transit")
			play_until_ready()
			assert(rogue.card_ranks == build)
	assert(rogue.phase == "result" and rogue.run_victory and rogue.settled)
	assert(profile.runs == 1 and profile.wins == 1 and profile.best_sector == 8)
	assert(profile.salvage == starting_salvage + rogue.earned_salvage)
	assert(profile.track_available("containment"))
	var banked: int = profile.salvage
	rogue.end_run()
	assert(profile.salvage == banked)
	rogue.go_dock()
	rogue.focus_track(5)
	assert(rogue.node_state(5, 1) == "NEXT")
	await shot("containment-available")
	check_pacing_and_currency()
	await check_routes()
	check_anomaly_coverage()
	check_island_bridge()
	check_system_effects()
	await check_draft_choices()
	assert(Save.data == campaign, "The expedition never writes Jump's campaign")
	print("ROGUELITE EXPEDITION OK: eight angular arenas, inner rails, scaled Anomalies, defended middle cuts, routes, transit, persistent builds, drafts and settlement")
	MapCatalog.testing.clear()
	get_tree().quit()

func coast_reachable() -> Dictionary:
	var reached := {rogue.p: true}
	var pending := [rogue.p]
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + direction
			if rogue.in_bounds(next) and rogue.cells[rogue.idx(next.x, next.y)] == Game.CLAIMED and not reached.has(next):
				reached[next] = true
				pending.append(next)
	return reached

func check_arena_geometry() -> void:
	assert(rogue.capture_percent == 0 and is_zero_approx(rogue.claimed_frac()))
	assert(rogue.base_free == rogue.cells.count(Game.FREE), "Initial rails award no territory")
	assert(rogue.cells[rogue.idx(rogue.p.x, rogue.p.y)] == Game.CLAIMED)
	assert(rogue.qixes.size() == rogue.Sectors.anomaly_count(rogue.level, rogue.arena_stage(rogue.level)) and rogue.sparx_to_spawn <= 2)
	assert(not rogue.boss_bond, "The expedition finale does not inherit Jump's sector-eight boss")
	for q in rogue.qixes: assert(not rogue.qix_blocked(q.c, q.theta, q.len))
	for pickup in rogue.nodes: assert(rogue.cells[rogue.idx(pickup.cell.x, pickup.cell.y)] == Game.FREE)
	for turret in rogue.turrets: assert(rogue.cells[rogue.idx(turret.cell.x, turret.cell.y)] == Game.FREE)
	var reached := coast_reachable()
	for i in rogue.cells.size():
		if rogue.cells[i] != Game.CLAIMED: continue
		var cell := Vector2i(i % rogue.grid_width, i / rogue.grid_width)
		var rail := false
		for hole in rogue.field_shape:
			if hole.grow(1).has_point(cell): rail = true
		assert(reached.has(cell) or rail, "Every initial safe cell is walkable coast or an island rail")
	if rogue.level == 8:
		assert(rogue.field_shape.size() == 1)
		var hole: Rect2i = rogue.field_shape[0]
		for y in range(hole.position.y - 1, hole.end.y + 1):
			for x in range(hole.position.x - 1, hole.end.x + 1):
				assert(rogue.cells[rogue.idx(x, y)] == (Game.ROCK if hole.has_point(Vector2i(x, y)) else Game.CLAIMED))
		assert(not reached.has(hole.position - Vector2i.ONE), "An island starts separate from the outer coast")
	print("shape %d: %s, %d capturable cells" % [rogue.level, rogue.Sectors.stage(rogue.level).name, rogue.base_free])

func check_island_bridge() -> void:
	rogue.start_run()
	rogue.launch_destination(0)
	rogue.level = 8
	rogue.start_level()
	rogue.state = Game.State.PLAYING
	rogue.freeze_time = 100
	rogue.qixes[0].c = rogue.center(Vector2i(20, 52))
	rogue.qixes[0].len = 8
	rogue.draw_armed = true
	var walked := 0
	for step in 50:
		assert(rogue.try_step(Vector2i.DOWN, true, false))
		if not rogue.drawing: break
		walked += 1
	assert(walked > 10 and not rogue.drawing)
	assert(rogue.first_claims == walked, "Bridging an island claims only the new trail")
	assert(is_equal_approx(rogue.capture_percent, rogue.claimed_frac() * 100.0))
	var hole: Rect2i = rogue.field_shape[0]
	assert(coast_reachable().has(hole.position - Vector2i.ONE), "New bridge makes the inner rail reachable")
	for step in 10: assert(rogue.try_step(Vector2i.RIGHT, false, false))
	rogue.draw_armed = true
	assert(rogue.try_step(Vector2i.UP, true, false) and rogue.drawing, "A player can walk the island rail and launch a cut from it")

func check_system_effects() -> void:
	var profile = rogue.progress
	profile.ranks.extractor = 1
	rogue.transit_skip = true
	rogue.start_run()
	rogue.launch_destination(0)
	rogue.earned_salvage = 0
	rogue.salvage_fraction = 0
	for i in 40: rogue.award_flux(1)
	assert(rogue.earned_salvage == 40 and is_equal_approx(rogue.salvage_fraction, 0.8))
	rogue.end_run()
	rogue.start_run()
	rogue.launch_destination(0)
	for i in 12: rogue.award_flux(1)
	assert(rogue.earned_salvage == 13, "Small Extractor bonuses carry across runs instead of rounding away")
	profile.ranks.hull = 10
	assert(rogue.run_extra_lives() == 2 and rogue.respawn_shield_duration() == 7.5)
	rogue.level = 8
	rogue.start_level()
	rogue.state = Game.State.PLAYING
	profile.ranks.containment = 10
	rogue.p = rogue.field_arena.start
	rogue.draw_armed = true
	assert(rogue.try_step(Vector2i.DOWN, true, false) and rogue.drawing)
	rogue.corruption[rogue.idx(rogue.p.x, rogue.p.y)] = 1
	rogue.update_corruption(4.0)
	assert(is_equal_approx(rogue.exposure, 2.8), "Containment extends time before corruption overload")
	rogue.owned_cards.assign(["afterburner", "hardlight", "phase"])
	rogue.card_ranks = {"afterburner": 3, "hardlight": 3, "phase": 3}
	rogue.activate_ability("afterburner")
	rogue.activate_ability("hardlight")
	assert(rogue.hardlight_time == 3.0 and rogue.movement_mult() > 2.2)
	rogue.hardlight_time = 0
	rogue.cut_time = 2.0
	assert(not rogue.tether_hit(rogue.p), "Upgraded Phase remains protective beyond rank one's duration")
	for card in Cards.LIST:
		for rank in range(1, 4):
			for ship in ["surveyor", "lancer", "sapper"]:
				var definition := Cards.definition(card.id, ship, rank)
				assert(VectorFont.width(definition.stats, 13) <= 392)

func check_draft_choices() -> void:
	rogue.start_run()
	rogue.launch_destination(0)
	rogue.state = Game.State.PLAYING
	rogue.owned_cards.assign(["afterburner", "hardlight", "stasis"])
	rogue.card_ranks = {"afterburner": 1, "hardlight": 1, "stasis": 1}
	rogue.open_draft()
	rogue.offers.assign([rogue.card_definition("afterburner", 2), rogue.card_definition("ion", 2), rogue.card_definition("hardlight", 2)])
	for card in rogue.offers:
		card.action = "UPGRADE" if rogue.has_card(card.id) else "REPLACE"
	rogue.ui_time = rogue.DRAFT_REVEAL
	await shot("upgrade-draft")
	rogue.begin_card_install(1)
	assert(rogue.phase == "replace" and rogue.drafts_taken == 0)
	var before: Array = rogue.owned_cards.duplicate()
	await shot("replace-system")
	rogue.cancel_replacement()
	assert(rogue.owned_cards == before and rogue.drafts_taken == 0)
	rogue.begin_card_install(1)
	rogue.cooldowns.afterburner = 10.0
	rogue.activate_choice(0)
	assert(rogue.phase == "install" and rogue.owned_cards == before)
	rogue.update(0.5)
	assert(rogue.owned_cards.size() == 3 and not rogue.has_card("afterburner") and rogue.card_rank("ion") == 2)
	assert(rogue.cooldowns.afterburner == 0.0, "Replacing a system clears its old cooldown")
	assert(rogue.drafts_taken == 1)
	rogue.open_draft()
	rogue.offers.assign([rogue.card_definition("ion", 3)])
	rogue.choose_card(0)
	assert(rogue.card_rank("ion") == 3 and rogue.owned_cards.size() == 3 and rogue.drafts_taken == 2)
	rogue.progress.ranks.scanner = 10
	rogue.rerolls_left = 2
	rogue.open_draft()
	var prior: Array[String] = []
	for card in rogue.offers: prior.append(card.id)
	rogue.ui_time = rogue.DRAFT_REVEAL
	rogue.reroll_draft()
	assert(rogue.rerolls_left == 2 and rogue.drafts_taken == 2, "Guaranteed full-build choices never waste a rescan")
	for card in rogue.offers:
		assert(prior.has(card.id))
		assert(card.id != "ion", "Max-rank cards cannot appear as useless upgrades")
	rogue.ui_time = rogue.DRAFT_REVEAL
	rogue.reroll_draft()
	rogue.ui_time = rogue.DRAFT_REVEAL
	var last: Array = rogue.offers.duplicate(true)
	rogue.reroll_draft()
	assert(rogue.rerolls_left == 2 and rogue.offers == last)
	var kept: Dictionary = rogue.card_ranks.duplicate()
	rogue.level = 8
	rogue.level_clear()
	rogue.keep_build()
	assert(rogue.drafts_taken == 3 and rogue.card_ranks == kept and rogue.run_victory, "Passing the last offer preserves the build and completes a winning capture")
	rogue.owned_cards.clear()
	rogue.rng.seed = 12345
	var upgraded := 0
	for i in 30:
		rogue.roll_offers()
		for card in rogue.offers:
			if card.rank == 2: upgraded += 1
	assert(upgraded > 0, "Scanner produces upgraded versions in the normal offer pool")
	rogue.phase = "draft"
	rogue.ui_time = rogue.DRAFT_REVEAL
	prior.clear()
	for card in rogue.offers: prior.append(card.id)
	rogue.reroll_draft()
	assert(rogue.rerolls_left == 1)
	for card in rogue.offers: assert(not prior.has(card.id), "Underfilled builds can rescan for different systems")
	await check_full_build_rewards()

func check_full_build_rewards() -> void:
	rogue.start_run()
	rogue.launch_destination(0)
	rogue.state = Game.State.PLAYING
	rogue.opening_draft_pending = false
	rogue.owned_cards.assign(["dash", "clean", "harvest"])
	# Owned systems remain upgradeable even when their acquisition gates are closed.
	rogue.corruption_active = false
	rogue.spawners.clear()
	rogue.turrets.clear()
	for ranks in [[1, 1, 1], [3, 2, 1], [3, 3, 2], [3, 3, 3]]:
		for i in 3: rogue.card_ranks[rogue.owned_cards[i]] = ranks[i]
		for seed_value in 20:
			rogue.rng.seed = seed_value
			rogue.open_draft()
			assert(rogue.offers.size() == 3)
			var seen: Array[String] = []
			for card in rogue.offers:
				assert(not seen.has(card.id), "Every reward is distinct")
				seen.append(card.id)
				if card.action == "UPGRADE":
					assert(rogue.has_card(card.id) and card.rank == rogue.card_rank(card.id) + 1 and card.rank <= 3)
				else:
					assert(card.action in ["BONUS", "COLLECT"], "Full builds offer no forced replacements")
			for id in rogue.owned_cards:
				assert(seen.has(id) == (rogue.card_rank(id) < 3), "Every unfinished system is guaranteed an upgrade")
		rogue.ui_time = rogue.DRAFT_REVEAL
		await shot("full-build-" + str(ranks[0]) + str(ranks[1]) + str(ranks[2]))
	var build: Dictionary = rogue.card_ranks.duplicate()
	var slots: Array = rogue.owned_cards.duplicate()
	var earned: int = rogue.earned_salvage
	var speed: float = rogue.movement_mult()
	var shield: float = rogue.respawn_shield_duration()
	# Resolve three queued rewards through the same install path used by all input devices.
	rogue.draft_capture.assign([20, 40, 60])
	rogue.drafts_taken = 0
	rogue.capture_percent = 65
	for id in ["draft_salvage", "draft_speed", "draft_shield"]:
		var pick := -1
		for i in rogue.offers.size():
			if rogue.offers[i].id == id: pick = i
		assert(pick >= 0)
		rogue.ui_time = rogue.DRAFT_REVEAL
		rogue.activate_choice(pick)
		assert(rogue.phase == "install", "Slot-free rewards bypass replacement")
		rogue.update(0.5)
	assert(rogue.phase == "run" and rogue.drafts_taken == 3)
	assert(rogue.card_ranks == build and rogue.owned_cards == slots)
	assert(rogue.earned_salvage == earned + 3, "The cache awards exactly the displayed salvage")
	assert(is_equal_approx(rogue.movement_mult(), speed + 0.05))
	assert(is_equal_approx(rogue.respawn_shield_duration(), shield + 0.5))
	rogue.open_draft()
	rogue.choose_card(1) # The speed bonus stacks without using a system slot.
	assert(is_equal_approx(rogue.movement_mult(), speed + 0.1))
	rogue.pause_run()
	await shot("full-build-passives-pause")
	rogue.level = 2
	rogue.start_level()
	assert(rogue.draft_speed_stacks == 2 and rogue.draft_shield_stacks == 1, "Bonuses carry between sectors")
	rogue.start_run()
	assert(rogue.draft_speed_stacks == 0 and rogue.draft_shield_stacks == 0, "Run bonuses reset on a fresh expedition")

func check_routes() -> void:
	for seed_value in 20:
		var random := RandomNumberGenerator.new()
		random.seed = seed_value
		var route: Array = rogue.Sectors.make_route(random)
		assert(route.size() == 8)
		for depth in range(1, 9):
			assert(route[depth - 1].size() == (1 if depth in [1, 4, 8] else 2))
			if route[depth - 1].size() == 2:
				assert(route[depth - 1][0].stage != route[depth - 1][1].stage)
	for kind in ["salvage", "repair", "beacon", "cargo", "breach", "rival", "race"]:
		rogue.start_run()
		rogue.launch_destination(0)
		play_until_ready()
		rogue.lives = 0
		rogue.level_clear()
		rogue.ui_time = rogue.VICTORY_REVEAL
		rogue.continue_expedition()
		rogue.route[1][1].kind = kind
		rogue.route[1][1].stage = 7
		rogue.ui_time = 0.3
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = rogue.chart_position(3, 0)
		rogue._input(click)
		assert(rogue.chart_focus_depth == 3 and rogue.selection == 0 and rogue.phase == "chart", "Distant nodes can be inspected")
		var path_before: Array = rogue.route_path.duplicate()
		rogue.activate_choice(0)
		click.position = rogue.CHART_JUMP.get_center()
		rogue._input(click)
		assert(rogue.phase == "chart" and rogue.route_path == path_before and rogue.level == 1, "Locked preview cannot launch through Enter or click")
		rogue.move_chart_focus(Vector2i.RIGHT)
		assert(rogue.chart_focus_depth == 4)
		rogue.move_chart_focus(Vector2i.LEFT)
		rogue.move_chart_focus(Vector2i.DOWN)
		assert(rogue.chart_focus_depth == 3 and rogue.selection == 1)
		await shot("star-chart-locked-preview")
		click.position = rogue.chart_position(2, 1)
		rogue._input(click)
		assert(rogue.chart_focus_depth == 2 and rogue.selection == 1 and rogue.phase == "chart", "Selecting a node only previews it")
		await shot("star-chart-" + kind)
		rogue.launch_destination(-1)
		assert(rogue.phase == "chart")
		click.position = Vector2(1300, 760)
		rogue._input(click)
		assert(rogue.phase == "run" and rogue.route_path == [0, 1])
		play_until_ready()
		assert(rogue.level == 2 and rogue.arena_stage(2) == 7)
		assert(rogue.base_free + rogue.rival_home.count(1) == SectorArena.build(7, 0, "roguelite", rogue.Sectors.holes(7, Vector2i(160, 104)), Vector2i(160, 104)).base_free, "Protected Rival home is excluded from capturable area")
		assert(rogue.turrets.size() == rogue.Sectors.turret_count(kind, 2) and rogue.turrets.size() == (2 if kind == "salvage" else 1))
		assert(rogue.nodes.size() == 3 + rogue.progress.rank_of("extractor") / 5 + (2 if kind == "salvage" else 0))
		assert(rogue.corruption_active == (kind == "breach"), "Only a breach brings corruption forward")
		assert(rogue.zones.size() == (2 if kind == "beacon" else 0) and rogue.cargo.is_empty() != (kind == "cargo") and rogue.breach.is_empty() != (kind == "breach"))
		assert(is_equal_approx(rogue.capture_target(), 0.65) == (kind in ["salvage", "repair"]), "Objective kinds hold the territory clear back")
		assert((rogue.rival != null and rogue.rival.alive) == (kind == "rival"))
		rogue.level_clear()
		assert(rogue.lives == (1 if kind == "repair" else 0))
		rogue.finish_sector()
		assert(rogue.lives == (1 if kind == "repair" else 0), "Clear rewards apply once")
		rogue.ui_time = rogue.VICTORY_REVEAL
		rogue.continue_expedition()
		assert(rogue.chart_focus_depth == 3 and rogue.selection == 1, "Next selection follows the chosen lane")
		assert(not rogue.chart_reachable(3, 0) and rogue.chart_reachable(3, 1))
		rogue.move_chart_focus(Vector2i.UP)
		rogue.activate_choice(0)
		assert(rogue.phase == "chart" and rogue.route_path == [0, 1], "Cannot cross to the unconnected lane")
		assert(not rogue.chart_connected(2, 0, 1) and not rogue.chart_connected(2, 1, 0))
		assert(rogue.chart_connected(3, 1, 0) and rogue.chart_connected(4, 0, 1), "Merge and fork links remain")
		var runs: int = rogue.progress.runs
		rogue.end_run()
		rogue.end_run()
		assert(rogue.progress.runs == runs + 1, "Chart exits settle once")

func check_anomaly_coverage() -> void:
	rogue.transit_skip = true
	for shape_id in range(1, 9):
		for iteration in 8:
			rogue.start_run()
			rogue.launch_destination(0)
			rogue.active_destination = {"depth": shape_id, "stage": shape_id, "kind": "survey"}
			rogue.level = shape_id
			rogue.start_level()
			assert(rogue.qixes.size() == rogue.Sectors.anomaly_count(shape_id, shape_id))
			for q in rogue.qixes: assert(not rogue.qix_blocked(q.c, q.theta, q.len))
			if rogue.qixes.size() >= 2:
				assert(rogue.to_cell(rogue.qixes[0].c).x < rogue.grid_width / 2 - 10)
				assert(rogue.to_cell(rogue.qixes[1].c).x > rogue.grid_width / 2 + 10)
			if shape_id in [3, 6, 7]:
				# A vertical cut through the neck must leave both lobes occupied.
				rogue.phase = "run"
				rogue.state = Game.State.PLAYING
				rogue.sparxes.clear()
				rogue.freeze_time = 100
				var x: int = rogue.grid_width / 2
				var top := 0
				while rogue.cells[rogue.idx(x, top)] != Game.FREE: top += 1
				rogue.p = Vector2i(x, top - 1)
				rogue.vis = rogue.center(rogue.p)
				rogue.draw_armed = true
				for step in rogue.grid_height:
					assert(rogue.try_step(Vector2i.DOWN, true, false))
					if not rogue.drawing: break
				assert(not rogue.drawing and rogue.capture_percent < 5, "A middle cut cannot claim an undefended half")

func check_pacing_and_currency() -> void:
	assert(rogue.Sectors.draft_milestones(2500) == [35])
	assert(rogue.Sectors.draft_milestones(3799) == [35])
	assert(rogue.Sectors.draft_milestones(3800) == [25, 55])
	assert(rogue.Sectors.draft_milestones(4399) == [25, 55])
	assert(rogue.Sectors.draft_milestones(4400) == [20, 40, 60])
	assert(rogue.Sectors.draft_milestones(20000).size() == 3)
	var profile := Progress.new()
	profile.apply_profile({"version": 5, "salvage": 41, "salvage_fraction": 0.5, "ships": {"lancer": true}, "ranks": {"hull": 5}})
	assert(profile.salvage == 10 and is_equal_approx(profile.salvage_fraction, 0.375))
	assert(profile.owns_ship("lancer") and profile.rank_of("hull") == 5)
	profile.apply_profile({"version": 6, "salvage": 10, "salvage_fraction": 0.375})
	assert(profile.salvage == 10 and is_equal_approx(profile.salvage_fraction, 0.375), "New profiles never convert twice")
	assert(profile.SHIP_PRICE == 10 and profile.node_cost(1) == 2 and profile.node_cost(10) == 11)
