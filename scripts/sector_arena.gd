class_name SectorArena
extends RefCounted
## Fixed 104-cell frame, authored playable silhouettes. Distances form a walkable inner rim.
const N := 104
static var cache := {}

static func enemy_mult(galaxy: String, level: int) -> float:
	return [0.5, 0.58, 0.66, 0.74, 0.80, 0.87, 0.94, 1.0][level - 1] if galaxy == "helix" and level >= 1 and level <= 8 else 1.0

static func anomaly_size_mult(galaxy: String, level: int) -> float:
	return [0.5, 0.58, 0.66, 0.74, 0.80, 0.87, 0.94, 1.0][level - 1] if galaxy == "helix" and level >= 1 and level <= 8 else 1.0

static func contains_cell(level: int, x: int, y: int) -> bool:
	var dx := absf(x + 0.5 - N * 0.5)
	var dy := absf(y + 0.5 - N * 0.5)
	match level:
		1: return dx < 26 and dy < 26
		2: return dx < 34 and dy < 24
		3: return dx < 34 and dy < 34
		4: return dx * dx + dy * dy < 42 * 42
		5: return dx < 48 and dy < 48 and (dx < 20 or dy < 20)
		6: return dx < 50 and dy < 38
		7: return dx < 50 and dy < 50
	return true

static func build(level: int, rim: int) -> Dictionary:
	var key := Vector2i(clampi(level, 1, 8), clampi(rim, 0, 12))
	if cache.has(key):
		return cache[key]
	var distance := PackedInt32Array()
	distance.resize(N * N)
	distance.fill(-1)
	var queue := PackedInt32Array()
	for y in N:
		for x in N:
			if not contains_cell(key.x, x, y):
				distance[y * N + x] = 0
				queue.append(y * N + x)
	for y in N:
		for x in N:
			if (x == 0 or y == 0 or x == N - 1 or y == N - 1) and distance[y * N + x] < 0:
				distance[y * N + x] = 1
				queue.append(y * N + x)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var x := index % N
		var y := index / N
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx >= 0 and ny >= 0 and nx < N and ny < N and distance[ny * N + nx] < 0:
					distance[ny * N + nx] = distance[index] + 1
					queue.append(ny * N + nx)
	var mask := PackedByteArray()
	mask.resize(N * N)
	var free_cells: Array[Vector2i] = []
	var base_free := 0
	for i in N * N:
		mask[i] = 0 if distance[i] == 0 else (1 if distance[i] <= key.y + 1 else 2)
		if distance[i] > 1:
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

static func is_free(mask: PackedByteArray, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < N and y < N and mask[y * N + x] == 2
