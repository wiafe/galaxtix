@tool
extends VBoxContainer
signal play_requested(map: MapDefinition, depth: int, encounter: String, ship: String)
signal saved
const Canvas = preload("res://addons/roguelite_maps/map_canvas.gd")
const Acts = preload("res://scripts/roguelite_acts.gd")
const Encounters = preload("res://scripts/map_encounters.gd")
var canvas: Control
var picker: ItemList
var act_picker: OptionButton
var map_heading: Label
var visible_maps: Array[Dictionary] = []
var last_map_by_act := {}
var status: Label
var detail: Label
var custom_enemies: CheckBox
var objective_button: Button
var custom_pickups: CheckBox
var goal_input: SpinBox
var seconds_input: SpinBox
var runs_input: SpinBox
var radius_input: SpinBox
var encounter_help: Label
var x_input: SpinBox
var y_input: SpinBox
var axis_input: OptionButton
var enemy_input: OptionButton
var enemy_help: Label
var depth_input: SpinBox
var encounter_input: OptionButton
var ship_input: OptionButton
var save_button: Button
var play_button: Button
var drafts := {}
var dirty := {}
var histories := {}
var futures := {}
var current_id := ""
var before: MapDefinition
var refreshing := false

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	var heading := Label.new()
	heading.text = "ROGUELITE MAPS"
	heading.add_theme_font_size_override("font_size", 20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(heading)
	add_button(toolbar, "Undo", undo)
	add_button(toolbar, "Redo", redo)
	add_button(toolbar, "Fit", func(): canvas.fit())
	save_button = add_button(toolbar, "Save map", save_current)
	play_button = add_button(toolbar, "Playtest", playtest)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 210
	body.add_child(left)
	add_label(left, "ACT")
	act_picker = OptionButton.new()
	for act in Acts.ACTS.size():
		act_picker.add_item("Act %d / %s" % [act + 1, String(Acts.ACTS[act].name).capitalize()], act + 1)
	act_picker.add_item("Original / Arcade", 0)
	left.add_child(act_picker)
	act_picker.item_selected.connect(func(index: int): select_act(act_picker.get_item_id(index)))
	add_label(left, "ENCOUNTER PREVIEW")
	encounter_input = OptionButton.new()
	for kind in preload("res://scripts/roguelite_sectors.gd").KINDS: encounter_input.add_item(kind.capitalize())
	left.add_child(encounter_input)
	encounter_input.item_selected.connect(func(_i): update_preview())
	add_label(left, "MAPS")
	picker = ItemList.new()
	picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(picker)
	picker.item_selected.connect(func(index: int): open_map(visible_maps[index].id))
	add_label(left, "Choose a map or boss arena.\nEdits stay with that map.")
	add_button(left, "Restore built-in map", restore_default)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(middle)
	map_heading = add_label(middle, "")
	map_heading.add_theme_font_size_override("font_size", 18)
	var tools_row := HFlowContainer.new()
	middle.add_child(tools_row)
	var group := ButtonGroup.new()
	for entry in [["Select / move", "select"], ["Open space", "open"], ["Rock", "rock"], ["Player", "start"], ["Enemy", "enemy"], ["Salvage", "salvage"], ["Objective", "objective"], ["Shield zone", "shield_zone"], ["Hazard zone", "hazard_zone"], ["Erase zone", "erase_zone"]]:
		var b := Button.new()
		b.text = entry[0]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = entry[1] == "select"
		b.pressed.connect(func(): canvas.tool = entry[1])
		tools_row.add_child(b)
		if entry[1] == "objective": objective_button = b
	canvas = Canvas.new()
	canvas.custom_minimum_size = Vector2(420, 320)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(canvas)
	canvas.stroke_started.connect(begin_change)
	canvas.stroke_finished.connect(finish_change)
	canvas.selection_changed.connect(refresh_inspector)
	var help := add_label(middle, "Wheel: zoom   Middle drag: pan   Right click: erase / reverse brush   Delete: remove marker")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.custom_minimum_size.x = 280
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(inspector_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(right)
	add_label(right, "ENCOUNTER RULES")
	goal_input = coordinate_input(right, "Capture %", 95)
	goal_input.min_value = 10
	goal_input.value_changed.connect(func(value): change_rule("goal", int(value)))
	seconds_input = coordinate_input(right, "Seconds", 300)
	seconds_input.min_value = 10
	seconds_input.value_changed.connect(func(value): change_rule("seconds", value))
	runs_input = coordinate_input(right, "Cargo deliveries", 20)
	runs_input.min_value = 1
	runs_input.value_changed.connect(func(value): change_rule("runs", int(value)))
	encounter_help = add_label(right, "")
	encounter_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_button(right, "Reset encounter overrides", reset_encounter)
	custom_pickups = CheckBox.new()
	custom_pickups.text = "Use authored salvage"
	right.add_child(custom_pickups)
	custom_pickups.toggled.connect(func(value):
		if refreshing: return
		begin_change()
		if value: canvas.author_pickups()
		else: canvas.map.override_pickups = false
		finish_change())
	add_label(right, "$ = salvage (1 each).\nAuto preview uses base upgrades.")
	add_label(right, "PAINT")
	var brush := SpinBox.new()
	brush.prefix = "Brush"
	brush.min_value = 1
	brush.max_value = 15
	brush.step = 2
	brush.value = 1
	right.add_child(brush)
	brush.value_changed.connect(func(value: float): canvas.brush_size = int(value))
	var zone_help := add_label(right, "Green +: protects your ship.\nRed X: 3s safe, 1s warning, 2s live.\nZones persist after capture.")
	zone_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_label(right, "NEW ENEMY")
	enemy_input = OptionButton.new()
	for kind in MapCatalog.ENEMY_KINDS: enemy_input.add_item(kind.capitalize())
	right.add_child(enemy_input)
	enemy_help = add_label(right, MapCatalog.ENEMY_HELP.anomaly)
	enemy_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enemy_input.item_selected.connect(func(i: int):
		canvas.enemy_kind = MapCatalog.ENEMY_KINDS[i]
		enemy_help.text = MapCatalog.ENEMY_HELP[canvas.enemy_kind])
	custom_enemies = CheckBox.new()
	custom_enemies.text = "Use authored enemies"
	right.add_child(custom_enemies)
	custom_enemies.toggled.connect(func(value: bool):
		if refreshing: return
		begin_change()
		canvas.map.override_enemies = value
		finish_change())
	add_label(right, "Automatic markers are examples.\nAuthored enemies use these exact\ncounts; Sparx start immediately.")
	add_label(right, "SELECTED MARKER")
	detail = add_label(right, "Select a marker to move it.")
	x_input = coordinate_input(right, "X", 159)
	y_input = coordinate_input(right, "Y", 103)
	x_input.value_changed.connect(move_marker)
	y_input.value_changed.connect(move_marker)
	radius_input = coordinate_input(right, "Radius", 10)
	radius_input.min_value = 1
	radius_input.value_changed.connect(change_radius)
	axis_input = OptionButton.new()
	axis_input.add_item("Turret: vertical")
	axis_input.add_item("Turret: horizontal")
	right.add_child(axis_input)
	axis_input.item_selected.connect(change_axis)
	add_button(right, "Delete selected marker", remove_enemy)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	add_label(right, "PLAYTEST")
	depth_input = coordinate_input(right, "Depth", Acts.LENGTH)
	depth_input.min_value = 1
	depth_input.value = 1
	depth_input.value_changed.connect(func(_value): update_preview())
	ship_input = OptionButton.new()
	for ship in ["Surveyor", "Lancer", "Bulwark"]: ship_input.add_item(ship)
	right.add_child(ship_input)
	add_label(right, "Playtests use a temporary profile.\nYour progress is preserved.")
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 48
	add_child(status)
	select_act(1)

func preview_kind() -> String:
	return encounter_input.get_item_text(encounter_input.selected).to_lower()

func update_preview() -> void:
	if refreshing or canvas == null or canvas.map == null or depth_input == null: return
	canvas.set_encounter(preview_kind(), int(depth_input.value))
	refresh()

func change_rule(key: String, value) -> void:
	if refreshing: return
	begin_change()
	var kind := preview_kind()
	if not canvas.map.encounters.has(kind): canvas.map.encounters[kind] = {}
	canvas.map.encounters[kind][key] = value
	finish_change()

func reset_encounter() -> void:
	begin_change()
	canvas.map.encounters.erase(preview_kind())
	canvas.selected = -1
	finish_change()

func change_radius(value: float) -> void:
	if refreshing or canvas.selected > -1000: return
	begin_change()
	canvas.author_objectives()
	canvas.map.encounters[preview_kind()].objectives[-canvas.selected - 1000].radius = int(value)
	finish_change()

func map_act(id: String) -> int:
	return Acts.map_act(int(id.right(2)))

func rebuild_map_picker(act: int) -> void:
	visible_maps.clear()
	picker.clear()
	for entry in MapCatalog.entries():
		if map_act(entry.id) != act: continue
		visible_maps.append(entry)
		picker.add_item(entry.title)
	act_picker.select(act_picker.get_item_index(act))

func select_act(act: int) -> void:
	canvas.finish_stroke()
	rebuild_map_picker(act)
	if visible_maps.is_empty(): return
	open_map(last_map_by_act.get(act, visible_maps[0].id))

func add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func add_label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func coordinate_input(parent: Node, prefix: String, maximum: int) -> SpinBox:
	var input := SpinBox.new()
	input.prefix = prefix
	input.max_value = maximum
	parent.add_child(input)
	return input

func open_map(id: String) -> void:
	canvas.finish_stroke()
	if not drafts.has(id):
		var map := MapCatalog.read(int(id.right(2)))
		if map == null:
			status.text = "Missing map source: " + id
			return
		drafts[id] = map.duplicate(true)
		histories[id] = []
		futures[id] = []
	current_id = id
	var act := map_act(id)
	last_map_by_act[act] = id
	if act_picker.get_selected_id() != act: rebuild_map_picker(act)
	for i in visible_maps.size():
		if visible_maps[i].id == id: picker.select(i)
	canvas.set_map(drafts[id])
	refreshing = true
	depth_input.value = Acts.map_depth(canvas.map.sector)
	var kinds: Array = preload("res://scripts/roguelite_sectors.gd").KINDS.keys()
	encounter_input.select(kinds.find("boss" if not canvas.map.boss_id.is_empty() else "survey"))
	for i in encounter_input.item_count:
		encounter_input.set_item_disabled(i, (kinds[i] != "boss") if not canvas.map.boss_id.is_empty() else kinds[i] == "boss")
	refreshing = false
	canvas.set_encounter(preview_kind(), int(depth_input.value))
	refresh()

func fingerprint(map: MapDefinition) -> int:
	return hash(canonical([map.rock, map.override_terrain, map.player_start, map.override_start, map.override_enemies, map.enemies, map.field_zones, map.act_theme, map.boss_id, map.override_pickups, map.pickups, map.encounters]))

func canonical(value):
	# ResourceSaver can reorder dictionary keys; equivalent content stays equivalent.
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var result: Array = []
		for key in keys: result.append([key, canonical(value[key])])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(canonical(item))
		return result
	return value

func begin_change() -> void:
	if canvas.map != null: before = canvas.map.duplicate(true)

func finish_change() -> void:
	if before != null and fingerprint(before) != fingerprint(canvas.map):
		histories[current_id].append(before)
		if histories[current_id].size() > 80: histories[current_id].pop_front()
		futures[current_id].clear()
		dirty[current_id] = true
	before = null
	canvas.rebuild()
	refresh()

func undo() -> void:
	if current_id.is_empty() or histories[current_id].is_empty(): return
	futures[current_id].append(canvas.map.duplicate(true))
	drafts[current_id] = histories[current_id].pop_back()
	canvas.set_map(drafts[current_id])
	dirty[current_id] = true
	refresh()

func redo() -> void:
	if current_id.is_empty() or futures[current_id].is_empty(): return
	histories[current_id].append(canvas.map.duplicate(true))
	drafts[current_id] = futures[current_id].pop_back()
	canvas.set_map(drafts[current_id])
	dirty[current_id] = true
	refresh()

func restore_default() -> void:
	begin_change()
	drafts[current_id] = load(MapCatalog.default_path(current_id)).duplicate(true)
	canvas.set_map(drafts[current_id])
	finish_change()

func refresh() -> void:
	for i in visible_maps.size():
		var entry: Dictionary = visible_maps[i]
		var boss_arena: bool = entry.sector >= Acts.FIRST_MAP and Acts.step_at(Acts.map_depth(entry.sector)) == Acts.ACT_LENGTH
		var title: String = entry.title
		if map_act(entry.id) > 0: title = "%02d / %s" % [i + 1, String(Acts.MAP_NAMES[entry.sector - Acts.FIRST_MAP]).capitalize()]
		picker.set_item_text(i, title + (" [Boss]" if boss_arena else "") + (" *" if dirty.has(entry.id) else ""))
		picker.set_item_tooltip(i, MapCatalog.path_for(entry.id))
	for i in act_picker.item_count:
		var act := act_picker.get_item_id(i)
		var modified := false
		for id: String in dirty:
			if map_act(id) == act: modified = true
		var title := "Original / Arcade" if act == 0 else "Act %d / %s" % [act, String(Acts.ACTS[act - 1].name).capitalize()]
		act_picker.set_item_text(i, title + (" *" if modified else ""))
	map_heading.text = canvas.map.title + (" / Boss arena" if not canvas.map.boss_id.is_empty() else "")
	var errors: PackedStringArray = canvas.map.problems()
	save_button.disabled = not errors.is_empty()
	play_button.disabled = not errors.is_empty()
	status.text = "\n".join(errors.slice(0, 3)) if not errors.is_empty() else ("Unsaved changes. " if dirty.has(current_id) else "Saved. ") + "Cyan = safe rail   Dark = open space   Grey = rock. " + MapCatalog.path_for(current_id)
	status.modulate = Color("ffbd85") if not errors.is_empty() else Color.WHITE
	refresh_inspector()

func refresh_inspector() -> void:
	if canvas.map == null: return
	refreshing = true
	custom_enemies.button_pressed = canvas.map.override_enemies
	custom_pickups.button_pressed = canvas.map.override_pickups
	var kind := preview_kind()
	objective_button.disabled = kind not in ["beacon", "cargo", "breach", "rival"]
	objective_button.tooltip_text = "Place a beacon, cargo start, breach or Rival home."
	if objective_button.disabled and canvas.tool == "objective": canvas.tool = "select"
	goal_input.visible = kind in ["survey", "salvage", "repair", "breach", "race"]
	seconds_input.visible = kind == "rival"
	runs_input.visible = kind == "cargo"
	goal_input.value = Encounters.goal(canvas.map, kind, int(depth_input.value))
	seconds_input.value = Encounters.seconds(canvas.map, kind)
	runs_input.value = Encounters.runs(canvas.map, kind, int(depth_input.value))
	encounter_help.text = "%d salvage / %d objectives.\nChanges apply to this encounter on this map." % [canvas.pickup_markers.size(), canvas.objective_markers.size()]
	if kind == "race": encounter_help.text += "\nRace uses matching arenas."
	if kind == "cargo": encounter_help.text += "\nMarker sets the first cargo spawn."
	if kind == "boss": encounter_help.text += "\nMove Core / Relay enemy markers."
	var selected: int = canvas.selected
	var cell := Vector2i.ZERO
	if selected == -2:
		cell = canvas.map.player_start
		detail.text = "Player start"
	elif selected <= -100:
		var marker: Dictionary = canvas.selected_record()
		cell = marker.get("cell", Vector2i.ZERO)
		detail.text = kind.capitalize() + " objective" if selected <= -1000 else "Salvage / 1"
	elif selected >= 0 and selected < canvas.map.enemies.size():
		var enemy: Dictionary = canvas.map.enemies[selected]
		cell = enemy.cell
		detail.text = String(enemy.kind).capitalize()
		detail.tooltip_text = MapCatalog.ENEMY_HELP.get(enemy.kind, "")
		axis_input.select(1 if enemy.get("axis", Vector2i.DOWN) == Vector2i.RIGHT else 0)
	else: detail.text = "Select a marker to move it."
	x_input.editable = selected != -1
	y_input.editable = selected != -1
	x_input.value = cell.x
	y_input.value = cell.y
	radius_input.visible = selected <= -1000 and kind != "cargo"
	if radius_input.visible: radius_input.value = canvas.selected_record().get("radius", 1)
	axis_input.visible = selected >= 0 and selected < canvas.map.enemies.size() and canvas.map.enemies[selected].kind == "turret"
	refreshing = false

func move_marker(_value: float) -> void:
	if refreshing or canvas.selected == -1: return
	begin_change()
	var cell := Vector2i(int(x_input.value), int(y_input.value))
	canvas.move_selected(cell)
	finish_change()

func change_axis(index: int) -> void:
	canvas.enemy_axis = Vector2i.RIGHT if index == 1 else Vector2i.DOWN
	if refreshing or canvas.selected < 0: return
	if canvas.map.enemies[canvas.selected].kind != "turret": return
	begin_change()
	canvas.map.enemies[canvas.selected].axis = canvas.enemy_axis
	canvas.map.override_enemies = true
	finish_change()

func remove_enemy() -> void:
	if canvas.selected in [-1, -2]: return
	begin_change()
	canvas.remove_selected()
	finish_change()

func save_current() -> bool:
	if canvas.map == null: return false
	canvas.finish_stroke()
	return save_map(current_id)

func save_map(id: String) -> bool:
	var map: MapDefinition = drafts[id]
	var errors := map.problems()
	if not errors.is_empty():
		status.text = map.title + ": " + "; ".join(errors)
		return false
	var path := MapCatalog.path_for(id)
	var error := ResourceSaver.save(map, path)
	if error != OK:
		status.text = "Could not save %s: %s" % [path, error_string(error)]
		return false
	# Future loads in this editor session must see the saved resource.
	ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	dirty.erase(id)
	refresh()
	saved.emit()
	return true

func save_all() -> void:
	for id: String in dirty.keys(): save_map(id)

func playtest() -> void:
	if not save_current(): return
	play_requested.emit(canvas.map, int(depth_input.value), encounter_input.get_item_text(encounter_input.selected).to_lower(), ship_input.get_item_text(ship_input.selected).to_lower())

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed() or event.is_echo(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event is InputEventKey:
		if event.ctrl_pressed and event.keycode == KEY_S: save_current()
		elif event.ctrl_pressed and event.keycode == KEY_Z:
			if event.shift_pressed: redo()
			else: undo()
		elif event.keycode == KEY_DELETE: remove_enemy()
		else: return
		get_viewport().set_input_as_handled()
