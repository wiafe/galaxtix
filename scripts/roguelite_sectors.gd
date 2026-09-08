extends RefCounted
## Jump silhouettes fitted into Roguelite's wider viewport; cell size never changes.
const CORRUPTION_SECTOR := 8
const LENGTH := 8
const LIST := [
	{"name": "OPEN FIELD", "source": "helix", "level": 1, "source_half": Vector2(26, 26), "half": Vector2(26, 26)},
	{"name": "WIDE FIELD", "source": "helix", "level": 2, "source_half": Vector2(34, 24), "half": Vector2(34, 24)},
	{"name": "LARGE FIELD", "source": "helix", "level": 3, "source_half": Vector2(34, 34), "half": Vector2(34, 34)},
	{"name": "OVAL", "source": "helix", "level": 4, "source_half": Vector2(42, 42), "half": Vector2(60, 32)},
	{"name": "CROSS", "source": "helix", "level": 5, "source_half": Vector2(48, 48), "half": Vector2(80, 34)},
	{"name": "NOTCHES", "source": "belt", "level": 2, "source_half": Vector2(46, 34), "half": Vector2(80, 34)},
	{"name": "BRIDGE", "source": "belt", "level": 4, "source_half": Vector2(50, 40), "half": Vector2(80, 34)},
	{"name": "ISLAND", "source": "belt", "level": 5, "source_half": Vector2(48, 48), "half": Vector2(80, 34)},
]

static func stage(level: int) -> Dictionary:
	return LIST[clampi(level - 1, 0, LIST.size() - 1)]

static func holes(level: int, size: Vector2i) -> Array:
	if level < LENGTH: return []
	# Jump's moat core, fitted to the same wide footprint as its outer coast.
	return [Rect2i(Vector2i(size.x / 2 - 20, size.y / 2 - 9), Vector2i(40, 18))]
