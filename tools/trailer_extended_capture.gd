extends "res://tools/steam_capture.gd"
## Trailer-only rehearsal. Real simulation at 30 fps, with isolated setup between takes.
const TAKES := ["draft_dash", "chart", "infestation", "reactor", "race", "rival", "prism", "maw", "endcard", "ships", "upgrades", "title_menu"]
const LENGTHS := [12.0, 4.0, 7.0, 7.0, 7.0, 7.0, 7.0, 12.0, 6.0, 6.0, 6.0, 4.0]
var take_index := -1
var take_time := 0.0
var frames := 0
var start_frame := 0
var ready_to_record := false
var waypoints: Array[Vector2i] = []
var wp := 0
var baseline_hull := 0
var take_failed := false
var events := {}
var manifest: Array = []
var only := ""
var end_wordmark: Node2D

func _ready() -> void:
	set_process(false)
	call_deferred("prepare_movie")

func prepare_movie() -> void:
	setup_capture()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trailer-shot="): only = arg.get_slice("=", 1)
	next_take()
	ready_to_record = true
	set_process(true)

func fresh(stage: int, depth: int, kind := "") -> void:
	rogue.autopilot = false
	launch(stage, depth, "surveyor", kind)
	rogue.autopilot = true
	rogue.auto_script = []
	rogue.invuln = 0.0
	rogue.owned_cards.assign(["dash", "hardlight"])

func next_take() -> void:
	if take_index >= 0:
		events.final_position = [rogue.p.x, rogue.p.y]
		events.waypoints = [wp, waypoints.size()]
		manifest.append({"name": TAKES[take_index], "start": start_frame / 30.0,
			"duration": (frames - start_frame) / 30.0, "failed": take_failed, "events": events.duplicate(true)})
		print("TAKE END ", manifest.back())
	if not only.is_empty() and take_index >= 0: take_index = TAKES.size()
	else:
		take_index += 1
		if not only.is_empty(): take_index = TAKES.find(only)
	if take_index < 0 or take_index >= TAKES.size():
		var suffix := "extended" if only.is_empty() else only
		var file := FileAccess.open("res://.godot/trailer-work/" + suffix + "-takes.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest, "\t"))
		print("EXTENDED TRAILER CAPTURE COMPLETE")
		get_tree().quit()
		ready_to_record = false
		return
	take_time = 0.0
	start_frame = frames
	wp = 0
	waypoints.clear()
	events.clear()
	take_failed = false
	match TAKES[take_index]:
		"draft_dash":
			fresh(24, 2)
			rogue.owned_cards.clear()
			rogue.card_ranks.clear()
			position_player(Vector2i(40, 32))
			rogue.opening_draft_pending = true
			rogue.open_draft()
			waypoints.assign([Vector2i(64, 32), Vector2i(64, 48), Vector2i(40, 48)])
		"chart":
			fresh(17, 12)
			rogue.open_chart()
		"infestation":
			fresh(17, 14)
			claim_strip()
			live_cut()
			waypoints = path_to_coast()
			rogue.cooldowns.hardlight = 0
			rogue.activate_ability("hardlight")
		"reactor":
			fresh(30, 17)
			position_player(Vector2i(65, 78))
			step_cut(Vector2i.UP, 12)
			waypoints.assign([Vector2i(65, 58), Vector2i(85, 58), Vector2i(85, 78)])
			# Rehearse the initial separation; the enemy remains live throughout the take.
			for q in rogue.qixes:
				q.c = rogue.center(Vector2i(48, 35))
				q.hist.clear()
			rogue.cooldowns.hardlight = 0
			rogue.activate_ability("hardlight")
		"race", "rival":
			var race: bool = TAKES[take_index] == "race"
			fresh(9 if race else 12, 4 if race else 6, TAKES[take_index])
			claim_strip()
			# Pre-roll the existing opponent into a developed contest, before the take.
			rogue.invuln = 1000
			for frame in 1000:
				rogue.update(1.0 / 60.0)
			rogue.invuln = 0
			rogue.msg_t = 0
			live_cut()
			waypoints = path_to_coast()
		"prism":
			fresh(35, 24)
			claim_strip()
			rogue.boss.relays[0].clock = 0
			rogue.boss.update(rogue, 0.01)
			position_player(Vector2i(124, 62))
			step_cut(Vector2i.LEFT, 16)
			waypoints = path_to_coast()
		"maw":
			fresh(34, 16)
			position_player(Vector2i(35, 42))
			rogue.boss.maw.phase = "warn"
			rogue.boss.maw.clock = 0
			rogue.boss.update(rogue, 0.01)
			position_player(Vector2i(35, 42))
			step_cut(Vector2i.RIGHT, 60)
			for q in rogue.qixes:
				q.c = rogue.center(Vector2i(110, 70))
				q.hist.clear()
			waypoints.assign([Vector2i(124, 42)])
			rogue.card_ranks.hardlight = 3
			rogue.cooldowns.hardlight = 0
			rogue.activate_ability("hardlight")
		"endcard":
			# Broad solid letters need less bloom than the gameplay's thin beams.
			main.display.env.glow_intensity = 0.12
			main.display.env.glow_bloom = 0.02
			main.display.env.glow_hdr_threshold = 0.85
			for child in main.display.scene_root.get_children():
				if child is Sprite2D: child.visible = false
			end_wordmark = preload("res://scripts/galaxtix_wordmark.gd").new()
			end_wordmark.position = Vector2(230, 315)
			end_wordmark.scale = Vector2.ONE * (1140.0 / 750.0)
			main.display.add_scene_child(end_wordmark)
		"ships", "upgrades":
			fresh(24, 2)
			rogue.progress.salvage = 45
			rogue.progress.ranks = {"engines": 3, "hull": 2, "reactor": 2, "scanner": 1, "extractor": 1, "containment": 1}
			rogue.progress.containment_unlocked = true
			rogue.go_dock()
			if TAKES[take_index] == "ships":
				rogue.hangar_page = "ships"
				rogue.selection = 10
			else:
				rogue.progress.select_ship("bulwark")
				rogue.selection = 1
		"title_menu":
			main.game.go_title()
	baseline_hull = rogue.lives
	print("TAKE START ", TAKES[take_index], " frame ", frames)

func path_to_coast() -> Array[Vector2i]:
	var queue: Array[Vector2i] = [rogue.p]
	var came := {rogue.p: rogue.p}
	var cursor := 0
	var goal := Vector2i(-1, -1)
	while cursor < queue.size() and goal.x < 0:
		var cell := queue[cursor]
		cursor += 1
		for dir in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = cell + dir
			if next.x < 0 or next.y < 0 or next.x >= rogue.grid_width or next.y >= rogue.grid_height or came.has(next): continue
			var value: int = rogue.cells[rogue.idx(next.x, next.y)]
			if value not in [Game.FREE, Game.CLAIMED]: continue
			came[next] = cell
			if value == Game.CLAIMED:
				goal = next
				break
			queue.append(next)
	var result: Array[Vector2i] = []
	while goal.x >= 0 and goal != rogue.p:
		result.push_front(goal)
		goal = came[goal]
	return result

func _process(_dt: float) -> void:
	if not ready_to_record: return
	const DT := 1.0 / 30.0
	take_time += DT
	var name: String = TAKES[take_index]
	if name == "ships":
		if take_time > 1.8 and not events.has("lancer"):
			rogue.purchase_or_select_ship(1)
			events.lancer = take_time
		if take_time > 3.6 and not events.has("bulwark"):
			rogue.purchase_or_select_ship(2)
			events.bulwark = take_time
	if name == "upgrades" and take_time > 2.8 and not events.has("purchase"):
		rogue.activate_choice(1)
		events.purchase = take_time
		events.engines_rank = rogue.progress.rank_of("engines")
	if name == "draft_dash":
		if take_time > 1.5 and rogue.phase == "draft": rogue.selection = 2
		if take_time > 3.4 and rogue.phase == "draft": rogue.begin_card_install(2)
		if take_time > 5.2 and not events.has("dash"):
			rogue.cooldowns.dash = 0.0
			rogue.activate_ability("dash")
			events.dash = take_time
	var direction := Vector2i.ZERO
	var can_move: bool = rogue.phase == "run" and (name != "draft_dash" or take_time > 4.0)
	if can_move:
		while wp < waypoints.size() and rogue.p == waypoints[wp]: wp += 1
		if wp < waypoints.size():
			var offset := waypoints[wp] - Vector2i(rogue.p)
			direction = Vector2i(signi(offset.x), 0) if offset.x != 0 else Vector2i(0, signi(offset.y))
		elif name != "maw" and not rogue.drawing:
			# Keep playing after a closure: a stationary ship makes an easy beam target.
			var heading: Vector2i = rogue.last_dir
			for candidate in [heading, Vector2i(-heading.y, heading.x), Vector2i(heading.y, -heading.x), -heading]:
				var next: Vector2i = rogue.p + candidate
				if next.x >= 0 and next.y >= 0 and next.x < rogue.grid_width and next.y < rogue.grid_height and rogue.cells[rogue.idx(next.x, next.y)] == Game.CLAIMED:
					direction = candidate
					break
	rogue.auto_script = [[1000.0, direction, direction != Vector2i.ZERO, false]]
	rogue.auto_i = 0
	rogue.auto_t = 0.0
	if name == "title_menu": main.game.update(DT)
	elif name != "endcard": rogue.update(DT)
	if rogue.lives < baseline_hull and not take_failed:
		take_failed = true
		events.hit = take_time
		print("TAKE HIT ", name, " at ", take_time, " reason ", rogue.msg)
	if wp >= waypoints.size() and not waypoints.is_empty() and not rogue.drawing and not events.has("closed"):
		events.closed = take_time
	if name == "maw" and rogue.boss.maw.carved() > 0 and not events.has("carved"):
		events.carved = {"time": take_time, "fraction": rogue.boss.maw.carved()}
	main.display.tick(DT)
	main.display.begin_draw()
	if name == "endcard":
		VectorFont.draw(main.display.lines, "RECLAIM YOUR EMPIRE.", Vector2(800, 495), 27, Palette.WHITE, 0.0, 0.0, 1)
		VectorFont.draw(main.display.lines, "ONE CUT AT A TIME.", Vector2(800, 548), 25, Palette.YELLOW, 0.0, 0.0, 1)
	else: main.game.draw()
	main.display.end_draw()
	frames += 1
	if take_time >= LENGTHS[take_index]: next_take()
