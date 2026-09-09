extends Node

func _ready() -> void:
	assert(not Save.enabled)
	# Even a direct scene run disables saving before Main creates Roguelite.
	Save.enabled = true
	var preview = load("res://tools/map_playtest.tscn").instantiate()
	add_child(preview)
	assert(not Save.enabled and not Save.is_processing())
	assert(Save.data == Save.fresh())
	preview.main.set_process(false)
	var rogue = preview.main.game.roguelite
	assert(rogue.state == Game.State.INTRO and rogue.phase == "run")
	for frame in 300:
		rogue.update(0.016)
		if rogue.phase == "briefing": break
	assert(rogue.phase == "briefing" and not rogue.cells.is_empty())
	print("MAP PLAYTEST PASS: direct launch, fresh temporary profile, loaded arena and sector briefing")
	get_tree().quit()
