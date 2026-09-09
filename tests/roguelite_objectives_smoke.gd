extends "res://tests/roguelite_ships_smoke.gd"
## Beacon, cargo and breach encounters: placement, capture rules, clears, rewards and routes.
const Sectors = preload("res://scripts/roguelite_sectors.gd")
var lo := Vector2i.ZERO
var hi := Vector2i.ZERO

## Force a kind on a stage without fighting the chart RNG, then quiet the simulation.
func force_kind(ship_id: String, kind: String, depth: int, stage: int) -> void:
	fresh_ship(ship_id)
	rogue.active_destination = {"depth": depth, "stage": stage, "kind": kind}
	rogue.level = depth
	rogue.start_level()
	rogue.state = Game.State.PLAYING
	rogue.invuln = 0
	rogue.sparxes.clear()
	rogue.sparx_to_spawn = 0
	rogue.mites.clear()
	rogue.freeze_time = 100
	lo = Vector2i(999, 999)
	hi = Vector2i.ZERO
	for cell in rogue.field_arena.free_cells:
		lo = lo.min(cell)
		hi = hi.max(cell)
	assert(rogue.encounter_kind(depth) == kind and rogue.arena_stage(depth) == stage)

## Exact payout and clear checks need no pickups, turrets or milestone drafts in the way.
func bare_field() -> void:
	rogue.nodes.clear()
	rogue.turrets.clear()
	rogue.bolts.clear()
	rogue.drafts_taken = rogue.draft_capture.size()

func park_anomalies(cell: Vector2i) -> void:
	assert(rogue.cells[rogue.idx(cell.x, cell.y)] == Game.FREE)
	for q in rogue.qixes:
		q.c = rogue.center(cell)
		q.len = 1.0
		q.v = Vector2.ZERO

func zone(cell: Vector2i) -> Dictionary:
	return {"cell": cell, "radius": Sectors.BEACON_RADIUS, "captured": false, "spin": 0.0}

## A real cut from a rail cell in one direction until it lands on land again.
func cut_line(start: Vector2i, dir: Vector2i, steps: int) -> void:
	assert(rogue.cells[rogue.idx(start.x, start.y)] == Game.CLAIMED, "Cuts start from land")
	rogue.p = start
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in steps:
		assert(rogue.try_step(dir, true, false), "The cut must reach the far rail")
	assert(not rogue.drawing)

func cut_column(x: int) -> void:
	cut_line(Vector2i(x, lo.y - 1), Vector2i.DOWN, hi.y - lo.y + 2)

func resolve_to_clear() -> void:
	for step in 300:
		if rogue.phase == "reward" or rogue.phase == "install":
			rogue.update(0.1)
		elif rogue.phase == "draft":
			rogue.ui_time = rogue.DRAFT_REVEAL
			rogue.choose_card(0)
		elif rogue.phase == "replace":
			rogue.activate_choice(0)
		else:
			return
	assert(false, "Queued rewards must always finish")

func render_frame() -> void:
	main.display.tick(0.016)
	main.display.begin_draw()
	main.game.draw()
	main.display.end_draw()

func check() -> void:
	assert(not Save.enabled)
	# Placement fixtures describe built-in arenas, independent of maps edited by the player.
	for stage in range(1, 9): MapCatalog.testing["roguelite_%02d" % stage] = null
	Save.set_process(false)
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
	rogue.progress.apply_profile({"version": 6, "ships": {"surveyor": true, "lancer": true, "sapper": true}})
	assert(not rogue.progress.containment_unlocked and rogue.progress.best_sector == 1)
	check_table_and_routes()
	await check_placement()
	check_beacon()
	check_cargo()
	check_breach()
	await check_surge()
	check_rival()
	await check_objective_guidance()
	await check_sector_briefings()
	await check_corruption_guidance()
	rogue.end_run()
	MapCatalog.testing.clear()
	assert(Save.data == campaign, "Objective encounters leave Jump untouched")
	print("ROGUELITE OBJECTIVES OK: kind table and routes, disc placement, beacon capture/guard/clear, cargo pickup/delivery/drop for every ship, breach seeding/pressure/seal and goal ordering, surge stall/capture/expiry/pause, rival planning/claims/contact/steals/elimination")
	get_tree().quit()

func check_table_and_routes() -> void:
	assert(Sectors.alternate_kinds(2) == ["salvage", "repair", "beacon"])
	assert(Sectors.alternate_kinds(3) == ["salvage", "repair", "beacon", "cargo", "rival"])
	assert(Sectors.alternate_kinds(5) == ["salvage", "repair", "beacon", "cargo", "breach", "rival"])
	assert(Sectors.turret_count("salvage", 2) == 2 and Sectors.turret_count("beacon", 2) == 1 and Sectors.turret_count("survey", 1) == 0)
	assert(Sectors.objective_count("beacon", 3) == 2 and Sectors.objective_count("beacon", 5) == 3)
	assert(Sectors.objective_count("cargo", 4) == 2 and Sectors.objective_count("cargo", 5) == 3 and Sectors.objective_count("breach", 7) == 1)
	assert(Sectors.objective_count("survey", 5) == 0 and Sectors.reward_copy("survey") == "")
	assert(not Sectors.territory_goal("beacon") and not Sectors.territory_goal("cargo") and Sectors.territory_goal("breach") and Sectors.territory_goal("repair"))
	var seen := {}
	for seed_value in 200:
		var random := RandomNumberGenerator.new()
		random.seed = seed_value
		var route: Array = Sectors.make_route(random)
		var previous := ""
		assert(route.size() == 8)
		for depth in range(1, 9):
			var row: Array = route[depth - 1]
			assert(row.size() == (1 if depth in [1, 4, 8] else 2))
			assert(row[0].kind == "survey" and row[0].stage == depth and row[0].depth == depth)
			if row.size() == 2:
				var kind: String = row[1].kind
				assert(Sectors.KINDS.has(kind) and kind != "survey")
				assert(int(Sectors.KINDS[kind].min_depth) <= depth, "Kinds respect their depth gate")
				assert(kind != previous, "Consecutive forks never repeat a kind")
				assert(row[0].stage != row[1].stage)
				previous = kind
				seen[kind] = true
	for kind in ["salvage", "repair", "beacon", "cargo", "breach", "rival"]:
		assert(seen.has(kind), "Every kind appears across seeds: " + kind)

func check_placement() -> void:
	for stage in range(2, 9):
		for kind in ["beacon", "cargo", "breach", "rival"]:
			var depth := maxi(stage, int(Sectors.KINDS[kind].min_depth))
			force_kind("surveyor", kind, depth, stage)
			var avoid: Array = [rogue.p]
			for nd in rogue.nodes: avoid.append(nd.cell)
			for tr in rogue.turrets: avoid.append(tr.cell)
			assert(rogue.turrets.size() == 1 and rogue.nodes.size() == 3, "Objective kinds keep survey pickups and turrets")
			match kind:
				"beacon":
					assert(rogue.zones.size() == Sectors.objective_count(kind, depth))
					assert(rogue.cargo.is_empty() and rogue.breach.is_empty())
					for z in rogue.zones:
						assert(int(z.radius) == Sectors.BEACON_RADIUS, "Every roguelite arena fits full beacon discs")
						for i in rogue.disc_cells(z.cell, z.radius):
							assert(rogue.cells[i] == Game.FREE, "Beacon discs start entirely in the void")
						for a in avoid:
							assert(Vector2(z.cell - (a as Vector2i)).length() >= z.radius + 4, "Beacons keep clear of pickups, turrets and the start")
						avoid.append(z.cell)
					assert(is_equal_approx(rogue.capture_target(), 2.0) and rogue.bar_scale() == 100.0)
					assert(rogue.objective_label() == "BEACONS 0/%d" % rogue.zones.size())
				"cargo":
					assert(rogue.zones.is_empty() and rogue.breach.is_empty())
					assert(int(rogue.cargo.runs) == Sectors.objective_count(kind, depth) and not rogue.cargo.carrying)
					var c: Vector2i = rogue.cargo.cell
					assert(rogue.cells[rogue.idx(c.x, c.y)] == Game.FREE)
					assert(Vector2(c - rogue.p).length() >= 20, "The pod starts far from the ship")
					assert(is_equal_approx(rogue.capture_target(), 2.0) and rogue.objective_label().begins_with("CARGO 0/"))
				"breach":
					assert(rogue.zones.is_empty() and rogue.cargo.is_empty())
					assert(rogue.corruption_active and int(rogue.breach.radius) == Sectors.BREACH_RADIUS and not rogue.breach.sealed)
					var disc: PackedInt32Array = rogue.disc_cells(rogue.breach.cell, rogue.breach.radius)
					for i in disc:
						assert(rogue.cells[i] == Game.FREE and rogue.corruption[i] == 1)
					assert(rogue.corruption.count(1) == disc.size(), "A breach sector seeds only its own disc")
					assert(is_equal_approx(rogue.capture_target(), 2.0), "An open breach holds the territory goal back")
					assert(rogue.objective_label() == "CAPTURE %d%%" % Sectors.capture_goal(depth) and rogue.bar_scale() == float(Sectors.capture_goal(depth)))
					if depth < Sectors.CORRUPTION_SECTOR: assert(not rogue.progress.containment_unlocked and not rogue.progress.track_available("containment"), "A breach does not unlock the Containment track")
					assert(not rogue.draft_exclusions().has("clean") and not rogue.draft_exclusions().has("containment"))
				"rival":
					assert(rogue.zones.is_empty() and rogue.cargo.is_empty() and rogue.breach.is_empty())
					assert(rogue.rival != null and rogue.rival.alive and rogue.rival_land.size() == rogue.cells.size())
					var seed_disc: PackedInt32Array = rogue.disc_cells(rogue.rival.pos, Sectors.RIVAL_RADIUS)
					for i in seed_disc:
						assert(rogue.cells[i] == Game.FREE and rogue.rival_land[i] == 1, "The rival's seed sits entirely in live void")
					assert(rogue.rival_land.count(1) == seed_disc.size() and rogue.rival.owned.size() == seed_disc.size())
					for a in avoid:
						assert(Vector2(rogue.rival.pos - (a as Vector2i)).length() >= Sectors.RIVAL_RADIUS + 4)
					assert(is_equal_approx(rogue.capture_target(), Sectors.capture_goal(depth) / 100.0), "A rival sector keeps the territory goal")
					assert(rogue.objective_label() == "CAPTURE %d%%" % Sectors.capture_goal(depth) and rogue.corruption_active == (depth >= Sectors.CORRUPTION_SECTOR))
			render_frame()
			if stage == 3: await shot("objective-" + kind)
	# Survey stays survey: the label, scale and goal are untouched.
	force_kind("surveyor", "survey", 3, 1)
	assert(rogue.zones.is_empty() and rogue.cargo.is_empty() and rogue.breach.is_empty())
	assert(is_equal_approx(rogue.capture_target(), 0.7) and rogue.bar_scale() == 70.0 and rogue.objective_label() == "CAPTURE 70%")
	for kind in Sectors.KINDS:
		rogue.draw_chart_symbol(kind, Vector2(100, 100), Palette.CYAN)

func check_beacon() -> void:
	# OPEN FIELD is a plain square: a full-height cut claims whichever side has no Anomaly.
	force_kind("surveyor", "beacon", 3, 1)
	bare_field()
	var a := lo + Vector2i(7, 7)
	var b := hi - Vector2i(7, 7)
	rogue.zones.assign([zone(a), zone(b)])
	park_anomalies(Vector2i(hi.x - 2, lo.y + 25))
	var salvage: int = rogue.earned_salvage
	var lives: int = rogue.lives
	cut_column(a.x + 7)
	assert(rogue.zones[0].captured and not rogue.zones[1].captured, "Enclosing a disc secures it")
	assert(rogue.earned_salvage == salvage + 1 and rogue.phase == "run" and not rogue.pending_clear)
	assert(rogue.objective_label() == "BEACONS 1/2")
	cut_column(b.x - 7)
	assert(rogue.capture_percent >= Sectors.capture_goal(3) and not rogue.zones[1].captured)
	assert(rogue.phase == "run" and not rogue.pending_clear, "Territory alone neither clears nor strands a beacon sector")
	render_frame()
	cut_line(Vector2i(hi.x - 14, b.y - 7), Vector2i.RIGHT, 15)
	assert(rogue.zones[1].captured and rogue.pending_clear and rogue.phase == "reward")
	assert(rogue.earned_salvage == salvage + 2)
	resolve_to_clear()
	assert(rogue.phase == "sector_clear" and rogue.lives == lives and rogue.run_sectors == 3)
	# An Anomaly inside the disc keeps the whole region alive.
	force_kind("surveyor", "beacon", 3, 1)
	bare_field()
	rogue.zones.assign([zone(a), zone(b)])
	park_anomalies(a)
	cut_column(a.x + 7)
	assert(not rogue.zones[0].captured and rogue.disc_claimed_fraction(a, Sectors.BEACON_RADIUS) == 0.0, "A guarded beacon cannot be enclosed")
	assert(rogue.capture_percent > 50, "The unguarded far side is claimed instead")
	# Milestone and objective on one cut: the draft opens first, then the sector clears once.
	force_kind("surveyor", "beacon", 3, 1)
	bare_field()
	rogue.drafts_taken = 0
	assert(rogue.draft_capture == [35])
	rogue.zones.assign([zone(a), zone(a + Vector2i(0, 24))])
	park_anomalies(Vector2i(hi.x - 2, lo.y + 25))
	lives = rogue.lives
	cut_column(lo.x + 18)
	assert(rogue.zones[0].captured and rogue.zones[1].captured and rogue.capture_percent >= 35)
	assert(rogue.phase == "reward" and rogue.pending_clear)
	resolve_to_clear()
	assert(rogue.phase == "sector_clear" and rogue.owned_cards.size() == 1 and rogue.lives == lives)
	# Guards drift back toward an open beacon; frozen Anomalies never move.
	force_kind("surveyor", "beacon", 3, 1)
	bare_field()
	rogue.zones.assign([zone(a)])
	var far := Vector2i(hi.x - 12, hi.y - 12)
	park_anomalies(far)
	var q = rogue.qixes[0]
	q.v = Vector2.RIGHT * 70.0
	var start_distance: float = q.c.distance_to(rogue.center(a))
	rogue.update_qix(q, 0.05, rogue.qix_speed())
	assert(q.c == rogue.center(far), "Frozen Anomalies hold position")
	rogue.freeze_time = 0
	seed(7)
	for step in 80:
		rogue.update_qix(q, 0.05, rogue.qix_speed())
	assert(q.c.distance_to(rogue.center(a)) < start_distance - 40.0, "A far Anomaly is pulled toward its beacon")
	rogue.freeze_time = 100

func cargo_fixture(ship_id: String) -> Vector2i:
	force_kind(ship_id, "cargo", 3, 1)
	bare_field()
	var c := lo + Vector2i(10, 10)
	rogue.cargo.cell = c
	park_anomalies(Vector2i(hi.x - 3, lo.y + 25))
	return c

func check_cargo() -> void:
	var c := cargo_fixture("surveyor")
	var salvage: int = rogue.earned_salvage
	assert(int(rogue.cargo.runs) == 2)
	rogue.p = Vector2i(c.x, lo.y - 1)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in 10:
		assert(rogue.try_step(Vector2i.DOWN, true, false))
		assert(not rogue.cargo.carrying, "No pickup before the ship reaches the pod")
	assert(rogue.try_step(Vector2i.DOWN, true, false) and rogue.p == c and rogue.cargo.carrying, "The trail head picks the pod up")
	assert(rogue.objective_instruction().contains("RETURN TO SAFE LAND") and rogue.objective_notice.begins_with("CARGO ABOARD"))
	for step in hi.y - c.y + 1:
		assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(not rogue.drawing and not rogue.cargo.carrying and int(rogue.cargo.delivered) == 1)
	assert(rogue.earned_salvage == salvage + 2 and rogue.phase == "run" and not rogue.pending_clear)
	var moved: Vector2i = rogue.cargo.cell
	assert(moved != c and rogue.cells[rogue.idx(moved.x, moved.y)] == Game.FREE, "The next pod waits in the void")
	assert(rogue.objective_label() == "CARGO 1/2")
	assert(rogue.objective_notice.begins_with("CARGO DELIVERED 1/2") and rogue.objective_notice_time > 0)
	# The second run completes the objective on the same claim.
	var c2 := Vector2i(hi.x - 10, lo.y + 10)
	rogue.cargo.cell = c2
	cut_column(c2.x)
	assert(int(rogue.cargo.delivered) == 2 and rogue.cargo.done and rogue.pending_clear and rogue.phase == "reward")
	assert(rogue.earned_salvage == salvage + 4)
	resolve_to_clear()
	assert(rogue.phase == "sector_clear")
	# Enclosed without contact: the pod moves rather than sitting unreachable on land.
	c = cargo_fixture("surveyor")
	cut_column(c.x + 5)
	assert(rogue.cells[rogue.idx(c.x, c.y)] == Game.CLAIMED and rogue.cargo.cell != c and not rogue.cargo.carrying)
	moved = rogue.cargo.cell
	assert(rogue.cells[rogue.idx(moved.x, moved.y)] == Game.FREE and int(rogue.cargo.delivered) == 0)
	assert(rogue.objective_notice.begins_with("POD RELOCATED") and rogue.objective_instruction().contains("ENCLOSING ALONE DOES NOT DELIVER"), "Enclosing without touching explains the missing delivery")
	var notice: String = rogue.objective_notice
	var notice_time: float = rogue.objective_notice_time
	rogue.begin_draft_reward()
	rogue.update(0.016)
	assert(rogue.objective_notice == notice and rogue.objective_notice_time == notice_time, "Card rewards must not consume objective feedback")
	# Death drops the pod where it was; hardened trail turning to land relocates it.
	c = cargo_fixture("surveyor")
	var lives: int = rogue.lives
	cut_line_to(c)
	assert(rogue.cargo.carrying)
	rogue.invuln = 1.0
	rogue.die("TEST")
	assert(rogue.cargo.carrying and rogue.lives == lives, "A shielded brush keeps the cargo")
	rogue.invuln = 0
	rogue.die("TEST")
	assert(not rogue.cargo.carrying and rogue.lives == lives - 1)
	assert(rogue.objective_notice.begins_with("CARGO DROPPED"))
	assert(rogue.cargo.cell == c and rogue.cells[rogue.idx(c.x, c.y)] == Game.FREE, "Dropped cargo returns to its cell")
	rogue.state = Game.State.PLAYING
	c = cargo_fixture("surveyor")
	cut_line_to(c)
	for cell in rogue.trail:
		rogue.cells[rogue.idx(cell.x, cell.y)] = Game.HARD
	rogue.die("TEST")
	assert(not rogue.cargo.carrying and rogue.cargo.cell != c and rogue.cells[rogue.idx(c.x, c.y)] == Game.CLAIMED)
	moved = rogue.cargo.cell
	assert(rogue.cells[rogue.idx(moved.x, moved.y)] == Game.FREE, "Cargo buried under hardened land relocates")
	rogue.state = Game.State.PLAYING
	c = cargo_fixture("surveyor")
	rogue.owned_cards.assign(["anchor"])
	cut_line_to(c)
	lives = rogue.lives
	rogue.die("TEST")
	assert(rogue.lives == lives and not rogue.cargo.carrying and rogue.cargo.cell == c, "Anchor recovery still drops the cargo")
	assert(rogue.cells[rogue.idx(c.x, c.y)] == Game.FREE)
	# Carrying draws the Anomaly toward the ship.
	c = cargo_fixture("surveyor")
	cut_line_to(c)
	var q = rogue.qixes[0]
	var far := Vector2i(hi.x - 12, hi.y - 12)
	park_anomalies(far)
	q.v = Vector2.UP * 70.0
	rogue.freeze_time = 0
	seed(3)
	var start_distance: float = q.c.distance_to(rogue.vis)
	for step in 60:
		rogue.update_qix(q, 0.05, rogue.qix_speed())
	assert(q.c.distance_to(rogue.vis) < start_distance - 40.0, "The Anomaly hunts a cargo carrier")
	rogue.freeze_time = 100
	render_frame()
	# Lancer: the ray marks the pod early, the run starts when the ride reaches it.
	c = cargo_fixture("lancer")
	salvage = rogue.earned_salvage
	rogue.p = Vector2i(c.x, lo.y - 1)
	rogue.vis = rogue.center(rogue.p)
	rogue.last_dir = Vector2i.DOWN
	rogue.lance_cd = 0
	rogue.fire_lance()
	assert(rogue.tether_active and rogue.trail.has(c) and not rogue.cargo.carrying, "Casting the tether is not contact")
	rogue.update(0.016)
	assert(rogue.cargo.cell == c and not rogue.cargo.carrying, "Cargo must stay on an exposed tether until the rider reaches it")
	for step in 200:
		if rogue.cargo.carrying: break
		rogue.update(0.016)
		assert(rogue.cargo.carrying == (rogue.p == c), "Pickup happens exactly when the ride reaches the pod")
	assert(rogue.cargo.carrying)
	for step in 200:
		if not rogue.tether_active: break
		rogue.update(0.016)
	assert(not rogue.tether_active and int(rogue.cargo.delivered) == 1 and rogue.earned_salvage == salvage + 2)
	# Sapper: walks the void to the pod, and delivers by stepping back onto land.
	c = cargo_fixture("sapper")
	salvage = rogue.earned_salvage
	rogue.p = Vector2i(c.x, lo.y - 1)
	rogue.vis = rogue.center(rogue.p)
	for step in 11:
		assert(rogue.try_step(Vector2i.DOWN, false, false))
	assert(rogue.p == c and rogue.exposed() and rogue.cargo.carrying, "An exposed Sapper picks the pod up by touch")
	for step in 11:
		assert(rogue.try_step(Vector2i.UP, false, false))
	assert(not rogue.exposed() and rogue.cargo.carrying)
	rogue.update(0.016)
	assert(not rogue.cargo.carrying and int(rogue.cargo.delivered) == 1 and rogue.earned_salvage == salvage + 2, "Reaching land delivers without a claim")

## Cut straight down from the top rail onto the pod and stop there, still exposed.
func cut_line_to(c: Vector2i) -> void:
	rogue.p = Vector2i(c.x, lo.y - 1)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in c.y - lo.y + 1:
		assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.p == c and rogue.drawing and rogue.cargo.carrying)

func infect_share(share: float) -> void:
	var free: Array = rogue.field_arena.free_cells
	var count := ceili(share * rogue.base_free)
	for i in mini(count, free.size()):
		var cell: Vector2i = free[i]
		if rogue.cells[rogue.idx(cell.x, cell.y)] == Game.FREE:
			rogue.corruption[rogue.idx(cell.x, cell.y)] = 1

func check_breach() -> void:
	force_kind("surveyor", "breach", 5, 1)
	bare_field()
	var b := lo + Vector2i(12, 12)
	rogue.breach.cell = b
	rogue.corruption.fill(0)
	rogue.seed_corruption()
	var disc: PackedInt32Array = rogue.disc_cells(b, Sectors.BREACH_RADIUS)
	assert(rogue.corruption.count(1) == disc.size())
	rogue.corruption.fill(0)
	rogue.spread_corruption()
	for i in disc:
		assert(rogue.corruption[i] == 1, "An open breach re-seeds after cleansing")
	# Past the limit the ship takes a hit and the infection collapses to the source.
	var lives: int = rogue.lives
	rogue.corruption.fill(0)
	infect_share(0.3)
	rogue.spread_corruption()
	assert(rogue.lives == lives - 1 and rogue.state == Game.State.DYING, "Containment loss costs a hull")
	assert(rogue.corruption.count(1) == disc.size() and float(rogue.breach.pressure) < Sectors.BREACH_LIMIT)
	rogue.state = Game.State.PLAYING
	rogue.invuln = 1.0
	infect_share(0.3)
	rogue.spread_corruption()
	assert(rogue.lives == lives - 1 and rogue.corruption.count(1) > disc.size(), "A shielded ship keeps its hull and the meter stays")
	rogue.invuln = 0
	rogue.corruption.fill(0)
	rogue.seed_corruption()
	# Sealing pays, restores the territory goal, and stops the spread.
	var salvage: int = rogue.earned_salvage
	park_anomalies(Vector2i(hi.x - 3, lo.y + 25))
	assert(is_equal_approx(rogue.capture_target(), 2.0))
	cut_column(b.x + 6)
	assert(rogue.breach.sealed and rogue.earned_salvage == salvage + 3, "Enclosing the breach seals it")
	assert(is_equal_approx(rogue.capture_target(), 0.8) and rogue.phase == "run" and not rogue.pending_clear)
	for i in disc:
		assert(rogue.corruption[i] == 0)
	infect_share(0.05)
	var infected: int = rogue.corruption.count(1)
	rogue.spread_corruption()
	assert(rogue.corruption.count(1) == infected, "A sealed breach spreads no further")
	render_frame()
	# Reaching the goal before the seal does not clear; sealing afterwards clears at once.
	force_kind("surveyor", "breach", 3, 1)
	bare_field()
	b = hi - Vector2i(7, 7)
	rogue.breach.cell = b
	rogue.breach.radius = Sectors.BREACH_RADIUS
	rogue.corruption.fill(0)
	rogue.seed_corruption()
	park_anomalies(Vector2i(hi.x - 2, lo.y + 25))
	lives = rogue.lives
	cut_column(b.x - 7)
	assert(rogue.capture_percent >= Sectors.capture_goal(3) and not rogue.breach.sealed)
	assert(rogue.phase == "run" and not rogue.pending_clear, "The goal waits for the seal")
	cut_line(Vector2i(hi.x - 14, b.y - 7), Vector2i.RIGHT, 15)
	assert(rogue.breach.sealed and rogue.pending_clear and rogue.phase == "reward")
	resolve_to_clear()
	assert(rogue.phase == "sector_clear" and rogue.lives == lives)

func wait_for_surge() -> void:
	for i in 230:
		if not rogue.surge.is_empty():
			return
		rogue.update(0.1)
	assert(false, "The stall clock must surface a surge within the limit")

func check_surge() -> void:
	force_kind("surveyor", "survey", 3, 1)
	bare_field()
	rogue.freeze_time = 1000
	park_anomalies(Vector2i(hi.x - 3, lo.y + 25))
	rogue.rng.seed = 5
	var salvage: int = rogue.earned_salvage
	var base_speed: float = rogue.qix_speed()
	assert(rogue.stall_time == 0.0 and rogue.surge.is_empty() and rogue.surge_pressure == 0.0)
	for i in 199:
		rogue.update(0.1)
	assert(rogue.surge.is_empty() and rogue.stall_time > 19.0, "No surge before the stall limit")
	rogue.update(0.2)
	assert(not rogue.surge.is_empty() and float(rogue.surge.telegraph) > 0.0, "A stalled sector surfaces a surge")
	var cell: Vector2i = rogue.surge.cell
	for i in rogue.disc_cells(cell, rogue.surge.radius):
		assert(rogue.cells[i] == Game.FREE, "The surge disc is live void")
	for q in rogue.qixes:
		assert(q.c.distance_to(rogue.center(cell)) >= q.len * 0.5 + (int(rogue.surge.radius) + 3) * Game.CELL, "The surge keeps clear of Anomalies")
	render_frame()
	for i in 21:
		rogue.update(0.1)
	assert(float(rogue.surge.telegraph) == 0.0 and float(rogue.surge.window) < rogue.SURGE_WINDOW, "The telegraph gives way to the window")
	render_frame()
	await shot("surge-active")
	rogue.surge.cell = lo + Vector2i(7, 7)
	cut_column(lo.x + 12)
	assert(rogue.surge.is_empty() and rogue.earned_salvage == salvage + 2 and rogue.stall_time == 0.0, "Enclosing the surge pays two salvage")
	assert(rogue.objective_notice.begins_with("SURGE SECURED"))
	# Expiry one and two queue a Sparx; later misses speed the Anomaly instead.
	for expiry in range(1, 4):
		wait_for_surge()
		rogue.surge.telegraph = 0.0
		rogue.surge.window = 0.05
		rogue.sparx_to_spawn = 0
		rogue.update(0.1)
		assert(rogue.surge.is_empty() and rogue.surge_expired == expiry and rogue.stall_time == 0.0)
		if expiry <= 2:
			assert(rogue.sparx_to_spawn == 1 and rogue.sparx_spawn_t == 0.0, "A missed surge brings a Sparx")
			assert(is_equal_approx(rogue.qix_speed(), base_speed))
		else:
			assert(rogue.sparx_to_spawn == 0 and is_equal_approx(rogue.surge_pressure, 0.1))
			assert(is_equal_approx(rogue.qix_speed(), base_speed * 1.1), "Later misses speed the Anomaly")
		rogue.sparx_to_spawn = 0
		rogue.sparxes.clear()
	# Pausing freezes the window.
	wait_for_surge()
	rogue.surge.telegraph = 0.0
	var window: float = rogue.surge.window
	rogue.pause_run()
	assert(rogue.phase == "paused")
	for i in 30:
		rogue.update(0.1)
	assert(is_equal_approx(float(rogue.surge.window), window), "Pausing freezes the surge window")
	rogue.resume_run()
	rogue.update(0.1)
	assert(float(rogue.surge.window) < window)
	# A surge shares a sector with beacons: one cut can secure both, and discs never overlap.
	force_kind("surveyor", "beacon", 3, 1)
	bare_field()
	rogue.freeze_time = 1000
	var a := lo + Vector2i(7, 7)
	rogue.zones.assign([zone(a), zone(hi - Vector2i(7, 7))])
	park_anomalies(Vector2i(hi.x - 2, lo.y + 25))
	rogue.surge = {"cell": a + Vector2i(0, 16), "radius": rogue.SURGE_RADIUS, "telegraph": 0.0, "window": rogue.SURGE_WINDOW, "spin": 0.0}
	salvage = rogue.earned_salvage
	cut_column(a.x + 7)
	assert(rogue.zones[0].captured and rogue.surge.is_empty() and rogue.earned_salvage == salvage + 3, "A cut can secure a beacon and a surge together")
	assert(rogue.phase == "run" and not rogue.pending_clear)
	wait_for_surge()
	var far_disc: PackedInt32Array = rogue.disc_cells(rogue.zones[1].cell, rogue.zones[1].radius)
	for i in rogue.disc_cells(rogue.surge.cell, rogue.surge.radius):
		assert(not far_disc.has(i), "Surges never overlap beacon discs")
	rogue.freeze_time = 100

## A rival sector on the plain square, with a hand-placed seed so geometry is exact.
func rival_fixture(ship_id: String) -> Vector2i:
	force_kind(ship_id, "rival", 3, 1)
	bare_field()
	rogue.freeze_time = 1000
	park_anomalies(Vector2i(hi.x - 3, lo.y + 25))
	var seed_cell := lo + Vector2i(12, 12)
	rogue.setup_rival(seed_cell, Sectors.RIVAL_RADIUS)
	rogue.rng.seed = 9
	return seed_cell

## Walk the rival straight out of its seed into the void so it carries a live line.
func rival_line_out(seed_cell: Vector2i, steps: int) -> void:
	rogue.rival.pos = seed_cell + Vector2i(0, -Sectors.RIVAL_RADIUS)
	rogue.rival.exposed = false
	rogue.rival.clear_trail()
	for i in steps:
		assert(rogue.rival.step(Vector2i.UP), "The rival can cut into open void")
	assert(rogue.rival.exposed and rogue.rival.trail.size() == steps)

func check_rival() -> void:
	var seed_cell := rival_fixture("surveyor")
	var free_before: int = rogue.free_count
	var owned_before: int = rogue.rival.owned.size()
	assert(owned_before == rogue.disc_cells(seed_cell, Sectors.RIVAL_RADIUS).size())
	# The planner finds a loop, walks it, and the flood grants what the loop walls off.
	var grew := false
	for i in 800:
		rogue.rival.tick(0.1)
		if rogue.rival.owned.size() > owned_before:
			grew = true
			break
	assert(grew and not rogue.rival.exposed, "The rival plans and completes a claim on its own")
	assert(rogue.free_count == free_before and rogue.capture_percent == 0.0, "Rival land is still void to the player")
	for i in rogue.cells.size():
		if rogue.rival_land[i] == 1: assert(rogue.cells[i] == Game.FREE)
	assert(rogue.rival_land.count(1) == rogue.rival.owned.size())
	render_frame()
	# Anomalies floating over rival land still seed the flood from open void beside them.
	seed_cell = rival_fixture("surveyor")
	park_anomalies(seed_cell)
	owned_before = rogue.rival.owned.size()
	rogue.rival_capture([])
	assert(rogue.rival.owned.size() == owned_before, "A seedless loop cannot swallow the arena")
	assert(rogue.rival_land.count(1) < 0.4 * rogue.base_free)
	# The rival's line crossing ours costs the line, not a hull; protections still hold.
	seed_cell = rival_fixture("surveyor")
	var lives: int = rogue.lives
	var column := lo.x + 30
	cut_line_to_row(column, lo.y + 9)
	var target := Vector2i(column, lo.y + 5)
	assert(rogue.cells[rogue.idx(target.x, target.y)] == Game.TRAIL)
	rogue.rival.pos = target + Vector2i.LEFT
	rogue.rival.exposed = true
	rogue.rival.anchor = seed_cell
	assert(rogue.rival.step(Vector2i.RIGHT))
	assert(not rogue.drawing and rogue.trail.is_empty() and rogue.p == rogue.anchor and rogue.lives == lives, "A rival cut sends the ship home with its hull")
	assert(rogue.cells.count(Game.TRAIL) == 0 and rogue.invuln > 0.0 and rogue.objective_notice.begins_with("RIVAL CUT YOUR LINE"))
	assert(rogue.rival.pos == target and rogue.rival.trail.has(target), "The rival keeps cutting through")
	rogue.invuln = 0.0
	rogue.rival.clear_trail()
	rogue.rival.exposed = false
	rogue.rival.pos = seed_cell
	cut_line_to_row(column, lo.y + 9)
	rogue.hardlight_time = 2.0
	rogue.rival.pos = target + Vector2i.LEFT
	rogue.rival.exposed = true
	assert(rogue.rival.step(Vector2i.RIGHT))
	assert(rogue.drawing and rogue.trail.size() == 10, "Hardlight shrugs the rival off")
	rogue.hardlight_time = 0.0
	rogue.lose_trail("TEST")
	# Crossing the rival's line, by step, by lance, or by beam, fails it back to its land.
	seed_cell = rival_fixture("surveyor")
	rival_line_out(seed_cell, 6)
	var line_cell: Vector2i = rogue.rival.trail[3]
	rogue.p = Vector2i(lo.x - 1, line_cell.y)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in line_cell.x - lo.x + 1:
		assert(rogue.try_step(Vector2i.RIGHT, true, false))
	assert(rogue.p == line_cell and rogue.rival.trail.is_empty() and not rogue.rival.exposed, "Stepping on the rival's line cuts it")
	assert(rogue.rival_land[rogue.idx(rogue.rival.pos.x, rogue.rival.pos.y)] == 1, "The rival returns to its land")
	rogue.lose_trail("TEST")
	seed_cell = rival_fixture("lancer")
	rival_line_out(seed_cell, 6)
	line_cell = rogue.rival.trail[2]
	rogue.p = Vector2i(lo.x - 1, line_cell.y)
	rogue.vis = rogue.center(rogue.p)
	rogue.last_dir = Vector2i.RIGHT
	rogue.lance_cd = 0
	rogue.fire_lance()
	assert(rogue.tether_active and rogue.rival.trail.is_empty(), "A cast tether cuts the rival's line where it crosses")
	rogue.lose_trail("TEST")
	seed_cell = rival_fixture("surveyor")
	rival_line_out(seed_cell, 6)
	line_cell = rogue.rival.trail[4]
	rogue.qixes[0].c = rogue.center(line_cell)
	rogue.qixes[0].len = 1.0
	rogue.update_rival(0.0)
	assert(rogue.rival.trail.is_empty() and not rogue.rival.exposed, "An Anomaly beam cuts the rival's line")
	park_anomalies(Vector2i(hi.x - 3, lo.y + 25))
	# Land closing over its line fails it; a blast takes the land under it and displaces it.
	seed_cell = rival_fixture("sapper")
	rival_line_out(seed_cell, 4)
	rogue.p = seed_cell + Vector2i(0, -Sectors.RIVAL_RADIUS - 2)
	rogue.vis = rogue.center(rogue.p)
	rogue.start_sapper_charge()
	rogue.sap_charge = 4.0
	rogue.detonate(4)
	assert(rogue.rival.trail.is_empty() and not rogue.rival.exposed, "Land over the rival's line cuts it")
	assert(rogue.rival.alive and rogue.rival.owned.size() < owned_before and rogue.rival.owned.size() > 0, "A blast takes rival land")
	assert(rogue.rival_land[rogue.idx(rogue.rival.pos.x, rogue.rival.pos.y)] == 1 and rogue.capture_percent > 0.0, "The rival stands on what it has left and the steal counts")
	# Stasis holds the rival; release lets it move through the real update path.
	seed_cell = rival_fixture("surveyor")
	rogue.freeze_time = 100
	var held: Vector2i = rogue.rival.pos
	for i in 20:
		rogue.update(0.1)
	assert(rogue.rival.pos == held and rogue.rival.trail.is_empty(), "A frozen rival does not move")
	rogue.freeze_time = 0.0
	var moved := false
	for i in 60:
		rogue.update(0.1)
		if rogue.rival.pos != held or not rogue.rival.trail.is_empty():
			moved = true
			break
	assert(moved, "The rival runs through the play loop")
	rogue.freeze_time = 1000
	# Enclosing the last of its land drives it off and pays; the depth goal still clears.
	seed_cell = rival_fixture("surveyor")
	var salvage: int = rogue.earned_salvage
	cut_column(lo.x + 18)
	assert(not rogue.rival.alive and rogue.rival_land.count(1) == 0 and rogue.earned_salvage == salvage + 3, "Taking every rival cell drives it off")
	assert(rogue.objective_notice.begins_with("RIVAL DRIVEN OFF") and rogue.capture_percent > 0.0)
	render_frame()
	cut_column(hi.x - 14)
	assert(rogue.capture_percent >= Sectors.capture_goal(3) and rogue.pending_clear and rogue.phase == "reward", "A rival sector clears on the depth goal")
	resolve_to_clear()
	assert(rogue.phase == "sector_clear")

## Cut straight down from the top rail to a row and stop there, still exposed.
func cut_line_to_row(x: int, y: int) -> void:
	rogue.p = Vector2i(x, lo.y - 1)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in y - lo.y + 1:
		assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.p == Vector2i(x, y) and rogue.drawing)

func check_objective_guidance() -> void:
	for kind in Sectors.KINDS:
		var depth := maxi(3, int(Sectors.KINDS[kind].min_depth))
		force_kind("surveyor", kind, depth, 3)
		var instruction: String = rogue.objective_instruction()
		assert(not instruction.is_empty())
		var rows: Array[String] = rogue.paragraph_lines(instruction, 820, 18)
		assert(rows.size() <= 3, "Briefing instructions fit above the reward and Begin button")
		for row in rows: assert(VectorFont.width(row, 18) <= 820)
		assert(VectorFont.width("OBJECTIVE: " + instruction, 13) <= 1120, "Objective instruction fits the pause screen")
		assert(VectorFont.width("OBJECTIVE: " + Sectors.objective_copy(kind, depth), 12) <= 1150, "Chart preview explains its clear rule without clipping")
		if kind == "breach":
			assert(instruction.contains("ENCLOSE THE BREACH") and instruction.contains("25%"))
			rogue.breach.sealed = true
			assert(rogue.objective_instruction().begins_with("BREACH SEALED - REACH"))
		if kind == "beacon": assert(instruction.contains("BEACON DISCS"))
	var c := cargo_fixture("surveyor")
	await shot("cargo-pickup-instructions")
	cut_line_to(c)
	await shot("cargo-aboard-instructions")
	for step in hi.y - c.y + 1:
		assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.objective_notice.contains("SALVAGE AWARDED"))
	assert(VectorFont.width(rogue.objective_notice, 12) < 620, "Delivery feedback fits beside the territory readout")
	await shot("cargo-delivery-feedback")
	rogue.pause_run()
	await shot("cargo-pause-objective")
	rogue.chart_depth = 3
	rogue.route_path.assign([0, 1])
	rogue.route[2][1] = {"depth": 3, "stage": 3, "kind": "cargo"}
	rogue.msg_t = 0.0
	rogue.open_chart()
	await shot("cargo-chart-objective")

func check_corruption_guidance() -> void:
	for ship_id in ["surveyor", "lancer", "sapper"]:
		for kind in ["survey", "breach"]:
			force_kind(ship_id, kind, 8, 3)
			for rank in [0, 10]:
				rogue.progress.ranks.containment = rank
				var help: Array[String] = rogue.corruption_help()
				assert(help[0].contains("STANDING ON PURPLE" if ship_id == "sapper" else "ANY UNFINISHED TRAIL"))
				assert(help[0].contains("4.0S" if rank == 0 else "5.7S"), "Displayed contact time follows Containment resistance")
				assert(" ".join(help).contains("25%") == (kind == "breach"), "Only breaches have an arena infection limit")
				for layout in [Vector3(820, 15, 22), Vector3(540, 13, 20)]:
					var height := 0.0
					for section in help:
						var rows: Array[String] = rogue.paragraph_lines(section, layout.x, layout.y)
						height += rows.size() * layout.z + 8
						for row in rows: assert(VectorFont.width(row, layout.y) <= layout.x)
					assert(height <= (120 if layout.x == 820 else 230), "Compact corruption help stays clear of the Begin button: %s" % height)
			rogue.phase = "briefing"
			await shot("corruption-briefing-" + kind + "-" + ship_id)
			rogue.phase = "run"
			rogue.exposure = 2.0
			await shot("corruption-hud-" + kind + "-" + ship_id)
			rogue.pause_run()
			await shot("corruption-pause-" + kind + "-" + ship_id)
			if kind == "breach":
				rogue.breach.sealed = true
				var sealed_help := " ".join(rogue.corruption_help())
				assert(sealed_help.contains("SPREAD STOPPED") and sealed_help.contains("STILL CAUSES EXPOSURE"))
				assert(not sealed_help.contains("25%"))
				await shot("corruption-sealed-" + ship_id)
	rogue.progress.ranks.containment = 0

func check_sector_briefings() -> void:
	# Launch every kind through the real transit and intro, including a second sector.
	rogue.start_run()
	rogue.transit_skip = false
	var depth := 0
	for kind in Sectors.KINDS:
		depth += 1
		rogue.chart_depth = depth
		rogue.route[depth - 1] = [{"depth": depth, "stage": mini(depth, 6), "kind": kind}]
		rogue.open_chart()
		rogue.launch_destination(0)
		assert(rogue.state == Game.State.TRANSIT and rogue.phase == "run")
		for frame in 600:
			rogue.update(0.016)
			if rogue.phase == "briefing": break
		assert(rogue.phase == "briefing" and rogue.state == Game.State.PLAYING, "Each loaded sector waits at its briefing")
		assert(not rogue.cells.is_empty() and not rogue.qixes.is_empty())
		if kind == "cargo": assert(not rogue.cargo.is_empty() and rogue.cargo.runs > 0)
		if kind == "beacon": assert(not rogue.zones.is_empty())
		if kind == "breach": assert(not rogue.breach.is_empty() and rogue.corruption.count(1) > 0)
		var position: Vector2 = rogue.qixes[0].c
		var clock_before: float = rogue.time
		var invuln_before: float = rogue.invuln
		var infection: PackedByteArray = rogue.corruption.duplicate()
		var hull: int = rogue.lives
		Input.action_press("confirm")
		for frame in 30: rogue.update(0.1)
		assert(rogue.phase == "briefing" and not rogue.briefing_ready, "Held launch input cannot dismiss the briefing")
		Input.action_release("confirm")
		await get_tree().process_frame
		rogue.update(0.016)
		assert(rogue.qixes[0].c == position and rogue.time == clock_before and rogue.invuln == invuln_before)
		assert(rogue.corruption == infection and rogue.lives == hull, "Enemies, infection, protection and hull stay frozen")
		render_frame()
		assert(main.display.modal_backdrop.visible and main.display.modal_lines.visible)
		assert(main.display.modal_lines.count > 0 and main.display.lines.multimesh.visible_instance_count == main.display.lines.modal_start, "Modal text renders separately above the blurred arena")
		click(Vector2(100, 100))
		assert(rogue.phase == "briefing", "Clicking outside the modal does not launch")
		await shot("briefing-" + kind)
		if kind == "cargo":
			var event := InputEventJoypadButton.new()
			event.device = 3
			event.button_index = JOY_BUTTON_A
			event.pressed = true
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			rogue.update(0.016)
			assert(rogue.phase == "run" and not rogue.draw_armed, "Controller confirm begins without firing the ship")
			var release := event.duplicate() as InputEventJoypadButton
			release.pressed = false
			Input.parse_input_event(release)
			Input.flush_buffered_events()
			await get_tree().process_frame
		elif kind == "beacon":
			click(rogue.choice_rect(0).get_center())
		else:
			await tap("confirm")
		assert(rogue.phase == "run" and rogue.qixes[0].c == position, "Confirmation leaves the loaded arena intact")
		render_frame()
		assert(not main.display.modal_backdrop.visible and not main.display.modal_lines.visible, "Begin removes blur and modal text immediately")
		rogue.update(0.016)
		assert(rogue.time > clock_before, "Simulation resumes after Begin")
