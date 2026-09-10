extends "res://tests/roguelite_ships_smoke.gd"

func enemy_fixture(kind: String) -> Game.QixBody:
	fresh_ship("surveyor")
	var map := load(MapCatalog.default_path("roguelite_01")).duplicate(true) as MapDefinition
	map.override_enemies = true
	map.enemies.assign([{"kind": kind, "cell": Vector2i(92, 57), "axis": Vector2i.DOWN}])
	assert(map.problems().is_empty(), "New void enemies can replace the base Anomaly")
	MapCatalog.testing[map.map_id] = map
	rogue.start_level()
	MapCatalog.testing.clear()
	rogue.phase = "run"
	rogue.state = Game.State.PLAYING
	rogue.freeze_time = 0
	rogue.invuln = 0
	rogue.nodes.clear()
	assert(rogue.qixes.size() == (7 if kind == "chain_worm" else 1) and rogue.authored_behaviors.size() == rogue.qixes.size())
	assert(rogue.to_cell(rogue.qixes[0].c) == Vector2i(92, 57))
	return rogue.qixes[0]

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
	var panel := preload("res://addons/roguelite_maps/map_panel.gd").new()
	add_child(panel)
	for kind in ["chain_worm", "brood_carrier"]:
		var option := MapCatalog.ENEMY_KINDS.find(kind)
		assert(panel.enemy_input.get_item_text(option) == kind.capitalize())
		panel.enemy_input.item_selected.emit(option)
		assert(panel.canvas.enemy_kind == kind and panel.enemy_help.text == MapCatalog.ENEMY_HELP[kind])
	panel.free()
	for entry in MapCatalog.entries():
		var map := load(MapCatalog.default_path(entry.id)) as MapDefinition
		for enemy in map.enemies:
			assert(enemy.kind not in ["gunner_orb", "ray_orb", "rotor", "chain_worm", "brood_carrier"], "New enemies are opt-in editor content")
	var q := enemy_fixture("gunner_orb")
	var behavior: Dictionary = rogue.authored_behaviors[q]
	behavior.clock = 0.01
	rogue.update_qix(q, 0.02, 50)
	assert(behavior.phase == "warn" and rogue.bolts.is_empty())
	var position := q.c
	var clock_before: float = behavior.clock
	rogue.freeze_time = 1.0
	rogue.update_qix(q, 0.5, 50)
	assert(q.c == position and behavior.clock == clock_before, "Stasis freezes attacks as well as movement")
	rogue.freeze_time = 0
	rogue.phase = "briefing"
	rogue.update(0.5)
	assert(behavior.clock == clock_before, "The briefing never spends attack time")
	rogue.phase = "run"
	rogue.update_qix(q, 0.4, 50)
	assert(q.c == position and rogue.bolts.is_empty(), "Gunner stops and warns before firing")
	await shot("gunner-warning")
	rogue.update_qix(q, 0.5, 50)
	assert(rogue.bolts.size() == 5 and behavior.phase == "roam")
	var headings := {}
	for bolt in rogue.bolts:
		assert(bolt.source == "GUNNER ORB FIRE")
		headings[snappedf(bolt.vel.angle(), 0.01)] = true
	assert(headings.size() == 5, "The volley fans out into five distinct directions")
	await shot("gunner-volley")
	for bolt in rogue.bolts:
		bolt.pos = rogue.center(rogue.p)
		bolt.vel = Vector2.ZERO
	rogue.update_hazards(0.016)
	assert(rogue.bolts.is_empty(), "Safe land absorbs Gunner shots")
	q = enemy_fixture("ray_orb")
	behavior = rogue.authored_behaviors[q]
	behavior.clock = 0.01
	rogue.update_qix(q, 0.02, 50)
	assert(behavior.phase == "warn" and q.len <= 12)
	var aim: float = behavior.aim
	rogue.vis += Vector2(200, 80)
	rogue.update_qix(q, 0.5, 50)
	assert(behavior.aim == aim and q.theta == aim, "Ray locks aim during its warning")
	await shot("ray-warning")
	rogue.update_qix(q, 0.7, 50)
	assert(behavior.phase == "fire")
	rogue.update_qix(q, 0.4, 50)
	assert(q.len > 12 and not rogue.qix_blocked(q.c, q.theta, q.len), "Active ray extends and clips at land")
	await shot("ray-firing")
	rogue.update_qix(q, 0.8, 50)
	assert(q.len <= 12 and behavior.phase == "roam", "The ray retracts before moving again")
	q = enemy_fixture("rotor")
	position = q.c
	var angle := q.theta
	rogue.update_qix(q, 0.1, 50)
	assert(q.c == position and q.theta != angle, "Rotor turns around a fixed centre")
	await shot("rotor")
	await check_rotor_capture()
	await check_sparx_capture()
	await check_worm_and_brood()
	# Roaming void enemies preserve their capture region and threaten live trails.
	for kind in ["gunner_orb", "ray_orb", "chain_worm", "brood_carrier"]:
		q = enemy_fixture(kind)
		rogue.p = Vector2i(70, 26)
		rogue.vis = rogue.center(rogue.p)
		rogue.draw_armed = true
		for step in 51: assert(rogue.try_step(Vector2i.DOWN, true, false))
		assert(not rogue.drawing and rogue.cells[rogue.idx(60, 50)] == Game.CLAIMED)
		assert(rogue.cells[rogue.idx(92, 57)] == Game.FREE, "Void enemies preserve their side of a capture")
		var cell: Vector2i = rogue.to_cell(q.c)
		rogue.cells[rogue.idx(cell.x, cell.y)] = Game.TRAIL
		assert(rogue.qix_trail_cell(q).x >= 0, "Enemy geometry participates in trail contact")
		rogue.state = Game.State.INTRO
		rogue.authored_behaviors[q].clock = 0.01
		rogue.update_qix(q, 0.5, 50)
		assert(rogue.bolts.is_empty(), "Entry animation cannot trigger a volley")
	print("ROGUELITE ENEMIES PASS: editor catalogue, exact spawns, Gunner, Ray, Rotor, Worm body/path/collision, Brood eggs/hatching/capture/cap, stasis and briefing")
	get_tree().quit()

func check_sparx_capture() -> void:
	enemy_fixture("gunner_orb")
	rogue.drafts_taken = rogue.draft_capture.size()
	var trapped := Game.SparxBody.new()
	trapped.c = Vector2i(54, 50)
	trapped.prev = Vector2i(54, 49)
	trapped.vis = rogue.center(trapped.c)
	var survivor := Game.SparxBody.new()
	survivor.c = Vector2i(105, 50)
	survivor.prev = Vector2i(105, 49)
	survivor.vis = rogue.center(survivor.c)
	rogue.sparxes.assign([trapped, survivor])
	assert(rogue.sparx_has_coast(trapped.c) and rogue.sparx_has_coast(survivor.c))
	rogue.p = Vector2i(55, 26)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	var flux_before: float = rogue.run_flux
	for step in 51: assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.sparxes == [survivor], "Capturing the strip removes only the Sparx cut off from void")
	assert(is_equal_approx(rogue.run_flux - flux_before, rogue.hazard_capture_value()), "A trapped Sparx pays the standard hazard reward")
	assert(rogue.capture_extra_hazards() == 0, "Captured Sparx cannot pay twice")
	var position := trapped.c
	# The new coast is only one cell away: even that small gap cannot be hopped.
	assert(rogue.border[rogue.idx(55, 50)] == 1)
	for step in 20: rogue.sparx_step(trapped)
	assert(trapped.c == position, "Stranded Sparx never relocate to the new coast")
	position = survivor.c
	rogue.sparx_step(survivor)
	assert(survivor.c != position and rogue.sparx_has_coast(survivor.c), "Uncaptured Sparx still patrol")
	await shot("sparx-captured")

func check_rotor_capture() -> void:
	for with_anomaly in [false, true]:
		var rotor := enemy_fixture("rotor")
		rogue.drafts_taken = rogue.draft_capture.size()
		if with_anomaly:
			var anomaly := Game.QixBody.new()
			anomaly.c = rogue.center(Vector2i(60, 50))
			anomaly.len = 4
			rogue.qixes.append(anomaly)
		rogue.p = Vector2i(89, 26)
		rogue.vis = rogue.center(rogue.p)
		rogue.draw_armed = true
		for step in 51: assert(rogue.try_step(Vector2i.DOWN, true, false))
		assert(rogue.cells[rogue.idx(92, 57)] == Game.CLAIMED, "Rotor's centre can be enclosed")
		assert(not rogue.qixes.has(rotor) and not rogue.authored_behaviors.has(rotor), "Captured Rotor is removed from rendering and collisions")
		assert(rogue.cells[rogue.idx(60, 50)] == Game.FREE, "A rotor-only map does not give away the entire arena")
		var paid: float = rogue.earned_salvage + rogue.salvage_fraction
		assert(paid > 0 and rogue.capture_extra_hazards() == 0, "Rotor capture pays once")
		assert(not rogue.capture_flood_seeds().is_empty(), "Future cuts keep a valid region after the final Rotor is destroyed")
		await shot("rotor-captured-" + str(with_anomaly))

func check_worm_and_brood() -> void:
	var head := enemy_fixture("chain_worm")
	var behavior: Dictionary = rogue.authored_behaviors[head]
	var start := head.c
	head.v = Vector2.LEFT
	for frame in 40: rogue.update_qix(head, 0.05, 50)
	assert(head.c.distance_to(start) > 30)
	var tail: Game.QixBody = behavior.links.back()
	assert(tail.c.distance_to(head.c) > 35, "The worm grows a trailing body, not a cluster of overlapping orbs")
	var cell: Vector2i = rogue.to_cell(tail.c)
	rogue.cells[rogue.idx(cell.x, cell.y)] = Game.TRAIL
	assert(rogue.qix_trail_cell(tail).x >= 0 and rogue.qix_contact_reason(tail) == "CHAIN WORM CONTACT")
	rogue.cells[rogue.idx(cell.x, cell.y)] = Game.FREE
	await shot("chain-worm")
	var position := head.c
	var tail_position := tail.c
	rogue.freeze_time = 1
	rogue.update_qix(head, 0.5, 50)
	assert(head.c == position and tail.c == tail_position)
	rogue.freeze_time = 0
	for frame in 300:
		rogue.update_qix(head, 0.05, 100)
		for part in rogue.qixes:
			assert(not rogue.qix_blocked(part.c, part.theta, part.len), "Head and tail remain within open terrain after bounces")
	assert(behavior.path.size() < 450, "Worm history stays bounded")
	var carrier := enemy_fixture("brood_carrier")
	behavior = rogue.authored_behaviors[carrier]
	behavior.clock = 0.01
	rogue.update_qix(carrier, 0.02, 50)
	assert(behavior.phase == "warn" and rogue.brood_eggs.is_empty())
	await shot("brood-warning")
	rogue.update_qix(carrier, 1, 50)
	assert(rogue.brood_eggs.size() == 1 and rogue.mites.is_empty())
	var egg: Dictionary = rogue.brood_eggs[0]
	var egg_clock: float = egg.clock
	rogue.freeze_time = 1
	rogue.update_hazards(0.5)
	assert(egg.clock == egg_clock)
	rogue.freeze_time = 0
	rogue.phase = "briefing"
	rogue.update(0.5)
	assert(egg.clock == egg_clock)
	rogue.phase = "run"
	rogue.update_qix(carrier, 1.5, 50)
	rogue.update_brood_eggs(4.5)
	assert(rogue.mites.is_empty())
	await shot("brood-egg")
	rogue.update_brood_eggs(1.6)
	assert(rogue.brood_eggs.is_empty() and rogue.mites.size() == 1 and behavior.home.alive == 1)
	var mite_position: Vector2 = rogue.mites[0].pos
	rogue.update_hazards(0.1)
	assert(rogue.mites[0].pos != mite_position, "Hatched mites join the normal chase simulation")
	# Never exceed four pending/hatched offspring from one carrier.
	for i in 8:
		carrier.c = rogue.center(Vector2i(80 + i, 55))
		behavior.phase = "warn"
		behavior.clock = 0
		rogue.update_qix(carrier, 0.01, 50)
	assert(rogue.brood_eggs.size() == 3 and behavior.home.alive == 1)
	# A real enclosure removes the egg and credits its reward once, before it hatches.
	carrier = enemy_fixture("brood_carrier")
	behavior = rogue.authored_behaviors[carrier]
	rogue.brood_eggs.append({"cell": Vector2i(60, 50), "clock": 6.0, "home": behavior.home})
	rogue.p = Vector2i(70, 26)
	rogue.vis = rogue.center(rogue.p)
	rogue.draw_armed = true
	for step in 51: assert(rogue.try_step(Vector2i.DOWN, true, false))
	assert(rogue.brood_eggs.is_empty() and rogue.mites.is_empty(), "Capture destroys eggs before hatch")
	assert(rogue.earned_salvage + rogue.salvage_fraction >= 0.25)
	rogue.start_level()
	assert(rogue.brood_eggs.is_empty(), "Sector restarts discard eggs")
	for ship_id in ["surveyor", "lancer", "sapper"]:
		for kind in ["chain_worm", "brood_carrier"]:
			var enemy := enemy_fixture(kind)
			rogue.ship = Ships.get_ship(ship_id)
			var cell_at: Vector2i = rogue.to_cell(enemy.c)
			rogue.cells[rogue.idx(cell_at.x, cell_at.y)] = Game.TRAIL
			rogue.p = cell_at
			rogue.vis = enemy.c
			rogue.drawing = true
			rogue.trail.assign([cell_at])
			rogue.hardlight_time = 1
			assert(not rogue.tether_hit(rogue.qix_trail_cell(enemy)), "New bodies respect Hardlight on every ship")
			rogue.hardlight_time = 0
			assert(rogue.tether_hit(rogue.qix_trail_cell(enemy)))
