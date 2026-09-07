class_name Game
extends Node
## The Qix run: a grid sector, a surveyor riding the coast, the Anomaly (Qix), Sparx on the
## coast, a fuse chasing an idle trail. Claims pay Flux into the persistent Save layer.
## Everything is drawn through ScopeLines each frame (no sprites, only beams).

const N := 104
const CELL := 8.0
var FX := 40.0                # field left edge: FX_DOCK for the title and dock, FX_RUN centred for a run
const FX_DOCK := 40.0
const FX_RUN := 384.0
const RUN_LX := 40.0          # run HUD columns either side of the centred field
const RUN_RX := 1256.0
const RUN_COL_W := 304.0
const FY := 34.0
const FREE := 0
const CLAIMED := 1
const TRAIL := 2
const TARGET := 0.75
const FLUX_PER_CELL := 0.1
const PANEL_X := 930.0
const PANEL_W := 620.0
const QIX_HIST := 12
const OFFS8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
const QIX_COLORS := [Palette.MAGENTA, Palette.PURPLE, Palette.BLUE, Palette.CYAN,
	Palette.GREEN, Palette.YELLOW, Palette.ORANGE, Palette.RED]

enum State { DOCK, PLAYING, DYING, LEVEL_CLEAR, RUN_OVER, INTRO, REPORT, OUTRO, TITLE, TRANSIT, BATTLE_ROYALE }

const TRANSIT_LEN := 3.2        # from the dock
const TRANSIT_SHORT := 2.2      # between sectors

## Title menu. TUBE (the FX lab) is a development tool: it only exists when running from the
## editor and the lab files are excluded from exports.
var TITLE_ITEMS: Array[String] = ["JUMP", "BATTLE ROYALE", "LOG", "RESPEC", "RESET", "QUIT"]
var TITLE_DESCS: Array[String] = ["TO THE DOCK", "8 CUTTERS. THREE ROUNDS. ONE WINNER.", "JUMP LOG", "REFUND EVERY UPGRADE. ENTER TWICE.", "WIPE THE SAVE. ENTER TWICE.", "POWER DOWN"]
## Destructive title items arm on the first Enter and fire on the second; anything else disarms.
const ARMED_DESCS := {
	"RESPEC": "SURE? ENTER AGAIN REFUNDS ALL UPGRADES. ARROWS CANCEL.",
	"RESET": "SURE? ENTER AGAIN WIPES EVERYTHING. ARROWS CANCEL.",
}
var armed_item := ""

const INTRO_LEN := 2.6
const INTRO_QIX_T := 1.4
const INTRO_SURV_T := 1.8
const OUTRO_COLLAPSE_T := 0.6
const OUTRO_CARD_T := 1.5


class QixBody:
	var c: Vector2
	var v: Vector2
	var theta := 0.0
	var omega := 1.5
	var len := 80.0
	var hist: Array = []
	var hist_t := 0.0
	var steer_t := 0.0
	var col_off := 0


class SparxBody:
	var c: Vector2i
	var prev: Vector2i
	var acc := 0.0
	var vis: Vector2
	var spin := 0.0


var lines: ScopeLines
var sparks: Sparks
var fill: Sprite2D
var fill_img: Image
var fill_tex: ImageTexture

var cells := PackedByteArray()
var border := PackedByteArray()
var border_cells: Array[Vector2i] = []
var coast := PackedVector2Array()
var reach := PackedByteArray()
var stack := PackedInt32Array()
var base_free := 0
var field_arena: Dictionary = {}
var field_shape: Array = []    # Rect2i cutouts (cells) pre-claimed for this sector
var free_count := 0

# surveyor
var p := Vector2i(N / 2, 0)
var vis := Vector2.ZERO
var move_acc := 0.0
var drawing := false
var anchor := Vector2i.ZERO
var trail: Array[Vector2i] = []
var trail_slow := true
var slow_held := false
var draw_armed := true        # a new trail needs a fresh Space press after a claim, detach, or death
var idle_t := 0.0
var fuse_on := false
var fuse_pos := 0.0
var lives := 3
var invuln := 0.0
var respawn_cell := Vector2i.ZERO
var last_dir := Vector2i.RIGHT

# run
var battle_fill: Sprite2D
var battle: BattleRoyale
var br_net_wired := false
var br_snapshot_t := 0.0
var br_board_sent := 0        # owners_version the last snapshot carried the board for
var br_input_t := 0.0
var br_last_dir := Vector2i.ZERO
var br_slots: Dictionary = {}   # host: peer id -> racer slot, fixed for the whole match
const BR_SNAPSHOT_HZ := 20.0
var result_selection := 0
var state := State.DOCK
var level := 1
var run_flux := 0.0
var state_t := 0.0
var shake := 0.0
var shake_off := Vector2.ZERO
var time := 0.0
var frame := 0
var msg := ""
var msg_currency := -1
var msg_amount := ""
var msg_t := 0.0
var msg_dur := 1.0
var dock_sel := 0
var dock_upgrade_scroll := 0
var dock_tab := 0
var dock_loadout_sel := 0
var dock_saved_upgrade := 3
var qixes: Array = []
var sparxes: Array = []
var sparx_spawn_t := 0.0
var sparx_to_spawn := 0
var beacon_note_t := 0.0

# dock briefing panes
var pane_t := 10.0            # seconds since the dock selection changed (drives the trace-in)
var pane_key := ""
var scan_layout: Dictionary = {}

# title screen
var title_t := 0.0
var title_sel := 0
var title_exit := -1          # menu item being left (drives the exit transition)
var title_exit_t := 0.0
var show_log := false
var liss_phase := 0.0

## A Flux node: sits in the void, worth node_value() when enclosed. Enemies cannot touch it.
class FluxNode:
	var cell: Vector2i
	var captured := false
	var telegraph := 0.0   # seconds until it surfaces (0 = active)
	var phase := 0.0
	var rare := false      # Isotope instead of Flux

## Hazards (Fortix lesson: nothing has hit points, everything is captured by enclosure).
class Turret:
	var cell: Vector2i
	var axis: Vector2i        # fires both ways along this axis
	var captured := false
	var fire_t := 2.0
	var phase := 0.0
	var interval := 3.0
	var rotate := false       # boss core turrets turn 90 degrees every few seconds
	var rot_t := 0.0
	var core := false

class Bolt:
	var pos: Vector2
	var vel: Vector2

class Spawner:
	var cell: Vector2i
	var captured := false
	var spawn_t := 3.0
	var alive := 0
	var interval := 5.0
	var max_alive := 3
	var mobile := false       # the Brood drifts through the void
	var pos: Vector2
	var vel: Vector2
	var mother := false

class Mite:
	var pos: Vector2
	var vel: Vector2
	var spin := 0.0
	var home: Spawner

var gal: Dictionary = Galaxies.LIST[0]

# ships: Bulwark hardens its trail, Islander drops buoys
const HARD := 3                 # cell state: hardened trail (a wall, becomes CLAIMED on death/claim)
const HARDEN_RATE_BASE := 5.0        # cells per second
const BUOY_CAP_BASE := 2
var ship: Dictionary = Ships.LIST[0]
var harden_len := 0.0
var sealing := false          # (unused: seals are now independent objects, see Seal)
const SEAL_SOFT := 4          # cell state: soft part of a detached Bulwark seal (a wall, not a life)
const ROCK := 5               # cell state: the sector's cutouts; nobody's land, nothing crosses it

## A detached Bulwark trail: keeps hardening on its own and claims when fully hard. If something
## cuts its soft part, the seal is lost (hard part stays as coast) but the pilot is unharmed.
class Seal:
	var cells: Array[Vector2i] = []
	var harden := 0.0
	var anchor_pt := Vector2.ZERO

var seals: Array = []
var buoy_charge := 1
const BUOY_RANGE_BASE := 20        # cells a thrown buoy can fly
var islands: Array = []        # Vector2i centers of 3x3 islands made by buoys
var buoy_flights: Array = []   # [from: Vector2, to: Vector2, t: float, cell: Vector2i]
# leaper: a line builds out ahead while Space is held; release leaps to its tip
const LEAP_RATE_BASE := 12.0       # cells per second
var leap_building := false
var leap_tip := Vector2i.ZERO
var leap_dir := Vector2i.DOWN
var leap_acc := 0.0
var leap_len := 0.0            # cells of aim so far
var braced := false            # bulwark: Space released mid-void, rooted while the trail hardens up to it
# after a leap into the void, a wall builds out both ways from the landing point (JezzBall)
var wall_building := false
var wall_ends: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO]
var wall_dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT]
var wall_cells: Array = [[], []]   # the trail cells each side of the wall has laid so far
var wall_done: Array[bool] = [false, false]
var sector_isotope := 0
var run_isotope := 0

# Lancer: a straight tether across the void, ridden at triple speed
const LANCE_CD_BASE := 6.0
const LANCE_SPEED_BASE := 3.0
var tether_active := false
var tether_i := -1            # index along the trail the ship has reached (-1 = still on the anchor)
var tether_dir := Vector2i.RIGHT
var lance_cd := 0.0
var lance_flash := 0.0        # brief ring flash when the lance comes off cooldown
var bends_left := 0           # mid-ride re-lances available on the current tether (BEND upgrade)
var lattice_ok := false       # the tether ahead can absorb one cut this lance (LATTICE upgrade)

# Sapper: plant a charge, hold still, claim a disc
const SAP_ARM_BASE := 3.0
const SAP_RADIUS_BASE := 8
var sap_live := false         # Space held: the wire is live and the disc is growing
var sap_charge := 0.0         # current disc radius in cells
var sap_guard_used := false   # INSULATED: one cut absorbed per charge
var sap_cell := Vector2i.ZERO
var turrets: Array = []
var bolts: Array = []
var spawners: Array = []
var mites: Array = []
var sector_hazards := 0
var run_hazards := 0

# galaxy structure: boss on sector LENGTH, endless past it once the galaxy is cleared
var boss_bond := false        # Twin Helix: the two Anomalies are joined by a lethal bond
var run_victory := false      # the run ended by clearing the galaxy
var endless := false          # this run is in the endless ladder (sector 9+)

var nodes: Array = []
var node_spawn_t := 0.0
var sector_nodes_captured := 0
var run_nodes := 0

# run / sector statistics for the report cards
var run_cells := 0
var run_best_claim := 0.0
var run_deaths := 0
var run_sectors := 0
var sector_capture := 0.0
var sector_bonus := 0.0
var sector_perfect := 0.0
var sector_deaths := 0

# intro / report / outro sequencing
var seq_t := 0.0
var intro_full := true
var transit_stars: Array = []   # {p: Vector2, d: depth} streaking past during the jump
var transit_skip := false      # autotests with scripted inputs jump straight to the intro
var transit_len := TRANSIT_LEN
var intro_fx_done := 0
var outro_fx_done := false
var surv_scale := 1.0

# autopilot (for automated screenshots / smoke tests)
var autopilot := false
var auto_script: Array = []   # [duration, Vector2i dir, draw, slow]
var auto_t := 0.0
var auto_i := 0


func setup(p_lines: ScopeLines, p_sparks: Sparks, p_fill: Sprite2D) -> void:
	lines = p_lines
	sparks = p_sparks
	fill = p_fill
	fill_img = Image.create(N, N, false, Image.FORMAT_RGBA8)
	fill_tex = ImageTexture.create_from_image(fill_img)
	fill.texture = fill_tex
	fill.centered = false
	fill.position = Vector2(FX, FY)
	fill.scale = Vector2(CELL, CELL)
	fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fill.material = m
	battle_fill = Sprite2D.new()
	battle_fill.centered = false
	battle_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	battle_fill.material = m
	battle_fill.visible = false
	fill.get_parent().add_child(battle_fill)
	fill.modulate = Color(Palette.CYAN.r, Palette.CYAN.g, Palette.CYAN.b, 0.16)
	cells.resize(N * N)
	border.resize(N * N)
	reach.resize(N * N)
	stack.resize(N * N)
	if Save.offline_gain > 1.0:
		beacon_note_t = 6.0
	go_title()


# ------------------------------------------------------------------ grid
func idx(x: int, y: int) -> int:
	return y * N + x


func center(c: Vector2i) -> Vector2:
	return Vector2(FX + (c.x + 0.5) * CELL, FY + (c.y + 0.5) * CELL)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < N and c.y < N


func to_cell(v: Vector2) -> Vector2i:
	return Vector2i(int(floor((v.x - FX) / CELL)), int(floor((v.y - FY) / CELL)))


func cell_blocked(c: Vector2i) -> bool:
	# for the Anomaly: claimed land and the outside are walls, the trail is not (it kills instead)
	if not in_bounds(c):
		return true
	var v := cells[idx(c.x, c.y)]
	return v == CLAIMED or v == HARD or v == ROCK


func claimed_frac() -> float:
	return 1.0 - float(free_count) / float(maxi(1, base_free))


func reset_field(rim: int) -> void:
	seals.clear()
	islands.clear()
	buoy_flights.clear()
	if not field_arena.is_empty():
		var mask: PackedByteArray = field_arena.mask
		for i in N * N:
			cells[i] = ROCK if mask[i] == 0 else (CLAIMED if mask[i] == 1 else FREE)
		base_free = field_arena.base_free
		free_count = field_arena.free_cells.size()
		grid_changed()
		return
	var r := 1 + rim
	for y in N:
		for x in N:
			var edge := x < r or y < r or x >= N - r or y >= N - r
			cells[idx(x, y)] = CLAIMED if edge else FREE
	# the sector's shape: cutouts are rock, not anyone's land; the rim path stays clear around them
	for rc in field_shape:
		var rr: Rect2i = rc
		for y in range(maxi(0, rr.position.y), mini(N, rr.end.y)):
			for x in range(maxi(0, rr.position.x), mini(N, rr.end.x)):
				if cells[idx(x, y)] == FREE:
					cells[idx(x, y)] = ROCK
	# the claim target is measured against the void this shape actually has (rim excluded)
	base_free = 0
	free_count = 0
	for y in N:
		for x in N:
			if cells[idx(x, y)] == FREE:
				free_count += 1
			if x >= 1 and y >= 1 and x < N - 1 and y < N - 1 and not in_shape(Vector2i(x, y), 0):
				base_free += 1
	grid_changed()


## Rock: an outline and a diagonal hatch, in the dim of the coast. Not land, so no fill.
func draw_rocks() -> void:
	for rc in field_shape:
		var rr: Rect2i = rc
		var a := Vector2(FX, FY) + Vector2(rr.position) * CELL
		var b := Vector2(FX, FY) + Vector2(rr.end) * CELL
		rock_shape(a, b, 1.0)


func rock_shape(a: Vector2, b: Vector2, alpha: float) -> void:
	var oc := Palette.DIM
	oc.a = 0.9 * alpha
	lines.rect(Rect2(a, b - a), oc, 0.4, 0.15, 0.9)
	var hc := Palette.DIM
	hc.a = 0.35 * alpha
	var w := b.x - a.x
	var h := b.y - a.y
	var step := 14.0
	var d := step
	while d < w + h:
		# a diagonal from the top/right edge to the left/bottom edge, clipped to the box
		var p0 := Vector2(a.x + minf(d, w), a.y + maxf(0.0, d - w))
		var p1 := Vector2(a.x + maxf(0.0, d - h), a.y + minf(d, h))
		lines.seg(p0, p1, hc, 0.3, 0.1, 0.6)
		d += step


## Slide the field: it sits at the left for the title and dock, and in the middle of the tube
## for a run, with the HUD split to either side.
func set_field_x(x: float) -> void:
	FX = x
	fill.position = Vector2(FX, FY)
	rebuild_coast()


func in_shape(c: Vector2i, grow: int) -> bool:
	for rc in field_shape:
		var rr: Rect2i = rc
		if c.x >= rr.position.x - grow and c.y >= rr.position.y - grow and c.x < rr.end.x + grow and c.y < rr.end.y + grow:
			return true
	return false


func grid_changed() -> void:
	recompute_border()
	rebuild_coast()
	update_fill()


func recompute_border() -> void:
	border_cells.clear()
	for y in N:
		for x in N:
			var i := idx(x, y)
			var b := 0
			if cells[i] == CLAIMED:
				for o in OFFS8:
					var nx: int = x + o.x
					var ny: int = y + o.y
					if nx >= 0 and ny >= 0 and nx < N and ny < N and cells[idx(nx, ny)] != CLAIMED and cells[idx(nx, ny)] != ROCK:
						b = 1
						break
			border[i] = b
			if b == 1:
				border_cells.append(Vector2i(x, y))


func _open(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= N or y >= N:
		return false
	var v := cells[idx(x, y)]
	return v != CLAIMED and v != HARD and v != ROCK


func rebuild_coast() -> void:
	# coast = every grid edge between claimed and unclaimed cells, merged into runs
	coast = PackedVector2Array()
	for y in range(N + 1):
		var run_start := -1
		for x in range(N + 1):
			var b := false
			if x < N:
				b = _open(x, y - 1) != _open(x, y)
			if b and run_start < 0:
				run_start = x
			elif not b and run_start >= 0:
				coast.append(Vector2(FX + run_start * CELL, FY + y * CELL))
				coast.append(Vector2(FX + x * CELL, FY + y * CELL))
				run_start = -1
	for x in range(N + 1):
		var run_start := -1
		for y in range(N + 1):
			var b := false
			if y < N:
				b = _open(x - 1, y) != _open(x, y)
			if b and run_start < 0:
				run_start = y
			elif not b and run_start >= 0:
				coast.append(Vector2(FX + x * CELL, FY + run_start * CELL))
				coast.append(Vector2(FX + x * CELL, FY + y * CELL))
				run_start = -1


func update_fill() -> void:
	var dither := int(cur_gal().dither)
	for y in N:
		for x in N:
			if cells[idx(x, y)] == CLAIMED:
				var on := false
				match dither:
					0: on = ((x + y) & 1) == 0          # checker
					1: on = (y & 1) == 0                # scanline stripes
					_: on = (x & 1) == 0 and (y & 1) == 0   # dots
				var v := 1.0 if on else 0.5
				fill_img.set_pixel(x, y, Color(v, v, v, 1.0))
			else:
				fill_img.set_pixel(x, y, Color(0, 0, 0, 0))
	fill_tex.update(fill_img)
	fill.modulate = fill_color()


# ------------------------------------------------------------------ run flow
func go_dock() -> void:
	state = State.DOCK
	dock_tab = 0
	dock_sel = 0
	dock_loadout_sel = 0
	lines.zoom = Vector2.ONE
	surv_scale = 1.0
	set_field_x(FX_DOCK)
	field_shape = []
	field_arena = {}
	reset_field(0)
	trail.clear()
	drawing = false
	sparxes.clear()
	qixes.clear()   # the briefing panes own the field while docked
	Save.save_data()


func start_run(retry_sector := 0) -> void:
	gal = Galaxies.get_galaxy(Save.data.galaxy)
	ship = Ships.get_ship(Save.data.ship) if Ships.owned(Save.data.ship) else Ships.LIST[0]
	lines.zoom = Vector2.ONE
	run_isotope = 0
	level = retry_sector if retry_sector > 0 else clampi(int(Save.data.start_sector), 1, max_start(gal.id))
	endless = level > Galaxies.LENGTH
	run_victory = false
	run_flux = 0.0
	run_nodes = 0
	run_hazards = 0
	lives = 2 + Save.extra_lives()
	run_cells = 0
	run_best_claim = 0.0
	run_deaths = 0
	run_sectors = 0
	set_field_x(FX_RUN)
	begin_transit(true)


func start_level() -> void:
	var lay := sector_layout(gal, level, Save.rim())
	field_shape = lay.shape
	field_arena = lay.arena
	reset_field(Save.rim())
	p = lay.start
	vis = center(p)
	drawing = false
	trail.clear()
	fuse_on = false
	invuln = 2.0
	move_acc = 0.0
	qixes.clear()
	spawn_qix()
	if level >= 5:
		spawn_qix()
	sparxes.clear()
	sparx_to_spawn = 1 + level / 2
	sparx_spawn_t = 3.0
	state_t = 0.0
	# the sector's base Flux and hazards come from the seeded layout (the dock scan shows the same)
	nodes.clear()
	sector_nodes_captured = 0
	for nd in lay.nodes:
		var fn := FluxNode.new()
		fn.cell = nd.cell
		fn.rare = nd.rare
		fn.phase = randf() * TAU
		nodes.append(fn)
	node_spawn_t = Save.prospect_interval()
	spawn_hazards(lay)
	boss_bond = false
	if level == Galaxies.LENGTH:
		spawn_boss()
	harden_len = 0.0
	buoy_charge = mini(buoy_cap(), 1 + up("prov"))
	sector_isotope = 0
	tether_active = false
	lance_cd = 0.0
	sap_live = false
	sap_charge = 0.0
	leap_building = false
	wall_building = false
	sector_capture = 0.0
	sector_bonus = 0.0
	sector_perfect = 0.0
	sector_deaths = 0


func end_run() -> void:
	Save.data.runs = int(Save.data.runs) + 1
	Save.data.best_level = maxi(int(Save.data.best_level), level)
	result_selection = 0
	state = State.OUTRO
	seq_t = 0.0
	outro_fx_done = false
	msg_t = 0.0
	drawing = false
	trail.clear()
	Save.save_data()


func set_msg(s: String, dur: float) -> void:
	msg_currency = -1
	msg = s
	msg_t = dur
	msg_dur = dur


# ------------------------------------------------------------------ update
func update(dt: float) -> void:
	time += dt
	frame += 1
	shake = maxf(0.0, shake - dt * 1.6)
	shake_off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * shake * 10.0
	msg_t -= dt
	invuln -= dt
	beacon_note_t -= dt
	pane_t += dt
	if state == State.DOCK:
		var key := "%s|%d|%s|%d" % [Save.data.galaxy, int(Save.data.start_sector), Save.data.ship, Save.rim()]
		if key != pane_key:
			pane_key = key
			pane_t = 0.0
			var g := Galaxies.get_galaxy(Save.data.galaxy)
			scan_layout = sector_layout(g, clampi(int(Save.data.start_sector), 1, max_start(g.id)), Save.rim())
	sparks.update(dt)
	match state:
		State.BATTLE_ROYALE:
			update_battle_royale(dt)
		State.DOCK:
			update_dock()
			for q in qixes:
				update_qix(q, dt, 60.0)
		State.PLAYING:
			update_play(dt)
		State.DYING:
			state_t += dt
			for q in qixes:
				update_qix(q, dt, qix_speed())
			if state_t > 1.3:
				if lives < 0:
					end_run()
				else:
					p = respawn_cell
					vis = center(p)
					invuln = 2.5 + (0.5 * up("shield") if ship.id == "surveyor" else 0.0)
					state = State.PLAYING
		State.LEVEL_CLEAR:
			state_t += dt
			if randf() < dt * 6.0:
				var pos := Vector2(FX + randf() * N * CELL, FY + randf() * N * CELL)
				sparks.burst(pos, 60, 260.0, 1.5, 0.9, QIX_COLORS[randi() % 8], 0.05)
				sparks.ripple(pos, 4.0, 240.0, 0.5, Palette.WHITE)
			if state_t > 2.0:
				begin_report()
		State.INTRO:
			update_intro(dt)
		State.TRANSIT:
			update_transit(dt)
		State.REPORT:
			update_report(dt)
		State.OUTRO:
			update_outro(dt)
		State.RUN_OVER:
			go_dock()
		State.TITLE:
			update_title(dt)


func arena_enemy_mult() -> float:
	return SectorArena.enemy_mult(gal.id, level)


func qix_speed() -> float:
	return 70.0 * pow(1.10, level - 1) * float(gal.qix_mult) * arena_enemy_mult()


func sparx_speed() -> float:
	return (7.0 + level * 0.7) * arena_enemy_mult()


func read_input() -> Dictionary:
	if autopilot:
		return read_autopilot()
	var d := Vector2i.ZERO
	if Input.is_action_pressed("move_left"):
		d = Vector2i.LEFT
	elif Input.is_action_pressed("move_right"):
		d = Vector2i.RIGHT
	elif Input.is_action_pressed("move_up"):
		d = Vector2i.UP
	elif Input.is_action_pressed("move_down"):
		d = Vector2i.DOWN
	return {"dir": d, "draw": Input.is_action_pressed("draw"), "slow": Input.is_action_pressed("slow"),
		"abort": Input.is_action_just_pressed("abort"), "special": Input.is_action_just_pressed("special")}


func read_autopilot() -> Dictionary:
	if auto_i >= auto_script.size():
		return {"dir": Vector2i.ZERO, "draw": false, "slow": false, "abort": false, "special": false}
	var step: Array = auto_script[auto_i]
	var first_frame := auto_t == 0.0
	auto_t += get_process_delta_time()
	if auto_t >= step[0]:
		auto_t = 0.0
		auto_i += 1
	var special: bool = step.size() > 4 and bool(step[4]) and first_frame
	return {"dir": step[1], "draw": step[2], "slow": step[3], "abort": false, "special": special}


func update_play(dt: float) -> void:
	var inp := read_input()
	if inp.abort:
		end_run()
		return
	slow_held = inp.slow
	var aim_dir: Vector2i = inp.dir   # the Leaper turns its aim with the arrows while held
	# bulwark: hold Space to advance; let go in the void and you brace where you stand
	braced = ship.id == "bulwark" and drawing and not inp.draw
	if (ship.id == "sapper" and sap_live) or leap_building or wall_building or braced:
		inp.dir = Vector2i.ZERO   # a charge or a line is growing from where you stand; hold your ground
	if not inp.draw:
		draw_armed = true   # releasing Space arms the next trail
	var speed := 11.0 * Save.speed_mult()
	if not drawing and border[idx(p.x, p.y)] == 0:
		speed *= 0.6   # interior of claimed land: walkable, but the coast is the fast lane
	if drawing and inp.slow:
		speed *= 0.5
	if ship.id == "sapper" and sap_live:
		speed *= 0.45   # charging: the disc rides with you, slowly
	if drawing and ship.id == "surveyor":
		speed *= 1.0 + 0.1 * up("slip")
	var moved := false
	if tether_active:
		# Lancer ride: automatic along the tether at triple speed; a sideways input steps off
		var idir: Vector2i = inp.dir
		var side: bool = idir != Vector2i.ZERO and idir != tether_dir and idir != -tether_dir
		if side and inp.draw and draw_armed and bends_left > 0 and tether_i >= 0:
			# BEND: drop the tether ahead and lance on in the steered direction, free of charge
			draw_armed = false
			for i in range(tether_i + 1, trail.size()):
				var rc := trail[i]
				cells[idx(rc.x, rc.y)] = FREE
			trail.resize(tether_i + 1)
			bends_left -= 1
			last_dir = idir
			fire_lance(true)
			sparks.burst(vis, 20, 160.0, 1.5, 0.4, Palette.CYAN)
			set_msg("BEND", 0.4)
		else:
			# no stepping off: the Lancer never walks the void, it rides to land or bends
			move_acc += speed * lance_speed_mult() * dt
			while move_acc >= 1.0 and state == State.PLAYING and tether_active:
				move_acc -= 1.0
				ride_step()
				moved = true
	elif inp.dir == Vector2i.ZERO:
		move_acc = 0.0
		idle_t += dt
	else:
		last_dir = inp.dir
		move_acc += speed * dt
		while move_acc >= 1.0 and state == State.PLAYING:
			move_acc -= 1.0
			if try_step(inp.dir, inp.draw and not (ship.id in ["sapper", "leaper", "lancer"]), inp.slow):
				moved = true
			else:
				move_acc = 0.0
				idle_t += dt
				break
	if moved:
		idle_t = 0.0
	if state != State.PLAYING:
		return

	# --- ship verbs
	if ship.id == "bulwark" and drawing:
		# the trail hardens from the anchor forward; the cell under the ship stays soft until the
		# ship is back on the coast (sealing), when the whole trail may harden
		# braced: hardening sprints at triple rate and may reach the cell under the ship
		var hr := harden_rate() * (3.0 if braced else 1.0)
		harden_len = minf(harden_len + hr * dt, float(trail.size() - (0 if braced else 1)))
		if braced and randf() < 0.4:
			sparks.emit(vis, Vector2(randf_range(-40, 40), randf_range(-40, 40)), 0.3, Palette.CYAN, 2.0)
		for i in int(floor(harden_len)):
			var hc := trail[i]
			if cells[idx(hc.x, hc.y)] == TRAIL:
				cells[idx(hc.x, hc.y)] = HARD
				if randf() < 0.5:
					sparks.emit(center(hc), Vector2(randf_range(-30, 30), randf_range(-30, 30)), 0.3, Palette.CYAN, 2.0)
	if not islands.is_empty() and up("tide") > 0:
		update_tide(dt)
		if state != State.PLAYING:
			return
	if not seals.is_empty():
		update_seals(dt)
		if state != State.PLAYING:
			return
	if ship.id == "leaper":
		# Space builds a line out ahead across the void, JezzBall style: it grows while held and
		# can be cut the whole time. Release, or reach land, and the ship leaps to the tip.
		if wall_building:
			wall_grow(dt)
			if state != State.PLAYING:
				return
		elif inp.draw and not leap_building and not drawing:
			start_leap()
		elif leap_building:
			if inp.draw:
				leap_aim(dt, aim_dir)
				if leap_reached_coast():
					finish_leap(true)
			else:
				finish_leap(false)
			if state != State.PLAYING:
				return
	var was_cd := lance_cd
	lance_cd = maxf(0.0, lance_cd - dt)
	if was_cd > 0.0 and lance_cd <= 0.0:
		lance_flash = 0.5
		sparks.ripple(vis, 4.0, 220.0, 0.4, Palette.CYAN)
	lance_flash = maxf(0.0, lance_flash - dt)
	if ship.id == "lancer" and inp.draw and draw_armed and not drawing:
		# Space is the lance: fire a tether in the facing direction and ride it to land
		draw_armed = false
		if lance_cd <= 0.0:
			fire_lance()
		else:
			set_msg("LANCE RECHARGING", 0.6)
			lines.spike(1.0, 0.2)
	if ship.id == "sapper":
		# Space is the charge, not the pen. The Sapper never leaves claimed land: hold Space and a
		# disc grows out from where it stands. The disc is the exposed part: the Anomaly, a mite or
		# a bolt crossing it kills. Release to blow. The longer you hold, the more you risk.
		var here := idx(p.x, p.y)
		var can_charge := cells[here] == FREE or border[here] != 0   # the void or the coast, never the interior
		if inp.draw and not sap_live and not can_charge:
			if draw_armed:
				set_msg("CHARGE FROM THE COAST OR THE VOID", 0.9)
				lines.spike(1.0, 0.2)
			draw_armed = false
		elif inp.draw:
			if not sap_live:
				sap_live = true
				sap_guard_used = false
				sap_cell = p
				sap_charge = 2.0 * up("primer")
				sparks.ripple(vis, 3.0, 160.0, 0.4, Palette.YELLOW)
			sap_charge = minf(sap_charge + sap_rate() * dt, float(sap_radius()))
			if randf() < 0.5:
				sparks.emit(vis, Vector2(randf_range(-50, 50), randf_range(-50, 50)), 0.3, Palette.YELLOW, 2.0)
		elif sap_live:
			sap_live = false
			if sap_charge >= 1.5:
				detonate(int(round(sap_charge)))
				return
			sap_charge = 0.0
			set_msg("FIZZLE", 0.5)
			sparks.burst(vis, 12, 90.0, 1.5, 0.3, Palette.YELLOW)

	# fuse: standing still while drawing lights it; it then chases you along the trail.
	# The Sapper has no fuse: its wire is dead until it charges.
	if drawing and not sealing and not (ship.id in ["sapper", "leaper"]):
		if idle_t > Save.fuse_delay():
			fuse_on = true
		if fuse_on:
			fuse_pos += speed * 0.8 * dt
			if fuse_pos >= trail.size():
				die("FUSE BURNED THROUGH")
				return
			if randf() < 0.6:
				sparks.emit(fuse_point(), Vector2(randf_range(-60, 60), randf_range(-60, 60)),
					0.3, Palette.FULLBRIGHT, 2.0)
	vis = vis.lerp(center(p), 1.0 - exp(-dt * 22.0))

	# exhaust
	if moved and randf() < 0.7:
		var back := -Vector2(last_dir) * 40.0
		sparks.emit(vis, back + Vector2(randf_range(-20, 20), randf_range(-20, 20)), 0.35,
			Palette.ORANGE if drawing else Palette.CYAN, 2.5)

	# Flux nodes: telegraphs count down; the Prospector surfaces extra ones over time
	for nd in nodes:
		var fn: FluxNode = nd
		fn.phase += dt
		if fn.telegraph > 0.0:
			fn.telegraph = maxf(0.0, fn.telegraph - dt)
			if fn.telegraph == 0.0:
				sparks.ripple(center(fn.cell), 3.0, 200.0, 0.5, Palette.YELLOW)
				sparks.burst(center(fn.cell), 24, 120.0, 1.5, 0.5, Palette.YELLOW)
	var interval := Save.prospect_interval()
	if interval > 0.0 and uncaptured_nodes() < 6:
		node_spawn_t -= dt
		if node_spawn_t <= 0.0:
			node_spawn_t = interval
			spawn_node(2.0)

	update_hazards(dt)
	if state != State.PLAYING:
		return

	# the Anomaly
	for q in qixes:
		update_qix(q, dt, qix_speed())
		var qc := qix_trail_cell(q)
		if qc.x >= 0 and tether_hit(qc):
			die("ANOMALY CONTACT")
			return
		if sap_live and qix_in_disc(q) and wire_hit():
			die("CHARGE BREACHED")
			return
		if exposed() and not drawing and qix_near(q, vis, CELL * 0.9):
			die("ANOMALY CONTACT")   # a Sapper out in the void with no line
			return
		var hit_seal := qix_hits_seal(q)
		if hit_seal != null:
			lose_seal(hit_seal)
	# Twin Helix: the bond between the two Anomalies cuts trails and seals like they do
	if boss_bond and qixes.size() >= 2:
		var a: Vector2 = (qixes[0] as QixBody).c
		var b: Vector2 = (qixes[1] as QixBody).c
		var n := int(maxf(2.0, a.distance_to(b) / 6.0))
		for k in range(n + 1):
			var c := to_cell(a.lerp(b, float(k) / n))
			if not in_bounds(c):
				continue
			var v := cells[idx(c.x, c.y)]
			if v == TRAIL and tether_hit(c) and wire_hit():
				die("BOND CONTACT")
				return
			if v == SEAL_SOFT:
				lose_seal(seal_at(c))

	# Sparx
	sparx_spawn_t -= dt
	if sparx_to_spawn > 0 and sparx_spawn_t <= 0.0:
		spawn_sparx()
		sparx_to_spawn -= 1
		sparx_spawn_t = 4.0
	for s in sparxes:
		update_sparx(s, dt)
		if s.c == p or s.vis.distance_to(vis) < CELL * 0.8:
			die("SPARX CONTACT")
			return


func try_step(dir: Vector2i, draw: bool, slow: bool) -> bool:
	var t := p + dir
	if not in_bounds(t):
		return false
	var tc := cells[idx(t.x, t.y)]
	if drawing:
		if tc == FREE:
			cells[idx(t.x, t.y)] = TRAIL
			trail.append(t)
			p = t
			if not slow:
				trail_slow = false
			return true
		elif tc == TRAIL or tc == SEAL_SOFT or tc == ROCK or (tc == HARD and trail.has(t)):
			return false   # own trail (soft or hardened), other seals' soft parts and rock are walls
		else:
			p = t
			if ship.id == "bulwark":
				# reached the coast: the trail detaches as a seal and hardens on its own
				detach_seal()
				return true
			complete_claim()
			return true
	else:
		if tc == CLAIMED:
			# claimed land is walkable everywhere; the coast is just the fast lane (see update_play)
			p = t
			return true
		elif tc == FREE and ship.id == "sapper":
			p = t   # the Sapper roams the void with no line; it is exposed out there
			return true
		elif tc == FREE and draw and draw_armed:
			drawing = true
			anchor = p
			trail.clear()
			trail_slow = slow
			fuse_on = false
			fuse_pos = 0.0
			idle_t = 0.0
			harden_len = 2.0 * up("front") if ship.id == "bulwark" else 0.0
			cells[idx(t.x, t.y)] = TRAIL
			trail.append(t)
			p = t
			return true
		return false


func qix_cell_index(q: QixBody) -> int:
	var c := to_cell(q.c)
	if in_bounds(c) and cells[idx(c.x, c.y)] == FREE:
		return idx(c.x, c.y)
	for r in range(1, 10):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if in_bounds(n) and cells[idx(n.x, n.y)] == FREE:
					return idx(n.x, n.y)
	return -1


func complete_claim() -> void:
	drawing = false
	fuse_on = false
	tether_active = false
	sap_live = false
	sap_charge = 0.0
	leap_building = false
	wall_building = false
	sealing = false
	draw_armed = false
	# flood the void from the Anomaly; whatever it cannot reach is ours
	reach.fill(0)
	var sp := 0
	for q in qixes:
		var ci := qix_cell_index(q)
		if ci >= 0 and reach[ci] == 0:
			reach[ci] = 1
			stack[sp] = ci
			sp += 1
	while sp > 0:
		sp -= 1
		var i := stack[sp]
		var x := i % N
		var y := i / N
		if x > 0 and cells[i - 1] == FREE and reach[i - 1] == 0:
			reach[i - 1] = 1
			stack[sp] = i - 1
			sp += 1
		if x < N - 1 and cells[i + 1] == FREE and reach[i + 1] == 0:
			reach[i + 1] = 1
			stack[sp] = i + 1
			sp += 1
		if y > 0 and cells[i - N] == FREE and reach[i - N] == 0:
			reach[i - N] = 1
			stack[sp] = i - N
			sp += 1
		if y < N - 1 and cells[i + N] == FREE and reach[i + N] == 0:
			reach[i + N] = 1
			stack[sp] = i + N
			sp += 1
	var gained := 0
	for i in N * N:
		if cells[i] == FREE and reach[i] == 0:
			cells[i] = CLAIMED
			gained += 1
	for t in trail:
		cells[idx(t.x, t.y)] = CLAIMED
	gained += trail.size()
	free_count -= gained

	# nodes now inside claimed land are captured: 1 Flux each (+Refinery), +1 if drawn slow
	var award := 0.0
	var got := 0
	var iso_got := 0
	for nd in nodes:
		var fn: FluxNode = nd
		if fn.captured or fn.telegraph > 0.0:
			continue
		if cells[idx(fn.cell.x, fn.cell.y)] == CLAIMED:
			fn.captured = true
			got += 1
			if fn.rare:
				Save.data.isotope = int(Save.data.isotope) + 1
				sector_isotope += 1
				run_isotope += 1
				iso_got += 1
			else:
				award += node_value() + ((1 + (up("slowb") if ship.id == "surveyor" else 0)) if trail_slow else 0)
			var np := center(fn.cell)
			sparks.zap_polyline(PackedVector2Array([np, vis]), Palette.YELLOW, 1800.0, 6.0)
			sparks.burst(np, 40, 200.0, 1.5, 0.7, Palette.YELLOW)
			sparks.ripple(np, 4.0, 300.0, 0.5, Palette.GREEN)
	# hazards inside claimed land are captured too: silenced, and worth 1 Flux each
	var caught := 0
	for tr in turrets:
		var t: Turret = tr
		if not t.captured and cells[idx(t.cell.x, t.cell.y)] == CLAIMED:
			t.captured = true
			caught += 1
			sparks.burst(center(t.cell), 50, 220.0, 1.5, 0.7, Palette.ORANGE)
			sparks.ripple(center(t.cell), 5.0, 320.0, 0.5, Palette.GREEN)
	for spw in spawners:
		var s: Spawner = spw
		if not s.captured and cells[idx(s.cell.x, s.cell.y)] == CLAIMED:
			s.captured = true
			caught += 1
			sparks.burst(center(s.cell), 60, 240.0, 1.5, 0.8, Palette.PURPLE)
			sparks.ripple(center(s.cell), 5.0, 320.0, 0.5, Palette.GREEN)
	# mites caught in the claim, or orphaned by a captured spawner, pop
	var j := mites.size() - 1
	while j >= 0:
		var m: Mite = mites[j]
		var mc := to_cell(m.pos)
		if (in_bounds(mc) and cells[idx(mc.x, mc.y)] == CLAIMED) or m.home.captured:
			sparks.burst(m.pos, 16, 120.0, 1.5, 0.4, Palette.RED)
			m.home.alive -= 1
			mites.remove_at(j)
		j -= 1
	if caught > 0:
		award += caught
	# boss objectives: the Brood captured, or every Bastion core turret enclosed
	if level == Galaxies.LENGTH and state == State.PLAYING:
		var boss_done := false
		for spw2 in spawners:
			if (spw2 as Spawner).mother and (spw2 as Spawner).captured:
				boss_done = true
		var cores := 0
		var cores_done := 0
		for tr2 in turrets:
			if (tr2 as Turret).core:
				cores += 1
				if (tr2 as Turret).captured:
					cores_done += 1
		if cores > 0 and cores_done == cores:
			boss_done = true
		if boss_done:
			set_msg("%s CAPTURED" % gal.boss_name, 2.0)
			award += 5.0
			Save.add_flux(award)
			run_flux += award
			sector_capture += award
			trail.clear()
			grid_changed()
			level_clear()
			return
		sector_hazards += caught
		run_hazards += caught
	sector_nodes_captured += got
	run_nodes += got
	Save.add_flux(award)
	run_flux += award
	sector_capture += award
	run_cells += gained
	run_best_claim = maxf(run_best_claim, float(gained) / float(base_free))

	sparks.zap_polyline(trail_points(), coast_color())
	sparks.ripple(vis, 6.0, 320.0, 0.6, Palette.WHITE)
	sparks.burst(vis, 30, 200.0, 2.0, 0.5, Palette.CYAN)
	lines.spike(2.5, 0.35)
	shake = maxf(shake, 0.35)
	if got + caught > 0:
		var tag := "  SLOW BONUS" if (trail_slow and got > 0) else ""
		if iso_got > 0:
			tag += "  +%d ISOTOPE" % iso_got
		if caught > 0:
			tag += "  %d HAZARD%s SILENCED" % [caught, "S" if caught > 1 else ""]
		set_msg("+%d FLUX%s" % [int(round(award)), tag], 1.4)
	elif gained > 40:
		set_msg("NO NODES", 0.8)
	trail.clear()
	grid_changed()
	if claimed_frac() >= TARGET:
		level_clear()


func level_clear() -> void:
	state = State.LEVEL_CLEAR
	state_t = 0.0
	var bonus := 1.0   # securing a sector is worth one node
	Save.add_flux(bonus)
	run_flux += bonus
	sector_bonus = bonus
	run_sectors += 1
	Save.data.galaxy_best[gal.id] = maxi(Galaxies.best(gal.id), mini(level, Galaxies.LENGTH))
	if level == Galaxies.LENGTH and not Galaxies.cleared(gal.id):
		Save.data.galaxy_clear[gal.id] = true
		Save.data.starcharts = int(Save.data.starcharts) + 1
	if level > Galaxies.LENGTH:
		Save.data.endless_best[gal.id] = maxi(Galaxies.endless_best(gal.id), level)
	Save.data.best_level = maxi(int(Save.data.best_level), level)
	set_msg("SECTOR %02d SECURED  +%d" % [level, int(bonus)], 2.6)
	shake = maxf(shake, 0.6)
	lines.spike(5.0, 0.5)
	drawing = false
	trail.clear()
	Save.save_data()


func die(reason: String) -> void:
	if invuln > 0.0:
		return
	state = State.DYING
	state_t = 0.0
	respawn_cell = anchor if drawing else p
	explode(vis)
	shake = 1.0
	lines.spike(5.0, 0.7)
	# Bulwark: the hardened part of the trail survives as coast and you respawn at its front
	var hardened := 0
	for t in trail:
		if cells[idx(t.x, t.y)] == HARD:
			cells[idx(t.x, t.y)] = CLAIMED
			hardened += 1
			respawn_cell = t
		else:
			cells[idx(t.x, t.y)] = FREE
	if hardened > 0:
		free_count -= hardened
		run_cells += hardened
		grid_changed()
	harden_len = 0.0
	tether_active = false
	sap_live = false
	sap_charge = 0.0
	leap_building = false
	wall_building = false
	sealing = false
	draw_armed = false
	trail.clear()
	drawing = false
	fuse_on = false
	lives -= 1
	sector_deaths += 1
	run_deaths += 1
	set_msg(reason, 1.4)


## explode(): concentric rings + fast fireball + slow smoke (assets.js:9037)
func explode(pos: Vector2) -> void:
	sparks.ripple(pos, 4.0, 420.0, 0.7, Palette.FULLBRIGHT)
	sparks.ripple(pos, 2.0, 300.0, 0.9, Palette.WHITE)
	sparks.burst(pos, 120, 420.0, 0.8, 0.7, Palette.FULLBRIGHT, 0.03, Vector2.ZERO, 1.2)
	sparks.burst(pos, 90, 220.0, 2.0, 1.2, Palette.ORANGE, 0.08, Vector2.ZERO, 1.0)
	sparks.burst(pos, 60, 90.0, 8.0, 2.4, Palette.RED, 0.2, Vector2.ZERO, 0.4)


# ------------------------------------------------------------------ anomaly
func spawn_qix() -> void:
	var q := QixBody.new()
	q.len = 80.0 * SectorArena.anomaly_size_mult(gal.id, level)
	q.c = Vector2(FX + N * CELL * randf_range(0.35, 0.65), FY + N * CELL * randf_range(0.35, 0.65))
	for tries in 40:
		# keep it out of the sector's cutouts
		var qc := to_cell(q.c)
		if in_bounds(qc) and cells[idx(qc.x, qc.y)] == FREE:
			break
		q.c = Vector2(FX + N * CELL * randf_range(0.2, 0.8), FY + N * CELL * randf_range(0.2, 0.8))
	q.v = Vector2.RIGHT.rotated(randf() * TAU) * 70.0
	q.theta = randf() * TAU
	q.omega = randf_range(1.5, 3.0) * (1.0 if randf() < 0.5 else -1.0)
	q.col_off = randi() % 8
	if not field_arena.is_empty():
		# Validate the whole beam, especially with a thick purchased rim in a small arena.
		q.c = center(Vector2i(N / 2, N / 2))
		for attempt in 64:
			var candidate: Vector2i = field_arena.free_cells[randi() % field_arena.free_cells.size()]
			var point := center(candidate)
			if not qix_blocked(point, q.theta, q.len):
				q.c = point
				break
	qixes.append(q)


func qix_ends(c: Vector2, theta: float, len: float) -> PackedVector2Array:
	var d := Vector2(cos(theta), sin(theta)) * len * 0.5
	return PackedVector2Array([c - d, c + d])


func qix_blocked(c: Vector2, theta: float, len: float) -> bool:
	var e := qix_ends(c, theta, len)
	var n := int(maxf(2.0, len / 6.0))
	for k in range(n + 1):
		if cell_blocked(to_cell(e[0].lerp(e[1], float(k) / n))):
			return true
	return false


func qix_hits_trail(q: QixBody) -> bool:
	var e := qix_ends(q.c, q.theta, q.len)
	var n := int(maxf(2.0, q.len / 5.0))
	for k in range(n + 1):
		var c := to_cell(e[0].lerp(e[1], float(k) / n))
		if in_bounds(c) and cells[idx(c.x, c.y)] == TRAIL:
			return wire_hit()
	return false


func update_qix(q: QixBody, dt: float, speed: float) -> void:
	q.steer_t -= dt
	if q.steer_t <= 0.0:
		q.steer_t = randf_range(0.6, 2.0)
		q.omega = randf_range(1.0, 3.5) * (1.0 if randf() < 0.5 else -1.0)
		q.v = q.v.rotated(randf_range(-1.2, 1.2))
	q.v = q.v.rotated(randf_range(-1.5, 1.5) * dt).normalized() * speed
	q.len = (70.0 + 30.0 * sin(time * 1.3 + q.col_off)) * SectorArena.anomaly_size_mult(gal.id, level)
	var nc := q.c + q.v * dt
	var nt := q.theta + q.omega * arena_enemy_mult() * dt
	if not qix_blocked(nc, nt, q.len):
		q.c = nc
		q.theta = nt
	else:
		var ok := false
		for a in [Vector2(-q.v.x, q.v.y), Vector2(q.v.x, -q.v.y), -q.v]:
			nc = q.c + a * dt
			if not qix_blocked(nc, nt, q.len):
				q.v = a
				q.c = nc
				q.theta = nt
				ok = true
				break
		if not ok:
			q.omega = -q.omega
			nt = q.theta + q.omega * arena_enemy_mult() * dt
			if not qix_blocked(q.c, nt, q.len * 0.9):
				q.theta = nt
			else:
				q.v = q.v.rotated(PI * 0.5)
	q.hist_t += dt
	if q.hist_t >= 1.0 / 22.0:
		q.hist_t = 0.0
		q.hist.push_front(qix_ends(q.c, q.theta, q.len))
		if q.hist.size() > QIX_HIST:
			q.hist.pop_back()


# ------------------------------------------------------------------ sparx
func spawn_sparx() -> void:
	var s := SparxBody.new()
	var best := Vector2i(-1, -1)
	var best_d := -1
	if border_cells.is_empty():
		return
	for tries in 60:
		var c := border_cells[randi() % border_cells.size()]
		var d := maxi(absi(c.x - p.x), absi(c.y - p.y))
		if d > best_d:
			best_d = d
			best = c
		if d > 45:
			break
	if best.x < 0:
		return
	s.c = best
	s.prev = best
	s.vis = center(best)
	sparxes.append(s)
	sparks.burst(s.vis, 40, 180.0, 1.5, 0.5, Palette.RED)


func sparx_step(s: SparxBody) -> void:
	var cands: Array[Vector2i] = []
	for o in OFFS8:
		var n: Vector2i = s.c + o
		if in_bounds(n) and border[idx(n.x, n.y)] == 1 and n != s.prev:
			cands.append(n)
	var pick: Vector2i
	if cands.is_empty():
		if in_bounds(s.prev) and border[idx(s.prev.x, s.prev.y)] == 1 and s.prev != s.c:
			pick = s.prev
		else:
			# stranded (the coast moved under it): hop to the nearest coast cell
			for r in range(1, 6):
				for o in OFFS8:
					var n: Vector2i = s.c + o * r
					if in_bounds(n) and border[idx(n.x, n.y)] == 1:
						s.prev = s.c
						s.c = n
						return
			return
	else:
		var cont: Vector2i = s.c + (s.c - s.prev)
		if cands.has(cont) and randf() < 0.85:
			pick = cont
		else:
			pick = cands[randi() % cands.size()]
	s.prev = s.c
	s.c = pick


func update_sparx(s: SparxBody, dt: float) -> void:
	s.acc += sparx_speed() * dt
	while s.acc >= 1.0:
		s.acc -= 1.0
		sparx_step(s)
	s.vis = s.vis.lerp(center(s.c), 1.0 - exp(-dt * 18.0))
	s.spin += dt * 9.0
	if randf() < 0.25:
		sparks.emit(s.vis, Vector2(randf_range(-50, 50), randf_range(-50, 50)), 0.25, Palette.RED, 2.0)


# ------------------------------------------------------------------ dock
## Dock rows: 0 = galaxy, 1 = start sector, 2 = ship, 3.. = upgrades, last = launch.


func dock_ship_step(dir: int) -> void:
	var i := (Ships.index_of(Save.data.ship) + dir + Ships.LIST.size()) % Ships.LIST.size()
	Save.data.ship = Ships.LIST[i].id
	lines.spike(1.0, 0.2)


func dock_ship_confirm() -> void:
	var id: String = Save.data.ship
	if Ships.owned(id):
		set_msg("%s READY" % Ships.get_ship(id).name, 1.0)
		return
	if Ships.buy(id):
		set_msg("%s COMMISSIONED" % Ships.get_ship(id).name, 1.4)
		lines.spike(3.0, 0.4)
		sparks.burst(Vector2(PANEL_X + 330, 244), 60, 200.0, 1.5, 0.7, Palette.CYAN)
	else:
		set_currency_ask(Ships.get_ship(id).cost, true)
		lines.spike(1.0, 0.2)


func dock_galaxy_step(dir: int) -> void:
	var i := (Galaxies.index_of(Save.data.galaxy) + dir + Galaxies.LIST.size()) % Galaxies.LIST.size()
	Save.data.galaxy = Galaxies.LIST[i].id
	Save.data.start_sector = mini(int(Save.data.start_sector), max_start(Save.data.galaxy))
	lines.spike(1.0, 0.2)


func dock_sector_step(dir: int) -> void:
	Save.data.start_sector = clampi(int(Save.data.start_sector) + dir, 1, max_start(Save.data.galaxy))


# ------------------------------------------------------------------ draw
func trail_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(center(anchor))
	var prev_dir := Vector2i.ZERO
	var prev := anchor
	for i in trail.size():
		var c := trail[i]
		var d := c - prev
		if d != prev_dir and i > 0:
			pts.append(center(prev))
		prev_dir = d
		prev = c
	if drawing:
		pts.append(vis)
	else:
		pts.append(center(prev))
	return pts


func fuse_point() -> Vector2:
	if trail.is_empty():
		return vis
	var i := int(floor(fuse_pos))
	var f := fuse_pos - i
	var a := center(anchor) if i == 0 else center(trail[i - 1])
	var b := center(trail[mini(i, trail.size() - 1)])
	return a.lerp(b, f)


func fmt(v: float) -> String:
	if v < 10000.0:
		return "%d" % int(v)
	if v < 1000000.0:
		return "%.1fK" % (v / 1000.0)
	return "%.2fM" % (v / 1000000.0)


func draw() -> void:
	battle_fill.visible = false
	if state == State.BATTLE_ROYALE:
		fill.visible = false
		battle.draw(lines, battle_fill)
		return
	if state == State.DOCK:
		fill.visible = false
		draw_dock_field()
		draw_dock_panel()
		sparks.draw(lines)
		if msg_t > 0.0:
			if msg_currency >= 0:
				draw_currency_caption(msg, msg_amount, msg_currency == 1, Vector2(800, 712))
			else:
				VectorFont.draw(lines, msg, Vector2(800, 705), 14, Palette.YELLOW, 0.0, 0.0, 1)
		return
	fill.visible = state != State.OUTRO and state != State.TRANSIT and not (state == State.TITLE and title_t < 0.85)
	if state == State.TRANSIT:
		draw_transit()
		sparks.draw(lines)
		return
	if state == State.OUTRO and seq_t >= OUTRO_CARD_T:
		draw_panel_header()
		draw_outro_card()
		sparks.draw(lines)
		return

	if state == State.INTRO:
		draw_intro()
	else:
		var field_rect := Rect2(FX, FY, N * CELL, N * CELL)
		lines.rect(field_rect, Palette.DIM, 0.4, 0.1, 0.8)
		# coast
		var cc := coast_color()
		for i in range(0, coast.size(), 2):
			lines.seg(coast[i], coast[i + 1], cc, 0.7, 0.15, 1.0)
		if state == State.TITLE:
			draw_title_field()
		else:
			draw_play()
		for q in qixes:
			draw_qix(q)
		if boss_bond and qixes.size() >= 2:
			# the Twin Helix bond: a crackling line between the two Anomalies
			var a: Vector2 = (qixes[0] as QixBody).c
			var b: Vector2 = (qixes[1] as QixBody).c
			var pts := PackedVector2Array()
			var n := int(maxf(3.0, a.distance_to(b) / 14.0))
			var nrm := (b - a).normalized().orthogonal()
			for k in range(n + 1):
				var f := float(k) / n
				var jag := 0.0 if (k == 0 or k == n) else randf_range(-6.0, 6.0)
				pts.append(a.lerp(b, f) + nrm * jag)
			lines.polyline(pts, false, Palette.MAGENTA, 3.0, 0.6, 1.1)
	sparks.draw(lines)
	if state == State.REPORT:
		draw_report_card()

	draw_panel_header()
	if state == State.TITLE:
		draw_title_panel()
	else:
		draw_hud()

	if msg_t > 0.0:
		var a := clampf(msg_t / 0.4, 0.0, 1.0)
		var c := Palette.YELLOW
		c.a = a
		var flick := 0.0 if fmod(time, 0.09) < 0.02 else 1.0
		if flick > 0.0:
			VectorFont.draw(lines, msg, Vector2(FX + N * CELL * 0.5, FY + N * CELL * 0.47), 22, c, 1.5, 0.5, 1, 1.2)


func draw_play() -> void:
	draw_rocks()
	# trail
	if drawing:
		var pts := trail_points()
		var tc := Palette.MAGENTA if slow_held else Palette.ORANGE
		if ship.id == "bulwark" and harden_len >= 1.0:
			# hardened part in coast cyan, soft part in trail orange, a bright front between them
			var hn := int(floor(harden_len))
			var hard_pts := PackedVector2Array([center(anchor)])
			for i in hn:
				hard_pts.append(center(trail[i]))
			lines.polyline(hard_pts, false, Palette.CYAN, 0.7, 0.2, 1.4)
			var front := center(trail[hn - 1])
			lines.circle(front, 4.0 + 1.5 * sin(time * 12.0), Palette.FULLBRIGHT, 6, 1.5, 0.6, 1.0)
			var soft_pts := PackedVector2Array([front])
			for i in range(hn, trail.size()):
				soft_pts.append(center(trail[i]))
			soft_pts[soft_pts.size() - 1] = vis
			lines.polyline(soft_pts, false, tc, 2.2, 0.45, 1.3)
		elif tether_active:
			# ridden part as a normal trail, the tether ahead as a taut bright line with pulses
			var behind := PackedVector2Array([center(anchor)])
			for i in range(0, tether_i + 1):
				behind.append(center(trail[i]))
			behind.append(vis)
			lines.polyline(behind, false, tc, 2.2, 0.45, 1.3)
			var tail := center(trail[trail.size() - 1]) + Vector2(tether_dir) * CELL * 0.5
			lines.seg(vis, tail, Palette.CYAN, 0.4, 0.3, 0.9)
			var L := vis.distance_to(tail)
			var k := 0.0
			while k < L:
				var pp := vis + (tail - vis) / maxf(L, 0.01) * k
				lines.seg(pp, pp, Palette.FULLBRIGHT, 0.5, 0.5, 1.2)
				k += 40.0
			var head := fmod(time * 500.0, maxf(L, 1.0))
			var hp := vis + (tail - vis) / maxf(L, 0.01) * head
			lines.circle(hp, 3.0, Palette.FULLBRIGHT, 6, 1.0, 0.6, 0.9)
		elif wall_building:
			# the wall growing out of the buoy both ways along the leap axis, bright heads while moving
			var tip := center(leap_tip)
			for s in 2:
				if wall_done[s]:
					continue   # a hardened side is coast now and draws itself
				var e := center(wall_ends[s])
				lines.seg(tip, e, Palette.YELLOW, 2.2, 0.45, 1.3)
				lines.circle(e, 3.0 + 1.5 * sin(time * 20.0), Palette.FULLBRIGHT, 6, 1.5, 0.6, 1.1)
		else:
			lines.polyline(pts, false, tc, 2.2, 0.45, 1.3)
		lines.circle(center(anchor), 4.0, Palette.ORANGE, 8, 1.0, 0.3, 0.8)
		if fuse_on:
			var fp := fuse_point()
			var r := 6.0 + 2.0 * sin(time * 40.0)
			lines.seg(fp + Vector2(-r, 0), fp + Vector2(r, 0), Palette.FULLBRIGHT, 3.0, 0.6, 1.4)
			lines.seg(fp + Vector2(0, -r), fp + Vector2(0, r), Palette.FULLBRIGHT, 3.0, 0.6, 1.4)
	draw_nodes()
	draw_hazards()
	draw_seals()
	draw_islands()
	# sparx
	for s in sparxes:
		var r := 11.0
		var col := Palette.RED if (frame / 4) % 2 == 0 else Palette.ORANGE
		for k in 2:
			var a: float = s.spin + k * PI * 0.5
			var d := Vector2(cos(a), sin(a)) * r
			lines.seg(s.vis - d, s.vis + d, col, 2.5, 0.5, 1.3)
		lines.circle(s.vis, 3.5, Palette.FULLBRIGHT, 6, 2.0, 0.5, 0.9)
	# surveyor
	if (state == State.PLAYING or state == State.LEVEL_CLEAR or state == State.REPORT or state == State.INTRO) and surv_scale > 0.0:
		var blink := invuln > 0.0 and fmod(time, 0.2) < 0.1 and state == State.PLAYING
		var pc := Palette.MAGENTA if drawing else Palette.FULLBRIGHT
		if blink:
			pc.a = 0.3
		var r := 7.0 * surv_scale
		var pts := PackedVector2Array([vis + Vector2(0, -r), vis + Vector2(r, 0), vis + Vector2(0, r), vis + Vector2(-r, 0)])
		match String(ship.id):
			"bulwark":
				# a shield: flat top, pointed keel
				pts = PackedVector2Array([vis + Vector2(-r, -r * 0.7), vis + Vector2(r, -r * 0.7), vis + Vector2(r, r * 0.2), vis + Vector2(0, r), vis + Vector2(-r, r * 0.2)])
				lines.polyline(pts, true, pc, 1.2, 0.6, 1.5)
			"leaper":
				lines.polyline(pts, true, pc, 1.2, 0.6, 1.3)
				lines.circle(vis, r * 1.7, pc, 8, 1.0, 0.4, 0.7)
			"lancer":
				# a long arrowhead pointing where the lance would go
				var d := Vector2(tether_dir if tether_active else last_dir)
				var n := Vector2(-d.y, d.x)
				pts = PackedVector2Array([vis + d * r * 1.8, vis - d * r * 0.8 + n * r * 0.9, vis - d * r * 0.3, vis - d * r * 0.8 - n * r * 0.9])
				lines.polyline(pts, true, pc, 1.2, 0.6, 1.4)
				if not drawing and lance_cd <= 0.0:
					lines.seg(vis + d * r * 2.2, vis + d * r * 3.4, pc, 1.5, 0.8, 0.8)
			"sapper":
				lines.circle(vis, r, pc, 6, 1.2, 0.6, 1.4)
				lines.seg(vis + Vector2(-r * 0.5, 0), vis + Vector2(r * 0.5, 0), pc, 1.0, 0.5, 1.0)
				lines.seg(vis + Vector2(0, -r * 0.5), vis + Vector2(0, r * 0.5), pc, 1.0, 0.5, 1.0)
			_:
				lines.polyline(pts, true, pc, 1.2, 0.6, 1.3)
		lines.seg(vis, vis + Vector2(last_dir) * r * 1.6, pc, 1.5, 0.8, 1.0)
		draw_ability_ring()


func draw_qix(q: QixBody) -> void:
	var n := q.hist.size()
	for i in n:
		var seg: PackedVector2Array = q.hist[i]
		var col: Color = QIX_COLORS[(frame / 3 + i + q.col_off + int(cur_gal().qix_shift)) % 8]
		col.a = 0.2 + 0.6 * (1.0 - float(i) / QIX_HIST)
		lines.seg(seg[0], seg[1], col, 2.0, 0.5, 1.2 if i == 0 else 1.0)


## Word-wrap for the narrow run columns.
func wrap_text(text: String, max_chars: int) -> Array:
	var out: Array = []
	var line := ""
	for w in text.split(" "):
		if line != "" and line.length() + 1 + w.length() > max_chars:
			out.append(line)
			line = w
		else:
			line = w if line == "" else line + " " + w
	if line != "":
		out.append(line)
	return out


## The run HUD: the field sits in the middle of the tube, so the readouts split into a column
## on either side. Left: where you are and how you're doing. Right: what you're earning.
func draw_hud() -> void:
	var lx := RUN_LX
	var rx := RUN_RX
	var w := RUN_COL_W
	# --- left column: sector, hull, claim, ship
	var y := 116.0
	VectorFont.draw(lines, "SECTOR %02d" % level, Vector2(lx, y), 18, coast_color(), 0.6, 0.2)
	VectorFont.draw(lines, String(gal.name), Vector2(lx, y + 26), 10, Palette.DIM, 0.3, 0.1)
	y += 56
	VectorFont.draw(lines, "HULL", Vector2(lx, y), 14, Palette.DIM, 0.4, 0.1)
	for i in range(maxi(0, lives)):
		var c := Vector2(lx + 70 + i * 22, y + 7)
		var r := 6.0
		lines.polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]),
			true, Palette.FULLBRIGHT, 1.0, 0.5, 1.0)
	y += 44
	var frac := claimed_frac()
	VectorFont.draw(lines, "CLAIMED %3d%%" % int(frac * 100.0), Vector2(lx, y), 15, Palette.WHITE, 0.5, 0.2)
	VectorFont.draw(lines, "TARGET %d%%" % int(TARGET * 100.0), Vector2(lx + w, y + 3), 11, Palette.DIM, 0.4, 0.1, 2)
	y += 26
	lines.rect(Rect2(lx, y, w, 14), Palette.DIM, 0.4, 0.1, 0.8)
	if frac > 0.0:
		var bw := w * minf(frac / TARGET, 1.0)
		var bc := Palette.GREEN if frac >= TARGET else Palette.CYAN
		lines.seg(Vector2(lx + 2, y + 7), Vector2(lx + 2 + bw, y + 7), bc, 0.8, 0.3, 4.5)
	lines.seg(Vector2(lx + w, y - 4), Vector2(lx + w, y + 18), Palette.YELLOW, 1.0, 0.4, 1.0)
	y += 46
	var ship_line: String = ship.name
	var sub := ""
	var ab := -1.0        # ability readiness 0..1, -1 = no bar
	var ab_col := Palette.CYAN
	match String(ship.id):
		"bulwark":
			if drawing:
				sub = "HARDENED %d/%d" % [int(floor(harden_len)), trail.size()]
			if not seals.is_empty():
				var s0: Seal = seals[0]
				sub += ("   " if sub != "" else "") + "SEALS %d" % seals.size()
				ab = s0.harden / maxf(1.0, float(s0.cells.size()))
				ab_col = Palette.GREEN
		"leaper":
			if leap_building:
				sub = "AIM %d/%d   RELEASE: LEAP" % [int(leap_len), leap_max()]
				ab = leap_len / float(leap_max())
				ab_col = Palette.YELLOW
			elif wall_building:
				sub = "ONE SIDE HARD - OTHER RUNNING" if (wall_done[0] or wall_done[1]) else "WALL BUILDING - A HIT HURTS"
				ab_col = Palette.YELLOW
			else:
				sub = "HOLD SPACE: BUILD A LINE"
		"lancer":
			if tether_active:
				sub = "RIDING"
				if bends_left > 0:
					sub += "   BENDS %d" % bends_left
				if lattice_ok:
					sub += "   LATTICE"
			elif lance_cd > 0.0:
				sub = "LANCE %.1fS" % lance_cd
				ab = 1.0 - lance_cd / lance_cd_max()
			else:
				sub = "LANCE READY"
				ab = 1.0
				ab_col = Palette.GREEN
		"sapper":
			if sap_live:
				sub = "CHARGING %d   RELEASE: BLOW" % int(round(sap_charge))
				ab = sap_charge / float(sap_radius())
				ab_col = Palette.YELLOW
			else:
				sub = "HOLD SPACE: CHARGE"
	VectorFont.draw(lines, ship_line, Vector2(lx, y), 14, Palette.WHITE, 0.4, 0.15)
	y += 20
	if sub != "":
		VectorFont.draw(lines, sub, Vector2(lx, y), 10, Palette.WHITE, 0.4, 0.12)
		y += 18
	if ab >= 0.0:
		lines.rect(Rect2(lx, y, w, 9), Palette.DIM, 0.3, 0.1, 0.7)
		if ab > 0.0:
			lines.seg(Vector2(lx + 2, y + 4.5), Vector2(lx + 2 + (w - 4) * ab, y + 4.5), ab_col, 0.6, 0.3, 3.0)
		y += 20
	var status := ""
	var sc := Palette.DIM
	if drawing:
		status = "DRAWING  X2 SLOW" if slow_held else "DRAWING"
		sc = Palette.MAGENTA if slow_held else Palette.ORANGE
		if braced:
			var caught := harden_len >= float(trail.size())
			status = "BRACED  HARD UP TO YOU" if caught else "BRACED  HARDENING X3"
			sc = Palette.CYAN
		if fuse_on:
			status = "FUSE LIT!"
			sc = Palette.FULLBRIGHT
	elif sap_live:
		status = "CHARGE EXPOSED"
		sc = Palette.YELLOW
	elif invuln > 0.0 and state == State.PLAYING:
		status = "SHIELDED"
		sc = Palette.CYAN
	if status != "":
		VectorFont.draw(lines, status, Vector2(lx, y + 8), 15, sc, 1.0, 0.4)
	# how-to card at the foot of the left column
	var help1 := "SPACE: DRAW INTO THE VOID. CLOSE A LOOP TO CLAIM."
	var help2 := "ENCLOSE NODES FOR FLUX. SHIFT: SLOW, +1 EACH."
	var verb := "SPACE DRAW"
	match ship.id:
		"sapper":
			help1 = "HOLD SPACE IN THE VOID OR ON THE COAST: A DISC GROWS."
			help2 = "IT CAN BE HIT. RELEASE TO CLAIM IT. ENCLOSE NODES FOR FLUX."
			verb = "SPACE CHARGE"
		"leaper":
			help1 = "HOLD SPACE TO AIM THE BUOY, ARROWS TURN IT. RELEASE: LEAP."
			help2 = "RELEASE: LEAP TO THE TIP, A WALL SPLITS BOTH WAYS. HOLD TO THE FAR COAST TO LEAP THERE. FIRST SIDE TO LAND HARDENS."
			verb = "SPACE LEAP"
		"lancer":
			help1 = "SPACE: LANCE A TETHER AHEAD AND RIDE IT TO LAND."
			help2 = "IT CAN BE CUT. STEER + SPACE MID-RIDE TO BEND."
			verb = "SPACE LANCE"
		"bulwark":
			help1 = "HOLD SPACE TO ADVANCE. LET GO IN THE VOID: BRACE, HARDENING X3."
			help2 = "THE TRAIL HARDENS BEHIND YOU. LOOPS SEAL WHEN IT CATCHES UP."
	var help: Array = wrap_text(help1 + " " + help2, 40)
	var hy := 866.0 - help.size() * 16.0
	lines.seg(Vector2(lx, hy - 14), Vector2(lx + w, hy - 14), Palette.DIM, 0.3, 0.1, 0.7)
	for i in help.size():
		VectorFont.draw(lines, help[i], Vector2(lx, hy + i * 16.0), 10, Palette.DIM, 0.3, 0.1)
	# --- right column: earnings, the sector's threats, the keys
	y = 116.0
	draw_dock_currency(Vector2(rx + 12, y + 8), fmt(Save.data.flux), false)
	draw_dock_currency(Vector2(rx + 170, y + 8), str(int(Save.data.isotope)), true)
	y += 52
	var nc := Palette.YELLOW if sector_nodes_captured < nodes.size() else Palette.GREEN
	VectorFont.draw(lines, "NODES %d/%d" % [sector_nodes_captured, nodes.size()], Vector2(rx, y), 14, nc, 0.5, 0.2)
	if level == Galaxies.LENGTH and not endless:
		VectorFont.draw(lines, "BOSS: " + String(gal.boss_name), Vector2(rx, y + 40), 12, Palette.RED, 0.6, 0.2)
	var keys := ["ARROWS  MOVE", verb.replace(" ", "  "), "SHIFT  SLOW", "ESC  ABORT"]
	var ky := 866.0 - keys.size() * 16.0
	lines.seg(Vector2(rx, ky - 14), Vector2(rx + w, ky - 14), Palette.DIM, 0.3, 0.1, 0.7)
	for i in keys.size():
		VectorFont.draw(lines, keys[i], Vector2(rx, ky + i * 16.0), 10, Palette.DIM, 0.3, 0.1)


# ------------------------------------------------------------------ flux nodes
func uncaptured_nodes() -> int:
	var n := 0
	for nd in nodes:
		if not (nd as FluxNode).captured:
			n += 1
	return n


## Place a node in the open void, away from the rim, other nodes, and the surveyor's start.
func spawn_node(telegraph: float) -> void:
	var r := 1 + Save.rim()
	var margin := r + 10
	var best := Vector2i(-1, -1)
	var best_d := -1.0
	for tries in 40:
		var c := Vector2i(randi_range(margin, N - 1 - margin), randi_range(margin, N - 1 - margin))
		if cells[idx(c.x, c.y)] != FREE:
			continue
		var d := 1e9
		for nd in nodes:
			d = minf(d, Vector2(c - (nd as FluxNode).cell).length())
		d = minf(d, Vector2(c - p).length())
		if d > best_d:
			best_d = d
			best = c
		if d > 26.0:
			break
	if best.x < 0:
		return
	var fn := FluxNode.new()
	fn.cell = best
	fn.telegraph = telegraph
	fn.phase = randf() * TAU
	# rare nodes carry Isotope: from sector 2 on, likelier in later galaxies
	if level >= 2 and randf() < 0.12 + 0.06 * Galaxies.index_of(gal.id):
		fn.rare = true
	nodes.append(fn)


func draw_nodes() -> void:
	for nd in nodes:
		var fn: FluxNode = nd
		var c := center(fn.cell)
		if fn.telegraph > 0.0:
			# surfacing: a ring tightens onto the spot
			var k := clampf(fn.telegraph / 2.0, 0.0, 1.0)
			var col := Palette.YELLOW
			col.a = 0.2 + 0.5 * (1.0 - k)
			lines.circle(c, 6.0 + 26.0 * k, col, 12, 1.5, 0.3, 0.8)
			continue
		if fn.captured:
			var gc := Palette.GREEN
			gc.a = 0.7
			lines.circle(c, 6.0, gc, 6, 0.8, 0.3, 0.9)
			continue
		var pulse := 0.5 + 0.5 * sin(time * 3.0 + fn.phase)
		var rr := 8.0 + 2.0 * pulse
		if fn.rare:
			# Isotope: a spinning four-point star in cyan-white, labelled ISO
			var a0 := time * 1.5 + fn.phase
			var sp := PackedVector2Array()
			for k in 8:
				var a := a0 + k * TAU / 8.0
				var rad := (rr + 3.0) if (k % 2 == 0) else 3.5
				sp.append(c + Vector2(cos(a), sin(a)) * rad)
			lines.polyline(sp, true, Palette.CYAN, 1.5, 0.5, 1.2)
			lines.circle(c, 2.5, Palette.FULLBRIGHT, 6, 1.0, 0.6, 0.9)
			var ic := Palette.CYAN
			ic.a = 0.5 + 0.4 * pulse
			VectorFont.draw(lines, "ISO", c + Vector2(15, -6), 10, ic, 0.5, 0.3)
			if randf() < 0.2:
				sparks.emit(c, Vector2(randf_range(-40, 40), randf_range(-60, -10)), 0.6, Palette.CYAN, 1.2)
			continue
		lines.circle(c, rr, Palette.YELLOW, 6, 1.2, 0.5, 1.2)
		lines.circle(c, 3.0, Palette.FULLBRIGHT, 6, 1.0, 0.6, 0.9)
		var vc := Palette.YELLOW
		vc.a = 0.5 + 0.4 * pulse
		VectorFont.draw(lines, str(node_value()), c + Vector2(13, -6), 11, vc, 0.5, 0.3)
		if randf() < 0.15:
			sparks.emit(c, Vector2(randf_range(-30, 30), randf_range(-70, -20)), 0.5, Palette.YELLOW, 1.5)


# ------------------------------------------------------------------ hazards
func node_value() -> int:
	return Save.node_value() + int(gal.node_bonus)


## A free cell in the void, at least `margin` cells from the rim and as far as practical from `avoid`.
func find_void_cell(margin: int, avoid: Array, want_d: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := -1.0
	for tries in 40:
		var c := Vector2i(randi_range(margin, N - 1 - margin), randi_range(margin, N - 1 - margin))
		if cells[idx(c.x, c.y)] != FREE:
			continue
		var d := 1e9
		for a in avoid:
			d = minf(d, Vector2(c - (a as Vector2i)).length())
		if d > best_d:
			best_d = d
			best = c
		if d > want_d:
			break
	return best


func occupied_cells() -> Array:
	var out: Array = [p]
	for nd in nodes:
		out.append((nd as FluxNode).cell)
	for tr in turrets:
		out.append((tr as Turret).cell)
	for sp in spawners:
		out.append((sp as Spawner).cell)
	return out


func spawn_hazards(lay: Dictionary) -> void:
	turrets.clear()
	bolts.clear()
	spawners.clear()
	mites.clear()
	for td in lay.turrets:
		var t := Turret.new()
		t.cell = td.cell
		t.axis = td.axis
		t.fire_t = 2.0 + randf() * 3.0
		t.phase = randf() * TAU
		turrets.append(t)
	for sd in lay.spawners:
		var s := Spawner.new()
		s.cell = sd.cell
		s.spawn_t = 4.0 + randf() * 2.0
		spawners.append(s)


func update_hazards(dt: float) -> void:
	# turrets: a bolt each way along their axis every 3 s; bolts die on claimed land
	for tr in turrets:
		var t: Turret = tr
		if t.captured:
			continue
		if t.rotate:
			t.rot_t += dt
			if t.rot_t >= 4.0:
				t.rot_t = 0.0
				t.axis = Vector2i(-t.axis.y, t.axis.x)
				sparks.ripple(center(t.cell), 4.0, 160.0, 0.3, Palette.ORANGE)
		t.fire_t -= dt
		if t.fire_t <= 0.0:
			t.fire_t = t.interval
			var c := center(t.cell)
			for sgn in [1.0, -1.0]:
				var b := Bolt.new()
				b.vel = Vector2(t.axis) * 150.0 * sgn
				b.pos = c + b.vel.normalized() * 12.0
				bolts.append(b)
				sparks.burst(b.pos, 8, 90.0, 1.5, 0.3, Palette.ORANGE, 0.0, b.vel * 0.3)
	var j := bolts.size() - 1
	while j >= 0:
		var b: Bolt = bolts[j]
		b.pos += b.vel * dt
		var bc := to_cell(b.pos)
		if not in_bounds(bc) or cells[idx(bc.x, bc.y)] == CLAIMED or cells[idx(bc.x, bc.y)] == ROCK:
			sparks.burst(b.pos, 10, 80.0, 1.5, 0.3, Palette.ORANGE)
			bolts.remove_at(j)
		elif cells[idx(bc.x, bc.y)] == TRAIL:
			if tether_hit(bc) and wire_hit():
				die("TURRET FIRE")
				return
			bolts.remove_at(j)
		elif sap_live and b.pos.distance_to(center(sap_cell)) < sap_charge * CELL:
			bolts.remove_at(j)
			if wire_hit():
				die("TURRET FIRE")
				return
		elif exposed() and b.pos.distance_to(vis) < 7.0:
			die("TURRET FIRE")
			return
		elif cells[idx(bc.x, bc.y)] == SEAL_SOFT:
			lose_seal(seal_at(bc))
			bolts.remove_at(j)
		j -= 1

	# spawners: breed up to 3 mites each; mites home on the surveyor through the void
	var mite_speed := 11.0 * CELL * 0.4 * (1.0 + 0.05 * level)
	for sp in spawners:
		var s: Spawner = sp
		if s.captured:
			continue
		if s.mobile:
			# the Brood drifts through the void like a slow Anomaly, bouncing off land
			s.vel = s.vel.rotated(randf_range(-1.0, 1.0) * dt).normalized() * 40.0
			var np := s.pos + s.vel * dt
			if cell_blocked(to_cell(np)):
				s.vel = -s.vel.rotated(randf_range(-0.6, 0.6))
			else:
				s.pos = np
			s.cell = to_cell(s.pos)
		s.spawn_t -= dt
		if s.spawn_t <= 0.0 and s.alive < s.max_alive:
			s.spawn_t = s.interval
			s.alive += 1
			var m := Mite.new()
			m.pos = center(s.cell)
			m.vel = Vector2.RIGHT.rotated(randf() * TAU) * mite_speed
			m.home = s
			mites.append(m)
			sparks.ripple(m.pos, 4.0, 200.0, 0.4, Palette.PURPLE)
	j = mites.size() - 1
	while j >= 0:
		var m: Mite = mites[j]
		var want := (vis - m.pos).normalized() * mite_speed
		m.vel = m.vel.lerp(want, 1.0 - exp(-dt * 1.5))
		m.spin += dt * 6.0
		var np := m.pos + m.vel * dt
		if cell_blocked(to_cell(np)):
			# slide along the coast: try each axis alone, else bounce
			if not cell_blocked(to_cell(Vector2(np.x, m.pos.y))):
				np = Vector2(np.x, m.pos.y)
			elif not cell_blocked(to_cell(Vector2(m.pos.x, np.y))):
				np = Vector2(m.pos.x, np.y)
			else:
				np = m.pos
				m.vel = -m.vel
		m.pos = np
		var mc := to_cell(m.pos)
		if in_bounds(mc) and cells[idx(mc.x, mc.y)] == TRAIL:
			if tether_hit(mc) and wire_hit():
				die("MITE CONTACT")
				return
		elif sap_live and m.pos.distance_to(center(sap_cell)) < sap_charge * CELL:
			if wire_hit():
				die("MITE CONTACT")
				return
		elif exposed() and m.pos.distance_to(vis) < 8.0:
			die("MITE CONTACT")
			return
		if in_bounds(mc) and cells[idx(mc.x, mc.y)] == SEAL_SOFT:
			lose_seal(seal_at(mc))
		if randf() < 0.1:
			sparks.emit(m.pos, Vector2(randf_range(-40, 40), randf_range(-40, 40)), 0.25, Palette.RED, 2.0)
		j -= 1


func draw_hazards() -> void:
	for tr in turrets:
		var t: Turret = tr
		var c := center(t.cell)
		if t.captured:
			var gc := Palette.GREEN
			gc.a = 0.7
			lines.rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), gc, 0.8, 0.2, 0.9)
			continue
		lines.rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), Palette.ORANGE, 1.2, 0.4, 1.2)
		var ax := Vector2(t.axis)
		lines.seg(c - ax * 16.0, c + ax * 16.0, Palette.RED, 1.5, 0.5, 1.4)
		# charge-up: the muzzles brighten in the last 0.6 s before a shot
		var charge := clampf(1.0 - t.fire_t / 0.6, 0.0, 1.0)
		if charge > 0.0:
			var wc := Palette.FULLBRIGHT
			wc.a = charge
			lines.seg(c + ax * 16.0, c + ax * 16.0, wc, 2.0, 0.6, 1.0 + 2.0 * charge)
			lines.seg(c - ax * 16.0, c - ax * 16.0, wc, 2.0, 0.6, 1.0 + 2.0 * charge)
	for bo in bolts:
		var b: Bolt = bo
		lines.seg(b.pos - b.vel.normalized() * 12.0, b.pos, Palette.ORANGE, 1.0, 0.4, 1.3)
		lines.seg(b.pos, b.pos, Palette.FULLBRIGHT, 1.0, 0.5, 1.6)
	for sp in spawners:
		var s: Spawner = sp
		var c := s.pos if s.mobile else center(s.cell)
		if s.mother and not s.captured:
			lines.circle(c, 20.0, Palette.MAGENTA, 8, 2.0, 0.5, 1.0)
		if s.captured:
			var gc := Palette.GREEN
			gc.a = 0.7
			lines.circle(c, 9.0, gc, 6, 0.8, 0.2, 0.9)
			continue
		lines.circle(c, 12.0, Palette.PURPLE, 6, 1.2, 0.4, 1.2)
		var pts := PackedVector2Array()
		for k in 3:
			var a := time * 2.0 + k * TAU / 3.0
			pts.append(c + Vector2(cos(a), sin(a)) * 6.0)
		lines.polyline(pts, true, Palette.MAGENTA, 1.5, 0.5, 1.0)
		var k2 := clampf(1.0 - s.spawn_t / 1.0, 0.0, 1.0)
		if k2 > 0.0 and s.alive < 3:
			var wc := Palette.MAGENTA
			wc.a = k2
			lines.circle(c, 12.0 + 8.0 * k2, wc, 6, 2.0, 0.5, 0.8)
	for mi in mites:
		var m: Mite = mi
		var pts := PackedVector2Array()
		for k in 3:
			var a := m.spin + k * TAU / 3.0
			pts.append(m.pos + Vector2(cos(a), sin(a)) * 6.0)
		lines.polyline(pts, true, Palette.RED, 2.0, 0.5, 1.2)


# ------------------------------------------------------------------ lancer
## Fire a tether from the coast straight across the void in the facing direction. The whole line
## becomes trail at once; the ship then rides it (ride_step) and claims when it lands.
func fire_lance(extend := false) -> void:
	# extend = a mid-ride bend: keep the ridden trail and lance on from where the ship is
	var d := last_dir
	var ray: Array[Vector2i] = []
	var c := p + d
	while in_bounds(c) and cells[idx(c.x, c.y)] == FREE:
		ray.append(c)
		c += d
	if ray.size() < 3 or not in_bounds(c) or cells[idx(c.x, c.y)] == ROCK:
		set_msg("NO LINE", 0.6)
		lines.spike(1.0, 0.2)
		return
	if not extend:
		anchor = p
		trail.clear()
		tether_i = -1
		lance_cd = lance_cd_max()
		bends_left = up("bend")
		lattice_ok = up("lattice") > 0
	for rc in ray:
		cells[idx(rc.x, rc.y)] = TRAIL
		trail.append(rc)
	drawing = true
	trail_slow = false
	fuse_on = false
	fuse_pos = 0.0
	idle_t = 0.0
	harden_len = 0.0
	tether_active = true
	tether_dir = d
	move_acc = 0.0
	var pts := PackedVector2Array([center(p), center(ray[ray.size() - 1])])
	sparks.zap_polyline(pts, Palette.CYAN, 2600.0, 6.0)
	lines.spike(2.5, 0.4)
	shake = maxf(shake, 0.3)
	set_msg("LANCE", 0.5)


func ride_step() -> void:
	tether_i += 1
	if tether_i < trail.size():
		p = trail[tether_i]
		last_dir = tether_dir
		return
	# landed: the cell past the tether is coast, which closes the line like any claim
	var t: Vector2i = trail[trail.size() - 1] + tether_dir
	tether_active = false
	p = t
	complete_claim()


## Leave the tether sideways: the part ahead of the ship vanishes, the ridden part stays a trail.
func step_off(dir: Vector2i, slow: bool) -> bool:
	var t := p + dir
	if not in_bounds(t) or cells[idx(t.x, t.y)] != FREE:
		return false
	for i in range(tether_i + 1, trail.size()):
		var rc := trail[i]
		cells[idx(rc.x, rc.y)] = FREE
	trail.resize(maxi(0, tether_i + 1))
	tether_active = false
	if trail.is_empty():
		# never left the anchor: this is just a normal first step into the void
		drawing = false
		return try_step(dir, true, slow)
	last_dir = dir
	return try_step(dir, true, slow)


# ------------------------------------------------------------------ sapper
## The charge goes off: every free cell within sap_radius() becomes land, the Anomaly is shoved out
## if it was inside, then the trail closes like a normal claim (which also flood-claims anything
## the disc and trail now enclose).
func detonate(rad_cells: int) -> void:
	sap_live = false
	sap_charge = 0.0
	leap_building = false
	wall_building = false
	var gained := 0
	var rad := maxi(2, rad_cells)
	var r2 := rad * rad
	# SHOCKWAVE: clear mites, bolts and Sparx a little beyond the blast
	if up("shock") > 0:
		var shock := (rad + 2 * up("shock")) * CELL
		var sc0 := center(sap_cell)
		var j := mites.size() - 1
		while j >= 0:
			var m: Mite = mites[j]
			if m.pos.distance_to(sc0) <= shock:
				sparks.burst(m.pos, 16, 140.0, 1.5, 0.4, Palette.RED)
				m.home.alive -= 1
				mites.remove_at(j)
			j -= 1
		j = bolts.size() - 1
		while j >= 0:
			if (bolts[j] as Bolt).pos.distance_to(sc0) <= shock:
				bolts.remove_at(j)
			j -= 1
		for sx in sparxes:
			var s: SparxBody = sx
			if s.vis.distance_to(sc0) <= shock:
				sparks.burst(s.vis, 30, 200.0, 1.5, 0.5, Palette.ORANGE)
				var far := Vector2i(-1, -1)
				var far_d := -1
				for tries in 40:
					var c := Vector2i(randi() % N, randi() % N)
					if border[idx(c.x, c.y)] == 0:
						continue
					var d := maxi(absi(c.x - p.x), absi(c.y - p.y))
					if d > far_d:
						far_d = d
						far = c
				if far.x >= 0:
					s.c = far
					s.prev = far
					s.vis = center(far)
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			if dx * dx + dy * dy > r2:
				continue
			var c := sap_cell + Vector2i(dx, dy)
			if in_bounds(c) and cells[idx(c.x, c.y)] == FREE:
				cells[idx(c.x, c.y)] = CLAIMED
				gained += 1
	free_count -= gained
	run_cells += gained
	# anything caught in the blast gets thrown clear
	for q in qixes:
		var qc := to_cell(q.c)
		if in_bounds(qc) and cells[idx(qc.x, qc.y)] == CLAIMED:
			var ci := qix_cell_index(q)
			if ci >= 0:
				q.c = center(Vector2i(ci % N, ci / N))
				q.v = (q.c - center(sap_cell)).normalized() * q.v.length()
	var sc := center(sap_cell)
	sparks.ripple(sc, 6.0, 900.0, 0.6, Palette.FULLBRIGHT)
	sparks.ripple(sc, 4.0, 600.0, 0.9, Palette.YELLOW)
	sparks.burst(sc, 140, 480.0, 0.8, 0.8, Palette.YELLOW, 0.03, Vector2.ZERO, 1.2)
	sparks.burst(sc, 80, 200.0, 2.0, 1.4, Palette.ORANGE, 0.1, Vector2.ZERO, 0.8)
	shake = 1.0
	lines.spike(6.0, 0.8)
	set_msg("DETONATION", 1.0)
	complete_claim()


# ------------------------------------------------------------------ islander
## Throw a buoy up to buoy_range() cells in the facing direction. It lands on the farthest spot
## whose 3x3 footprint is clear void and becomes an island: permanent land you can draw to,
## ride around, and loop from. Touching it with a trail closes the line as a causeway.
func island_spot_ok(c: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := c + Vector2i(dx, dy)
			if not in_bounds(q) or cells[idx(q.x, q.y)] != FREE:
				return false
	for nd in nodes:
		if Vector2(c - (nd as FluxNode).cell).length() < 2.5:
			return false
	for tr in turrets:
		if Vector2(c - (tr as Turret).cell).length() < 2.5:
			return false
	for sp in spawners:
		if Vector2(c - (sp as Spawner).cell).length() < 2.5:
			return false
	return true


func throw_buoy() -> void:
	var d := last_dir
	var best := Vector2i(-1, -1)
	for k in range(buoy_range(), 3, -1):
		var c := p + d * k
		if island_spot_ok(c):
			best = c
			break
	if best.x < 0:
		set_msg("NO LANDING", 0.8)
		lines.spike(1.0, 0.2)
		return
	buoy_charge -= 1
	buoy_flights.append([vis, center(best), 0.0, best])
	sparks.burst(vis, 12, 90.0, 1.5, 0.3, Palette.YELLOW, 0.0, Vector2(d) * 120.0)
	set_msg("BUOY AWAY", 0.6)


func update_buoys(dt: float) -> void:
	var j := buoy_flights.size() - 1
	while j >= 0:
		var f: Array = buoy_flights[j]
		f[2] += dt / 0.45
		if f[2] >= 1.0:
			land_buoy(f[3])
			buoy_flights.remove_at(j)
		j -= 1


func land_buoy(c: Vector2i) -> void:
	if not island_spot_ok(c):
		set_msg("BUOY LOST", 0.8)   # something moved in while it flew
		return
	var gained := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := c + Vector2i(dx, dy)
			cells[idx(q.x, q.y)] = CLAIMED
			gained += 1
	free_count -= gained
	run_cells += gained
	islands.append({"c": c, "r": 1, "t": 0.0})
	grid_changed()
	var cp := center(c)
	sparks.ripple(cp, 4.0, 360.0, 0.6, Palette.YELLOW)
	sparks.burst(cp, 50, 200.0, 1.5, 0.6, Palette.CYAN)
	lines.spike(2.0, 0.3)
	shake = maxf(shake, 0.25)


func draw_islands() -> void:
	for isl in islands:
		var c := center(isl.c as Vector2i)
		var pulse := 0.5 + 0.5 * sin(time * 2.5)
		var bc := Palette.YELLOW
		bc.a = 0.4 + 0.5 * pulse
		lines.circle(c, 5.0 + 3.0 * pulse, bc, 8, 0.8, 0.3, 0.9)
		lines.seg(c + Vector2(0, -3), c + Vector2(0, 3), Palette.FULLBRIGHT, 0.8, 0.4, 1.0)
		if int(isl.r) < tide_max_radius():
			# the tide: a faint ring creeping outward toward the next growth
			var k: float = clampf(float(isl.t) / TIDE_INTERVAL, 0.0, 1.0)
			var tc := Palette.CYAN
			tc.a = 0.15 + 0.35 * k
			var rr := (float(isl.r) + 0.5 + k) * CELL
			lines.rect(Rect2(c - Vector2(rr, rr), Vector2(rr * 2, rr * 2)), tc, 0.6, 0.2, 0.7)
	for f in buoy_flights:
		var t: float = f[2]
		var pos: Vector2 = (f[0] as Vector2).lerp(f[1], t) + Vector2(0, -sin(t * PI) * 40.0)
		lines.circle(pos, 4.0, Palette.YELLOW, 6, 1.0, 0.5, 1.2)
		var tail: Vector2 = (f[0] as Vector2).lerp(f[1], maxf(0.0, t - 0.12)) + Vector2(0, -sin(maxf(0.0, t - 0.12) * PI) * 40.0)
		lines.seg(tail, pos, Palette.YELLOW * Color(1, 1, 1, 0.6), 1.0, 0.4, 0.9)
		var lc := Palette.YELLOW
		lc.a = 0.35
		lines.rect(Rect2((f[1] as Vector2) - Vector2(12, 12), Vector2(24, 24)), lc, 0.6, 0.2, 0.7)


# ------------------------------------------------------------------ seeded sector layout
## Node and hazard placement for a sector, seeded by galaxy and sector number so the dock's
## scan shows exactly what the jump will land in. Assumes the field is empty inside the rim,
## which is true at sector start.
func sector_layout(g: Dictionary, lvl: int, rim: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [g.id, lvl])
	var r := 1 + rim
	var shape := sector_shape(g, lvl, rng)
	# Carved galaxies go through the arena builder: the silhouette is the outline and every pillar
	# in `shape` becomes a hole with its own one-cell rail (an inner coast you can cut to and from).
	var arena := SectorArena.build(lvl, rim, g.id, shape) if SectorArena.carved(g.id, lvl) else {}
	var start: Vector2i = arena.start if not arena.is_empty() else Vector2i(N / 2, r - 1)
	var occupied: Array = [start]
	var out := {"nodes": [], "turrets": [], "spawners": [], "shape": shape, "arena": arena, "start": start}
	for i in mini(6, 3 + (lvl - 1) / 3):
		var c := layout_pick(rng, r + 10, occupied, 26.0, shape, arena)
		occupied.append(c)
		var rare: bool = lvl >= 2 and rng.randf() < 0.12 + 0.06 * Galaxies.index_of(g.id)
		out.nodes.append({"cell": c, "rare": rare})
	for i in Galaxies.turret_count(g, lvl):
		var c := layout_pick(rng, r + 8, occupied, 22.0, shape, arena)
		occupied.append(c)
		out.turrets.append({"cell": c, "axis": Vector2i.RIGHT if (i % 2) == 0 else Vector2i.DOWN})
	for i in Galaxies.spawner_count(g, lvl):
		var c := layout_pick(rng, r + 8, occupied, 22.0, shape, arena)
		occupied.append(c)
		out.spawners.append({"cell": c})
	return out


## The sector's rock, as Rect2i in cells: pylons out in the void for galaxies that have them.
## They grow with the sector; the boss arena has a fixed four; endless sectors keep the vocabulary.
## In a carved galaxy each pylon sits inside the silhouette and gets a rail from the arena builder.
func sector_shape(g: Dictionary, lvl: int, rng: RandomNumberGenerator) -> Array:
	var rects: Array = []
	if String(g.shape) != "pillar":
		return rects
	if lvl == Galaxies.LENGTH:
		for off in [Vector2i(-30, -30), Vector2i(22, -30), Vector2i(-30, 22), Vector2i(22, 22)]:
			rects.append(Rect2i(Vector2i(N / 2, N / 2) + off, Vector2i(8, 8)))
		return rects
	if g.id == "belt" and lvl == 5:
		rects.append(Rect2i(Vector2i(N / 2 - 12, N / 2 - 12), Vector2i(24, 24)))   # the moat's core
		return rects
	var grade := mini(lvl, Galaxies.LENGTH)
	var n := mini(4, 1 + (grade + 1) / 2)
	for i in n:
		for tries in 30:
			var w := rng.randi_range(5, 6 + grade)
			var h := rng.randi_range(5, 6 + grade)
			var pos := Vector2i(rng.randi_range(18, N - 18 - w), rng.randi_range(18, N - 18 - h))
			var rr := Rect2i(pos, Vector2i(w, h))
			var ok := true
			for o in rects:
				if (o as Rect2i).grow(12).intersects(rr):
					ok = false
					break
			if ok and SectorArena.carved(g.id, lvl) and not SectorArena.rect_inside(g.id, lvl, rr, 7):
				ok = false   # keep a pylon and its rail clear of the carve so the rail is a real island
			if ok:
				rects.append(rr)
				break
	return rects


func layout_pick(rng: RandomNumberGenerator, margin: int, avoid: Array, want_d: float, shape: Array = [], arena: Dictionary = {}) -> Vector2i:
	var best := Vector2i(N / 2, N / 2)
	var best_d := -1.0
	for tries in 60:
		var c := Vector2i(rng.randi_range(margin, N - 1 - margin), rng.randi_range(margin, N - 1 - margin))
		if not arena.is_empty():
			c = arena.free_cells[rng.randi_range(0, arena.free_cells.size() - 1)]
		var inside := false
		for rc in shape:
			if (rc as Rect2i).grow(3).has_point(c):
				inside = true
				break
		if inside:
			continue
		var d := 1e9
		for a in avoid:
			d = minf(d, Vector2(c - (a as Vector2i)).length())
		if d > best_d:
			best_d = d
			best = c
		if d > want_d:
			break
	return best


# ------------------------------------------------------------------ dock briefing panes
func dashed(a: Vector2, b: Vector2, c: Color, dash := 10.0, gap := 8.0) -> void:
	var L := a.distance_to(b)
	var d := (b - a) / maxf(L, 0.001)
	var k := 0.0
	while k < L:
		lines.seg(a + d * k, a + d * minf(k + dash, L), c, 0.3, 0.1, 0.7)
		k += dash + gap


func arc(center: Vector2, radius: float, from: float, to: float, c: Color, thick := 1.0) -> void:
	var n := maxi(3, int(abs(to - from) / 0.25))
	var pts := PackedVector2Array()
	for i in range(n + 1):
		var a := from + (to - from) * float(i) / n
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	lines.polyline(pts, false, c, 0.5, 0.2, thick)


func pane_frame(r: Rect2, title: String, focus: bool) -> void:
	var fc := Palette.CYAN if focus else Palette.DIM
	fc.a = 0.9 if focus else 0.5
	lines.rect(r, fc, 0.4, 0.1, 0.9 if focus else 0.6)
	VectorFont.draw(lines, title, r.position + Vector2(10, 8), 10, fc, 0.4, 0.1)


# ------------------------------------------------------------------ ability cooldown ring
## A ring around the ship that fills as an ability recharges, and flashes when it's ready.
func draw_ability_ring() -> void:
	var r := 16.0
	match String(ship.id):
		"lancer":
			if lance_cd > 0.0 and not tether_active:
				var f := 1.0 - lance_cd / lance_cd_max()
				var bc := Palette.DIM
				bc.a = 0.6
				lines.circle(vis, r, bc, 16, 0.5, 0.2, 0.6)
				arc(vis, r, -PI * 0.5, -PI * 0.5 + TAU * f, Palette.CYAN, 1.2)
			elif lance_flash > 0.0:
				var fc := Palette.FULLBRIGHT
				fc.a = lance_flash / 0.5
				lines.circle(vis, r + (0.5 - lance_flash) * 30.0, fc, 16, 1.0, 0.4, 1.2)
		"sapper":
			if sap_live:
				# the charge: the disc so far, the cap as a faint ring, a flickering core
				lines.circle(vis, sap_charge * CELL, Palette.YELLOW, 32, 1.5, 0.4, 1.0)
				var dc := Palette.YELLOW
				dc.a = 0.3
				lines.circle(vis, sap_radius() * CELL, dc, 32, 0.8, 0.2, 0.6)
				lines.circle(vis, 3.0 + 2.0 * sin(time * 30.0), Palette.FULLBRIGHT, 6, 2.0, 0.6, 1.2)
				VectorFont.draw(lines, "%d" % int(round(sap_charge)), vis + Vector2(0, -sap_charge * CELL - 18), 12, Palette.YELLOW, 1.0, 0.4, 1)
		"leaper":
			if leap_building:
				# aiming: a dashed ghost to the buoy, which slides out as the hold goes on
				arc(vis, r, -PI * 0.5, -PI * 0.5 + TAU * leap_len / float(leap_max()), Palette.YELLOW, 1.2)
				var tgt := center(leap_target())
				var gc := Palette.YELLOW
				gc.a = 0.5
				dashed(center(anchor), tgt, gc, 6.0, 6.0)
				lines.circle(tgt, 4.0 + 1.5 * sin(time * 8.0), Palette.YELLOW, 8, 1.0, 0.4, 1.0)
				lines.seg(tgt + Vector2(0, -3), tgt + Vector2(0, 3), Palette.FULLBRIGHT, 0.8, 0.4, 1.0)
				var pd := Vector2(-leap_dir.y, leap_dir.x) * 5.0
				lines.seg(tgt - pd, tgt + pd, Palette.FULLBRIGHT, 0.8, 0.4, 0.8)


# ------------------------------------------------------------------ title screen
## The tube powers on (dot, line, picture: the outro in reverse), the title plots itself in
## over a drifting Lissajous with the Anomaly prowling behind it, and a four-item menu waits.
func start_battle_royale() -> void:
	battle = BattleRoyale.new()
	battle.start()
	wire_battle_net()
	state = State.BATTLE_ROYALE
	lines.zoom = Vector2.ONE
	shake = 0.0
	qixes.clear()
	sparxes.clear()
	trail.clear()
	drawing = false


func go_title() -> void:
	field_arena = {}
	field_shape = []
	state = State.TITLE
	set_field_x(FX_DOCK)
	if OS.has_feature("editor") and not TITLE_ITEMS.has("TUBE"):
		TITLE_ITEMS.insert(2, "TUBE")
		TITLE_DESCS.insert(2, "TUNE THE TUBE (DEV)")
	reset_field(0)
	trail.clear()
	drawing = false
	sparxes.clear()
	qixes.clear()
	spawn_qix()
	surv_scale = 1.0
	title_t = 0.0
	title_exit = -1
	title_exit_t = 0.0
	show_log = false
	msg_t = 0.0
	lines.zoom = Vector2(0.01, 0.004)
	sparks.ripple(lines.zoom_center, 2.0, 400.0, 0.5, Palette.FULLBRIGHT)
	Save.save_data()


func title_paths() -> Array[PackedVector2Array]:
	return VectorFont.paths("GALAXTIX", Vector2(FX + N * CELL * 0.5, FY + N * CELL * 0.34), 96, 1, VectorFont.display)


func update_title(dt: float) -> void:
	title_t += dt
	liss_phase += dt * 0.35
	# power-on: a dot stretches into a line, the line opens into the picture
	if title_t < 0.35:
		lines.zoom = Vector2(0.02 + 0.98 * (title_t / 0.35), 0.004)
	elif title_t < 0.85:
		var k := (title_t - 0.35) / 0.5
		lines.zoom = Vector2(1.0, 0.004 + 0.996 * k * k)
		if title_t - dt < 0.35:
			lines.spike(3.0, 0.5)
	else:
		lines.zoom = Vector2.ONE
	for q in qixes:
		update_qix(q, dt, 55.0)
	if title_exit >= 0:
		title_exit_t += dt
		if title_exit_t > 0.55:
			match TITLE_ITEMS[title_exit]:
				"JUMP":
					go_dock()
					pane_t = 0.0
				"BATTLE ROYALE":
					start_battle_royale()
				"TUBE":
					get_tree().change_scene_to_file("res://scenes/fx_lab.tscn")
				"QUIT":
					get_tree().quit()
		return
	if title_t < 1.0:
		return
	if Input.is_action_just_pressed("move_up"):
		title_sel = (title_sel - 1 + TITLE_ITEMS.size()) % TITLE_ITEMS.size()
		lines.spike(0.8, 0.2)
	if Input.is_action_just_pressed("move_down"):
		title_sel = (title_sel + 1) % TITLE_ITEMS.size()
		lines.spike(0.8, 0.2)
	if armed_item != "" and (TITLE_ITEMS[title_sel] != armed_item or Input.is_action_just_pressed("abort")):
		disarm_title()
	if Input.is_action_just_pressed("abort") and show_log:
		show_log = false
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("launch"):
		activate_title_item()


func activate_title_item() -> void:
	var item := TITLE_ITEMS[title_sel]
	if item == "LOG":
		show_log = not show_log
		lines.spike(1.5, 0.3)
		return
	if ARMED_DESCS.has(item):
		if armed_item != item:
			armed_item = item
			TITLE_DESCS[title_sel] = ARMED_DESCS[item]
			lines.spike(1.5, 0.3)
			return
		if item == "RESET":
			Save.reset_data()
			set_msg("SAVE WIPED", 1.5)
		else:
			set_msg("+%s FLUX REFUNDED" % fmt(Save.respec()), 1.5)
		disarm_title()
		sparks.burst(Vector2(PANEL_X + 100, 300), 60, 260.0, 1.5, 0.8, Palette.RED if item == "RESET" else Palette.GREEN)
		lines.spike(4.0, 0.5)
		shake = maxf(shake, 0.6)
		return
	title_exit = title_sel
	title_exit_t = 0.0
	for pth in title_paths():
		sparks.zap_polyline(pth, Palette.CYAN, 2600.0, 5.0)
	lines.spike(4.0, 0.5)
	shake = maxf(shake, 0.4)


func disarm_title() -> void:
	armed_item = ""
	TITLE_DESCS[TITLE_ITEMS.find("RESPEC")] = "REFUND EVERY UPGRADE. ENTER TWICE."
	TITLE_DESCS[TITLE_ITEMS.find("RESET")] = "WIPE THE SAVE. ENTER TWICE."


func draw_title_field() -> void:
	var cx := FX + N * CELL * 0.5
	# a slow Lissajous figure: the classic scope idle
	var lp := PackedVector2Array()
	var cy := FY + N * CELL * 0.62
	for i in 241:
		var u := float(i) / 240.0 * TAU
		lp.append(Vector2(cx + sin(3.0 * u + liss_phase) * 300.0, cy + sin(2.0 * u) * 150.0))
	var lc := Palette.GREEN
	lc.a = 0.35
	lines.polyline(lp, false, lc, 0.8, 0.3, 0.8)
	# title, plotted in after power-on, burst into sparks on exit
	if title_exit < 0:
		var tf := clampf((title_t - 0.9) / 0.9, 0.0, 1.0)
		lines.trace(title_paths(), tf, Palette.CYAN, 1.5, 0.4, 1.5)
		if tf >= 1.0:
			var sub := "CLAIM THE VOID"
			var n := int(clampf((title_t - 1.8) * 30.0, 0.0, float(sub.length())))
			VectorFont.draw(lines, sub.substr(0, n), Vector2(cx, FY + N * CELL * 0.34 + 120), 18, Palette.WHITE, 1.0, 0.4, 1)
	# scope readouts in the corner, for the vibe
	var rc := Palette.DIM
	rc.a = 0.7
	VectorFont.draw(lines, "CH1 2V/DIV   TRIG AUTO   XY", Vector2(FX + 14, FY + N * CELL - 22), 9, rc, 0.3, 0.1)
	VectorFont.draw(lines, "1600X900", Vector2(FX + N * CELL - 14, FY + N * CELL - 22), 9, rc, 0.3, 0.1, 2)
	if show_log:
		draw_log()


func draw_log() -> void:
	var cx := FX + N * CELL * 0.5
	var y := FY + N * CELL * 0.5
	lines.rect(Rect2(cx - 260, y - 30, 520, 250), Palette.DIM, 0.4, 0.1, 0.8)
	VectorFont.draw(lines, "JUMP LOG", Vector2(cx, y), 20, Palette.YELLOW, 0.8, 0.3, 1, 1.0, VectorFont.display)
	var rows := [
		["JUMPS", str(int(Save.data.runs))],
		["FLUX EARNED", fmt(float(Save.data.total_flux))],
		["ISOTOPE", str(int(Save.data.isotope))],
		["SHIPS", "%d/%d" % [1 + Save.data.ships.size(), Ships.LIST.size()]],
		["STARCHARTS", str(int(Save.data.starcharts))],
	]
	for g in Galaxies.LIST:
		rows.append([String(g.name), ("SECTOR %02d" % Galaxies.best(g.id)) if Galaxies.best(g.id) > 0 else "--"])
	var ry := y + 40
	for r in rows:
		VectorFont.draw(lines, r[0], Vector2(cx - 230, ry), 12, Palette.WHITE, 0.4, 0.15)
		VectorFont.draw(lines, r[1], Vector2(cx + 230, ry), 12, Palette.CYAN, 0.4, 0.15, 2)
		ry += 26


func draw_title_panel() -> void:
	var a := clampf((title_t - 1.2) / 0.6, 0.0, 1.0)
	if a <= 0.0:
		return
	var y := 200.0
	for i in TITLE_ITEMS.size():
		var sel := i == title_sel
		var col := Palette.FULLBRIGHT if sel else Palette.DIM
		col.a = a
		if title_exit >= 0 and i != title_exit:
			col.a *= 0.3
		var ry := y + i * 84
		if sel:
			var pulse := 0.6 + 0.4 * sin(time * 8.0)
			var mc := Palette.YELLOW
			mc.a = pulse * a
			var rx := PANEL_X + 8
			lines.polyline(PackedVector2Array([Vector2(rx, ry + 4), Vector2(rx + 14, ry + 14), Vector2(rx, ry + 24)]), false, mc, 1.2, 0.5, 1.2)
			var sw := fmod(time * 240.0, PANEL_W)
			var sc := Palette.CYAN
			sc.a = 0.6 * a
			lines.seg(Vector2(PANEL_X + 30, ry + 36), Vector2(PANEL_X + 30 + sw, ry + 36), sc, 0.6, 0.3, 0.8)
			VectorFont.draw(lines, TITLE_DESCS[i], Vector2(PANEL_X + 32, ry + 42), 10, Palette.CYAN * Color(1, 1, 1, a), 0.5, 0.2)
		VectorFont.draw(lines, TITLE_ITEMS[i], Vector2(PANEL_X + 30, ry), 30, col, 1.0 if sel else 0.4, 0.4 if sel else 0.1, 0, 1.3, VectorFont.display)
	var hc := Palette.DIM
	hc.a = a
	VectorFont.draw(lines, "ARROWS   ENTER", Vector2(PANEL_X, 850), 11, hc, 0.3, 0.1)
	if beacon_note_t > 0.0:
		VectorFont.draw(lines, "BEACON +%s FLUX WHILE AWAY" % fmt(Save.offline_gain), Vector2(PANEL_X, 780), 11, Palette.GREEN, 0.6, 0.2)


# ------------------------------------------------------------------ bulwark seals
## The live trail becomes a seal: its soft cells turn SEAL_SOFT (a wall that can be cut without
## costing a life), the ship is free at once, and the seal keeps hardening on its own.
func detach_seal() -> void:
	var s := Seal.new()
	s.cells = trail.duplicate()
	s.harden = harden_len
	s.anchor_pt = center(anchor)
	for c in s.cells:
		if cells[idx(c.x, c.y)] == TRAIL:
			cells[idx(c.x, c.y)] = SEAL_SOFT
	seals.append(s)
	trail.clear()
	drawing = false
	fuse_on = false
	harden_len = 0.0
	draw_armed = false
	set_msg("SEAL %d" % seals.size(), 0.7)
	sparks.ripple(vis, 4.0, 220.0, 0.4, Palette.CYAN)


func seal_at(c: Vector2i) -> Seal:
	for sl in seals:
		if (sl as Seal).cells.has(c):
			return sl
	return null


func qix_hits_seal(q: QixBody) -> Seal:
	var e := qix_ends(q.c, q.theta, q.len)
	var n := int(maxf(2.0, q.len / 5.0))
	for k in range(n + 1):
		var c := to_cell(e[0].lerp(e[1], float(k) / n))
		if in_bounds(c) and cells[idx(c.x, c.y)] == SEAL_SOFT:
			return seal_at(c)
	return null


func update_seals(dt: float) -> void:
	var j := seals.size() - 1
	while j >= 0:
		var s: Seal = seals[j]
		s.harden = minf(s.harden + harden_rate() * dt, float(s.cells.size()))
		for i in int(floor(s.harden)):
			var hc := s.cells[i]
			if cells[idx(hc.x, hc.y)] == SEAL_SOFT:
				cells[idx(hc.x, hc.y)] = HARD
				if randf() < 0.5:
					sparks.emit(center(hc), Vector2(randf_range(-30, 30), randf_range(-30, 30)), 0.3, Palette.CYAN, 2.0)
		if s.harden >= float(s.cells.size()):
			seals.remove_at(j)
			finish_seal(s)
			if state != State.PLAYING:
				return
		j -= 1


## Fully hardened: claim exactly like a closed loop, without disturbing the live trail.
func finish_seal(s: Seal) -> void:
	claim_cells(s.cells, s.cells[0])


## Run the claim logic (flood from the Anomaly, node and hazard capture, awards) for a cell
## list that isn't the live trail, then put the live trail back.
func claim_cells(list: Array[Vector2i], anc: Vector2i) -> void:
	var live_trail := trail.duplicate()
	var live_drawing := drawing
	var live_anchor := anchor
	var live_h := harden_len
	var live_armed := draw_armed
	trail = list
	anchor = anc
	complete_claim()
	if state == State.PLAYING:
		trail = live_trail
		drawing = live_drawing
		anchor = live_anchor
		harden_len = live_h
		draw_armed = live_armed


# ------------------------------------------------------------------ tide (islander upgrade)
const TIDE_INTERVAL := 10.0


func tide_max_radius() -> int:
	return 1 + up("tide")


## Every TIDE_INTERVAL seconds an island grows one ring outward (trails and seals are never
## eaten), then the claim logic runs so swallowed nodes and hazards pay out and any pocket the
## island walls off is claimed.
func update_tide(dt: float) -> void:
	var rmax := tide_max_radius()
	for isl in islands:
		if int(isl.r) >= rmax:
			continue
		isl.t = float(isl.t) + dt
		if float(isl.t) < TIDE_INTERVAL:
			continue
		isl.t = 0.0
		isl.r = int(isl.r) + 1
		var r: int = isl.r
		var c: Vector2i = isl.c
		var gained := 0
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if in_bounds(q) and cells[idx(q.x, q.y)] == FREE:
					cells[idx(q.x, q.y)] = CLAIMED
					gained += 1
		free_count -= gained
		run_cells += gained
		for q in qixes:
			var qc := to_cell(q.c)
			if in_bounds(qc) and cells[idx(qc.x, qc.y)] == CLAIMED:
				var ci := qix_cell_index(q)
				if ci >= 0:
					q.c = center(Vector2i(ci % N, ci / N))
					q.v = (q.c - center(c)).normalized() * q.v.length()
		var cp := center(c)
		sparks.ripple(cp, (r + 0.5) * CELL, 120.0, 0.5, Palette.CYAN)
		lines.spike(1.0, 0.2)
		claim_cells([], c)
		if state != State.PLAYING:
			return


## Something cut the soft part: the hardened part stays as coast, the rest returns to the void.
func lose_seal(s: Seal) -> void:
	if s == null:
		return
	seals.erase(s)
	var hardened := 0
	for c in s.cells:
		var v := cells[idx(c.x, c.y)]
		if v == HARD:
			cells[idx(c.x, c.y)] = CLAIMED
			hardened += 1
		elif v == SEAL_SOFT:
			cells[idx(c.x, c.y)] = FREE
			if randf() < 0.3:
				sparks.emit(center(c), Vector2(randf_range(-60, 60), randf_range(-60, 60)), 0.4, Palette.ORANGE, 2.0)
	free_count -= hardened
	run_cells += hardened
	grid_changed()
	lines.spike(2.0, 0.3)
	set_msg("SEAL CUT", 0.9)


func draw_seals() -> void:
	for sl in seals:
		var s: Seal = sl
		var hn := int(floor(s.harden))
		var hard_pts := PackedVector2Array([s.anchor_pt])
		for i in mini(hn, s.cells.size()):
			hard_pts.append(center(s.cells[i]))
		lines.polyline(hard_pts, false, Palette.CYAN, 0.7, 0.2, 1.4)
		if hn < s.cells.size():
			var front := hard_pts[hard_pts.size() - 1]
			lines.circle(front, 4.0 + 1.5 * sin(time * 12.0), Palette.FULLBRIGHT, 6, 1.5, 0.6, 1.0)
			var soft_pts := PackedVector2Array([front])
			for i in range(hn, s.cells.size()):
				soft_pts.append(center(s.cells[i]))
			var sc := Palette.ORANGE
			sc.a = 0.75
			lines.polyline(soft_pts, false, sc, 1.6, 0.4, 1.1)


# ------------------------------------------------------------------ ship upgrade stats
func up(id: String) -> int:
	return Ships.up_level(ship.id, id)


func harden_rate() -> float:
	return HARDEN_RATE_BASE + up("temper")


func buoy_cap() -> int:
	return BUOY_CAP_BASE + up("rack")


func buoy_range() -> int:
	return BUOY_RANGE_BASE + 5 * up("arm")


func lance_cd_max() -> float:
	return maxf(1.5, LANCE_CD_BASE - up("cap"))


func lance_speed_mult() -> float:
	return LANCE_SPEED_BASE + 0.5 * up("rails")


## Disc growth in cells per second: the base radius over the base arming time, faster per Quick Fuse.
func sap_rate() -> float:
	return (SAP_RADIUS_BASE / SAP_ARM_BASE) * (1.0 + 0.25 * up("quick"))


func sap_radius() -> int:
	return SAP_RADIUS_BASE + up("payload")


## Is any part of the Anomaly inside the Sapper's growing disc?
func qix_in_disc(q: QixBody) -> bool:
	var sc := center(sap_cell)
	var r := sap_charge * CELL
	if q.c.distance_to(sc) < r:
		return true
	var e := qix_ends(q.c, q.theta, q.len)
	return e[0].distance_to(sc) < r or e[1].distance_to(sc) < r


## Something crossed the trail or the Sapper's disc. True if that kills: INSULATED absorbs the
## first hit of each charge.
func wire_hit() -> bool:
	if ship.id != "sapper":
		return true
	if not sap_live:
		return false
	if up("insul") > 0 and not sap_guard_used:
		sap_guard_used = true
		set_msg("INSULATED", 0.6)
		lines.spike(1.5, 0.3)
		sparks.burst(vis, 20, 140.0, 1.5, 0.4, Palette.CYAN)
		return false
	return true


# ------------------------------------------------------------------ lancer tether hits
## The first trail cell the Anomaly's segment crosses, or (-1,-1).
func qix_trail_cell(q: QixBody) -> Vector2i:
	var e := qix_ends(q.c, q.theta, q.len)
	var n := int(maxf(2.0, q.len / 5.0))
	for k in range(n + 1):
		var c := to_cell(e[0].lerp(e[1], float(k) / n))
		if in_bounds(c) and cells[idx(c.x, c.y)] == TRAIL:
			return c
	return Vector2i(-1, -1)


## Something touched a trail cell. Returns true if that kills the pilot. With LATTICE, a hit on
## the un-ridden tether ahead is absorbed once: that part drops away and the ride ends in place.
func tether_hit(c: Vector2i) -> bool:
	if wall_building:
		return wall_hit(c)
	if not (tether_active and lattice_ok):
		return true
	var i := trail.find(c)
	if i <= tether_i:
		return true
	lattice_ok = false
	for k in range(tether_i + 1, trail.size()):
		var rc := trail[k]
		cells[idx(rc.x, rc.y)] = FREE
	trail.resize(maxi(0, tether_i + 1))
	tether_active = false
	if trail.is_empty():
		drawing = false
		draw_armed = false
	sparks.burst(center(c), 30, 200.0, 1.5, 0.5, Palette.CYAN)
	lines.spike(2.0, 0.3)
	set_msg("TETHER CUT", 0.8)
	return false


# ------------------------------------------------------------------ galaxy structure & bosses
## Highest sector you may start at: up to the next unsecured one, capped at the boss; once the
## galaxy is cleared, LENGTH + 1 means the endless ladder.
func max_start(gid: String) -> int:
	if Galaxies.cleared(gid):
		return Galaxies.LENGTH + 1
	return mini(Galaxies.best(gid) + 1, Galaxies.LENGTH)


func spawn_boss() -> void:
	match String(gal.boss):
		"twin":
			# two Anomalies bound together; the second spawns beside the first
			if qixes.size() < 2:
				spawn_qix()
			boss_bond = true
		"bastion":
			# four core turrets around the centre, rotating and firing fast
			var mid := Vector2i(N / 2, N / 2)
			var offs := [Vector2i(-9, -9), Vector2i(9, -9), Vector2i(9, 9), Vector2i(-9, 9)]
			for i in 4:
				var t := Turret.new()
				t.cell = mid + offs[i]
				t.axis = Vector2i.RIGHT if (i % 2) == 0 else Vector2i.DOWN
				t.interval = 2.0
				t.fire_t = 1.0 + i * 0.5
				t.rotate = true
				t.rot_t = i * 1.0
				t.core = true
				turrets.append(t)
		"brood":
			var s := Spawner.new()
			s.cell = Vector2i(N / 2, N / 2)
			s.pos = center(s.cell)
			s.vel = Vector2.RIGHT.rotated(randf() * TAU) * 40.0
			s.mobile = true
			s.mother = true
			s.interval = 3.0
			s.max_alive = 6
			s.spawn_t = 2.0
			spawners.append(s)


# ------------------------------------------------------------------ galaxy palette
## The galaxy whose colours the field wears: the one being played, or the one selected in the dock.
func cur_gal() -> Dictionary:
	if state == State.DOCK or state == State.TITLE:
		return Galaxies.get_galaxy(Save.data.galaxy)
	return gal


func coast_color() -> Color:
	return cur_gal().coast


func fill_color() -> Color:
	var c: Color = cur_gal().fill
	c.a = 0.16
	return c


func draw_panel_header() -> void:
	if state == State.TITLE or state == State.DOCK:
		VectorFont.draw(lines, "GALAXTIX", Vector2(PANEL_X, 46), 30, Palette.WHITE, 0.9, 0.25, 0, 1.0, VectorFont.display)
		lines.seg(Vector2(PANEL_X, 88), Vector2(PANEL_X + PANEL_W, 88), Palette.DIM, 0.3, 0.1, 0.7)
	else:
		# in a run the field is centred: the wordmark heads the left column, a rule heads the right
		VectorFont.draw(lines, "GALAXTIX", Vector2(RUN_LX, 46), 24, Palette.WHITE, 0.9, 0.25, 0, 1.0, VectorFont.display)
		lines.seg(Vector2(RUN_LX, 88), Vector2(RUN_LX + RUN_COL_W, 88), Palette.DIM, 0.3, 0.1, 0.7)
		lines.seg(Vector2(RUN_RX, 88), Vector2(RUN_RX + RUN_COL_W, 88), Palette.DIM, 0.3, 0.1, 0.7)


# ------------------------------------------------------------------ sequences
## Launch intro: the field traces itself in, the sector title plots, the Anomaly warps in,
## the surveyor materializes. `full` adds the dock title bursting into sparks.
func begin_intro(full: bool) -> void:
	if full:
		# the ship in the bay bursts off the drawing board
		for pth in Hulls.paths(ship.id, BAY.position + Vector2(208, 190), 85.0, time * 0.7, 0.4):
			sparks.zap_polyline(pth, Palette.CYAN, 2200.0, 5.0)
		lines.spike(3.0, 0.4)
	start_level()
	msg_t = 0.0
	state = State.INTRO
	seq_t = 0.0
	intro_full = full
	intro_fx_done = 0
	surv_scale = 0.0


func seq_skip_pressed() -> bool:
	return Input.is_action_just_pressed("draw") or Input.is_action_just_pressed("confirm")


func update_intro(dt: float) -> void:
	seq_t += dt
	if seq_skip_pressed() and seq_t > 0.3:
		seq_t = INTRO_LEN
	if seq_t >= INTRO_QIX_T and intro_fx_done < 1:
		intro_fx_done = 1
		for q in qixes:
			sparks.ripple(q.c, 6.0, 380.0, 0.6, Palette.MAGENTA)
			sparks.burst(q.c, 50, 220.0, 1.5, 0.6, Palette.PURPLE)
		lines.spike(2.0, 0.3)
	if seq_t >= INTRO_SURV_T and intro_fx_done < 2:
		intro_fx_done = 2
		sparks.ripple(vis, 3.0, 260.0, 0.5, Palette.FULLBRIGHT)
	if seq_t >= INTRO_QIX_T:
		for q in qixes:
			update_qix(q, dt, qix_speed())
	surv_scale = clampf((seq_t - INTRO_SURV_T) / 0.3, 0.0, 1.0)
	if seq_t >= INTRO_LEN:
		state = State.PLAYING
		invuln = 2.0
		surv_scale = 1.0


## Sector report card after the fireworks: capture, secured bonus, perfect bonus, total.
func begin_report() -> void:
	state = State.REPORT
	seq_t = 0.0
	msg_t = 0.0
	sector_perfect = 0.0
	if sector_deaths == 0:
		sector_perfect = 1.0   # a flawless sector is worth one node
		Save.add_flux(sector_perfect)
		run_flux += sector_perfect


func update_report(dt: float) -> void:
	seq_t += dt
	for q in qixes:
		update_qix(q, dt, qix_speed())
	if seq_t > 3.6 or (seq_t > 1.4 and seq_skip_pressed()):
		if level == Galaxies.LENGTH and not endless:
			# the boss fell: the galaxy is cleared and the jump ends in victory
			run_victory = true
			end_run()
			return
		level += 1
		begin_transit(false)


## Run outro: the tube switches off (squash to a line, then a dot), then the jump report.
func update_outro(dt: float) -> void:
	seq_t += dt
	for q in qixes:
		update_qix(q, dt, qix_speed())
	if seq_t < OUTRO_COLLAPSE_T:
		lines.zoom = Vector2.ONE
	elif seq_t < OUTRO_CARD_T:
		var k := (seq_t - OUTRO_COLLAPSE_T) / (OUTRO_CARD_T - OUTRO_COLLAPSE_T)
		var k1 := minf(k / 0.6, 1.0)            # squash to a line
		var k2 := maxf(0.0, (k - 0.6) / 0.4)    # then shrink the line to a dot
		var sy := maxf(0.004, pow(1.0 - k1, 2.2))
		var sx := (1.0 + 0.2 * k1) * (1.0 - k2 * k2)
		lines.zoom = Vector2(maxf(sx, 0.01), sy)
		lines.spike(3.0 * (1.0 - k), 0.6)
	else:
		lines.zoom = Vector2.ONE
		if not outro_fx_done:
			outro_fx_done = true
			sparks.ripple(lines.zoom_center, 2.0, 500.0, 0.7, Palette.FULLBRIGHT)
			sparks.burst(lines.zoom_center, 40, 160.0, 2.0, 0.8, Palette.WHITE)
		if seq_t > OUTRO_CARD_T + 1.0:
			if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right"):
				result_selection = 1 - result_selection
			if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("launch"):
				activate_result(result_selection)
			elif Input.is_action_just_pressed("abort"):
				go_dock()
			elif autopilot and seq_t > OUTRO_CARD_T + 5.4:
				go_dock()


func result_button(index: int) -> Rect2:
	return Rect2(510 + index * 310, 660, 270, 56)


func activate_result(index: int) -> void:
	if index == 0:
		go_dock()
		dock_sel = 2
		switch_dock_tab()
	else:
		start_run(level)


func _input(event: InputEvent) -> void:
	if state == State.TITLE and title_t >= 1.0 and title_exit < 0 and not show_log:
		if event is InputEventMouseMotion or event is InputEventMouseButton:
			for i in TITLE_ITEMS.size():
				if Rect2(PANEL_X, 194 + i * 84, PANEL_W, 72).has_point(event.position):
					title_sel = i
					if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
						activate_title_item()
						get_viewport().set_input_as_handled()
					return

	if state != State.OUTRO or seq_t <= OUTRO_CARD_T + 1.0:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		for i in 2:
			if result_button(i).has_point(event.position):
				result_selection = i
				if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
					activate_result(i)
					get_viewport().set_input_as_handled()
				return


func typed(text: String, t0: float, cps := 40.0) -> String:
	var n := int(clampf((seq_t - t0) * cps, 0.0, float(text.length())))
	if n < text.length() and n > 0 and fmod(time, 0.3) < 0.15:
		return text.substr(0, n) + "_"
	return text.substr(0, n)


func countup(v: float, t0: float, dur := 0.6) -> float:
	return v * clampf((seq_t - t0) / dur, 0.0, 1.0)


func draw_intro() -> void:
	var fr := clampf((seq_t - 0.2) / 0.6, 0.0, 1.0)
	var field_rect := Rect2(FX, FY, N * CELL, N * CELL)
	var frame_path := PackedVector2Array([field_rect.position, Vector2(field_rect.end.x, field_rect.position.y),
		field_rect.end, Vector2(field_rect.position.x, field_rect.end.y), field_rect.position])
	lines.trace([frame_path], fr, Palette.DIM, 0.4, 0.1, 0.8)
	var coast_paths: Array = []
	for i in range(0, coast.size(), 2):
		coast_paths.append(PackedVector2Array([coast[i], coast[i + 1]]))
	lines.trace(coast_paths, fr, coast_color(), 0.7, 0.15, 1.0)

	var cx := FX + N * CELL * 0.5
	var cy := FY + N * CELL * 0.45
	var fade := 1.0 - clampf((seq_t - 2.3) / 0.3, 0.0, 1.0)
	if fade > 0.0:
		var tc := Palette.CYAN
		tc.a = fade
		var tf := clampf((seq_t - 0.7) / 0.6, 0.0, 1.0)
		lines.trace(VectorFont.paths("SECTOR %02d" % level, Vector2(cx, cy - 50), 44, 1, VectorFont.display), tf, tc, 1.2, 0.4, 1.3)
		var gc := Palette.WHITE
		gc.a = fade * 0.8
		var gline := String(gal.name)
		if level == Galaxies.LENGTH:
			gline += "   BOSS: " + String(gal.boss_name)
			gc = Palette.RED
			gc.a = fade
		elif level > Galaxies.LENGTH:
			gline += "   ENDLESS"
		VectorFont.draw(lines, typed(gline, 0.5, 30.0), Vector2(cx, cy - 82), 14, gc, 0.5, 0.2, 1)
		var sub := "%s   TARGET %d%%   HULL %d   %d FLUX NODES" % [ship.name, int(TARGET * 100), lives + 1, nodes.size()]
		if turrets.size() + spawners.size() > 0:
			sub += "   %d HAZARDS" % (turrets.size() + spawners.size())
		var sc := Palette.WHITE
		sc.a = fade
		VectorFont.draw(lines, typed(sub, 1.1), Vector2(cx, cy + 20), 14, sc, 0.5, 0.2, 1)
	if seq_t >= INTRO_QIX_T:
		for q in qixes:
			draw_qix(q)
	draw_play()


func draw_report_card() -> void:
	var cx := FX + N * CELL * 0.5
	var y := FY + N * CELL * 0.30
	lines.rect(Rect2(cx - 300, y - 30, 600, 310), Palette.DIM, 0.4, 0.1, 0.8)
	var tf := clampf(seq_t / 0.5, 0.0, 1.0)
	lines.trace(VectorFont.paths("SECTOR %02d SECURED" % level, Vector2(cx, y), 28, 1, VectorFont.display), tf, Palette.GREEN, 1.0, 0.3, 1.2)
	y += 62
	var rows := [
		["NODES %d/%d" % [sector_nodes_captured, nodes.size()], "+" + fmt(sector_capture), Palette.YELLOW],
		["SECURED BONUS", "+" + fmt(sector_bonus), Palette.CYAN],
		["PERFECT", ("+" + fmt(sector_perfect)) if sector_perfect > 0.0 else "--", Palette.YELLOW if sector_perfect > 0.0 else Palette.DIM],
		["ISOTOPE", ("+%d" % sector_isotope) if sector_isotope > 0 else "--", Palette.CYAN if sector_isotope > 0 else Palette.DIM],
	]
	for i in rows.size():
		var t0 := 0.5 + i * 0.35
		VectorFont.draw(lines, typed(rows[i][0], t0), Vector2(cx - 260, y), 15, Palette.WHITE, 0.4, 0.15)
		VectorFont.draw(lines, typed(rows[i][1], t0 + 0.25), Vector2(cx + 260, y), 15, rows[i][2], 0.4, 0.15, 2)
		y += 38
	var t_total := 0.5 + rows.size() * 0.35 + 0.2
	if seq_t > t_total:
		lines.seg(Vector2(cx - 260, y - 8), Vector2(cx + 260, y - 8), Palette.DIM, 0.3, 0.1, 0.7)
		VectorFont.draw(lines, "TOTAL", Vector2(cx - 260, y + 4), 18, Palette.WHITE, 0.5, 0.2)
		VectorFont.draw(lines, "+" + fmt(countup(sector_capture + sector_bonus + sector_perfect, t_total)), Vector2(cx + 260, y + 4), 18, Palette.GREEN, 0.6, 0.25, 2)


func draw_outro_card() -> void:
	var cx := 800.0
	var t := seq_t - OUTRO_CARD_T
	var title := "GALAXY SECURED" if run_victory else "SIGNAL LOST"
	lines.trace(VectorFont.paths(title, Vector2(cx, 230), 34, 1, VectorFont.display), clampf(t / 0.5, 0.0, 1.0), Palette.GREEN if run_victory else Palette.RED, 1.2, 0.4, 1.3)
	var rows := [["SECTORS CLEARED", str(run_sectors)], ["BEST CAPTURE", "%d%%" % int(run_best_claim * 100.0)]]
	for i in rows.size():
		VectorFont.draw(lines, rows[i][0], Vector2(510, 320 + i * 44), 15, Palette.WHITE)
		VectorFont.draw(lines, rows[i][1], Vector2(1090, 320 + i * 44), 15, Palette.CYAN, 0.4, 0.15, 2)
	lines.seg(Vector2(510, 418), Vector2(1090, 418), Palette.DIM)
	VectorFont.draw(lines, "EARNED", Vector2(510, 456), 15, Palette.WHITE)
	draw_dock_currency(Vector2(820, 463), "+" + fmt(run_flux), false)
	draw_dock_currency(Vector2(980, 463), "+%d" % run_isotope, true)
	VectorFont.draw(lines, "BALANCE", Vector2(510, 508), 15, Palette.WHITE)
	draw_dock_currency(Vector2(820, 515), fmt(Save.data.flux), false)
	draw_dock_currency(Vector2(980, 515), str(int(Save.data.isotope)), true)
	if run_victory:
		VectorFont.draw(lines, "+1 STAR CHART", Vector2(cx, 578), 15, Palette.YELLOW, 0.5, 0.2, 1)
	if t > 1.0:
		for i in 2:
			var rect := result_button(i)
			var col := Palette.CYAN if result_selection == i else Palette.DIM
			lines.rect(rect, col, 0.5, 0.2, 1.2)
			VectorFont.draw(lines, "UPGRADES" if i == 0 else "RESTART", rect.get_center() - Vector2(0, 8), 16, col, 0.5, 0.2, 1)
		VectorFont.draw(lines, "LEFT/RIGHT CHOOSE   ENTER SELECT   ESC DOCK", Vector2(cx, 746), 11, Palette.DIM, 0.4, 0.1, 1)


# ------------------------------------------------------------------ transit (dock -> sector)
## The launch: the hull leaves the drawing board and crosses a streaking starfield toward the
## target galaxy's constellation, which swells as it nears. A warp squash hands over to the intro.
func begin_transit(from_dock: bool) -> void:
	if transit_skip:
		begin_intro(from_dock)
		return
	transit_len = TRANSIT_LEN if from_dock else TRANSIT_SHORT
	if from_dock:
		for pth in Hulls.paths(ship.id, BAY.position + Vector2(208, 190), 85.0, time * 0.7, 0.4):
			sparks.zap_polyline(pth, Palette.CYAN, 2200.0, 5.0)
		lines.spike(3.0, 0.4)
	lines.zoom = Vector2.ONE
	state = State.TRANSIT
	seq_t = 0.0
	msg_t = 0.0
	surv_scale = 0.0
	transit_stars.clear()
	for k in 110:
		transit_stars.append({"p": Vector2(randf() * 1600.0, randf() * 900.0), "d": 0.25 + randf() * 0.75})


func transit_speed() -> float:
	return 140.0 + 1100.0 * pow(clampf(seq_t / transit_len, 0.0, 1.0), 2.4)


func transit_hull_pos() -> Vector2:
	var k := clampf(seq_t / (transit_len - 0.4), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	return Vector2(lerpf(360.0, 1040.0, e), 450.0 + 6.0 * sin(time * 2.3))


func update_transit(dt: float) -> void:
	seq_t += dt
	var warp_t := transit_len - 0.4
	if seq_skip_pressed() and seq_t > 0.3 and seq_t < warp_t:
		seq_t = warp_t
	var v := transit_speed()
	for st in transit_stars:
		var pos: Vector2 = st.p
		pos.x -= v * float(st.d) * dt
		if pos.x < -60.0:
			pos = Vector2(1660.0, randf() * 900.0)
		st.p = pos
	# thrust: sparks shed off the stern, carried backwards by the stream
	var hp := transit_hull_pos()
	if randf() < dt * 90.0:
		sparks.emit(hp + Vector2(-40.0, randf_range(-8.0, 8.0)), Vector2(-v * 0.5 - 80.0, randf_range(-20.0, 20.0)),
			0.35, Palette.ORANGE, 0.9)
	if seq_t >= warp_t:
		var k := (seq_t - warp_t) / 0.4
		lines.zoom = Vector2(1.0 + 5.0 * k * k, maxf(0.004, 1.0 - k * k))
		lines.spike(2.5 * k, 0.5)
	if seq_t >= transit_len:
		lines.zoom = Vector2.ONE
		sparks.ripple(lines.zoom_center, 2.0, 600.0, 0.6, Palette.FULLBRIGHT)
		sparks.burst(lines.zoom_center, 50, 220.0, 2.0, 0.7, Palette.WHITE)
		begin_intro(false)


## A galaxy's constellation: a seeded 7-point loop (the star chart's glyph) at any scale.
func constellation(g: Dictionary, c: Vector2, scale: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(g.id))
	var pts := PackedVector2Array()
	for k in 7:
		var a := k * TAU / 7.0 + rng.randf_range(-0.3, 0.3)
		var rad := rng.randf_range(28.0, 62.0)
		pts.append(c + Vector2(cos(a), sin(a)) * rad * scale)
	return pts


func draw_transit() -> void:
	var v := transit_speed()
	var k := clampf(seq_t / transit_len, 0.0, 1.0)
	# starfield streaks: length grows with speed, depth sets brightness
	for st in transit_stars:
		var pos: Vector2 = st.p
		var d: float = st.d
		var len := 2.0 + v * d * 0.035
		var sc := Palette.WHITE
		sc.a = 0.25 + 0.6 * d
		lines.seg(pos, pos + Vector2(len, 0.0), sc, 0.2, 0.05, 0.6 + 0.6 * d)
	# destination: the target constellation swelling up ahead, in its galaxy colour
	var tc := Vector2(1290.0, 450.0)
	var gs := 0.4 + 2.2 * k * k
	var pts := constellation(gal, tc, gs)
	var gc: Color = gal.coast
	gc.a = 0.5 + 0.5 * k
	lines.polyline(pts, true, gc, 0.6, 0.25, 1.0)
	lines.seg(pts[0], pts[3], gc, 0.6, 0.25, 0.7)
	lines.seg(pts[2], pts[5], gc, 0.6, 0.25, 0.7)
	for pt in pts:
		lines.seg(pt, pt, Palette.FULLBRIGHT, 1.0, 0.5, 1.6)
	# the sector marker on the ring, pulsing, where the run begins
	var a := -PI * 0.5 + ((level - 1) % 8) * TAU / 8.0
	var spos := tc + Vector2(cos(a), sin(a)) * 98.0 * gs
	var mc := Palette.YELLOW
	mc.a = 0.5 + 0.5 * sin(time * 6.0)
	lines.rect(Rect2(spos - Vector2(6, 6) * gs, Vector2(12, 12) * gs), mc, 0.5, 0.2, 0.9)
	# the hull crossing the frame
	var hp := transit_hull_pos()
	for pth in Hulls.paths(ship.id, hp, 95.0, time * 0.9, 0.35):
		lines.polyline(pth, false, Palette.CYAN, 0.7, 0.3, 1.1)
	# the copy: destination typed out, distance closing at the foot
	var cx := 800.0
	VectorFont.draw(lines, "JUMP", Vector2(cx, 120), 40, Palette.WHITE, 0.5, 0.2, 1, 1.4, VectorFont.display)
	var dest := "%s   SECTOR %02d" % [gal.name, level]
	if level > Galaxies.LENGTH:
		dest = "%s   ENDLESS %02d" % [gal.name, level]
	VectorFont.draw(lines, typed(dest, 0.4, 30.0), Vector2(cx, 172), 15, gal.coast, 0.4, 0.15, 1)
	VectorFont.draw(lines, typed(ship.name, 1.0), Vector2(cx, 198), 12, Palette.CYAN, 0.4, 0.15, 1)
	var bx := cx - 300.0
	var by := 790.0
	lines.rect(Rect2(bx, by, 600.0, 10.0), Palette.DIM, 0.3, 0.1, 0.7)
	if k > 0.0:
		lines.rect(Rect2(bx + 2.0, by + 2.0, 596.0 * k, 6.0), gal.coast, 0.3, 0.1, 0.9)
	VectorFont.draw(lines, "DISTANCE", Vector2(bx, by - 12), 10, Palette.WHITE, 0.4, 0.1, 0)
	VectorFont.draw(lines, "%d%%" % int(k * 100.0), Vector2(bx + 600.0, by - 12), 10, Palette.WHITE, 0.4, 0.1, 2)
	VectorFont.draw(lines, "SPACE  SKIP", Vector2(cx, 850), 9, Palette.DIM, 0.4, 0.1, 1)


# ------------------------------------------------------------------ leaper
## Cells per second the line builds at; Stride speeds it up.
func leap_rate() -> float:
	return LEAP_RATE_BASE * (1.0 + 0.25 * up("stride"))


func leap_max() -> int:
	return BUOY_RANGE_BASE + 5 * up("arm")


## Island half-size: 1 = 3x3, 2 = 5x5 with the Landing Pad.
func pad_r() -> int:
	return 1


## Free cells ahead of `from` in `dir` before land, a line, or the edge.
func ray_len(from: Vector2i, dir: Vector2i) -> int:
	var n := 0
	var c := from + dir
	while in_bounds(c) and cells[idx(c.x, c.y)] == FREE:
		n += 1
		c += dir
	return n


## Where a leap in `dir` would start: the last cell of the ship's own land in that direction.
func leap_start(dir: Vector2i) -> Vector2i:
	var cur := p
	var guard := 0
	while guard < N and in_bounds(cur + dir) and cells[idx(cur.x + dir.x, cur.y + dir.y)] == CLAIMED:
		cur += dir
		guard += 1
	return cur


## Start aiming: nothing is built yet, so nothing can be cut. Arrows turn the aim while held.
## Only from the coast, and from the cell the ship stands on: no leaping out of the interior.
func start_leap() -> void:
	if border[idx(p.x, p.y)] == 0:
		set_msg("COAST ONLY", 0.5)
		lines.spike(1.0, 0.2)
		return
	var dir := last_dir
	if dir == Vector2i.ZERO or ray_len(p, dir) < 1:
		dir = Vector2i.ZERO
		for d in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
			if ray_len(p, d) >= 1:
				dir = d
				break
	if dir == Vector2i.ZERO:
		set_msg("NO ROOM", 0.5)
		lines.spike(1.0, 0.2)
		return
	anchor = p
	leap_dir = dir
	leap_len = 0.0
	leap_building = true
	sparks.ripple(center(anchor), 3.0, 160.0, 0.4, Palette.YELLOW)


func leap_aim(dt: float, aim: Vector2i) -> void:
	if aim != Vector2i.ZERO and aim != leap_dir and ray_len(p, aim) >= 1:
		leap_dir = aim
		last_dir = aim
	leap_len = minf(leap_len + leap_rate() * dt, float(mini(leap_max(), ray_len(anchor, leap_dir))))


## Held all the way: the aim has touched the far coast, so the ship leaps to the end of it.
func leap_reached_coast() -> bool:
	var reach := ray_len(anchor, leap_dir)
	return reach >= 1 and reach <= leap_max() and leap_len >= float(reach)


## The landing cell for the current aim.
func leap_target() -> Vector2i:
	return anchor + leap_dir * maxi(1, int(floor(leap_len)))


## The leap: the ship dashes to the tip of the aim and a wall splits from there along the leap
## axis, ahead and back, until each end meets land. The tip is the first cell of the wall; the
## ship stands on it. Held to the far coast, the ahead side lands at once and hardens.
func finish_leap(_on_land: bool) -> void:
	leap_building = false
	if leap_len < 1.0:
		set_msg("FIZZLE", 0.5)
		return
	var landing := leap_target()
	if not in_bounds(landing) or cells[idx(landing.x, landing.y)] != FREE:
		set_msg("BLOCKED", 0.5)
		return
	var from := vis
	leap_tip = landing
	p = landing
	sparks.zap_polyline(PackedVector2Array([from, center(landing)]), Palette.YELLOW, 2600.0, 5.0)
	sparks.burst(center(landing), 40, 220.0, 1.5, 0.5, Palette.CYAN)
	lines.spike(2.0, 0.3)
	shake = maxf(shake, 0.25)
	cells[idx(leap_tip.x, leap_tip.y)] = TRAIL
	trail.clear()
	trail.append(leap_tip)
	trail_slow = false
	drawing = true
	fuse_on = false
	wall_dirs = [leap_dir, -leap_dir]
	wall_ends = [leap_tip, leap_tip]
	wall_done = [false, false]
	wall_cells = [[], []]
	wall_building = true
	leap_acc = 0.0
	set_msg("LEAP", 0.5)


## JezzBall rules. The wall grows one cell per side per step. The first side to meet land, the
## edge or a line hardens on the spot and is safe from then on. The other side keeps running;
## when it lands too, the flood fill decides the split. A hit on the running side after the first
## has hardened just drops that side, no harm done. A hit while both are still running hurts.
func wall_grow(dt: float) -> void:
	leap_acc += leap_rate() * 2.0 * dt   # the wall runs twice as fast as the aim
	while leap_acc >= 1.0 and wall_building:
		leap_acc -= 1.0
		for s in 2:
			if wall_done[s]:
				continue
			var nxt: Vector2i = wall_ends[s] + wall_dirs[s]
			if not in_bounds(nxt) or cells[idx(nxt.x, nxt.y)] != FREE:
				wall_done[s] = true
				sparks.burst(center(wall_ends[s]), 16, 140.0, 1.5, 0.4, Palette.CYAN)
				if wall_done[1 - s]:
					# the closing side: the flood fill takes it from here
					wall_building = false
					set_msg("WALL UP", 0.6)
					complete_claim()
					return
				wall_harden(s)
				continue
			cells[idx(nxt.x, nxt.y)] = TRAIL
			trail.append(nxt)
			wall_cells[s].append(nxt)
			wall_ends[s] = nxt
			if randf() < 0.6:
				sparks.emit(center(nxt), Vector2(randf_range(-40, 40), randf_range(-40, 40)), 0.3, Palette.YELLOW, 2.0)


## The first side to land becomes coast at once: a bridge from the island to whatever it reached.
func wall_harden(s: int) -> void:
	var n := 0
	for c in wall_cells[s] + [leap_tip]:
		var rc: Vector2i = c
		if cells[idx(rc.x, rc.y)] == TRAIL:
			cells[idx(rc.x, rc.y)] = CLAIMED
			n += 1
		trail.erase(rc)
	wall_cells[s] = []
	if n > 0:
		free_count -= n
		run_cells += n
		grid_changed()
	set_msg("SIDE HARDENED", 0.5)
	lines.spike(1.2, 0.2)


## Something touched the wall while it was building. Both sides still running: that hurts.
## One side already hardened: the running side just stops and drops away.
func wall_hit(c: Vector2i) -> bool:
	var s := -1
	for k in 2:
		if wall_cells[k].has(c) or (c == leap_tip and not wall_done[k]):
			s = k
	if s < 0 or not (wall_done[0] or wall_done[1]):
		return true
	for cc in wall_cells[s]:
		var rc: Vector2i = cc
		if cells[idx(rc.x, rc.y)] == TRAIL:
			cells[idx(rc.x, rc.y)] = FREE
	wall_cells = [[], []]
	trail.clear()
	wall_building = false
	drawing = false
	draw_armed = false
	sparks.burst(center(c), 30, 200.0, 1.5, 0.5, Palette.YELLOW)
	lines.spike(2.0, 0.3)
	set_msg("WALL CUT", 0.6)
	return false


## Is the ship hittable by things that only hurt a ship off the coast? Drawing, or a Sapper out
## in the void with no line.
func exposed() -> bool:
	return drawing or (ship.id == "sapper" and cells[idx(p.x, p.y)] == FREE)


func qix_near(q: QixBody, pt: Vector2, r: float) -> bool:
	var e := qix_ends(q.c, q.theta, q.len)
	return Geometry2D.get_closest_point_to_segment(pt, e[0], e[1]).distance_to(pt) < r


# ------------------------------------------------------------------ dock
const CHART := Rect2(200, 205, 1200, 440)
const SCAN := Rect2(600, 190, 400, 516)
const BAY := Rect2(592, 205, 416, 400)
const DOCK_FIXED_ROWS := 3



func dock_rows() -> int:
	return DOCK_FIXED_ROWS + Save.UPGRADES.size() + Ships.upgrades(Save.data.ship).size() + 1


## Dock upgrade row index -> ["general", def] or ["ship", def]
func dock_upgrade_at(row: int) -> Array:
	var ui := row - DOCK_FIXED_ROWS
	if ui < 0:
		return []
	if ui < Save.UPGRADES.size():
		return ["general", Save.UPGRADES[ui]]
	ui -= Save.UPGRADES.size()
	var ups := Ships.upgrades(Save.data.ship)
	if ui < ups.size():
		return ["ship", ups[ui]]
	return []


func dock_navigation_rows() -> Array:
	if dock_tab == 0:
		return [0, 1, 2]
	return range(DOCK_FIXED_ROWS, dock_rows() - 1)


func switch_dock_tab() -> void:
	if dock_tab == 0 and dock_sel != 2:
		return
	if dock_tab == 0:
		dock_loadout_sel = dock_sel
		dock_tab = 1
		dock_sel = clampi(dock_saved_upgrade, DOCK_FIXED_ROWS, dock_rows() - 2)
	else:
		dock_saved_upgrade = dock_sel
		dock_tab = 0
		dock_sel = clampi(dock_loadout_sel, 0, 2)
	pane_t = 0.0


func update_dock() -> void:
	if Input.is_action_just_pressed("tab"):
		switch_dock_tab()
		return
	if Input.is_action_just_pressed("abort"):
		if dock_tab == 1:
			switch_dock_tab()
		elif dock_sel > 0:
			dock_sel -= 1
			pane_t = 0.0
		else:
			go_title()
		return
	if dock_tab == 0:
		update_dock_step()
		return
	var choices := dock_navigation_rows()
	var index := maxi(0, choices.find(dock_sel))
	if Input.is_action_just_pressed("move_up"):
		index = (index - 1 + choices.size()) % choices.size()
	if Input.is_action_just_pressed("move_down"):
		index = (index + 1) % choices.size()
	dock_sel = choices[index]
	if Input.is_action_just_pressed("confirm"):
		var entry := dock_upgrade_at(dock_sel)
		var burst_at := Vector2(1050, 285 + (dock_sel - DOCK_FIXED_ROWS - dock_upgrade_scroll) * 48)
		if entry[0] == "general":
			var id: String = entry[1].id
			if Save.buy(id):
				set_msg("%s LV %d" % [Save.def(id).name, Save.level(id)], 1.2)
				lines.spike(2.0, 0.3)
				sparks.burst(burst_at, 40, 160.0, 1.5, 0.5, Palette.GREEN)
			else:
				if Save.maxed(id):
					set_msg("MAXED", 1.0)
				else:
					set_currency_ask(Save.cost(id), false)
				lines.spike(1.0, 0.2)
		else:
			var sid: String = Save.data.ship
			var uid: String = entry[1].id
			if Ships.buy_up(sid, uid):
				set_msg("%s LV %d" % [entry[1].name, Ships.up_level(sid, uid)], 1.2)
				lines.spike(2.0, 0.3)
				sparks.burst(burst_at, 40, 160.0, 1.5, 0.5, Palette.CYAN)
			elif not Ships.owned(sid):
				set_msg("COMMISSION THE SHIP FIRST", 1.0)
			else:
				if Ships.up_maxed(sid, uid):
					set_msg("MAXED", 1.0)
				else:
					set_currency_ask(Ships.up_cost(sid, uid), false)
				lines.spike(1.0, 0.2)


## One decision per step. Buying a locked ship requires a separate press from launch.
func update_dock_step() -> void:
	dock_sel = clampi(dock_sel, 0, 2)
	var lr := 0
	if Input.is_action_just_pressed("move_left"):
		lr = -1
	elif Input.is_action_just_pressed("move_right"):
		lr = 1
	if lr != 0:
		match dock_sel:
			0: dock_galaxy_step(lr)
			1: dock_sector_step(lr)
			2: dock_ship_step(lr)
	var confirm := Input.is_action_just_pressed("confirm")
	var launch := Input.is_action_just_pressed("launch") and dock_sel == 2
	if not confirm and not launch:
		return
	if not Galaxies.unlocked(Save.data.galaxy):
		set_msg(Galaxies.unlock_hint(Save.data.galaxy), 1.6)
		return
	if dock_sel < 2:
		dock_sel += 1
		pane_t = 0.0
	elif not Ships.owned(Save.data.ship):
		if confirm:
			dock_ship_confirm()
		else:
			set_msg("UNLOCK SHIP FIRST", 1.2)
	else:
		start_run()


func draw_dock_field() -> void:
	if dock_tab == 1 or dock_sel == 2:
		draw_bay(Rect2(180, 220, 416, 400))
	elif dock_sel == 1:
		draw_scan()
	else:
		draw_chart()


func dock_progress_hint() -> String:
	var g := Galaxies.get_galaxy(Save.data.galaxy)
	if not Galaxies.unlocked(g.id):
		return Galaxies.unlock_hint(g.id)
	var i := Galaxies.index_of(g.id)
	if i + 1 < Galaxies.LIST.size() and Galaxies.best(g.id) < Galaxies.UNLOCK_AT:
		if i == 0:
			return ""
		return "SECTOR %02d UNLOCKS %s" % [Galaxies.UNLOCK_AT, Galaxies.LIST[i + 1].name]
	if not Galaxies.cleared(g.id):
		return "SECTOR %02d: %s" % [Galaxies.LENGTH, g.boss_name]
	return "GALAXY CLEARED / ENDLESS OPEN"


func draw_chart() -> void:
	var dimf := 1.0
	var sel_id: String = Save.data.galaxy
	var cy := CHART.position.y + 180.0
	for i in Galaxies.LIST.size():
		var g: Dictionary = Galaxies.LIST[i]
		var cx := CHART.position.x + 200.0 + i * 400.0
		var selected: bool = g.id == sel_id
		var unlocked := Galaxies.unlocked(g.id)
		var pts := constellation(g, Vector2(cx, cy), 1.0)
		var col: Color = g.coast if selected else (Palette.WHITE if unlocked else Palette.DIM)
		col.a = (1.0 if selected else 0.55) * dimf
		if not unlocked:
			col.a *= 0.5
		lines.polyline(pts, true, col, 0.8, 0.3, 1.0 if selected else 0.8)
		lines.seg(pts[0], pts[3], col, 0.8, 0.3, 0.7)
		lines.seg(pts[2], pts[5], col, 0.8, 0.3, 0.7)
		for pt in pts:
			lines.seg(pt, pt, Palette.FULLBRIGHT if selected else col, 1.0, 0.5, 1.5)
		var nc := Palette.WHITE if unlocked else Palette.RED
		nc.a = dimf
		VectorFont.draw(lines, g.name, Vector2(cx, cy + 120), 18, nc, 0.4, 0.15, 1)
		if not unlocked:
			VectorFont.draw(lines, "LOCKED", Vector2(cx, cy + 148), 12, Palette.RED, 0.4, 0.1, 1)
		elif Galaxies.cleared(g.id):
			var eb := Galaxies.endless_best(g.id)
			VectorFont.draw(lines, "CLEARED" + (("   ENDLESS %02d" % eb) if eb > 0 else ""), Vector2(cx, cy + 148), 12, Palette.GREEN, 0.4, 0.1, 1)
		elif unlocked:
			VectorFont.draw(lines, "%d / %d SECURED" % [mini(Galaxies.best(g.id), Galaxies.LENGTH), Galaxies.LENGTH], Vector2(cx, cy + 148), 12, Palette.GREEN, 0.0, 0.0, 1)
		if selected:
			# reticle and the sector ring: secured sectors green, the next one pulsing
			var ra := time * 0.4
			var rr := 78.0
			var sq := PackedVector2Array()
			for k in 4:
				var a := ra + k * TAU / 4.0
				sq.append(Vector2(cx, cy) + Vector2(cos(a), sin(a)) * rr)
			if dock_sel != 1:
				lines.polyline(sq, true, Palette.CYAN, 0.6, 0.2, 0.7)
			if unlocked:
				var best := Galaxies.best(g.id)
				var ss := clampi(int(Save.data.start_sector), 1, max_start(g.id))
				for s in range(1, 9):
					var a := -PI * 0.5 + (s - 1) * TAU / 8.0
					var pp := Vector2(cx, cy) + Vector2(cos(a), sin(a)) * 98.0
					var sc := Palette.DIM
					if s <= best:
						sc = Palette.GREEN
					elif s == best + 1:
						sc = Palette.YELLOW
						sc.a = 0.5 + 0.5 * sin(time * 6.0)
					lines.rect(Rect2(pp - Vector2(5, 5), Vector2(10, 10)), sc, 0.5, 0.2, 0.8)
					if s <= best:
						lines.seg(pp - Vector2(3, 3), pp + Vector2(3, 3), sc, 0.5, 0.2, 0.7)
					if s == ss:
						lines.circle(pp, 9.0, Palette.FULLBRIGHT, 8, 0.8, 0.3, 0.8)
						VectorFont.draw(lines, "%02d" % s, pp - Vector2(0, 24), 10, Palette.WHITE, 0.0, 0.0, 1)
				var sector_label := "ENDLESS" if ss > Galaxies.LENGTH else "SECTOR %02d" % ss
				if ss == Galaxies.LENGTH:
					sector_label += " / " + String(g.boss_name)
				VectorFont.draw(lines, "< " + sector_label + " >" if dock_sel == 1 else sector_label,
					Vector2(cx, cy + 184), 13, Palette.YELLOW if dock_sel == 1 else Palette.CYAN, 0.0, 0.0, 1)
				if ss > Galaxies.LENGTH:
					lines.circle(Vector2(cx, cy), 110, Palette.CYAN, 32, 0.0, 0.0, 0.7)
		if i < Galaxies.LIST.size() - 1:
			var rc := Palette.DIM
			rc.a = dimf
			dashed(Vector2(cx + 120, cy), Vector2(cx + 400 - 120, cy), rc)

	VectorFont.draw(lines, dock_progress_hint(), Vector2(800, CHART.end.y - 36), 15, Palette.YELLOW, 0.0, 0.0, 1)

func draw_scan(rect: Rect2 = SCAN, compact := false) -> void:
	var focus := dock_sel == 1
	var g := Galaxies.get_galaxy(Save.data.galaxy)
	var ss := clampi(int(Save.data.start_sector), 1, max_start(g.id))
	var scan_title := "SECTOR %02d SCAN" % ss
	if ss == Galaxies.LENGTH:
		scan_title = "BOSS SCAN: " + String(g.boss_name)
	elif ss > Galaxies.LENGTH:
		scan_title = "ENDLESS SCAN"
	if not compact:
		VectorFont.draw(lines, scan_title, Vector2(rect.get_center().x, rect.position.y), 14, Palette.CYAN, 0.0, 0.0, 1)
	if scan_layout.is_empty():
		return
	var dimf := 1.0 if focus else 0.6
	var s := (rect.size.x - 12.0 if compact else rect.size.x - 28.0) / N
	var o := rect.position + (Vector2(6, 6) if compact else Vector2(14, 34))
	var r := 1 + Save.rim()
	var frac := clampf(pane_t / 0.6, 0.0, 1.0)
	var paths: Array = []
	# rim and field edge
	var rim := Rect2(o + Vector2(r, r) * s, Vector2(N - 2 * r, N - 2 * r) * s)
	paths.append(PackedVector2Array([rim.position, Vector2(rim.end.x, rim.position.y), rim.end, Vector2(rim.position.x, rim.end.y), rim.position]))
	for sh in scan_layout.shape:
		var sr: Rect2i = sh
		rock_shape(o + Vector2(sr.position) * s, o + Vector2(sr.end) * s, frac * dimf)
	var rc: Color = g.coast
	rc.a = dimf
	if scan_layout.arena.is_empty():
		lines.trace(paths, frac, rc, 0.4, 0.1, 0.8)
	else:
		var outline: PackedVector2Array = scan_layout.arena.outline
		for i in range(0, int(outline.size() * frac) / 2 * 2, 2):
			lines.seg(o + outline[i] * s, o + outline[i + 1] * s, rc, 0.4, 0.1, 0.8)
	var oc := Palette.DIM
	oc.a = 0.5 * dimf
	lines.rect(Rect2(o, Vector2(N, N) * s), oc, 0.3, 0.1, 0.6)
	# markers appear once the rim has traced
	if frac >= 1.0:
		var k := clampf((pane_t - 0.6) / 0.4, 0.0, 1.0)
		for nd in scan_layout.nodes:
			var pp: Vector2 = o + (Vector2(nd.cell) + Vector2(0.5, 0.5)) * s
			var col := Palette.CYAN if nd.rare else Palette.YELLOW
			col.a = k * dimf
			lines.circle(pp, 5.0, col, 6, 0.6, 0.3, 1.0)
			lines.seg(pp, pp, col, 0.6, 0.3, 1.2)
		for td in scan_layout.turrets:
			var pp: Vector2 = o + (Vector2(td.cell) + Vector2(0.5, 0.5)) * s
			var col := Palette.ORANGE
			col.a = k * dimf
			lines.rect(Rect2(pp - Vector2(4, 4), Vector2(8, 8)), col, 0.6, 0.3, 0.9)
			var ax := Vector2(td.axis) * 9.0
			lines.seg(pp - ax, pp + ax, Palette.RED * Color(1, 1, 1, k * dimf), 0.6, 0.3, 0.8)
		for sd in scan_layout.spawners:
			var pp: Vector2 = o + (Vector2(sd.cell) + Vector2(0.5, 0.5)) * s
			var col := Palette.PURPLE
			col.a = k * dimf
			lines.circle(pp, 6.0, col, 6, 0.6, 0.3, 0.9)
		var sp := o + (Vector2(scan_layout.start) + Vector2(0.5, 0.5)) * s
		var pc := Palette.FULLBRIGHT
		pc.a = k * dimf
		lines.polyline(PackedVector2Array([sp + Vector2(0, -5), sp + Vector2(5, 0), sp + Vector2(0, 5), sp + Vector2(-5, 0)]), true, pc, 0.6, 0.3, 1.0)
	if compact:
		return
	# legend
	var ly := rect.end.y - 60
	var lc := Palette.WHITE
	lc.a = dimf
	var haz: int = scan_layout.turrets.size() + scan_layout.spawners.size()
	VectorFont.draw(lines, "%d NODES   %d HAZARDS" % [scan_layout.nodes.size(), haz], Vector2(o.x, ly), 11, lc, 0.4, 0.15)
	var dc := Palette.DIM
	dc.a = dimf
	var qs := int(70.0 * pow(1.10, ss - 1) * float(g.qix_mult) * SectorArena.enemy_mult(g.id, ss))
	VectorFont.draw(lines, "ANOMALY %d   %d SPARX   TARGET %d%%" % [qs, 1 + ss / 2, int(TARGET * 100)], Vector2(o.x, ly + 20), 10, dc, 0.4, 0.1)


func draw_bay(rect: Rect2 = BAY) -> void:
	var focus := dock_sel >= 2 and dock_sel < dock_rows() - 1
	var dimf := 1.0 if focus else 0.6
	var sh := Ships.get_ship(Save.data.ship)
	var owned := Ships.owned(sh.id)
	var center := rect.position + Vector2(208, 190)
	var frac := clampf(pane_t / 0.7, 0.0, 1.0)
	var hc := Palette.CYAN if owned else Palette.DIM
	hc.a = dimf
	lines.trace(Hulls.paths(sh.id, center, 85.0, time * 0.7, 0.4), frac, hc, 0.8, 0.3, 1.1)
	# drawing-board grid under the hull
	var gc := Palette.DIM
	gc.a = 0.35 * dimf
	for k in 5:
		var yy := center.y + 120 + k * 8
		lines.seg(Vector2(center.x - 120 + k * 12, yy), Vector2(center.x + 120 - k * 12, yy), gc, 0.3, 0.1, 0.6)
	var nc := Palette.WHITE
	nc.a = dimf
	VectorFont.draw(lines, sh.name, Vector2(center.x, rect.position.y + 30), 22, nc, 0.6, 0.2, 1, 1.2, VectorFont.display)
	if owned:
		VectorFont.draw(lines, "READY", Vector2(center.x, rect.position.y + 80), 10, Palette.GREEN, 0.4, 0.15, 1)
	else:
		var cc := Palette.GREEN if Ships.can_buy(sh.id) else Palette.RED
		VectorFont.draw(lines, "LOCKED", Vector2(center.x, rect.position.y + 80), 10, cc, 0.4, 0.15, 1)
	# Keep the preview visual; selection details live in one fixed area.
	VectorFont.draw(lines, "LIVES %d   SPEED %d%%" % [3 + Save.extra_lives(), int(Save.speed_mult() * 100)],
		Vector2(center.x, rect.end.y - 56), 12, Palette.DIM, 0.4, 0.1, 1)


## Match the pickups: yellow hexagon for Flux, cyan four-point star for Isotope.
func draw_dock_currency(pos: Vector2, amount: String, isotope: bool, affordable := true) -> void:
	var col := Palette.CYAN if isotope else Palette.YELLOW
	if isotope:
		var pts := PackedVector2Array()
		for k in 8:
			var angle := -PI * 0.5 + k * TAU / 8.0
			pts.append(pos + Vector2(cos(angle), sin(angle)) * (12.0 if k % 2 == 0 else 4.0))
		lines.polyline(pts, true, col, 0.0, 0.0, 1.1)
	else:
		lines.circle(pos, 10, col, 6, 0.0, 0.0, 1.1)
	lines.circle(pos, 2.5, Palette.FULLBRIGHT, 6, 0.0, 0.0, 0.8)
	VectorFont.draw(lines, amount, pos + Vector2(22, -7), 14, Palette.RED if not affordable else col)


func set_currency_ask(amount: float, isotope: bool) -> void:
	set_msg("NEED", 1.2)
	msg_currency = 1 if isotope else 0
	msg_amount = fmt(amount)


## Center a currency ask without embedding currency names into the text.
func draw_currency_caption(label: String, amount: String, isotope: bool, pos: Vector2, suffix := "", affordable := true) -> void:
	var label_width := VectorFont.width(label + " ", 14)
	var amount_width := VectorFont.width(amount, 14)
	var suffix_width := VectorFont.width(suffix, 14)
	var left := pos.x - (label_width + 34 + amount_width + suffix_width) * 0.5
	VectorFont.draw(lines, label, Vector2(left, pos.y - 7), 14, Palette.CYAN)
	draw_dock_currency(Vector2(left + label_width + 12, pos.y), amount, isotope, affordable)
	VectorFont.draw(lines, suffix, Vector2(left + label_width + 34 + amount_width, pos.y - 7), 14, Palette.CYAN)


func draw_dock_panel() -> void:
	VectorFont.draw(lines, "GALAXTIX", Vector2(800, 35), 30, Palette.WHITE, 0.0, 0.0, 1, 1.2, VectorFont.display)
	draw_dock_currency(Vector2(1270, 56), fmt(Save.data.flux), false)
	draw_dock_currency(Vector2(1430, 56), fmt(Save.data.isotope), true)
	var step := 2 if dock_tab == 1 else dock_sel
	var steps := ["1 GALAXY", "2 SECTOR", "3 SHIP"]
	for i in 3:
		var x := 570.0 + i * 230.0
		var col := Palette.YELLOW if step == i else (Palette.GREEN if i < step else Palette.DIM)
		VectorFont.draw(lines, steps[i], Vector2(x, 105), 13, col, 0.0, 0.0, 1)
		if i < 2:
			VectorFont.draw(lines, ">", Vector2(x + 115, 105), 12, Palette.DIM, 0.0, 0.0, 1)
	var g := Galaxies.get_galaxy(Save.data.galaxy)
	var sh := Ships.get_ship(Save.data.ship)
	if step == 2:
		draw_dock_upgrades()
	if dock_tab == 0:
		var ss := clampi(int(Save.data.start_sector), 1, max_start(g.id))
		var sector := "ENDLESS" if ss > Galaxies.LENGTH else "SECTOR %02d" % ss
		var value: String = g.name
		var action := "CHOOSE SECTOR"
		if dock_sel == 1:
			value = sector
			action = "CHOOSE SHIP"
		elif dock_sel == 2:
			value = sh.name
			action = "LAUNCH" if Ships.owned(sh.id) else "UNLOCK"
			VectorFont.draw(lines, "%s / %s" % [g.name, sector], Vector2(800, 175), 12, Palette.DIM, 0.0, 0.0, 1)
		VectorFont.draw(lines, "< %s >" % value, Vector2(800, 756), 20, Palette.CYAN, 0.0, 0.0, 1)
		if dock_sel == 2:
			draw_dock_desc(635, 205, 420)
		lines.rect(Rect2(580, 804, 440, 44), Palette.CYAN)
		if dock_sel == 2 and not Ships.owned(sh.id):
			draw_currency_caption("UNLOCK", str(int(sh.cost)), true, Vector2(800, 826), " [ENTER]", Ships.can_buy(sh.id))
		else:
			VectorFont.draw(lines, action + " [ENTER]", Vector2(800, 819), 16, Palette.CYAN, 0.0, 0.0, 1)
	var hint := "UP/DOWN SELECT   ENTER BUY   TAB SHIP   ESC BACK" if dock_tab == 1 else "LEFT/RIGHT CHOOSE   ENTER CONTINUE   ESC BACK"
	if dock_tab == 0 and dock_sel == 2:
		hint += "   TAB UPGRADES"
	if dock_tab == 0 and dock_sel == 2 and Ships.owned(sh.id):
		hint = "LEFT/RIGHT CHOOSE   ENTER/SPACE LAUNCH   ESC BACK   TAB UPGRADES"
	VectorFont.draw(lines, hint, Vector2(800, 873), 11, Palette.DIM, 0.0, 0.0, 1)


func draw_dock_upgrades() -> void:
	var sh := Ships.get_ship(Save.data.ship)
	var total := dock_rows() - DOCK_FIXED_ROWS - 1
	const VISIBLE := 6
	dock_upgrade_scroll = clampi(dock_upgrade_scroll, 0, maxi(0, total - VISIBLE))
	if dock_sel >= DOCK_FIXED_ROWS and dock_sel < dock_rows() - 1:
		var selected := dock_sel - DOCK_FIXED_ROWS
		dock_upgrade_scroll = clampi(dock_upgrade_scroll, maxi(0, selected - VISIBLE + 1), selected)
	VectorFont.draw(lines, "UPGRADES", Vector2(770, 235), 12, Palette.DIM)
	VectorFont.draw(lines, "%d-%d / %d" % [dock_upgrade_scroll + 1, mini(dock_upgrade_scroll + VISIBLE, total), total],
		Vector2(1380, 235), 11, Palette.DIM, 0.0, 0.0, 2)
	for i in range(dock_upgrade_scroll, mini(dock_upgrade_scroll + VISIBLE, total)):
		var row := DOCK_FIXED_ROWS + i
		var entry := dock_upgrade_at(row)
		var u: Dictionary = entry[1]
		var general: bool = entry[0] == "general"
		var lvl := Save.level(u.id) if general else Ships.up_level(sh.id, u.id)
		var maxed := Save.maxed(u.id) if general else Ships.up_maxed(sh.id, u.id)
		var affordable := Save.can_buy(u.id) if general else Ships.can_buy_up(sh.id, u.id)
		var cost := Save.cost(u.id) if general else Ships.up_cost(sh.id, u.id)
		var y := 285.0 + (i - dock_upgrade_scroll) * 48.0
		var selected := dock_sel == row
		draw_dock_cursor(y, selected)
		VectorFont.draw(lines, u.name, Vector2(770, y), 15, Palette.WHITE if selected else Palette.DIM)
		VectorFont.draw(lines, "LV %d" % lvl, Vector2(1100, y), 13, Palette.DIM)
		var price := "MAX" if maxed else fmt(cost)
		if not general and not Ships.owned(sh.id):
			price = "LOCKED"
		if price == "MAX" or price == "LOCKED":
			VectorFont.draw(lines, price, Vector2(1380, y), 14, Palette.DIM, 0.0, 0.0, 2)
		else:
			var price_width := VectorFont.width(price, 14)
			draw_dock_currency(Vector2(1380 - price_width - 22, y + 7), price, false, affordable)
	lines.seg(Vector2(742, 598), Vector2(1380, 598), Palette.DIM)
	if dock_tab == 1:
		draw_dock_desc(635, 770, 580)


func draw_dock_cursor(y: float, selected: bool) -> void:
	if selected:
		VectorFont.draw(lines, ">", Vector2(742, y), 16, Palette.YELLOW, 0.0, 0.0)


## One fixed description area keeps navigation from shifting the layout.
func draw_dock_desc(y: float, x := 360.0, max_width := 880.0) -> void:
	var text := ""
	var col := Palette.CYAN
	var g := Galaxies.get_galaxy(Save.data.galaxy)
	var sh := Ships.get_ship(Save.data.ship)
	if dock_sel == 0:
		text = String(g.desc) if Galaxies.unlocked(g.id) else Galaxies.unlock_hint(g.id)
		if not Galaxies.unlocked(g.id):
			col = Palette.RED
	elif dock_sel == 1:
		var ss := clampi(int(Save.data.start_sector), 1, max_start(g.id))
		if not Galaxies.unlocked(g.id):
			text = Galaxies.unlock_hint(g.id)
			col = Palette.RED
		elif ss == Galaxies.LENGTH:
			text = String(g.boss_desc)
		elif not scan_layout.is_empty():
			text = "%d NODES / %d HAZARDS / CLAIM 75%%" % [scan_layout.nodes.size(), scan_layout.turrets.size() + scan_layout.spawners.size()]
	elif dock_sel == 2:
		text = String(sh.desc)
		if not Ships.owned(sh.id):
			VectorFont.draw(lines, "UNLOCK", Vector2(x, y), 12, Palette.CYAN)
			draw_dock_currency(Vector2(x + VectorFont.width("UNLOCK", 12) + 18, y + 6), str(int(sh.cost)), true, Ships.can_buy(sh.id))
			y += 26
	elif dock_sel < dock_rows() - 1:
		var entry := dock_upgrade_at(dock_sel)
		text = String(entry[1].desc)
		if entry[0] == "ship":
			text = String(sh.name) + ": " + text
	else:
		text = "%s / SECTOR %02d / %s" % [g.name, int(Save.data.start_sector), sh.name]
		if not Galaxies.unlocked(g.id):
			text = Galaxies.unlock_hint(g.id)
			col = Palette.RED
		elif not Ships.owned(sh.id):
			text = "UNLOCK SHIP OR CHOOSE AN OWNED SHIP."
			col = Palette.YELLOW
	var line := ""
	for word in text.split(" "):
		var candidate := word if line.is_empty() else line + " " + word
		if not line.is_empty() and VectorFont.width(candidate, 12) > max_width:
			VectorFont.draw(lines, line, Vector2(x, y), 12, col)
			y += 22
			line = word
		else:
			line = candidate
	VectorFont.draw(lines, line, Vector2(x, y), 12, col)


# ------------------------------------------------------------------ battle royale online
## Solo runs the sim locally. Hosting runs the same sim and streams snapshots; guests send
## intents and render what they are told. `Net` hides whether that is Steam or ENet.
func wire_battle_net() -> void:
	if br_net_wired:
		return
	br_net_wired = true
	Net.hosting_started.connect(_br_hosting_started)
	Net.joined.connect(_br_joined)
	Net.join_failed.connect(_br_join_failed)
	Net.disconnected.connect(_br_disconnected)
	Net.roster_changed.connect(_br_roster_changed)
	Net.match_started.connect(_br_match_started)
	Net.snapshot_received.connect(_br_snapshot)
	Net.input_received.connect(_br_input)
	Net.ability_received.connect(_br_ability)
	Net.board_requested.connect(_br_board_requested)


func update_battle_royale(dt: float) -> void:
	if battle.phase == "lobby":
		update_battle_lobby(dt)
		return
	if Net.is_guest():
		battle.tick_guest(dt)
		if Input.is_action_just_pressed("abort"):
			leave_battle_online()
			go_title()
			return
		if battle.phase == "playing":
			battle.poll_local_input()
			var me := battle.racer(battle.local_id)
			if me != null:
				br_input_t += dt
				if me.intent_dir != br_last_dir or br_input_t >= 0.1:
					br_input_t = 0.0
					br_last_dir = me.intent_dir
					Net.send_input(me.intent_dir, true)
				if me.want_harden: Net.send_ability(true)
				if me.want_drive: Net.send_ability(false)
				me.want_harden = false
				me.want_drive = false
		return
	if battle.phase == "ready" and Net.is_offline() and not Net.pending():
		if Input.is_action_just_pressed("br_host"):
			battle.notice = ""
			if not Net.host():
				battle.notice = "COULD NOT HOST"
				battle.notice_time = 2.0
			return
		if Input.is_action_just_pressed("br_join"):
			var code := DisplayServer.clipboard_get().strip_edges()
			if code == "" or code.length() > 64:
				battle.notice = "COPY AN INVITE CODE FIRST"
				battle.notice_time = 2.0
			elif not Net.join(code):
				pass   # join_failed carries the reason
			else:
				battle.notice = "JOINING %s..." % code
				battle.notice_time = 6.0
			return
	if Net.pending():
		battle.notice_time = maxf(0.0, battle.notice_time - dt)
		return   # a Steam lobby is opening; don't let Enter start a solo round underneath it
	if battle.update(dt):
		leave_battle_online()
		go_title()
		return
	if Net.is_host():
		br_snapshot_t += dt
		if br_snapshot_t >= 1.0 / BR_SNAPSHOT_HZ:
			br_snapshot_t = 0.0
			var with_board := battle.owners_version != br_board_sent
			Net.send_snapshot(battle.encode_state(with_board), with_board)
			if with_board: br_board_sent = battle.owners_version


func update_battle_lobby(dt: float) -> void:
	battle.notice_time = maxf(0.0, battle.notice_time - dt)
	refresh_battle_lobby()
	if Input.is_action_just_pressed("abort"):
		leave_battle_online()
		battle.phase = "ready"
		return
	if not Net.is_host():
		return
	if Input.is_action_just_pressed("br_invite") and Net.overlay_available():
		Net.open_invite_overlay()
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("launch"):
		start_hosted_match()


func start_hosted_match() -> void:
	var slots: Array = []
	for i in Net.peers.size():
		slots.append([Net.peers[i], i, Net.display_name(Net.peers[i])])
	Net.start_match(randi() & 0x7fffffff, slots)


func refresh_battle_lobby() -> void:
	var lobby_names: Array = []
	for peer in Net.peers:
		lobby_names.append(Net.display_name(peer))
	battle.lobby = {
		"host": Net.is_host(),
		"names": lobby_names,
		"code": Net.invite_code() if Net.is_host() else "",
		"overlay": Net.overlay_available(),
		"message": battle.notice if battle.notice_time > 0.0 else "",
	}


func leave_battle_online() -> void:
	Net.leave()
	battle.guest = false
	battle.humans = 1
	battle.local_id = 0
	battle.names.assign(BattleRoyale.NAMES)


func _br_hosting_started() -> void:
	if state != State.BATTLE_ROYALE:
		return
	battle.phase = "lobby"
	var code := Net.invite_code()
	DisplayServer.clipboard_set(code)
	battle.notice = "LOBBY OPEN - CODE COPIED"
	battle.notice_time = 3.0
	refresh_battle_lobby()


func _br_joined() -> void:
	if state != State.BATTLE_ROYALE:
		return
	battle.guest = true
	battle.phase = "lobby"
	battle.notice = ""
	refresh_battle_lobby()


func _br_join_failed(reason: String) -> void:
	if state != State.BATTLE_ROYALE:
		return
	battle.phase = "ready"
	battle.guest = false
	battle.notice = reason
	battle.notice_time = 4.0


func _br_disconnected() -> void:
	if state != State.BATTLE_ROYALE:
		return
	leave_battle_online()
	battle.start()
	battle.notice = "HOST LEFT THE MATCH"
	battle.notice_time = 4.0


func _br_roster_changed() -> void:
	if state == State.BATTLE_ROYALE and battle.phase == "lobby":
		refresh_battle_lobby()


func _br_match_started(seed_value: int, slots: Array) -> void:
	if state != State.BATTLE_ROYALE:
		return
	br_slots.clear()
	for entry in slots: br_slots[int(entry[0])] = int(entry[1])
	battle.start(seed_value)
	battle.set_slots(slots, Net.local_id())
	battle.guest = Net.is_guest()
	battle.phase = "playing"
	br_board_sent = 0
	br_snapshot_t = 0.0


func _br_snapshot(bytes: PackedByteArray) -> void:
	if state == State.BATTLE_ROYALE and Net.is_guest() and battle.humans > 1:
		battle.decode_state(bytes)


func _br_input(peer: int, dir: Vector2i, draw: bool) -> void:
	if state != State.BATTLE_ROYALE or not Net.is_host():
		return
	var slot: int = br_slots.get(peer, -1)
	if slot > 0: battle.set_intent(slot, dir, draw)


func _br_ability(peer: int, hard: bool) -> void:
	if state != State.BATTLE_ROYALE or not Net.is_host():
		return
	var slot: int = br_slots.get(peer, -1)
	var r := battle.racer(slot) if slot > 0 else null
	if r == null:
		return
	if hard: r.want_harden = true
	else: r.want_drive = true


func _br_board_requested(peer: int) -> void:
	if state == State.BATTLE_ROYALE and Net.is_host():
		Net.send_board(peer, battle.encode_state(true))
