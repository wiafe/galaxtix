extends SceneTree
## Run explicitly to create missing act maps. Existing edits are never overwritten.
const Acts = preload("res://scripts/roguelite_acts.gd")

func _initialize() -> void:
	for stage in range(Acts.FIRST_MAP, Acts.LAST_MAP + 1):
		var map := build(stage)
		var problems := map.problems()
		if not problems.is_empty():
			push_error("%s: %s" % [map.title, problems])
			quit(1)
			return
		for path in [MapCatalog.default_path(map.map_id), MapCatalog.path_for(map.map_id)]:
			if not FileAccess.file_exists(path):
				assert(ResourceSaver.save(map, path) == OK)
	print("ACT MAPS READY: 21 encounter arenas and 6 boss arenas")
	quit()

func block(map: MapDefinition, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x): map.rock[y * 160 + x] = 1

func build(stage: int) -> MapDefinition:
	if stage >= 33: return build_boss_alternative(stage)
	if stage >= 24: return build_extra(stage)
	var map := MapDefinition.new()
	map.map_id = "roguelite_%02d" % stage
	map.title = Acts.MAP_NAMES[stage - 9]
	map.sector = stage
	map.act_theme = Acts.map_act(stage)
	map.override_terrain = true
	map.override_enemies = true
	map.override_start = true
	map.rock.resize(160 * 104)
	map.rock.fill(1)
	var variant := (stage - 9) % 5
	for y in range(23, 81):
		for x in range(35, 125):
			var dx := absf(x - 79.5)
			var dy := absf(y - 51.5)
			var open := true
			if variant < 4:
				match map.act_theme:
					1: open = dx < 40 and dy < 26 and not (variant == 3 and dy > 15 and dx < 7)
					2: open = pow(dx / 42.0, 2) + pow(dy / 27.0, 2) < 1 or (dx < 12 and dy < 28)
					3: open = dx < 44 and dy < 28 and not (variant == 3 and dy > 15 and dx > 26)
			if open: map.rock[y * 160 + x] = 0
	if variant < 4:
		match map.act_theme:
			1:
				for rect in [[Rect2i(59, 42, 6, 16), Rect2i(94, 42, 6, 16)], [Rect2i(52, 39, 17, 5), Rect2i(89, 61, 17, 5)], [Rect2i(57, 38, 7, 7), Rect2i(96, 38, 7, 7), Rect2i(57, 61, 7, 7), Rect2i(96, 61, 7, 7)], [Rect2i(56, 47, 8, 8), Rect2i(96, 47, 8, 8)]][variant]: block(map, rect)
			2:
				for rect in [[Rect2i(66, 45, 5, 12), Rect2i(92, 44, 5, 12)], [Rect2i(64, 34, 5, 20), Rect2i(91, 51, 5, 20)], [Rect2i(69, 42, 21, 4), Rect2i(69, 59, 21, 4)], [Rect2i(68, 40, 5, 22), Rect2i(86, 46, 5, 22)]][variant]: block(map, rect)
			3:
				for rect in [[Rect2i(75, 24, 10, 17), Rect2i(75, 63, 10, 17)], [Rect2i(67, 39, 26, 4), Rect2i(67, 61, 26, 4), Rect2i(67, 43, 4, 8), Rect2i(89, 53, 4, 8)], [Rect2i(61, 42, 8, 18), Rect2i(92, 42, 8, 18)], [Rect2i(74, 43, 12, 16)]][variant]: block(map, rect)
	map.invalidate()
	var mask: PackedByteArray = map.arena().mask
	map.player_start = MapCatalog.nearest(mask, map.grid_size, Vector2i(80, 23), 1)
	var roster: Array = []
	if variant == 4:
		map.boss_id = Acts.ACTS[map.act_theme - 1].bosses[0]
		map.enemies.append({"kind": "boss_core", "cell": Vector2i(80, 52)})
		for cell in [Vector2i(56, 38), Vector2i(104, 38), Vector2i(80, 70)]: map.enemies.append({"kind": "boss_relay", "cell": cell})
		roster = ["anomaly"]
	else:
		match map.act_theme:
			1: roster = [["anomaly", "sparx", "turret"], ["gunner_orb", "rotor", "sparx"], ["anomaly", "turret", "rotor"], ["gunner_orb", "sparx", "turret"]][variant]
			2: roster = [["anomaly", "spawner", "spawner"], ["chain_worm", "spawner"], ["brood_carrier", "spawner"], ["chain_worm", "brood_carrier"]][variant]
			3: roster = [["ray_orb", "sniper"], ["anomaly", "siege", "sniper"], ["ray_orb", "siege"], ["anomaly", "sniper", "siege"]][variant]
	var spots := [Vector2i(107, 62), Vector2i(55, 55), Vector2i(100, 36)]
	for i in roster.size():
		var kind: String = roster[i]
		var cell := MapCatalog.nearest(mask, map.grid_size, spots[i], 1 if kind == "sparx" else 2)
		map.enemies.append({"kind": kind, "cell": cell, "axis": Vector2i.DOWN})
	if map.act_theme == 3:
		map.field_zones.resize(mask.size())
		for y in range(25, 31):
			for x in range(48, 56):
				if mask[y * 160 + x] != 0: map.field_zones[y * 160 + x] = 1
		if variant < 4:
			for y in range(68, 72):
				for x in range(100, 109):
					if mask[y * 160 + x] != 0: map.field_zones[y * 160 + x] = 2
	return map

func build_boss_alternative(stage: int) -> MapDefinition:
	var act := Acts.map_act(stage)
	var map := build(Acts.BOSSES[Acts.ACTS[act - 1].bosses[0]].map)
	map.map_id = "roguelite_%02d" % stage
	map.title = Acts.MAP_NAMES[stage - Acts.FIRST_MAP]
	map.sector = stage
	map.boss_id = Acts.ACTS[act - 1].bosses[1]
	# Distinct cover and perimeter shapes; the relay/core approach lanes stay open.
	match act:
		1:
			for rect in [Rect2i(65, 47, 4, 10), Rect2i(92, 47, 4, 10)]: block(map, rect)
		2:
			for rect in [Rect2i(35, 23, 12, 9), Rect2i(113, 23, 12, 9), Rect2i(35, 72, 12, 9), Rect2i(113, 72, 12, 9)]: block(map, rect)
		3:
			for rect in [Rect2i(67, 28, 4, 10), Rect2i(89, 28, 4, 10), Rect2i(51, 69, 6, 7), Rect2i(103, 69, 6, 7)]: block(map, rect)
	map.invalidate()
	return map

func build_extra(stage: int) -> MapDefinition:
	var map := MapDefinition.new()
	map.map_id = "roguelite_%02d" % stage
	map.title = Acts.MAP_NAMES[stage - Acts.FIRST_MAP]
	map.sector = stage
	map.act_theme = Acts.map_act(stage)
	map.override_terrain = true
	map.override_enemies = true
	map.override_start = true
	map.rock.resize(160 * 104)
	map.rock.fill(1)
	var variant := (stage - 24) % 3
	for y in range(25, 79):
		for x in range(40, 120):
			var dx := absf(x - 79.5)
			var dy := absf(y - 51.5)
			var open := true
			if map.act_theme == 2: open = pow(dx / 39.0, 2) + pow(dy / 26.0, 2) < 1
			if variant == 2 and dy > 17 and dx > 27: open = false
			if open: map.rock[y * 160 + x] = 0
	if variant == 1:
		block(map, Rect2i(76, 46, 8, 12))
	elif variant == 2:
		for rect in [Rect2i(61, 38, 5, 17), Rect2i(78, 53, 5, 16), Rect2i(96, 38, 5, 17)]: block(map, rect)
	map.invalidate()
	var mask: PackedByteArray = map.arena().mask
	map.player_start = MapCatalog.nearest(mask, map.grid_size, Vector2i(80, 25), 1)
	var rosters := {
		24: ["anomaly", "sparx"], 25: ["anomaly", "turret"], 26: ["gunner_orb", "rotor", "turret"],
		27: ["anomaly", "spawner"], 28: ["anomaly", "spawner", "spawner"], 29: ["chain_worm", "brood_carrier"],
		30: ["anomaly"], 31: ["anomaly", "sniper"], 32: ["ray_orb", "siege", "sniper"],
	}
	var spots := [Vector2i(103, 60), Vector2i(55, 52), Vector2i(101, 34)]
	for i in rosters[stage].size():
		var kind: String = rosters[stage][i]
		map.enemies.append({"kind": kind, "cell": MapCatalog.nearest(mask, map.grid_size, spots[i], 1 if kind == "sparx" else 2), "axis": Vector2i.DOWN})
	if map.act_theme == 3:
		map.field_zones.resize(mask.size())
		for y in range(32, 38):
			for x in range(50, 58):
				if mask[y * 160 + x] != 0: map.field_zones[y * 160 + x] = 1
		if variant == 2:
			for y in range(65, 70):
				for x in range(100, 107):
					if mask[y * 160 + x] != 0: map.field_zones[y * 160 + x] = 2
	return map
