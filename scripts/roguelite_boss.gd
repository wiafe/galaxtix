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
var maw = preload("res://scripts/thorn_maw.gd").new()

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
			relays.append({"cell": enemy.cell, "captured": false, "phase": "idle", "clock": 2.0 + relays.size() * 1.4, "direction": Vector2.DOWN, "target": enemy.cell, "home": home, "cycle": 0})
	# A locked core is solid, so even Charge cannot capture it before the relays.
	for i in g.disc_cells(core, 4):
		if g.cells[i] == g.FREE:
			shell.append(i)
			g.cells[i] = g.ROCK
			g.free_count -= 1
	g.grid_changed()
	if id == "thorn_maw": maw.reset(g, self)

func active() -> bool:
	return not id.is_empty()

func remaining() -> int:
	return relays.filter(func(r): return not r.captured).size()

func instruction() -> String:
	if id == "thorn_maw": return "HEART CAPTURED" if defeated else maw.instruction(unlocked)
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
	if id == "thorn_maw": maw.observe(g)
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
	if not unlocked and (maw.ready() if id == "thorn_maw" else remaining() == 0):
		unlocked = true
		if id == "thorn_maw": maw.set_open(g, true)
		for i in shell:
			g.cells[i] = g.FREE
			g.credited[i] = 0
			g.free_count += 1
		g.bolts.clear()
		g.grid_changed()
		g.show_objective_notice("HEART EXPOSED - ENCLOSE IT" if id == "thorn_maw" else "CORE EXPOSED - ENCLOSE IT")
		g.sparks.ripple(g.center(core), 30, 280, 0.8, Palette.YELLOW)
		return # The core must be captured with a subsequent cut.
	if unlocked and g.disc_claimed_fraction(core, 4) >= 1.0:
		defeated = true
		g.bolts.clear()
		g.sparks.burst(g.center(core), 160, 400, 1.6, 1.2, Palette.YELLOW)
		g.sparks.ripple(g.center(core), 10, 700, 1.5, Palette.GREEN)
		g.lines.spike(3, 0.5)
		g.show_objective_notice("HEART CAPTURED" if id == "thorn_maw" else "CORE CAPTURED")

func update(g, dt: float) -> void:
	if not active() or defeated or g.phase != "run" or g.state != g.State.PLAYING: return
	observe(g)
	if defeated or g.freeze_time > 0: return
	if id == "thorn_maw":
		maw.update(g, self, dt)
		return
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
					relay.clock = fire_seconds()
				"fire":
					relay.phase = "idle"
					relay.clock = 4.0 if id != "brood_queen" else 5.5
					relay.cycle += 1
		if relay.phase == "fire":
			for ray in beams(g, relay, index):
				g.field_features.sniper_contact(g, ray)
				if g.state != g.State.PLAYING: return
		if g.state != g.State.PLAYING: return

func fire_seconds() -> float:
	return 1.2 if id == "grinder" else (0.65 if id == "prism_warden" else 0.35)

## Warning and damage use the same rays. Grinder shows the whole sweep envelope.
func beams(g, relay: Dictionary, index: int, warning := false) -> Array[Dictionary]:
	var angles: Array = []
	match id:
		"reactor_heart":
			if index == 0: angles = [0.0]
		"grinder":
			angles = [-0.45, 0.0, 0.45] if warning else [lerpf(-0.45, 0.45, clampf(1.0 - float(relay.clock) / fire_seconds(), 0.0, 1.0))]
		"prism_warden":
			angles = [-0.32, 0.0, 0.32]
	var result: Array[Dictionary] = []
	for angle in angles:
		var ray := relay.duplicate()
		ray.direction = Vector2(relay.direction).rotated(angle)
		if id == "grinder": ray["range"] = 22 * g.CELL
		result.append(ray)
	return result

func attack(g, relay: Dictionary, index: int) -> void:
	var origin: Vector2 = g.center(relay.cell)
	if id == "thorn_maw":
		# Rotating gaps make successive bursts different; claimed land catches spores.
		for i in 12:
			var bolt := Game.Bolt.new()
			bolt.pos = origin
			bolt.vel = Vector2.RIGHT.rotated(i * TAU / 12 + int(relay.cycle) * PI / 12) * 95
			bolt.source = "THORN SPORE"
			g.bolts.append(bolt)
	elif id in ["grinder", "prism_warden"]:
		pass # Persistent beams are resolved during their fire phase.
	elif id == "brood_queen":
		if relay.home.alive >= 2: return
		var mite := Game.Mite.new()
		mite.pos = origin
		mite.vel = relay.direction * 45
		mite.home = relay.home
		mite.home.pos = origin
		g.configure_mite(mite)
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
	if id == "thorn_maw":
		maw.draw(g, self)
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
			if id == "thorn_maw":
				for i in 12:
					var direction := Vector2.RIGHT.rotated(i * TAU / 12 + int(relay.cycle) * PI / 12)
					g.lines.seg(point + direction * 20, point + direction * 36, Palette.YELLOW)
			elif id == "reactor_heart" and index == 1:
				g.lines.circle(g.center(relay.target), 3 * g.CELL, Palette.ORANGE, 16)
			elif id in ["grinder", "prism_warden"] or (id == "reactor_heart" and index == 0):
				for ray in beams(g, relay, index, true):
					g.dashed(point, g.field_features.beam_end(g, ray), Color(Palette.YELLOW, 0.6), 5, 7)
			elif id != "brood_queen":
				g.dashed(point, g.field_features.beam_end(g, relay), Color(Palette.YELLOW, 0.6), 5, 7)
		if relay.phase == "fire":
			for ray in beams(g, relay, index):
				g.lines.seg(point, g.field_features.beam_end(g, ray), Palette.RED, 0.1, 0.03, 3)
	# Each boss has a distinct central silhouette, all much larger than normal enemies.
	var radius: float = 4.5 * g.CELL
	# Share the anomaly's cycling spectrum and unstable halo while capture is blocked.
	# The stable yellow silhouette signals that the exposed core can now be enclosed.
	color = Palette.YELLOW if unlocked else g.anomaly_color()
	if not unlocked: g.draw_anomaly_ring(pos, radius + 18, 32, 0, 1.6)
	if id == "grinder":
		var teeth := PackedVector2Array()
		for i in 32:
			teeth.append(pos + Vector2.RIGHT.rotated(i * TAU / 32 + g.time * 0.3) * (radius + (8 if i % 4 < 2 else 0)))
		g.lines.polyline(teeth, true, color, 0.2, 0.04, 2)
		g.lines.circle(pos, radius * 0.65, color, 16)
	elif id == "prism_warden":
		for ring in 3:
			var points := PackedVector2Array()
			for i in 3: points.append(pos + Vector2.UP.rotated(i * TAU / 3 + ring * TAU / 3 + sin(g.time) * 0.08) * (radius + ring * 7))
			g.lines.polyline(points, true, color, 0.2, 0.04, 2)
	elif id == "foreman":
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
