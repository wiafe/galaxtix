extends "res://scripts/game.gd"
const FieldFeatures = preload("res://scripts/roguelite_field_features.gd")
var field_features := FieldFeatures.new()
## Shape expedition built on Jump's simulation. Only run flow, progression,
## card effects and corruption live here; controls and flood-fill remain in Game.
signal exited
const Progress = preload("res://scripts/roguelite_progress.gd")
const Cards = preload("res://scripts/roguelite_cards.gd")
var draft_capture: Array[int] = [35]
var opening_draft_pending := true
var leap_input_frame := false
var charge_input_frame := false
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
const Encounters = preload("res://scripts/map_encounters.gd")
const Acts = preload("res://scripts/roguelite_acts.gd")
var boss = preload("res://scripts/roguelite_boss.gd").new()
const MAX_CARD_RANK := 3
const CHART_JUMP := Rect2(1240, 718, 260, 60)
const BRIEFING_PANEL := Rect2(380, 320, 840, 250)
var briefing_ready := false
var route: Array = []
var route_path: Array[int] = []
var active_destination := {}
var authored_map: MapDefinition
var authored_behaviors := {} # QixBody -> attack state; also participates in capture flood seeds.
var brood_eggs: Array[Dictionary] = []
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
var draft_speed_stacks := 0
var draft_shield_stacks := 0
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
var objective_notice := ""
var objective_notice_time := 0.0
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
# Surge: a stalled sector surfaces a bonus disc in the void; miss it and the sector escalates.
const SURGE_AFTER := 20.0 # Seconds without a land change before a surge surfaces; playtest values.
const SURGE_TELEGRAPH := 2.0
const SURGE_WINDOW := 15.0
const SURGE_RADIUS := 3
const SURGE_RETRY := 5.0
var stall_time := 0.0
var surge := {}
var surge_expired := 0
var surge_pressure := 0.0
# Rival: one AI cutter claiming void. Its land and line are overlays; cells stay FREE beneath,
# so the player's cut, the claim flood and the Sparx never need to know it exists.
const RivalCutter = preload("res://scripts/rival_cutter.gd")
const RIVAL_COLOR := Palette.ORANGE
var rival = null
var rival_land := PackedByteArray()
var rival_home := PackedByteArray() # Permanent starting territory, excluded from either score.
var rival_home_cell := Vector2i.ZERO
var rival_home_radius := 3
var rival_segments := PackedVector2Array()
var rival_visual_dirty := true
var rival_remaining := 0.0
var rival_tally := {}
var rival_entry := {}
var race_opponent: Game
const RACE_COLOR := Color(0.08, 0.76, 0.59)
var race_elapsed := 0.0
var race_claimed := 0
var race_bounds := Rect2()
var race_map_bounds := Rect2()
var race_pending_salvage := 0.0
const RIVAL_RETRY_FIELDS := ["owned_cards", "card_ranks", "opening_draft_pending", "draft_speed_stacks", "draft_shield_stacks", "earned_salvage", "salvage_fraction", "bonus_salvage", "capture_count", "small_chain", "cooldowns"]
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
var hardlight_armed := false
var cooldowns := {"charge": 0.0, "hardening": 0.0, "leap": 0.0, "dash": 0.0, "afterburner": 0.0, "hardlight": 0.0, "anchor": 0.0, "ion": 0.0}
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
	draft_speed_stacks = 0
	draft_shield_stacks = 0
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
	var map := MapCatalog.read(arena_stage(lvl))
	if map != null and map.override_terrain:
		layout.arena = map.arena(rim)
		layout.shape = map.rock_rectangles()
		layout.start = layout.arena.start
	if map != null and map.override_start:
		layout.start = MapCatalog.nearest(layout.arena.mask, map.grid_size, map.player_start, 1)
	last_objectives = Encounters.populate(layout, map, lvl, encounter_kind(lvl), progress.rank_of("extractor"))
	return layout

func sector_shape(_g: Dictionary, lvl: int, _rng: RandomNumberGenerator) -> Array:
	return Sectors.holes(lvl, Vector2i(grid_width, grid_height))

# ------------------------------------------------------------------ objective encounters

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
	objective_notice = ""
	objective_notice_time = 0.0
	zones.clear()
	cargo.clear()
	breach.clear()
	clear_rival()
	var found: Dictionary = last_objectives
	last_objectives = {}
	if found.is_empty() or String(found.kind) != encounter_kind(level):
		return
	match encounter_kind(level):
		"beacon":
			for disc in found.zones:
				zones.append({"cell": disc.cell, "radius": disc.radius, "captured": false, "spin": 0.0})
		"cargo":
			cargo = {"cell": found.pod, "carrying": false, "delivered": 0, "runs": Encounters.runs(authored_map, "cargo", level), "done": false}
		"breach":
			breach = {"cell": found.breach.cell, "radius": found.breach.radius, "sealed": false, "pressure": 0.0, "spin": 0.0}
		"rival":
			setup_rival(found.rival.cell, int(found.rival.radius))

func encounter_goal() -> int:
	return Encounters.goal(authored_map, encounter_kind(level), level)

func encounter_copy(map, kind: String, depth: int) -> String:
	var copy := Sectors.objective_copy(kind, depth)
	if kind == "race": copy = copy.replace(str(Sectors.RACE_GOAL) + "%", str(Encounters.goal(map, kind, depth)) + "%")
	else: copy = copy.replace(str(Sectors.capture_goal(depth)) + "%", str(Encounters.goal(map, kind, depth)) + "%")
	if kind == "rival": copy = copy.replace(str(int(Sectors.RIVAL_SECONDS)), str(int(Encounters.seconds(map, kind))))
	if kind == "beacon" and Encounters.settings(map, kind).has("objectives"):
		copy = copy.replace(str(Sectors.objective_count(kind, depth)) + " BEACON", str(Encounters.settings(map, kind).objectives.size()) + " BEACON")
	return copy

func objective_complete() -> bool:
	match encounter_kind(level):
		"boss": return boss.active() and boss.defeated
		"rival", "race": return false # Contests settle after both competitors advance.
		"beacon":
			for zone in zones:
				if not zone.captured:
					return false
			return not zones.is_empty()
		"cargo":
			return not cargo.is_empty() and int(cargo.delivered) >= int(cargo.runs)
		"breach":
			return not breach.is_empty() and bool(breach.sealed) and capture_percent >= encounter_goal()
	return capture_percent >= encounter_goal()

## Advances every objective from the current board and returns a note for the HUD.
func check_objectives() -> String:
	var note := ""
	match encounter_kind(level):
		"boss": boss.observe(self)
		"beacon": note = update_zones()
		"cargo": note = update_cargo()
		"breach": note = update_breach_seal()
	# The surge is kind-independent, so it is checked after whatever the kind reported.
	var extra := update_surge()
	if extra.is_empty():
		return note
	return extra if note.is_empty() else note + " / " + extra

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
	if not note.is_empty():
		show_objective_notice(note)
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
	if cells[idx(cell.x, cell.y)] not in [FREE, TRAIL]:
		# Enclosed without contact: the pod is unreachable on land, so it drifts elsewhere.
		# A Lancer's exposed tether is still reachable when the rider gets here.
		relocate_pod()
		var note := "CARGO RELOCATED - PICK IT UP BEFORE RETURNING TO LAND"
		show_objective_notice(note)
		return note
	return ""

## Pickup follows the ship, with a two-cell reach. Casting a lance alone is not contact.
func check_cargo_contact() -> void:
	if cargo.is_empty() or bool(cargo.carrying) or bool(cargo.done):
		return
	if exposed() and cargo_in_reach():
		cargo.carrying = true
		show_objective_notice("CARGO ABOARD - RETURN TO SAFE LAND")
		set_msg("CARGO ABOARD", 1.0)
		sparks.ripple(center(cargo.cell), 4.0, 240.0, 0.4, Palette.YELLOW)
		lines.spike(1.0, 0.2)

func cargo_in_reach() -> bool:
	var cell: Vector2i = cargo.cell
	if Vector2(p - cell).length_squared() > Sectors.CARGO_PICKUP_RADIUS * Sectors.CARGO_PICKUP_RADIUS:
		return false
	# Reach across open space, never through a rail, rock or already enclosed cargo.
	var from := center(p)
	var to := center(cell)
	var steps := maxi(1, ceili(from.distance_to(to) / (CELL * 0.5)))
	for step in range(1, steps + 1):
		var sample := to_cell(from.lerp(to, float(step) / steps))
		if not in_bounds(sample) or cells[idx(sample.x, sample.y)] not in [FREE, TRAIL]: return false
	return true

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
	var note := "CARGO DELIVERED %d/%d" % [cargo.delivered, cargo.runs]
	show_objective_notice(note + " - SALVAGE AWARDED")
	return note

func drop_cargo() -> void:
	if cargo.is_empty() or bool(cargo.done):
		return
	if bool(cargo.carrying):
		cargo.carrying = false
		show_objective_notice("CARGO DROPPED - PICK IT UP AGAIN")
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
	show_objective_notice("BREACH SEALED - SALVAGE AWARDED")
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
		"race": return "RACE / FIRST TO %d%%" % encounter_goal()
		"rival": return "RIVAL  %02d:%02d" % [ceili(rival_remaining) / 60, ceili(rival_remaining) % 60]
		"beacon":
			var secured := 0
			for zone in zones:
				if zone.captured:
					secured += 1
			return "BEACONS %d/%d" % [secured, zones.size()]
		"cargo":
			return "CARGO %d/%d" % [int(cargo.get("delivered", 0)), int(cargo.get("runs", 0))]
	return "CAPTURE %d%%" % encounter_goal()

func show_objective_notice(text: String) -> void:
	objective_notice = text
	objective_notice_time = 4.0
	stall_time = 0.0 # Objective events count as progress against the surge clock.

func objective_instruction() -> String:
	if boss.active(): return boss.instruction()
	if encounter_kind(level) == "cargo" and not cargo.is_empty():
		if bool(cargo.done):
			return "ALL CARGO RUNS COMPLETE."
		if bool(cargo.carrying):
			return "CARGO ABOARD - RETURN TO SAFE LAND TO DELIVER. ANOMALIES ARE CHASING YOU."
	if encounter_kind(level) == "breach" and not breach.is_empty() and bool(breach.sealed):
		return "BREACH SEALED - REACH %d%% TERRITORY TO CLEAR." % encounter_goal()
	return encounter_copy(authored_map, encounter_kind(level), level)

func bar_scale() -> float:
	return 100.0 if not Sectors.territory_goal(encounter_kind(level)) else float(encounter_goal())

func advance_objective_visuals(dt: float) -> void:
	for zone in zones:
		if not zone.captured:
			zone.spin = float(zone.spin) + dt * (0.6 + (4.0 if zone_contested(zone) else 0.0))
	if not breach.is_empty() and not bool(breach.sealed):
		breach.spin = float(breach.spin) + dt * (0.6 + 6.0 * float(breach.pressure) / Sectors.BREACH_LIMIT)
	if not surge.is_empty():
		var urgency := 1.0 - clampf(float(surge.window) / SURGE_WINDOW, 0.0, 1.0)
		surge.spin = float(surge.spin) + dt * (0.6 + 3.0 * urgency)

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
			lines.circle(c, Sectors.CARGO_PICKUP_RADIUS * CELL, Color(Palette.YELLOW, 0.25), 24, 0.0, 0.0, 0.6)
			draw_pod(c, 9.0, pulse)
			var label_color := Palette.YELLOW
			label_color.a = 0.5 + 0.4 * pulse
			VectorFont.draw(lines, "CARGO", c + Vector2(21, -6), 10, label_color, 0.5, 0.3)
	if not breach.is_empty():
		var c := center(breach.cell)
		var radius := (float(breach.radius) + 0.5) * CELL
		if bool(breach.sealed):
			lines.circle(c, radius, Palette.DIM, 16, 0.3, 0.1, 1.0)
		else:
			draw_ring(c, radius, float(breach.spin), Palette.MAGENTA)
			lines.circle(c, 3.0, Palette.MAGENTA, 6, 1.0, 0.6, 0.9)
	draw_rival()
	if not surge.is_empty():
		var c := center(surge.cell)
		var radius := (float(surge.radius) + 0.5) * CELL
		if float(surge.telegraph) > 0.0:
			# Surfacing: a ring tightens onto the spot, as pickups do.
			var k := clampf(float(surge.telegraph) / SURGE_TELEGRAPH, 0.0, 1.0)
			var col := Palette.ORANGE
			col.a = 0.2 + 0.5 * (1.0 - k)
			lines.circle(c, radius + 26.0 * k, col, 12, 1.5, 0.3, 0.8)
		else:
			draw_ring(c, radius, float(surge.spin), Palette.ORANGE)
			var fraction := disc_claimed_fraction(surge.cell, surge.radius)
			if fraction > 0.0:
				arc(c, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * fraction, Palette.GREEN, 1.0)
			var left := clampf(float(surge.window) / SURGE_WINDOW, 0.0, 1.0)
			if left > 0.0:
				arc(c, radius + 5.0, -PI * 0.5, -PI * 0.5 + TAU * left, Palette.ORANGE, 0.8)
			lines.circle(c, 3.0, Palette.FULLBRIGHT, 6, 1.0, 0.6, 0.9)
			VectorFont.draw(lines, "%dS" % ceili(maxf(0.0, float(surge.window))), c + Vector2(radius + 8.0, -6.0), 10, Palette.ORANGE, 0.5, 0.3)

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

# ------------------------------------------------------------------ surge
## The stall clock only runs while no surge is up; the surge itself telegraphs, then counts down.
func update_surge_clock(dt: float) -> void:
	if encounter_kind(level) == "boss": return
	if encounter_kind(level) == "race": return
	if surge.is_empty():
		stall_time += dt
		if stall_time >= SURGE_AFTER:
			spawn_surge()
		return
	if float(surge.telegraph) > 0.0:
		surge.telegraph = maxf(0.0, float(surge.telegraph) - dt)
		if float(surge.telegraph) == 0.0:
			var c := center(surge.cell)
			sparks.ripple(c, 3.0, 220.0, 0.5, Palette.ORANGE)
			sparks.burst(c, 24, 120.0, 1.5, 0.5, Palette.ORANGE)
		return
	surge.window = float(surge.window) - dt

## Every disc cell must be live void, off every objective, and out of an Anomaly's reach,
## otherwise a fifteen-second window on a guarded pocket would be a guaranteed penalty.
func surge_disc_open(c: Vector2i, radius: int, blocked: Dictionary) -> bool:
	for i in disc_cells(c, radius):
		if cells[i] != FREE or blocked.has(i):
			return false
	var point := center(c)
	for q: QixBody in qixes:
		if q.c.distance_to(point) < q.len * 0.5 + (radius + 3) * CELL:
			return false
	return true

func spawn_surge() -> void:
	var free: Array = field_arena.get("free_cells", [])
	var blocked := {}
	for zone in zones:
		for i in disc_cells(zone.cell, zone.radius):
			blocked[i] = true
	if not breach.is_empty():
		for i in disc_cells(breach.cell, breach.radius):
			blocked[i] = true
	if not cargo.is_empty() and not bool(cargo.done):
		blocked[idx(cargo.cell.x, cargo.cell.y)] = true
	for r in range(SURGE_RADIUS, 0, -1):
		var best := Vector2i(-1, -1)
		var best_d := -1.0
		for tries in 80:
			if free.is_empty():
				break
			var c: Vector2i = free[rng.randi_range(0, free.size() - 1)]
			if not surge_disc_open(c, r, blocked):
				continue
			var d := Vector2(c - p).length()
			if d > best_d:
				best_d = d
				best = c
			if d > 30.0:
				break
		if best.x >= 0:
			surge = {"cell": best, "radius": r, "telegraph": SURGE_TELEGRAPH, "window": SURGE_WINDOW, "spin": 0.0}
			show_objective_notice("SURGE - ENCLOSE THE ZONE WITHIN %d SECONDS" % int(SURGE_WINDOW))
			set_msg("SURGE", 1.0)
			return
	# No open pocket right now: try again shortly rather than giving up on the sector.
	stall_time = SURGE_AFTER - SURGE_RETRY

func update_surge() -> String:
	if surge.is_empty() or disc_claimed_fraction(surge.cell, surge.radius) < 1.0:
		return ""
	var c := center(surge.cell)
	award_flux(2.0)
	sparks.ripple(c, (float(surge.radius) + 0.5) * CELL, 320.0, 0.6, Palette.GREEN)
	sparks.burst(c, 40, 200.0, 1.5, 0.7, Palette.ORANGE)
	surge.clear()
	show_objective_notice("SURGE SECURED - SALVAGE AWARDED")
	return "SURGE SECURED"

## A missed surge brings a Sparx while the coast can take one, then the Anomaly speeds up.
func expire_surge() -> void:
	var c := center(surge.cell)
	sparks.burst(c, 30, 160.0, 1.5, 0.5, Palette.ORANGE)
	lines.spike(1.5, 0.25)
	surge.clear()
	surge_expired += 1
	stall_time = 0.0
	var authored := authored_map != null and authored_map.override_enemies
	if surge_expired <= 2 and not authored:
		sparx_to_spawn += 1
		sparx_spawn_t = 0.0
		show_objective_notice("SURGE LOST - SPARX INBOUND")
	else:
		surge_pressure = minf(0.5, surge_pressure + 0.1)
		show_objective_notice("SURGE LOST - ANOMALY SURGING")
	set_msg("SURGE LOST", 1.2)

func qix_speed() -> float:
	return super.qix_speed() * (1.0 + surge_pressure)

# ------------------------------------------------------------------ rival cutter
func clear_rival() -> void:
	clear_race()
	rival_remaining = 0.0
	rival_tally.clear()
	rival = null
	rival_land.resize(0)
	rival_home.resize(0)
	rival_segments.clear()
	rival_visual_dirty = true

func setup_rival(seed_cell: Vector2i, radius: int) -> void:
	rival_home_radius = radius
	# Test/playtest setups can relocate the home on the same board.
	for i in rival_home.size():
		if rival_home[i] == 1:
			cells[i] = FREE
			base_free += 1
			free_count += 1
	rival_remaining = Encounters.seconds(authored_map, "rival")
	rival_land.resize(grid_width * grid_height)
	rival_land.fill(0)
	rival_home.resize(cells.size())
	rival_home.fill(0)
	rival_home_cell = seed_cell
	for i in disc_cells(seed_cell, radius):
		if cells[i] == FREE:
			rival_land[i] = 1
			rival_home[i] = 1
			cells[i] = ROCK # Solid to player movement, beams, blasts, and claim floods.
			base_free -= 1
			free_count -= 1
	rival = RivalCutter.new()
	rival.setup(Vector2i(grid_width, grid_height), rng, {
		"owner_of": rival_owner_of,
		"is_solid": rival_is_solid,
		"player_trail_at": rival_player_trail_at,
		"on_capture": rival_capture,
		"on_cross_player_trail": rival_crossed_trail,
		"on_fail": rival_failed,
	})
	rival.pos = seed_cell
	rival.anchor = seed_cell
	rival.aggression = clampf((level - 3) / 4.0, 0.0, 1.0)
	rival.speed_scale = lerpf(1.0, 1.48, rival.aggression)
	refresh_rival_owned()
	# setup follows the base field's opaque white texture. Bake both territory
	# tints now, before draw switches off the sprite's shared tint for Rival.
	update_fill()

func rival_active() -> bool:
	return rival != null and rival.alive and rival_land.size() == cells.size()

## The board as the rival sees it: its land, open void it may cut through, or a wall.
func rival_owner_of(c: Vector2i) -> int:
	if not in_bounds(c):
		return -1
	var i := idx(c.x, c.y)
	if rival_land[i] == 1:
		return 1
	return 0 if cells[i] == FREE or cells[i] == TRAIL else -1

func rival_is_solid(c: Vector2i) -> bool:
	if in_bounds(c) and rival_home.size() == cells.size() and rival_home[idx(c.x, c.y)] == 1: return false
	return not in_bounds(c) or (cells[idx(c.x, c.y)] != FREE and cells[idx(c.x, c.y)] != TRAIL)

func rival_player_trail_at(c: Vector2i) -> bool:
	return in_bounds(c) and cells[idx(c.x, c.y)] == TRAIL

func rival_failed() -> void:
	if rival != null and rival.alive:
		sparks.burst(center(rival.pos), 20, 140.0, 1.5, 0.4, RIVAL_COLOR)
		set_msg("RIVAL LINE CUT", 1.0)

## The rival's line crossed ours: the same gate bolts and mites use, so Hardlight, Phase,
## Ion and a hardened Leap wall protect the trail exactly as they do against them.
func rival_crossed_trail(c: Vector2i) -> void:
	if tether_hit(c) and wire_hit():
		lose_trail("RIVAL CUT YOUR LINE")

## Battle Royale's contact rule: the line is lost and the ship returns to its anchor,
## with a short shield and no hull lost.
func lose_trail(reason: String) -> void:
	for c in trail:
		var i := idx(c.x, c.y)
		if cells[i] == TRAIL or cells[i] == HARD:
			cells[i] = FREE
	trail.clear()
	tether_active = false
	tether_i = -1
	leap_building = false
	wall_building = false
	wall_cells = [[], []]
	harden_len = 0.0
	sap_live = false
	sap_charge = 0.0
	drawing = false
	fuse_on = false
	draw_armed = false
	move_acc = 0.0
	p = anchor
	vis = center(p)
	invuln = 1.0
	exposure = 0.0
	cut_time = 0.0
	reset_movement_module()
	drop_cargo()
	grid_changed()
	sparks.burst(vis, 30, 200.0, 1.5, 0.5, RIVAL_COLOR)
	lines.spike(2.0, 0.3)
	set_msg(reason, 1.4)
	show_objective_notice(reason + " - BACK TO YOUR ANCHOR")

## A closed rival loop claims the void it walls off, judged the same way as ours: whatever
## no Anomaly can reach. The seed has to be open void, because Anomalies float over rival
## land and a seedless flood would hand the rival the whole arena.
func rival_capture(loop: Array) -> void:
	if not rival_active():
		return
	for c in loop:
		rival_land[idx(c.x, c.y)] = 1
	reach.fill(0)
	var sp := 0
	for q: QixBody in qixes:
		var seed_i := rival_seed_index(q)
		if seed_i >= 0 and reach[seed_i] == 0:
			reach[seed_i] = 1
			stack[sp] = seed_i
			sp += 1
	if sp > 0:
		while sp > 0:
			sp -= 1
			var i := stack[sp]
			var x := i % grid_width
			var y := i / grid_width
			for n in [i - 1 if x > 0 else -1, i + 1 if x < grid_width - 1 else -1, i - grid_width if y > 0 else -1, i + grid_width if y < grid_height - 1 else -1]:
				if n < 0 or reach[n] != 0 or rival_land[n] == 1:
					continue
				if cells[n] != FREE and cells[n] != TRAIL:
					continue
				reach[n] = 1
				stack[sp] = n
				sp += 1
		var gained := PackedInt32Array()
		for i in grid_width * grid_height:
			if cells[i] == FREE and rival_land[i] == 0 and reach[i] == 0:
				gained.append(i)
		if gained.size() <= 0.4 * free_count:
			for i in gained:
				rival_land[i] = 1
		if gained.size() > 0:
			sparks.ripple(center(rival.pos), 6.0, 280.0, 0.5, RIVAL_COLOR)
	refresh_rival_owned()
	rival_visual_dirty = true
	update_fill()

func rival_seed_index(q: QixBody) -> int:
	var c := to_cell(q.c)
	for r in 11:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if not in_bounds(n):
					continue
				var i := idx(n.x, n.y)
				if cells[i] == FREE and rival_land[i] == 0:
					return i
	return -1

## Land under the rival is always in step with the board: the player's claims and blasts
## take it back, its line fails when land closes over it, and no land at all drives it off.
func sweep_rival() -> void:
	if rival == null or not rival.alive or rival_land.size() != cells.size():
		return
	var changed := false
	var line_cut := false
	for i in grid_width * grid_height:
		if rival_home.size() == cells.size() and rival_home[i] == 1: continue
		var v := cells[i]
		if v != FREE and v != TRAIL:
			if rival_land[i] == 1:
				rival_land[i] = 0
				changed = true
			if rival.trail_mask[i] == 1:
				line_cut = true
	if line_cut:
		rival.fail()
	if changed or line_cut:
		refresh_rival_owned()
		rival_visual_dirty = true

func refresh_rival_owned() -> void:
	if rival == null or not rival.alive:
		return
	var owned: Array[Vector2i] = []
	for i in grid_width * grid_height:
		if rival_land[i] == 1:
			owned.append(Vector2i(i % grid_width, i / grid_width))
	rival.owned = owned
	if owned.is_empty():
		eliminate_rival()
		return
	if not rival.exposed and rival_land[idx(rival.pos.x, rival.pos.y)] == 0:
		rival.pos = rival.nearest_owned(rival.pos)
		rival.plan.clear()

func eliminate_rival() -> void:
	rival.alive = false
	rival.clear_trail()
	rival_land.fill(0)
	sparks.burst(center(rival.pos), 60, 240.0, 1.5, 0.8, RIVAL_COLOR)
	sparks.ripple(center(rival.pos), 6.0, 360.0, 0.7, Palette.GREEN)
	set_msg("RIVAL DRIVEN OFF", 1.4)
	show_objective_notice("RIVAL DRIVEN OFF - HOLD UNTIL TIME")
	rival_visual_dirty = true
	update_fill()

func beam_cuts_rival(q: QixBody) -> bool:
	var e := qix_ends(q.c, q.theta, q.len)
	var n := int(maxf(2.0, q.len / 5.0))
	for k in range(n + 1):
		if rival.trail_at(to_cell(e[0].lerp(e[1], float(k) / n))):
			return true
	return false

func update_rival(dt: float) -> void:
	if not rival_active():
		return
	for q: QixBody in qixes:
		if rival.exposed and beam_cuts_rival(q):
			rival.fail()
			break
	if freeze_time <= 0.0:
		rival.tick(dt)

func rival_scores() -> Vector2i:
	var scores := Vector2i.ZERO
	for i in cells.size():
		if field_arena.mask[i] != 2: continue # Rock and starting rails do not score.
		if rival_home.size() == cells.size() and rival_home[i] == 1: continue
		if cells[i] == CLAIMED: scores.x += 1
		elif rival_land.size() == cells.size() and rival_land[i] == 1: scores.y += 1
	return scores

func clear_race() -> void:
	if race_opponent != null:
		race_opponent.fill.visible = false
		race_opponent.queue_free()
		race_opponent = null
	race_elapsed = 0.0
	race_pending_salvage = 0.0
	if fill != null:
		fill.position = Vector2(FX, FY)
		fill.scale = Vector2(CELL, CELL)

func setup_race() -> void:
	# Load at runtime because the isolated simulator inherits this ruleset.
	race_opponent = load("res://scripts/race_opponent.gd").new()
	add_child(race_opponent)
	var quiet_lines := ScopeLines.new()
	quiet_lines.visible = false
	race_opponent.add_child(quiet_lines)
	var opponent_fill := Sprite2D.new()
	fill.get_parent().add_child(opponent_fill) # Inside the same HDR/blur viewport as the player.
	race_opponent.setup(quiet_lines, Sparks.new(), opponent_fill)
	race_opponent.take_starting_board(self)
	var first := true
	for i in cells.size():
		if field_arena.mask[i] == 0: continue
		var cell_rect := Rect2(Vector2(FX + (i % grid_width) * CELL, FY + (i / grid_width) * CELL), Vector2.ONE * CELL)
		if first:
			race_map_bounds = cell_rect
			first = false
		else: race_map_bounds = race_map_bounds.merge(cell_rect)
	race_bounds = race_map_bounds.grow(CELL * 2)

func race_viewport(side: int) -> Rect2:
	return Rect2(170 + side * 670, 186, 590, 540)

func race_map_rect(side: int) -> Rect2:
	var viewport := race_viewport(side)
	var scale_at := minf(viewport.size.x / race_bounds.size.x, viewport.size.y / race_bounds.size.y)
	var origin := viewport.get_center() - race_bounds.get_center() * scale_at
	return Rect2(race_map_bounds.position * scale_at + origin, race_map_bounds.size * scale_at)

func race_bar_rect(side: int) -> Rect2:
	var map_rect := race_map_rect(side)
	return Rect2(map_rect.position.x, 134, map_rect.size.x, 10)

func race_scores() -> Vector2i:
	return Vector2i(race_claimed, race_opponent.race_claimed) if race_opponent != null else Vector2i.ZERO

func check_race_finish() -> void:
	if race_opponent == null or not rival_tally.is_empty(): return
	var scores := race_scores()
	var player_done := scores.x * 100 >= base_free * encounter_goal()
	var racer_done := scores.y * 100 >= base_free * encounter_goal()
	if not player_done and not racer_done: return
	rival_tally = {"player": scores.x, "rival": scores.y, "outcome": "tie" if player_done and racer_done else ("win" if player_done else "loss")}
	show_contest_tally()

func draw_race_board(board: Game, bounds: Rect2, viewport: Rect2) -> void:
	var scale_at := minf(viewport.size.x / bounds.size.x, viewport.size.y / bounds.size.y)
	var origin := viewport.get_center() - bounds.get_center() * scale_at
	lines.zoom_center = Vector2.ZERO
	lines.zoom = Vector2.ONE * scale_at
	lines.offset = origin / scale_at
	board.fill.visible = true
	board.fill.modulate = board.fill_color()
	board.fill.position = Vector2(board.FX, FY) * scale_at + origin
	board.fill.scale = Vector2.ONE * CELL * scale_at
	var own_lines := board.lines
	board.lines = lines
	for i in range(0, board.coast.size(), 2):
		lines.seg(board.coast[i], board.coast[i + 1], board.coast_color(), 0.3, 0.05)
	board.draw_play()
	for q in board.qixes: board.draw_qix(q)
	board.sparks.draw(lines)
	board.lines = own_lines
	lines.zoom = Vector2.ONE
	lines.offset = Vector2.ZERO
	lines.zoom_center = Vector2(800, 450)

func draw_race_meter() -> void:
	var scores := race_scores()
	for side in 2:
		var bar := race_bar_rect(side)
		var x := bar.position.x
		var color := Palette.CYAN if side == 0 else RACE_COLOR
		var percent := scores[side] * 100.0 / maxi(1, base_free)
		hud_label("%s  %.1f%% / %d%%" % ["YOU" if side == 0 else "RACER", percent, encounter_goal()], Vector2(x, 104), 16, color)
		lines.rect(bar, Palette.DIM)
		lines.seg(bar.position + Vector2(0, 5), bar.position + Vector2(bar.size.x * clampf(percent / encounter_goal(), 0, 1), 5), color, 0, 0, 3)

func draw_race() -> void:
	draw_race_board(self, race_bounds, race_viewport(0))
	draw_race_board(race_opponent, race_bounds, race_viewport(1))
	lines.seg(Vector2(800, 180), Vector2(800, 740), Palette.DIM)
	draw_hud()
	label("FIRST TO %d%%" % encounter_goal(), Vector2(800, 161), 13, Palette.WHITE, 1)
	if race_opponent.state == State.DYING:
		label("RACER RECOVERING", Vector2(1135, 710), 13, RACE_COLOR, 1)
	if phase in ["briefing", "rival_tally"]:
		lines.modal_start = lines.count
		if phase == "briefing": draw_briefing()
		else: draw_rival_tally()

func finish_rival_contest() -> void:
	if not rival_tally.is_empty() or encounter_kind(level) != "rival": return
	var scores := rival_scores() # Live land only: unfinished trails, erosion and stolen land matter.
	rival_tally = {"player": scores.x, "rival": scores.y, "outcome": "win" if scores.x > scores.y else ("loss" if scores.x < scores.y else "tie")}
	rival_remaining = 0.0
	show_contest_tally()

func show_contest_tally() -> void:
	phase = "rival_tally"
	state = State.PLAYING # Keep the frozen board visible under the modal.
	selection = 0
	ui_time = 0.0
	msg_t = 0.0
	capture_flights.clear()
	displayed_capture = capture_percent
	if rival_tally.outcome == "win":
		if encounter_kind(level) == "race":
			award_flux(race_pending_salvage)
			race_pending_salvage = 0.0
		award_flux(3.0)
		reward_audio.stream = victory_cue
		reward_audio.play()

func accept_rival_tally() -> void:
	if phase != "rival_tally" or ui_time < 1.5: return
	var outcome: String = rival_tally.outcome
	if outcome == "win":
		if encounter_kind(level) == "race" and draft_ready():
			pending_clear = true
			begin_draft_reward()
			return
		level_clear()
		if phase == "sector_clear":
			ui_time = VICTORY_REVEAL
			continue_expedition()
		return
	if outcome == "loss": lives -= 1
	# Roll back this attempt's loot and drafts, retaining the hull damage it cost.
	for key in RIVAL_RETRY_FIELDS:
		var value = rival_entry[key]
		set(key, value.duplicate(true) if value is Array or value is Dictionary else value)
	if lives < 0:
		end_run()
		return
	start_level()
	phase = "briefing"
	state = State.PLAYING
	briefing_ready = false
	ui_time = 0.0
	boost_time = 0.0
	hardlight_time = 0.0
	freeze_time = 0.0
	safe_motion = 0.0
	hot_entry = false
	draw_armed = false
	containment_time = 0.0

func draw_rival_tally() -> void:
	lines.rect(Rect2(340, 230, 920, 420), Palette.CYAN, 0.0, 0.0, 1.2)
	var outcome: String = rival_tally.outcome
	var opponent_name := "RACER" if encounter_kind(level) == "race" else "RIVAL"
	label("YOU WIN" if outcome == "win" else (opponent_name + " WINS" if outcome == "loss" else "DRAW"), Vector2(800, 280), 30, Palette.GREEN if outcome == "win" else Palette.YELLOW, 1)
	var reveal := clampf(ui_time / 1.0, 0.0, 1.0)
	label("YOU", Vector2(570, 355), 18, Palette.CYAN, 1)
	label(opponent_name, Vector2(1030, 355), 18, RACE_COLOR if encounter_kind(level) == "race" else RIVAL_COLOR, 1)
	label("%.1f%%" % (100.0 * rival_tally.player / maxi(1, base_free) * reveal), Vector2(570, 395), 34, Palette.WHITE, 1)
	label("%.1f%%" % (100.0 * rival_tally.rival / maxi(1, base_free) * reveal), Vector2(1030, 395), 34, Palette.WHITE, 1)
	label("%d CELLS" % roundi(rival_tally.player * reveal), Vector2(570, 446), 13, Palette.DIM, 1)
	label("%d CELLS" % roundi(rival_tally.rival * reveal), Vector2(1030, 446), 13, Palette.DIM, 1)
	label("+3 SALVAGE" if outcome == "win" else ("-1 HULL" if outcome == "loss" else "NO HULL LOST"), Vector2(800, 493), 17, Palette.YELLOW, 1)
	if ui_time >= 1.5:
		button(0, "STAR CHART" if outcome == "win" else ("END EXPEDITION" if outcome == "loss" and lives == 0 else "RETRY"))

func rival_touched(c: Vector2i) -> void:
	if rival_active() and rival.exposed and rival.trail_at(c):
		rival.fail()

## Merged runs of the rival's coast, cached in field-local pixels like corruption strokes.
func rebuild_rival_segments() -> void:
	rival_segments.clear()
	rival_visual_dirty = false
	if rival_land.size() != cells.size():
		return
	for y in grid_height:
		var top_start := -1
		var bottom_start := -1
		for x in range(grid_width + 1):
			var i := y * grid_width + x
			var mine := x < grid_width and rival_land[i] == 1
			var top := mine and (y == 0 or rival_land[i - grid_width] == 0)
			var bottom := mine and (y == grid_height - 1 or rival_land[i + grid_width] == 0)
			if top and top_start < 0: top_start = x
			elif not top and top_start >= 0:
				rival_segments.append(Vector2(top_start * CELL, y * CELL))
				rival_segments.append(Vector2(x * CELL, y * CELL))
				top_start = -1
			if bottom and bottom_start < 0: bottom_start = x
			elif not bottom and bottom_start >= 0:
				rival_segments.append(Vector2(bottom_start * CELL, (y + 1) * CELL))
				rival_segments.append(Vector2(x * CELL, (y + 1) * CELL))
				bottom_start = -1
	for x in grid_width:
		var left_start := -1
		var right_start := -1
		for y in range(grid_height + 1):
			var i := y * grid_width + x
			var mine := y < grid_height and rival_land[i] == 1
			var left := mine and (x == 0 or rival_land[i - 1] == 0)
			var right := mine and (x == grid_width - 1 or rival_land[i + 1] == 0)
			if left and left_start < 0: left_start = y
			elif not left and left_start >= 0:
				rival_segments.append(Vector2(x * CELL, left_start * CELL))
				rival_segments.append(Vector2(x * CELL, y * CELL))
				left_start = -1
			if right and right_start < 0: right_start = y
			elif not right and right_start >= 0:
				rival_segments.append(Vector2((x + 1) * CELL, right_start * CELL))
				rival_segments.append(Vector2((x + 1) * CELL, y * CELL))
				right_start = -1

func draw_rival() -> void:
	if rival == null or not rival.alive or rival_land.size() != cells.size():
		return
	var home_pos := center(rival_home_cell)
	lines.circle(home_pos, (rival_home_radius + 0.7) * CELL, RIVAL_COLOR, 24, 0.0, 0.0, 1.2)
	# A small shield marks the permanent home without covering the cutter.
	lines.polyline(PackedVector2Array([home_pos + Vector2(-6, -5), home_pos + Vector2(6, -5), home_pos + Vector2(5, 3), home_pos + Vector2(0, 8), home_pos + Vector2(-5, 3)]), true, Color(RIVAL_COLOR, 0.5))
	if rival_visual_dirty:
		rebuild_rival_segments()
	var coast := RIVAL_COLOR
	coast.a = 0.55
	var origin := Vector2(FX, FY)
	for i in range(0, rival_segments.size(), 2):
		lines.seg(origin + rival_segments[i], origin + rival_segments[i + 1], coast, 0.4, 0.1, 1.0)
	if rival.trail.size() > 0:
		var pts := PackedVector2Array()
		pts.append(center(rival.anchor))
		for c in rival.trail:
			pts.append(center(c))
		lines.polyline(pts, false, RIVAL_COLOR, 2.2, 0.45, 1.3)
		lines.circle(center(rival.anchor), 4.0, RIVAL_COLOR, 8, 1.0, 0.3, 0.8)
	var hp := center(rival.pos)
	for pth in Hulls.paths("surveyor", hp, 7.0, 0.0, 0.0):
		lines.polyline(pth, false, RIVAL_COLOR)
	lines.seg(hp, hp + Vector2(rival.facing) * 9.0, RIVAL_COLOR, 0.0, 0.0, 1.0)

## In a rival sector both colours are baked into the one fill texture and it is drawn
## unmodulated; everywhere else Game's byte-identical dither and modulate tint stay in use.
func uses_race_palette() -> bool:
	return false # The opposing pilot opts in; the player keeps their normal territory.

func coast_color() -> Color:
	return RACE_COLOR if uses_race_palette() else super.coast_color()

func fill_color() -> Color:
	# Race stores its background/territory contrast in the texture alpha.
	return RACE_COLOR if uses_race_palette() else super.fill_color()

func current_theme() -> int:
	return authored_map.act_theme if authored_map != null else 0

func update_race_fill() -> void:
	var pixels := PackedByteArray()
	pixels.resize(grid_width * grid_height * 4)
	for y in grid_height:
		for x in grid_width:
			var i := idx(x, y)
			if cells[i] == ROCK: continue # Keep cutouts and the outside of either arena empty.
			var chevron := posmod(y - absi(x % 16 - 8), 12) == 0
			var opacity := 0.022 if chevron else 0.008
			if cells[i] == CLAIMED:
				opacity = 0.18 if chevron else 0.065
			pixels.encode_u32(i * 4, Color(1.0, 1.0, 1.0, opacity).to_abgr32())
	fill_img.set_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, pixels)
	fill_tex.update(fill_img)
	fill.modulate = fill_color()

func update_fill() -> void:
	if uses_race_palette():
		update_race_fill()
		return
	if rival_land.size() != cells.size():
		super.update_fill()
		return
	var dither := int(cur_gal().dither)
	var mine := fill_color()
	var mine_on := Color(mine.r, mine.g, mine.b, 0.16).to_abgr32()
	var mine_off := Color(mine.r * 0.5, mine.g * 0.5, mine.b * 0.5, 0.16).to_abgr32()
	var theirs_on := Color(RIVAL_COLOR.r, RIVAL_COLOR.g, RIVAL_COLOR.b, 0.16).to_abgr32()
	var theirs_off := Color(RIVAL_COLOR.r * 0.5, RIVAL_COLOR.g * 0.5, RIVAL_COLOR.b * 0.5, 0.16).to_abgr32()
	var rivalry := rival_land.size() == cells.size()
	var pixels := PackedByteArray()
	pixels.resize(grid_width * grid_height * 4)
	for y in grid_height:
		var row := y * grid_width
		for x in grid_width:
			var i := row + x
			var claimed := cells[i] == CLAIMED
			var theirs := rivalry and not claimed and rival_land[i] == 1
			if not claimed and not theirs: continue
			var on := false
			match dither:
				0: on = ((x + y) & 1) == 0
				1: on = (y & 1) == 0
				_: on = (x & 1) == 0 and (y & 1) == 0
			if claimed:
				pixels.encode_u32(i * 4, mine_on if on else mine_off)
			else:
				# Keep the rival's checkerboard identity across all acts.
				pixels.encode_u32(i * 4, theirs_on if ((x + y) & 1) == 0 else theirs_off)
	fill_img.set_data(grid_width, grid_height, false, Image.FORMAT_RGBA8, pixels)
	fill_tex.update(fill_img)
	fill.modulate = Color.WHITE

func start_level() -> void:
	boss.id = ""
	rival_entry.clear()
	if encounter_kind(level) in ["rival", "race"]:
		for key in RIVAL_RETRY_FIELDS:
			var value = get(key)
			rival_entry[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	authored_behaviors.clear()
	brood_eggs.clear()
	authored_map = MapCatalog.read(arena_stage(level))
	var territory: Dictionary = Acts.TERRITORY[clampi(current_theme() - 1, 0, Acts.TERRITORY.size() - 1)]
	for key in territory: gal[key] = territory[key]
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
	clear_rival() # The field rebuild below calls grid_changed; no stale rival may react to it.
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
	stall_time = 0.0
	surge.clear()
	surge_expired = 0
	surge_pressure = 0.0
	anchor = p
	if authored_map != null and authored_map.override_enemies:
		apply_authored_enemies()
	field_features.reset(self)
	boss.reset(self)
	if encounter_kind(level) == "race": setup_race()

func apply_authored_enemies() -> void:
	qixes.clear()
	sparxes.clear()
	sparx_to_spawn = 0
	for enemy in authored_map.enemies:
		var cell: Vector2i = enemy.cell
		if enemy.kind in MapCatalog.VOID_ENEMIES:
			super.spawn_qix()
			var q: QixBody = qixes.back()
			q.c = center(MapCatalog.nearest(field_arena.mask, authored_map.grid_size, cell, 2))
			# Keep the authored centre, fitting the initial beam into nearby geometry.
			while q.len > CELL and qix_blocked(q.c, q.theta, q.len): q.len *= 0.8
			if enemy.kind != "anomaly":
				if enemy.kind == "rotor":
					q.theta = 0.0
					q.omega = 1.6
				q.len = 80.0 if enemy.kind == "rotor" else 12.0
				while q.len > 2.0 and qix_blocked(q.c, q.theta, q.len): q.len *= 0.8
				authored_behaviors[q] = {"kind": enemy.kind, "phase": "roam", "clock": 2.4, "aim": q.theta}
				if enemy.kind == "chain_worm":
					var links: Array[QixBody] = []
					for i in 6:
						var link := QixBody.new()
						link.c = q.c
						link.len = 2.0
						qixes.append(link)
						links.append(link)
						authored_behaviors[link] = {"kind": "worm_link"}
					authored_behaviors[q].links = links
					authored_behaviors[q].path = [q.c]
				if enemy.kind == "brood_carrier":
					# A home tracks hatched mites without adding an automatic spawner.
					authored_behaviors[q].home = Spawner.new()
		elif enemy.kind == "sparx":
			var s := SparxBody.new()
			s.c = MapCatalog.nearest(field_arena.mask, authored_map.grid_size, cell, 1)
			s.prev = s.c
			s.vis = center(s.c)
			sparxes.append(s)

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
	pass # Act bosses are initialized after authored terrain and hazards are ready.

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
	return encounter_goal() / 100.0

func run_extra_lives() -> int:
	return progress.rank_of("hull") / 5

func movement_mult() -> float:
	var mult: float = 1.0 + progress.rank_of("engines") * 0.02 + draft_speed_stacks * 0.05
	if dash_time > 0.0: mult *= 3.0
	if drawing:
		if boost_time > 0.0:
			mult *= 1.0 + 0.8 * card_power("afterburner")
		if hot_entry and cut_time < (3.0 if progress.rank_of("engines") >= 10 else 2.0):
			mult *= 1.0 + 0.3 * (card_power("slipstream") if has_card("slipstream") else 1.0)
		mult *= 1.0 + small_chain * 0.15 * card_power("compression")
	return mult

func respawn_shield_duration() -> float:
	return 2.5 + progress.rank_of("hull") * 0.5 + draft_shield_stacks * 0.5

func sap_rate() -> float:
	var mult := 1.0 + 0.03 * progress.rank_of("reactor")
	if boost_time > 0.0:
		mult *= 1.0 + 0.8 * card_power("afterburner")
	if hot_entry and cut_time < (3.0 if progress.rank_of("engines") >= 10 else 2.0):
		mult *= 1.0 + 0.3 * (card_power("slipstream") if has_card("slipstream") else 1.0)
	mult *= 1.0 + small_chain * 0.15 * card_power("compression")
	return super.sap_rate() * mult * (card_power("charge") if has_card("charge") else 1.0)

func sap_radius() -> int:
	return roundi(super.sap_radius() * (card_power("charge") if has_card("charge") else 1.0))

func begin_attack() -> void:
	if hardlight_armed and (drawing or sap_live): start_hardlight()
	cut_time = 0.0
	hot_entry = safe_motion >= 2.0 and (has_card("slipstream") or progress.rank_of("engines") >= 5)
	safe_motion = 0.0

func fire_lance(extend := false) -> void:
	var was_drawing := drawing
	super.fire_lance(extend)
	if drawing and not was_drawing:
		begin_attack()
	if tether_active:
		for c in trail:
			rival_touched(c) # A cast ray cuts the rival's line where it crosses it.

func start_sapper_charge() -> void:
	super.start_sapper_charge()
	begin_attack()

func wire_hit() -> bool:
	if field_features.shielded(self): return false
	if ship.id == "sapper" and sap_live and disc_braced and hardening_time > 0.0:
		disc_braced = false
		hardening_time = 0.0
		# Let the absorbed contact separate before the next collision check.
		hardlight_time = maxf(hardlight_time, 0.25)
		return false
	if sap_live and not tether_hit(sap_cell):
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
	if race_rewards_locked():
		race_pending_salvage += amount
		return
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

func draft_bonus(id: String) -> Dictionary:
	match id:
		"draft_speed":
			return {"id": id, "name": "THRUSTER TUNING", "kind": "PASSIVE", "action": "BONUS", "desc": "Move faster for the rest of this expedition.", "stats": "+5% MOVEMENT SPEED", "detail": "NO SLOT / STACKS THIS RUN"}
		"draft_shield":
			return {"id": id, "name": "RECOVERY SHIELD", "kind": "PASSIVE", "action": "BONUS", "desc": "Stay protected longer after respawning.", "stats": "+0.5S RESPAWN PROTECTION", "detail": "NO SLOT / STACKS THIS RUN"}
	return {"id": "draft_salvage", "name": "SALVAGE CACHE", "kind": "CURRENCY", "action": "COLLECT", "desc": "Add salvage to your expedition earnings.", "stats": "+3 SALVAGE", "detail": "SPEND ON PERMANENT UPGRADES"}

func can_rescan_draft() -> bool:
	# Full builds have guaranteed upgrades/rewards, so rescanning cannot improve them.
	return not opening_draft_pending and owned_cards.size() < 3 and rerolls_left > 0

func roll_offers(avoid: Array[String] = []) -> void:
	if opening_draft_pending:
		offers.clear()
		for id in Cards.OPENING:
			var card := card_definition(id, 1)
			card.action = "NEW"
			offers.append(card)
		return
	if owned_cards.size() >= 3:
		offers.clear()
		for id in owned_cards:
			if card_rank(id) >= MAX_CARD_RANK: continue
			var card := card_definition(id, card_rank(id) + 1)
			card.action = "UPGRADE"
			offers.append(card)
		# Currency is always available when fewer than three upgrades remain.
		for id in ["draft_salvage", "draft_speed", "draft_shield"]:
			if offers.size() >= 3: break
			offers.append(draft_bonus(id))
		return
	var pool: Array[String] = []
	var excluded := draft_exclusions()
	for card in Cards.LIST:
		if Cards.OPENING.has(card.id) and not has_card(card.id): continue
		if Cards.SECONDARY.has(card.id) and not secondary_ability().is_empty() and not has_card(card.id): continue
		if not excluded.has(card.id) and not has_card(card.id):
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
	if not can_rescan_draft() or phase != "draft" or ui_time < DRAFT_REVEAL:
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
	if phase == "boss_clear":
		time += dt
		sparks.update(dt)
		if ui_time >= 1.8:
			boss.presented = true
			finish_sector()
		return
	if phase == "run" and state == State.PLAYING and encounter_kind(level) == "rival" and rival_remaining <= 0.0:
		finish_rival_contest()
		return
	if phase == "briefing":
		# A held launch/skip button must be released before accepting a new press.
		if not briefing_ready:
			if not Input.is_action_pressed("confirm") and not Input.is_action_pressed("draw"):
				briefing_ready = true
			return
		update_choices()
		return
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
				if draft_ready():
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
		if encounter_kind(level) == "rival" and rival_remaining <= 0.0:
			finish_rival_contest()
			return
		if draft_ready():
			begin_draft_reward()
		elif pending_clear:
			finish_sector()

func update_play(dt: float) -> void:
	if race_opponent == null:
		update_encounter_play(dt)
		return
	# Both boards receive the same small slice, including the slice of a finishing cut.
	# Drafts, briefings, pause and player death stop both boards between slices.
	var remaining := dt
	while remaining > 0.000001 and phase == "run" and state == State.PLAYING:
		if pending_clear or (draft_ready()): return
		var step := minf(remaining, 1.0 / 60.0)
		update_encounter_play(step)
		race_opponent.simulate(step)
		race_elapsed += step
		check_race_finish()
		remaining -= step

func accepts_player_input() -> bool:
	return true

func update_encounter_play(dt: float) -> void:
	# A capture may queue several drafts, including the final cut. No simulation
	# advances between that capture, its choices and settlement.
	if pending_clear or (draft_ready()):
		return
	if encounter_kind(level) == "rival":
		if rival_remaining <= 0.0:
			finish_rival_contest()
			return
		dt = minf(dt, rival_remaining)
		rival_remaining = maxf(0.0, rival_remaining - dt)
	if freeze_time <= 0.0: field_features.zone_time += dt
	field_features.zone_contact(self)
	if state != State.PLAYING or phase != "run": return
	objective_notice_time = maxf(0.0, objective_notice_time - dt)
	for key in cooldowns:
		cooldowns[key] = maxf(0.0, float(cooldowns[key]) - dt * (1.0 + 0.03 * progress.rank_of("reactor")))
	boost_time = maxf(0.0, boost_time - dt)
	hardlight_time = maxf(0.0, hardlight_time - dt)
	freeze_time = maxf(0.0, freeze_time - dt)
	containment_time = maxf(0.0, containment_time - dt)
	advance_objective_visuals(dt)
	update_surge_clock(dt)
	if accepts_player_input() and Input.is_action_just_pressed("br_harden"):
		activate_ability(movement_module())
	if accepts_player_input() and Input.is_action_just_pressed("special"):
		activate_ability(secondary_ability())
	charge_input_frame = sap_live and has_card("charge")
	update_movement_module(dt)
	if phase != "run" or state != State.PLAYING: return
	leap_input_frame = leap_building or wall_building
	var old_p := p
	if drawing or sap_live:
		cut_time += dt
	if ship.id == "lancer":
		lance_cd = maxf(0.0, lance_cd - dt * 0.03 * progress.rank_of("reactor"))
	super.update_play(dt)
	field_features.remember_walls(self, trail)
	if state != State.PLAYING or phase != "run" or pending_clear:
		return
	boss.update(self, dt)
	if state != State.PLAYING or phase != "run": return
	if not drawing and not sap_live and cells[idx(p.x, p.y)] == CLAIMED:
		if p != old_p or move_acc > 0.0:
			safe_motion += dt
		elif not Input.is_action_pressed("move_left") and not Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_up") and not Input.is_action_pressed("move_down"):
			safe_motion = 0.0
	update_rival(dt)
	if state != State.PLAYING or phase != "run":
		return
	var note := check_objectives()
	if not note.is_empty():
		set_msg(note, 1.2)
	settle_objective()
	if state != State.PLAYING or pending_clear:
		return
	# Expiry runs only after a frame that neither cleared nor died, so a lost surge
	# never lands on top of a sector clear.
	if not surge.is_empty() and float(surge.telegraph) <= 0.0 and float(surge.window) <= 0.0:
		expire_surge()
	update_corruption(dt)

func try_step(dir: Vector2i, draw_line: bool, slow: bool) -> bool:
	var was_drawing := drawing
	if ship.id == "sapper" and cells[idx(p.x, p.y)] == CLAIMED:
		anchor = p
	var moved := super.try_step(dir, draw_line, slow)
	if drawing and not was_drawing:
		begin_attack()
	check_cargo_contact() # Per step, so a fast frame cannot skip the pod's cell.
	rival_touched(p)
	field_features.zone_contact(self)
	return moved

func ride_step() -> void:
	super.ride_step()
	check_cargo_contact()
	rival_touched(p)
	field_features.zone_contact(self)

func activate_ability(id: String) -> void:
	if phase != "run" or state != State.PLAYING or not has_card(id) or float(cooldowns.get(id, 1.0)) > 0.0:
		return
	if id == "charge":
		if sap_live or leap_building or wall_building: return
		if not drawing and (cells[idx(p.x, p.y)] != CLAIMED or border[idx(p.x, p.y)] == 0): return
		stop_module_tether()
		if not drawing: anchor = p
		start_sapper_charge()
	elif id == "hardening":
		if wall_building or leap_building or not (drawing or sap_live): return
		hardening_time = 3.0 * card_power(id)
		disc_braced = sap_live
		cooldowns[id] = 12.0
	elif id == "leap":
		if sap_live or leap_building or wall_building: return
		stop_module_tether()
		start_leap()
		if not leap_building: return
		begin_attack()
	elif id == "dash":
		if leap_building or wall_building or sap_live or last_dir == Vector2i.ZERO: return
		dash_direction = tether_dir if tether_active else last_dir
		dash_time = 0.3 * card_power(id)
		cooldowns[id] = 8.0
	elif id == "afterburner":
		boost_time = 3.0
		cooldowns[id] = 14.0
	elif id == "hardlight":
		if hardlight_armed: return
		if drawing or sap_live or wall_building:
			start_hardlight()
		else:
			hardlight_armed = true
	sparks.ripple(vis, 5.0, 260.0, 0.6, Palette.CYAN)

func start_hardlight() -> void:
	hardlight_armed = false
	hardlight_time = 2.0 * card_power("hardlight")
	cooldowns.hardlight = 18.0

## Changing modules mid-ride keeps the travelled wire and drops the unused tether.
func stop_module_tether() -> void:
	if not tether_active: return
	for i in range(tether_i + 1, trail.size()):
		var c := trail[i]
		if cells[idx(c.x, c.y)] in [TRAIL, HARD]: cells[idx(c.x, c.y)] = FREE
	trail.resize(tether_i + 1)
	tether_active = false
	tether_i = -1
	move_acc = 0.0

func can_start_leap() -> bool:
	return drawing or super.can_start_leap()

func tether_hit(c: Vector2i) -> bool:
	if field_features.shielded(self) or field_features.zone_at(self, c) == 1: return false
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
		if authored_behaviors.has(q):
			update_authored_enemy(q, dt, speed)
			return
		super.update_qix(q, dt, speed)
		steer_anomaly(q, dt, speed)

func enemy_beam_length(q: QixBody, desired: float) -> float:
	var length := desired
	while length > 2.0 and qix_blocked(q.c, q.theta, length): length -= 2.0
	return maxf(2.0, length)

func move_authored_orb(q: QixBody, dt: float, speed: float) -> void:
	# Small steps keep the body from crossing thin rails or rock at low frame rates.
	var steps := maxi(1, ceili(speed * dt / 3.0))
	for step in steps:
		var delta := q.v.normalized() * speed * dt / steps
		if not qix_blocked(q.c + delta, q.theta, q.len):
			q.c += delta
		elif not qix_blocked(q.c + Vector2(-delta.x, delta.y), q.theta, q.len):
			q.v.x *= -1
			q.c += Vector2(-delta.x, delta.y)
		elif not qix_blocked(q.c + Vector2(delta.x, -delta.y), q.theta, q.len):
			q.v.y *= -1
			q.c += Vector2(delta.x, -delta.y)
		else: q.v = -q.v

func update_authored_enemy(q: QixBody, dt: float, speed: float) -> void:
	var behavior: Dictionary = authored_behaviors[q]
	if behavior.kind == "siege":
		if state == State.PLAYING and phase == "run": field_features.update_siege(self, q, dt, speed)
		return
	if behavior.kind == "worm_link": return
	if behavior.kind == "chain_worm":
		if state == State.PLAYING and phase == "run": update_chain_worm(q, dt, speed)
		return
	if behavior.kind == "brood_carrier":
		if state == State.PLAYING and phase == "run": update_brood_carrier(q, dt, speed)
		return
	if behavior.kind == "rotor":
		q.len = enemy_beam_length(q, q.len)
		var next_angle := q.theta + q.omega * dt * 0.65
		if qix_blocked(q.c, next_angle, q.len):
			q.omega = -q.omega
		else: q.theta = next_angle
		return
	# Entry/death animations may move enemies, but never spend attack timers or fire.
	if state != State.PLAYING or phase != "run": return
	behavior.clock -= dt
	match String(behavior.phase):
		"roam":
			q.len = enemy_beam_length(q, 12.0)
			move_authored_orb(q, dt, speed * 0.55)
			if behavior.clock <= 0.0:
				behavior.phase = "warn"
				behavior.clock = 0.85 if behavior.kind == "gunner_orb" else 1.15
				behavior.aim = (vis - q.c).angle()
				q.theta = behavior.aim
		"warn":
			if behavior.clock <= 0.0:
				if behavior.kind == "gunner_orb":
					for i in 5:
						var bolt := Bolt.new()
						bolt.vel = Vector2.RIGHT.rotated(float(behavior.aim) + (i - 2) * 0.22) * 125.0
						bolt.pos = q.c
						bolt.source = "GUNNER ORB FIRE"
						bolts.append(bolt)
					behavior.phase = "roam"
					behavior.clock = 3.2
				else:
					behavior.phase = "fire"
					behavior.clock = 1.1
		"fire":
			var extension := sin(PI * clampf(1.0 - float(behavior.clock) / 1.1, 0.0, 1.0))
			q.len = enemy_beam_length(q, 12.0 + 164.0 * extension)
			if behavior.clock <= 0.0:
				q.len = enemy_beam_length(q, 12.0)
				behavior.phase = "roam"
				behavior.clock = 3.6

func worm_path_point(path: Array, distance: float) -> Vector2:
	for i in range(1, path.size()):
		var length: float = path[i - 1].distance_to(path[i])
		if length >= distance: return path[i - 1].lerp(path[i], distance / maxf(length, 0.001))
		distance -= length
	return path.back()

func update_chain_worm(q: QixBody, dt: float, speed: float) -> void:
	var behavior: Dictionary = authored_behaviors[q]
	var path: Array = behavior.path
	var steps := maxi(1, ceili(speed * 0.65 * dt / 2.0))
	for step in steps:
		move_authored_orb(q, dt / steps, speed * 0.65)
		if q.c.distance_to(path[0]) > 0.25: path.push_front(q.c)
	# Keep a short spatial history; the tail follows turns instead of swinging through walls.
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
		if length > 100.0:
			path.resize(i + 1)
			break
	var front := q.c
	for i in behavior.links.size():
		var back := worm_path_point(path, (i + 1) * 14.0)
		var link: QixBody = behavior.links[i]
		link.c = (front + back) * 0.5
		link.theta = (front - back).angle()
		link.len = maxf(2.0, front.distance_to(back))
		if qix_blocked(link.c, link.theta, link.len):
			link.c = back
			link.len = 2.0
		front = back

func update_brood_carrier(q: QixBody, dt: float, speed: float) -> void:
	var behavior: Dictionary = authored_behaviors[q]
	behavior.clock -= dt
	if behavior.phase == "roam":
		move_authored_orb(q, dt, speed * 0.4)
		if behavior.clock <= 0:
			behavior.phase = "warn"
			behavior.clock = 0.9
	elif behavior.clock <= 0:
		var home: Spawner = behavior.home
		var count := home.alive
		for egg in brood_eggs:
			if egg.home == home: count += 1
		var cell := to_cell(q.c)
		var occupied := brood_eggs.any(func(egg: Dictionary) -> bool: return egg.cell == cell)
		if count < 4 and not occupied and in_bounds(cell) and cells[idx(cell.x, cell.y)] == FREE:
			brood_eggs.append({"cell": cell, "clock": 6.0, "home": home})
		behavior.phase = "roam"
		behavior.clock = 4.0

func update_brood_eggs(dt: float) -> void:
	for i in range(brood_eggs.size() - 1, -1, -1):
		var egg := brood_eggs[i]
		var cell: Vector2i = egg.cell
		if cells[idx(cell.x, cell.y)] == CLAIMED:
			award_flux(0.25)
			sparks.burst(center(cell), 16, 120, 1.0, 0.4, Palette.GREEN)
			brood_eggs.remove_at(i)
			continue
		egg.clock -= dt
		# A live trail can still close over an egg at the last moment.
		if dt > 0.0 and egg.clock <= 0 and cells[idx(cell.x, cell.y)] == FREE:
			var mite := Mite.new()
			mite.pos = center(cell)
			mite.vel = (vis - mite.pos).normalized() * 40.0
			mite.home = egg.home
			mite.home.alive += 1
			mites.append(mite)
			brood_eggs.remove_at(i)
			sparks.ripple(mite.pos, 4, 120, 0.4, Palette.PURPLE)

func draw_hazards() -> void:
	super.draw_hazards()
	field_features.draw(self)
	for egg in brood_eggs:
		var pos := center(egg.cell)
		var color := Palette.YELLOW if egg.clock < 2.0 else Palette.PURPLE
		lines.circle(pos, 5, color, 8)
		arc(pos, 9, -PI / 2, -PI / 2 + TAU * clampf(egg.clock / 6.0, 0.01, 1.0), color, 1.0)

func draw_qix(q: QixBody) -> void:
	if not authored_behaviors.has(q):
		super.draw_qix(q)
		return
	var behavior: Dictionary = authored_behaviors[q]
	if behavior.kind == "siege":
		field_features.draw_siege(self, q)
		return
	if behavior.kind in ["chain_worm", "worm_link"]:
		var ends := qix_ends(q.c, q.theta, q.len)
		lines.seg(ends[0], ends[1], anomaly_color(q.col_off), 2.0, 0.5, 2.0)
		draw_anomaly_ring(q.c, 6 if behavior.kind == "chain_worm" else 3, 6, q.col_off)
		if behavior.kind == "chain_worm": lines.circle(q.c, 2, Palette.WHITE, 4)
		return
	if behavior.kind == "brood_carrier":
		draw_anomaly_ring(q.c, 9, 6, q.col_off, 1.5)
		for side in [-1, 1]: draw_anomaly_ring(q.c + Vector2(side * 11, 0), 4, 6, q.col_off + 3)
		if behavior.phase == "warn": lines.circle(q.c, 15 + sin(time * 12) * 2, Palette.YELLOW, 12)
		return
	var color := Palette.ORANGE if behavior.kind == "gunner_orb" else (Palette.CYAN if behavior.kind == "ray_orb" else Palette.YELLOW)
	if behavior.kind == "rotor":
		var ends := qix_ends(q.c, q.theta, q.len)
		lines.seg(ends[0], ends[1], color, 0.2, 0.05, 2.0)
		for end in ends: lines.circle(end, 4, color, 6)
		lines.circle(q.c, 6, color, 8)
		return
	draw_anomaly_ring(q.c, 7, 10, q.col_off, 1.4)
	if behavior.kind == "gunner_orb":
		for i in 3:
			var angle := time * 0.8 + i * TAU / 3.0
			lines.seg(q.c + Vector2.RIGHT.rotated(angle) * 9, q.c + Vector2.RIGHT.rotated(angle) * 14, anomaly_color(q.col_off + i * 2), 2.0, 0.5)
	if behavior.phase == "warn":
		lines.circle(q.c, 12 + sin(time * 20) * 2, color, 16)
		if behavior.kind == "ray_orb":
			var ends := qix_ends(q.c, q.theta, enemy_beam_length(q, 176.0))
			dashed(ends[0], ends[1], Color(color, 0.5), 5, 5)
	elif behavior.phase == "fire":
		var ends := qix_ends(q.c, q.theta, q.len)
		lines.seg(ends[0], ends[1], Palette.WHITE, 0.2, 0.05, 2.2)

func qix_contact_reason(q: QixBody) -> String:
	if authored_behaviors.has(q) and authored_behaviors[q].kind == "worm_link": return "CHAIN WORM CONTACT"
	if authored_behaviors.has(q): return String(authored_behaviors[q].kind).replace("_", " ").to_upper() + " CONTACT"
	return super.qix_contact_reason(q)

func update_sparx(s: SparxBody, dt: float) -> void:
	if freeze_time <= 0.0:
		super.update_sparx(s, dt)

func update_hazards(dt: float) -> void:
	if freeze_time <= 0.0:
		super.update_hazards(dt)
		if state == State.PLAYING and phase == "run": update_brood_eggs(dt)
		field_features.update(self, dt)

func die(reason: String) -> void:
	if invuln > 0.0 or field_features.shielded(self):
		return
	reset_movement_module()
	corruption_visual_dirty = true
	if (drawing or sap_live or (ship.id == "sapper" and cells[idx(p.x, p.y)] == FREE)) and has_card("anchor") and float(cooldowns.anchor) <= 0.0:
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
		stall_time = 0.0
		return
	super.die(reason)
	drop_cargo()
	exposure = 0.0
	safe_motion = 0.0
	stall_time = 0.0

func complete_claim() -> void:
	field_features.remember_walls(self, trail)
	super.complete_claim()

func preserve_live_capture() -> bool:
	return super.preserve_live_capture() or (not pending_clear and phase in ["reward", "draft", "install", "replace"])

func capture_flood_seeds() -> PackedInt32Array:
	var seeds := PackedInt32Array()
	for q in qixes:
		if authored_behaviors.get(q, {}).get("kind", "") == "rotor": continue
		var ci := qix_cell_index(q)
		if ci >= 0: seeds.append(ci)
	if not seeds.is_empty(): return seeds
	# Maps containing only capturable hazards still claim the smaller enclosed
	# regions, rather than giving away the entire board on the first cut.
	var visited := PackedByteArray()
	visited.resize(cells.size())
	var largest := 0
	var seed_cell := -1
	for start in cells.size():
		if cells[start] != FREE or visited[start]: continue
		var region := PackedInt32Array([start])
		visited[start] = 1
		var head := 0
		while head < region.size():
			var i := region[head]
			head += 1
			var x := i % grid_width
			var y := i / grid_width
			for next in [i - 1 if x > 0 else -1, i + 1 if x + 1 < grid_width else -1, i - grid_width if y > 0 else -1, i + grid_width if y + 1 < grid_height else -1]:
				if next >= 0 and cells[next] == FREE and not visited[next]:
					visited[next] = 1
					region.append(next)
		if region.size() > largest:
			largest = region.size()
			seed_cell = start
	if seed_cell >= 0: seeds.append(seed_cell)
	return seeds

func capture_extra_hazards() -> int:
	var caught := super.capture_extra_hazards() + field_features.capture_snipers(self)
	for i in range(qixes.size() - 1, -1, -1):
		var q: QixBody = qixes[i]
		if authored_behaviors.get(q, {}).get("kind", "") != "rotor": continue
		var cell := to_cell(q.c)
		if not in_bounds(cell) or cells[idx(cell.x, cell.y)] != CLAIMED: continue
		sparks.burst(q.c, 40, 180, 1.5, 0.5, Palette.GREEN)
		sparks.ripple(q.c, 5, 240, 0.4, Palette.GREEN)
		authored_behaviors.erase(q)
		qixes.remove_at(i)
		caught += 1
	return caught

func lose_seal(seal: Seal) -> void:
	if seal != null: field_features.remember_walls(self, seal.cells)
	super.lose_seal(seal)

func race_rewards_locked() -> bool:
	return encounter_kind(level) == "race" and rival_tally.get("outcome", "") != "win"

func draft_ready() -> bool:
	return not race_rewards_locked() and drafts_taken < draft_capture.size() and draft_progress() >= draft_capture[drafts_taken]

func draft_progress() -> float:
	return capture_percent + field_features.lost_land.size() * 100.0 / maxi(1, base_free)

func on_claim(gained: int, caught: int) -> void:
	update_brood_eggs(0.0)
	field_features.on_claim(self)
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
	# Erosion reduces the territory goal, while drafts still use first-time captures.
	capture_percent = (first_claims - field_features.lost_land.size()) * 100.0 / maxi(1, base_free)
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
	var milestone := draft_ready()
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
	for sniper in field_features.snipers:
		if not sniper.captured: has_capture_target = true
	if not has_capture_target:
		excluded.append("harvest")
	return excluded

func begin_draft_reward() -> void:
	if race_rewards_locked(): return
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
	if boss.active():
		hud_label(Acts.BOSSES[boss.id].name + " / " + boss.instruction(), Vector2(CAPTURE_BAR.position.x, 104), 15, Palette.YELLOW)
		for i in 3:
			var rect := Rect2(CAPTURE_BAR.position + Vector2(i * (CAPTURE_BAR.size.x / 3), 0), Vector2(CAPTURE_BAR.size.x / 3 - 10, CAPTURE_BAR.size.y))
			lines.rect(rect, Palette.GREEN if boss.relays[i].captured else Palette.DIM)
			if boss.relays[i].captured: lines.seg(rect.position + Vector2(2, 5), rect.end - Vector2(2, 5), Palette.GREEN, 0, 0, 3)
		return
	if race_opponent != null:
		draw_race_meter()
		return
	var goal := encounter_goal()
	var kind := encounter_kind(level)
	var color := Palette.GREEN if Sectors.territory_goal(kind) and displayed_capture >= goal else Palette.CYAN
	hud_label(objective_label(), Vector2(CAPTURE_BAR.position.x, 104), 13, Palette.DIM)
	if objective_notice_time > 0.0 and kind != "rival":
		hud_label(objective_notice, Vector2(CAPTURE_BAR.position.x + 400, 104), 12, Palette.YELLOW)
	if kind == "breach" and not breach.is_empty():
		var pressure := int(round(100.0 * float(breach.pressure)))
		var hot := not bool(breach.sealed) and float(breach.pressure) >= 0.15
		hud_label("BREACH SEALED" if bool(breach.sealed) else "ARENA %d%% / 25%%" % pressure, Vector2(CAPTURE_BAR.position.x + 180, 104), 12, Palette.MAGENTA if hot else Palette.DIM)
	var area_text := "%.1f%%" % displayed_capture
	if kind == "rival":
		var scores := rival_scores()
		hud_label("YOU %.1f%%  /  RIVAL %.1f%%" % [scores.x * 100.0 / maxi(1, base_free), scores.y * 100.0 / maxi(1, base_free)], Vector2(CAPTURE_BAR.position.x + 250, 104), 13, Palette.CYAN)
	if not Sectors.territory_goal(kind): area_text = "TERRITORY " + area_text
	VectorFont.draw(lines, area_text, Vector2(CAPTURE_BAR.end.x, 102), 18, color, 0.0, 0.0, 2)
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
	if offers[index].get("action", "") not in ["BONUS", "COLLECT"] and not has_card(offers[index].id) and owned_cards.size() >= 3 and replace_id.is_empty():
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
	if offers[index].get("action", "") in ["BONUS", "COLLECT"]:
		match id:
			"draft_speed": draft_speed_stacks += 1
			"draft_shield": draft_shield_stacks += 1
			"draft_salvage": earned_salvage += 3
		pending_card.clear()
		replace_id = ""
		finish_draft()
		return
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
		if replace_id == "hardlight":
			hardlight_time = 0.0
			hardlight_armed = false
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
	if draft_ready():
		open_draft()
	elif pending_clear:
		finish_sector()
	else:
		phase = "run"
		state = State.PLAYING
		draw_armed = false
		ui_time = 0.0

func level_clear() -> void:
	if encounter_kind(level) == "boss" and not boss.defeated: return
	pending_clear = true
	run_victory = level >= sector_limit
	run_sectors = level
	if phase not in ["draft", "reward", "install", "replace"]:
		finish_sector()

func finish_sector() -> void:
	if settled or phase in ["sector_clear", "chart"]: return
	if boss.active() and boss.defeated:
		if not boss.rewarded:
			boss.rewarded = true
			award_flux(Acts.BOSSES[boss.id].reward)
			lives = mini(lives + 1, 2 + run_extra_lives())
		if not boss.presented:
			phase = "boss_clear"
			state = State.REPORT
			ui_time = 0
			return
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
	clear_race()
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
	var bounds := chart_bounds()
	chart_focus_depth = clampi(chart_focus_depth + direction.x, bounds.x, bounds.y)
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
	clear_rival()
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

func update_intro(dt: float) -> void:
	super.update_intro(dt)
	if phase == "run" and state == State.PLAYING:
		phase = "briefing"
		selection = 0
		ui_time = 0.0
		briefing_ready = false
		shake_off = Vector2.ZERO

func begin_sector() -> void:
	if phase != "briefing" or not briefing_ready or ui_time < choice_delay(): return
	phase = "run"
	ui_time = 0.0
	draw_armed = false

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
	clear_rival()
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
	if phase == "rival_tally": return 1.5
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
	if phase == "rival_tally":
		accept_rival_tally()
	elif phase == "briefing":
		begin_sector()
	elif phase == "chart":
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
	if phase == "rival_tally": return Rect2(580, 560, 440, 64)
	if phase == "briefing":
		return Rect2(580, 452, 440, 64)
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
	Controls.observe_input(event)
	var host := get_parent() as Game
	if host != null and host.state == State.ROGUELITE and phase == "draft":
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and keep_build_rect().has_point(event.position):
			keep_build()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("reroll"):
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
				var bounds := chart_bounds()
				for depth in range(bounds.x, bounds.y + 1):
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

func draw_arena() -> void:
	super.draw()

func draw() -> void:
	if phase == "boss_clear":
		super.draw()
		label("CORE CAPTURED", Vector2(800, 210), 30, Palette.GREEN, 1)
		return
	battle_fill.visible = false
	if race_opponent != null:
		race_opponent.fill.visible = false
		if phase in ["run", "reward", "briefing", "rival_tally"]:
			draw_race()
			return
	fill.modulate = Color.WHITE if rival_land.size() == cells.size() else fill_color() # See update_fill.
	if phase == "rival_tally":
		super.draw()
		lines.modal_start = lines.count
		lines.offset = Vector2.ZERO
		lines.zoom = Vector2.ONE
		draw_rival_tally()
		return
	if phase == "briefing":
		super.draw()
		lines.modal_start = lines.count
		lines.offset = Vector2.ZERO
		lines.zoom = Vector2.ONE
		draw_briefing()
		return
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

## Shared briefing/pause copy follows the current ship, upgrades and breach state.
func corruption_help() -> Array[String]:
	var contact := "ANY UNFINISHED TRAIL IN PURPLE"
	if ship.id == "sapper": contact = "STANDING ON PURPLE"
	var seconds := 4.0 / (1.0 - 0.03 * progress.rank_of("containment"))
	var result: Array[String] = [
		"%s: 100%% EXPOSURE = HULL HIT (%.1fS)." % [contact, seconds],
		"CAPTURE TO CLEANSE AND RESET. AVOID PURPLE TO LOWER EXPOSURE.",
	]
	if encounter_kind(level) == "breach" and bool(breach.get("sealed", false)):
		result.append("SEALED: SPREAD STOPPED. REMAINING PURPLE STILL CAUSES EXPOSURE.")
	else:
		if encounter_kind(level) == "breach":
			result.append("SPREADS EVERY 3S; SEAL TO STOP. ARENA 25% = HIT EVEN ON SAFE LAND.")
		else:
			result.append("PURPLE SPREADS EVERY 3S.")
	return result

func draw_corruption_help(pos: Vector2, width: float, size: float, row_height: float) -> void:
	for section in corruption_help():
		for row in paragraph_lines(section, width, size):
			hud_label(row, pos, size)
			pos.y += row_height
		pos.y += 8

func draw_briefing() -> void:
	var kind := encounter_kind(level)
	lines.rect(BRIEFING_PANEL, Palette.CYAN, 0.0, 0.0, 1.2)
	var goal := "CAPTURE %d%%" % encounter_goal()
	match kind:
		"boss": goal = boss.instruction()
		"race": goal = "RACE: FIRST TO %d%%" % encounter_goal()
		"rival": goal = "OWN MORE TERRITORY IN %d SECONDS" % int(Encounters.seconds(authored_map, "rival"))
		"cargo": goal = "DELIVER CARGO TO SAFE LAND (%d)" % int(cargo.get("runs", 0))
		"beacon": goal = "ENCLOSE %d BEACONS" % zones.size()
		"breach": goal = "SEAL BREACH + " + goal
	var rows := paragraph_lines(goal, 740, 26)
	if kind == "boss" and boss.active():
		label(Acts.BOSSES[boss.id].name, Vector2(800, 340), 18, Acts.ACTS[Acts.BOSSES[boss.id].act - 1].color, 1)
	for i in rows.size():
		label(rows[i], Vector2(800, 365 + i * 36), 26, Palette.WHITE, 1)
	button(0, "START")

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
	label(Controls.hint("ARROWS: BROWSE    ENTER: %s    ESC: BACK") % enter_action, Vector2(950, 815), 13, Palette.DIM, 1)

func ship_controls(id: String) -> String:
	match id:
		"lancer": return Controls.hint("ARROWS / WASD: AIM\nSPACE: LANCE + RIDE")
		"bulwark": return Controls.hint("ARROWS / WASD: MOVE\nHOLD SPACE: DRAW + HARDEN\nRELEASE: BRACE")
		"sapper": return Controls.hint("ARROWS / WASD: MOVE\nHOLD SPACE: CHARGE\nRELEASE: DETONATE")
	return Controls.hint("ARROWS / WASD: MOVE\nSPACE: DRAW\nSHIFT: SLOW DRAW")

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
		label(["DRAW AND ENCLOSE", "FIRE A LINE. RIDE IT.", "DRAW. HARDEN. CAPTURE."][i], r.position + Vector2(225, 357), 17, Palette.WHITE, 1)
		var action := ship_action_rect(i)
		var affordable: bool = progress.salvage >= Progress.SHIP_PRICE
		lines.rect(action, Palette.GREEN if active else (Palette.CYAN if owned else (Palette.YELLOW if affordable else Palette.RED)))
		if owned:
			label("SELECTED" if active else "SELECT", action.position + Vector2(195, 19), 16, Palette.GREEN if active else Palette.CYAN, 1)
		else:
			draw_currency_caption("UNLOCK", str(Progress.SHIP_PRICE), false, action.get_center(), "", affordable, Palette.CYAN if affordable else Palette.RED)
	label("UPGRADES APPLY TO EVERY SHIP", Vector2(800, 724), 13, Palette.DIM, 1)
	label(Controls.hint("ARROWS: BROWSE    ENTER: SELECT / UNLOCK    ESC: BACK"), Vector2(950, 815), 13, Palette.DIM, 1)

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
	if id == "draft_salvage": return Palette.YELLOW
	if id == "draft_speed": return Palette.ORANGE
	if id in ["afterburner", "slipstream", "compression", "dash", "leap"]:
		return Palette.ORANGE
	if id in ["ion", "stasis", "loop"]:
		return Palette.PURPLE
	return Palette.CYAN

func draw_card_icon(id: String, center_at: Vector2, color: Color, scale_at := 1.0) -> void:
	# Slot-free rewards reuse the established speed, shield and salvage symbols.
	id = {"draft_speed": "slipstream", "draft_shield": "hardlight", "draft_salvage": "harvest"}.get(id, id)
	var paths: Array = []
	match id:
		"charge":
			lines.circle(center_at, 42 * scale_at, color, 24)
			lines.circle(center_at, 22 * scale_at, color, 16)
			paths = [[-12, 0, 12, 0], [0, -12, 0, 12]]
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
	var title := "MOVEMENT" if opening_draft_pending else ("UPGRADE SYSTEMS" if owned_cards.size() >= 3 else "POWER UP")
	if owned_cards.size() >= 3 and not offers.any(func(card: Dictionary) -> bool: return card.get("action", "") == "UPGRADE"):
		title = "EXPEDITION BONUS"
	label("REWARD APPLIED" if installing else title, Vector2(800, 130), 38, Palette.GREEN if installing else Palette.WHITE, 1)
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
		var kind: String = card.kind
		if Cards.OPENING.has(card.id):
			kind = ("HOLD " if card.id in ["leap", "charge"] else "") + Controls.action_label("br_harden", "Q")
		elif Cards.SECONDARY.has(card.id):
			kind = Controls.action_label("special", "E")
		label(kind, r.position + Vector2(24, 25), 12, Color(color, opacity))
		var action: String = card.get("action", "NEW")
		var badge := action if action in ["BONUS", "COLLECT"] else "%s / %s" % [action, ["I", "II", "III"][int(card.get("rank", 1)) - 1]]
		label(badge, Vector2(r.end.x - 24, r.position.y + 25), 12, Color(Palette.GREEN if int(card.get("rank", 1)) > 1 else color, opacity), 2)
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
		label(Controls.hint("ARROWS + ENTER / CLICK"), Vector2(800, 803), 12, Palette.DIM, 1)
		if owned_cards.size() == 3:
			lines.rect(keep_build_rect(), Palette.DIM)
			label(Controls.hint("ESC: KEEP BUILD"), keep_build_rect().position + Vector2(16, 14), 13, Palette.DIM)
		if can_rescan_draft():
			lines.rect(reroll_rect(), Palette.CYAN)
			label("%s: RESCAN %d" % [Controls.action_label("reroll", "R"), rerolls_left], reroll_rect().position + Vector2(16, 14), 13, Palette.CYAN)

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
	label(Controls.hint("ENTER: REPLACE    ESC: KEEP CURRENT BUILD"), Vector2(800, 795), 14, Palette.DIM, 1)

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
	label(("ACT CLEAR" if boss.defeated else "SECTOR CLEAR") if phase == "sector_clear" else "EXPEDITION COMPLETE", Vector2(800, 116), 42, color, 1)
	if ui_time >= 0.5:
		draw_salvage("+%d" % victory_salvage_shown(), Vector2(800, 533), 58, 1)
	if ui_time >= 1.8 and phase != "sector_clear":
		label("%d SECTORS SECURED" % run_sectors, Vector2(800, 630), 16, Palette.DIM, 1)
	if ui_time >= VICTORY_REVEAL:
		button(0, ("NEXT ACT" if boss.defeated else "STAR CHART") if phase == "sector_clear" else ("RETRY SAVE" if save_failed else "HANGAR"))
		if phase == "sector_clear": label(Controls.hint("ESC: BANK AND EXIT"), Vector2(800, 810), 13, Palette.DIM, 1)
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
	var stage_name := "ACT %d / %s" % [Acts.act_at(level), Acts.ACTS[Acts.act_at(level) - 1].name] if current_theme() > 0 else "%s / %02d-%02d" % [ship.name, level, sector_limit]
	hud_label(stage_name, Vector2(FIELD_X, 61), 18)
	draw_hull_icons(Vector2(1254, 70), maxi(0, lives + 1))
	draw_dock_currency(Vector2(1374, 70), str(earned_salvage), false)
	draw_draft_meter()
	hud_label(Controls.hint("ESC  PAUSE"), Vector2(FIELD_X, 794), 12, Palette.DIM)
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
			var ability_key := Controls.action_label("special", "E") if Cards.SECONDARY.has(id) else Controls.action_label("br_harden", "Q")
			hud_label(ability_key, r.position + Vector2(0, 80), 9 if ability_key.length() > 2 else 13)
		if id == "hardlight" and hardlight_armed:
			hud_label("ARMED", r.position + Vector2(24, 98 if Controls.using_controller else 80), 12, Palette.GREEN)
		elif active > 0.0 or cooldown > 0.0:
			hud_label("%.1fS" % (active if active > 0.0 else cooldown), r.position + Vector2(24, 98 if Controls.using_controller else 80), 12, Palette.GREEN if active > 0.0 else Palette.DIM)
	if corruption_active:
		VectorFont.draw(lines, "PERSONAL EXPOSURE %d%%" % int(clampf(exposure / 4.0, 0.0, 1.0) * 100), Vector2(1440, 790), 13, Palette.MAGENTA, 0.0, 0.0, 2)
		VectorFont.draw(lines, "100% = HULL HIT / CAPTURE TO RESET", Vector2(1440, 814), 11, Palette.DIM, 0.0, 0.0, 2)

func draw_pause() -> void:
	label("PAUSED", Vector2(240, 100), 34)
	hud_label("OBJECTIVE: " + objective_instruction(), Vector2(240, 152), 13, Palette.CYAN)
	hud_label("CONTROLS", Vector2(240, 191), 16, Palette.CYAN)
	paragraph(ship_controls(ship.id), Vector2(240, 235), 36, 15)
	if draft_speed_stacks > 0 or draft_shield_stacks > 0:
		hud_label("RUN BONUSES / +%d%% MOVE SPEED / +%.1fS RESPAWN SHIELD" % [draft_speed_stacks * 5, draft_shield_stacks * 0.5], Vector2(240, 660), 12, Palette.GREEN)
	if corruption_active:
		hud_label("CORRUPTION", Vector2(240, 370), 15, Palette.MAGENTA)
		draw_corruption_help(Vector2(240, 404), 540, 13, 20)
		var ranks: Array[String] = []
		for track in Progress.TRACKS:
			ranks.append("%s %d" % [track.to_upper(), progress.rank_of(track)])
		hud_label("UPGRADES / " + "   ".join(ranks), Vector2(240, 685), 12, Palette.DIM)
	else:
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
	sweep_rival() # Before the fill rebuild below, so stolen rival land never flashes twice.
	super.grid_changed()
	if encounter_kind(level) == "race":
		race_claimed = 0
		for i in cells.size():
			if field_arena.mask[i] == 2 and cells[i] == CLAIMED: race_claimed += 1
	corruption_visual_dirty = true
	stall_time = 0.0 # Any land change, including blasts and hardened walls, is progress.

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
	boss.draw(self)
	if sap_live and has_card("charge"):
		lines.circle(center(sap_cell), sap_radius() * CELL, Color(Palette.YELLOW, 0.3), 32)
		lines.circle(center(sap_cell), sap_charge * CELL, Palette.YELLOW, 32, 0.3, 0.05, 1.2)
	if drawing and (hardlight_time > 0.0 or (has_card("phase") and cut_time < 1.5 * card_power("phase"))):
		lines.polyline(trail_points(), false, Palette.CYAN, 0.3, 0.1, 2.0)

func chart_bounds() -> Vector2i:
	if route.size() != Acts.LENGTH: return Vector2i(1, route.size())
	var first := (Acts.act_at(chart_depth) - 1) * Acts.ACT_LENGTH + 1
	return Vector2i(first, first + Acts.ACT_LENGTH - 1)

func chart_position(depth: int, branch: int) -> Vector2:
	var count: int = route[depth - 1].size()
	var bounds := chart_bounds()
	var pos := Vector2(180 + (depth - bounds.x) * (1240.0 / maxi(1, bounds.y - bounds.x)), 370 + (branch - (count - 1) * 0.5) * 210)
	if route.size() == Acts.LENGTH:
		var step := depth - bounds.x
		match Acts.act_at(chart_depth):
			2: pos.y += sin(step * PI * 0.5) * 55.0
			3: pos.y += sin(step * PI * 0.5) * 35.0
	return pos

func draw_act_chart_backdrop(act: int) -> void:
	var tint: Color = Acts.ACTS[act - 1].color
	var backdrop := Color(tint * 0.28, 0.10)
	# Each galaxy repeats its arena motif at a much larger scale.
	match act:
		1:
			for x in range(100, 1510, 95):
				for y in range(205, 645, 72):
					lines.polyline(PackedVector2Array([Vector2(x, y + 12), Vector2(x, y), Vector2(x + 22, y)]), false, backdrop)
		2:
			for strand in 7:
				var points := PackedVector2Array()
				for x in range(85, 1520, 24):
					points.append(Vector2(x, 248 + strand * 52 + sin(x * 0.006 + strand * 0.8) * 34))
				lines.polyline(points, false, backdrop)
		3:
			for radius in range(110, 710, 70):
				var points := PackedVector2Array()
				for i in 65:
					var angle := i * TAU / 64.0
					points.append(Vector2(800, 405) + Vector2(cos(angle) * radius, sin(angle) * radius * 0.31))
				lines.polyline(points, true, backdrop)
	label("ACT %d / %s" % [act, Acts.ACTS[act - 1].name], Vector2(800, 145), 26, tint, 1)

func draw_chart_symbol(kind: String, pos: Vector2, color: Color) -> void:
	match kind:
		"race":
			lines.seg(pos + Vector2(-8, 13), pos + Vector2(-8, -13), color, 0, 0, 1.5)
			lines.rect(Rect2(pos + Vector2(-8, -13), Vector2(20, 15)), color)
			for x in 4:
				for y in 3:
					if (x + y) % 2 == 0:
						lines.seg(pos + Vector2(-6 + x * 5, -11 + y * 5), pos + Vector2(-3 + x * 5, -11 + y * 5), color, 0, 0, 2)
		"repair":
			lines.seg(pos - Vector2(9, 0), pos + Vector2(9, 0), color, 0, 0, 1.5)
			lines.seg(pos - Vector2(0, 9), pos + Vector2(0, 9), color, 0, 0, 1.5)
		"salvage":
			lines.circle(pos, 10, color, 6)
			lines.circle(pos, 2.5, color, 6)
		"finale", "boss":
			lines.polyline(PackedVector2Array([pos + Vector2(0, -14), pos + Vector2(7, 0), pos + Vector2(0, 14), pos + Vector2(-7, 0)]), true, color)
			lines.circle(pos, 6, color, 4)
		"beacon":
			for k in 3:
				var a := -PI * 0.5 + k * TAU / 3.0
				lines.circle(pos + Vector2(cos(a), sin(a)) * 9.0, 3, color, 6)
		"cargo":
			lines.rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), color)
			lines.seg(pos - Vector2(6, 6), pos + Vector2(6, 6), color)
		"rival":
			lines.polyline(PackedVector2Array([pos + Vector2(-10, 6), pos + Vector2(-2, 0), pos + Vector2(-10, -6)]), true, color)
			lines.polyline(PackedVector2Array([pos + Vector2(10, 6), pos + Vector2(2, 0), pos + Vector2(10, -6)]), true, color)
		"breach":
			arc(pos, 10.0, 0.45, TAU - 0.45, color, 1.0)
			lines.circle(pos, 2.5, color, 6)
		_:
			lines.circle(pos, 4, color, 12)

func draw_chart() -> void:
	var bounds := chart_bounds()
	if route.size() == Acts.LENGTH:
		draw_act_chart_backdrop(Acts.act_at(chart_depth))
	# A quiet status row leaves the route as the main visual element.
	label("SECTOR %02d / %02d" % [chart_depth - bounds.x + 1, bounds.y - bounds.x + 1], Vector2(80, 76), 18, Palette.DIM)
	for i in owned_cards.size():
		var card := card_definition(owned_cards[i])
		var pos := Vector2(380 + i * 265, 71)
		draw_card_icon(card.id, pos, card_color(card.id), 0.25)
		label("%s %s" % [card.name, ["I", "II", "III"][card_rank(owned_cards[i]) - 1]], pos + Vector2(25, 4), 11, Palette.DIM)
	draw_hull_icons(Vector2(1240, 70), maxi(0, lives + 1))
	draw_salvage(str(earned_salvage), Vector2(1400, 70), 15)
	for depth in range(bounds.x, bounds.y):
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
	for depth in range(bounds.x, bounds.y + 1):
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
	var ship_pos := Vector2(95, 370) if route_path.size() < bounds.x else chart_position(route_path.size(), route_path.back()) + Vector2(0, -55)
	for path in Hulls.paths(ship.id, ship_pos, 16.0, 0.0, 0.0):
		lines.polyline(path, false, Palette.WHITE)
	var node: Dictionary = route[chart_focus_depth - 1][selection]
	label("BOSS" if node.kind == "boss" else String(node.kind).to_upper(), chart_position(chart_focus_depth, selection) + Vector2(0, 65), 13, Palette.CYAN, 1)
	if route.size() == Acts.LENGTH:
		var finale: Dictionary = route[bounds.y - 1][0]
		label(Acts.BOSSES[finale.boss].name, chart_position(bounds.y, 0) + Vector2(0, 100), 14, Acts.ACTS[Acts.act_at(chart_depth) - 1].color, 1)
	# One compact inspector, without a surrounding card competing with the map.
	lines.seg(Vector2(80, 680), Vector2(1500, 680), Palette.DIM * 0.6)
	var shape_id := int(node.stage)
	var arena := SectorArena.build(shape_id, 0, "roguelite", Sectors.holes(shape_id, Vector2i(grid_width, grid_height)), Vector2i(grid_width, grid_height))
	var map := MapCatalog.read(shape_id)
	if map != null and map.override_terrain: arena = map.arena()
	var outline: PackedVector2Array = arena.outline
	for i in range(0, outline.size(), 2):
		lines.seg(Vector2(195, 750) + (outline[i] - Vector2(grid_width, grid_height) * 0.5) * 1.2, Vector2(195, 750) + (outline[i + 1] - Vector2(grid_width, grid_height) * 0.5) * 1.2, Palette.CYAN)
	label(Acts.BOSSES[node.boss].name if node.kind == "boss" else "%02d / %s" % [chart_focus_depth, Sectors.stage(shape_id).name], Vector2(350, 733), 21)
	var kind := String(node.kind)
	var turrets := Sectors.turret_count(kind, chart_focus_depth)
	var anomaly_count := Sectors.anomaly_count(chart_focus_depth, shape_id)
	if map != null and map.override_enemies:
		turrets = 0
		anomaly_count = 0
		for enemy in map.enemies:
			if enemy.kind in ["turret", "sniper"]: turrets += 1
			elif enemy.kind in MapCatalog.VOID_ENEMIES: anomaly_count += 1
	var threats := "CAPTURE %d%%" % Encounters.goal(map, kind, chart_focus_depth)
	if kind == "race": threats = "RACE TO %d%%" % Encounters.goal(map, kind, chart_focus_depth)
	elif kind == "beacon": threats = "BEACONS %d" % Encounters.runs(map, kind, chart_focus_depth)
	elif kind == "cargo": threats = "CARGO %d" % Encounters.runs(map, kind, chart_focus_depth)
	threats += " / %d %s" % [anomaly_count, ("VOID ENEMIES" if map != null and map.override_enemies else ("ANOMALY" if anomaly_count == 1 else "ANOMALIES"))]
	if turrets > 0: threats += " / %d TURRET%s" % [turrets, "" if turrets == 1 else "S"]
	if kind == "breach": threats += " / BREACH"
	if kind == "rival": threats += " / RIVAL"
	if chart_focus_depth >= Sectors.CORRUPTION_SECTOR: threats += " / CORRUPTION"
	if kind == "boss": threats = "CAPTURE 3 %s / ENCLOSE THE CORE" % Acts.BOSSES[node.boss].targets
	label(threats, Vector2(350, 772), 13, Palette.YELLOW)
	label("OBJECTIVE: " + encounter_copy(map, kind, chart_focus_depth), Vector2(350, 805), 12, Palette.CYAN)
	var reward := Sectors.reward_copy(kind)
	if not reward.is_empty():
		# Right-aligned beside the Jump button, clear of the longest threat strings.
		label(reward, Vector2(1205, 754), 15, Palette.GREEN, 2)
	var reachable := chart_reachable(chart_focus_depth, selection)
	lines.rect(CHART_JUMP, Palette.CYAN if reachable else Palette.DIM)
	var action := Controls.hint("JUMP  [ENTER]") if reachable else ("CLEARED" if chart_focus_depth < chart_depth and route_path[chart_focus_depth - 1] == selection else "LOCKED")
	label(action, CHART_JUMP.get_center() - Vector2(0, 8.5), 17, Palette.WHITE if reachable else Palette.DIM, 1)
	label(Controls.hint("ESC  BANK & EXIT"), Vector2(80, 842), 12, Palette.DIM)
	label(Controls.hint("ARROWS  SELECT"), Vector2(1500, 842), 12, Palette.DIM, 2)

func announce_lance() -> void:
	pass # Space already communicates the Lancer's action; keep failure/recharge messages.

func movement_module() -> String:
	for id in Cards.OPENING:
		if has_card(id): return id
	return ""

func reset_movement_module() -> void:
	hardlight_armed = false
	leap_input_frame = false
	charge_input_frame = false
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
	elif charge_input_frame:
		input.dir = Vector2i.ZERO
		input.draw = false
	elif dash_time > 0.0:
		input.dir = dash_direction
		input.draw = drawing and ship.id in ["surveyor", "bulwark"]
		input.slow = false
	return input

func leap_rate() -> float:
	return super.leap_rate() * card_power("leap")

func finish_leap(on_land: bool) -> void:
	super.finish_leap(on_land)
	if wall_building:
		cooldowns.leap = 16.0
		if hardlight_armed: start_hardlight()

func update_movement_module(dt: float) -> void:
	if sap_live and has_card("charge"):
		if Input.is_action_pressed("br_harden"):
			sap_charge = minf(sap_charge + sap_rate() * dt, float(sap_radius()))
		else:
			var radius := sap_charge
			sap_live = false
			sap_charge = 0.0
			if radius >= 1.5:
				cooldowns.charge = 12.0
				detonate(roundi(radius))
			return
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
		dashed(center(leap_origin), target, Palette.YELLOW, 6.0, 6.0)
		lines.circle(target, 6, Palette.YELLOW, 4)

func secondary_ability() -> String:
	for id in Cards.SECONDARY:
		if has_card(id): return id
	return ""
