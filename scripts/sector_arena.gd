class_name SectorArena
extends RefCounted
## Fixed 104-cell frame, authored playable silhouettes, plus rock holes with a one-cell walkable rim.
##
## Two ideas from the Fillit teardown (see docs/field-shapes.md):
##  - carved outlines: the silhouette decides which cells are void; everything outside is rock and the
##    rim (rim + 1 cells thick) hugs the carve, so the coast follows crosses, bridges and notches.
##  - inner rails: rock that does not touch the outer rock (pillars, a moat's core) gets a one-cell
##    claimed ring. It is an island of coast: you can cut to it, ride it, and cut from it, and a trail
##    that reaches it without enclosing anything becomes a claimed bridge (the claim flood runs from
##    the Anomaly, so an unenclosed trail simply joins the coast).
const N := 104
static var cache := {}

static func enemy_mult(galaxy: String, level: int) -> float:
	return [0.5, 0.58, 0.66, 0.74, 0.80, 0.87, 0.94, 1.0][level - 1] if galaxy == "helix" and level >= 1 and level <= 8 else 1.0

static func anomaly_size_mult(galaxy: String, level: int) -> float:
	return [0.5, 0.58, 0.66, 0.74, 0.80, 0.87, 0.94, 1.0][level - 1] if galaxy == "helix" and level >= 1 and level <= 8 else 1.0

## Which galaxies run through the arena builder at which sectors. Helix carves 1..8; the Belt
## carves every sector (endless included) so its pillars always carry a rail.
static func carved(galaxy: String, level: int) -> bool:
	match galaxy:
		"helix": return level <= 8
		"belt": return true
	return false

## The playable silhouette, in cell coordinates. dx/dy are distances from the centre.
static func contains_cell(galaxy: String, level: int, x: int, y: int) -> bool:
	var sx := x + 0.5 - N * 0.5
	var sy := y + 0.5 - N * 0.5
	var dx := absf(sx)
	var dy := absf(sy)
	match galaxy:
		"helix":
			match level:
				1: return dx < 26 and dy < 26
				2: return dx < 34 and dy < 24
				3: return dx < 34 and dy < 34
				4: return dx * dx + dy * dy < 42 * 42
				5: return dx < 48 and dy < 48 and (dx < 20 or dy < 20)
				6: return dx < 50 and dy < 38
				7: return dx < 50 and dy < 50
			return true
		"belt":
			match level:
				1: return dx < 40 and dy < 40                                      # square, two railed pillars
				2: return dx < 46 and dy < 34 and not (dy > 20 and dx < 10)         # notches bitten from top and bottom
				3: return (dx < 48 and dy < 20) or (dx < 20 and dy < 48)           # the plus
				4: return (dx >= 12 and dx < 50 and dy < 40) or (dx < 12 and dy < 12)   # two halves and a narrow bridge
				5: return dx < 48 and dy < 48                                      # moat: the core hole comes from the shape list
				6: return dx < 50 and dy < 50 and not (sy < 12 and (absf(sx - 18) < 4 or absf(sx + 18) < 4))   # slices from the top edge
				7: return dx < 50 and dy < 50 and not (dx > 30 and dy > 30)        # corners bitten off
			return true
	return true

## True when the rectangle (grown by `grow`) sits entirely inside the silhouette.
static func rect_inside(galaxy: String, level: int, r: Rect2i, grow: int) -> bool:
	var rr := r.grow(grow)
	for y in range(rr.position.y, rr.end.y):
		for x in range(rr.position.x, rr.end.x):
			if x < 0 or y < 0 or x >= N or y >= N or not contains_cell(galaxy, level, x, y):
				return false
	return true

static func build(level: int, rim: int, galaxy := "helix", holes: Array = []) -> Dictionary:
	var lvl := clampi(level, 1, 9)
	var key := "%s:%d:%d:%s" % [galaxy, lvl, clampi(rim, 0, 12), str(holes)]
	if cache.has(key):
		return cache[key]
	var rock := PackedByteArray()
	rock.resize(N * N)
	for y in N:
		for x in N:
			var solid := not contains_cell(galaxy, lvl, x, y)
			if not solid:
				for h in holes:
					if (h as Rect2i).has_point(Vector2i(x, y)):
						solid = true
						break
			rock[y * N + x] = 1 if solid else 0
	# Outer rock is every rock cell 8-connected to the frame; the rest are holes with their own rail.
	var outer := PackedByteArray()
	outer.resize(N * N)
	var queue := PackedInt32Array()
	for i in N * N:
		var x := i % N
		var y := i / N
		if rock[i] == 1 and (x == 0 or y == 0 or x == N - 1 or y == N - 1):
			outer[i] = 1
			queue.append(i)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		for o in neighbours(index):
			if rock[o] == 1 and outer[o] == 0:
				outer[o] = 1
				queue.append(o)
	# Distance from the outer rock (frame cells count as 1) grows the thick outer rim.
	var distance := PackedInt32Array()
	distance.resize(N * N)
	distance.fill(-1)
	queue.clear()
	for i in N * N:
		if outer[i] == 1:
			distance[i] = 0
			queue.append(i)
	for i in N * N:
		var x := i % N
		var y := i / N
		if (x == 0 or y == 0 or x == N - 1 or y == N - 1) and distance[i] < 0:
			distance[i] = 1
			queue.append(i)
	head = 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		for o in neighbours(index):
			if distance[o] < 0:
				distance[o] = distance[index] + 1
				queue.append(o)
	# Distance from hole rock: exactly one cell of rail, whatever the rim upgrade says.
	var hole_distance := PackedInt32Array()
	hole_distance.resize(N * N)
	hole_distance.fill(-1)
	queue.clear()
	for i in N * N:
		if rock[i] == 1 and outer[i] == 0:
			hole_distance[i] = 0
			queue.append(i)
	head = 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		if hole_distance[index] >= 1:
			continue
		for o in neighbours(index):
			if hole_distance[o] < 0 and rock[o] == 0:
				hole_distance[o] = hole_distance[index] + 1
				queue.append(o)
	var mask := PackedByteArray()
	mask.resize(N * N)
	var free_cells: Array[Vector2i] = []
	var base_free := 0
	for i in N * N:
		if rock[i] == 1:
			mask[i] = 0
		elif distance[i] <= clampi(rim, 0, 12) + 1 or hole_distance[i] == 1:
			mask[i] = 1
		else:
			mask[i] = 2
		if rock[i] == 0 and distance[i] > 1:
			base_free += 1
		if mask[i] == 2:
			free_cells.append(Vector2i(i % N, i / N))
	var start := Vector2i(N / 2, 0)
	for y in N:
		if mask[y * N + N / 2] == 2:
			start.y = y - 1
			break
	var outline := PackedVector2Array()
	# Merge straight runs to keep circular and plus previews inexpensive.
	for axis in 2:
		for a in range(N + 1):
			var begin := -1
			for b in range(N + 1):
				var edge := false
				if b < N:
					edge = is_free(mask, b, a - 1) != is_free(mask, b, a) if axis == 0 else is_free(mask, a - 1, b) != is_free(mask, a, b)
				if edge and begin < 0:
					begin = b
				elif not edge and begin >= 0:
					outline.append(Vector2(begin, a) if axis == 0 else Vector2(a, begin))
					outline.append(Vector2(b, a) if axis == 0 else Vector2(a, b))
					begin = -1
	var result := {"mask": mask, "distance": distance, "free_cells": free_cells, "base_free": base_free, "start": start, "outline": outline}
	cache[key] = result
	return result

static func neighbours(index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x := index % N
	var y := index / N
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < N and ny < N:
				out.append(ny * N + nx)
	return out

static func is_free(mask: PackedByteArray, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < N and y < N and mask[y * N + x] == 2
