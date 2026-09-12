extends RefCounted
## A closed cubed-sphere surface. Four reciprocal neighbours per tile, including
## face seams: there are no rectangular wrap shortcuts or polar singularities.
const FREE := 0
const CLAIMED := 1
const TRAIL := 2
const ROCK := 3
const NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
const AXES_U := [Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.LEFT]
const AXES_V := [Vector3.DOWN, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD, Vector3.DOWN, Vector3.DOWN]
var size := 24
var cells := PackedByteArray()
var directions := PackedVector3Array()
var neighbours: Array[PackedInt32Array] = []
var weights := PackedFloat64Array()
var total_area := 0.0

func build(resolution := 24) -> void:
	size = resolution
	cells.resize(6 * size * size)
	cells.fill(FREE)
	directions.resize(cells.size())
	weights.resize(cells.size())
	neighbours.resize(cells.size())
	total_area = 0.0
	for face in 6:
		for y in size:
			for x in size:
				var i := index(face, x, y)
				directions[i] = point(face, x + 0.5, y + 0.5)
				var a := point(face, x, y)
				var b := point(face, x + 1, y)
				var c := point(face, x + 1, y + 1)
				var d := point(face, x, y + 1)
				weights[i] = triangle_area(a, b, c) + triangle_area(a, c, d)
				total_area += weights[i]
				var adjacent := PackedInt32Array()
				for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var nx: int = x + offset.x
					var ny: int = y + offset.y
					if nx >= 0 and ny >= 0 and nx < size and ny < size:
						adjacent.append(index(face, nx, ny))
					else:
						# Cross infinitesimally beyond the edge. Projecting a full cell
						# beyond it would skip neighbours near the cube's corners.
						var px := clampf(nx + 0.5, -0.001, size + 0.001)
						var py := clampf(ny + 0.5, -0.001, size + 0.001)
						adjacent.append(cell_at(point(face, px, py)))
				neighbours[i] = adjacent

func index(face: int, x: int, y: int) -> int:
	return face * size * size + y * size + x

func point(face: int, x: float, y: float) -> Vector3:
	return (NORMALS[face] + AXES_U[face] * (x * 2.0 / size - 1.0) + AXES_V[face] * (y * 2.0 / size - 1.0)).normalized()

func cell_at(direction: Vector3) -> int:
	var face := 0
	var best := -INF
	for f in 6:
		var amount: float = direction.dot(NORMALS[f])
		if amount > best:
			best = amount
			face = f
	var plane := direction / best
	var x := clampi(int((plane.dot(AXES_U[face]) + 1.0) * 0.5 * size), 0, size - 1)
	var y := clampi(int((plane.dot(AXES_V[face]) + 1.0) * 0.5 * size), 0, size - 1)
	return index(face, x, y)

func triangle_area(a: Vector3, b: Vector3, c: Vector3) -> float:
	return 2.0 * atan2(absf(a.dot(b.cross(c))), 1.0 + a.dot(b) + b.dot(c) + c.dot(a))

func neighbour_toward(cell: int, tangent: Vector3) -> int:
	var up := directions[cell]
	var chosen := -1
	var score := -INF
	for next in neighbours[cell]:
		var delta := directions[next] - up
		delta = (delta - up * delta.dot(up)).normalized()
		var alignment := delta.dot(tangent)
		if alignment > score:
			score = alignment
			chosen = next
	return chosen

func coast(cell: int) -> bool:
	if cells[cell] != CLAIMED: return false
	for next in neighbours[cell]:
		if cells[next] == FREE: return true
	return false

func claimable(seeds: PackedInt32Array) -> PackedInt32Array:
	var seen := PackedByteArray()
	seen.resize(cells.size())
	var queue := PackedInt32Array()
	for seed_cell in seeds:
		if seed_cell >= 0 and seed_cell < cells.size() and cells[seed_cell] == FREE and not seen[seed_cell]:
			seen[seed_cell] = 1
			queue.append(seed_cell)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		for next in neighbours[i]:
			if cells[next] == FREE and not seen[next]:
				seen[next] = 1
				queue.append(next)
	var result := PackedInt32Array()
	for i in cells.size():
		if cells[i] == FREE and not seen[i]: result.append(i)
	return result

func area(indices: PackedInt32Array) -> float:
	var result := 0.0
	for i in indices: result += weights[i]
	return result
