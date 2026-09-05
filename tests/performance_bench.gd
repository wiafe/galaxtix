extends Node
## CPU-only benchmark: godot --headless --path . res://tests/performance_bench.tscn -- --nosave
func _ready() -> void:
	call_deferred("bench")
func bench() -> void:
	assert(not get_tree().root.get_node("Save").enabled, "Run with --nosave")
	var main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	main.set_process(false)
	var game = main.game
	for mode in ["dock", "play"]:
		seed(1337)
		if mode == "dock":
			game.go_dock()
		else:
			game.transit_skip = true
			game.autopilot = true
			game.auto_script = [[1.0, Vector2i.RIGHT, false, false], [2.6, Vector2i.DOWN, true, false], [1.6, Vector2i.RIGHT, true, false], [3.2, Vector2i.UP, true, false]]
			game.start_run()
		var samples := []
		for i in 600:
			var start := Time.get_ticks_usec()
			main.display.tick(1.0 / 60)
			game.update(1.0 / 60)
			main.display.begin_draw(game.shake_off)
			game.draw()
			main.display.end_draw()
			if i >= 60:
				samples.append((Time.get_ticks_usec() - start) / 1000.0)
		samples.sort()
		print("BENCH %s median=%.2fms p95=%.2fms max=%.2fms" % [mode, samples[samples.size()/2], samples[int(samples.size()*0.95)], samples[-1]])
	get_tree().quit()
