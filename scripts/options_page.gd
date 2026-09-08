extends Node
## Uses the same beam geometry, stroke fonts and CRT pipeline as the title and dock.
signal closed
signal roguelite_reset
const Preferences = preload("res://scripts/player_settings.gd")
const Progress = preload("res://scripts/roguelite_progress.gd")
const CATEGORIES := ["DISPLAY", "EFFECTS", "AUDIO", "SAVE DATA"]
const ROWS := [
	[["FULLSCREEN", "fullscreen"], ["WINDOW RESOLUTION", "resolution"], ["VSYNC", "vsync"]],
	[["BLOOM / GLOW", "glow"], ["PHOSPHOR TRAILS", "trails"], ["CRT CURVATURE", "crt"],
	["SCANLINES", "scanlines"], ["CHROMATIC ABERRATION", "aberration"], ["FILM GRAIN", "grain"],
	["VIGNETTE", "vignette"], ["SCREEN SHAKE", "shake"], ["BEAM JITTER / FLICKER", "flicker"]],
	[["MASTER VOLUME", "volume"], ["TEST SOUND", "test"]],
	[["RESPEC JUMP UPGRADES", "respec"], ["RESET JUMP SAVE", "jump_reset"], ["RESET ROGUELITE SAVE", "roguelite_reset"]],
]
var preferences = Preferences.new()
var display: ScopeDisplay
var baseline: FxSettings
var status := "CHANGES SAVE AUTOMATICALLY"
var category := 0
var selection := 0
var is_open := false
var pending_action: Callable
var confirm_title := ""
var confirm_text := ""
var confirm_selection := 0
var previous_zoom := Vector2.ONE
var sound: AudioStreamPlayer

func setup(tube: ScopeDisplay) -> void:
	display = tube
	baseline = tube.settings.duplicate()
	display.settings = baseline.duplicate()
	preferences.read_settings()
	preferences.apply_effects(display, baseline)
	preferences.apply_audio()
	preferences.apply_display()
	sound = AudioStreamPlayer.new()
	add_child(sound)
	sound.stream = preload("res://scripts/roguelite_fanfare.gd").make_cue()

func open() -> void:
	is_open = true
	previous_zoom = display.lines.zoom
	display.lines.zoom = Vector2.ONE

func close() -> void:
	pending_action = Callable()
	is_open = false
	display.lines.zoom = previous_zoom
	sound.stop()
	closed.emit()

func category_rect(index: int) -> Rect2:
	return Rect2(80, 280 + index * 76, 320, 60)

func row_rect(index: int) -> Rect2:
	return Rect2(510, 245 + index * 52, 970, 48)

func back_rect() -> Rect2:
	return Rect2(80, 756, 320, 64)

func confirm_rect(index: int) -> Rect2:
	return Rect2(570 + index * 430, 570, 350, 64)

func select_category(index: int) -> void:
	category = posmod(index, CATEGORIES.size())
	selection = 0

func _disabled(key: String) -> bool:
	return (key == "fullscreen" and OS.has_feature("web")) or (key == "resolution" and (OS.has_feature("web") or preferences.values.fullscreen))

func _change(key: String, value: Variant) -> void:
	preferences.values[key] = value
	if Preferences.EFFECTS.has(key):
		preferences.apply_effects(display, baseline)
	elif key == "volume":
		preferences.apply_audio()
	else:
		preferences.apply_display()
	status = "CHANGES SAVED" if preferences.write_settings() == OK else "COULD NOT SAVE OPTIONS. PLEASE TRY AGAIN."

func activate(direction := 1) -> void:
	var key: String = ROWS[category][selection][1]
	if _disabled(key):
		return
	match key:
		"resolution":
			_change(key, posmod(int(preferences.values[key]) + direction, Preferences.RESOLUTIONS.size()))
		"volume":
			_change(key, clampi(int(preferences.values[key]) + direction * 5, 0, 100))
		"test":
			sound.play()
		"respec":
			_confirm("REFUND ALL JUMP UPGRADES?", "DOCK AND SHIP UPGRADES WILL BE REFUNDED.\nUNLOCKED SHIPS AND RECORDS ARE KEPT.", func():
				status = "%.0f FLUX REFUNDED" % Save.respec())
		"jump_reset":
			_confirm("RESET JUMP SAVE?", "DELETE ALL JUMP CURRENCIES, UPGRADES, SHIPS AND RECORDS.\nROGUELITE AND OPTIONS ARE KEPT. THIS CANNOT BE UNDONE.", func():
				Save.reset_data()
				status = "JUMP SAVE RESET")
		"roguelite_reset":
			_confirm("RESET ROGUELITE SAVE?", "DELETE ALL ROGUELITE SALVAGE, UPGRADES, SHIPS AND RECORDS.\nJUMP AND OPTIONS ARE KEPT. THIS CANNOT BE UNDONE.", func():
				var fresh = Progress.new()
				if fresh.write_profile():
					roguelite_reset.emit()
					status = "ROGUELITE SAVE RESET"
				else:
					status = "SAVE FAILED. PLEASE TRY AGAIN.")
		_:
			_change(key, not preferences.values[key])

func _confirm(title: String, text: String, action: Callable) -> void:
	pending_action = action
	confirm_title = title
	confirm_text = text
	confirm_selection = 0 # Cancellation is always the default.

func resolve_confirmation() -> void:
	var action := pending_action
	pending_action = Callable()
	if confirm_selection == 1 and action.is_valid():
		action.call()

func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if pending_action.is_valid():
			if event.is_action_pressed("abort"):
				pending_action = Callable()
			elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right") or event.is_action_pressed("tab"):
				confirm_selection = 1 - confirm_selection
			elif event.is_action_pressed("confirm") or event.is_action_pressed("launch"):
				resolve_confirmation()
		elif event.is_action_pressed("abort"):
			close()
		elif event.is_action_pressed("tab"):
			select_category(category + (-1 if event.shift_pressed else 1))
		elif event.is_action_pressed("move_up"):
			selection = posmod(selection - 1, ROWS[category].size())
		elif event.is_action_pressed("move_down"):
			selection = posmod(selection + 1, ROWS[category].size())
		elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
			if preferences.values.has(ROWS[category][selection][1]):
				activate(-1 if event.is_action_pressed("move_left") else 1)
		elif event.is_action_pressed("confirm") or event.is_action_pressed("launch"):
			activate()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion or event is InputEventMouseButton:
		var click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
		if pending_action.is_valid():
			for index in 2:
				if confirm_rect(index).has_point(event.position):
					confirm_selection = index
					if click: resolve_confirmation()
		else:
			for index in CATEGORIES.size():
				if click and category_rect(index).has_point(event.position):
					select_category(index)
			for index in ROWS[category].size():
				if row_rect(index).has_point(event.position):
					selection = index
					if click:
						if ROWS[category][index][1] == "volume":
							_change("volume", clampi(roundi((event.position.x - 1120) / 300.0 * 20.0) * 5, 0, 100))
						else:
							activate(-1 if event.position.x < 1210 else 1)
			if click and back_rect().has_point(event.position): close()
		get_viewport().set_input_as_handled()

func _text(text: String, at: Vector2, size: float, color: Color, align := 0, title := false) -> void:
	VectorFont.draw(display.lines, text, at, size, color, 0.4, 0.1, align, 1.0, VectorFont.display if title else VectorFont.current)

func _marker(at: Vector2) -> void:
	display.lines.polyline(PackedVector2Array([at, at + Vector2(12, 10), at + Vector2(0, 20)]), false, Palette.YELLOW, 0.6, 0.2, 1.2)

func draw() -> void:
	var lines := display.lines
	lines.rect(Rect2(40, 60, 1520, 780), Palette.DIM, 0.3, 0.1, 0.8)
	lines.seg(Vector2(450, 90), Vector2(450, 810), Palette.DIM, 0.3, 0.1, 0.8)
	_text("OPTIONS", Vector2(80, 110), 48, Palette.CYAN, 0, true)
	_text("TUNE THE SIGNAL", Vector2(82, 184), 13, Palette.WHITE)
	for index in CATEGORIES.size():
		var rect := category_rect(index)
		var selected: bool = index == category
		if selected:
			_marker(rect.position + Vector2(0, 7))
			lines.seg(rect.position + Vector2(28, 48), rect.position + Vector2(292, 48), Palette.CYAN, 0.4, 0.1)
		_text(CATEGORIES[index], rect.position + Vector2(30, 3), 25, Palette.FULLBRIGHT if selected else Palette.DIM, 0, true)
	_text("TAB   CHANGE CATEGORY", Vector2(82, 684), 11, Palette.DIM)
	_text("SHIFT+TAB   PREVIOUS", Vector2(82, 706), 11, Palette.DIM)
	_text("ESC  BACK TO TITLE", back_rect().position + Vector2(0, 18), 16, Palette.CYAN)
	_text("%02d / %02d" % [category + 1, CATEGORIES.size()], Vector2(1480, 119), 12, Palette.DIM, 2)
	_text(CATEGORIES[category], Vector2(510, 112), 36, Palette.CYAN, 0, true)
	lines.seg(Vector2(510, 184), Vector2(1480, 184), Palette.DIM, 0.3, 0.1)
	if pending_action.is_valid():
		_draw_confirmation()
		return
	for index in ROWS[category].size():
		var row: Array = ROWS[category][index]
		var key: String = row[1]
		var rect := row_rect(index)
		var selected: bool = selection == index
		var disabled := _disabled(key)
		var color := Palette.DIM if disabled else (Palette.FULLBRIGHT if selected else Palette.WHITE)
		if selected:
			_marker(rect.position + Vector2(-25, 4))
			lines.seg(rect.position + Vector2(0, 40), rect.position + Vector2(rect.size.x, 40), Palette.DIM, 0.3, 0.1, 0.6)
		_text(row[0], rect.position, 19, color)
		if key == "volume":
			for tick in 21:
				var at := Vector2(1120 + tick * 15, rect.position.y + 22)
				lines.seg(at, at + Vector2(0, -15), Palette.CYAN if tick * 5 <= preferences.values.volume else Palette.DIM, 0.2, 0.1)
			_text("%d%%" % preferences.values.volume, Vector2(1480, rect.position.y), 17, Palette.YELLOW, 2)
		elif key == "resolution":
			var resolution: Vector2i = Preferences.RESOLUTIONS[preferences.values.resolution]
			_text("< %d X %d >" % [resolution.x, resolution.y], Vector2(1480, rect.position.y), 17, Palette.DIM if disabled else Palette.CYAN, 2)
		elif preferences.values.has(key):
			_text("< ON >" if preferences.values[key] else "< OFF >", Vector2(1480, rect.position.y), 17, Palette.DIM if disabled else (Palette.GREEN if preferences.values[key] else Palette.CYAN), 2)
		else:
			_text("ENTER" if selected else "--", Vector2(1480, rect.position.y), 15, Palette.YELLOW if selected else Palette.DIM, 2)
	var notes := ["WINDOW RESOLUTION APPLIES IN WINDOWED MODE.", "EFFECTS APPLY LIVE TO THIS DISPLAY.", "LEFT / RIGHT ADJUST   CLICK THE METER TO SET VOLUME.", "RESETS REQUIRE CONFIRMATION. OPTIONS ARE KEPT."]
	_text(notes[category], Vector2(510, 748), 12, Palette.CYAN)
	_text(status, Vector2(510, 782), 12, Palette.YELLOW)
	_text("UP / DOWN SELECT   LEFT / RIGHT ADJUST   ENTER ACTIVATE", Vector2(510, 858), 11, Palette.DIM)

func _draw_confirmation() -> void:
	var lines := display.lines
	lines.rect(Rect2(510, 260, 970, 420), Palette.RED, 0.3, 0.1, 1.0)
	_text("CONFIRM ACTION", Vector2(550, 292), 13, Palette.RED)
	_text(confirm_title, Vector2(550, 342), 25, Palette.YELLOW, 0, true)
	var y := 418.0
	for part in confirm_text.split("\n"):
		_text(part, Vector2(550, y), 13, Palette.WHITE)
		y += 30
	for index in 2:
		var rect := confirm_rect(index)
		lines.rect(rect, Palette.YELLOW if confirm_selection == index else Palette.DIM, 0.3, 0.1)
		_text("CANCEL" if index == 0 else "CONFIRM", rect.position + Vector2(175, 20), 20, Palette.FULLBRIGHT if confirm_selection == index else Palette.DIM, 1)
	_text("LEFT / RIGHT CHOOSE   ENTER SELECT   ESC CANCEL", Vector2(510, 748), 12, Palette.CYAN)
