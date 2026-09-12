extends "res://tools/steam_capture.gd"
## Ship mechanics in real simulation; saves are disabled and enemies remain live.
var ship_id := "lancer"
var recording := false
var elapsed := 0.0
var frame_count := 0
var leg := 0
var route: Array[Vector2i] = []
var initial_hull := 0
var initial_free := 0
var peak_seals := 0
var previous_seals := 0
var failed := false
var events := {}

func _ready() -> void:
	set_process(false)
	call_deferred("prepare")

func prepare() -> void:
	setup_capture()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trailer-ship="): ship_id = arg.get_slice("=", 1)
	launch(30, 17, ship_id)
	# Rehearsed random stream: the Anomaly remains live at its normal speed.
	if ship_id == "bulwark": seed(23)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rehearsal-seed="): seed(int(arg.get_slice("=", 1)))
	rogue.autopilot = true
	rogue.auto_script = []
	rogue.owned_cards.assign(["dash", "afterburner"] if ship_id == "bulwark" else ["dash", "hardlight"])
	rogue.card_ranks = {"dash": 1, "afterburner": 1, "hardlight": 1}
	# Starting separation is rehearsed, with normal enemy behavior during the take.
	for q in rogue.qixes:
		q.c = rogue.center(Vector2i(100, 35) if ship_id == "bulwark" else Vector2i(55, 60))
		q.v = Vector2.RIGHT
		q.hist.clear()
	if ship_id == "lancer":
		position_player(Vector2i(90, 25))
		rogue.last_dir = Vector2i.DOWN
	else:
		position_player(Vector2i(119,68))
		route.assign([Vector2i(40,68), Vector2i(40,62),
			Vector2i(58,62), Vector2i(58,54), Vector2i(40,54), Vector2i(40,48),
			Vector2i(50,48), Vector2i(50,42), Vector2i(40,42)])
	initial_hull = rogue.lives
	initial_free = rogue.free_count
	recording = true
	set_process(true)
	print("SHIP TAKE START ", ship_id)

func _process(_dt: float) -> void:
	if not recording: return
	const DT := 1.0 / 30.0
	elapsed += DT
	var direction := Vector2i.ZERO
	var draw_line := false
	if ship_id == "lancer":
		if elapsed > 0.6 and not events.has("fired"):
			rogue.fire_lance()
			rogue.cooldowns.hardlight = 0.0
			rogue.activate_ability("hardlight")
			events.fired = elapsed
		if events.has("fired") and not rogue.tether_active and not events.has("landed"):
			events.landed = elapsed
			events.captured_cells = initial_free - rogue.free_count
	else:
		while leg < route.size() and rogue.p == route[leg]: leg += 1
		if elapsed > 0.5 and leg < route.size():
			var delta: Vector2i = route[leg] - rogue.p
			direction = Vector2i(signi(delta.x), 0) if delta.x != 0 else Vector2i(0, signi(delta.y))
			# Releasing on the coast arms a fresh cut; keep holding through every turn.
			var next: Vector2i = rogue.p + direction
			draw_line = rogue.drawing or rogue.cells[rogue.idx(next.x, next.y)] == Game.FREE
			if leg == 2 and not events.has("afterburner"):
				rogue.cooldowns.afterburner = 0.0
				rogue.activate_ability("afterburner")
				events.afterburner = elapsed
	rogue.auto_script = [[1000.0, direction, draw_line, false]]
	rogue.auto_i = 0
	rogue.auto_t = 0.0
	rogue.update(DT)
	if rogue.lives < initial_hull and not failed:
		failed = true
		events.hit = elapsed
		print("SHIP TAKE HIT ", ship_id, " ", elapsed, " ", rogue.msg)
	if rogue.seals.size() != previous_seals:
		if not events.has("seal_changes"): events.seal_changes = []
		events.seal_changes.append({"time": elapsed, "pending": rogue.seals.size(), "captured": initial_free - rogue.free_count})
		previous_seals = rogue.seals.size()
	peak_seals = maxi(peak_seals, rogue.seals.size())
	main.display.tick(DT)
	main.display.begin_draw()
	main.game.draw()
	main.display.end_draw()
	frame_count += 1
	if elapsed >= (6.0 if ship_id == "lancer" else 23.0):
		events.peak_seals = peak_seals
		events.final_pending = rogue.seals.size()
		events.captured_cells = initial_free - rogue.free_count
		events.final_leg = leg
		var entry := {"name": ship_id + "_action", "start": 0.0, "duration": frame_count / 30.0, "failed": failed, "events": events}
		var file := FileAccess.open("res://.godot/trailer-work/" + ship_id + "_action-takes.json", FileAccess.WRITE)
		file.store_string(JSON.stringify([entry], "\t"))
		print("SHIP TAKE END ", entry)
		recording = false
		get_tree().quit()
