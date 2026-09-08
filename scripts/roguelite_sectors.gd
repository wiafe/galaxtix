extends RefCounted
## Jump silhouettes fitted into Roguelite's wider viewport; cell size never changes.
const CORRUPTION_SECTOR := 8
const LENGTH := 8

static func capture_goal(depth: int) -> int:
	return clampi(60 + (depth - 1) * 5, 60, 90)

const LIST := [
	{"name": "OPEN FIELD", "source": "helix", "level": 1, "source_half": Vector2(26, 26), "half": Vector2(26, 26)},
	{"name": "PYLONS", "source": "belt", "level": 1, "source_half": Vector2(40, 40), "half": Vector2(30, 30)},
	{"name": "NOTCHED FIELD", "source": "belt", "level": 2, "source_half": Vector2(46, 34), "half": Vector2(34, 34)},
	{"name": "FOUR PILLARS", "source": "belt", "level": 1, "source_half": Vector2(40, 40), "half": Vector2(34, 34)},
	{"name": "SLICES", "source": "belt", "level": 6, "source_half": Vector2(50, 50), "half": Vector2(34, 34)},
	{"name": "NOTCHES", "source": "belt", "level": 2, "source_half": Vector2(46, 34), "half": Vector2(40, 34)},
	{"name": "BRIDGE", "source": "belt", "level": 4, "source_half": Vector2(50, 40), "half": Vector2(40, 34)},
	{"name": "ISLAND", "source": "belt", "level": 5, "source_half": Vector2(48, 48), "half": Vector2(40, 34)},
]

static func stage(level: int) -> Dictionary:
	return LIST[clampi(level - 1, 0, LIST.size() - 1)]

static func holes(level: int, size: Vector2i) -> Array:
	# Authored Jump-style pylons; every detached block gets a walkable inner rail.
	var blocks: Array = []
	match level:
		2: blocks = [Rect2i(-17, -10, 8, 8), Rect2i(9, 2, 8, 8)]
		3: blocks = [Rect2i(-24, -4, 6, 8), Rect2i(18, -4, 6, 8)]
		4:
			for x in [-24, 16]:
				for y in [-24, 16]: blocks.append(Rect2i(x, y, 8, 8))
		6: blocks = [Rect2i(-30, -5, 8, 10), Rect2i(22, -5, 8, 10)]
		7: blocks = [Rect2i(-34, -20, 8, 8), Rect2i(26, -20, 8, 8)]
		8: blocks = [Rect2i(-12, -12, 24, 24)]
	var result: Array = []
	for block: Rect2i in blocks:
		result.append(Rect2i(block.position + size / 2, block.size))
	return result

static func anomaly_count(depth: int, shape_id: int) -> int:
	var count := 1 if depth <= 2 else (2 if depth <= 5 else 3)
	return maxi(count, 2) if shape_id in [3, 5, 6, 7] else count

## Shape IDs are independent of encounter depth; only depth controls enemy progression.
static func make_route(random: RandomNumberGenerator, length := LENGTH) -> Array:
	var route: Array = []
	for depth in range(1, length + 1):
		var row: Array = [{"depth": depth, "stage": depth, "kind": "survey"}]
		if depth not in [1, 4, length]:
			var pool := [2, 3] if depth <= 3 else [4, 5, 6, 7]
			pool.erase(depth)
			var alternate: int = pool[random.randi_range(0, pool.size() - 1)]
			row.append({"depth": depth, "stage": alternate, "kind": "salvage" if random.randf() < 0.5 else "repair"})
		route.append(row)
	return route

static func draft_milestones(area: int) -> Array[int]:
	if area < 3800: return [35]
	if area < 4400: return [25, 55]
	return [20, 40, 60]
