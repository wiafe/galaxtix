extends "res://tools/steam_capture.gd"
## A rehearsed, real-time cut through the real roguelite simulation.
## Launch with --write-movie <ignored-work-dir>/opening.avi --fixed-fps 30
## --resolution 1920x1080 -- --nosave --no-steam. Does not change saved maps.
var elapsed := 0.0
var active := false
var waypoint := 0
var closed_at := -1.0
var initial_free := 0
var initial_hull := 0
var targets: Array[Vector2i] = [Vector2i(64, 32), Vector2i(64, 48), Vector2i(40, 48)]

func _ready() -> void:
	set_process(false)
	call_deferred("prepare")

func prepare() -> void:
	setup_capture()
	launch(24, 2)
	rogue.owned_cards.clear()
	rogue.card_ranks.clear()
	position_player(Vector2i(40, 32))
	rogue.autopilot = true
	initial_free = rogue.free_count
	initial_hull = rogue.lives
	active = true
	set_process(true)
	print("TRAILER START: normal simulation, seed 9102050, stage 24")

func _process(dt: float) -> void:
	if not active: return
	elapsed += dt
	var direction := Vector2i.ZERO
	if elapsed > 0.7 and waypoint < targets.size():
		if rogue.p == targets[waypoint]: waypoint += 1
		if waypoint < targets.size():
			var offset: Vector2i = targets[waypoint] - rogue.p
			direction = Vector2i(signi(offset.x), 0) if offset.x != 0 else Vector2i(0, signi(offset.y))
	rogue.auto_script = [[1000.0, direction, direction != Vector2i.ZERO, false]]
	rogue.auto_i = 0
	rogue.auto_t = 0.0
	rogue.update(dt)
	if rogue.lives < initial_hull or rogue.state != Game.State.PLAYING:
		print("TRAILER FAILED: player hit at ", elapsed, " cell ", rogue.p)
		get_tree().quit(1)
		return
	if waypoint >= targets.size() and not rogue.drawing and rogue.seals.is_empty() and closed_at < 0:
		closed_at = elapsed
		print("TRAILER CAPTURE: ", initial_free - rogue.free_count, " cells at ", elapsed)
	main.display.tick(dt)
	main.display.begin_draw()
	main.game.draw()
	main.display.end_draw()
	if elapsed >= 10.0:
		assert(closed_at > 0 and rogue.free_count < initial_free, "Opening must show a successful capture")
		print("TRAILER COMPLETE: ", elapsed, " seconds; hull unchanged; real-time movement")
		get_tree().quit()
