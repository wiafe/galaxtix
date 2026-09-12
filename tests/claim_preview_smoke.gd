extends "res://tools/steam_capture.gd"

func _ready() -> void:
	call_deferred("check")

func fixture(two_sides := false, ship_id := "surveyor") -> void:
	launch(24, 2, ship_id)
	rogue.nodes.clear()
	rogue.qixes.clear()
	rogue.sparxes.clear()
	rogue.turrets.clear()
	rogue.spawners.clear()
	rogue.mites.clear()
	rogue.cells.fill(Game.CLAIMED)
	rogue.credited.fill(1)
	rogue.corruption.fill(0)
	rogue.first_claims = 0
	rogue.free_count = 400
	rogue.base_free = 400
	for y in range(30, 50):
		for x in range(40, 60):
			rogue.cells[rogue.idx(x, y)] = Game.FREE
			rogue.credited[rogue.idx(x, y)] = 0
	for cell in ([Vector2i(54, 40), Vector2i(44, 40)] if two_sides else [Vector2i(54, 40)]):
		var q := Game.QixBody.new()
		q.c = rogue.center(cell)
		q.len = 2
		rogue.qixes.append(q)
	position_player(Vector2i(50, 29))
	step_cut(Vector2i.DOWN, 16)
	rogue.claim_preview.refresh(rogue, true)

func check() -> void:
	setup_capture()
	fixture()
	check_label_fade()
	var before: PackedByteArray = rogue.cells.duplicate()
	var live_trail: Array = rogue.trail.duplicate()
	rogue.claim_preview.refresh(rogue, true)
	var prediction: Dictionary = rogue.claim_preview.result.duplicate(true)
	assert(prediction.end == Vector2i(50, 50))
	assert(prediction.region.size() == 200 and not prediction.split)
	assert(rogue.cells == before and rogue.trail == live_trail and rogue.free_count == 400, "Preview must not mutate gameplay")
	step_cut(Vector2i.DOWN, 5)
	assert(rogue.free_count == 180, "Real capture includes predicted area and the 20-cell boundary")
	for i in prediction.region: assert(rogue.cells[i] == Game.CLAIMED)
	rogue.claim_preview.refresh(rogue, true)
	assert(rogue.claim_preview.result.is_empty(), "Hide the hint immediately after closure")
	fixture(true)
	assert(rogue.claim_preview.result.split)
	step_cut(Vector2i.DOWN, 5)
	assert(rogue.free_count == 380 and rogue.msg.begins_with("SPLIT / NEW COAST"))
	fixture(true)
	rogue.qixes[1].c = rogue.center(Vector2i(55, 42))
	rogue.time += 0.1
	rogue.claim_preview.refresh(rogue)
	assert(not rogue.claim_preview.result.split, "Enemy motion must change the forecast even while player is stationary")
	rogue.cells[rogue.idx(50, 47)] = Game.ROCK
	rogue.claim_preview.refresh(rogue, true)
	assert(rogue.claim_preview.result.is_empty(), "Do not project through rocks")
	fixture()
	rogue.qixes.clear()
	rogue.claim_preview.refresh(rogue, true)
	assert(rogue.claim_preview.result.region.size() == 180, "Seedless maps preserve their largest region after the projected closure")
	fixture(false, "bulwark")
	assert(rogue.claim_preview.result.region.size() == 200)
	step_cut(Vector2i.DOWN, 5)
	assert(rogue.seals.size() == 1 and rogue.free_count == 400)
	rogue.update_seals(100.0)
	assert(rogue.seals.is_empty() and rogue.free_count == 180)
	fixture(false, "lancer")
	# Start a fresh native tether instead of the fixture's manual trail.
	for cell in rogue.trail: rogue.cells[rogue.idx(cell.x, cell.y)] = Game.FREE
	rogue.trail.clear()
	rogue.drawing = false
	position_player(Vector2i(50, 29))
	rogue.last_dir = Vector2i.DOWN
	rogue.lance_cd = 0
	rogue.fire_lance()
	rogue.claim_preview.refresh(rogue, true)
	assert(rogue.tether_active and rogue.claim_preview.result.region.size() == 200)
	rogue.phase = "draft"
	rogue.claim_preview.refresh(rogue, true)
	assert(rogue.claim_preview.result.is_empty(), "Never leak the overlay into a modal")
	print("CLAIM PREVIEW OK: exact capture, split feedback, read-only prediction, moving enemies, blocked path, seedless maps, Bulwark, Lancer and modal cleanup")
	if "--preview-shots" in OS.get_cmdline_user_args(): await preview_shots()
	get_tree().quit()

func check_label_fade() -> void:
	var preview = rogue.claim_preview
	for depth in [1, 2, 3]: assert(preview.label_opacity(depth) == 1.0)
	var previous := 1.0
	for depth in range(4, 9):
		var opacity: float = preview.label_opacity(depth)
		assert(opacity < previous and opacity >= 0.0)
		previous = opacity
	for depth in [8, 9, 16, 17, 24]: assert(preview.label_opacity(depth) == 0.0)
	rogue.level = 3
	main.display.begin_draw()
	preview.draw(rogue)
	var with_text: int = rogue.lines.count
	main.display.end_draw()
	rogue.level = 9
	main.display.begin_draw()
	preview.draw(rogue)
	assert(rogue.lines.count > 0 and rogue.lines.count < with_text, "Only text fades; area hatching and the closing guide remain")
	main.display.end_draw()
	rogue.level = 2
	assert(preview.label_opacity(rogue.level) == 1.0, "A new run restores early guidance")

func preview_shots() -> void:
	launch(24, 2)
	position_player(Vector2i(40, 32))
	step_cut(Vector2i.RIGHT, 24)
	step_cut(Vector2i.DOWN, 16)
	step_cut(Vector2i.LEFT, 12)
	for q in rogue.qixes:
		q.c = rogue.center(Vector2i(100, 65))
		q.hist.clear()
	for name in ["claim", "split"]:
		if name == "split":
			var q := Game.QixBody.new()
			q.c = rogue.center(Vector2i(55, 40))
			q.len = 35
			rogue.qixes.append(q)
		rogue.claim_preview.refresh(rogue, true)
		assert(not rogue.claim_preview.result.is_empty())
		for frame in 16:
			main.display.tick(1.0 / 60)
			main.display.begin_draw()
			main.game.draw()
			main.display.end_draw()
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/preview-" + name + ".png")
