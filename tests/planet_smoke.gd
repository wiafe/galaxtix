extends Node
const Grid = preload("res://scripts/planet_grid.gd")
const Run = preload("res://scripts/planet_run.gd")

func _ready() -> void:
	call_deferred("check")

func fixture() -> RefCounted:
	var run := Run.new()
	run.start()
	run.grid.cells.fill(Grid.FREE)
	run.enemies = [{"cell": 0, "previous": -1, "hunter": false}]
	run.salvage_cells.clear()
	run.initial_area = run.grid.total_area
	run.reclaimed_area = 0
	for x in range(8, 15): run.grid.cells[run.grid.index(4, x, 10)] = Grid.CLAIMED
	run.player = run.grid.index(4, 8, 10)
	run.home = run.player
	run.begin()
	run.draw_armed = true
	return run

func cut_rectangle(run: RefCounted) -> void:
	for y in range(11, 15): assert(run.move_to(run.grid.index(4, 8, y), true))
	for x in range(9, 15): assert(run.move_to(run.grid.index(4, x, 14), true))
	for y in range(13, 9, -1): assert(run.move_to(run.grid.index(4, 14, y), true))

func check() -> void:
	assert(not Save.enabled)
	var grid := Grid.new()
	grid.build()
	assert(absf(grid.total_area - 4 * PI) < 0.0001)
	for i in grid.cells.size():
		assert(grid.cell_at(grid.directions[i]) == i)
		assert(grid.neighbours[i].size() == 4)
		var unique := {}
		for next in grid.neighbours[i]:
			assert(next != i and grid.neighbours[next].has(i), "Seams must be reciprocal")
			unique[next] = true
		assert(unique.size() == 4)
	assert(grid.claimable(PackedInt32Array([0])).is_empty(), "One connected sphere")
	# Enclose a tile whose ring crosses a cube-face seam.
	var seam := grid.index(4, 23, 12)
	for next in grid.neighbours[seam]: grid.cells[next] = Grid.TRAIL
	assert(grid.claimable(PackedInt32Array([0])) == PackedInt32Array([seam]))
	var run := fixture()
	run.salvage_cells.append(run.grid.index(4, 10, 12))
	cut_rectangle(run)
	assert(run.grid.cells[run.grid.index(4, 10, 12)] == Grid.CLAIMED)
	assert(run.salvage == 1 and run.percent() > 0 and not run.drawing)
	run = fixture()
	run.enemies.append({"cell": run.grid.index(4, 10, 12), "previous": -1, "hunter": false})
	cut_rectangle(run)
	assert(run.grid.cells[run.grid.index(4, 10, 12)] == Grid.FREE)
	assert(run.notice == "SPLIT / NEW COAST")
	run = fixture()
	var next: int = run.grid.index(4, 8, 11)
	run.enemies[0].cell = next
	assert(not run.move_to(next, true) and run.grid.cells[next] == Grid.FREE, "Invulnerability cannot overwrite an enemy")
	run.enemies[0].cell = 0
	assert(run.move_to(next, true))
	run.invulnerable = 0
	run.hurt()
	assert(run.hull == 2 and run.player == run.home and run.grid.cells[next] == Grid.FREE)
	run.dash()
	run.phase = "paused"
	var cooldown: float = run.dash_cooldown
	run.tick(1)
	assert(run.dash_cooldown == cooldown)
	for sector in range(1, 9):
		run.sector = sector
		run.start_sector()
		assert(run.salvage_cells.size() == 12 and run.grid.coast(run.player))
		run.begin()
		run.reclaimed_area = run.initial_area
		run.close_cut()
		assert(run.phase == ("complete" if sector == 8 else "draft"))
		if sector < 8:
			run.choose_upgrade(0)
			assert(run.sector == sector + 1 and run.phase == "chart")
	var panel := preload("res://addons/roguelite_maps/map_panel.gd").new()
	add_child(panel)
	var launches := [0]
	panel.planet_requested.connect(func(): launches[0] += 1)
	var button: Button
	for found in panel.find_children("*", "Button", true, false):
		if found.text == "Launch Planet Prototype": button = found
	assert(button != null)
	var map_id: String = panel.current_id
	button.pressed.emit()
	assert(launches[0] == 1 and panel.current_id == map_id)
	panel.queue_free()
	var planet := preload("res://scenes/planet_act.tscn").instantiate()
	add_child(planet)
	planet.set_process(false)
	for normal in Grid.NORMALS:
		planet.run.player = planet.run.grid.cell_at(normal)
		for frame in 90: planet.update_camera(1.0 / 60)
		assert(planet.camera.basis.is_finite() and absf(planet.camera.basis.determinant() - 1) < 0.001)
		assert(planet.camera.position.normalized().dot(normal) > 0.99)
	planet.run.start()
	planet.shown_sector = -1
	planet.sync_surface()
	assert(planet.capture_pulses.is_empty(), "Landing never plays capture effects")
	if "--planet-shots" in OS.get_cmdline_user_args():
		await shot(planet, "chart")
		planet.run.begin()
		await shot(planet, "landfall")
		planet.run = fixture()
		planet.shown_revision = -1
		planet.shown_sector = -1
		planet.sync_surface()
		for y in range(11, 15): assert(planet.run.move_to(planet.run.grid.index(4, 8, y), true))
		await shot(planet, "cut")
		planet.run = fixture()
		planet.shown_sector = -1
		planet.sync_surface()
		cut_rectangle(planet.run)
		planet.sync_surface()
		assert(not planet.capture_pulses.is_empty())
		await shot(planet, "capture")
	planet.queue_free()
	await get_tree().process_frame
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	assert(not main.has_method("start_planet_prototype"), "Prototype is only exposed through Maps")
	main.queue_free()
	print("PLANET SMOKE PASS: globe seams, area, capture/split, damage, eight sectors, camera poles, Maps-only launch")
	get_tree().quit()

func shot(planet: Node, title: String) -> void:
	for frame in 60:
		planet.elapsed += 1.0 / 60
		planet.sync_surface()
		planet.update_camera(1.0 / 60)
		planet.draw_entities(1.0 / 60)
		planet.display.tick(1.0 / 60)
		planet.display.begin_draw()
		planet.draw_hud()
		planet.display.end_draw()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/planet-%s.png" % title)
