extends Node2D
## FX LAB: the vector display with demo content and live sliders for every FxSettings value.
## Open scenes/fx_lab.tscn and press F6, or run:  godot --path . res://scenes/fx_lab.tscn
## Keys: TAB hide/show panel, H hit spike, E explosion, S save as game defaults, R reset defaults.

const PARAMS := [
	["BEAM", "Beam width px", "beam", 0.5, 6.0, 0.05],
	["BEAM", "Wobble base px", "wobble", 0.0, 4.0, 0.01],
	["BEAM", "Slop base", "slop", 0.0, 1.0, 0.01],
	["BEAM", "LFO speed", "lfo_speed", 0.0, 3.0, 0.01],
	["BEAM", "Element wobble x", "element_wobble", 0.0, 2.0, 0.01],
	["BEAM", "Element slop x", "element_slop", 0.0, 2.0, 0.01],
	["BEAM", "Hit spike x", "spike_mult", 0.0, 2.0, 0.01],
	["BEAM", "Screen shake x", "shake_mult", 0.0, 2.0, 0.01],
	["GLOW", "Glow intensity", "glow_intensity", 0.0, 3.0, 0.01],
	["GLOW", "Glow strength", "glow_strength", 0.0, 2.0, 0.01],
	["GLOW", "Glow threshold", "glow_threshold", 0.0, 2.0, 0.01],
	["GLOW", "Glow bloom", "glow_bloom", 0.0, 1.0, 0.01],
	["TRAILS", "Persistence", "trail_feedback", 0.0, 0.98, 0.005],
	["TRAILS", "Trail blur px", "trail_blur", 0.0, 4.0, 0.05],
	["TRAILS", "Live brightness", "trail_dry", 0.0, 2.0, 0.01],
	["CRT", "Curvature", "crt_curve", 0.0, 0.3, 0.005],
	["CRT", "Scanline depth", "scan_depth", 0.0, 1.0, 0.01],
	["CRT", "Scanline count", "scan_lines", 100.0, 900.0, 1.0],
	["CRT", "Vignette", "vignette", 0.0, 1.0, 0.01],
	["CRT", "Aberration px", "aberration", 0.0, 4.0, 0.05],
	["CRT", "Grain", "grain", 0.0, 0.2, 0.001],
	["TYPE", "Tracking", "font_tracking", 0.7, 1.5, 0.01],
	["GRADE", "Contrast", "contrast", 0.5, 2.0, 0.01],
	["GRADE", "Gamma", "gamma", 0.5, 2.5, 0.01],
	["GRADE", "Saturation", "saturation", 0.0, 2.0, 0.01],
	["GRADE", "Warmth", "warmth", -0.5, 0.5, 0.01],
]
const QIX_COLORS := [Palette.MAGENTA, Palette.PURPLE, Palette.BLUE, Palette.CYAN,
	Palette.GREEN, Palette.YELLOW, Palette.ORANGE, Palette.RED]

var display: ScopeDisplay
var settings: FxSettings
var panel: PanelContainer
var sliders := {}
var value_labels := {}
var glow_check: CheckButton
var font_pick: OptionButton
var title_pick: OptionButton
var status: Label
const FONT_NAMES := ["futural", "futuram", "rowmans", "rowmand", "rowmant", "timesr", "timesi", "scripts", "cursive", "gothiceng"]
var t := 0.0
var frame := 0
var shake := 0.0
var boom_t := 1.0

# demo actors
var ast_pos := Vector2(300, 600)
var ast_vel := Vector2(26, 18)
var ast_rot := 0.0
var ast_verts := PackedFloat32Array()
var ship_pos := Vector2(500, 300)
var ship_heading := 0.7
var liss_phase := 0.0
var fill_sprite: Sprite2D

var autotest := false
var shots_dir := ""
var shot_done := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autotest":
			autotest = true
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)
	settings = FxSettings.load_or_default()
	display = ScopeDisplay.new(settings)
	add_child(display)

	# a sample of the claimed-territory fill so its brightness can be judged too
	var img := Image.create(24, 20, false, Image.FORMAT_RGBA8)
	for y in 20:
		for x in 24:
			var v := 1.0 if ((x + y) & 1) == 0 else 0.55
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	fill_sprite = Sprite2D.new()
	fill_sprite.texture = ImageTexture.create_from_image(img)
	fill_sprite.centered = false
	fill_sprite.position = Vector2(760, 640)
	fill_sprite.scale = Vector2(8, 8)
	fill_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fill_sprite.material = m
	fill_sprite.modulate = Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.16)
	display.add_scene_child(fill_sprite)

	for i in 13:
		ast_verts.append(0.7 + randf() * 0.45)
	_build_panel()
	if autotest:
		seed(7)


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(1170, 16)
	panel.custom_minimum_size = Vector2(414, 868)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(414, 868)
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(394, 0)
	vb.add_theme_constant_override("separation", 2)
	scroll.add_child(vb)

	var title := Label.new()
	title.text = "FX LAB   TAB hide   H spike   E boom   ESC back"
	vb.add_child(title)

	var group := ""
	for prm in PARAMS:
		if prm[0] != group:
			group = prm[0]
			var gl := Label.new()
			gl.text = group
			gl.modulate = Color(0.55, 0.85, 1.0)
			vb.add_child(gl)
		var row := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = prm[1]
		name_l.custom_minimum_size = Vector2(150, 0)
		row.add_child(name_l)
		var sl := HSlider.new()
		sl.min_value = prm[3]
		sl.max_value = prm[4]
		sl.step = prm[5]
		sl.value = settings.get(prm[2])
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.custom_minimum_size = Vector2(160, 0)
		sl.value_changed.connect(_on_slider.bind(prm[2]))
		row.add_child(sl)
		var vl := Label.new()
		vl.text = _fmt(prm[2], settings.get(prm[2]))
		vl.custom_minimum_size = Vector2(56, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		vb.add_child(row)
		sliders[prm[2]] = sl
		value_labels[prm[2]] = vl

	glow_check = CheckButton.new()
	glow_check.text = "Glow enabled"
	glow_check.button_pressed = settings.glow_enabled
	glow_check.toggled.connect(func(on: bool) -> void:
		settings.glow_enabled = on
		display.apply_settings())
	vb.add_child(glow_check)

	var frow := HBoxContainer.new()
	var fl := Label.new()
	fl.text = "Typeface"
	fl.custom_minimum_size = Vector2(150, 0)
	frow.add_child(fl)
	font_pick = OptionButton.new()
	font_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for f in FONT_NAMES:
		font_pick.add_item(f)
	font_pick.selected = maxi(0, FONT_NAMES.find(settings.font))
	font_pick.item_selected.connect(func(i: int) -> void:
		settings.font = FONT_NAMES[i]
		display.apply_settings())
	frow.add_child(font_pick)
	vb.add_child(frow)

	var trow := HBoxContainer.new()
	var tl := Label.new()
	tl.text = "Title face"
	tl.custom_minimum_size = Vector2(150, 0)
	trow.add_child(tl)
	title_pick = OptionButton.new()
	title_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for f in FONT_NAMES:
		title_pick.add_item(f)
	title_pick.selected = maxi(0, FONT_NAMES.find(settings.title_font))
	title_pick.item_selected.connect(func(i: int) -> void:
		settings.title_font = FONT_NAMES[i]
		display.apply_settings())
	trow.add_child(title_pick)
	vb.add_child(trow)

	var buttons := HBoxContainer.new()
	var save_b := Button.new()
	save_b.text = "Save as game defaults (S)"
	save_b.pressed.connect(_save)
	buttons.add_child(save_b)
	var reset_b := Button.new()
	reset_b.text = "Reset (R)"
	reset_b.pressed.connect(_reset)
	buttons.add_child(reset_b)
	vb.add_child(buttons)

	status = Label.new()
	status.text = "Editing " + ("res://fx_settings.tres" if ResourceLoader.exists(FxSettings.PATH) else "built-in defaults (unsaved)")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(380, 0)
	vb.add_child(status)
	add_child(panel)


func _fmt(prop: String, v: float) -> String:
	return "%d" % int(v) if prop == "scan_lines" else "%.2f" % v


func _on_slider(v: float, prop: String) -> void:
	settings.set(prop, v)
	value_labels[prop].text = _fmt(prop, v)
	display.apply_settings()


func _sync_sliders() -> void:
	for prop in sliders:
		sliders[prop].set_value_no_signal(settings.get(prop))
		value_labels[prop].text = _fmt(prop, settings.get(prop))
	glow_check.set_pressed_no_signal(settings.glow_enabled)
	font_pick.selected = maxi(0, FONT_NAMES.find(settings.font))
	title_pick.selected = maxi(0, FONT_NAMES.find(settings.title_font))


func _save() -> void:
	var err := settings.save()
	status.text = "Saved to res://fx_settings.tres, the game now uses these values." if err == OK else "Save failed: error %d" % err


func _reset() -> void:
	settings.copy_from(FxSettings.new())
	_sync_sliders()
	display.apply_settings()
	status.text = "Reset to built-in defaults (not saved yet)."


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				panel.visible = not panel.visible
			KEY_H:
				display.lines.spike(6.0, 0.6)
				shake = 0.8
			KEY_E:
				_explode(Vector2(randf_range(150, 1000), randf_range(120, 780)))
			KEY_S:
				_save()
			KEY_R:
				_reset()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/main.tscn")


func _explode(pos: Vector2) -> void:
	var sp := display.sparks
	sp.ripple(pos, 4.0, 420.0, 0.7, Palette.FULLBRIGHT)
	sp.ripple(pos, 2.0, 300.0, 0.9, Palette.WHITE)
	sp.burst(pos, 120, 420.0, 0.8, 0.7, Palette.FULLBRIGHT, 0.03, Vector2.ZERO, 1.2)
	sp.burst(pos, 90, 220.0, 2.0, 1.2, Palette.ORANGE, 0.08, Vector2.ZERO, 1.0)
	sp.burst(pos, 60, 90.0, 8.0, 2.4, Palette.RED, 0.2, Vector2.ZERO, 0.4)
	display.lines.spike(5.0, 0.7)
	shake = 1.0


func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	t += dt
	frame += 1
	shake = maxf(0.0, shake - dt * 1.6)
	boom_t -= dt
	if boom_t <= 0.0:
		boom_t = 3.5
		_explode(Vector2(randf_range(150, 1000), randf_range(120, 780)))
	display.tick(dt)
	display.sparks.update(dt)
	var lines := display.lines
	var shake_off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * shake * 10.0
	display.begin_draw(shake_off)

	# frame + a sample coast rectangle around the fill sample
	lines.rect(Rect2(40, 34, 832, 832), Palette.DIM, 0.4, 0.1, 0.8)
	lines.rect(Rect2(760, 640, 192, 160), Palette.CYAN, 0.7, 0.15, 1.0)

	# asteroid: closed lumpy polygon, spinning + drifting (bounces inside the left area)
	ast_pos += ast_vel * dt
	ast_rot += dt * 0.6
	if ast_pos.x < 150 or ast_pos.x > 1000:
		ast_vel.x = -ast_vel.x
	if ast_pos.y < 150 or ast_pos.y > 780:
		ast_vel.y = -ast_vel.y
	var pts := PackedVector2Array()
	for i in ast_verts.size():
		var a := ast_rot + TAU * i / ast_verts.size()
		pts.append(ast_pos + Vector2(cos(a), sin(a)) * 70.0 * ast_verts[i])
	lines.polyline(pts, true, Palette.CYAN, 1.0, 0.3)

	# Lissajous: self-overlap shows additive bloom
	liss_phase += dt * 0.5
	var lp := PackedVector2Array()
	for i in 241:
		var u := float(i) / 240.0 * TAU
		lp.append(Vector2(560 + sin(3.0 * u + liss_phase) * 250.0, 470 + sin(2.0 * u) * 250.0))
	lines.polyline(lp, false, Palette.GREEN, 0.8, 0.3)

	# roaming ship + exhaust sparks
	ship_heading += (randf() - 0.5) * 1.6 * dt
	var d := Vector2(cos(ship_heading), sin(ship_heading))
	ship_pos += d * 130.0 * dt
	if ship_pos.x < 80:
		ship_pos.x = 1080
	if ship_pos.x > 1080:
		ship_pos.x = 80
	if ship_pos.y < 60:
		ship_pos.y = 840
	if ship_pos.y > 840:
		ship_pos.y = 60
	var n := Vector2(-d.y, d.x)
	lines.polyline(PackedVector2Array([ship_pos + d * 16, ship_pos - d * 16 + n * 8, ship_pos - d * 16 - n * 8]), true, Palette.MAGENTA, 1.0, 0.4)
	for k in 3:
		var spread := (randf() - 0.5)
		var ex := (-d).rotated(spread)
		display.sparks.emit(ship_pos - d * 16, ex * randf_range(60, 200) + d * 26, randf_range(0.5, 1.0), Palette.ORANGE, 0.6)

	# an Anomaly helix and a Sparx, like in the game
	for i in 12:
		var ang := t * 1.5 + i * 0.22
		var c := Vector2(930, 250) + Vector2(i * 2.0, i * 3.0)
		var e := Vector2(cos(ang), sin(ang)) * 45.0
		var col: Color = QIX_COLORS[(frame / 3 + i) % 8]
		col.a = 0.2 + 0.6 * (1.0 - float(i) / 12.0)
		lines.seg(c - e, c + e, col, 2.0, 0.5, 1.2 if i == 0 else 1.0)
	var sx := Vector2(1000, 560)
	for k in 2:
		var a: float = t * 9.0 + k * PI * 0.5
		var dd := Vector2(cos(a), sin(a)) * 11.0
		lines.seg(sx - dd, sx + dd, Palette.RED if (frame / 4) % 2 == 0 else Palette.ORANGE, 2.5, 0.5, 1.3)

	# text at the sizes the game uses
	VectorFont.draw(lines, "GALAXTIX", Vector2(70, 60), 72, Palette.CYAN, 2.2, 0.5, 0, 1.4, VectorFont.display)
	VectorFont.draw(lines, "SECTOR 01   CLAIMED 42%   FLUX 1234", Vector2(70, 160), 18, Palette.WHITE, 0.6, 0.2)
	VectorFont.draw(lines, "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG 0123456789", Vector2(70, 196), 11, Palette.DIM, 0.3, 0.1)
	VectorFont.draw(lines, "H = HIT SPIKE   E = EXPLOSION   TAB = HIDE PANEL", Vector2(70, 222), 13, Palette.YELLOW, 1.5, 0.5)

	display.sparks.draw(lines)
	display.end_draw()

	if autotest and not shot_done and t > 2.0:
		shot_done = true
		_shot()


func _shot() -> void:
	if shots_dir != "":
		await display.screenshot(shots_dir + "/lab.png")
	print("lab shot saved, segs=%d" % display.lines.count)
	get_tree().quit()
