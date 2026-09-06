class_name BattleRoyale
extends RefCounted
## Shared-board qualifying. Owned islands survive severance; excursions can reconnect to any owned territory.
const SIZES := [Vector2i(68, 42), Vector2i(56, 34), Vector2i(46, 28)]
const TIMES := [90.0, 75.0, 60.0]
const CUTS := [6, 4, 1]
const LABELS := ["Q1", "Q2", "FINAL"]
const DIRS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const NAMES := ["YOU", "NOVA", "VEGA", "ION", "ORBIT", "ECHO", "COMET", "PULSE", "LYRA", "QUARK", "SOL", "RIFT"]
const CELL := 11.0
const FRAME := Rect2(40, 40, 836, 836)

class Racer:
	var id := 0
	var pos := Vector2i.ZERO
	var facing := Vector2i.UP
	var anchor := Vector2i.ZERO
	var rail: Array[Vector2i] = []
	var trail: Array[Vector2i] = []
	var plan: Array[Vector2i] = []
	var owned: Array[Vector2i] = []
	var exposed := false
	var acc := 0.0
	var think := 0.0
	var harden := 0.0
	var drive := 0.0
	var has_harden := true
	var has_drive := true
	var failures := 0
	var biggest := 0
	var score := 0
	var tie := 0
	var wall_edges: Array = []
	var wall_hatching: Array = []

var racers: Array[Racer] = []
var standings: Array[Racer] = []
var owners := PackedInt32Array()
var rails := PackedInt32Array()
var trails := PackedInt32Array()
var size := Vector2i.ZERO
var origin := Vector2.ZERO
var round_index := 0
var remaining := 90.0
var phase := "ready"
var phase_time := 0.0
var notice := ""
var notice_time := 0.0
var hazard := Vector2.ZERO
var hazard_velocity := Vector2(3.1, 2.3)
var territory_segments: Array = []
var territory_image: Image
var territory_texture: ImageTexture
var texture_dirty := false
var rng := RandomNumberGenerator.new()
var turn := 0
var roster: Array[Racer] = []       # fixed on-screen order during a round; no live ranking
var reveal_order: Array[int] = []   # standings slots in the order the buzzer reveals them
var reveal_count := 0
var reveal_time: Dictionary = {}    # racer id -> phase_time when its slot was revealed
var reveal_finish := INF
const REVEAL_BEAT := 1.0
const REVEAL_STEP := 0.4
const REVEAL_HOLD := 1.2

func start(seed_value := -1) -> void:
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	racers.clear()
	for id in 12:
		var r := Racer.new()
		r.id = id
		racers.append(r)
	round_index = 0
	begin_round()

func index(c: Vector2i) -> int:
	return c.y * size.x + c.x

func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y

func owner(c: Vector2i) -> int:
	return owners[index(c)] if inside(c) else -2

func racer(id: int) -> Racer:
	for r in racers:
		if r.id == id:
			return r
	return null

func color(id: int) -> Color:
	return Palette.CYAN if id == 0 else Color.from_hsv(fmod(0.07 + id * 0.618034, 1.0), 0.65, 1.0)

func point(c: Vector2i) -> Vector2:
	return origin + (Vector2(c) + Vector2.ONE * 0.5) * CELL

func begin_round() -> void:
	size = SIZES[round_index]
	origin = FRAME.get_center() - Vector2(size) * CELL * 0.5
	territory_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	territory_texture = ImageTexture.create_from_image(territory_image)
	owners.resize(size.x * size.y)
	owners.fill(-1)
	rails.resize(owners.size())
	rails.fill(-1)
	trails.resize(owners.size())
	trails.fill(-1)
	var perimeter: Array[Vector2i] = []
	for x in size.x: perimeter.append(Vector2i(x, 0))
	for y in range(1, size.y): perimeter.append(Vector2i(size.x - 1, y))
	for x in range(size.x - 2, -1, -1): perimeter.append(Vector2i(x, size.y - 1))
	for y in range(size.y - 2, 0, -1): perimeter.append(Vector2i(0, y))
	# Shuffle spawn assignments without relying on global gameplay randomness.
	for i in range(racers.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := racers[i]
		racers[i] = racers[j]
		racers[j] = tmp
	var offset := rng.randi_range(0, perimeter.size() - 1)
	for i in racers.size():
		var r := racers[i]
		r.rail.clear()
		r.trail.clear()
		r.plan.clear()
		r.exposed = false
		r.harden = 0.0
		r.drive = 0.0
		r.acc = 0.0
		r.think = rng.randf_range(0.3, 1.0)
		r.failures = 0
		r.biggest = 0
		r.tie = i
		var slot := (offset + i * perimeter.size() / racers.size()) % perimeter.size()
		for k in range(-3, 4):
			var c := perimeter[posmod(slot + k, perimeter.size())]
			r.rail.append(c)
			rails[index(c)] = r.id
			owners[index(c)] = r.id
		r.pos = perimeter[slot]
		r.anchor = r.pos
		r.facing = Vector2i.DOWN if r.pos.y == 0 else (Vector2i.UP if r.pos.y == size.y - 1 else (Vector2i.RIGHT if r.pos.x == 0 else Vector2i.LEFT))
	roster.assign(racers)
	roster.sort_custom(func(a: Racer, b: Racer) -> bool: return a.id < b.id)
	remaining = TIMES[round_index]
	phase = "ready"
	phase_time = 0.0
	hazard = Vector2(size) * 0.5
	rebuild()

func rebuild() -> void:
	for r in racers:
		r.owned.clear()
		r.score = 0
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			var id := owner(c)
			if id >= 0:
				var r := racer(id)
				r.owned.append(c)
				if rails[index(c)] < 0: r.score += 1
	# Cache each owner's complete wall, including borders shared with higher-numbered owners.
	for r in racers:
		r.wall_edges.clear()
		r.wall_hatching.clear()
		for c in r.owned:
			var top_left := origin + Vector2(c) * CELL
			if (c.x + c.y) % 3 == 0:
				r.wall_hatching.append([top_left + Vector2(1, CELL - 1), top_left + Vector2(CELL - 1, 1)])
			for d in DIRS:
				if owner(c + d) != r.id:
					var midpoint := point(c) + Vector2(d) * CELL * 0.5
					var tangent := Vector2(-d.y, d.x) * CELL * 0.5
					r.wall_edges.append([midpoint - tangent, midpoint + tangent])
	standings.assign(racers)
	standings.sort_custom(func(a: Racer, b: Racer) -> bool:
		if a.score != b.score: return a.score > b.score
		if a.biggest != b.biggest: return a.biggest > b.biggest
		if a.failures != b.failures: return a.failures < b.failures
		return a.tie < b.tie)
	# Ownership texture changes only on capture; cache merged border outlines alongside it.
	refresh_fill()
	territory_segments.clear()
	for axis in 2:
		var across := size.x if axis == 0 else size.y
		var down := size.y if axis == 0 else size.x
		for a in range(down + 1):
			var start_b := -1
			var last_id := -1
			for b in range(across + 1):
				var id := -1
				if b < across:
					var c := Vector2i(b, a) if axis == 0 else Vector2i(a, b)
					var prev := c - (Vector2i.DOWN if axis == 0 else Vector2i.RIGHT)
					if owner(c) != owner(prev): id = maxi(owner(c), owner(prev))
				if id != last_id:
					if start_b >= 0:
						var p1 := Vector2(start_b, a) if axis == 0 else Vector2(a, start_b)
						var p2 := Vector2(b, a) if axis == 0 else Vector2(a, b)
						territory_segments.append([origin + p1 * CELL, origin + p2 * CELL, last_id])
					start_b = b if id >= 0 else -1
					last_id = id

func revealed(id: int) -> bool:
	return reveal_time.has(id)

func fill_alpha(id: int) -> float:
	if phase != "results": return 0.16
	return 0.32 if revealed(id) else 0.05

func refresh_fill() -> void:
	territory_image.fill(Color.TRANSPARENT)
	for y in size.y:
		for x in size.x:
			var id := owner(Vector2i(x, y))
			if id >= 0:
				var col := color(id)
				col.a = fill_alpha(id)
				territory_image.set_pixel(x, y, col)
	texture_dirty = true

func solid(c: Vector2i, r: Racer) -> bool:
	if not inside(c): return true
	var rail_id := rails[index(c)]
	if rail_id >= 0 and rail_id != r.id: return true
	var id := owner(c)
	return id >= 0 and id != r.id and racer(id).harden > 0.0

func nearest_safe(r: Racer, from: Vector2i) -> Vector2i:
	var best := r.rail[0]
	var distance := 1000000
	for c in r.owned:
		var d := absi(c.x - from.x) + absi(c.y - from.y)
		if d < distance:
			distance = d
			best = c
	return best

func clear_trail(r: Racer) -> void:
	for c in r.trail:
		if trails[index(c)] == r.id: trails[index(c)] = -1
	r.trail.clear()

func fail(r: Racer) -> void:
	clear_trail(r)
	r.pos = nearest_safe(r, r.anchor)
	r.exposed = false
	r.plan.clear()
	r.failures += 1
	r.think = 0.5
	if r.id == 0:
		notice = "TRAIL HIT - BACK TO ANCHOR"
		notice_time = 1.6

func step(r: Racer, d: Vector2i, draw_allowed := true) -> bool:
	var next := r.pos + d
	if solid(next, r): return false
	if owner(next) != r.id and (r.harden > 0.0 or not draw_allowed and not r.exposed): return false
	var other := trails[index(next)]
	if other >= 0 and other != r.id: fail(racer(other))
	if other == r.id:
		# Allow retracing the last step to get out of corners; crossing yourself fails.
		if r.trail.size() >= 2 and next == r.trail[r.trail.size() - 2]:
			trails[index(r.trail.pop_back())] = -1
			r.pos = next
			return true
		fail(r)
		return false
	if not r.exposed and owner(next) != r.id:
		r.anchor = r.pos
		r.exposed = true
	r.pos = next
	r.facing = d
	if r.exposed:
		if owner(next) == r.id:
			capture(r)
		else:
			r.trail.append(next)
			trails[index(next)] = r.id
	return true

func capture(r: Racer) -> void:
	var before := r.score
	for c in r.trail:
		if not solid(c, r): owners[index(c)] = r.id
	clear_trail(r)
	r.exposed = false
	# Flood from the outer boundary; only genuinely enclosed regions are awarded.
	var seen := PackedByteArray()
	seen.resize(owners.size())
	var queue: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if (x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1) and owner(c) != r.id:
				seen[index(c)] = 1
				queue.append(c)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if inside(n) and seen[index(n)] == 0 and owner(n) != r.id:
				seen[index(n)] = 1
				queue.append(n)
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if seen[index(c)] == 0 and not solid(c, r): owners[index(c)] = r.id
	var after := 0
	for i in owners.size():
		if owners[i] == r.id and rails[i] < 0: after += 1
	r.biggest = maxi(r.biggest, after - before)
	rebuild()
	for other in racers:
		if not other.exposed and owner(other.pos) != other.id:
			other.pos = nearest_safe(other, other.pos)
			other.plan.clear()
	r.plan.clear()

func ability(r: Racer, hard: bool) -> void:
	if hard:
		if not r.has_harden or r.exposed: return
		r.has_harden = false
		r.harden = 4.0 - round_index
		for other in racers:
			if other == r: continue
			for i in range(other.trail.size() - 1, -1, -1):
				var c := other.trail[i]
				if owner(c) == r.id:
					trails[index(c)] = -1
					other.trail.remove_at(i)
			if owner(other.pos) == r.id:
				var best := other.pos
				var distance := 1000000
				for y in size.y:
					for x in size.x:
						var c := Vector2i(x, y)
						var dist := absi(c.x - other.pos.x) + absi(c.y - other.pos.y)
						if not solid(c, other) and dist < distance:
							distance = dist
							best = c
				other.pos = best
				other.plan.clear()
	else:
		if not r.has_drive: return
		r.has_drive = false
		r.drive = 4.0 - round_index

func safe_path(r: Racer, target: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [r.pos]
	var previous := {r.pos: r.pos}
	var head := 0
	while head < queue.size() and not previous.has(target):
		var c := queue[head]
		head += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if owner(n) == r.id and not previous.has(n):
				previous[n] = c
				queue.append(n)
	var path: Array[Vector2i] = []
	if not previous.has(target): return path
	var c := target
	while c != r.pos:
		path.push_front(c)
		c = previous[c]
	return path

func plan_ai(r: Racer) -> void:
	if r.exposed:
		# Replan a shortest legal route home when territory or Harden invalidates a plan.
		var queue: Array[Vector2i] = [r.pos]
		var previous := {r.pos: r.pos}
		var head := 0
		var target := r.pos
		while head < queue.size():
			var c := queue[head]
			head += 1
			if owner(c) == r.id:
				target = c
				break
			for d in DIRS:
				var n: Vector2i = c + d
				if not solid(n, r) and trails[index(n)] != r.id and not previous.has(n):
					previous[n] = c
					queue.append(n)
		while target != r.pos:
			r.plan.push_front(target)
			target = previous[target]
		return
	var best_value := -1.0
	var best: Array[Vector2i] = []
	for attempt in 36:
		var start_cell := r.owned[rng.randi_range(0, r.owned.size() - 1)]
		var outward: Vector2i = DIRS[rng.randi_range(0, 3)]
		if owner(start_cell + outward) == r.id: continue
		var tangent := Vector2i(-outward.y, outward.x) * (1 if rng.randf() < 0.5 else -1)
		var depth := rng.randi_range(3, 9)
		var width := rng.randi_range(2, 6)
		if owner(start_cell + tangent * width) != r.id: continue
		var path: Array[Vector2i] = []
		var c := start_cell
		var valid := true
		for leg in [[outward, depth], [tangent, width], [-outward, depth]]:
			for k in int(leg[1]):
				c += Vector2i(leg[0])
				if solid(c, r): valid = false
				path.append(c)
		if not valid: continue
		var value := 0.0
		for a in range(1, depth + 1):
			for b in range(width + 1):
				var id := owner(start_cell + outward * a + tangent * b)
				if id != r.id: value += 1.0 if id < 0 else 1.8
		value *= rng.randf_range(0.7, 1.3)
		if value > best_value:
			var approach := safe_path(r, start_cell)
			if start_cell != r.pos and approach.is_empty(): continue
			best_value = value
			best = approach
			best.append_array(path)
	r.plan = best

func finish_round() -> void:
	rebuild()
	phase = "results"
	phase_time = 0.0
	reveal_order.clear()
	reveal_time.clear()
	reveal_count = 0
	reveal_finish = INF
	# Eliminated from the bottom up, then qualifiers from the top, saving the last slot for the end.
	var cut := mini(CUTS[round_index], standings.size())
	for i in range(standings.size() - 1, cut - 1, -1): reveal_order.append(i)
	for i in range(0, cut - 1): reveal_order.append(i)
	reveal_order.append(cut - 1)
	refresh_fill()

func reveal_at(k: int) -> float:
	var t := REVEAL_BEAT + k * REVEAL_STEP
	if k == reveal_order.size() - 1: t += REVEAL_HOLD
	return t

func reveal_next() -> void:
	var slot: int = reveal_order[reveal_count]
	reveal_time[standings[slot].id] = phase_time
	reveal_count += 1
	if reveal_count == reveal_order.size():
		reveal_finish = phase_time + 0.6
		var cut := mini(CUTS[round_index], standings.size())
		if cut < standings.size():
			var last := standings[cut - 1]
			var first_out := standings[cut]
			if last.score == first_out.score:
				notice = "TIED %.1f%% - " % percent(last)
				if last.biggest != first_out.biggest:
					notice += "BIGGEST CAPTURE %d VS %d" % [last.biggest, first_out.biggest]
				elif last.failures != first_out.failures:
					notice += "FEWEST FAILS %d VS %d" % [last.failures, first_out.failures]
				else:
					notice += "DRAW ORDER"
				notice_time = 4.0
	refresh_fill()

func reveal_complete() -> bool:
	return phase_time >= reveal_finish

func skip_reveal() -> void:
	while reveal_count < reveal_order.size(): reveal_next()
	reveal_finish = phase_time

func percent(r: Racer) -> float:
	return 100.0 * r.score / (owners.size() - racers.size() * 7)

func qualified() -> bool:
	for i in mini(CUTS[round_index], standings.size()):
		if standings[i].id == 0: return true
	return false

func advance() -> void:
	if round_index == 2 or not qualified():
		start()
		return
	racers.assign(standings.slice(0, CUTS[round_index]))
	round_index += 1
	begin_round()

func update(dt: float, human_input := true) -> bool:
	phase_time += dt
	notice_time = maxf(0.0, notice_time - dt)
	if human_input and Input.is_action_just_pressed("abort"): return true
	if phase == "ready":
		if human_input and (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("launch")):
			phase = "playing"
		return false
	if phase == "results":
		while reveal_count < reveal_order.size() and phase_time >= reveal_at(reveal_count): reveal_next()
		if human_input and phase_time > 0.3 and (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("launch")):
			if reveal_complete(): advance()
			else: skip_reveal()
		return false
	remaining = maxf(0.0, remaining - dt)
	turn += 1
	for offset in racers.size():
		var r := racers[(turn + offset) % racers.size()]
		r.harden = maxf(0.0, r.harden - dt)
		r.drive = maxf(0.0, r.drive - dt)
		r.think -= dt
		if r.id == 0 and human_input:
			if Input.is_action_just_pressed("br_harden"): ability(r, true)
			if Input.is_action_just_pressed("br_overdrive"): ability(r, false)
		elif r.id != 0:
			if remaining < 18.0 and r.has_drive and r.exposed: ability(r, false)
			if remaining < 6.0 and r.has_harden and not r.exposed: ability(r, true)
		var speed := 10.0 if r.exposed else 18.0
		if r.drive > 0.0: speed *= 2.0
		r.acc = minf(r.acc + dt * speed, 2.0)
		while r.acc >= 1.0:
			r.acc -= 1.0
			if r.id == 0 and human_input:
				var d := Vector2i.ZERO
				for pair in [["move_up", Vector2i.UP], ["move_right", Vector2i.RIGHT], ["move_down", Vector2i.DOWN], ["move_left", Vector2i.LEFT]]:
					if Input.is_action_pressed(pair[0]): d = pair[1]
				if d != Vector2i.ZERO: step(r, d, Input.is_action_pressed("draw"))
			elif r.id != 0:
				if r.plan.is_empty() and r.think <= 0.0:
					plan_ai(r)
					r.think = rng.randf_range(0.25, 0.7)
				if not r.plan.is_empty():
					var target: Vector2i = r.plan.pop_front()
					var d := target - r.pos
					if absi(d.x) + absi(d.y) != 1 or not step(r, d): r.plan.clear()
	# One modest neutral hazard. Sweep substeps so a trail cannot be skipped.
	var moves := maxi(1, ceili(dt * hazard_velocity.length() * 2.0))
	for k in moves:
		var next := hazard + hazard_velocity * dt / moves
		if next.x < 1 or next.x >= size.x - 1: hazard_velocity.x *= -1
		if next.y < 1 or next.y >= size.y - 1: hazard_velocity.y *= -1
		next = hazard + hazard_velocity * dt / moves
		if owner(Vector2i(next)) >= 0:
			hazard_velocity = hazard_velocity.rotated(PI * 0.63)
		else:
			hazard = next.clamp(Vector2.ONE, Vector2(size) - Vector2.ONE * 1.01)
		var id := trails[index(Vector2i(hazard))]
		if id >= 0: fail(racer(id))
	if remaining <= 0.0: finish_round()
	return false

func text(lines: ScopeLines, value: String, pos: Vector2, font_size := 14, col := Color.WHITE, align := 0) -> void:
	VectorFont.draw(lines, value, pos, font_size, col, 0.0, 0.0, align)

func draw(lines: ScopeLines, fill: Sprite2D) -> void:
	if texture_dirty:
		territory_texture.update(territory_image)
		texture_dirty = false
	fill.texture = territory_texture
	fill.position = origin
	fill.scale = Vector2.ONE * CELL
	fill.visible = true
	lines.rect(FRAME, Palette.DIM, 0.0, 0.0, 0.8)
	text(lines, "BATTLE ROYALE", Vector2(70, 66), 24, Palette.CYAN)
	text(lines, "%s   %02d:%02d" % [LABELS[round_index], ceili(remaining) / 60, ceili(remaining) % 60], Vector2(846, 70), 20, Palette.WHITE, 2)
	for segment in territory_segments:
		var col := color(segment[2])
		col.a = 0.55 if racer(segment[2]).harden <= 0.0 else 1.0
		if phase == "results": col.a = 0.9 if revealed(segment[2]) else 0.12
		lines.seg(segment[0], segment[1], col, 0.0, 0.0, 1.0)
	# Harden is a geometric wall treatment, not just a brighter ownership color.
	for r in racers:
		if r.harden <= 0.0: continue
		var hatch_col := color(r.id).lerp(Palette.WHITE, 0.65)
		hatch_col.a = 0.8
		for hatch in r.wall_hatching:
			lines.seg(hatch[0], hatch[1], hatch_col, 0.0, 0.0, 1.5)
		for edge in r.wall_edges:
			lines.seg(edge[0], edge[1], color(r.id), 0.0, 0.0, 4.0)
			lines.seg(edge[0], edge[1], Palette.WHITE, 0.0, 0.0, 1.6)
	# A freshly revealed racer flashes its whole territory outline on the board.
	if phase == "results":
		for r in racers:
			if not revealed(r.id): continue
			var age: float = phase_time - reveal_time[r.id]
			if age > 0.6: continue
			var flash := color(r.id).lerp(Palette.WHITE, 0.5)
			flash.a = 1.0 - age / 0.6
			for edge in r.wall_edges:
				lines.seg(edge[0], edge[1], flash, 0.0, 0.0, 3.0)
	lines.rect(Rect2(origin, Vector2(size) * CELL), Palette.CYAN, 0.0, 0.0, 1.0)
	for r in racers:
		var col := color(r.id)
		if phase == "results" and not revealed(r.id): col.a = 0.25
		for c in r.rail:
			lines.rect(Rect2(point(c) - Vector2.ONE * 3.5, Vector2.ONE * 7), col, 0.0, 0.0, 1.4)
		for c in r.trail:
			lines.circle(point(c), 2.5, col, 4)
		if r.exposed:
			lines.circle(point(r.anchor), 5, col, 8)
		lines.circle(point(r.pos), 5.0, col, 4, 0.0, 0.0, 1.3)
		lines.seg(point(r.pos), point(r.pos) + Vector2(r.facing) * 8.0, col, 0.0, 0.0, 1.0)
		if r.id == 0:
			text(lines, "YOU", point(r.pos) + Vector2(0, -20), 10, Palette.WHITE, 1)
	var hp := origin + hazard * CELL
	lines.seg(hp - Vector2(6, 8), hp + Vector2(6, 8), Palette.MAGENTA, 0.0, 0.0, 1.8)
	text(lines, "STANDINGS" if phase == "results" else "CUTTERS", Vector2(940, 70), 24, Palette.WHITE)
	text(lines, "TOP %d %s" % [CUTS[round_index], "WIN" if round_index == 2 else "ADVANCE"], Vector2(940, 110), 13, Palette.GREEN)
	if phase == "results":
		draw_reveal(lines)
	else:
		draw_roster(lines)
	var player := racer(0)
	text(lines, "ARROWS MOVE   HOLD SPACE TO DRAW", Vector2(70, 786), 12, Palette.WHITE)
	if player.harden > 0.0:
		text(lines, "HARDENED  %.1fS" % player.harden, Vector2(846, 815), 13, Palette.WHITE, 2)
	if phase != "results":
		text(lines, "YOUR TERRITORY  %.1f%%" % percent(player), Vector2(846, 786), 13, Palette.CYAN, 2)
	text(lines, "Q HARDEN %s   E OVERDRIVE %s" % ["1" if player.has_harden else "0", "1" if player.has_drive else "0"], Vector2(70, 815), 12, Palette.CYAN)
	text(lines, "ESC MENU", Vector2(70, 846), 11, Palette.DIM)
	if notice_time > 0.0: text(lines, notice, Vector2(458, 740), 12, Palette.YELLOW, 1)
	if phase != "playing":
		var title := "SURVEYORS ONLY - CLOSE A LOOP TO CLAIM"
		var sub := "ENTER START - TOP %d %s" % [CUTS[round_index], "WINS" if round_index == 2 else "ADVANCE"]
		if phase == "results":
			title = "QUALIFIED" if qualified() else "ELIMINATED"
			if round_index == 2: title = "CHAMPION" if qualified() else "%s WINS" % NAMES[standings[0].id]
			sub = "ENTER NEXT ROUND" if qualified() and round_index < 2 else "ENTER PLAY AGAIN"
			if not reveal_complete():
				title = "TIME" if phase_time < REVEAL_BEAT else "FINAL STANDINGS"
				sub = "ENTER SKIP"
		text(lines, title, Vector2(458, 130), 18, Palette.YELLOW, 1)
		text(lines, sub, Vector2(458, 166), 12, Palette.WHITE, 1)
	text(lines, "H HARDEN   O OVERDRIVE", Vector2(940, 724), 11, Palette.DIM)
	text(lines, "TIES: BIGGEST CAPTURE, FEWEST FAILS, DRAW", Vector2(940, 754), 9, Palette.DIM)

## Mid-round panel: every cutter in a fixed order with charges, no ranks, no cut line, no percentages.
func draw_roster(lines: ScopeLines) -> void:
	text(lines, "H  O", Vector2(1480, 110), 11, Palette.DIM)
	for i in roster.size():
		var r := roster[i]
		var y := 156.0 + i * 43.0
		var col := color(r.id)
		if r.id == 0: lines.rect(Rect2(932, y - 8, 608, 33), Palette.CYAN, 0.0, 0.0, 0.8)
		text(lines, "%s%s" % ["> " if r.id == 0 else "", NAMES[r.id]], Vector2(940, y), 16, col)
		if r.harden > 0.0:
			text(lines, "HARDENED %.1fS" % r.harden, Vector2(1180, y + 2), 11, Palette.WHITE)
		elif r.drive > 0.0:
			text(lines, "OVERDRIVE %.1fS" % r.drive, Vector2(1180, y + 2), 11, Palette.WHITE)
		elif r.exposed:
			text(lines, "CUTTING", Vector2(1180, y + 2), 11, Palette.DIM)
		draw_charges(lines, r, y)

func draw_charges(lines: ScopeLines, r: Racer, y: float) -> void:
	var col := color(r.id)
	for a in 2:
		var available := r.has_harden if a == 0 else r.has_drive
		var active := r.harden > 0.0 if a == 0 else r.drive > 0.0
		var pos := Vector2(1485 + a * 30, y + 6)
		lines.circle(pos, 5, Palette.WHITE if active else (col if available else Palette.DIM), 4)
		if available or active: lines.circle(pos, 2, col, 4)

## Buzzer panel: names wait in the left column, then slide one by one into their ranked slot.
func draw_reveal(lines: ScopeLines) -> void:
	var cut := mini(CUTS[round_index], standings.size())
	for i in standings.size():
		var y := 156.0 + i * 43.0
		if i == cut and phase_time >= REVEAL_BEAT:
			lines.seg(Vector2(1176, y - 16), Vector2(1540, y - 16), Palette.RED)
		text(lines, "%02d" % (i + 1), Vector2(1180, y), 16, Palette.DIM)
		lines.seg(Vector2(1230, y + 6), Vector2(1530, y + 6), Color(Palette.DIM, 0.35))
	for i in roster.size():
		var r := roster[i]
		var col := color(r.id)
		var from := Vector2(940, 156.0 + i * 43.0)
		if not revealed(r.id):
			col.a = 0.45
			text(lines, NAMES[r.id], from, 16, col)
			continue
		var rank := standings.find(r)
		var to := Vector2(1236, 156.0 + rank * 43.0)
		var t: float = clampf((phase_time - reveal_time[r.id]) / 0.35, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		var pos := from.lerp(to, t)
		if r.id == 0 and t >= 1.0:
			lines.rect(Rect2(1172, to.y - 8, 368, 33), Palette.CYAN, 0.0, 0.0, 0.8)
		text(lines, "%s%s" % ["> " if r.id == 0 else "", NAMES[r.id]], pos, 16, col)
		if t >= 1.0:
			var pct_col := Palette.GREEN if rank < cut else Palette.RED
			text(lines, "%.1f%%" % percent(r), Vector2(1530, to.y), 14, pct_col, 2)
