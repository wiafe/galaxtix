extends "res://tests/roguelite_acts_smoke.gd"
const EditorPanel = preload("res://addons/roguelite_maps/map_panel.gd")

func fresh(id := "surveyor") -> void:
	MapCatalog.testing["roguelite_34"] = load(MapCatalog.default_path("roguelite_34"))
	launch(34, 16, id)
	for q in rogue.qixes: q.c = rogue.center(Vector2i(120, 52))
	rogue.invuln = 1000

func expose() -> void:
	rogue.freeze_time = 0
	rogue.boss.maw.phase = "warn"
	rogue.boss.maw.clock = 0
	rogue.boss.update(rogue, 0.01)
	assert(rogue.boss.maw.phase == "exposed")
	rogue.freeze_time = 1000

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
	rogue.progress.ships = {"surveyor": true, "lancer": true, "bulwark": true}
	for id in ["surveyor", "lancer", "bulwark"]:
		fresh(id)
		var maw = rogue.boss.maw
		assert(maw.original_size > 1000 and maw.carved() == 0)
		for i in maw.body: assert(rogue.cells[i] == Game.ROCK)
		rogue.p = Vector2i(56, 31)
		assert(not rogue.try_step(Vector2i.DOWN, true, false), "Armored body blocks cutting")
		if id == "surveyor": await shot("maw-armored")
		expose()
		assert(rogue.bolts.size() == 36)
		for i in maw.body: assert(rogue.cells[i] == Game.FREE)
		if id == "surveyor": await shot("maw-exposed")
		# Begin a real cut while open, let the window expire, then finish it safely.
		rogue.p = Vector2i(35, 42)
		rogue.vis = rogue.center(rogue.p)
		rogue.draw_armed = true
		for step in 25: assert(rogue.try_step(Vector2i.RIGHT, true, false))
		rogue.freeze_time = 0
		maw.clock = 0.01
		rogue.boss.update(rogue, 0.1)
		assert(maw.phase == "exposed" and maw.held_cut and rogue.drawing)
		for step in 64: assert(rogue.try_step(Vector2i.RIGHT, true, false))
		if id == "bulwark":
			assert(not rogue.seals.is_empty())
			rogue.boss.update(rogue, 0.1)
			assert(maw.phase == "exposed", "Detached seals keep their cutting window")
		rogue.freeze_time = 1000
		for step in 600:
			if rogue.seals.is_empty(): break
			rogue.update(0.05)
		assert(maw.carved() > 0 and not rogue.boss.unlocked)
		assert(rogue.boss.remaining() < 3, "Carving off thorns disables their spores")
		if id == "surveyor": await shot("maw-first-chunk")
		var carved_before: float = maw.carved()
		rogue.freeze_time = 0
		rogue.boss.update(rogue, 0.1)
		assert(maw.phase == "armored" and maw.carved() == carved_before)
		assert(rogue.free_count == rogue.cells.count(Game.FREE), "Armor transitions preserve territory accounting")
		expose()
		rogue.bolts.clear()
		for index in rogue.boss.relays.size():
			if not rogue.boss.relays[index].captured: rogue.boss.attack(rogue, rogue.boss.relays[index], index)
		assert(rogue.bolts.size() == 12 * rogue.boss.remaining())
		cut(Vector2i(35, 62), Vector2i.RIGHT, 89)
		cut(Vector2i(70, 42), Vector2i.DOWN, 20)
		if not rogue.boss.unlocked: cut(Vector2i(90, 42), Vector2i.DOWN, 20)
		assert(rogue.boss.unlocked and not rogue.boss.defeated, "Carve enough body to expose the heart on a subsequent cut")
		if id == "surveyor": await shot("maw-heart")
		var before: int = rogue.earned_salvage
		cut(Vector2i(86, 42), Vector2i.DOWN, 20)
		assert(rogue.boss.defeated and rogue.pending_clear)
		for step in 100:
			if rogue.phase == "sector_clear": break
			rogue.update(0.05)
		assert(rogue.phase == "sector_clear" and rogue.earned_salvage >= before + 7)
		var paid: int = rogue.earned_salvage
		rogue.finish_sector()
		assert(rogue.earned_salvage == paid)
		if id == "surveyor": await shot("maw-victory")
		fresh(id)
		assert(rogue.boss.maw.carved() == 0 and rogue.boss.remaining() == 3)
	# Pause and Stasis preserve the opening; closing armor ejects roaming enemies.
	fresh()
	expose()
	var window: float = rogue.boss.maw.clock
	rogue.boss.update(rogue, 20)
	assert(rogue.boss.maw.clock == window)
	rogue.freeze_time = 0
	rogue.phase = "paused"
	rogue.boss.update(rogue, 20)
	assert(rogue.boss.maw.clock == window)
	rogue.phase = "run"
	rogue.qixes[0].c = rogue.center(Vector2i(90, 52))
	rogue.boss.maw.clock = 0
	rogue.boss.update(rogue, 0.1)
	var relocated: Vector2i = rogue.to_cell(rogue.qixes[0].c)
	assert(rogue.cells[rogue.idx(relocated.x, relocated.y)] == Game.FREE)
	var panel = EditorPanel.new()
	add_child(panel)
	panel.open_map("roguelite_34")
	assert(panel.canvas.boss_body.size() == rogue.boss.maw.original_size)
	assert(panel.encounter_help.text.contains("heart"))
	panel.free()
	MapCatalog.testing.clear()
	print("THORN MAW PASS: armor, vulnerability grace, all-ship body cuts, lost weapons, heart capture, rewards, reset and editor footprint")
	get_tree().quit()
