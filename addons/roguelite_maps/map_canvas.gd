@tool
extends Control
signal stroke_started
signal stroke_finished
signal selection_changed
const Encounters = preload("res://scripts/map_encounters.gd")
var encounter := "survey"
var depth := 1
var preview := {}
var pickup_markers: Array = []
var objective_markers: Array = []
var boss_body := {}
var map: MapDefinition
var tool := "select"
var enemy_kind := "anomaly"
var enemy_axis := Vector2i.DOWN
var brush_size := 1
var selected := -1 # -2 is the player.
var zoom := 1.0
var pan := Vector2.ZERO
var terrain: ImageTexture
var zone_texture: ImageTexture
var hover := Vector2i(-1, -1)
var dragging := false
var panning := false
var last_cell := Vector2i(-1, -1)
var erasing := false
var painted := {}
const COLORS := {"anomaly": Color("e987ec"), "sparx": Color("ff6677"), "turret": Color("ffc56b"), "spawner": Color("a594ff"), "gunner_orb": Color("ff9944"), "ray_orb": Color("6bf1db"), "rotor": Color("fff08a"), "chain_worm": Color("75e7aa"), "brood_carrier": Color("cb8cff"), "sniper": Color("ff7766"), "siege": Color("ffbb55")}
const GLYPHS := {"anomaly": "A", "sparx": "S", "turret": "T", "spawner": "M", "gunner_orb": "G", "ray_orb": "R", "rotor": "O", "chain_worm": "W", "brood_carrier": "B", "sniper": "N", "siege": "D", "boss_core": "C", "boss_relay": "R"}

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
	rebuild_zones()
	rebuild_preview()
	painted.clear()
	queue_redraw()

func set_encounter(value: String, at_depth: int) -> void:
	encounter = value
	depth = at_depth
	selected = -1
	rebuild_preview()
	selection_changed.emit()

func rebuild_preview() -> void:
	boss_body.clear()
	if map == null or map.arena().free_cells.is_empty():
		pickup_markers.clear()
		objective_markers.clear()
		queue_redraw()
		return
	preview = Encounters.preview(map, depth, encounter)
	pickup_markers = preview.nodes
	objective_markers = Encounters.markers(preview.objectives)
	if map.boss_id == "thorn_maw": boss_body = preload("res://scripts/thorn_maw.gd").footprint(map)
	queue_redraw()

func author_pickups() -> void:
	if map.override_pickups: return
	map.pickups.assign(pickup_markers.duplicate(true))
	map.override_pickups = true

func author_objectives() -> void:
	if not map.encounters.has(encounter): map.encounters[encounter] = {}
	if not map.encounters[encounter].has("objectives"):
		map.encounters[encounter].objectives = objective_markers.duplicate(true)

func selected_record() -> Dictionary:
	if selected <= -1000:
		var i := -selected - 1000
		return objective_markers[i] if i < objective_markers.size() else {}
	if selected <= -100:
		var i := -selected - 100
		return pickup_markers[i] if i < pickup_markers.size() else {}
	if selected >= 0 and selected < map.enemies.size(): return map.enemies[selected]
	return {}

func move_selected(cell: Vector2i) -> void:
	if selected <= -100 and selected_record().get("cell") == cell: return
	if selected <= -1000:
		author_objectives()
		map.encounters[encounter].objectives[-selected - 1000].cell = cell
	elif selected <= -100:
		author_pickups()
		map.pickups[-selected - 100].cell = cell
	elif selected == -2:
		map.player_start = cell
		map.override_start = true
	elif selected >= 0:
		map.enemies[selected].cell = cell
		map.override_enemies = true
	# Keep dragged markers under the pointer; the full preview rebuild follows release.
	if selected <= -100: selected_record().cell = cell

func remove_selected() -> void:
	if selected <= -1000:
		author_objectives()
		map.encounters[encounter].objectives.remove_at(-selected - 1000)
	elif selected <= -100:
		author_pickups()
		map.pickups.remove_at(-selected - 100)
	elif selected >= 0:
		map.enemies.remove_at(selected)
		map.override_enemies = true
	selected = -1

func rebuild_zones() -> void:
	zone_texture = null
	if map.field_zones.size() != map.grid_size.x * map.grid_size.y: return
	var pixels := PackedByteArray()
	pixels.resize(map.field_zones.size() * 4)
	for i in map.field_zones.size():
		if map.field_zones[i] == 0: continue
		var color := Color(0.25, 1.0, 0.65, 0.55) if map.field_zones[i] == 1 else Color(1.0, 0.2, 0.3, 0.55)
		pixels.encode_u32(i * 4, color.to_abgr32())
	zone_texture = ImageTexture.create_from_image(Image.create_from_data(map.grid_size.x, map.grid_size.y, false, Image.FORMAT_RGBA8, pixels))
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
	if zone_texture != null: draw_texture_rect(zone_texture, Rect2(origin, Vector2(map.grid_size) * step), false)
	for cell: Vector2i in boss_body.values():
		draw_rect(Rect2(origin + Vector2(cell) * step, Vector2.ONE * step), Color(0.75, 0.35, 0.9, 0.24))
	for band in [Rect2(0, 0, 160, 18), Rect2(0, 86, 160, 18)]:
		draw_rect(Rect2(origin + band.position * step, band.size * step), Color("171d26"))
	draw_rect(Rect2(origin + Vector2(MapDefinition.EDITABLE.position) * step, Vector2(MapDefinition.EDITABLE.size) * step), Color("65758a"), false, 1)
	for cell: Vector2i in painted:
		draw_rect(Rect2(origin + Vector2(cell) * step, Vector2.ONE * step), Color("28313c") if painted[cell] else Color("101924"))
	if step >= 8:
		for x in range(map.grid_size.x + 1): draw_line(origin + Vector2(x * step, 0), origin + Vector2(x * step, map.grid_size.y * step), Color(0.3, 0.4, 0.5, 0.16))
		for y in range(map.grid_size.y + 1): draw_line(origin + Vector2(0, y * step), origin + Vector2(map.grid_size.x * step, y * step), Color(0.3, 0.4, 0.5, 0.16))
	var font := ThemeDB.fallback_font
	for i in pickup_markers.size():
		var point := screen_cell(pickup_markers[i].cell)
		draw_circle(point, 7, Color("101924"))
		draw_arc(point, 7, 0, TAU, 6, Color("ffe16b"), 2, true)
		draw_string(font, point + Vector2(-3, 4), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ffe16b"))
		if selected == -100 - i: draw_circle(point, 12, Color.WHITE, false, 2)
	for i in objective_markers.size():
		var marker: Dictionary = objective_markers[i]
		var point := screen_cell(marker.cell)
		var color := Color("d794ff") if encounter == "breach" else Color("68e9dc")
		var radius := maxf(10, float(marker.get("radius", 0)) * step)
		draw_circle(point, radius, Color(color, 0.08))
		draw_circle(point, radius, color, false, 1.5)
		draw_string(font, point + Vector2(-4, 4), {"beacon": "B", "cargo": "C", "breach": "!", "rival": "R"}.get(encounter, "?"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		if selected == -1000 - i: draw_circle(point, radius + 4, Color.WHITE, false, 2)
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
		var radius := brush_size / 2 if tool in ["rock", "open", "shield_zone", "hazard_zone", "erase_zone"] else 0
		draw_rect(Rect2(origin + Vector2(hover - Vector2i.ONE * radius) * step, Vector2.ONE * step * (radius * 2 + 1)), Color(1, 1, 1, 0.7), false, 1)

func hit(pos: Vector2) -> int:
	if screen_cell(map.player_start).distance_to(pos) <= 10: return -2
	for i in range(map.enemies.size() - 1, -1, -1):
		if screen_cell(map.enemies[i].cell).distance_to(pos) <= maxf(10, scale_at()): return i
	for i in range(pickup_markers.size() - 1, -1, -1):
		if screen_cell(pickup_markers[i].cell).distance_to(pos) <= 10: return -100 - i
	for i in range(objective_markers.size() - 1, -1, -1):
		if screen_cell(objective_markers[i].cell).distance_to(pos) <= 10: return -1000 - i
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
		if erasing and tool not in ["open", "rock", "shield_zone", "hazard_zone", "erase_zone"]:
			selected = hit(event.position)
			remove_selected()
		elif tool == "select": selected = hit(event.position)
		elif tool == "salvage":
			author_pickups()
			map.pickups.append({"cell": cell, "rare": false})
			rebuild_preview()
			selected = -100 - (map.pickups.size() - 1)
		elif tool == "objective" and encounter in ["beacon", "cargo", "breach", "rival"]:
			author_objectives()
			var markers: Array = map.encounters[encounter].objectives
			if encounter != "beacon": markers.clear()
			markers.append({"cell": cell, "radius": {"beacon": 5, "cargo": 0, "breach": 4, "rival": 3}[encounter]})
			rebuild_preview()
			selected = -1000 - (markers.size() - 1)
		elif tool == "enemy":
			map.enemies.append({"kind": enemy_kind, "cell": cell, "axis": enemy_axis})
			map.override_enemies = true
			selected = map.enemies.size() - 1
		elif tool == "start": selected = -2
		elif tool == "objective": selected = -1
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
	if tool in ["shield_zone", "hazard_zone", "erase_zone"]:
		if map.field_zones.is_empty(): map.field_zones.resize(map.grid_size.x * map.grid_size.y)
		var mask: PackedByteArray = map.arena().mask
		var radius := brush_size / 2
		for y in range(cell.y - radius, cell.y + radius + 1):
			for x in range(cell.x - radius, cell.x + radius + 1):
				var c := Vector2i(x, y)
				if not MapDefinition.EDITABLE.has_point(c): continue
				var i := y * map.grid_size.x + x
				if erasing or tool == "erase_zone": map.field_zones[i] = 0
				elif mask[i] != 0: map.field_zones[i] = 1 if tool == "shield_zone" else 2
		rebuild_zones()
	elif tool in ["rock", "open"]:
		var radius := brush_size / 2
		var solid := (tool == "rock") != erasing
		for y in range(cell.y - radius, cell.y + radius + 1):
			for x in range(cell.x - radius, cell.x + radius + 1):
				var c := Vector2i(x, y)
				if not MapDefinition.EDITABLE.has_point(c): continue
				map.rock[y * map.grid_size.x + x] = 1 if solid else 0
				if solid and not map.field_zones.is_empty(): map.field_zones[y * map.grid_size.x + x] = 0
				painted[c] = solid
		map.override_terrain = true
	elif not erasing:
		move_selected(cell)

func finish_stroke() -> void:
	if not dragging: return
	dragging = false
	rebuild()
	stroke_finished.emit()
