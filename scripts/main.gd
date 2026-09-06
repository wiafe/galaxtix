extends Node2D
## Game entry: a ScopeDisplay (the tube) plus the Game (the run). Also hosts the smoke-test
## autopilot: `godot --path . -- --autotest --nosave --shots=<dir>` and the other --autotest=
## modes below. Debug keys: F9 unlock ships, F10 currencies, F11 galaxies.

var display: ScopeDisplay
var fill: Sprite2D
var game: Game

var autotest := false
var auto_mode := "play"
var shots_dir := ""
var shot_times := [1.5, 4.0, 7.5, 11.0]
var shot_i := 0
var t := 0.0
var script_ms := 0.0


func _ready() -> void:
	_setup_input()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--autotest":
			autotest = true
		elif a == "--autotest=dock":
			autotest = true
			auto_mode = "dock"
			shot_times = [1.5, 3.0]
		elif a == "--autotest=intro":
			autotest = true
			auto_mode = "intro"
			shot_times = [3.7, 4.2, 4.8, 5.5]   # after the transit
		elif a == "--autotest=transit":
			autotest = true
			auto_mode = "transit"
			shot_times = [0.5, 1.5, 2.6, 3.0]
		elif a == "--autotest=sector":
			autotest = true
			auto_mode = "sector"
			shot_times = [12.4, 13.2, 13.9, 14.6]
		elif a == "--autotest=outro":
			autotest = true
			auto_mode = "outro"
			shot_times = [7.1, 7.5, 8.8, 11.2]
		elif a == "--autotest=title":
			autotest = true
			auto_mode = "title"
			shot_times = [0.25, 0.6, 1.6, 3.2]
		elif a == "--autotest=pattern":
			autotest = true
			auto_mode = "pattern"
		elif a == "--autotest=royale":
			autotest = true
			auto_mode = "royale"
			shot_times = [4.0, 9.6, 12.5, 16.6]   # roster mid-round, buzzer beat, mid reveal, last slot + card
		elif a.begins_with("--autotest=boss"):
			autotest = true
			auto_mode = a.substr(11)   # boss, boss:belt, boss:deep
			shot_times = [3.0, 6.0, 9.0, 12.0]
		elif a == "--autotest=hazards":
			autotest = true
			auto_mode = "hazards"
			shot_times = [3.5, 6.0, 9.0, 12.0]
		elif a in ["--autotest=bulwark", "--autotest=leaper", "--autotest=lancer", "--autotest=sapper"]:
			autotest = true
			auto_mode = a.substr(11)
			shot_times = [5.0, 7.5, 9.5, 12.0]
			if auto_mode == "lancer":
				shot_times = [6.9, 7.3, 9.5, 12.0]   # catch the tether right after it fires
			if auto_mode == "bulwark":
				shot_times = [10.2, 13.2, 15.7, 21.7]   # braced, then two seals cooking, then the first completes
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)

	display = ScopeDisplay.new()
	add_child(display)
	if args.has("--nocrt"):
		# diagnostic: no curvature / aberration / scanlines, so the scene texture is sampled 1:1
		display.settings.crt_curve = 0.0
		display.settings.aberration = 0.0
		display.settings.scan_depth = 0.0
		display.apply_settings()
	if args.has("--rawview"):
		# diagnostic: show the scene viewport texture directly, bypassing trails and the CRT pass
		var tr := TextureRect.new()
		tr.texture = display.scene_vp.get_texture()
		tr.size = Vector2(1600, 900)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	fill = Sprite2D.new()
	display.add_scene_child(fill)

	game = Game.new()
	add_child(game)
	game.setup(display.lines, display.sparks, fill)

	if autotest:
		seed(1337)   # repeatable Anomaly / Sparx behaviour for screenshots
		game.transit_skip = not (auto_mode in ["intro", "outro", "transit", "sector"])
		if auto_mode == "bulwark":
			seed(4242)   # a seed where the Anomaly starts away from the top edge
	if autotest and auto_mode == "dock":
		game.go_dock()
	if autotest and auto_mode == "royale":
		game.start_battle_royale()
		game.battle.start(1337)
		game.battle.phase = "playing"
		game.battle.remaining = 8.0   # short round so the buzzer reveal fits in the shot window
	if autotest and (auto_mode in ["intro", "outro", "transit", "sector"]):
		game.autopilot = true   # no inputs, just watch the sequences
		game.start_run()
	if autotest and auto_mode.begins_with("boss"):
		# jump straight into a galaxy's boss sector (in memory only)
		var gid := "helix"
		if auto_mode.contains(":"):
			gid = auto_mode.split(":")[1]
		Save.data.galaxy_best = {"helix": 7, "belt": 7, "deep": 7}
		Save.data.galaxy = gid
		Save.data.start_sector = Galaxies.LENGTH
		game.autopilot = true
		game.auto_script = [
			[3.0, Vector2i.ZERO, false, false],
			[1.0, Vector2i.RIGHT, false, false],
			[2.6, Vector2i.DOWN, true, false],
			[1.6, Vector2i.RIGHT, true, false],
			[3.2, Vector2i.UP, true, false],
			[6.0, Vector2i.ZERO, false, false],
		]
		game.start_run()
	if autotest and auto_mode == "hazards":
		# in-memory only (--nosave): pretend the first two galaxies are secured, jump into the third
		Save.data.galaxy_best = {"helix": 5, "belt": 5}
		Save.data.galaxy = "deep"
		Save.data.start_sector = 2
		game.autopilot = true
		game.auto_script = [
			[3.0, Vector2i.ZERO, false, false],
			[1.0, Vector2i.RIGHT, false, false],
			[2.6, Vector2i.DOWN, true, false],
			[1.6, Vector2i.RIGHT, true, false],
			[3.2, Vector2i.UP, true, false],
			[6.0, Vector2i.ZERO, false, false],
		]
		game.start_run()
	if autotest and auto_mode in ["bulwark", "leaper", "lancer", "sapper"]:
		Save.data.ships = {auto_mode: true}
		Save.data.ship = auto_mode
		Save.data.isotope = 3
		if auto_mode == "leaper":
			Save.data.ship_upgrades = {"leaper:tide": 1}
			shot_times = [7.5, 8.6, 12.5, 16.5]   # aiming, wall growing, wall up, later
		if auto_mode == "lancer":
			Save.data.ship_upgrades = {"lancer:bend": 1, "lancer:lattice": 1}
			shot_times = [7.3, 8.0, 9.0, 11.0]   # lance, bend, ride, land
		if auto_mode == "sapper":
			Save.data.ship_upgrades = {"sapper:shock": 1, "sapper:insul": 1}
			shot_times = [10.0, 11.6, 15.0, 16.8]   # roaming, charging, the blow, second disc
		game.autopilot = true
		# step: [duration, dir, draw, slow, special]
		var scripts := {
			"bulwark": [
				[3.0, Vector2i.ZERO, false, false, false],
				[1.0, Vector2i.RIGHT, false, false, false],
				[2.0, Vector2i.DOWN, true, false, false],
				[1.0, Vector2i.RIGHT, true, false, false],
				[1.2, Vector2i.ZERO, false, false, false],       # let go: BRACE, hardening sprints up to the ship
				[0.5, Vector2i.RIGHT, true, false, false],
				[2.4, Vector2i.UP, true, false, false],
				[0.8, Vector2i.RIGHT, false, false, false],
				[1.5, Vector2i.DOWN, true, false, false],
				[1.2, Vector2i.RIGHT, true, false, false],
				[1.9, Vector2i.UP, true, false, false],
				[6.0, Vector2i.ZERO, false, false, false],
			],
			"leaper": [
				[3.0, Vector2i.ZERO, false, false, false],
				[1.0, Vector2i.RIGHT, false, false, false],
				[0.1, Vector2i.DOWN, false, false, false],       # face the void
				[1.2, Vector2i.ZERO, true, false, false],        # hold Space: the line builds downward
				[0.1, Vector2i.ZERO, false, false, false],       # release: leap, island
				[0.6, Vector2i.RIGHT, false, false, false],      # face right on the island
				[1.0, Vector2i.ZERO, true, false, false],        # second line
				[0.1, Vector2i.ZERO, false, false, false],
				[0.6, Vector2i.DOWN, false, false, false],
				[3.0, Vector2i.ZERO, true, false, false],        # third line runs to its max or to land
				[0.1, Vector2i.ZERO, false, false, false],
				[3.0, Vector2i.ZERO, false, false, false],
			],
			"lancer": [
				[3.0, Vector2i.ZERO, false, false, false],
				[1.0, Vector2i.RIGHT, false, false, false],
				[0.1, Vector2i.DOWN, false, false, false],
				[0.2, Vector2i.ZERO, true, false, false],       # Space: fire the lance downward
				[0.9, Vector2i.ZERO, false, false, false],     # ride
				[0.2, Vector2i.RIGHT, true, false, false],      # BEND: steer right + Space mid-ride
				[2.5, Vector2i.ZERO, false, false, false],     # ride the bent tether to the coast
				[3.0, Vector2i.ZERO, false, false, false],
			],
			"sapper": [
				[3.0, Vector2i.ZERO, false, false, false],
				[1.0, Vector2i.RIGHT, false, false, false],
				[1.5, Vector2i.DOWN, false, false, false],       # roam out into the void, no line
				[3.2, Vector2i.ZERO, true, false, false],        # hold Space: the disc grows
				[0.1, Vector2i.ZERO, false, false, false],       # release: blow
				[1.6, Vector2i.DOWN, false, false, false],       # walk on, out of the new land
				[3.2, Vector2i.ZERO, true, false, false],        # charge again
				[0.1, Vector2i.ZERO, false, false, false],
				[3.0, Vector2i.ZERO, false, false, false],
			],
		}
		game.auto_script = scripts[auto_mode]
		game.start_run()
	if autotest and auto_mode == "play":
		game.autopilot = true
		game.auto_script = [
			[1.0, Vector2i.RIGHT, false, false],
			[2.6, Vector2i.DOWN, true, false],
			[1.6, Vector2i.RIGHT, true, false],
			[3.2, Vector2i.UP, true, false],
			[1.2, Vector2i.LEFT, false, false],
			[2.2, Vector2i.DOWN, true, true],
			[1.5, Vector2i.LEFT, true, true],
			[3.0, Vector2i.UP, true, true],
			[2.0, Vector2i.ZERO, false, false],
		]
		game.start_run()


func _setup_input() -> void:
	var map := {
		"move_left": [KEY_LEFT, KEY_A],
		"move_right": [KEY_RIGHT, KEY_D],
		"move_up": [KEY_UP, KEY_W],
		"move_down": [KEY_DOWN, KEY_S],
		"draw": [KEY_SPACE],
		"slow": [KEY_SHIFT],
		"confirm": [KEY_ENTER, KEY_KP_ENTER],
		"launch": [KEY_SPACE],
		"abort": [KEY_ESCAPE],
		"special": [KEY_E, KEY_CTRL],
		"tab": [KEY_TAB],
		"br_harden": [KEY_Q],
		"br_overdrive": [KEY_E],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	t += dt
	var t0 := Time.get_ticks_usec()
	display.tick(dt)
	if auto_mode == "pattern":
		_draw_pattern()
		if t > 1.0 and shot_i == 0:
			shot_i = 1
			_take_shot(1)
		if t > 1.6:
			get_tree().quit()
		return
	game.update(dt)
	display.begin_draw(game.shake_off)
	game.draw()
	display.end_draw()
	script_ms = (Time.get_ticks_usec() - t0) / 1000.0

	if autotest:
		if auto_mode == "sector" and t > 6.5 and game.state == Game.State.PLAYING:
			game.level_clear()   # force a clear to watch the sector-to-sector jump
		if auto_mode == "outro" and t > 6.5 and game.state == Game.State.PLAYING:
			game.end_run()
		if shot_i < shot_times.size() and t >= shot_times[shot_i]:
			shot_i += 1
			_take_shot(shot_i)
		if t > shot_times[-1] + 0.6:
			get_tree().quit()


## Renderer diagnostic (--autotest=pattern): lone segments in 8 directions, polylines, ticks of
## rising thickness, glyph-sized short strokes, and a dense block of tiny segments.
func _draw_pattern() -> void:
	display.begin_draw()
	var L := display.lines
	var c := Vector2(400, 450)
	for k in 8:
		var a := k * TAU / 8.0
		var d := Vector2(cos(a), sin(a))
		L.seg(c + d * 40.0, c + d * 180.0, Palette.CYAN, 0.0, 0.0, 1.5)
		VectorFont.draw(L, str(k), c + d * 205.0, 14, Palette.YELLOW, 0.0, 0.0, 1)
	var c2 := Vector2(1000, 450)
	for k in 8:
		var a := k * TAU / 8.0
		var d := Vector2(cos(a), sin(a))
		L.polyline(PackedVector2Array([c2 + d * 40.0, c2 + d * 110.0, c2 + d * 180.0]), false, Palette.GREEN, 0.0, 0.0, 1.5)
	for k in 12:
		L.seg(Vector2(300 + k * 60, 780), Vector2(300 + k * 60, 820), Palette.WHITE, 0.0, 0.0, 1.0 + k * 0.25)
		L.seg(Vector2(300 + k * 60, 100), Vector2(340 + k * 60, 100), Palette.WHITE, 0.0, 0.0, 1.0 + k * 0.25)
	for k in 8:
		var ln := 2.0 + k * 2.0
		L.seg(Vector2(1100 + k * 40, 120), Vector2(1100 + k * 40 + ln, 120), Palette.WHITE, 0.0, 0.0, 1.0)
		L.seg(Vector2(1100 + k * 40, 150), Vector2(1100 + k * 40, 150 + ln), Palette.WHITE, 0.0, 0.0, 1.0)
	for k in 3000:
		var px := 1100.0 + (k % 100) * 4.0
		var py := 700.0 + (k / 100) * 4.0
		L.seg(Vector2(px, py), Vector2(px + 2.0, py), Palette.ORANGE, 0.0, 0.0, 0.6)
	display.end_draw()


## Debug keys: F9 unlocks every ship, F10 grants a million of each currency, F11 unlocks all galaxies.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F9:
			for s in Ships.LIST:
				Save.data.ships[s.id] = true
			game.set_msg("DEBUG: ALL SHIPS UNLOCKED", 1.5)
		KEY_F10:
			Save.add_flux(1000000.0)
			Save.data.isotope = int(Save.data.isotope) + 1000000
			game.set_msg("DEBUG: +1M FLUX  +1M ISOTOPE", 1.5)
		KEY_F11:
			for g in Galaxies.LIST:
				Save.data.galaxy_best[g.id] = maxi(Galaxies.best(g.id), Galaxies.UNLOCK_AT)
			game.set_msg("DEBUG: ALL GALAXIES UNLOCKED", 1.5)
		_:
			return
	Save.save_data()


func _take_shot(i: int) -> void:
	if shots_dir == "":
		return
	await display.screenshot(shots_dir + "/shot%d.png" % i)
	print("shot %d saved, segs=%d state=%s claimed=%.2f fps=%d script_ms=%.2f" % [i, display.lines.count,
		game.state, game.claimed_frac(), Engine.get_frames_per_second(), script_ms])
