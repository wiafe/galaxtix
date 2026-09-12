@tool
extends RefCounted
## Body cells become real territory when a loop slices them away.
const CARVE_GOAL := 0.60
const OPEN_SECONDS := 6.0
var body := {}
var original_size := 0
var phase := "armored"
var clock := 2.0
var cycle := 0
var held_cut := false
var edges := PackedVector2Array()
var ribs := PackedVector2Array()

static func footprint(map: MapDefinition) -> Dictionary:
	var core := Vector2i.ZERO
	var thorns: Array[Vector2i] = []
	for enemy in map.enemies:
		if enemy.kind == "boss_core": core = enemy.cell
		if enemy.kind == "boss_relay": thorns.append(enemy.cell)
	var result := {}
	for cell: Vector2i in map.arena().free_cells:
		var delta := Vector2(cell - core)
		if delta.length_squared() <= 16: continue # The heart keeps its own locked shell.
		var inside := pow(delta.x / 24.0, 2) + pow(delta.y / 15.0, 2) <= 1.0
		for thorn in thorns:
			inside = inside or cell.distance_squared_to(thorn) <= 36 or Geometry2D.get_closest_point_to_segment(Vector2(cell), Vector2(core), Vector2(thorn)).distance_to(Vector2(cell)) <= 4.0
		if inside: result[cell.y * map.grid_size.x + cell.x] = cell
	return result

func reset(g, boss) -> void:
	body = footprint(g.authored_map)
	for i in body.keys():
		if g.cells[i] != g.FREE: body.erase(i)
	original_size = body.size()
	phase = "armored"
	clock = 2.0
	cycle = 0
	held_cut = false
	rebuild_shape(g)
	set_open(g, false)

func carved() -> float:
	return 1.0 - float(body.size()) / maxi(1, original_size)

func ready() -> bool:
	return carved() >= CARVE_GOAL

func instruction(unlocked: bool) -> String:
	if unlocked: return "ENCLOSE THE HEART"
	if phase == "exposed": return "FINISH YOUR CUT" if clock <= 0 else "CUT THROUGH ITS BODY"
	return "WAIT FOR THE BODY TO OPEN"

func set_open(g, opened: bool) -> void:
	var changed := false
	for i in body:
		if opened and g.cells[i] == g.ROCK:
			g.cells[i] = g.FREE
			g.free_count += 1
			changed = true
		elif not opened and g.cells[i] == g.FREE:
			g.cells[i] = g.ROCK
			g.free_count -= 1
			changed = true
	if not changed: return
	# Reclosing armor must not trap a roaming enemy inside solid cells.
	if not opened:
		for q in g.qixes:
			var cell: Vector2i = g.to_cell(q.c)
			if body.has(g.idx(cell.x, cell.y)):
				q.c = g.center(MapCatalog.nearest(g.cells, Vector2i(g.grid_width, g.grid_height), cell, g.FREE))
				while q.len > 2 and g.qix_blocked(q.c, q.theta, q.len): q.len *= 0.8
				q.hist.clear()
	g.grid_changed()

func observe(g) -> void:
	var removed := 0
	var piece := Vector2.ZERO
	for i in body.keys():
		if g.cells[i] != g.CLAIMED: continue
		piece += g.center(body[i])
		body.erase(i)
		removed += 1
	if removed == 0: return
	rebuild_shape(g)
	g.sparks.burst(piece / removed, mini(100, removed), 160, 1.2, 0.7, Palette.GREEN)
	g.show_objective_notice("BODY CARVED")

func seeds(g, boss, board: PackedByteArray = PackedByteArray()) -> PackedInt32Array:
	if board.is_empty(): board = g.cells
	var result := PackedInt32Array()
	if boss.unlocked or phase != "exposed": return result
	# The heart guards the connected body, so an outside loop cannot swallow it whole.
	for i in g.disc_cells(boss.core, 6):
		if body.has(i) and board[i] == g.FREE: result.append(i)
	return result

func update(g, boss, dt: float) -> void:
	if boss.unlocked: return
	if phase == "exposed" and clock > 0 and (g.drawing or g.sap_live or not g.seals.is_empty()): held_cut = true
	clock -= dt
	if clock > 0: return
	match phase:
		"armored":
			phase = "warn"
			clock = 1.4
			for thorn in boss.relays:
				if not thorn.captured: thorn.phase = "warn"
		"warn":
			phase = "exposed"
			clock = OPEN_SECONDS
			held_cut = g.drawing or g.sap_live or not g.seals.is_empty()
			set_open(g, true)
			for index in boss.relays.size():
				var thorn: Dictionary = boss.relays[index]
				thorn.phase = "idle"
				thorn.cycle = cycle
				if not thorn.captured: boss.attack(g, thorn, index)
			g.show_objective_notice("BODY OPEN - CUT THROUGH IT")
		"exposed":
			# Keep the window open through detached Bulwark seals and movement abilities.
			if held_cut and (g.drawing or g.sap_live or not g.seals.is_empty()): return
			if body.has(g.idx(g.p.x, g.p.y)): return # Never close armor on a pilot.
			phase = "armored"
			clock = 2.5
			cycle += 1
			held_cut = false
			set_open(g, false)

func rebuild_shape(g) -> void:
	edges.clear()
	ribs.clear()
	for i in body:
		var cell: Vector2i = body[i]
		var point: Vector2 = g.center(cell)
		var half: float = g.CELL * 0.5
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if body.has(g.idx(next.x, next.y)): continue
			var middle := point + Vector2(direction) * half
			var side := Vector2(direction).orthogonal() * half
			edges.append(middle - side)
			edges.append(middle + side)
		if cell.y % 2 == 0:
			ribs.append(point - Vector2(half, 0))
			ribs.append(point + Vector2(half, 0))

func draw(g, boss) -> void:
	var open: bool = phase == "exposed" or boss.unlocked
	var color: Color = Palette.YELLOW if open else g.anomaly_color()
	for i in range(0, ribs.size(), 2): g.lines.seg(ribs[i], ribs[i + 1], Color(color, 0.16), 0, 0, 1)
	for i in range(0, edges.size(), 2):
		g.lines.seg(edges[i], edges[i + 1], color if open else g.anomaly_color(i / 8), 0.1 if open else 2.0, 0.03 if open else 0.5, 1.6)
	for thorn in boss.relays:
		if thorn.captured: continue
		var point: Vector2 = g.center(thorn.cell)
		g.lines.circle(point, 10, color, 8, 0.2, 0.04, 2)
		if phase == "warn":
			for i in 12:
				var direction := Vector2.RIGHT.rotated(i * TAU / 12 + cycle * PI / 12)
				g.lines.seg(point + direction * 18, point + direction * 34, Palette.YELLOW)
	var pos: Vector2 = g.center(boss.core)
	if not boss.unlocked: g.draw_anomaly_ring(pos, 4.0 * g.CELL, 24, 0, 1.6)
	var heart := PackedVector2Array([pos + Vector2(-16, -8), pos + Vector2(-8, -16), pos, pos + Vector2(8, -16), pos + Vector2(16, -8), pos + Vector2(16, 0), pos + Vector2(0, 20), pos + Vector2(-16, 0)])
	g.lines.polyline(heart, true, Palette.YELLOW if boss.unlocked else g.anomaly_color(), 0.2, 0.04, 2)
