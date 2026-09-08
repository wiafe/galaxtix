extends "res://scripts/game.gd"
## Shape expedition built on Jump's simulation. Only run flow, progression,
## card effects and corruption live here; controls and flood-fill remain in Game.
signal exited
const Progress = preload("res://scripts/roguelite_progress.gd")
const Cards = preload("res://scripts/roguelite_cards.gd")
var draft_capture: Array[int] = [35]
var opening_draft_pending := true
var leap_input_frame := false
var hardening_time := 0.0
var disc_braced := false
var dash_time := 0.0
var dash_direction := Vector2i.ZERO
const SPREAD_SECONDS := 3.0
const FIELD_X := 160.0
const FIELD_COLUMNS := 160
const CAPTURE_BAR := Rect2(FIELD_X, 130, 1280, 18)
const REWARD_HOLD := 0.45
const DRAFT_REVEAL := 0.85
const VICTORY_REVEAL := 2.2
const Sectors = preload("res://scripts/roguelite_sectors.gd")
const EXPEDITION_SECTORS := Sectors.LENGTH
const MAX_CARD_RANK := 3
const CHART_JUMP := Rect2(1240, 718, 260, 60)
var route: Array = []
var route_path: Array[int] = []
var active_destination := {}
var chart_depth := 1
var chart_focus_depth := 1
var sector_limit := EXPEDITION_SECTORS # Also supports isolated one-sector test fixtures.
const Fanfare = preload("res://scripts/roguelite_fanfare.gd")
var reward_audio: AudioStreamPlayer
var reveal_cue: AudioStreamWAV
var install_cue: AudioStreamWAV
var victory_cue: AudioStreamWAV
var progress = Progress.new()
var phase := "hangar"
var ui_time := 0.0
var selection := 0
var viewed_track := 0
var viewed_ranks: Array[int] = [1, 1, 1, 1, 1, 1]
const TRACK_VIEW := Rect2(345, 160, 800, 520)
const TRACK_ROW := 160.0
var track_scroll := 0.0
var scroll_dragging := false
var scroll_grab := 0.0
var owned_cards: Array[String] = []
var card_ranks := {}
var pending_card := {}
var replace_id := ""
var rerolls_left := 0
var salvage_fraction := 0.0
var sector_salvage_start := 0
var offers: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var capture_percent := 0.0
var displayed_capture := 0.0
var capture_flights: Array[Dictionary] = []
var capture_flash := 0.0
var reward_hold := 0.0
var drafts_taken := 0
var credited := PackedByteArray()
var first_claims := 0
var capture_count := 0
var pending_clear := false
var settled := false
var earned_salvage := 0
var bonus_salvage := 0.0
var banked_salvage := 0
var save_failed := false
var corruption := PackedByteArray()
var corruption_strokes := PackedVector2Array()
var corruption_visual_dirty := true
var corruption_active := false # Introduced after the bridge, in the final island sector.
# Objective encounters: beacon discs to enclose, a cargo pod to run home, a breach to seal.
var zones: Array[Dictionary] = []
var cargo := {}
var breach := {}
var last_objectives := {} # Handed from sector_layout to start_level; Game keeps its layout local.
var spread_clock := SPREAD_SECONDS
var containment_time := 0.0
var exposure := 0.0
var cut_time := 0.0
var safe_motion := 0.0
var hot_entry := false
var small_chain := 0
var freeze_time := 0.0
var boost_time := 0.0
var hardlight_time := 0.0
var cooldowns := {"hardening": 0.0, "leap": 0.0, "dash": 0.0, "afterburner": 0.0, "hardlight": 0.0, "anchor": 0.0, "ion": 0.0}
var last_result := ""
var hangar_page := "upgrades"
var viewed_ship := 0

func setup(p_lines: ScopeLines, p_sparks: Sparks, p_fill: Sprite2D) -> void:
	grid_width = FIELD_COLUMNS
	reward_audio = AudioStreamPlayer.new()
	reward_audio.volume_db = -8.0
	add_child(reward_audio)
	reveal_cue = Fanfare.make_cue()
	install_cue = Fanfare.make_cue(true)
	victory_cue = Fanfare.make_victory()
	progress.read_profile()
	rng.randomize()
	super.setup(p_lines, p_sparks, p_fill)

func go_title() -> void:
	go_dock()

func go_dock() -> void:
	phase = "hangar"
	state = State.DOCK
	selection = 1
	hangar_page = "upgrades"
	viewed_ship = Progress.SHIPS.find(progress.selected_ship)
	viewed_track = 0
	track_scroll = 0.0
	scroll_dragging = false
	for i in Progress.TRACKS.size():
		viewed_ranks[i] = mini(Progress.MAX_RANK, progress.rank_of(Progress.TRACKS[i]) + 1)
	ui_time = 0.0
	msg_t = 0.0
	lines.zoom = Vector2.ONE
	fill.visible = false

func start_run(_retry_sector := 0) -> void:
	reward_audio.stop()
	opening_draft_pending = true
	reset_movement_module()
	owned_cards.clear()
	card_ranks.clear()
	pending_card.clear()
	replace_id = ""
	salvage_fraction = progress.salvage_fraction
	offers.clear()
	capture_percent = 0
	displayed_capture = 0.0
	capture_flights.clear()
	capture_flash = 0.0
	reward_hold = 0.0
	corruption_active = false
	drafts_taken = 0
	first_claims = 0
	capture_count = 0
	bonus_salvage = 0
	earned_salvage = 0
	banked_salvage = 0
	settled = false
	save_failed = false
	pending_clear = false
	for key in cooldowns:
		cooldowns[key] = 0.0
	small_chain = 0
	freeze_time = 0.0
	boost_time = 0.0
	hardlight_time = 0.0
	containment_time = 0.0
	safe_motion = 0.0
	hot_entry = false
	phase = "run"
	gal = Galaxies.LIST[0].duplicate(true)
	gal.name = "HELIX REACH"
	gal.spawners = 0
	gal.boss = "none"
	ship = Ships.get_ship(progress.selected_ship if progress.owns_ship(progress.selected_ship) else "surveyor")
	level = 1
	endless = false
	run_victory = false
	lives = 2 + run_extra_lives()
	run_flux = 0.0
	run_isotope = 0
	run_cells = 0
	run_best_claim = 0.0
	run_deaths = 0
	run_sectors = 0
	run_hazards = 0
	run_nodes = 0
	set_field_x(FIELD_X)
	route = Sectors.make_route(rng, sector_limit)
	route_path.clear()
	active_destination.clear()
	chart_depth = 1
	open_chart()

func sector_layout(g: Dictionary, lvl: int, rim: int) -> Dictionary:
	var layout_galaxy := g.duplicate(true)
	layout_galaxy.id = "roguelite"
	var layout := super.sector_layout(layout_galaxy, arena_stage(lvl), rim)
	var placement := RandomNumberGenerator.new()
	placement.seed = hash("roguelite-pickups:%d" % lvl)
	var occupied: Array = [layout.start]
	layout.nodes.clear()
	for i in 3 + progress.rank_of("extractor") / 5 + (2 if encounter_kind(lvl) == "salvage" else 0):
		var cell := layout_pick(placement, 10, occupied, 24.0, layout.shape, layout.arena)
		layout.nodes.append({"cell": cell, "rare": false})
		occupied.append(cell)
	layout.turrets.clear()
	layout.spawners.clear()
	for i in Sectors.turret_count(encounter_kind(lvl), lvl):
		var cell := layout_pick(placement, 10, occupied, 28.0, layout.shape, layout.arena)
		layout.turrets.append({"cell": cell, "axis": Vector2i.DOWN})
		occupied.append(cell)
	# Objectives draw after pickups and turrets so existing kinds keep their placements.
	place_objectives(layout, lvl, placement, occupied)
	return layout

func sector_shape(_g: Dictionary, lvl: int, _rng: RandomNumberGenerator) -> Array:
	return Sectors.holes(lvl, Vector2i(grid_width, grid_height))

# ------------------------------------------------------------------ objective encounters
func place_objectives(layout: Dictionary, lvl: int, placement: RandomNumberGenerator, occupied: Array) -> void:
	var kind := encounter_kind(lvl)
	last_objectives = {"kind": kind, "zones": [], "pod": Vector2i(-1, -1), "breach": {}}
	match kind:
		"beacon":
			for i in Sectors.objective_count(kind, lvl):
				var disc := pick_disc(placement, Sectors.BEACON_RADIUS, occupied, layout.arena)
				last_objectives.zones.append(disc)
				occupied.append(disc.cell)
		"cargo":
			last_objectives.pod = layout_pick(placement, 10, occupied, 40.0, layout.shape, layout.arena)
		"breach":
			last_objectives.breach = pick_disc(placement, Sectors.BREACH_RADIUS, occupied, layout.arena)

## A disc centre whose every cell is playable void, clear of pickups, turrets and the start.
## Rails are mask 1 and begin claimed, so a disc touching one would start half captured.
## Candidates come straight from the arena's free cells; the shared arena is never mutated.
func pick_disc(placement: RandomNumberGenerator, radius: int, avoid: Array, arena: Dictionary) -> Dictionary:
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

func disc_free(c: Vector2i, radius: int, mask: PackedByteArray) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var q := c + Vector2i(dx, dy)
			if not in_bounds(q) or mask[idx(q.x, q.y)] != 2:
				return false
	return true

func disc_cells(c: Vector2i, radius: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var q := c + Vector2i(dx, dy)
			if dx * dx + dy * dy <= radius * radius and in_bounds(q):
				out.append(idx(q.x, q.y))
	return out

## Claimed means land: a live or hardened trail crossing the disc does not count.
func disc_claimed_fraction(c: Vector2i, radius: int) -> float:
	var cells_in := disc_cells(c, radius)
	var claimed := 0
	for i in cells_in:
		if cells[i] == CLAIMED:
			claimed += 1
	return float(claimed) / maxi(1, cells_in.size())

func setup_objectives() -> void:
	zones.clear()
	cargo.clear()
	breach.clear()
	var found: Dictionary = last_objectives
	last_objectives = {}
	if found.is_empty() or String(found.kind) != encounter_kind(level):
		return
	match encounter_kind(level):
		"beacon":
			for disc in found.zones:
				zones.append({"cell": disc.cell, "radius": disc.radius, "captured": false, "spin": 0.0})
		"cargo":
			cargo = {"cell": found.pod, "carrying": false, "delivered": 0, "runs": Sectors.objective_count("cargo", level), "done": false}
		"breach":
			breach = {"cell": found.breach.cell, "radius": found.breach.radius, "sealed": false, "pressure": 0.0, "spin": 0.0}

func objective_complete() -> bool:
	match encounter_kind(level):
		"beacon":
			for zone in zones:
				if not zone.captured:
					return false
			return not zones.is_empty()
		"cargo":
			return not cargo.is_empty() and int(cargo.delivered) >= int(cargo.runs)
		"breach":
			return not breach.is_empty() and bool(breach.sealed) and capture_percent >= Sectors.capture_goal(level)
	return capture_percent >= Sectors.capture_goal(level)

## Advances every objective from the current board and returns a note for the HUD.
func check_objectives() -> String:
	match encounter_kind(level):
		"beacon": return update_zones()
		"cargo": return update_cargo()
		"breach": return update_breach_seal()
	return ""

## Off-claim completions (a Sapper walking cargo home, a hardened Leap wall) still clear.
func settle_objective() -> void:
	if pending_clear or phase != "run" or state != State.PLAYING:
		return
	if objective_complete():
		begin_draft_reward()
		level_clear()

func update_zones() -> String:
	var note := ""
	for zone in zones:
		if zone.captured or disc_claimed_fraction(zone.cell, zone.radius) < 1.0:
			continue
		zone.captured = true
		award_flux(1.0)
		var secured := 0
		for other in zones:
			if other.captured:
				secured += 1
		var c := center(zone.cell)
		sparks.ripple(c, (zone.radius + 0.5) * CELL, 320.0, 0.6, Palette.GREEN)
		sparks.burst(c, 40, 200.0, 1.5, 0.7, Palette.CYAN)
		note = "BEACON SECURED %d/%d" % [secured, zones.size()]
	return note

func zone_contested(zone: Dictionary) -> bool:
	var c := center(zone.cell)
	for q: QixBody in qixes:
		if q.c.distance_to(c) <= (zone.radius + 0.5) * CELL:
			return true
	return false

func update_cargo() -> String:
	if cargo.is_empty() or bool(cargo.done):
		return ""
	if bool(cargo.carrying):
		if not exposed():
			return deliver_cargo()
		return ""
	check_cargo_contact()
	if bool(cargo.carrying):
		return ""
	var cell: Vector2i = cargo.cell
	if cells[idx(cell.x, cell.y)] != FREE:
		# Enclosed without contact: the pod is unreachable on land, so it drifts elsewhere.
		relocate_pod()
	return ""

## Pickup is contact by the ship itself: the trail head, a ridden lance cell, or the Sapper.
## A lance ray marks the cell early, but the run starts only when the ride reaches it.
func check_cargo_contact() -> void:
	if cargo.is_empty() or bool(cargo.carrying) or bool(cargo.done):
		return
	if exposed() and p == cargo.cell:
		cargo.carrying = true
		set_msg("CARGO ABOARD", 1.0)
		sparks.ripple(center(cargo.cell), 4.0, 240.0, 0.4, Palette.YELLOW)
		lines.spike(1.0, 0.2)

func deliver_cargo() -> String:
	cargo.carrying = false
	cargo.delivered = int(cargo.delivered) + 1
	award_flux(2.0)
	sparks.burst(vis, 40, 200.0, 1.5, 0.7, Palette.YELLOW)
	sparks.ripple(vis, 6.0, 300.0, 0.5, Palette.GREEN)
	if int(cargo.delivered) >= int(cargo.runs):
		cargo.done = true
	else:
		relocate_pod()
	return "CARGO DELIVERED %d/%d" % [cargo.delivered, cargo.runs]

func drop_cargo() -> void:
	if cargo.is_empty() or bool(cargo.done):
		return
	if bool(cargo.carrying):
		cargo.carrying = false
		set_msg("CARGO LOST", 1.2)
	var cell: Vector2i = cargo.cell
	if cells[idx(cell.x, cell.y)] != FREE:
		relocate_pod()

## A fresh void cell, far from the ship and not hugging the coast, drawn from the live board.
func relocate_pod() -> void:
	var free: Array = field_arena.get("free_cells", [])
	var best := Vector2i(-1, -1)
	var best_d := -1.0
	for tries in 120:
		if free.is_empty():
			break
		var c: Vector2i = free[rng.randi_range(0, free.size() - 1)]
		if cells[idx(c.x, c.y)] != FREE:
			continue
		var d := Vector2(c - p).length()
		if d <= best_d:
			continue
		var open := true
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var q := c + Vector2i(dx, dy)
				if not in_bounds(q) or cells[idx(q.x, q.y)] != FREE:
					open = false
		if not open and best_d >= 0.0:
			continue
		best_d = d
		best = c
		if open and d > 40.0:
			break
	if best.x < 0:
		# No void left to hide in: the remaining runs are forfeit rather than impossible.
		cargo.runs = cargo.delivered
		cargo.done = true
		return
	cargo.cell = best
	sparks.ripple(center(best), 6.0, 200.0, 0.5, Palette.YELLOW)

func update_breach_seal() -> String:
	if breach.is_empty() or bool(breach.sealed):
		return ""
	if disc_claimed_fraction(breach.cell, breach.radius) < 1.0:
		return ""
	breach.sealed = true
	award_flux(3.0)
	var c := center(breach.cell)
	sparks.ripple(c, (breach.radius + 0.5) * CELL, 360.0, 0.7, Palette.GREEN)
	sparks.burst(c, 60, 240.0, 1.5, 0.8, Palette.MAGENTA)
	return "BREACH SEALED"

func seed_breach() -> void:
	if breach.is_empty():
		return
	for i in disc_cells(breach.cell, breach.radius):
		if cells[i] == FREE:
			corruption[i] = 1
	corruption_visual_dirty = true

## The open breach cannot be cleansed, and its spread is the fail meter: past the limit
## the ship takes a hit and the infection collapses back to the source.
func update_breach_pressure() -> void:
	seed_breach()
	var infected := 0
	for i in grid_width * grid_height:
		if corruption[i] != 0 and cells[i] == FREE:
			infected += 1
	breach.pressure = float(infected) / maxi(1, base_free)
	if breach.pressure < Sectors.BREACH_LIMIT:
		return
	die("CONTAINMENT LOST")
	if state != State.DYING:
		return # A shielded ship keeps its hull; the meter is checked again next tick.
	corruption.fill(0)
	seed_breach()
	breach.pressure = float(disc_cells(breach.cell, breach.radius).size()) / maxi(1, base_free)
	spread_clock = SPREAD_SECONDS

func objective_label() -> String:
	match encounter_kind(level):
		"beacon":
			var secured := 0
			for zone in zones:
				if zone.captured:
					secured += 1
			return "BEACONS %d/%d" % [secured, zones.size()]
		"cargo":
			return "CARGO %d/%d" % [int(cargo.get("delivered", 0)), int(cargo.get("runs", 0))]
	return "CAPTURE %d%%" % Sectors.capture_goal(level)

func bar_scale() -> float:
	return 100.0 if not Sectors.territory_goal(encounter_kind(level)) else float(Sectors.capture_goal(level))

func advance_objective_visuals(dt: float) -> void:
	for zone in zones:
		if not zone.captured:
			zone.spin = float(zone.spin) + dt * (0.6 + (4.0 if zone_contested(zone) else 0.0))
	if not breach.is_empty() and not bool(breach.sealed):
		breach.spin = float(breach.spin) + dt * (0.6 + 6.0 * float(breach.pressure) / Sectors.BREACH_LIMIT)

func draw_ring(c: Vector2, radius: float, spin: float, color: Color, thick := 1.4) -> void:
	# Three arcs with gaps, spinning faster as the objective is contested.
	for k in 3:
		var a0 := spin + k * TAU / 3.0
		arc(c, radius, a0, a0 + TAU / 6.0, color, thick)

func draw_objectives() -> void:
	for zone in zones:
		var c := center(zone.cell)
		var radius := (float(zone.radius) + 0.5) * CELL
		if zone.captured:
			lines.circle(c, radius, Palette.GREEN, 24, 0.3, 0.1, 1.0)
			lines.circle(c, 3.0, Palette.GREEN, 6, 0.8, 0.3, 0.9)
			continue
		draw_ring(c, radius, float(zone.spin), Palette.CYAN)
		var fraction := disc_claimed_fraction(zone.cell, zone.radius)
		if fraction > 0.0:
			arc(c, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, Palette.GREEN, 1.0)
		lines.circle(c, 3.0, Palette.FULLBRIGHT, 6, 1.0, 0.6, 0.9)
	if not cargo.is_empty() and not bool(cargo.done):
		var pulse := 0.5 + 0.5 * sin(time * 3.0)
		if bool(cargo.carrying):
			draw_pod(vis + Vector2(12, -12), 6.0, pulse)
			lines.circle(center(anchor), 8.0 + 3.0 * pulse, Palette.YELLOW, 8, 0.8, 0.3, 1.0)
		else:
			var c := center(cargo.cell)
			draw_pod(c, 9.0, pulse)
			var label_color := Palette.YELLOW
			label_color.a = 0.5 + 0.4 * pulse
			VectorFont.draw(lines, "CARGO", c + Vector2(13, -6), 10, label_color, 0.5, 0.3)
	if not breach.is_empty():
		var c := center(breach.cell)
		var radius := (float(breach.radius) + 0.5) * CELL
		if bool(breach.sealed):
			lines.circle(c, radius, Palette.DIM, 16, 0.3, 0.1, 1.0)
		else:
			draw_ring(c, radius, float(breach.spin), Palette.MAGENTA)
			lines.circle(c, 3.0, Palette.MAGENTA, 6, 1.0, 0.6, 0.9)

func draw_pod(c: Vector2, size: float, pulse: float) -> void:
	var pts := PackedVector2Array()
	for k in 4:
		var a := time * 1.5 + k * PI * 0.5
		pts.append(c + Vector2(cos(a), sin(a)) * (size + 1.5 * pulse))
	lines.polyline(pts, true, Palette.YELLOW, 1.2, 0.5, 1.2)
	lines.circle(c, 2.5, Palette.FULLBRIGHT, 6, 1.0, 0.6, 0.9)

## Anomalies guard uncaptured beacons and hunt a cargo carrier: a loose pull that the
## random re-steer keeps fighting, so windows still open.
func steer_anomaly(q: QixBody, dt: float, speed: float) -> void:
	if q.v.length_squared() < 0.001 or speed <= 0.0:
		return
	var target := Vector2.ZERO
	var rate := 0.0
	if not cargo.is_empty() and bool(cargo.carrying):
		target = vis
		rate = 1.2
	elif not zones.is_empty():
		var open: Array[Dictionary] = []
		for zone in zones:
			if not zone.captured:
				open.append(zone)
		if open.is_empty():
			return
		var zone: Dictionary = open[maxi(0, qixes.find(q)) % open.size()]
		var c := center(zone.cell)
		if q.c.distance_to(c) <= 3.0 * float(zone.radius) * CELL:
			return
		target = c
		rate = 0.8
	else:
		return
	var toward := (target - q.c).normalized() * speed
	q.v = q.v.slerp(toward, 1.0 - exp(-dt * rate)).normalized() * speed

func start_level() -> void:
	reset_movement_module()
	corruption_active = level >= Sectors.CORRUPTION_SECTOR or encounter_kind(level) == "breach"
	if level >= Sectors.CORRUPTION_SECTOR: progress.containment_unlocked = true
	progress.best_sector = maxi(progress.best_sector, mini(level, EXPEDITION_SECTORS))
	capture_percent = 0.0
	displayed_capture = 0.0
	first_claims = 0
	drafts_taken = 0
	pending_clear = false
	run_victory = false
	capture_flights.clear()
	rerolls_left = progress.rank_of("scanner") / 5
	sector_salvage_start = earned_salvage
	super.start_level()
	setup_objectives() # Before seeding corruption, which a breach sector sources from its disc.
	draft_capture = Sectors.draft_milestones(base_free)
	while qixes.size() < Sectors.anomaly_count(level, arena_stage(level)):
		spawn_qix()
	sparx_to_spawn = mini(sparx_to_spawn, 2) # Geometry teaches the new challenge before enemy volume.
	trail_slow = false # Only Surveyor explicitly starting a slow cut earns the slow bonus.
	# Reuse Jump's node placement, icons, enclosure checks, and collection effects.
	credited.resize(grid_width * grid_height)
	credited.fill(0)
	corruption.resize(grid_width * grid_height)
	corruption.fill(0)
	for i in grid_width * grid_height:
		if cells[i] != FREE:
			credited[i] = 1
	seed_corruption()
	exposure = 0.0
	cut_time = 0.0
	spread_clock = SPREAD_SECONDS
	anchor = p

func spawn_qix() -> void:
	var count := Sectors.anomaly_count(level, arena_stage(level))
	if qixes.size() >= count: return
	super.spawn_qix()
	var q: QixBody = qixes.back()
	var half: Vector2 = Sectors.stage(arena_stage(level)).half
	var offsets := [Vector2(0.45, 0.2)] if count == 1 else [Vector2(-0.6, 0.25), Vector2(0.6, 0.25), Vector2(0, -0.65)]
	var target: Vector2 = Vector2(grid_width, grid_height) * 0.5 + offsets[qixes.size() - 1] * half
	var best_score := INF
	# Search legal full-beam positions nearest the assigned side. This avoids
	# random clustering on one side of a notch or inside the bridge's neck.
	for cell: Vector2i in field_arena.free_cells:
		var score := Vector2(cell).distance_squared_to(target)
		if score >= best_score: continue
		var point := center(cell)
		if qix_blocked(point, q.theta, q.len): continue
		var overlaps := false
		for other: QixBody in qixes:
			if other != q and point.distance_to(other.c) < (q.len + other.len) * 0.5 + CELL * 2:
				overlaps = true
				break
		if overlaps: continue
		best_score = score
		q.c = point

func spawn_boss() -> void:
	pass # Sector eight is the expedition finale, not Jump's galaxy boss encounter.

func seed_corruption() -> void:
	corruption_visual_dirty = true
	if not corruption_active:
		return
	if encounter_kind(level) == "breach" and not breach.is_empty():
		seed_breach()
		return
	for source in [Vector2i(30, 33), Vector2i(72, 62)]:
		for dy in range(-7, 8):
			for dx in range(-7, 8):
				var c: Vector2i = source + Vector2i(dx, dy)
				if dx * dx + dy * dy <= 49 and cells[idx(c.x, c.y)] == FREE:
					corruption[idx(c.x, c.y)] = 1

# Explicit stat/economy overrides prevent campaign power or rewards leaking across modes.
func run_rim() -> int:
	return 0

func capture_target() -> float:
	# Objective sectors never clear on territory alone; an open breach holds the goal back.
	var kind := encounter_kind(level)
	if not Sectors.territory_goal(kind) or (kind == "breach" and not bool(breach.get("sealed", false))):
		return 2.0
	return Sectors.capture_goal(level) / 100.0

func run_extra_lives() -> int:
	return progress.rank_of("hull") / 5

func movement_mult() -> float:
	var mult: float = 1.0 + progress.rank_of("engines") * 0.02
	if dash_time > 0.0: mult *= 3.0
	if drawing:
		if boost_time > 0.0:
			mult *= 1.0 + 0.8 * card_power("afterburner")
		if hot_entry and cut_time < (3.0 if progress.rank_of("engines") >= 10 else 2.0):
			mult *= 1.0 + 0.3 * (card_power("slipstream") if has_card("slipstream") else 1.0)
		mult *= 1.0 + small_chain * 0.15 * card_power("compression")
	return mult

func respawn_shield_duration() -> float:
	return 2.5 + progress.rank_of("hull") * 0.5

func sap_rate() -> float:
	var mult := 1.0 + 0.03 * progress.rank_of("reactor")
	if boost_time > 0.0:
		mult *= 1.0 + 0.8 * card_power("afterburner")
	if hot_entry and cut_time < (3.0 if progress.rank_of("engines") >= 10 else 2.0):
		mult *= 1.0 + 0.3 * (card_power("slipstream") if has_card("slipstream") else 1.0)
	mult *= 1.0 + small_chain * 0.15 * card_power("compression")
	return super.sap_rate() * mult

func begin_attack() -> void:
	cut_time = 0.0
	hot_entry = safe_motion >= 2.0 and (has_card("slipstream") or progress.rank_of("engines") >= 5)
	safe_motion = 0.0

func fire_lance(extend := false) -> void:
	var was_drawing := drawing
	super.fire_lance(extend)
	if drawing and not was_drawing:
		begin_attack()

func start_sapper_charge() -> void:
	super.start_sapper_charge()
	begin_attack()

func wire_hit() -> bool:
	if ship.id == "sapper" and sap_live and disc_braced and hardening_time > 0.0:
		disc_braced = false
		hardening_time = 0.0
		# Let the absorbed contact separate before the next collision check.
		hardlight_time = maxf(hardlight_time, 0.25)
		return false
	if ship.id == "sapper" and sap_live and not tether_hit(sap_cell):
		return false
	return super.wire_hit()

func prospect_interval() -> float:
	return 0.0

func fuse_delay() -> float:
	return 1.5

func base_node_value() -> int:
	return 1

func slow_node_bonus() -> float:
	return 0.25

func hazard_capture_value() -> float:
	return 0.25

func award_flux(amount: float) -> void:
	# Shared enclosure rewards are banked only in the Roguelite profile.
	salvage_fraction += amount * (1.0 + 0.02 * progress.rank_of("extractor"))
	var whole := floori(salvage_fraction + 0.000001)
	earned_salvage += whole
	salvage_fraction = maxf(0.0, salvage_fraction - whole)

func award_isotope() -> void:
	pass

func up(id: String) -> int:
	return progress.rank_of("hull") if id == "shield" else 0

func has_card(id: String) -> bool:
	return owned_cards.has(id)

func card_rank(id: String) -> int:
	return clampi(int(card_ranks.get(id, 1)), 1, MAX_CARD_RANK)

func card_power(id: String) -> float:
	return 1.0 + 0.25 * (card_rank(id) - 1)

func card_definition(id: String, rank := 0) -> Dictionary:
	return Cards.definition(id, ship.id, card_rank(id) if rank == 0 else rank)

func roll_offers(avoid: Array[String] = []) -> void:
	if opening_draft_pending:
		offers.clear()
		for id in Cards.OPENING:
			var card := card_definition(id, 1)
			card.action = "NEW"
			offers.append(card)
		return
	var pool: Array[String] = []
	var excluded := draft_exclusions()
	for card in Cards.LIST:
		if Cards.OPENING.has(card.id) and not has_card(card.id): continue
		if Cards.SECONDARY.has(card.id) and not secondary_ability().is_empty() and not has_card(card.id): continue
		if not excluded.has(card.id) and (not has_card(card.id) or (owned_cards.size() >= 3 and card_rank(card.id) < MAX_CARD_RANK)):
			pool.append(card.id)
	var fresh_pool: Array[String] = []
	for id in pool:
		if not avoid.has(id): fresh_pool.append(id)
	if fresh_pool.size() >= 3: pool = fresh_pool
	offers.clear()
	while offers.size() < 3 and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		var id := pool[index]
		pool.remove_at(index)
		var rank := card_rank(id) + 1 if has_card(id) else (2 if rng.randf() < progress.rank_of("scanner") * 0.02 else 1)
		var card := card_definition(id, rank)
		card.action = "UPGRADE" if has_card(id) else ("REPLACE" if owned_cards.size() >= 3 else "NEW")
		offers.append(card)

func reroll_draft() -> void:
	if opening_draft_pending or phase != "draft" or ui_time < DRAFT_REVEAL or rerolls_left <= 0:
		return
	rerolls_left -= 1
	var previous: Array[String] = []
	for card in offers: previous.append(card.id)
	roll_offers(previous)
	selection = 0
	ui_time = 0.0
	reward_audio.stream = reveal_cue
	reward_audio.play()

func update(dt: float) -> void:
	ui_time += dt
	if phase == "paused":
		update_choices()
		return
	if phase == "run" and state == State.PLAYING and Input.is_action_just_pressed("abort"):
		pause_run()
		return
	if phase == "install":
		sparks.update(dt)
		if ui_time >= 0.45:
			phase = "draft"
			choose_card(selection)
		return
	if phase in ["run", "reward"]:
		update_capture_feedback(dt)
	if phase == "reward":
		time += dt
		msg_t -= dt
		shake_off = Vector2.ZERO
		sparks.update(dt)
		if capture_flights.is_empty():
			reward_hold += dt
			if reward_hold >= REWARD_HOLD:
				if drafts_taken < draft_capture.size() and capture_percent >= draft_capture[drafts_taken]:
					open_draft()
				elif pending_clear:
					finish_sector()
		return
	if phase != "run":
		time += dt
		msg_t -= dt
		shake_off = Vector2.ZERO
		sparks.update(dt)
		update_choices()
		return
	super.update(dt)
	if phase == "run" and state == State.PLAYING:
		if drafts_taken < draft_capture.size() and capture_percent >= draft_capture[drafts_taken]:
			begin_draft_reward()
		elif pending_clear:
			finish_sector()

func update_play(dt: float) -> void:
	# A capture may queue several drafts, including the final cut. No simulation
	# advances between that capture, its choices and settlement.
	if pending_clear or (drafts_taken < draft_capture.size() and capture_percent >= draft_capture[drafts_taken]):
		return
	for key in cooldowns:
		cooldowns[key] = maxf(0.0, float(cooldowns[key]) - dt * (1.0 + 0.03 * progress.rank_of("reactor")))
	boost_time = maxf(0.0, boost_time - dt)
	hardlight_time = maxf(0.0, hardlight_time - dt)
	freeze_time = maxf(0.0, freeze_time - dt)
	containment_time = maxf(0.0, containment_time - dt)
	advance_objective_visuals(dt)
	if Input.is_action_just_pressed("br_harden"):
		activate_ability(movement_module())
	if Input.is_action_just_pressed("special"):
		activate_ability(secondary_ability())
	update_movement_module(dt)
	leap_input_frame = leap_building or wall_building
	var old_p := p
	if drawing or sap_live:
		cut_time += dt
	if ship.id == "lancer":
		lance_cd = maxf(0.0, lance_cd - dt * 0.03 * progress.rank_of("reactor"))
	super.update_play(dt)
	if state != State.PLAYING or phase != "run" or pending_clear:
		return
	if not drawing and not sap_live and cells[idx(p.x, p.y)] == CLAIMED:
		if p != old_p or move_acc > 0.0:
			safe_motion += dt
		elif not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_up") and not Input.is_action_pressed("move_down"):
			safe_motion = 0.0
	var note := check_objectives()
	if not note.is_empty():
		set_msg(note, 1.2)
	settle_objective()
	if state != State.PLAYING or pending_clear:
		return
	update_corruption(dt)

func try_step(dir: Vector2i, draw_line: bool, slow: bool) -> bool:
	var was_drawing := drawing
	if ship.id == "sapper" and cells[idx(p.x, p.y)] == CLAIMED:
		anchor = p
	var moved := super.try_step(dir, draw_line, slow)
	if drawing and not was_drawing:
		begin_attack()
	check_cargo_contact() # Per step, so a fast frame cannot skip the pod's cell.
	return moved

func ride_step() -> void:
	super.ride_step()
	check_cargo_contact()

func activate_ability(id: String) -> void:
	if phase != "run" or state != State.PLAYING or not has_card(id) or float(cooldowns.get(id, 1.0)) > 0.0:
		return
	if id == "hardening":
		if wall_building or leap_building or not (drawing or sap_live): return
		hardening_time = 3.0 * card_power(id)
		disc_braced = sap_live
		cooldowns[id] = 12.0
	elif id == "leap":
		if drawing or sap_live or leap_building or wall_building or cells[idx(p.x, p.y)] != CLAIMED: return
		start_leap()
		if not leap_building: return
		begin_attack()
	elif id == "dash":
		if leap_building or wall_building or sap_live or last_dir == Vector2i.ZERO: return
		if ship.id == "surveyor" and not drawing: draw_armed = true
		dash_direction = tether_dir if tether_active else last_dir
		dash_time = 0.3 * card_power(id)
		cooldowns[id] = 8.0
	elif id == "afterburner":
		boost_time = 3.0
		cooldowns[id] = 14.0
	elif id == "hardlight":
		hardlight_time = 2.0 * card_power("hardlight")
		cooldowns[id] = 18.0
	sparks.ripple(vis, 5.0, 260.0, 0.6, Palette.CYAN)

func tether_hit(c: Vector2i) -> bool:
	if hardlight_time > 0.0 or (has_card("phase") and cut_time < 1.5 * card_power("phase")):
		return false
	if has_card("ion") and float(cooldowns.ion) <= 0.0:
		cooldowns.ion = 10.0
		freeze_time = 1.5 * card_power("ion")
		# Repel the contact so the same overlapping enemy does not immediately
		# invalidate the stun on the next frame.
		for q in qixes:
			q.v = -q.v
		for m in mites:
			m.vel = (m.pos - center(c)).normalized() * 150.0
		hardlight_time = maxf(hardlight_time, 1.8)
		sparks.ripple(center(c), 5.0, 350.0, 0.5, Palette.CYAN)
		return false
	return super.tether_hit(c)

func update_qix(q: QixBody, dt: float, speed: float) -> void:
	if freeze_time <= 0.0:
		super.update_qix(q, dt, speed)
		steer_anomaly(q, dt, speed)

func update_sparx(s: SparxBody, dt: float) -> void:
	if freeze_time <= 0.0:
		super.update_sparx(s, dt)

func update_hazards(dt: float) -> void:
	if freeze_time <= 0.0:
		super.update_hazards(dt)

func die(reason: String) -> void:
	if invuln > 0.0:
		return
	reset_movement_module()
	corruption_visual_dirty = true
	if (drawing or (ship.id == "sapper" and (sap_live or cells[idx(p.x, p.y)] == FREE))) and has_card("anchor") and float(cooldowns.anchor) <= 0.0:
		cooldowns.anchor = 24.0 / card_power("anchor")
		for c in trail:
			cells[idx(c.x, c.y)] = FREE
		trail.clear()
		tether_active = false
		leap_building = false
		wall_building = false
		harden_len = 0.0
		sap_live = false
		sap_charge = 0.0
		p = anchor
		vis = center(p)
		drawing = false
		fuse_on = false
		draw_armed = false
		move_acc = 0.0
		invuln = 1.0
		exposure = 0.0
		set_msg("ANCHOR RECOVERY", 1.0)
		drop_cargo() # After the trail is freed, so the pod's cell reads correctly.
		return
	super.die(reason)
	drop_cargo()
	exposure = 0.0
	safe_motion = 0.0

func on_claim(gained: int, caught: int) -> void:
	var previous_capture := capture_percent
	var newly_claimed: Array[int] = []
	var cleansed := 0
	for i in grid_width * grid_height:
		if cells[i] == CLAIMED and credited[i] == 0:
			credited[i] = 1
			first_claims += 1
			newly_claimed.append(i)
			if corruption[i] != 0:
				cleansed += 1
			corruption[i] = 0
	# First-time territory drives both card milestones and the sector goal.
	capture_percent = first_claims * 100.0 / maxi(1, base_free)
	# Objectives read the board before the early return: a cut that only re-crosses
	# credited land can still close a beacon, seal a breach or deliver cargo.
	var note := check_objectives()
	if newly_claimed.is_empty():
		if not note.is_empty():
			set_msg(note, 1.2)
		settle_objective()
		return
	corruption_visual_dirty = true
	queue_capture_feedback(newly_claimed, previous_capture)
	capture_count += 1
	var fraction := float(newly_claimed.size()) / maxi(1, base_free)
	var clean_radius := maxi(roundi(6 * card_power("clean")) if has_card("clean") else 0, (progress.rank_of("containment") / 5) * 2)
	if clean_radius > 0:
		clean_near_claim(newly_claimed, clean_radius)
	if has_card("containment") and fraction >= 0.08:
		containment_time = 8.0 * card_power("containment")
	if has_card("compression"):
		if fraction < 0.04:
			small_chain = mini(3, small_chain + 1)
		elif fraction >= 0.08:
			small_chain = 0
	if has_card("loop") and capture_count % 3 == 0:
		refund_cooldowns(6.0 * card_power("loop"))
	if progress.rank_of("reactor") >= 5:
		refund_cooldowns(float(progress.rank_of("reactor") / 5))
	if has_card("stasis"):
		freeze_time = maxf(freeze_time, card_power("stasis"))
	if has_card("harvest"):
		bonus_salvage += caught * 1.25
		award_flux(caught * 1.25 * card_power("harvest"))
	exposure = 0.0
	var tags := " / CORRUPTION CLEANSED" if cleansed > 0 else ""
	if not note.is_empty():
		tags += " / " + note
	set_msg("+%d%% CAPTURE%s" % [int(fraction * 100), tags], 1.1)
	# The reward phase opens first and the clear is queued behind it: level_clear settles
	# immediately outside a draft phase, and finish_sector must run exactly once.
	var milestone := drafts_taken < draft_capture.size() and capture_percent >= draft_capture[drafts_taken]
	var done := objective_complete()
	if milestone or done:
		begin_draft_reward()
	if done:
		level_clear()

func refund_cooldowns(seconds: float) -> void:
	lance_cd = maxf(0.0, lance_cd - seconds)
	for key in cooldowns:
		cooldowns[key] = maxf(0.0, float(cooldowns[key]) - seconds)

func clean_near_claim(claims: Array[int], radius := 6) -> void:
	corruption_visual_dirty = true
	# Only boundary cells need a neighbourhood check; interior cells cannot
	# have adjacent hostile corruption. This keeps a large capture inexpensive.
	for i in claims:
		if border[i] == 0:
			continue
		var origin := Vector2i(i % grid_width, i / grid_width)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := origin + Vector2i(dx, dy)
				if in_bounds(c) and dx * dx + dy * dy <= radius * radius:
					corruption[idx(c.x, c.y)] = 0

func spread_corruption() -> void:
	if not corruption_active:
		return
	var breaching := encounter_kind(level) == "breach" and not breach.is_empty()
	if breaching and bool(breach.sealed):
		return # A sealed breach spreads no further; captures still cleanse what remains.
	var next := corruption.duplicate()
	var changed := false
	for i in grid_width * grid_height:
		if corruption[i] == 0 or cells[i] != FREE:
			continue
		# Read sources from the old mask so a tick still grows exactly one cell.
		# Integer neighbours avoid allocating vectors/arrays for every infected cell.
		var x := i % grid_width
		if x > 0 and cells[i - 1] == FREE and next[i - 1] == 0:
			next[i - 1] = 1
			changed = true
		if x + 1 < grid_width and cells[i + 1] == FREE and next[i + 1] == 0:
			next[i + 1] = 1
			changed = true
		if i >= grid_width and cells[i - grid_width] == FREE and next[i - grid_width] == 0:
			next[i - grid_width] = 1
			changed = true
		if i + grid_width < cells.size() and cells[i + grid_width] == FREE and next[i + grid_width] == 0:
			next[i + grid_width] = 1
			changed = true
	corruption = next
	if changed: corruption_visual_dirty = true
	if breaching:
		update_breach_pressure()

func update_corruption(dt: float) -> void:
	if not corruption_active:
		return
	if containment_time <= 0.0:
		spread_clock -= dt
		if spread_clock <= 0.0:
			spread_clock += SPREAD_SECONDS
			spread_corruption()
			if state != State.PLAYING:
				return # A breach collapse already took this frame's hit.
	var infected_trail := false
	if ship.id == "sapper":
		infected_trail = corruption[idx(p.x, p.y)] != 0
	for c in trail:
		if corruption[idx(c.x, c.y)] != 0:
			infected_trail = true
			break
	if infected_trail:
		exposure += dt * (1.0 - 0.03 * progress.rank_of("containment"))
	else:
		exposure = maxf(0.0, exposure - dt * 2.0)
	if exposure >= 4.0:
		die("CORRUPTION OVERLOAD")

func draft_exclusions() -> Array[String]:
	var excluded: Array[String] = []
	if not corruption_active:
		excluded.assign(["clean", "containment"])
	var has_capture_target := false
	for nest in spawners:
		if not nest.captured:
			has_capture_target = true
	for turret in turrets:
		if not turret.captured:
			has_capture_target = true
	if not has_capture_target:
		excluded.append("harvest")
	return excluded

func begin_draft_reward() -> void:
	phase = "reward"
	state = State.LEVEL_CLEAR # Freeze immediately, keeping the arena visible for particle delivery.
	reward_hold = 0.0
	ui_time = 0.0
	msg_t = 0.0

func queue_capture_feedback(claims: Array[int], previous_capture: float) -> void:
	var gain := capture_percent - previous_capture
	if gain <= 0:
		return
	# Bound visual work for rapid micro-captures; territory was already credited.
	if capture_flights.size() > 48:
		capture_flights.clear()
		displayed_capture = previous_capture
	var count := clampi(ceili(gain), 6, 18)
	for i in count:
		var cell_index := claims[mini(claims.size() - 1, int((i + 0.5) * claims.size() / count))]
		var origin := center(Vector2i(cell_index % grid_width, cell_index / grid_width))
		var portion := float(gain) / count
		var destination := capture_bar_point(previous_capture + portion * (i + 1))
		capture_flights.append({"origin": origin, "target": destination,
			"age": -i * 0.014, "duration": 0.60 + (i % 4) * 0.035,
			"amount": portion, "bend": Vector2(sin(i * 2.4) * 75.0, -65.0)})

func capture_flight_position(flight: Dictionary, age: float) -> Vector2:
	var t := clampf(age / float(flight.duration), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var start: Vector2 = flight.origin
	var end: Vector2 = flight.target
	var control: Vector2 = start.lerp(end, 0.5) + Vector2(flight.bend)
	return start * pow(1.0 - t, 2.0) + control * 2.0 * (1.0 - t) * t + end * t * t

func update_capture_feedback(dt: float) -> void:
	capture_flash = maxf(0.0, capture_flash - dt)
	for i in range(capture_flights.size() - 1, -1, -1):
		var flight := capture_flights[i]
		flight.age = float(flight.age) + dt
		if float(flight.age) >= float(flight.duration):
			displayed_capture = minf(capture_percent, displayed_capture + float(flight.amount))
			capture_flash = 0.35
			sparks.ripple(flight.target, 2.0, 32.0, 0.2, Palette.CYAN)
			capture_flights.remove_at(i)
	if capture_flights.is_empty():
		displayed_capture = capture_percent

func draw_capture_flights() -> void:
	for flight in capture_flights:
		var age: float = flight.age
		if age < 0.0:
			continue
		var head := capture_flight_position(flight, age)
		var tail := capture_flight_position(flight, maxf(0.0, age - 0.08))
		lines.seg(tail, head, Palette.CYAN, 0.25, 0.05, 1.4)
		lines.circle(head, 2.2, Palette.WHITE, 8, 0.1, 0.0, 1.1)

func capture_bar_point(percent: float) -> Vector2:
	return Vector2(CAPTURE_BAR.position.x + 3 + (CAPTURE_BAR.size.x - 6) * clampf(percent / bar_scale(), 0.0, 1.0), CAPTURE_BAR.get_center().y)

func hud_label(text: String, pos: Vector2, size := 16.0, color := Palette.WHITE) -> void:
	VectorFont.draw(lines, text, pos, size, color, 0.0, 0.0)

func draw_draft_meter() -> void:
	var goal := Sectors.capture_goal(level)
	var kind := encounter_kind(level)
	var color := Palette.GREEN if Sectors.territory_goal(kind) and displayed_capture >= goal else Palette.CYAN
	hud_label(objective_label(), Vector2(CAPTURE_BAR.position.x, 104), 13, Palette.DIM)
	if kind == "breach" and not breach.is_empty():
		var pressure := int(round(100.0 * float(breach.pressure)))
		var hot := not bool(breach.sealed) and float(breach.pressure) >= 0.15
		hud_label("SEALED" if bool(breach.sealed) else "BREACH %d%%" % pressure, Vector2(CAPTURE_BAR.position.x + 180, 104), 13, Palette.MAGENTA if hot else Palette.DIM)
	VectorFont.draw(lines, "%.1f%%" % displayed_capture, Vector2(CAPTURE_BAR.end.x, 102), 18, color, 0.0, 0.0, 2)
	var left := capture_bar_point(0)
	lines.rect(CAPTURE_BAR, Palette.WHITE if capture_flash > 0.0 else Palette.DIM, 0.0, 0.0, 1.0)
	var fill_x := capture_bar_point(displayed_capture).x
	var start_x := left.x
	for i in draft_capture.size():
		var c := capture_bar_point(draft_capture[i])
		if fill_x > start_x:
			lines.seg(Vector2(start_x, c.y), Vector2(minf(fill_x, c.x - 9), c.y), color, 0.0, 0.0, 4.0)
		start_x = c.x + 9
		var marker := Palette.GREEN if i < drafts_taken else (Palette.YELLOW if i == drafts_taken else Palette.DIM)
		lines.polyline(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), true, marker, 0.0, 0.0, 1.2)
		if i < drafts_taken:
			lines.circle(c, 1.5, marker, 4)
	if fill_x > start_x:
		lines.seg(Vector2(start_x, left.y), Vector2(fill_x, left.y), color, 0.0, 0.0, 4.0)
	if capture_flash > 0.0:
		lines.circle(capture_bar_point(displayed_capture), 3.0, Palette.WHITE, 8)

func open_draft() -> void:
	phase = "draft"
	state = State.REPORT # Park the shared simulation immediately, even mid-movement frame.
	roll_offers()
	selection = 0
	ui_time = 0.0
	msg_t = 0.0
	reward_audio.stream = reveal_cue
	reward_audio.play()
	sparks.ripple(Vector2(800, 195), 12.0, 440.0, 0.7, Palette.CYAN)

func begin_card_install(index: int) -> void:
	if phase != "draft" or ui_time < DRAFT_REVEAL or index < 0 or index >= offers.size():
		return
	if not has_card(offers[index].id) and owned_cards.size() >= 3 and replace_id.is_empty():
		pending_card = {"index": index}
		phase = "replace"
		selection = 0
		ui_time = 0.0
		return
	selection = index
	phase = "install"
	ui_time = 0.0
	reward_audio.stream = install_cue
	reward_audio.play()
	sparks.ripple(choice_rect(index).get_center(), 35.0, 500.0, 0.45, Palette.GREEN)
	sparks.burst(choice_rect(index).get_center(), 36, 260.0, 1.5, 0.45, Palette.GREEN)

func choose_card(index: int) -> void:
	if phase != "draft" or index < 0 or index >= offers.size():
		return
	var id: String = offers[index].id
	if not has_card(id) and owned_cards.size() >= 3 and replace_id.is_empty():
		pending_card = {"index": index}
		phase = "replace"
		selection = 0
		ui_time = 0.0
		return
	if not replace_id.is_empty():
		var slot := owned_cards.find(replace_id)
		if slot < 0: return
		owned_cards[slot] = id
		card_ranks.erase(replace_id)
		if cooldowns.has(replace_id): cooldowns[replace_id] = 0.0
		if Cards.OPENING.has(replace_id): reset_movement_module()
		if replace_id == "compression": small_chain = 0
		if replace_id == "afterburner": boost_time = 0.0
		if replace_id == "hardlight": hardlight_time = 0.0
		if replace_id == "slipstream" and progress.rank_of("engines") < 5: hot_entry = false
		replace_id = ""
	elif not has_card(id):
		owned_cards.append(id)
	card_ranks[id] = int(offers[index].get("rank", 1))
	pending_card.clear()
	finish_draft()

func keep_build() -> void:
	if phase != "draft" or ui_time < DRAFT_REVEAL or owned_cards.size() < 3: return
	finish_draft()

func finish_draft() -> void:
	opening_draft_pending = false
	drafts_taken += 1
	offers.clear()
	if drafts_taken < draft_capture.size() and capture_percent >= draft_capture[drafts_taken]:
		open_draft()
	elif pending_clear:
		finish_sector()
	else:
		phase = "run"
		state = State.PLAYING
		draw_armed = false
		ui_time = 0.0

func level_clear() -> void:
	pending_clear = true
	run_victory = level >= sector_limit
	run_sectors = level
	if phase not in ["draft", "reward", "install", "replace"]:
		finish_sector()

func finish_sector() -> void:
	if settled or phase in ["sector_clear", "chart"]: return
	if encounter_kind(level) == "repair":
		lives = mini(lives + 1, 2 + run_extra_lives())
	if level >= sector_limit:
		end_run()
		return
	phase = "sector_clear"
	state = State.REPORT
	ui_time = 0.0
	selection = 0
	msg_t = 0.0
	reward_audio.stream = victory_cue
	reward_audio.play()
	sparks.ripple(Vector2(800, 310), 20.0, 560.0, 1.2, Palette.GREEN)

func continue_expedition() -> void:
	if phase != "sector_clear" or ui_time < VICTORY_REVEAL: return
	chart_depth = level + 1
	open_chart()

func arena_stage(depth: int) -> int:
	return int(active_destination.stage) if active_destination.get("depth", 0) == depth else depth

func encounter_kind(depth: int) -> String:
	return String(active_destination.kind) if active_destination.get("depth", 0) == depth else "survey"

func open_chart() -> void:
	sparks.ripples.clear()
	sparks.dur.fill(0.0)
	phase = "chart"
	state = State.REPORT
	chart_focus_depth = chart_depth
	selection = 0
	for i in route[chart_depth - 1].size():
		if chart_reachable(chart_depth, i):
			selection = i
			break
	ui_time = 0.0
	fill.visible = false
	lines.zoom = Vector2.ONE

func chart_connected(depth: int, from_branch: int, to_branch: int) -> bool:
	return route[depth - 1].size() == 1 or route[depth].size() == 1 or from_branch == to_branch

func chart_reachable(depth: int, branch: int) -> bool:
	if depth != chart_depth or branch < 0 or branch >= route[depth - 1].size(): return false
	return depth == 1 or chart_connected(depth - 1, route_path[depth - 2], branch)

func move_chart_focus(direction: Vector2i) -> void:
	chart_focus_depth = clampi(chart_focus_depth + direction.x, 1, route.size())
	selection = clampi(selection + direction.y, 0, route[chart_focus_depth - 1].size() - 1)

func update_chart_input() -> void:
	if Input.is_action_just_pressed("move_left"): move_chart_focus(Vector2i.LEFT)
	if Input.is_action_just_pressed("move_right"): move_chart_focus(Vector2i.RIGHT)
	if Input.is_action_just_pressed("move_up"): move_chart_focus(Vector2i.UP)
	if Input.is_action_just_pressed("move_down"): move_chart_focus(Vector2i.DOWN)
	if Input.is_action_just_pressed("confirm"): launch_destination(selection)
	elif Input.is_action_just_pressed("abort"): end_run()

func launch_destination(index: int) -> void:
	if phase != "chart" or chart_focus_depth != chart_depth or not chart_reachable(chart_focus_depth, index): return
	active_destination = route[chart_depth - 1][index]
	route_path.append(index)
	level = chart_depth
	phase = "run"
	pending_clear = false
	zones.clear()
	cargo.clear()
	breach.clear()
	run_victory = false
	capture_percent = 0.0
	displayed_capture = 0.0
	drafts_taken = 0
	for key in cooldowns: cooldowns[key] = 0.0
	boost_time = 0.0
	hardlight_time = 0.0
	freeze_time = 0.0
	containment_time = 0.0
	safe_motion = 0.0
	hot_entry = false
	begin_transit(false)

func end_run() -> void:
	if settled:
		return
	settled = true
	capture_flights.clear()
	banked_salvage = earned_salvage
	progress.salvage += banked_salvage
	progress.salvage_fraction = salvage_fraction
	progress.runs += 1
	if run_victory:
		progress.wins += 1
	save_failed = not progress.write_profile()
	last_result = "SECTOR SECURED" if run_victory else ("HULL LOST" if lives < 0 else "EXPEDITION ENDED")
	if run_victory:
		reward_audio.stream = victory_cue
		reward_audio.play()
		sparks.ripple(Vector2(800, 310), 20.0, 560.0, 1.2, Palette.GREEN)
		sparks.ripple(Vector2(800, 310), 5.0, 340.0, 1.5, Palette.YELLOW)
		sparks.burst(Vector2(800, 310), 100, 420.0, 0.7, 1.4, Palette.GREEN)
	phase = "result"
	state = State.RUN_OVER
	selection = 0
	ui_time = 0.0
	drawing = false
	trail.clear()
	zones.clear()
	cargo.clear()
	breach.clear()
	lines.zoom = Vector2.ONE
	msg_t = 0.0

func pause_run() -> void:
	if phase != "run" or state != State.PLAYING:
		return
	phase = "paused"
	selection = 0
	ui_time = 0.0

func resume_run() -> void:
	phase = "run"
	ui_time = 0.0
	if not drawing:
		draw_armed = false

func choice_delay() -> float:
	if phase == "draft":
		return DRAFT_REVEAL
	if phase == "result" and run_victory:
		return VICTORY_REVEAL
	if phase == "sector_clear": return VICTORY_REVEAL
	return 0.2

func update_choices() -> void:
	if ui_time < choice_delay():
		return
	if phase == "hangar":
		update_track_input()
		return
	if phase == "chart":
		update_chart_input()
		return
	var count := 3 if phase in ["draft", "replace"] else (2 if phase == "paused" else 1)
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("move_left"):
		selection = posmod(selection - 1, count)
	if Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("move_right"):
		selection = (selection + 1) % count
	if Input.is_action_just_pressed("confirm"):
		activate_choice(selection)
	elif Input.is_action_just_pressed("abort"):
		if phase == "draft":
			keep_build()
		elif phase == "replace":
			cancel_replacement()
		elif phase in ["sector_clear", "chart"]:
			end_run()
		elif phase == "paused":
			resume_run()
		elif phase == "hangar":
			leave_mode()
		elif phase == "result":
			activate_choice(0)

func activate_choice(index: int) -> void:
	if phase == "chart":
		launch_destination(index)
	elif phase == "sector_clear":
		continue_expedition()
	elif phase == "replace":
		if index < 0 or index >= owned_cards.size(): return
		replace_id = owned_cards[index]
		var reward_index := int(pending_card.index)
		phase = "draft"
		ui_time = DRAFT_REVEAL
		begin_card_install(reward_index)
	elif phase == "paused":
		if index == 0:
			resume_run()
		elif index == 1:
			end_run()
	elif phase == "draft":
		begin_card_install(index)
	elif phase == "result":
		if ui_time < choice_delay():
			return
		if save_failed:
			save_failed = not progress.write_profile()
			if save_failed:
				return
		go_dock()
	elif phase == "hangar":
		if index == 0:
			start_run()
		elif index == 4:
			leave_mode()
		elif index in [5, 6]:
			hangar_page = "ships" if index == 5 else "upgrades"
			selection = 10 + viewed_ship if index == 5 else track_selection(viewed_track)
			scroll_dragging = false
			if index == 6: reveal_track(viewed_track)
		elif index >= 10 and index <= 12 and hangar_page == "ships":
			purchase_or_select_ship(index - 10)
		elif index in [1, 2, 3, 7, 8, 9]:
			var track_index := index - 1 if index <= 3 else index - 4
			var track: String = Progress.TRACKS[track_index]
			if not progress.track_available(track):
				set_msg("REACH SECTOR %d" % Sectors.CORRUPTION_SECTOR, 1.2)
				return
			if viewed_ranks[track_index] != progress.rank_of(track) + 1:
				return
			if progress.buy(track):
				var purchased := viewed_ranks[track_index]
				viewed_ranks[track_index] = mini(Progress.MAX_RANK, purchased + 1)
				sparks.ripple(track_node_position(track_index, purchased), 5.0, 100.0, 0.45, Palette.GREEN)
				set_msg("%s UPGRADED" % track.to_upper(), 1.0)
			elif progress.rank_of(track) >= Progress.MAX_RANK:
				set_msg("MAX LEVEL", 1.0)
			elif progress.salvage < progress.cost(track):
				set_currency_ask(progress.cost(track) - progress.salvage, false)
			else:
				set_msg("SAVE FAILED - UPGRADE REFUNDED", 2.0)

func leave_mode() -> void:
	fill.visible = false
	exited.emit()

func choice_rect(index: int) -> Rect2:
	if phase == "paused":
		return Rect2(240 + index * 600, 726, 520, 64)
	if phase in ["draft", "install", "replace"]:
		return Rect2(110 + index * 470, 260, 440, 430)
	if phase in ["result", "sector_clear"]:
		return Rect2(540, 700, 520, 66)
	if index == 0:
		return Rect2(1280, 55, 230, 56)
	if index == 4:
		return Rect2(80, 55, 160, 56)
	if index == 5:
		return Rect2(520, 55, 190, 56)
	if index == 6:
		return Rect2(270, 55, 220, 56)
	return Rect2(355, 205 + (index - 1) * 160, 780, 145)

func _input(event: InputEvent) -> void:
	var host := get_parent() as Game
	if host != null and host.state == State.ROGUELITE and phase == "draft":
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and keep_build_rect().has_point(event.position):
			keep_build()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
			reroll_draft()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and reroll_rect().has_point(event.position):
			reroll_draft()
			get_viewport().set_input_as_handled()
			return
	if host != null and host.state == State.ROGUELITE and phase == "run" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var inspect := Rect2(FIELD_X - 10, 780, 190, 44).has_point(event.position)
		for i in owned_cards.size():
			inspect = inspect or run_card_rect(i).has_point(event.position)
		if inspect:
			pause_run()
			get_viewport().set_input_as_handled()
			return
	if host == null or host.state != State.ROGUELITE or phase in ["run", "reward", "install"] or ui_time < choice_delay():
		return
	if phase == "chart":
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if CHART_JUMP.has_point(event.position):
				launch_destination(selection)
			else:
				for depth in range(1, route.size() + 1):
					for i in route[depth - 1].size():
						if chart_position(depth, i).distance_to(event.position) < 42:
							chart_focus_depth = depth
							selection = i
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if phase == "hangar":
			handle_track_mouse(event)
			return
		var count := 3 if phase in ["draft", "replace"] else (2 if phase == "paused" else 1)
		for i in count:
			if choice_rect(i).has_point(event.position):
				selection = i
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					activate_choice(i)
					get_viewport().set_input_as_handled()
				return

# Presentation uses the existing beam renderer and fonts.
func label(text: String, pos: Vector2, size: float = 16, color: Color = Palette.WHITE, align: int = 0) -> void:
	VectorFont.draw(lines, text, pos, size, color, 0.25, 0.05, align)

func paragraph(text: String, pos: Vector2, chars: int = 42, size: float = 15, color: Color = Palette.WHITE) -> void:
	var row := 0
	for part in paragraph_lines(text, chars * size * 0.65, size):
		label(part, pos + Vector2(0, row * (size + 10)), size, color)
		row += 1

func paragraph_lines(text: String, max_width: float, size: float) -> Array[String]:
	var result: Array[String] = []
	for section in text.to_upper().split("\n"):
		var row := ""
		for word in section.split(" ", false):
			var candidate := word if row.is_empty() else row + " " + word
			if not row.is_empty() and VectorFont.width(candidate, size) > max_width:
				result.append(row)
				row = word
			else:
				row = candidate
		result.append(row)
	return result

func button(index: int, text: String) -> void:
	var r := choice_rect(index)
	lines.rect(r, Palette.CYAN if selection == index else Palette.DIM, 0.2, 0.05, 1.0)
	label(("> " if selection == index else "") + text, r.get_center() - Vector2(0, 9), 18, Palette.WHITE if selection == index else Palette.DIM, 1)

func draw() -> void:
	battle_fill.visible = false
	if phase == "paused":
		fill.visible = false
		lines.zoom = Vector2.ONE
		draw_pause()
		return
	if phase in ["run", "reward"]:
		super.draw()
		draw_capture_flights()
		return
	fill.visible = false
	lines.zoom = Vector2.ONE
	if phase not in ["chart", "hangar", "draft", "install", "replace", "sector_clear"] and not (phase == "result" and run_victory):
		label("ROGUELITE", Vector2(80, 70), 30, Palette.CYAN)
	if phase not in ["chart", "draft", "install", "replace", "sector_clear"] and not (phase == "result" and run_victory):
		lines.seg(Vector2(80, 125), Vector2(1510, 125), Palette.DIM)
	match phase:
		"chart": draw_chart()
		"hangar": draw_hangar()
		"draft", "install": draw_draft()
		"replace": draw_replacement()
		"sector_clear": draw_victory()
		"result": draw_result()
	sparks.draw(lines)
	if msg_t > 0.0:
		if msg_currency >= 0:
			draw_currency_caption(msg, msg_amount, false, Vector2(950, 774), "", false, Palette.RED)
		else:
			label(msg, Vector2(950, 766), 15, Palette.YELLOW, 1)

## Reuse the board currency glyph, with aligned amounts at the hangar and reward sizes.
func draw_salvage(amount: String, pos: Vector2, text_size := 14.0, align := 0, affordable := true) -> void:
	var icon_scale := text_size / 14.0
	var width := 32.0 * icon_scale + VectorFont.width(amount, text_size)
	var left := pos.x - width * float(align) * 0.5
	draw_dock_currency(Vector2(left + 10 * icon_scale, pos.y), amount, false, affordable, text_size)

func draw_hangar() -> void:
	for index in [4, 6, 5, 0]:
		button(index, {4: "BACK", 0: "LAUNCH", 6: "UPGRADES", 5: "SHIPS"}[index])
	var active_tab := choice_rect(5 if hangar_page == "ships" else 6)
	lines.seg(Vector2(active_tab.position.x, 120), Vector2(active_tab.end.x, 120), Palette.CYAN, 0.0, 0.0, 2.0)
	lines.seg(Vector2(80, 762), Vector2(1510, 762), Palette.DIM)
	draw_salvage(str(progress.salvage), Vector2(80, 804), 24)
	if hangar_page == "ships":
		draw_ship_shop()
		return
	label(progress.selected_ship.to_upper(), Vector2(80, 210), 25)
	for path in Hulls.paths(progress.selected_ship, Vector2(195, 408), 85.0, 0.0, 0.4):
		lines.polyline(path, false, Palette.CYAN, 0.3, 0.05, 1.2)
	paragraph(ship_controls(progress.selected_ship), Vector2(80, 555), 25, 13, Palette.DIM)
	lines.clip_y = Vector2(TRACK_VIEW.position.y, TRACK_VIEW.end.y)
	for i in visible_tracks():
		draw_upgrade_track(i)
	lines.clip_y = Vector2(-INF, INF)
	lines.seg(scrollbar_rect().position + Vector2(4, 0), scrollbar_rect().end - Vector2(4, 0), Palette.DIM)
	lines.rect(scrollbar_thumb(), Palette.CYAN if scroll_dragging else Palette.WHITE)
	lines.seg(Vector2(1160, 200), Vector2(1160, 730), Palette.DIM)
	draw_node_details()
	label("OWNED", Vector2(397, 710), 12, Palette.GREEN)
	label("NEXT", Vector2(583, 710), 12, Palette.YELLOW)
	label("LOCKED", Vector2(744, 710), 12, Palette.DIM)
	lines.circle(Vector2(376, 716), 7, Palette.GREEN)
	lines.circle(Vector2(562, 716), 7, Palette.YELLOW)
	lines.circle(Vector2(723, 716), 7, Palette.DIM)
	var enter_action: String = {0: "LAUNCH", 4: "BACK", 5: "SHIPS", 6: "UPGRADES"}.get(selection, "BUY")
	label("ARROWS: BROWSE    ENTER: %s    ESC: BACK" % enter_action, Vector2(950, 815), 13, Palette.DIM, 1)

func ship_controls(id: String) -> String:
	match id:
		"lancer": return "ARROWS / WASD: AIM\nSPACE: LANCE + RIDE"
		"sapper": return "ARROWS / WASD: MOVE\nHOLD SPACE: CHARGE\nRELEASE: DETONATE"
	return "ARROWS / WASD: MOVE\nSPACE: DRAW\nSHIFT: SLOW DRAW"

func ship_rect(index: int) -> Rect2:
	return Rect2(80 + index * 490, 185, 450, 515)

func ship_action_rect(index: int) -> Rect2:
	return Rect2(110 + index * 490, 620, 390, 56)

func purchase_or_select_ship(index: int) -> void:
	if index < 0 or index >= Progress.SHIPS.size():
		return
	viewed_ship = index
	selection = 10 + index
	var id: String = Progress.SHIPS[index]
	var owned: bool = progress.owns_ship(id)
	if owned and progress.selected_ship == id:
		return
	if not owned and progress.salvage < Progress.SHIP_PRICE:
		set_currency_ask(Progress.SHIP_PRICE - progress.salvage, false)
		return
	var success: bool = progress.select_ship(id) if owned else progress.buy_ship(id)
	if not success:
		set_msg("SAVE FAILED - TRY AGAIN" if owned else "SAVE FAILED - PURCHASE REFUNDED", 2.0)
		return
	set_msg("%s %s" % [id.to_upper(), "SELECTED" if owned else "UNLOCKED"], 1.4)
	sparks.ripple(ship_rect(index).get_center(), 25.0, 340.0, 0.6, Palette.GREEN)
	if not owned:
		reward_audio.stream = install_cue
		reward_audio.play()
		sparks.burst(ship_rect(index).get_center(), 40, 220.0, 0.7, 0.6, Palette.GREEN)

func draw_ship_shop() -> void:
	for i in Progress.SHIPS.size():
		var id: String = Progress.SHIPS[i]
		var r := ship_rect(i)
		var active: bool = progress.selected_ship == id
		var owned: bool = progress.owns_ship(id)
		var color := Palette.CYAN if owned else Palette.DIM
		lines.rect(r, Palette.WHITE if selection == 10 + i else Palette.DIM, 0.0, 0.0, 0.7)
		label(id.to_upper(), r.position + Vector2(30, 30), 25, Palette.WHITE if owned else Palette.DIM)
		label("ACTIVE" if active else ("OWNED" if owned else "LOCKED"), r.position + Vector2(30, 75), 12, Palette.GREEN if active else color)
		for path in Hulls.paths(id, r.position + Vector2(225, 225), 77.0, 0.0, 0.4):
			lines.polyline(path, false, color, 0.3, 0.05, 1.2)
		label(["DRAW AND ENCLOSE", "FIRE A LINE. RIDE IT.", "CHARGE. DETONATE."][i], r.position + Vector2(225, 357), 17, Palette.WHITE, 1)
		var action := ship_action_rect(i)
		var affordable: bool = progress.salvage >= Progress.SHIP_PRICE
		lines.rect(action, Palette.GREEN if active else (Palette.CYAN if owned else (Palette.YELLOW if affordable else Palette.RED)))
		if owned:
			label("SELECTED" if active else "SELECT", action.position + Vector2(195, 19), 16, Palette.GREEN if active else Palette.CYAN, 1)
		else:
			draw_currency_caption("UNLOCK", str(Progress.SHIP_PRICE), false, action.get_center(), "", affordable, Palette.CYAN if affordable else Palette.RED)
	label("UPGRADES APPLY TO EVERY SHIP", Vector2(800, 724), 13, Palette.DIM, 1)
	label("ARROWS: BROWSE    ENTER: SELECT / UNLOCK    ESC: BACK", Vector2(950, 815), 13, Palette.DIM, 1)

func track_node_position(track_index: int, rank: int) -> Vector2:
	return Vector2(386 + (rank - 1) * 80, TRACK_VIEW.position.y + 75 + track_index * TRACK_ROW - track_scroll)

func track_node_rect(track_index: int, rank: int) -> Rect2:
	return Rect2(track_node_position(track_index, rank) - Vector2(32, 32), Vector2(64, 82))

func upgrade_button_rect() -> Rect2:
	return Rect2(1195, 635, 315, 64)

func node_state(track_index: int, rank: int) -> String:
	if not progress.track_available(Progress.TRACKS[track_index]): return "LOCKED"
	var current: int = progress.rank_of(Progress.TRACKS[track_index])
	return "OWNED" if rank <= current else ("NEXT" if rank == current + 1 else "LOCKED")

func visible_tracks() -> Array[int]:
	var tracks: Array[int] = []
	for i in Progress.TRACKS.size():
		var top := TRACK_VIEW.position.y + i * TRACK_ROW - track_scroll
		if top < TRACK_VIEW.end.y and top + TRACK_ROW > TRACK_VIEW.position.y: tracks.append(i)
	return tracks

func max_track_scroll() -> float:
	return maxf(0.0, Progress.TRACKS.size() * TRACK_ROW - TRACK_VIEW.size.y)

func scrollbar_rect() -> Rect2:
	return Rect2(1146, TRACK_VIEW.position.y, 8, TRACK_VIEW.size.y)

func scrollbar_thumb() -> Rect2:
	var bar := scrollbar_rect()
	var height := bar.size.y * TRACK_VIEW.size.y / (Progress.TRACKS.size() * TRACK_ROW)
	return Rect2(bar.position + Vector2(0, (bar.size.y - height) * track_scroll / maxf(1.0, max_track_scroll())), Vector2(8, height))

func reveal_track(index: int) -> void:
	track_scroll = clampf(track_scroll, (index + 1) * TRACK_ROW - TRACK_VIEW.size.y, index * TRACK_ROW)
	track_scroll = clampf(track_scroll, 0.0, max_track_scroll())

func track_selection(index: int) -> int:
	return index + 1 if index < 3 else index + 4

func focus_track(index: int) -> void:
	selection = track_selection(index)
	viewed_track = index
	reveal_track(index)

func browse_track(row_delta: int, rank_delta: int) -> void:
	if row_delta != 0:
		var order: Array[int] = []
		for i in Progress.TRACKS.size(): order.append(track_selection(i))
		order.append_array([4, 6, 5, 0])
		selection = order[posmod(order.find(selection) + row_delta, order.size())]
		if selection in [1, 2, 3, 7, 8, 9]:
			viewed_track = selection - 1 if selection <= 3 else selection - 4
			reveal_track(viewed_track)
	if rank_delta != 0:
		if selection in [1, 2, 3, 7, 8, 9]:
			viewed_ranks[viewed_track] = clampi(viewed_ranks[viewed_track] + rank_delta, 1, Progress.MAX_RANK)
			reveal_track(viewed_track)
		elif selection in [4, 6, 5, 0]:
			var nav := [4, 6, 5, 0]
			selection = nav[posmod(nav.find(selection) + rank_delta, nav.size())]

func update_track_input() -> void:
	if hangar_page == "ships":
		update_ship_input()
		return
	if Input.is_action_just_pressed("move_up"):
		browse_track(-1, 0)
	if Input.is_action_just_pressed("move_down"):
		browse_track(1, 0)
	if Input.is_action_just_pressed("move_left"):
		browse_track(0, -1)
	if Input.is_action_just_pressed("move_right"):
		browse_track(0, 1)
	if Input.is_action_just_pressed("confirm"):
		activate_choice(selection)
	elif Input.is_action_just_pressed("abort"):
		leave_mode()

func handle_track_mouse(event: InputEvent) -> void:
	var click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	if hangar_page == "upgrades" and handle_track_scroll(event): return
	for i in [4, 6, 5, 0]:
		if choice_rect(i).has_point(event.position):
			selection = i
			if click:
				activate_choice(i)
				get_viewport().set_input_as_handled()
			return
	if hangar_page == "ships":
		for i in Progress.SHIPS.size():
			if ship_rect(i).has_point(event.position):
				selection = 10 + i
				viewed_ship = i
				if click and ship_action_rect(i).has_point(event.position):
					purchase_or_select_ship(i)
					get_viewport().set_input_as_handled()
				return
		return
	for i in visible_tracks():
		for rank in range(1, Progress.MAX_RANK + 1):
			if TRACK_VIEW.has_point(event.position) and track_node_rect(i, rank).has_point(event.position):
				if click:
					focus_track(i)
					viewed_ranks[i] = rank
					get_viewport().set_input_as_handled()
				return
	if upgrade_button_rect().has_point(event.position):
		focus_track(viewed_track)
		if click:
			activate_choice(selection)
			get_viewport().set_input_as_handled()
		return

func handle_track_scroll(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			scroll_dragging = false
		elif event.pressed and TRACK_VIEW.grow(12).has_point(event.position):
			if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				track_scroll = clampf(track_scroll + (48.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -48.0) * maxf(1.0, event.factor), 0.0, max_track_scroll())
				get_viewport().set_input_as_handled()
				return true
			if event.button_index == MOUSE_BUTTON_LEFT and scrollbar_rect().grow(8).has_point(event.position):
				scroll_grab = event.position.y - scrollbar_thumb().position.y if scrollbar_thumb().has_point(event.position) else scrollbar_thumb().size.y * 0.5
				scroll_dragging = true
	if scroll_dragging and (event is InputEventMouseMotion or event is InputEventMouseButton):
		var travel := scrollbar_rect().size.y - scrollbar_thumb().size.y
		track_scroll = clampf((event.position.y - scrollbar_rect().position.y - scroll_grab) / maxf(1.0, travel), 0.0, 1.0) * max_track_scroll()
		get_viewport().set_input_as_handled()
		return true
	return false

func update_ship_input() -> void:
	var dx := int(Input.is_action_just_pressed("move_right")) - int(Input.is_action_just_pressed("move_left"))
	if selection >= 10:
		viewed_ship = posmod(viewed_ship + dx, Progress.SHIPS.size())
		selection = 10 + viewed_ship
		if Input.is_action_just_pressed("move_up"):
			selection = 5
	else:
		browse_track(0, dx)
		if Input.is_action_just_pressed("move_down"):
			selection = 10 + viewed_ship
	if Input.is_action_just_pressed("confirm"):
		activate_choice(selection)
	elif Input.is_action_just_pressed("abort"):
		activate_choice(6)

func subsystem_icon(track_index: int, pos: Vector2, color: Color, scale: float = 1.0) -> void:
	var points: PackedVector2Array
	match track_index:
		0:
			points = PackedVector2Array([Vector2(-8, 7), Vector2(0, -8), Vector2(8, 7), Vector2(0, 3)])
		1:
			points = PackedVector2Array([Vector2(-8, -7), Vector2(8, -7), Vector2(7, 3), Vector2(0, 9), Vector2(-7, 3)])
		3:
			lines.circle(pos, 4 * scale, color, 16)
			points = PackedVector2Array([Vector2(-11, 0), Vector2(0, -8), Vector2(11, 0), Vector2(0, 8)])
		4:
			points = PackedVector2Array([Vector2(-10, 0), Vector2(-5, -9), Vector2(5, -9), Vector2(10, 0), Vector2(5, 9), Vector2(-5, 9)])
			lines.circle(pos, 2 * scale, Palette.FULLBRIGHT, 6)
		5:
			points = PackedVector2Array([Vector2(-10, -9), Vector2(10, -9), Vector2(10, 9), Vector2(-10, 9)])
			lines.seg(pos + Vector2(-5, 0) * scale, pos + Vector2(5, 0) * scale, color)
		_:
			points = PackedVector2Array([Vector2(0, -9), Vector2(-7, 1), Vector2(0, 1), Vector2(-2, 9), Vector2(8, -3), Vector2(1, -3)])
	for i in points.size():
		points[i] = pos + points[i] * scale
	lines.polyline(points, true, color, 0.1, 0.0, 1.0)

func milestone_name(track_index: int, rank := 5) -> String:
	return (["OVERDRIVE", "REINFORCED HULL", "RAPID REFUND", "DOUBLE SCAN", "SALVAGE FIELD", "PURIFY"] if rank == 10 else ["HOT ENTRY", "SPARE HULL", "CAPTURE REFUND", "RESCAN", "EXTRA PICKUP", "CLEAN BORDER"])[track_index]

func milestone_detail(index: int, rank: int) -> String:
	var verb := "CHARGE" if progress.selected_ship == "sapper" else ("LANCE" if progress.selected_ship == "lancer" else "CUT")
	return ["MOVE SAFE 2S\nNEXT %s +30%% / %dS" % [verb, 3 if rank == 10 else 2], "+1 STARTING HULL", "CAPTURE: -%dS COOLDOWN" % (rank / 5), "%d REROLLS PER SECTOR" % (rank / 5), "+%d PICKUPS PER SECTOR" % (rank / 5), "CAPTURE CLEANSES\n%d CELLS BEYOND BORDER" % (rank / 5 * 2)][index]

func draw_upgrade_track(track_index: int) -> void:
	var track: String = Progress.TRACKS[track_index]
	var current: int = progress.rank_of(track)
	var selected := selection == track_selection(track_index)
	var y := TRACK_VIEW.position.y + 10 + track_index * TRACK_ROW - track_scroll
	label(track.to_upper(), Vector2(355, y), 22, Palette.WHITE if selected else Palette.CYAN)
	label("%d / 10" % current, Vector2(1130, y + 4), 15, Palette.DIM, 2)
	for rank in range(1, Progress.MAX_RANK + 1):
		var pos := track_node_position(track_index, rank)
		var status := node_state(track_index, rank)
		var color := Palette.GREEN if status == "OWNED" else (Palette.YELLOW if status == "NEXT" else Palette.DIM)
		var milestone := rank in [5, 10]
		var radius := 26.0 if milestone else 19.0
		if rank < Progress.MAX_RANK:
			var end := track_node_position(track_index, rank + 1)
			lines.seg(pos + Vector2(radius + 4, 0), end - Vector2(30 if rank == 4 else 23, 0), Palette.GREEN if rank < current else Palette.DIM, 0.1, 0.0, 0.8)
		if milestone:
			lines.polyline(PackedVector2Array([pos + Vector2(0, -radius), pos + Vector2(radius, 0), pos + Vector2(0, radius), pos + Vector2(-radius, 0)]), true, color)
		else:
			lines.circle(pos, radius, color, 20, 0.1, 0.0, 1.2)
		if status == "OWNED":
			lines.polyline(PackedVector2Array([pos + Vector2(-7, 0), pos + Vector2(-2, 5), pos + Vector2(8, -6)]), false, color, 0.1, 0.0, 1.3)
		else:
			subsystem_icon(track_index, pos, color)
		if selected and viewed_ranks[track_index] == rank:
			lines.rect(Rect2(pos - Vector2(32, 32), Vector2(64, 64)), Palette.WHITE, 0.1, 0.0, 1.1)
		label(str(rank), pos + Vector2(0, 39), 12, color, 1)
		if rank == 5:
			label(milestone_name(track_index), pos + Vector2(0, 65), 11, Palette.GREEN if status == "OWNED" else Palette.CYAN, 1)

func node_effect_lines(track_index: int, rank: int) -> Array[String]:
	var effects: Array[String] = []
	var before := rank - 1
	match track_index:
		0: effects.assign(["MOVEMENT SPEED", "%d%% > %d%%" % [100 + before * 2, 100 + rank * 2]])
		1: effects.assign(["RESPAWN SHIELD", "%.1fS > %.1fS" % [2.5 + before * 0.5, 2.5 + rank * 0.5], "AFTER LOSING A HULL"])
		2:
			if progress.selected_ship == "sapper":
				effects.assign(["BLAST CHARGE SPEED", "%d%% > %d%%" % [100 + before * 3, 100 + rank * 3], "ALSO: ABILITY RECHARGE"])
			else:
				var base := LANCE_CD_BASE if progress.selected_ship == "lancer" else 14.0
				effects.assign(["LANCE RECHARGE" if progress.selected_ship == "lancer" else "ABILITY RECHARGE", "%.1fS > %.1fS" % [base / (1 + before * 0.03), base / (1 + rank * 0.03)]])
				if progress.selected_ship == "surveyor": effects.append("EXAMPLE: AFTERBURNER")
		3: effects.assign(["UPGRADED DRAFT CHANCE", "%d%% > %d%%" % [before * 2, rank * 2]])
		4: effects.assign(["BONUS SALVAGE", "+%d%% > +%d%%" % [before * 2, rank * 2], "CARRIES BETWEEN RUNS"])
		5: effects.assign(["CORRUPTION TOLERANCE", "%.1fS > %.1fS" % [4.0 / (1 - before * 0.03), 4.0 / (1 - rank * 0.03)], "TIME BEFORE OVERLOAD"])
	return effects

func draw_node_details() -> void:
	var i := viewed_track
	var rank := viewed_ranks[i]
	var status := node_state(i, rank)
	var color := Palette.GREEN if status == "OWNED" else (Palette.YELLOW if status == "NEXT" else Palette.DIM)
	label("%s / %02d" % [Progress.TRACKS[i].to_upper(), rank], Vector2(1195, 210), 18)
	label(status, Vector2(1195, 250), 13, color)
	subsystem_icon(i, Vector2(1345, 322), color, 3.0)
	var effects := node_effect_lines(i, rank)
	for row in effects.size():
		label(effects[row], Vector2(1195, 385 + row * 32), 15, Palette.WHITE if row == 0 else Palette.DIM)
	if rank in [5, 10]:
		label(milestone_name(i, rank), Vector2(1195, 500), 18, Palette.CYAN)
		paragraph(milestone_detail(i, rank), Vector2(1195, 541), 31, 14, Palette.CYAN)
	if status != "OWNED":
		draw_salvage(str(progress.node_cost(rank)), Vector2(1195, 608), 16, 0, progress.salvage >= progress.node_cost(rank))
	var action := "UPGRADE"
	if status == "OWNED":
		action = "OWNED"
	elif status == "LOCKED":
		action = "REQUIRES RANK %d" % (rank - 1) if progress.track_available(Progress.TRACKS[i]) else "REACH SECTOR %d" % Sectors.CORRUPTION_SECTOR
	var rect := upgrade_button_rect()
	var shortfall: bool = status == "NEXT" and progress.salvage < progress.node_cost(rank)
	lines.rect(rect, Palette.RED if shortfall else (color if status == "NEXT" else Palette.DIM))
	if shortfall:
		draw_currency_caption("NEED", str(progress.node_cost(rank) - progress.salvage), false, rect.get_center(), "", false, Palette.RED)
	else:
		label(action, rect.position + Vector2(20, 24), 16, color)

func card_color(id: String) -> Color:
	if id in ["afterburner", "slipstream", "compression", "dash", "leap"]:
		return Palette.ORANGE
	if id in ["ion", "stasis", "loop"]:
		return Palette.PURPLE
	return Palette.CYAN

func draw_card_icon(id: String, center_at: Vector2, color: Color, scale_at := 1.0) -> void:
	var paths: Array = []
	match id:
		"hardening": paths = [[-42, -36, -42, 36, 42, 36, 42, -36, -42, -36], [-42, 0, 42, 0], [0, -36, 0, 0], [-20, 0, -20, 36], [20, 0, 20, 36]]
		"leap": paths = [[-48, 28, -25, -15, 0, -36, 25, -15, 48, 28], [18, 22, 48, 28, 45, -3], [-48, 42, -30, 42], [30, 42, 48, 42]]
		"dash": paths = [[-12, -32, 34, 0, -12, 32], [-55, -22, -25, -22], [-65, 0, -30, 0], [-55, 22, -25, 22]]
		"afterburner":
			paths = [[-28, 30, 0, -42, 28, 30, 0, 16, -28, 30], [-13, 30, 0, 54, 13, 30]]
		"hardlight", "phase":
			paths = [[0, -48, 38, -30, 30, 18, 0, 48, -30, 18, -38, -30, 0, -48], [-16, 0, -2, 15, 23, -16]]
			if id == "phase":
				paths.append([-55, 30, 55, -30])
		"anchor":
			paths = [[0, -32, 0, 44, -34, 16, -34, 0], [0, 44, 34, 16, 34, 0], [-22, -17, 22, -17]]
			lines.circle(center_at + Vector2(0, -40) * scale_at, 10 * scale_at, color)
		"ion":
			paths = [[12, -48, -24, 4, 0, 4, -12, 48, 30, -10, 6, -10, 12, -48], [-58, 15, -38, 15], [38, -15, 58, -15]]
		"slipstream":
			paths = [[-48, -30, -12, 0, -48, 30], [-12, -30, 24, 0, -12, 30], [24, -30, 60, 0, 24, 30]]
		"loop":
			paths = [[-38, 8, -38, -24, 0, -44, 38, -24, 38, 8, 20, -8], [38, -8, 38, 24, 0, 44, -38, 24, -38, -8, -20, 8]]
		"compression":
			paths = [[-52, -30, -22, 0, -52, 30], [52, -30, 22, 0, 52, 30], [0, -26, 15, 0, 0, 26, -15, 0, 0, -26]]
		"stasis":
			for k in 6:
				var v := Vector2.from_angle(k * TAU / 6.0)
				lines.seg(center_at, center_at + v * 48 * scale_at, color, 0.1, 0.0, 1.6)
				for sign_at in [-1, 1]:
					lines.seg(center_at + v * 29 * scale_at, center_at + (v * 19 + v.orthogonal() * 12 * sign_at) * scale_at, color)
		"clean":
			paths = [[0, -48, 10, -10, 45, 0, 10, 10, 0, 48, -10, 10, -45, 0, -10, -10, 0, -48]]
		"containment":
			paths = [[-38, -38, 38, -38, 38, 38, -38, 38, -38, -38], [-10, -20, -10, 20], [10, -20, 10, 20]]
		"harvest":
			paths = [[0, -45, 38, -22, 38, 22, 0, 45, -38, 22, -38, -22, 0, -45], [-20, 0, 20, 0], [0, -20, 0, 20]]
	for coords in paths:
		var points := PackedVector2Array()
		for j in range(0, coords.size(), 2):
			points.append(center_at + Vector2(coords[j], coords[j + 1]) * scale_at)
		lines.polyline(points, false, color, 0.1, 0.0, 1.8)

func draw_draft() -> void:
	var installing := phase == "install"
	label("INSTALLED" if installing else ("MOVEMENT" if opening_draft_pending else "POWER UP"), Vector2(800, 130), 38, Palette.GREEN if installing else Palette.WHITE, 1)
	for j in draft_capture.size():
		var dot := Vector2(800 + (j - (draft_capture.size() - 1) * 0.5) * 24, 188)
		lines.circle(dot, 5, Palette.GREEN if j < drafts_taken else (Palette.YELLOW if j == drafts_taken else Palette.DIM), 4)
	# One radial burst opens the reveal; the cards assemble from narrow beams.
	var burst := clampf(ui_time / 0.7, 0.0, 1.0)
	if not installing and burst < 1.0:
		for j in 24:
			var ray := Vector2.from_angle(j * TAU / 24.0)
			lines.seg(Vector2(800, 440) + ray * (60 + burst * 360), Vector2(800, 440) + ray * (100 + burst * 400), Color(Palette.CYAN, (1.0 - burst) * 0.65), 0.0, 0.0, 1.5)
	for i in offers.size():
		var card := offers[i]
		var r := choice_rect(i)
		var reveal := 1.0 if installing else clampf((ui_time - i * 0.12) / 0.48, 0.0, 1.0)
		if reveal <= 0.0:
			continue
		var color := card_color(card.id)
		var selected := selection == i
		var opacity := 0.25 if installing and not selected else 1.0
		var ease := 1.0 - pow(1.0 - reveal, 3)
		var width := r.size.x * ease
		var panel := Rect2(r.get_center().x - width / 2, r.position.y, width, r.size.y)
		lines.rect(panel, Color(color if selected else Palette.DIM, opacity), 0.1, 0.0, 1.6 if selected else 0.8)
		if reveal < 0.65:
			continue
		var center_at := Vector2(r.get_center().x, r.position.y + 135)
		lines.circle(center_at, 79, Color(color, 0.25 * opacity), 48)
		draw_card_icon(card.id, center_at, Color(color, opacity), 1.15 + (0.15 * sin(ui_time * PI / 0.45) if installing and selected else 0.0))
		label(card.kind, r.position + Vector2(24, 25), 12, Color(color, opacity))
		label("%s / %s" % [card.get("action", "NEW"), ["I", "II", "III"][int(card.get("rank", 1)) - 1]], Vector2(r.end.x - 24, r.position.y + 25), 12, Color(Palette.GREEN if int(card.get("rank", 1)) > 1 else color, opacity), 2)
		label(card.name, Vector2(center_at.x, r.position.y + 243), 23, Color(Palette.WHITE, opacity), 1)
		var rows := paragraph_lines(card.desc, 390, 14)
		for row in rows.size():
			label(rows[row], Vector2(center_at.x, r.position.y + 289 + row * 21), 14, Color(Palette.WHITE, opacity), 1)
		label(card.stats, Vector2(center_at.x, r.position.y + 354), 13, Color(color, opacity), 1)
		if not card.detail.is_empty():
			label(card.detail, Vector2(center_at.x, r.position.y + 383), 12, Color(Palette.DIM, opacity), 1)
		if selected:
			lines.seg(r.position + Vector2(22, 414), r.position + Vector2(r.size.x - 22, 414), Palette.GREEN if installing else color, 0.0, 0.0, 2.0)
	if not installing and ui_time >= DRAFT_REVEAL:
		label("CHOOSE ONE", Vector2(800, 751), 18, Palette.WHITE, 1)
		label("ARROWS + ENTER / CLICK", Vector2(800, 803), 12, Palette.DIM, 1)
		if owned_cards.size() == 3:
			lines.rect(keep_build_rect(), Palette.DIM)
			label("ESC: KEEP BUILD", keep_build_rect().position + Vector2(16, 14), 13, Palette.DIM)
		if rerolls_left > 0 and not opening_draft_pending:
			lines.rect(reroll_rect(), Palette.CYAN)
			label("R: RESCAN %d" % rerolls_left, reroll_rect().position + Vector2(16, 14), 13, Palette.CYAN)

func reroll_rect() -> Rect2:
	return Rect2(1260, 760, 240, 48)

func keep_build_rect() -> Rect2:
	return Rect2(110, 760, 240, 48)

func cancel_replacement() -> void:
	pending_card.clear()
	replace_id = ""
	phase = "draft"
	selection = 0
	ui_time = DRAFT_REVEAL

func draw_replacement() -> void:
	var reward: Dictionary = offers[int(pending_card.index)]
	label("MAKE ROOM FOR " + reward.name, Vector2(800, 130), 28, Palette.WHITE, 1)
	label("CHOOSE A SYSTEM TO REPLACE", Vector2(800, 200), 16, Palette.DIM, 1)
	for i in owned_cards.size():
		var card := card_definition(owned_cards[i])
		var r := choice_rect(i)
		var color := Palette.YELLOW if selection == i else Palette.DIM
		lines.rect(r, color)
		draw_card_icon(card.id, r.position + Vector2(220, 135), card_color(card.id))
		label(card.name, r.position + Vector2(220, 260), 23, Palette.WHITE, 1)
		label("RANK " + ["I", "II", "III"][card_rank(card.id) - 1], r.position + Vector2(220, 315), 14, Palette.DIM, 1)
		label("REPLACE", r.position + Vector2(220, 380), 16, color, 1)
	label("ENTER: REPLACE    ESC: KEEP CURRENT BUILD", Vector2(800, 795), 14, Palette.DIM, 1)

func draw_result() -> void:
	if run_victory:
		draw_victory()
		return
	label(last_result, Vector2(800, 200), 40, Palette.GREEN if run_victory else Palette.YELLOW, 1)
	label("%d%% CLAIMED / %d CAPTURES / %d SYSTEMS" % [int(claimed_frac() * 100), capture_count, owned_cards.size()], Vector2(800, 285), 19, Palette.WHITE, 1)
	draw_salvage("+%d" % banked_salvage, Vector2(800, 405), 38, 1)
	label("%d PICKUPS" % run_nodes, Vector2(800, 452), 16, Palette.DIM, 1)
	draw_currency_caption("BALANCE", str(progress.salvage), false, Vector2(800, 551))
	button(0, "RETRY SAVE" if save_failed else "RETURN TO HANGAR")
	if save_failed:
		label("SAVE FAILED - PROGRESS IS HELD IN MEMORY", Vector2(800, 818), 16, Palette.YELLOW, 1)

func victory_salvage_shown() -> int:
	var t := clampf((ui_time - 0.7) / 1.1, 0.0, 1.0)
	var amount := earned_salvage - sector_salvage_start if phase == "sector_clear" else banked_salvage
	return roundi(amount * (1.0 - pow(1.0 - t, 3)))

func draw_victory() -> void:
	var crest := Vector2(800, 310)
	var arrive := clampf(ui_time / 0.5, 0.0, 1.0)
	var scale_at := 0.6 + 0.4 * (1.0 - pow(1.0 - arrive, 3))
	var color := Color(Palette.GREEN, arrive)
	# The Surveyor becomes the medal; paired laurels assemble around it.
	for path in Hulls.paths(ship.id, crest, 67.0 * scale_at, 0.0, 0.0):
		lines.polyline(path, false, Color(Palette.WHITE, arrive), 0.1, 0.0, 1.5)
	for side in [-1, 1]:
		for j in 7:
			var leaf := clampf((ui_time - j * 0.055) / 0.18, 0.0, 1.0)
			var angle := deg_to_rad(25.0 + j * 20.0)
			var tip := crest + Vector2(side * sin(angle) * 133, cos(angle) * 122)
			var stem := crest + Vector2(side * sin(angle) * 108, cos(angle) * 105)
			lines.seg(stem, stem.lerp(tip, leaf), Color(Palette.YELLOW, leaf), 0.0, 0.0, 2.0)
	lines.circle(crest, 89 * scale_at, Color(Palette.GREEN, arrive * 0.35), 64)
	if ui_time < 1.15:
		var pulse := ui_time / 1.15
		for j in 32:
			var direction := Vector2.from_angle(j * TAU / 32.0)
			lines.seg(crest + direction * (145 + pulse * 270), crest + direction * (175 + pulse * 350), Color(Palette.YELLOW, (1.0 - pulse) * 0.7), 0.0, 0.0, 1.4)
	label("SECTOR CLEAR" if phase == "sector_clear" else "EXPEDITION COMPLETE", Vector2(800, 116), 42, color, 1)
	if ui_time >= 0.5:
		draw_salvage("+%d" % victory_salvage_shown(), Vector2(800, 533), 58, 1)
	if ui_time >= 1.8 and phase != "sector_clear":
		label("%d SECTORS SECURED" % run_sectors, Vector2(800, 630), 16, Palette.DIM, 1)
	if ui_time >= VICTORY_REVEAL:
		button(0, "STAR CHART" if phase == "sector_clear" else ("RETRY SAVE" if save_failed else "HANGAR"))
		if phase == "sector_clear": label("ESC: BANK AND EXIT", Vector2(800, 810), 13, Palette.DIM, 1)
		if save_failed:
			label("SAVE FAILED - PROGRESS IS HELD IN MEMORY", Vector2(800, 818), 16, Palette.YELLOW, 1)

func draw_intro_frame(_rect: Rect2, _progress: float) -> void:
	pass # Trace only the playable coast during entry, just as during the run.

func draw_field_frame(_rect: Rect2) -> void:
	pass # The actual coast supplies the arena outline; the fixed field needs no extra frame.

func draw_panel_header() -> void:
	pass # Readouts stay in the top and bottom bands, outside the rectangular arenas.

func run_card_rect(index: int) -> Rect2:
	return Rect2(800 - (maxi(1, owned_cards.size()) * 100 - 32) * 0.5 + index * 100, 758, 68, 68)

func draw_hud() -> void:
	hud_label("%s / %02d-%02d" % [ship.name, level, sector_limit], Vector2(FIELD_X, 61), 18)
	draw_hull_icons(Vector2(1254, 70), maxi(0, lives + 1))
	draw_dock_currency(Vector2(1374, 70), str(earned_salvage), false)
	draw_draft_meter()
	hud_label("ESC  PAUSE", Vector2(FIELD_X, 794), 12, Palette.DIM)
	for i in owned_cards.size():
		var id: String = owned_cards[i]
		var r := run_card_rect(i)
		var color := card_color(id)
		var cooldown := float(cooldowns.get(id, 0.0))
		var active := boost_time if id == "afterburner" else (hardlight_time if id == "hardlight" else (hardening_time if id == "hardening" else (dash_time if id == "dash" else 0.0)))
		if cooldown > 0.0 and active <= 0.0:
			color = Palette.DIM
		draw_card_icon(id, r.get_center(), color, 0.48)
		if card_rank(id) > 1:
			hud_label(["I", "II", "III"][card_rank(id) - 1], r.position + Vector2(50, -10), 11, Palette.GREEN)
		if id in ["afterburner", "hardlight"] or Cards.OPENING.has(id):
			lines.rect(r, Color(color, 0.5), 0.0, 0.0, 0.7)
			hud_label("E" if Cards.SECONDARY.has(id) else "Q", r.position + Vector2(0, 80), 13)
		if active > 0.0 or cooldown > 0.0:
			hud_label("%.1fS" % (active if active > 0.0 else cooldown), r.position + Vector2(24, 80), 12, Palette.GREEN if active > 0.0 else Palette.DIM)
	if corruption_active:
		# Reserved for later sectors in the bottom HUD band.
			hud_label("EXPOSURE %.1f/4S" % exposure, Vector2(1080, 794), 13, Palette.MAGENTA)

func draw_pause() -> void:
	label("PAUSED", Vector2(240, 100), 34)
	hud_label("CONTROLS", Vector2(240, 191), 16, Palette.CYAN)
	paragraph(ship_controls(ship.id), Vector2(240, 235), 36, 15)
	hud_label("PERMANENT UPGRADES", Vector2(240, 404), 16, Palette.CYAN)
	for i in Progress.TRACKS.size():
		var track: String = Progress.TRACKS[i]
		hud_label("%s  %d" % [track.to_upper(), progress.rank_of(track)], Vector2(240, 450 + i * 30), 15)
	for i in owned_cards.size():
		var card := card_definition(owned_cards[i])
		var y := 190.0 + i * 160
		draw_card_icon(card.id, Vector2(880, y + 36), card_color(card.id), 0.5)
		hud_label(card.name, Vector2(940, y), 18)
		paragraph(card.desc, Vector2(940, y + 36), 39, 14)
		hud_label(card.stats, Vector2(940, y + 91), 12, card_color(card.id))
		if not card.detail.is_empty():
			hud_label(card.detail, Vector2(940, y + 119), 12, Palette.DIM)
	button(0, "RESUME")
	button(1, "END EXPEDITION")

func grid_changed() -> void:
	super.grid_changed()
	corruption_visual_dirty = true

func rebuild_corruption_strokes() -> void:
	corruption_strokes.clear()
	for y in range(1, grid_height - 1):
		var start := -1
		var row := y * grid_width
		for x in range(1, grid_width):
			var i := row + x
			var active := x < grid_width - 1 and corruption[i] != 0 and (cells[i] == FREE or cells[i] == TRAIL)
			if active and start < 0:
				start = x
			elif not active and start >= 0:
				# Cache in field-local pixels so moving the whole arena needs no rebuild.
				corruption_strokes.append(Vector2((start + 0.5) * CELL - 3, (y + 0.5) * CELL))
				corruption_strokes.append(Vector2((x - 0.5) * CELL + 3, (y + 0.5) * CELL))
				start = -1
	corruption_visual_dirty = false

func draw_play() -> void:
	if corruption_active:
		if corruption_visual_dirty: rebuild_corruption_strokes()
		var color := Color(Palette.MAGENTA, (0.65 + 0.2 * sin(time * 3.0)) * 0.55)
		var origin := Vector2(FX, FY)
		for i in range(0, corruption_strokes.size(), 2):
			lines.seg(origin + corruption_strokes[i], origin + corruption_strokes[i + 1], color, 0.4, 0.1, 1.3)
	draw_objectives()
	super.draw_play()
	if drawing and (hardlight_time > 0.0 or (has_card("phase") and cut_time < 1.5 * card_power("phase"))):
		lines.polyline(trail_points(), false, Palette.CYAN, 0.3, 0.1, 2.0)

func chart_position(depth: int, branch: int) -> Vector2:
	var count: int = route[depth - 1].size()
	return Vector2(170 + (depth - 1) * 180, 355 + (branch - (count - 1) * 0.5) * 320)

func draw_chart_symbol(kind: String, pos: Vector2, color: Color) -> void:
	match kind:
		"repair":
			lines.seg(pos - Vector2(9, 0), pos + Vector2(9, 0), color, 0, 0, 1.5)
			lines.seg(pos - Vector2(0, 9), pos + Vector2(0, 9), color, 0, 0, 1.5)
		"salvage":
			lines.circle(pos, 10, color, 6)
			lines.circle(pos, 2.5, color, 6)
		"finale":
			lines.polyline(PackedVector2Array([pos + Vector2(0, -14), pos + Vector2(7, 0), pos + Vector2(0, 14), pos + Vector2(-7, 0)]), true, color)
			lines.circle(pos, 6, color, 4)
		"beacon":
			for k in 3:
				var a := -PI * 0.5 + k * TAU / 3.0
				lines.circle(pos + Vector2(cos(a), sin(a)) * 9.0, 3, color, 6)
		"cargo":
			lines.rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), color)
			lines.seg(pos - Vector2(6, 6), pos + Vector2(6, 6), color)
		"breach":
			arc(pos, 10.0, 0.45, TAU - 0.45, color, 1.0)
			lines.circle(pos, 2.5, color, 6)
		_:
			lines.circle(pos, 4, color, 12)

func draw_chart() -> void:
	# A quiet status row leaves the route as the main visual element.
	label("%02d / %02d" % [chart_depth, route.size()], Vector2(80, 76), 18, Palette.DIM)
	for i in owned_cards.size():
		var card := card_definition(owned_cards[i])
		var pos := Vector2(380 + i * 265, 71)
		draw_card_icon(card.id, pos, card_color(card.id), 0.25)
		label("%s %s" % [card.name, ["I", "II", "III"][card_rank(owned_cards[i]) - 1]], pos + Vector2(25, 4), 11, Palette.DIM)
	draw_hull_icons(Vector2(1240, 70), maxi(0, lives + 1))
	draw_salvage(str(earned_salvage), Vector2(1400, 70), 15)
	for depth in range(1, route.size()):
		for a in route[depth - 1].size():
			for b in route[depth].size():
				if not chart_connected(depth, a, b): continue
				var traveled: bool = route_path.size() > depth and route_path[depth - 1] == a and route_path[depth] == b
				var approach: bool = depth == chart_focus_depth - 1 and chart_reachable(chart_focus_depth, b) and route_path[depth - 1] == a and b == selection
				var color := Palette.GREEN if traveled else (Palette.CYAN if approach else Palette.DIM * 0.45)
				var start := chart_position(depth, a)
				var end := chart_position(depth + 1, b)
				var direction := start.direction_to(end)
				lines.seg(start + direction * 34, end - direction * 34, color)
	for depth in range(1, route.size() + 1):
		for branch in route[depth - 1].size():
			var pos := chart_position(depth, branch)
			var visited: bool = route_path.size() >= depth and route_path[depth - 1] == branch
			var focused: bool = depth == chart_focus_depth and branch == selection
			var color := Palette.GREEN if visited else (Palette.CYAN if chart_reachable(depth, branch) else Palette.DIM * 0.75)
			if depth < chart_depth and not visited: color = Palette.DIM * 0.35
			lines.circle(pos, 25, color, 6)
			if focused: lines.circle(pos, 36 + sin(ui_time * 3) * 2, Palette.WHITE, 6)
			if visited:
				lines.polyline(PackedVector2Array([pos + Vector2(-8, 0), pos + Vector2(-2, 6), pos + Vector2(9, -7)]), false, color)
			else:
				draw_chart_symbol("finale" if depth == route.size() else route[depth - 1][branch].kind, pos, color)
	# The ship marks the last completed jump; only the focused node needs a label.
	var ship_pos := Vector2(95, 355) if route_path.is_empty() else chart_position(route_path.size(), route_path.back()) + Vector2(0, -55)
	for path in Hulls.paths(ship.id, ship_pos, 16.0, 0.0, 0.0):
		lines.polyline(path, false, Palette.WHITE)
	var node: Dictionary = route[chart_focus_depth - 1][selection]
	label("FINALE" if chart_focus_depth == route.size() else String(node.kind).to_upper(), chart_position(chart_focus_depth, selection) + Vector2(0, 65), 13, Palette.CYAN, 1)
	# One compact inspector, without a surrounding card competing with the map.
	lines.seg(Vector2(80, 680), Vector2(1500, 680), Palette.DIM * 0.6)
	var shape_id := int(node.stage)
	var arena := SectorArena.build(shape_id, 0, "roguelite", Sectors.holes(shape_id, Vector2i(grid_width, grid_height)), Vector2i(grid_width, grid_height))
	var outline: PackedVector2Array = arena.outline
	for i in range(0, outline.size(), 2):
		lines.seg(Vector2(195, 750) + (outline[i] - Vector2(grid_width, grid_height) * 0.5) * 1.2, Vector2(195, 750) + (outline[i + 1] - Vector2(grid_width, grid_height) * 0.5) * 1.2, Palette.CYAN)
	label("%02d / %s" % [chart_focus_depth, Sectors.stage(shape_id).name], Vector2(350, 733), 21)
	var kind := String(node.kind)
	var turrets := Sectors.turret_count(kind, chart_focus_depth)
	var anomaly_count := Sectors.anomaly_count(chart_focus_depth, shape_id)
	var threats := "CAPTURE %d%%" % Sectors.capture_goal(chart_focus_depth)
	if kind == "beacon": threats = "BEACONS %d" % Sectors.objective_count(kind, chart_focus_depth)
	elif kind == "cargo": threats = "CARGO %d" % Sectors.objective_count(kind, chart_focus_depth)
	threats += " / %d %s" % [anomaly_count, "ANOMALY" if anomaly_count == 1 else "ANOMALIES"]
	if turrets > 0: threats += " / %d TURRET%s" % [turrets, "" if turrets == 1 else "S"]
	if kind == "breach": threats += " / BREACH"
	if chart_focus_depth >= Sectors.CORRUPTION_SECTOR: threats += " / CORRUPTION"
	label(threats, Vector2(350, 772), 13, Palette.YELLOW)
	var reward := Sectors.reward_copy(kind)
	if not reward.is_empty():
		# Right-aligned beside the Jump button, clear of the longest threat strings.
		label(reward, Vector2(1205, 754), 15, Palette.GREEN, 2)
	var reachable := chart_reachable(chart_focus_depth, selection)
	lines.rect(CHART_JUMP, Palette.CYAN if reachable else Palette.DIM)
	var action := "JUMP  [ENTER]" if reachable else ("CLEARED" if chart_focus_depth < chart_depth and route_path[chart_focus_depth - 1] == selection else "LOCKED")
	label(action, CHART_JUMP.get_center() - Vector2(0, 8.5), 17, Palette.WHITE if reachable else Palette.DIM, 1)
	label("ESC  BANK & EXIT", Vector2(80, 842), 12, Palette.DIM)
	label("ARROWS  SELECT", Vector2(1500, 842), 12, Palette.DIM, 2)

func announce_lance() -> void:
	pass # Space already communicates the Lancer's action; keep failure/recharge messages.

func movement_module() -> String:
	for id in Cards.OPENING:
		if has_card(id): return id
	return ""

func reset_movement_module() -> void:
	leap_input_frame = false
	hardening_time = 0.0
	disc_braced = false
	dash_time = 0.0
	dash_direction = Vector2i.ZERO

func uses_leap_controls() -> bool:
	return leap_building or wall_building or leap_input_frame

func read_input() -> Dictionary:
	var input := super.read_input()
	if uses_leap_controls():
		input.draw = Input.is_action_pressed("br_harden")
	elif dash_time > 0.0:
		input.dir = dash_direction
		input.draw = ship.id == "surveyor"
		input.slow = false
	return input

func leap_rate() -> float:
	return super.leap_rate() * card_power("leap")

func finish_leap(on_land: bool) -> void:
	super.finish_leap(on_land)
	if wall_building: cooldowns.leap = 16.0

func update_movement_module(dt: float) -> void:
	dash_time = maxf(0.0, dash_time - dt)
	hardening_time = maxf(0.0, hardening_time - dt)
	if not sap_live: disc_braced = false
	if hardening_time <= 0.0 or not drawing or wall_building: return
	var limit := maxi(0, tether_i) if tether_active else maxi(0, trail.size() - 1)
	harden_len = minf(harden_len + 10.0 * dt, limit)
	for i in int(harden_len):
		var cell: Vector2i = trail[i]
		if cells[idx(cell.x, cell.y)] == TRAIL:
			cells[idx(cell.x, cell.y)] = HARD
			corruption_visual_dirty = true

func draw_ability_ring() -> void:
	super.draw_ability_ring()
	if leap_building:
		var target := center(leap_target())
		dashed(center(anchor), target, Palette.YELLOW, 6.0, 6.0)
		lines.circle(target, 6, Palette.YELLOW, 4)

func secondary_ability() -> String:
	for id in Cards.SECONDARY:
		if has_card(id): return id
	return ""
