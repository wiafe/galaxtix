class_name BattleRoyale
extends RefCounted
## Shared-board qualifying. Owned islands survive severance; excursions can reconnect to any owned territory.
##
## Multiplayer: the host runs this simulation for everyone. Human racers occupy ids 0..humans-1 and
## move from per-racer intents (set by the local keyboard or by `Net`); everything else is AI.
## Guests never call `update`; they rebuild rounds from the match seed and apply `decode_state`.
const SIZES := [Vector2i(68, 42), Vector2i(56, 34), Vector2i(46, 28)]
const TIMES := [90.0, 75.0, 60.0]
const FIELD := 8               # cutters at the start; two are cut in each qualifier
const CUTS := [6, 4, 1]
const LABELS := ["Q1", "Q2", "FINAL"]
const DIRS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const NAMES := ["YOU", "NOVA", "VEGA", "ION", "ORBIT", "ECHO", "COMET", "PULSE", "LYRA", "QUARK", "SOL", "RIFT"]
const CELL := 11.0
const CUT_SPEED := 8.0         # cells per second while exposed (was 10)
const SAFE_SPEED := 14.0       # cells per second on your own land (was 18); Overdrive doubles both
const FRAME := Rect2(384, 34, 832, 832)   # centred like a campaign run, readouts in columns either side
const LX := 40.0
const RX := 1256.0
const COL_W := 304.0

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
	var intent_dir := Vector2i.ZERO   # what this human wants this tick (AI ignores these)
	var intent_draw := false
	var want_harden := false          # edge-triggered ability requests, consumed by update
	var want_drive := false

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
var rng := RandomNumberGenerator.new()          # AI and hazard randomness (host only)
var layout_rng := RandomNumberGenerator.new()   # per-round board layout, reproducible from the seed
var turn := 0
var humans := 1                    # racer ids below this are people
var local_id := 0                  # which racer this machine plays
var names: Array[String] = []      # per racer id; human slots get persona names
var match_seed := 0
var owners_version := 0            # bumps on every ownership change so guests know to refetch
var guest := false                 # true when this instance only renders snapshots
var board_request_t := 0.0
var lobby: Dictionary = {}         # phase "lobby": {host, names, code, pending, message}
var roster: Array[Racer] = []       # fixed on-screen order during a round; no live ranking
var reveal_order: Array = []        # groups of standings slots in the order the buzzer reveals them
var reveal_count := 0
var reveal_time: Dictionary = {}    # racer id -> phase_time when its slot was revealed
var reveal_finish := INF
const REVEAL_BEAT := 1.0
const REVEAL_STEP := 0.4
const REVEAL_HOLD := 1.6

func start(seed_value := -1) -> void:
	if seed_value < 0:
		rng.randomize()
		seed_value = rng.randi() & 0x7fffffff
	match_seed = seed_value
	rng.seed = match_seed
	racers.clear()
	for id in FIELD:
		var r := Racer.new()
		r.id = id
		racers.append(r)
	if names.size() != NAMES.size():
		names.assign(NAMES)
	round_index = 0
	begin_round()

## Human slots from the lobby: [[peer, racer_id, name], ...]. Everything else stays AI.
func set_slots(slots: Array, my_peer: int) -> void:
	names.assign(NAMES)
	humans = 0
	for entry in slots:
		var slot := int(entry[1])
		names[slot] = String(entry[2]).to_upper().substr(0, 10)
		humans = maxi(humans, slot + 1)
		if int(entry[0]) == my_peer: local_id = slot
	names[0] = names[0] if humans > 1 else "YOU"

func label(id: int) -> String:
	return "YOU" if id == local_id and humans == 1 else names[id]

func set_intent(id: int, dir: Vector2i, draw: bool) -> void:
	var r := racer(id)
	if r != null:
		r.intent_dir = dir
		r.intent_draw = draw

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

func begin_round(shuffle := true) -> void:
	layout_rng.seed = hash([match_seed, round_index])
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
	# Shuffle spawn assignments from the layout rng so a guest can rebuild the same board.
	# The offset is drawn first so a guest handed the already-shuffled order can skip the shuffle.
	var offset := layout_rng.randi_range(0, perimeter.size() - 1)
	if shuffle:
		for i in range(racers.size() - 1, 0, -1):
			var j := layout_rng.randi_range(0, i)
			var tmp := racers[i]
			racers[i] = racers[j]
			racers[j] = tmp
	for i in racers.size():
		var r := racers[i]
		r.rail.clear()
		r.trail.clear()
		r.plan.clear()
		r.exposed = false
		r.harden = 0.0
		r.drive = 0.0
		r.acc = 0.0
		r.think = layout_rng.randf_range(0.3, 1.0)
		r.intent_dir = Vector2i.ZERO
		r.intent_draw = false
		r.want_harden = false
		r.want_drive = false
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
	reveal_time.clear()
	reveal_count = 0
	reveal_finish = INF
	rebuild()

func rebuild() -> void:
	owners_version += 1
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
	if r.id == local_id:
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
	setup_reveal()

func setup_reveal() -> void:
	reveal_order.clear()
	reveal_time.clear()
	reveal_count = 0
	reveal_finish = INF
	# Eliminated from the bottom up, then qualifiers from the top; the bubble (last in, first out)
	# waits behind a longer hold and lands as one group so neither side gives the other away.
	var cut := mini(CUTS[round_index], standings.size())
	for i in range(standings.size() - 1, cut, -1): reveal_order.append([i])
	for i in range(0, cut - 1): reveal_order.append([i])
	var bubble := [cut - 1]
	if cut < standings.size(): bubble.append(cut)
	reveal_order.append(bubble)
	refresh_fill()

func reveal_at(k: int) -> float:
	var t := REVEAL_BEAT + k * REVEAL_STEP
	if k == reveal_order.size() - 1: t += REVEAL_HOLD
	return t

func reveal_next() -> void:
	for slot in reveal_order[reveal_count]:
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
		if standings[i].id == local_id: return true
	return false

## Solo: the match ends when you are cut. Multiplayer: it runs on while any human is still in.
func advance() -> void:
	var anyone := false
	for i in mini(CUTS[round_index], standings.size()):
		if standings[i].id < humans: anyone = true
	if round_index == 2 or not anyone:
		start()
		return
	racers.assign(standings.slice(0, CUTS[round_index]))
	round_index += 1
	begin_round()

func poll_local_input() -> void:
	var d := Vector2i.ZERO
	for pair in [["move_up", Vector2i.UP], ["move_right", Vector2i.RIGHT], ["move_down", Vector2i.DOWN], ["move_left", Vector2i.LEFT]]:
		if Input.is_action_pressed(pair[0]): d = pair[1]
	set_intent(local_id, d, true)   # no draw key in this mode: leaving your land is the cut
	var me := racer(local_id)
	if me == null: return
	if Input.is_action_just_pressed("br_harden"): me.want_harden = true
	if Input.is_action_just_pressed("br_overdrive"): me.want_drive = true

func update(dt: float, human_input := true) -> bool:
	phase_time += dt
	notice_time = maxf(0.0, notice_time - dt)
	if human_input and Input.is_action_just_pressed("abort"): return true
	if phase == "ready":
		if human_input and (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("launch")):
			phase = "playing"
		return false
	if phase == "lobby": return false
	if phase == "results":
		while reveal_count < reveal_order.size() and phase_time >= reveal_at(reveal_count): reveal_next()
		if human_input and phase_time > 0.3 and (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("launch")):
			if reveal_complete(): advance()
			else: skip_reveal()
		return false
	if human_input: poll_local_input()
	remaining = maxf(0.0, remaining - dt)
	turn += 1
	for offset in racers.size():
		var r := racers[(turn + offset) % racers.size()]
		r.harden = maxf(0.0, r.harden - dt)
		r.drive = maxf(0.0, r.drive - dt)
		r.think -= dt
		if r.id < humans:
			if r.want_harden: ability(r, true)
			if r.want_drive: ability(r, false)
			r.want_harden = false
			r.want_drive = false
		else:
			if remaining < 18.0 and r.has_drive and r.exposed: ability(r, false)
			if remaining < 6.0 and r.has_harden and not r.exposed: ability(r, true)
		var speed := CUT_SPEED if r.exposed else SAFE_SPEED
		if r.drive > 0.0: speed *= 2.0
		r.acc = minf(r.acc + dt * speed, 2.0)
		while r.acc >= 1.0:
			r.acc -= 1.0
			if r.id < humans:
				if r.intent_dir != Vector2i.ZERO: step(r, r.intent_dir, r.intent_draw)
			else:
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

# ---------------------------------------------------------------------------
# Snapshots: the host encodes the whole live state; a guest applies it verbatim.
# ---------------------------------------------------------------------------
const PHASES := ["ready", "playing", "results", "lobby"]

func board_bytes() -> PackedByteArray:
	# 4 bits per cell: owner + 1 (0 = neutral). Q1 is 2856 cells, so 1428 bytes.
	var out := PackedByteArray()
	out.resize((owners.size() + 1) / 2)
	for i in owners.size():
		var v := owners[i] + 1
		if i % 2 == 0: out[i / 2] = v
		else: out[i / 2] |= v << 4
	return out

func encode_state(with_board: bool) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(1 if with_board else 0)
	b.put_64(match_seed)
	b.put_u8(round_index)
	b.put_u8(PHASES.find(phase))
	b.put_float(phase_time)
	b.put_float(remaining)
	b.put_float(hazard.x)
	b.put_float(hazard.y)
	b.put_u32(owners_version)
	b.put_u8(reveal_count)
	b.put_u8(racers.size())
	for r in racers: b.put_u8(r.id)
	for r in standings: b.put_u8(r.id)
	for r in racers:
		b.put_u8(r.pos.x)
		b.put_u8(r.pos.y)
		b.put_u8(DIRS.find(r.facing))
		b.put_u8(r.anchor.x)
		b.put_u8(r.anchor.y)
		b.put_u8((1 if r.exposed else 0) | (2 if r.has_harden else 0) | (4 if r.has_drive else 0))
		b.put_u16(int(r.harden * 100.0))
		b.put_u16(int(r.drive * 100.0))
		b.put_u8(mini(r.failures, 255))
		b.put_u16(r.biggest)
		b.put_u16(r.score)
		b.put_u16(r.trail.size())
		for c in r.trail:
			b.put_u8(c.x)
			b.put_u8(c.y)
	if with_board:
		b.put_data(board_bytes())
	return b.data_array

## Rebuild the racer list and board for a round the host has moved to. `ids` arrive in the
## host's already-shuffled order, so the layout shuffle is skipped and the rails line up.
func reset_round(seed_value: int, round_i: int, ids: PackedByteArray) -> void:
	match_seed = seed_value
	round_index = round_i
	var fresh: Array[Racer] = []
	for id in ids:
		var old := racer(id)
		var r := Racer.new()
		r.id = id
		if old != null and round_i > 0:
			r.has_harden = old.has_harden
			r.has_drive = old.has_drive
		fresh.append(r)
	racers = fresh
	begin_round(false)

func decode_state(bytes: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var with_board := b.get_u8() == 1
	var seed_value := b.get_64()
	var round_i := b.get_u8()
	var phase_i := b.get_u8()
	var p_time := b.get_float()
	var p_remaining := b.get_float()
	var hz := Vector2(b.get_float(), b.get_float())
	var version := b.get_u32()
	var remote_reveal := b.get_u8()
	var count := b.get_u8()
	var ids := PackedByteArray()
	for i in count: ids.append(b.get_u8())
	var order := PackedByteArray()
	for i in count: order.append(b.get_u8())
	var same := seed_value == match_seed and round_i == round_index and ids.size() == racers.size()
	if same:
		for i in count:
			if racers[i].id != ids[i]: same = false
	if not same:
		reset_round(seed_value, round_i, ids)
	var was_results := phase == "results"
	phase = PHASES[phase_i]
	phase_time = p_time
	remaining = p_remaining
	hazard = hz
	trails.fill(-1)
	var my_failures := racer(local_id).failures if racer(local_id) != null else 0
	for i in count:
		var r := racers[i]
		r.pos = Vector2i(b.get_u8(), b.get_u8())
		r.facing = DIRS[b.get_u8()]
		r.anchor = Vector2i(b.get_u8(), b.get_u8())
		var flags := b.get_u8()
		r.exposed = flags & 1 != 0
		r.has_harden = flags & 2 != 0
		r.has_drive = flags & 4 != 0
		r.harden = b.get_u16() / 100.0
		r.drive = b.get_u16() / 100.0
		r.failures = b.get_u8()
		r.biggest = b.get_u16()
		r.score = b.get_u16()
		var n := b.get_u16()
		r.trail.clear()
		for k in n:
			var c := Vector2i(b.get_u8(), b.get_u8())
			r.trail.append(c)
			trails[index(c)] = r.id
	var me := racer(local_id)
	if me != null and me.failures > my_failures:
		notice = "TRAIL HIT - BACK TO ANCHOR"
		notice_time = 1.6
	if with_board:
		var packed: PackedByteArray = b.get_data((owners.size() + 1) / 2)[1]
		for i in owners.size():
			var v: int = packed[i / 2] >> (4 * (i % 2)) & 15
			owners[i] = v - 1
		rebuild()
		owners_version = version   # after rebuild, which bumps it
		board_request_t = 0.0
	elif version != owners_version and board_request_t <= 0.0:
		board_request_t = 0.5   # ask again after a beat if the reliable reply is still in flight
		Net.request_board()
	# rebuild() re-derives scores from the board; the host's numbers and order still win.
	var by_id := {}
	for r in racers: by_id[r.id] = r
	standings.clear()
	for id in order: standings.append(by_id[id])
	if phase == "results":
		if not was_results or reveal_order.is_empty(): setup_reveal()
		while reveal_count < remote_reveal and reveal_count < reveal_order.size(): reveal_next()
	elif was_results:
		refresh_fill()

## Guest-side clock between snapshots so timers and the reveal animate smoothly.
func tick_guest(dt: float) -> void:
	phase_time += dt
	notice_time = maxf(0.0, notice_time - dt)
	board_request_t = maxf(0.0, board_request_t - dt)
	if phase == "playing": remaining = maxf(0.0, remaining - dt)

func text(lines: ScopeLines, value: String, pos: Vector2, font_size := 14, col := Color.WHITE, align := 0) -> void:
	VectorFont.draw(lines, value, pos, font_size, col, 0.0, 0.0, align)

func draw(lines: ScopeLines, fill: Sprite2D) -> void:
	if texture_dirty:
		territory_texture.update(territory_image)
		texture_dirty = false
	fill.texture = territory_texture
	fill.position = origin
	fill.scale = Vector2.ONE * CELL
	fill.visible = phase != "lobby"
	lines.rect(FRAME, Palette.DIM, 0.0, 0.0, 0.8)
	text(lines, "BATTLE ROYALE", Vector2(LX, 70), 22, Palette.CYAN)
	if phase == "lobby":
		draw_lobby(lines)
		return
	text(lines, LABELS[round_index], Vector2(LX, 116), 18, Palette.WHITE)
	text(lines, "%02d:%02d" % [ceili(remaining) / 60, ceili(remaining) % 60], Vector2(LX + COL_W, 116), 20, Palette.WHITE, 2)
	text(lines, "TOP %d %s" % [CUTS[round_index], "WIN" if round_index == 2 else "ADVANCE"], Vector2(LX, 146), 13, Palette.GREEN)
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
		if r.id == local_id:
			text(lines, "YOU", point(r.pos) + Vector2(0, -20), 10, Palette.WHITE, 1)
	var hp := origin + hazard * CELL
	lines.seg(hp - Vector2(6, 8), hp + Vector2(6, 8), Palette.MAGENTA, 0.0, 0.0, 1.8)
	text(lines, "STANDINGS" if phase == "results" else "CUTTERS", Vector2(RX, 70), 22, Palette.WHITE)
	if phase == "results":
		draw_reveal(lines)
	else:
		draw_roster(lines)
	var player := racer(local_id)
	if phase != "results":
		text(lines, "YOUR TERRITORY", Vector2(LX, 206), 13, Palette.DIM)
		text(lines, "%.1f%%" % percent(player), Vector2(LX + COL_W, 206), 16, Palette.CYAN, 2)
		text(lines, "Q HARDEN", Vector2(LX, 250), 12, Palette.CYAN if player.has_harden else Palette.DIM)
		text(lines, "E OVERDRIVE", Vector2(LX + 150, 250), 12, Palette.CYAN if player.has_drive else Palette.DIM)
		if player.harden > 0.0:
			text(lines, "HARDENED  %.1fS" % player.harden, Vector2(LX, 282), 13, Palette.WHITE)
		elif player.drive > 0.0:
			text(lines, "OVERDRIVE  %.1fS" % player.drive, Vector2(LX, 282), 13, Palette.WHITE)
		elif player.exposed:
			text(lines, "CUTTING", Vector2(LX, 282), 13, Palette.ORANGE)
	text(lines, "ARROWS MOVE", Vector2(LX, 786), 12, Palette.WHITE)
	text(lines, "LEAVE YOUR LAND TO CUT", Vector2(LX, 810), 12, Palette.WHITE)
	text(lines, "ESC MENU", Vector2(LX, 846), 11, Palette.DIM)
	if notice_time > 0.0: text(lines, notice, Vector2(FRAME.get_center().x, 740), 12, Palette.YELLOW, 1)
	if phase != "playing":
		var title := "SURVEYORS ONLY - CLOSE A LOOP TO CLAIM"
		var sub := "ENTER START - TOP %d %s" % [CUTS[round_index], "WINS" if round_index == 2 else "ADVANCE"]
		if guest: sub = "WAITING FOR THE HOST"
		elif humans == 1 and Net.is_offline(): sub += "   H HOST FOR FRIENDS   J JOIN"
		if phase == "results":
			title = "QUALIFIED" if qualified() else "ELIMINATED"
			if round_index == 2: title = "CHAMPION" if qualified() else "%s WINS" % label(standings[0].id)
			sub = "ENTER NEXT ROUND" if qualified() and round_index < 2 else "ENTER PLAY AGAIN"
			if humans > 1 and not qualified() and round_index < 2: sub = "ENTER WATCH THE NEXT ROUND"
			if guest: sub = "WAITING FOR THE HOST"
			if not reveal_complete():
				title = "TIME" if phase_time < REVEAL_BEAT else "FINAL STANDINGS"
				sub = "WAITING FOR THE HOST" if guest else "ENTER SKIP"
		if Net.pending(): sub = "OPENING A STEAM LOBBY..."
		text(lines, title, Vector2(FRAME.get_center().x, 130), 18, Palette.YELLOW, 1)
		text(lines, sub, Vector2(FRAME.get_center().x, 166), 12, Palette.WHITE, 1)
	text(lines, "H HARDEN   O OVERDRIVE", Vector2(RX, 786), 11, Palette.DIM)
	text(lines, "TIES: BIGGEST CAPTURE,", Vector2(RX, 816), 9, Palette.DIM)
	text(lines, "FEWEST FAILS, DRAW", Vector2(RX, 834), 9, Palette.DIM)

## Mid-round panel: every cutter in a fixed order with charges, no ranks, no cut line, no percentages.
func draw_roster(lines: ScopeLines) -> void:
	text(lines, "H  O", Vector2(RX + COL_W - 44, 110), 11, Palette.DIM)
	for i in roster.size():
		var r := roster[i]
		var y := 156.0 + i * 43.0
		var col := color(r.id)
		if r.id == local_id: lines.rect(Rect2(RX - 8, y - 8, COL_W + 16, 33), Palette.CYAN, 0.0, 0.0, 0.8)
		text(lines, "%s%s" % ["> " if r.id == local_id else "", label(r.id)], Vector2(RX, y), 16, col)
		if r.harden > 0.0:
			text(lines, "HARD %.1fS" % r.harden, Vector2(RX + 128, y + 2), 10, Palette.WHITE)
		elif r.drive > 0.0:
			text(lines, "DRIVE %.1fS" % r.drive, Vector2(RX + 128, y + 2), 10, Palette.WHITE)
		elif r.exposed:
			text(lines, "CUTTING", Vector2(RX + 128, y + 2), 10, Palette.DIM)
		draw_charges(lines, r, y)

func draw_charges(lines: ScopeLines, r: Racer, y: float) -> void:
	var col := color(r.id)
	for a in 2:
		var available := r.has_harden if a == 0 else r.has_drive
		var active := r.harden > 0.0 if a == 0 else r.drive > 0.0
		var pos := Vector2(RX + COL_W - 40 + a * 28, y + 6)
		lines.circle(pos, 5, Palette.WHITE if active else (col if available else Palette.DIM), 4)
		if available or active: lines.circle(pos, 2, col, 4)

## Buzzer panel: names wait in the left column, then slide one by one into their ranked slot.
func draw_reveal(lines: ScopeLines) -> void:
	var cut := mini(CUTS[round_index], standings.size())
	for i in standings.size():
		var y := 156.0 + i * 43.0
		if i == cut and phase_time >= REVEAL_BEAT:
			lines.seg(Vector2(RX - 8, y - 16), Vector2(RX + COL_W + 8, y - 16), Palette.RED)
		text(lines, "%02d" % (i + 1), Vector2(RX, y), 16, Palette.DIM)
	var waiting := 0
	for r in roster:
		if not revealed(r.id) or phase_time - reveal_time[r.id] < 0.5: waiting += 1
	if waiting > 0: text(lines, "WAITING", Vector2(LX, 206), 13, Palette.DIM)
	for i in roster.size():
		var r := roster[i]
		var col := color(r.id)
		var from := Vector2(LX, 240.0 + i * 30.0)
		if not revealed(r.id):
			col.a = 0.45
			text(lines, label(r.id), from, 14, col)
			continue
		var rank := standings.find(r)
		var to := Vector2(RX + 44, 156.0 + rank * 43.0)
		var t: float = clampf((phase_time - reveal_time[r.id]) / 0.5, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		var pos := from.lerp(to, t)
		if r.id == local_id and t >= 1.0:
			lines.rect(Rect2(RX - 8, to.y - 8, COL_W + 16, 33), Palette.CYAN, 0.0, 0.0, 0.8)
		text(lines, "%s%s" % ["> " if r.id == local_id else "", label(r.id)], pos, int(lerpf(14.0, 16.0, t)), col)
		if t >= 1.0:
			var pct_col := Palette.GREEN if rank < cut else Palette.RED
			text(lines, "%.1f%%" % percent(r), Vector2(RX + COL_W, to.y), 14, pct_col, 2)

## Friends lobby: who is here, how to invite, and who presses Enter.
func draw_lobby(lines: ScopeLines) -> void:
	var cx := FRAME.get_center().x
	text(lines, "FRIENDS LOBBY", Vector2(cx, 130), 18, Palette.YELLOW, 1)
	var code: String = lobby.get("code", "")
	if code != "":
		text(lines, "INVITE CODE", Vector2(cx, 300), 12, Palette.DIM, 1)
		text(lines, code, Vector2(cx, 330), 20 if code.length() < 20 else 14, Palette.WHITE, 1)
		text(lines, "COPIED TO CLIPBOARD - FRIENDS PRESS J WITH IT COPIED", Vector2(cx, 364), 10, Palette.DIM, 1)
	var lobby_names: Array = lobby.get("names", [])
	for i in lobby_names.size():
		var y := 430.0 + i * 36.0
		var col := color(i)
		text(lines, "%d  %s" % [i + 1, String(lobby_names[i]).to_upper()], Vector2(cx, y), 16, col, 1)
	for i in range(lobby_names.size(), 4):
		text(lines, "%d  ---" % (i + 1), Vector2(cx, 430.0 + i * 36.0), 16, Palette.DIM, 1)
	text(lines, "%d AI CUTTERS FILL THE REST" % (FIELD - maxi(1, lobby_names.size())), Vector2(cx, 590), 10, Palette.DIM, 1)
	var message: String = lobby.get("message", "")
	if message != "": text(lines, message, Vector2(cx, 640), 12, Palette.YELLOW, 1)
	if lobby.get("host", false):
		text(lines, "ENTER START THE MATCH" if lobby_names.size() > 1 else "WAITING FOR FRIENDS - ENTER STARTS ANYWAY", Vector2(cx, 166), 12, Palette.WHITE, 1)
		if lobby.get("overlay", false): text(lines, "I STEAM INVITE OVERLAY", Vector2(cx, 700), 11, Palette.CYAN, 1)
	else:
		text(lines, "WAITING FOR THE HOST TO START", Vector2(cx, 166), 12, Palette.WHITE, 1)
	text(lines, "ESC LEAVE", Vector2(LX, 846), 11, Palette.DIM)
