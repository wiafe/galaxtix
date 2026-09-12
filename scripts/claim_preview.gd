extends RefCounted
## Roguelite-only hint. The real board is never changed by prediction.
const RANGE := 16
const Acts = preload("res://scripts/roguelite_acts.gd")
const FULL_LABEL_SECTORS := 3
var result := {}
var strokes := PackedVector2Array()
var refreshed := -INF
var signature := 0

func label_opacity(depth: int) -> float:
	# Run depth, not map ID: retries keep their guidance and later acts do not reset it.
	return clampf(float(Acts.ACT_LENGTH - depth) / (Acts.ACT_LENGTH - FULL_LABEL_SECTORS), 0.0, 1.0)

func closing_path(g) -> Dictionary:
	if g.state != Game.State.PLAYING or g.phase != "run" or not g.drawing:
		return {}
	# Other seals can change the board before this cut settles. Do not promise
	# their future outcome, or treat a growing two-ended leap wall as a normal cut.
	if not g.seals.is_empty() or g.wall_building or g.leap_building or g.sap_live:
		return {}
	var dir: Vector2i = g.tether_dir if g.tether_active else g.last_dir
	if absi(dir.x) + absi(dir.y) != 1: return {}
	var tip: Vector2i = g.trail.back() if g.tether_active else g.p
	var extension: Array[Vector2i] = []
	for distance in range(1, RANGE + 1):
		var cell: Vector2i = tip + dir * distance
		if not g.in_bounds(cell): return {}
		match g.cells[g.idx(cell.x, cell.y)]:
			Game.FREE: extension.append(cell)
			Game.CLAIMED:
				return {"end": cell, "extension": extension}
			_: return {} # Rocks, own trail and unfinished walls are not closing edges.
	return {}

func refresh(g, force := false) -> void:
	var path := closing_path(g)
	if path.is_empty():
		result.clear()
		strokes.clear()
		signature = 0
		return
	var key := hash([g.p, g.last_dir, g.trail, path.end])
	if not force and key == signature and g.time >= refreshed and g.time - refreshed < 0.08:
		return
	signature = key
	refreshed = g.time
	var board: PackedByteArray = g.cells.duplicate()
	for cell in path.extension: board[g.idx(cell.x, cell.y)] = Game.TRAIL
	var region: PackedInt32Array = g.capture_region(board)
	result = {"end": path.end, "extension": path.extension, "region": region, "split": region.is_empty()}
	strokes.clear()
	var mask := PackedByteArray()
	mask.resize(board.size())
	for i in region: mask[i] = 1
	# Diagonal runs clipped to predicted cells, drawn beneath enemies and the ship.
	for i in region:
		var x: int = i % g.grid_width
		var y: int = i / g.grid_width
		if (x + y) % 4 != 0: continue
		if x + 1 < g.grid_width and y > 0 and mask[i - g.grid_width + 1]: continue
		var end := Vector2i(x, y)
		while end.x > 0 and end.y + 1 < g.grid_height and mask[g.idx(end.x - 1, end.y + 1)]:
			end += Vector2i(-1, 1)
		strokes.append(g.center(Vector2i(x, y)) + Vector2(3, -3))
		strokes.append(g.center(end) + Vector2(-3, 3))

func draw(g) -> void:
	refresh(g)
	if result.is_empty(): return
	var tint: Color = g.coast_color()
	var alpha := 0.16 + 0.02 * sin(g.time * 3.0)
	for i in range(0, strokes.size(), 2):
		g.lines.seg(strokes[i], strokes[i + 1], Color(tint, alpha), 0.0, 0.0, 0.8)
	var end: Vector2 = g.center(result.end)
	var from: Vector2 = g.vis
	var direction := (end - from).normalized()
	for step in range(0, int(from.distance_to(end)), 12):
		g.lines.seg(from + direction * step, from + direction * minf(step + 4, from.distance_to(end)), Color(Palette.CYAN, 0.45), 0.0, 0.0, 0.8)
	g.lines.circle(end, 5.0 + 1.5 * sin(g.time * 5.0), Palette.CYAN, 12, 0.0, 0.0, 1.0)
	var text_alpha := label_opacity(g.level)
	if text_alpha <= 0.0: return
	var label := "SPLIT" if result.split else "CLAIM"
	if g.ship.id == "bulwark": label += " / ON SEAL"
	var label_at: Vector2 = g.vis + Vector2(0, -22)
	label_at.x = clampf(label_at.x, g.FX + 80, g.FX + g.grid_width * g.CELL - 80)
	label_at.y = maxf(label_at.y, g.FY + 16)
	VectorFont.draw(g.lines, label, label_at, 11, Color(Palette.CYAN, text_alpha), 0.0, 0.0, 1)
