extends Node
## Deterministic promotional captures through the real roguelite renderer.
## Run only with --nosave --no-steam; never changes maps or player profiles.
const OUT := "res://marketing/steam/2026-09-10/screenshots/"
var main
var rogue

func _ready() -> void:
	call_deferred("capture_all")

func launch(stage: int, depth: int, ship_id := "surveyor", encounter := "") -> void:
	seed(9102026 + stage)
	rogue.rng.seed = 9102026 + stage
	rogue.progress.select_ship(ship_id)
	rogue.transit_skip = true
	rogue.start_run()
	rogue.chart_depth = depth
	rogue.route_path.resize(depth - 1)
	rogue.route_path.fill(0)
	var map := MapCatalog.read(stage)
	var kind := "boss" if not map.boss_id.is_empty() else "survey"
	if not encounter.is_empty(): kind = encounter
	rogue.route[depth - 1] = [{"depth": depth, "stage": stage, "kind": kind, "boss": map.boss_id}]
	rogue.open_chart()
	rogue.launch_destination(0)
	rogue.phase = "run"
	rogue.state = Game.State.PLAYING
	rogue.surv_scale = 1.0
	rogue.opening_draft_pending = false
	rogue.drafts_taken = rogue.draft_capture.size()
	rogue.owned_cards.assign(["dash", "hardlight", "anchor"])
	rogue.card_ranks = {"dash": 1, "hardlight": 1, "anchor": 1}
	rogue.invuln = 0.0
	for frame in 90:
		rogue.update(1.0 / 60.0)
	assert(rogue.state == Game.State.PLAYING)

func position_player(cell: Vector2i) -> void:
	assert(rogue.cells[rogue.idx(cell.x, cell.y)] == Game.CLAIMED)
	rogue.p = cell
	rogue.vis = rogue.center(cell)
	rogue.draw_armed = true

func step_cut(direction: Vector2i, count: int) -> void:
	for step in count:
		assert(rogue.try_step(direction, true, false))
	rogue.vis = rogue.center(rogue.p)
	rogue.last_dir = direction

func settle_capture() -> void:
	# Pause hazards while the normal claim animation resolves between staged cuts.
	rogue.freeze_time = 1000
	for frame in 1200:
		if rogue.seals.is_empty(): break
		rogue.update(1.0 / 60.0)
	assert(rogue.seals.is_empty())
	for frame in 180:
		rogue.update(1.0 / 60.0)
	rogue.freeze_time = 0
	rogue.invuln = 0
	rogue.msg_t = 0
	assert(rogue.state == Game.State.PLAYING and rogue.phase == "run")

func claim_strip() -> void:
	# Find a real coast-to-coast cut near the left edge of this authored arena.
	for x in range(48, 64):
		var first := -1
		var last := -1
		for y in range(1, rogue.grid_height - 1):
			if rogue.cells[rogue.idx(x, y)] == Game.FREE:
				if first < 0: first = y
				last = y
		if first < 0 or last - first < 25: continue
		var clear := true
		for y in range(first, last + 1):
			if rogue.cells[rogue.idx(x, y)] != Game.FREE: clear = false
		if not clear: continue
		position_player(Vector2i(x, first - 1))
		step_cut(Vector2i.DOWN, last - first + 2)
		settle_capture()
		return
	assert(false, "No suitable capture strip")

func live_cut() -> void:
	# Find a long horizontal lane starting on actual captured territory.
	var best := Vector2i.ZERO
	var distance := 0
	for y in range(40, 69):
		for x in range(36, 100):
			if rogue.cells[rogue.idx(x, y)] != Game.CLAIMED: continue
			var run := 0
			while x + run + 1 < rogue.grid_width and rogue.cells[rogue.idx(x + run + 1, y)] == Game.FREE:
				run += 1
			if run > distance:
				best = Vector2i(x, y)
				distance = run
	assert(distance > 12)
	position_player(best)
	step_cut(Vector2i.RIGHT, int(distance * 0.65))
	var turn_clear := true
	for offset in range(1, 9):
		if rogue.cells[rogue.idx(rogue.p.x, rogue.p.y + offset)] != Game.FREE:
			turn_clear = false
	if turn_clear: step_cut(Vector2i.DOWN, 8)
	assert(rogue.drawing)

func shot(filename: String) -> void:
	for frame in 20:
		main.display.tick(1.0 / 60.0)
		main.display.begin_draw()
		main.game.draw()
		main.display.end_draw()
		await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	print("CAPTURE SIZE ", picture.get_size(), " WINDOW ", get_window().size)
	assert(picture.get_size() == Vector2i(1920, 1080))
	assert(picture.save_png(OUT.path_join(filename + ".png")) == OK)
	print("CAPTURED ", filename, " ", picture.get_size())

func setup_capture() -> void:
	assert(not Save.enabled, "Capture with --nosave --no-steam")
	Save.set_process(false)
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_size = Vector2i(1600, 900)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	# Main applies saved window preferences during _ready; override only afterwards.
	get_window().size = Vector2i(1920, 1080)
	main.game.start_roguelite()
	rogue = main.game.roguelite
	rogue.progress.ships = {"surveyor": true, "lancer": true, "bulwark": true}

func capture_encounters() -> void:
	launch(9, 4, "surveyor", "race")
	claim_strip()
	# Let the actual opposing pilot claim territory and begin its next cut.
	rogue.invuln = 1000
	for frame in 1800:
		rogue.update(1.0 / 60.0)
		if frame > 480 and rogue.race_scores().y > rogue.base_free * 0.08 and rogue.race_opponent.trail.size() > 8: break
	assert(rogue.phase == "run" and rogue.race_scores().y > 0)
	rogue.invuln = 0
	live_cut()
	await shot("07-encounter-race")
	launch(12, 6, "surveyor", "rival")
	claim_strip()
	rogue.invuln = 1000
	for frame in 1200:
		rogue.update(1.0 / 60.0)
		if frame > 600 and rogue.rival_scores().y > rogue.base_free * 0.05 and rogue.rival.trail.size() > 8: break
	assert(rogue.phase == "run" and rogue.rival_remaining > 0 and rogue.rival_scores().y > 0)
	rogue.invuln = 0
	rogue.msg_t = 0
	live_cut()
	await shot("08-encounter-rival")

func capture_all() -> void:
	setup_capture()
	for entry in [[12, 6, "surveyor", "01-act-1-foundry"], [17, 14, "lancer", "02-act-2-infestation"], [22, 22, "bulwark", "03-act-3-reactor"]]:
		launch(entry[0], entry[1], entry[2])
		claim_strip()
		live_cut()
		if entry[0] == 17: rogue.activate_ability("hardlight")
		await shot(entry[3])
	launch(34, 16)
	rogue.boss.maw.phase = "warn"
	rogue.boss.maw.clock = 0
	rogue.boss.update(rogue, 0.01)
	position_player(Vector2i(35, 42))
	step_cut(Vector2i.RIGHT, 89)
	settle_capture()
	position_player(Vector2i(70, 42))
	step_cut(Vector2i.DOWN, 13)
	await shot("04-boss-thorn-maw")
	launch(35, 24)
	claim_strip()
	# Let an authored lens begin its normal warning toward the previous position.
	rogue.boss.relays[0].clock = 0
	rogue.boss.update(rogue, 0.01)
	position_player(Vector2i(124, 62))
	step_cut(Vector2i.LEFT, 16)
	rogue.boss.update(rogue, 1.41)
	assert(rogue.state == Game.State.PLAYING and rogue.drawing)
	await shot("05-boss-prism-warden")
	rogue.progress.salvage = 24
	rogue.progress.ranks = {"engines": 3, "hull": 2, "reactor": 2, "scanner": 1, "extractor": 1, "containment": 1}
	rogue.progress.containment_unlocked = true
	rogue.go_dock()
	rogue.ui_time = 1.0
	await shot("06-upgrade-hangar")
	await capture_encounters()
	print("STEAM CAPTURE PASS: eight 1920x1080 roguelite screenshots")
	get_tree().quit()
