extends RefCounted
## One AI cutter competing for the void, ported from Battle Royale's planner. It sees the
## board only through the host's callables, so the host's cell model stays private: the
## host decides what is open, what is solid, and what a completed loop encloses.
const DIRS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const LAND_SPEED := 9.0 # Cells per second on its own land; playtest values.
const CUT_SPEED := 6.0
const ATTEMPTS := 24

var size := Vector2i.ZERO
var rng: RandomNumberGenerator
var owner_of: Callable # (Vector2i) -> int: 1 mine, 0 open void, -1 solid or player land.
var is_solid: Callable # (Vector2i) -> bool
var player_trail_at: Callable # (Vector2i) -> bool
var on_capture: Callable # (Array[Vector2i] loop) -> void: the host converts the loop and its enclosure.
var on_cross_player_trail: Callable # (Vector2i) -> void
var on_fail: Callable # () -> void

var pos := Vector2i.ZERO
var facing := Vector2i.UP
var anchor := Vector2i.ZERO
var trail: Array[Vector2i] = []
var trail_mask := PackedByteArray()
var plan: Array[Vector2i] = []
var owned: Array[Vector2i] = []
var exposed := false
var acc := 0.0
var think := 0.0
var alive := true
var speed_scale := 1.0

func setup(grid: Vector2i, random: RandomNumberGenerator, callbacks: Dictionary) -> void:
	size = grid
	rng = random
	owner_of = callbacks.owner_of
	is_solid = callbacks.is_solid
	player_trail_at = callbacks.player_trail_at
	on_capture = callbacks.on_capture
	on_cross_player_trail = callbacks.on_cross_player_trail
	on_fail = callbacks.on_fail
	trail_mask.resize(size.x * size.y)
	trail_mask.fill(0)

func index(c: Vector2i) -> int:
	return c.y * size.x + c.x

func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y

func trail_at(c: Vector2i) -> bool:
	return inside(c) and trail_mask[index(c)] == 1

func nearest_owned(from: Vector2i) -> Vector2i:
	var best := from
	var distance := 1000000
	for c in owned:
		var d := absi(c.x - from.x) + absi(c.y - from.y)
		if d < distance:
			distance = d
			best = c
	return best

func clear_trail() -> void:
	for c in trail:
		trail_mask[index(c)] = 0
	trail.clear()

## Something cut the line: back to the anchor, or the nearest land left if that was taken.
func fail() -> void:
	clear_trail()
	pos = nearest_owned(anchor)
	exposed = false
	plan.clear()
	think = 0.5
	on_fail.call()

func tick(dt: float) -> void:
	if not alive or owned.is_empty():
		return
	think = maxf(0.0, think - dt)
	var speed := (CUT_SPEED if exposed else LAND_SPEED) * speed_scale
	acc = minf(acc + dt * speed, 2.0) # Never bursts after a freeze.
	while acc >= 1.0:
		acc -= 1.0
		if plan.is_empty() and think <= 0.0:
			plan_route()
			think = rng.randf_range(0.4, 1.0)
		if plan.is_empty():
			return
		var target: Vector2i = plan.pop_front()
		var d := target - pos
		# A plan that no longer lines up with the board is thrown away, not repaired.
		if absi(d.x) + absi(d.y) != 1 or not step(d):
			plan.clear()

func step(d: Vector2i) -> bool:
	var next := pos + d
	if is_solid.call(next):
		return false
	var i := index(next)
	if trail_mask[i] == 1:
		# Retracing the last step leaves a corner; any other self-cross fails.
		if trail.size() >= 2 and next == trail[trail.size() - 2]:
			trail_mask[index(trail.pop_back())] = 0
			pos = next
			return true
		fail()
		return false
	var mine: bool = owner_of.call(next) == 1
	if not exposed and not mine:
		anchor = pos
		exposed = true
	if player_trail_at.call(next):
		on_cross_player_trail.call(next)
	pos = next
	facing = d
	if exposed:
		if mine:
			var loop := trail.duplicate()
			clear_trail()
			exposed = false
			plan.clear()
			on_capture.call(loop)
		else:
			trail.append(next)
			trail_mask[i] = 1
	return true

func plan_route() -> void:
	plan.clear()
	if exposed:
		plan_home()
		return
	# One walk over the whole territory serves every candidate below.
	var parent := bfs_owned()
	var best_value := -1.0
	var best: Array[Vector2i] = []
	for attempt in ATTEMPTS:
		var start_cell: Vector2i = owned[rng.randi_range(0, owned.size() - 1)]
		if parent[index(start_cell)] < 0:
			continue # Another island: unreachable on foot.
		var outward: Vector2i = DIRS[rng.randi_range(0, 3)]
		if owner_of.call(start_cell + outward) != 0:
			continue # Must face open void.
		var tangent := Vector2i(-outward.y, outward.x) * (1 if rng.randf() < 0.5 else -1)
		var depth := rng.randi_range(4, 14)
		var width := rng.randi_range(3, 10)
		if owner_of.call(start_cell + tangent * width) != 1:
			continue # The landing edge must be mine.
		var path: Array[Vector2i] = []
		var c := start_cell
		var valid := true
		for leg in [[outward, depth], [tangent, width], [-outward, depth]]:
			for k in int(leg[1]):
				c += Vector2i(leg[0])
				if is_solid.call(c):
					valid = false
				path.append(c)
		if not valid:
			continue
		# Only open void is worth anything: player land is solid and never converts.
		var value := 0.0
		for a in range(1, depth + 1):
			for b in range(width + 1):
				if owner_of.call(start_cell + outward * a + tangent * b) == 0:
					value += 1.0
		value *= rng.randf_range(0.7, 1.3)
		if value > best_value:
			best_value = value
			best = walk_back(parent, start_cell)
			best.append_array(path)
	plan = best

## Shortest legal route back onto my land, avoiding my own line.
func plan_home() -> void:
	var parent := PackedInt32Array()
	parent.resize(size.x * size.y)
	parent.fill(-1)
	var queue := PackedInt32Array()
	queue.append(index(pos))
	parent[index(pos)] = index(pos)
	var head := 0
	var target := -1
	while head < queue.size():
		var i := queue[head]
		head += 1
		var c := Vector2i(i % size.x, i / size.x)
		if owner_of.call(c) == 1:
			target = i
			break
		for d in DIRS:
			var n: Vector2i = c + d
			if not inside(n) or is_solid.call(n):
				continue
			var ni := index(n)
			if trail_mask[ni] == 1 or parent[ni] >= 0:
				continue
			parent[ni] = i
			queue.append(ni)
	if target < 0:
		return
	plan = walk_back(parent, Vector2i(target % size.x, target / size.x))

func bfs_owned() -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(size.x * size.y)
	parent.fill(-1)
	if not inside(pos):
		return parent
	var queue := PackedInt32Array()
	queue.append(index(pos))
	parent[index(pos)] = index(pos)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var c := Vector2i(i % size.x, i / size.x)
		for d in DIRS:
			var n: Vector2i = c + d
			if not inside(n):
				continue
			var ni := index(n)
			if parent[ni] >= 0 or owner_of.call(n) != 1:
				continue
			parent[ni] = i
			queue.append(ni)
	return parent

## The path from just after pos up to and including target, or empty when unreachable.
func walk_back(parent: PackedInt32Array, target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var i := index(target)
	if parent[i] < 0:
		return path
	var start := index(pos)
	while i != start:
		path.push_front(Vector2i(i % size.x, i / size.x))
		i = parent[i]
	return path
