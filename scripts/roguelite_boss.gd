extends RefCounted
## Captures dismantle the boss. No weapon damage or upgrade is required to finish it.
const Acts = preload("res://scripts/roguelite_acts.gd")
var id := ""
var core := Vector2i.ZERO
var relays: Array[Dictionary] = []
var shell := PackedInt32Array()
var unlocked := false
var defeated := false
var rewarded := false
var presented := false

func reset(g) -> void:
	id = ""
	relays.clear()
	shell.clear()
	unlocked = false
	defeated = false
	rewarded = false
	presented = false
	if g.encounter_kind(g.level) != "boss" or g.authored_map == null: return
	id = String(g.active_destination.get("boss", g.authored_map.boss_id))
	if not Acts.BOSSES.has(id):
		id = ""
		return
	for enemy in g.authored_map.enemies:
		if enemy.kind == "boss_core": core = enemy.cell
		elif enemy.kind == "boss_relay":
			var home := Game.Spawner.new()
			home.cell = enemy.cell
			relays.append({"cell": enemy.cell, "captured": false, "phase": "idle", "clock": 2.0 + relays.size() * 1.4, "direction": Vector2.DOWN, "target": enemy.cell, "home": home})
	# A locked core is solid, so even Charge cannot capture it before the relays.
	for i in g.disc_cells(core, 4):
		if g.cells[i] == g.FREE:
			shell.append(i)
			g.cells[i] = g.ROCK
			g.free_count -= 1
	g.grid_changed()

func active() -> bool:
	return not id.is_empty()

func remaining() -> int:
	return relays.filter(func(r): return not r.captured).size()

func instruction() -> String:
	if defeated: return "CORE CAPTURED"
	if unlocked: return "ENCLOSE THE CORE"
	return "CAPTURE %d %s" % [remaining(), Acts.BOSSES[id].targets] if active() else ""

func protected_cell(cell: Vector2i) -> bool:
	if not active(): return false
	if cell.distance_squared_to(core) <= 25: return true
	for relay in relays:
		if relay.captured and cell.distance_squared_to(relay.cell) <= 9: return true
	return false

func observe(g) -> void:
	if not active() or defeated: return
	for relay in relays:
		if relay.captured or g.disc_claimed_fraction(relay.cell, 2) < 1.0: continue
		relay.captured = true
		relay.phase = "idle"
		relay.home.captured = true
		for i in range(g.mites.size() - 1, -1, -1):
			if g.mites[i].home == relay.home: g.mites.remove_at(i)
		g.sparks.zap_polyline(PackedVector2Array([g.center(relay.cell), g.center(core)]), Palette.GREEN, 900.0, 3.0)
		g.sparks.ripple(g.center(relay.cell), 5, 240, 0.6, Palette.GREEN)
		g.show_objective_notice("%s CAPTURED / %d LEFT" % [Acts.BOSSES[id].targets, remaining()])
	if not unlocked and remaining() == 0:
		unlocked = true
		for i in shell:
			g.cells[i] = g.FREE
			g.credited[i] = 0
			g.free_count += 1
		g.bolts.clear()
		g.grid_changed()
		g.show_objective_notice("CORE EXPOSED - ENCLOSE IT")
		g.sparks.ripple(g.center(core), 30, 280, 0.8, Palette.YELLOW)
		return # The core must be captured with a subsequent cut.
	if unlocked and g.disc_claimed_fraction(core, 4) >= 1.0:
		defeated = true
		g.bolts.clear()
		g.sparks.burst(g.center(core), 160, 400, 1.6, 1.2, Palette.YELLOW)
		g.sparks.ripple(g.center(core), 10, 700, 1.5, Palette.GREEN)
		g.lines.spike(3, 0.5)
		g.show_objective_notice("CORE CAPTURED")

func update(g, dt: float) -> void:
	if not active() or defeated or g.phase != "run" or g.state != g.State.PLAYING: return
	observe(g)
	if defeated or g.freeze_time > 0: return
	for index in relays.size():
		var relay: Dictionary = relays[index]
		if relay.captured: continue
		relay.clock -= dt
		if relay.clock <= 0:
			match String(relay.phase):
				"idle":
					relay.phase = "warn"
					relay.clock = 1.4
					relay.direction = (g.vis - g.center(relay.cell)).normalized()
					relay.target = g.p
				"warn":
					attack(g, relay, index)
					relay.phase = "fire"
					relay.clock = 0.35
				"fire":
					relay.phase = "idle"
					relay.clock = 4.0 if id != "brood_queen" else 5.5
		if id == "reactor_heart" and index == 0 and relay.phase == "fire":
			g.field_features.sniper_contact(g, relay)
		if g.state != g.State.PLAYING: return

func attack(g, relay: Dictionary, index: int) -> void:
	var origin: Vector2 = g.center(relay.cell)
	if id == "brood_queen":
		if relay.home.alive >= 2: return
		var mite := Game.Mite.new()
		mite.pos = origin
		mite.vel = relay.direction * 45
		mite.home = relay.home
		relay.home.alive += 1
		g.mites.append(mite)
	elif id == "reactor_heart" and index == 1:
		g.field_features.break_patch(g, relay.target)
	elif id != "reactor_heart" or index == 2:
		for i in 5:
			var bolt := Game.Bolt.new()
			bolt.pos = origin
			bolt.vel = relay.direction.rotated((i - 2) * 0.22) * 130
			bolt.source = "BOSS VOLLEY"
			g.bolts.append(bolt)

func draw(g) -> void:
	if not active(): return
	var pos: Vector2 = g.center(core)
	var color: Color = Acts.ACTS[Acts.BOSSES[id].act - 1].color
	if defeated:
		g.lines.circle(pos, 35 + g.ui_time * 120, Color(Palette.GREEN, maxf(0, 0.6 - g.ui_time * 0.3)), 48)
		return
	for index in relays.size():
		var relay: Dictionary = relays[index]
		var point: Vector2 = g.center(relay.cell)
		var relay_color := Palette.GREEN if relay.captured else Palette.YELLOW
		g.dashed(point, pos, Color(relay_color, 0.3 if relay.captured else 0.5), 5, 8)
		g.lines.circle(point, 2.5 * g.CELL, relay_color, 12, 0.1, 0.02, 1.4)
		if relay.captured:
			g.lines.polyline(PackedVector2Array([point + Vector2(-7, 0), point + Vector2(-2, 5), point + Vector2(8, -6)]), false, Palette.GREEN)
		else:
			g.lines.circle(point, 8, color, 6 if id != "brood_queen" else 10, 0.3, 0.1, 2)
		if relay.phase == "warn":
			g.lines.circle(point, 3.4 * g.CELL + sin(g.time * 15) * 2, Palette.YELLOW, 20)
			if id == "reactor_heart" and index == 1:
				g.lines.circle(g.center(relay.target), 3 * g.CELL, Palette.ORANGE, 16)
			elif id != "brood_queen":
				g.dashed(point, g.field_features.beam_end(g, relay), Color(Palette.YELLOW, 0.6), 5, 7)
		if id == "reactor_heart" and index == 0 and relay.phase == "fire":
			g.lines.seg(point, g.field_features.beam_end(g, relay), Palette.RED, 0.1, 0.03, 3)
	# Each boss has a distinct central silhouette, all much larger than normal enemies.
	var radius: float = 4.5 * g.CELL
	if id == "foreman":
		g.lines.rect(Rect2(pos - Vector2(radius, radius), Vector2.ONE * radius * 2), color, 0.2, 0.04, 2)
		for side in [-1, 1]: g.lines.rect(Rect2(pos + Vector2(side * radius - 6, -12), Vector2(12, 24)), color)
	elif id == "brood_queen":
		g.lines.circle(pos, radius, color, 10, 0.5, 0.1, 2)
		for i in 6:
			var arm := Vector2.RIGHT.rotated(i * TAU / 6 + sin(g.time) * 0.08)
			g.lines.seg(pos + arm * radius, pos + arm * (radius + 12), color, 0.4, 0.1, 2)
	else:
		for ring in [0, 1]:
			var points := PackedVector2Array()
			for i in 6: points.append(pos + Vector2.RIGHT.rotated(i * TAU / 6 + g.time * (0.15 if ring == 0 else -0.1)) * (radius + ring * 9))
			g.lines.polyline(points, true, color, 0.1, 0.03, 1.6)
	g.lines.circle(pos, 13 + sin(g.time * 3) * 2, Palette.YELLOW if unlocked else color, 8, 0.1, 0.03, 2)
	if not unlocked:
		g.lines.rect(Rect2(pos - Vector2(5, 1), Vector2(10, 9)), Palette.WHITE)
		g.arc(pos + Vector2(0, -1), 5, PI, TAU, Palette.WHITE, 1)
