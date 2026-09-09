extends "res://tests/roguelite_ships_smoke.gd"

func enemy_fixture(kind: String) -> Game.QixBody:
	fresh_ship("surveyor")
	var map := MapCatalog.read(1).duplicate(true) as MapDefinition
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
	assert(rogue.qixes.size() == 1 and rogue.authored_behaviors.size() == 1)
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
	for entry in MapCatalog.entries():
		var map := MapCatalog.read(entry.sector)
		for enemy in map.enemies:
			assert(enemy.kind not in ["gunner_orb", "ray_orb", "rotor"], "New enemies are opt-in editor content")
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
	# All three participate in the actual capture flood and share trail protections.
	for kind in ["gunner_orb", "ray_orb", "rotor"]:
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
	print("ROGUELITE ENEMIES PASS: opt-in catalogue, exact spawns, Gunner warning/fan/land blocking, Ray warning/aim/extension/retraction, Rotor rotation, stasis, briefing, capture and trail contact")
	get_tree().quit()
