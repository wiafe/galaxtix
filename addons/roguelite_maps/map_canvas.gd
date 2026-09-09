@tool
extends Control
signal stroke_started
signal stroke_finished
signal selection_changed
var map: MapDefinition
var tool := "select"
var enemy_kind := "anomaly"
var enemy_axis := Vector2i.DOWN
var brush_size := 1
var selected := -1 # -2 is the player.
var zoom := 1.0
var pan := Vector2.ZERO
var terrain: ImageTexture
var hover := Vector2i(-1, -1)
var dragging := false
var panning := false
var last_cell := Vector2i(-1, -1)
var erasing := false
var painted := {}
const COLORS := {"anomaly": Color("e987ec"), "sparx": Color("ff6677"), "turret": Color("ffc56b"), "spawner": Color("a594ff"), "gunner_orb": Color("ff9944"), "ray_orb": Color("6bf1db"), "rotor": Color("fff08a")}
const GLYPHS := {"anomaly": "A", "sparx": "S", "turret": "T", "spawner": "M", "gunner_orb": "G", "ray_orb": "R", "rotor": "O"}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	resized.connect(queue_redraw)

func set_map(value: MapDefinition) -> void:
	map = value
	selected = -1
	painted.clear()
	rebuild()

func rebuild() -> void:
	if map == null: return
	map.invalidate()
	var mask: PackedByteArray = map.arena().mask
	if not map.override_start: map.player_start = map.arena().start
	var pixels := PackedByteArray()
	pixels.resize(mask.size() * 4)
	var colors := [Color("28313c"), Color("4bb8cd"), Color("101924")]
	for i in mask.size(): pixels.encode_u32(i * 4, colors[mask[i]].to_abgr32())
	terrain = ImageTexture.create_from_image(Image.create_from_data(map.grid_size.x, map.grid_size.y, false, Image.FORMAT_RGBA8, pixels))
	painted.clear()
	queue_redraw()

func scale_at() -> float:
	return minf(size.x / 160.0, size.y / 104.0) * 0.94 * zoom

func origin_at() -> Vector2:
	return (size - Vector2(160, 104) * scale_at()) * 0.5 + pan

func screen_cell(cell: Vector2i) -> Vector2:
	return origin_at() + (Vector2(cell) + Vector2.ONE * 0.5) * scale_at()

func cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(((pos - origin_at()) / scale_at()).floor())

func fit() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0b1018"))
	if map == null or terrain == null: return
	var step := scale_at()
	var origin := origin_at()
	draw_texture_rect(terrain, Rect2(origin, Vector2(map.grid_size) * step), false)
	for band in [Rect2(0, 0, 160, 18), Rect2(0, 86, 160, 18)]:
		draw_rect(Rect2(origin + band.position * step, band.size * step), Color("171d26"))
	draw_rect(Rect2(origin + Vector2(MapDefinition.EDITABLE.position) * step, Vector2(MapDefinition.EDITABLE.size) * step), Color("65758a"), false, 1)
	for cell: Vector2i in painted:
		draw_rect(Rect2(origin + Vector2(cell) * step, Vector2.ONE * step), Color("28313c") if painted[cell] else Color("101924"))
	if step >= 8:
		for x in range(map.grid_size.x + 1): draw_line(origin + Vector2(x * step, 0), origin + Vector2(x * step, map.grid_size.y * step), Color(0.3, 0.4, 0.5, 0.16))
		for y in range(map.grid_size.y + 1): draw_line(origin + Vector2(0, y * step), origin + Vector2(map.grid_size.x * step, y * step), Color(0.3, 0.4, 0.5, 0.16))
	var font := ThemeDB.fallback_font
	for i in map.enemies.size():
		var enemy: Dictionary = map.enemies[i]
		var p := screen_cell(enemy.cell)
		var color: Color = COLORS.get(enemy.kind, Color.WHITE)
		var radius := maxf(7, step * 0.7)
		draw_circle(p, radius, Color("101924"))
		draw_arc(p, radius, 0, TAU, 24, color, 2, true)
		draw_string(font, p + Vector2(-4, 4), GLYPHS.get(enemy.kind, "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		if enemy.kind == "turret":
			var direction: Vector2 = Vector2(enemy.get("axis", Vector2i.DOWN)) * (radius + 5)
			draw_line(p - direction, p + direction, color, 1)
		if selected == i: draw_arc(p, radius + 4, 0, TAU, 24, Color.WHITE, 2, true)
	var player := screen_cell(map.player_start)
	draw_rect(Rect2(player - Vector2.ONE * 7, Vector2.ONE * 14), Color("72f2af"), false, 2)
	draw_string(font, player + Vector2(-4, 4), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("72f2af"))
	if selected == -2: draw_circle(player, 11, Color.WHITE, false, 2)
	if map.contains(hover):
		var radius := brush_size / 2 if tool in ["rock", "open"] else 0
		draw_rect(Rect2(origin + Vector2(hover - Vector2i.ONE * radius) * step, Vector2.ONE * step * (radius * 2 + 1)), Color(1, 1, 1, 0.7), false, 1)

func hit(pos: Vector2) -> int:
	if screen_cell(map.player_start).distance_to(pos) <= 10: return -2
	for i in range(map.enemies.size() - 1, -1, -1):
		if screen_cell(map.enemies[i].cell).distance_to(pos) <= maxf(10, scale_at()): return i
	return -1

func _gui_input(event: InputEvent) -> void:
	if map == null: return
	if event is InputEventMouseButton:
		grab_focus()
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var before: Vector2 = (event.position - origin_at()) / scale_at()
			zoom = clampf(zoom * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 0.5, 8)
			pan += event.position - (origin_at() + before * scale_at())
			queue_redraw()
			accept_event()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			return
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: return
		if not event.pressed:
			finish_stroke()
			return
		var cell := cell_at(event.position)
		if not map.contains(cell): return
		stroke_started.emit()
		dragging = true
		erasing = event.button_index == MOUSE_BUTTON_RIGHT
		last_cell = cell
		if erasing and tool not in ["open", "rock"]:
			selected = hit(event.position)
			if selected >= 0:
				map.enemies.remove_at(selected)
				map.override_enemies = true
			selected = -1
		elif tool == "select": selected = hit(event.position)
		elif tool == "enemy":
			map.enemies.append({"kind": enemy_kind, "cell": cell, "axis": enemy_axis})
			map.override_enemies = true
			selected = map.enemies.size() - 1
		elif tool == "start": selected = -2
		apply_at(cell)
		selection_changed.emit()
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		hover = cell_at(event.position)
		if panning: pan += event.relative
		elif dragging:
			# Fill gaps when a fast brush crosses several cells between mouse events.
			var steps := maxi(absi(hover.x - last_cell.x), absi(hover.y - last_cell.y))
			for i in range(1, mini(steps, 320) + 1):
				apply_at(Vector2i(Vector2(last_cell).lerp(Vector2(hover), float(i) / maxi(1, steps)).round()))
			last_cell = hover
		queue_redraw()

func apply_at(cell: Vector2i) -> void:
	if not map.contains(cell): return
	if tool in ["rock", "open"]:
		var radius := brush_size / 2
		var solid := (tool == "rock") != erasing
		for y in range(cell.y - radius, cell.y + radius + 1):
			for x in range(cell.x - radius, cell.x + radius + 1):
				var c := Vector2i(x, y)
				if not MapDefinition.EDITABLE.has_point(c): continue
				map.rock[y * map.grid_size.x + x] = 1 if solid else 0
				painted[c] = solid
		map.override_terrain = true
	elif not erasing:
		if selected == -2:
			map.player_start = cell
			map.override_start = true
		elif selected >= 0:
			map.enemies[selected].cell = cell
			map.override_enemies = true

func finish_stroke() -> void:
	if not dragging: return
	dragging = false
	rebuild()
	stroke_finished.emit()
