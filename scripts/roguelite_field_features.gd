extends RefCounted
## Optional map-authored hazards. All positions use the live grid, never the saved resource.
const SNIPER_RECHARGE := 3.5
const SNIPER_WARNING := 1.25
const SNIPER_FIRE := 0.3
const SIEGE_WARNING := 1.5
const SIEGE_RADIUS := 2
var snipers: Array[Dictionary] = []
var zone_mask := PackedByteArray()
var zone_edges: Array[PackedVector2Array] = []
var zone_marks: Array[Vector2i] = []
var zone_time := 0.0
var fortified := {} # Hardened walls stay reinforced after becoming claimed land.
var lost_land := {} # Reclaiming erosion restores territory, but never pays another draft.

func reset(g) -> void:
	snipers.clear()
	zone_mask.clear()
	zone_edges.clear()
	zone_marks.clear()
	zone_time = 0.0
	fortified.clear()
	lost_land.clear()
	var map: MapDefinition = g.authored_map
	if map == null: return
	if map.field_zones.size() == g.cells.size():
		zone_mask = map.field_zones.duplicate()
		for i in zone_mask.size():
			if g.cells[i] == g.ROCK: zone_mask[i] = 0
		build_zone_visuals(g)
	if map.override_enemies:
		for enemy in map.enemies:
			if enemy.kind == "sniper":
				var cell: Vector2i = MapCatalog.nearest(g.field_arena.mask, map.grid_size, enemy.cell, 2)
				snipers.append({"cell": cell, "phase": "idle", "clock": 2.0, "direction": Vector2.DOWN, "captured": false})

func zone_at(g, cell: Vector2i) -> int:
	if zone_mask.is_empty() or not g.in_bounds(cell): return 0
	return zone_mask[g.idx(cell.x, cell.y)]

func shielded(g) -> bool:
	return zone_at(g, g.p) == 1

func zone_phase() -> String:
	var cycle := fmod(zone_time, 6.0)
	return "live" if cycle >= 4.0 else ("warn" if cycle >= 3.0 else "safe")

func zone_contact(g) -> void:
	if g.phase == "run" and g.state == g.State.PLAYING and zone_at(g, g.p) == 2 and zone_phase() == "live":
		g.die("HAZARD ZONE")

func build_zone_visuals(g) -> void:
	zone_edges.assign([PackedVector2Array(), PackedVector2Array(), PackedVector2Array()])
	for i in zone_mask.size():
		var kind := zone_mask[i]
		if kind == 0: continue
		var c := Vector2i(i % g.grid_width, i / g.grid_width)
		var origin: Vector2 = Vector2(c) * g.CELL
		var edges := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
		var corners := [Vector2.ZERO, Vector2(g.CELL, 0), Vector2(g.CELL, g.CELL), Vector2(0, g.CELL)]
		for side in 4:
			if zone_at(g, c + edges[side]) == kind: continue
			zone_edges[kind].append(origin + corners[side])
			zone_edges[kind].append(origin + corners[(side + 1) % 4])
		if (c.x % 3 == 0 and c.y % 3 == 0) or (zone_at(g, c + Vector2i.LEFT) != kind and zone_at(g, c + Vector2i.UP) != kind):
			zone_marks.append(c)

func update(g, dt: float) -> void:
	if g.phase != "run" or g.state != g.State.PLAYING or g.freeze_time > 0.0: return
	for sniper in snipers:
		if sniper.captured: continue
		sniper.clock -= dt
		if sniper.clock <= 0.0:
			match sniper.phase:
				"idle":
					sniper.phase = "warn"
					sniper.clock = SNIPER_WARNING
					sniper.direction = (g.vis - g.center(sniper.cell)).normalized()
					if sniper.direction == Vector2.ZERO: sniper.direction = Vector2.DOWN
				"warn":
					sniper.phase = "fire"
					sniper.clock = SNIPER_FIRE
				"fire":
					sniper.phase = "idle"
					sniper.clock = SNIPER_RECHARGE
		if sniper.phase == "fire":
			sniper_contact(g, sniper)
			if g.state != g.State.PLAYING or g.phase != "run": return

func beam_end(g, sniper: Dictionary) -> Vector2:
	var origin: Vector2 = g.center(sniper.cell)
	var last := origin
	for step in range(1, 700):
		var point: Vector2 = origin + Vector2(sniper.direction) * step * 2.0
		var cell: Vector2i = g.to_cell(point)
		if not g.in_bounds(cell) or g.cells[g.idx(cell.x, cell.y)] == g.ROCK: return last
		last = point
	return last

func sniper_contact(g, sniper: Dictionary) -> void:
	if sniper.captured or shielded(g) or g.invuln > 0.0: return
	var origin: Vector2 = g.center(sniper.cell)
	var end := beam_end(g, sniper)
	if Geometry2D.get_closest_point_to_segment(g.vis, origin, end).distance_to(g.vis) <= 5.0:
		# Existing defense cards also protect against a direct beam hit.
		if g.tether_hit(g.p): g.die("SNIPER BEAM")
		return
	var steps := maxi(1, ceili(origin.distance_to(end) / 3.0))
	for step in range(steps + 1):
		var cell: Vector2i = g.to_cell(origin.lerp(end, float(step) / steps))
		if not g.in_bounds(cell): continue
		var value: int = g.cells[g.idx(cell.x, cell.y)]
		if value == g.TRAIL and zone_at(g, cell) != 1:
			if g.tether_hit(cell) and g.wire_hit(): g.die("SNIPER BEAM")
			return
		if value == g.SEAL_SOFT:
			g.lose_seal(g.seal_at(cell))
			return
	if g.sap_live:
		var disc: Vector2 = g.center(g.sap_cell)
		if Geometry2D.get_closest_point_to_segment(disc, origin, end).distance_to(disc) < g.sap_charge * g.CELL:
			if g.wire_hit(): g.die("SNIPER BEAM")

func capture_snipers(g) -> int:
	var caught := 0
	for sniper in snipers:
		if not sniper.captured and g.cells[g.idx(sniper.cell.x, sniper.cell.y)] == g.CLAIMED:
			sniper.captured = true
			sniper.phase = "idle"
			caught += 1
			g.sparks.burst(g.center(sniper.cell), 32, 180, 1.5, 0.5, Palette.GREEN)
	return caught

func on_claim(g) -> void:
	var caught := capture_snipers(g)
	if caught > 0:
		g.award_flux(caught * (g.hazard_capture_value() + (1.25 * g.card_power("harvest") if g.has_card("harvest") else 0.0)))
	for i in lost_land.keys():
		if g.cells[i] == g.CLAIMED: lost_land.erase(i)

func remember_walls(g, wall: Array) -> void:
	for cell: Vector2i in wall:
		var i: int = g.idx(cell.x, cell.y)
		if g.cells[i] == g.HARD: fortified[i] = true

func breakable(g, cell: Vector2i) -> bool:
	if g.boss.protected_cell(cell): return false
	if not g.in_bounds(cell): return false
	var i: int = g.idx(cell.x, cell.y)
	if g.cells[i] != g.CLAIMED or g.field_arena.mask[i] != 2 or fortified.has(i): return false
	if zone_at(g, cell) == 1: return false
	# Never remove the player's foothold or either end of an unfinished crossing.
	if cell.distance_squared_to(g.p) <= 2 or cell.distance_squared_to(g.anchor) <= 2: return false
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var next: Vector2i = cell + direction
		if g.in_bounds(next) and g.cells[g.idx(next.x, next.y)] in [g.TRAIL, g.HARD, g.SEAL_SOFT]: return false
	for zone in g.zones:
		if zone.captured and cell.distance_squared_to(zone.cell) <= zone.radius * zone.radius: return false
	if not g.breach.is_empty() and g.breach.sealed and cell.distance_squared_to(g.breach.cell) <= g.breach.radius * g.breach.radius: return false
	return true

func update_siege(g, q, dt: float, speed: float) -> void:
	var behavior: Dictionary = g.authored_behaviors[q]
	behavior.clock -= dt
	if behavior.phase == "warn":
		if behavior.clock <= 0.0:
			break_patch(g, behavior.target)
			behavior.phase = "roam"
			behavior.clock = 3.0
		return
	g.move_authored_orb(q, dt, speed * 0.35)
	if behavior.clock > 0.0: return
	var best := Vector2i(-1, -1)
	var distance := INF
	for cell: Vector2i in g.border_cells:
		if not breakable(g, cell): continue
		var d: float = g.center(cell).distance_squared_to(q.c)
		if d < distance:
			distance = d
			best = cell
	behavior.clock = 0.75
	if best.x < 0: return
	q.v = (g.center(best) - q.c).normalized()
	if distance <= pow(6 * g.CELL, 2):
		behavior.target = best
		behavior.phase = "warn"
		behavior.clock = SIEGE_WARNING

func break_patch(g, target: Vector2i) -> int:
	var removed := 0
	for dy in range(-SIEGE_RADIUS, SIEGE_RADIUS + 1):
		for dx in range(-SIEGE_RADIUS, SIEGE_RADIUS + 1):
			if dx * dx + dy * dy > SIEGE_RADIUS * SIEGE_RADIUS: continue
			var cell := target + Vector2i(dx, dy)
			if not breakable(g, cell): continue
			var i: int = g.idx(cell.x, cell.y)
			g.cells[i] = g.FREE
			if g.credited[i] == 1: lost_land[i] = true
			removed += 1
	if removed == 0: return 0
	g.free_count += removed
	g.capture_percent = (g.first_claims - lost_land.size()) * 100.0 / maxi(1, g.base_free)
	g.grid_changed()
	# Sparx remain on a valid coast after their former rail is destroyed.
	for sparx in g.sparxes:
		if g.cells[g.idx(sparx.c.x, sparx.c.y)] != g.CLAIMED:
			var best: Vector2i = g.p
			var distance := INF
			for cell: Vector2i in g.border_cells:
				var d := cell.distance_squared_to(sparx.c)
				if d < distance:
					distance = d
					best = cell
			sparx.c = best
			sparx.prev = best
			sparx.vis = g.center(best)
	g.sparks.ripple(g.center(target), 5, 140, 0.5, Palette.ORANGE)
	g.show_objective_notice("SIEGE - TERRITORY LOST")
	return removed

func draw(g) -> void:
	var origin := Vector2(g.FX, g.FY)
	var phase := zone_phase()
	for kind in range(1, zone_edges.size()):
		var color := Palette.GREEN if kind == 1 else (Palette.RED if phase == "live" else (Palette.YELLOW if phase == "warn" else Color(Palette.RED, 0.35)))
		var edges: PackedVector2Array = zone_edges[kind]
		for i in range(0, edges.size(), 2): g.lines.seg(origin + edges[i], origin + edges[i + 1], color, 0.05, 0.01, 1.5)
	for cell in zone_marks:
		var pos: Vector2 = g.center(cell)
		if zone_at(g, cell) == 1:
			g.lines.seg(pos - Vector2(2, 0), pos + Vector2(2, 0), Palette.GREEN)
			g.lines.seg(pos - Vector2(0, 2), pos + Vector2(0, 2), Palette.GREEN)
		else:
			var color := Palette.RED if phase == "live" else (Palette.YELLOW if phase == "warn" else Color(Palette.RED, 0.35))
			g.lines.seg(pos - Vector2(2, 2), pos + Vector2(2, 2), color)
			g.lines.seg(pos - Vector2(2, -2), pos + Vector2(2, -2), color)
	if shielded(g): g.lines.circle(g.vis, 12, Palette.GREEN, 8)
	for sniper in snipers:
		if sniper.captured: continue
		var pos: Vector2 = g.center(sniper.cell)
		var color := Palette.RED
		g.lines.circle(pos, 16, color, 4, 0.1, 0.02, 2.0)
		g.lines.circle(pos, 9, color, 4)
		g.lines.circle(pos, 5, color, 8)
		var aim: Vector2 = sniper.direction
		var side := aim.orthogonal() * 3.5
		for offset in [-side, side]:
			g.lines.seg(pos + aim * 10 + offset, pos + aim * 25 + offset, color, 0.1, 0.02, 2.0)
		if sniper.phase == "warn":
			g.dashed(pos, beam_end(g, sniper), Palette.YELLOW, 7, 5)
			g.lines.circle(pos, 21 + sin(g.time * 14) * 2, Palette.YELLOW, 16)
			g.lines.circle(pos + aim * 38, 8, Palette.YELLOW, 4)
		elif sniper.phase == "fire":
			g.lines.seg(pos, beam_end(g, sniper), Palette.RED, 0.05, 0.01, 3.0)
			g.lines.seg(pos, beam_end(g, sniper), Palette.WHITE, 0.05, 0.01, 1.0)

func draw_siege(g, q) -> void:
	g.draw_anomaly_ring(q.c, 9, 6, q.col_off, 2.0)
	g.draw_anomaly_ring(q.c, 4, 4, q.col_off + 3)
	var behavior: Dictionary = g.authored_behaviors[q]
	if behavior.phase == "warn":
		var target: Vector2 = g.center(behavior.target)
		g.dashed(q.c, target, Palette.YELLOW, 4, 4)
		g.lines.circle(target, (SIEGE_RADIUS + 0.5) * g.CELL, Palette.YELLOW, 16, 0.05, 0.01, 2.0)
		g.arc(target, (SIEGE_RADIUS + 1) * g.CELL, -PI / 2, -PI / 2 + TAU * clampf(1.0 - float(behavior.clock) / SIEGE_WARNING, 0.01, 1.0), Palette.ORANGE, 1.5)
