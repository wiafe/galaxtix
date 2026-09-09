extends Node
## Maintenance tool: snapshots the existing procedural layouts for the editor.
## Run this scene with -- --nosave --no-steam. Existing defaults are never overwritten.
func _ready() -> void:
	assert(not Save.enabled)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.set_process(false)
	main.game.start_roguelite()
	var rogue = main.game.roguelite
	rogue.start_run()
	DirAccess.make_dir_recursive_absolute("res://maps/defaults")
	for entry in MapCatalog.entries():
		var path := MapCatalog.default_path(entry.id)
		if ResourceLoader.exists(path): continue
		rogue.level = entry.sector
		rogue.active_destination = {"depth": entry.sector, "stage": entry.sector, "kind": "survey"}
		rogue.start_level()
		var map := MapDefinition.new()
		map.map_id = entry.id
		map.title = entry.title
		map.sector = entry.sector
		map.rock.resize(rogue.cells.size())
		for i in rogue.cells.size(): map.rock[i] = 1 if rogue.cells[i] == Game.ROCK else 0
		map.player_start = rogue.p
		for q in rogue.qixes: map.enemies.append({"kind": "anomaly", "cell": rogue.to_cell(q.c), "axis": Vector2i.DOWN})
		for t in rogue.turrets: map.enemies.append({"kind": "turret", "cell": t.cell, "axis": t.axis})
		for i in rogue.sparx_to_spawn: rogue.spawn_sparx()
		for s in rogue.sparxes: map.enemies.append({"kind": "sparx", "cell": s.c, "axis": Vector2i.DOWN})
		assert(ResourceSaver.save(map, path) == OK)
		print("BAKED ", path)
	get_tree().quit()
