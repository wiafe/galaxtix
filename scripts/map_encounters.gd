@tool
extends RefCounted
## Pure placement shared by the editor preview and the running encounter.
const Sectors = preload("res://scripts/roguelite_sectors.gd")

static func settings(map, kind: String) -> Dictionary:
	return map.encounters.get(kind, {}) if map != null else {}

static func goal(map, kind: String, depth: int) -> int:
	return int(settings(map, kind).get("goal", Sectors.RACE_GOAL if kind == "race" else Sectors.capture_goal(depth)))

static func seconds(map, kind: String) -> float:
	return float(settings(map, kind).get("seconds", Sectors.RIVAL_SECONDS))

static func runs(map, kind: String, depth: int) -> int:
	if kind == "beacon" and settings(map, kind).has("objectives"): return settings(map, kind).objectives.size()
	return int(settings(map, kind).get("runs", Sectors.objective_count(kind, depth)))

static func preview(map, depth: int, kind: String) -> Dictionary:
	var arena: Dictionary = map.arena()
	var shape: Array = map.rock_rectangles() if map.override_terrain else Sectors.holes(map.sector, map.grid_size)
	var layout := {"arena": arena, "shape": shape, "start": map.player_start if map.override_start else arena.start, "nodes": [], "turrets": [], "spawners": []}
	layout.objectives = populate(layout, map, depth, kind)
	return layout

static func populate(layout: Dictionary, map, lvl: int, kind: String, extractor_rank := 0) -> Dictionary:
	var placement := RandomNumberGenerator.new()
	placement.seed = hash("roguelite-pickups:%d" % lvl)
	var occupied: Array = [layout.start]
	if map != null and map.override_enemies:
		for enemy in map.enemies: occupied.append(enemy.cell)
	layout.nodes.clear()
	for i in 3 + extractor_rank / 5 + (2 if kind == "salvage" else 0):
		var cell := layout_pick(placement, 10, occupied, 24.0, layout.shape, layout.arena)
		layout.nodes.append({"cell": cell, "rare": false})
		occupied.append(cell)
	if map != null and map.override_pickups:
		layout.nodes = map.pickups.duplicate(true)
		for node in layout.nodes:
			node.rare = false
			occupied.append(node.cell)
	layout.turrets.clear()
	layout.spawners.clear()
	for i in Sectors.turret_count(kind, lvl):
		var cell := layout_pick(placement, 10, occupied, 28.0, layout.shape, layout.arena)
		layout.turrets.append({"cell": cell, "axis": Vector2i.DOWN})
		occupied.append(cell)
	if map != null and map.override_enemies:
		layout.turrets.clear()
		for enemy in map.enemies:
			if enemy.kind == "turret": layout.turrets.append({"cell": enemy.cell, "axis": enemy.get("axis", Vector2i.DOWN)})
			elif enemy.kind == "spawner": layout.spawners.append({"cell": enemy.cell})
	var found := objectives(layout, lvl, kind, placement, occupied)
	var custom := settings(map, kind)
	if custom.has("objectives"):
		var markers: Array = custom.objectives.duplicate(true)
		match kind:
			"beacon": found.zones = markers
			"cargo": found.pod = markers[0].cell if not markers.is_empty() else Vector2i(-1, -1)
			"breach", "rival":
				found[kind] = markers[0] if not markers.is_empty() else {}
	return found

static func markers(found: Dictionary) -> Array:
	match String(found.kind):
		"beacon": return found.zones.duplicate(true)
		"cargo": return [{"cell": found.pod, "radius": 0}] if found.pod.x >= 0 else []
		"breach", "rival": return [found[found.kind].duplicate(true)] if not found[found.kind].is_empty() else []
	return []

static func objectives(layout: Dictionary, lvl: int, kind: String, placement: RandomNumberGenerator, occupied: Array) -> Dictionary:
	var found := {"kind": kind, "zones": [], "pod": Vector2i(-1, -1), "breach": {}}
	match kind:
		"beacon":
			for i in Sectors.objective_count(kind, lvl):
				var disc := pick_disc(placement, Sectors.BEACON_RADIUS, occupied, layout.arena)
				found.zones.append(disc)
				occupied.append(disc.cell)
		"cargo":
			found.pod = layout_pick(placement, 10, occupied, 40.0, layout.shape, layout.arena)
		"breach":
			found.breach = pick_disc(placement, Sectors.BREACH_RADIUS, occupied, layout.arena)
		"rival":
			found.rival = pick_disc(placement, Sectors.RIVAL_RADIUS, occupied, layout.arena)
	return found

## A disc centre whose every cell is playable void, clear of pickups, turrets and the start.
## Rails are mask 1 and begin claimed, so a disc touching one would start half captured.
## Candidates come straight from the arena's free cells; the shared arena is never mutated.
static func pick_disc(placement: RandomNumberGenerator, radius: int, avoid: Array, arena: Dictionary) -> Dictionary:
	var free: Array = arena.get("free_cells", [])
	if free.is_empty():
		return {"cell": layout_pick(placement, 10, avoid, 30.0), "radius": radius}
	var fallback := Vector2i(-1, -1)
	var fallback_d := -1.0
	for r in range(radius, 0, -1):
		var best := Vector2i(-1, -1)
		var best_d := -1.0
		for tries in 80:
			var c: Vector2i = free[placement.randi_range(0, free.size() - 1)]
			if not disc_free(c, r, arena.mask):
				continue
			var d := 1e9
			for a in avoid:
				d = minf(d, Vector2(c - (a as Vector2i)).length())
			if d > fallback_d:
				fallback_d = d
				fallback = c
			if d < r + 4:
				continue
			if d > best_d:
				best_d = d
				best = c
			if d > 30.0:
				break
		if best.x >= 0:
			return {"cell": best, "radius": r}
	if fallback.x >= 0:
		return {"cell": fallback, "radius": 1}
	return {"cell": free[placement.randi_range(0, free.size() - 1)], "radius": 1}

static func disc_free(c: Vector2i, radius: int, mask: PackedByteArray) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var q := c + Vector2i(dx, dy)
			if not Rect2i(0, 0, 160, 104).has_point(q) or mask[q.y * 160 + q.x] != 2:
				return false
	return true

static func layout_pick(rng: RandomNumberGenerator, margin: int, avoid: Array, want_d: float, shape: Array = [], arena: Dictionary = {}) -> Vector2i:
	var best := Vector2i(160 / 2, 104 / 2)
	var best_d := -1.0
	for tries in 60:
		var c := Vector2i(rng.randi_range(margin, 160 - 1 - margin), rng.randi_range(margin, 104 - 1 - margin))
		if not arena.is_empty():
			c = arena.free_cells[rng.randi_range(0, arena.free_cells.size() - 1)]
		var inside := false
		for rc in shape:
			if (rc as Rect2i).grow(3).has_point(c):
				inside = true
				break
		if inside:
			continue
		var d := 1e9
		for a in avoid:
			d = minf(d, Vector2(c - (a as Vector2i)).length())
		if d > best_d:
			best_d = d
			best = c
		if d > want_d:
			break
	return best
