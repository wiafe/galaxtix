@tool
class_name MapDefinition
extends Resource
const EDITABLE := Rect2i(0, 18, 160, 68) # Keep the gameplay HUD bands clear.
## Roguelite map source. Disabled overrides retain the procedural game's behavior.
@export var map_id := ""
@export var title := ""
@export var sector := 1 # Arena shape, independent of encounter depth.
@export var grid_size := Vector2i(160, 104)
@export var override_terrain := false
@export var rock := PackedByteArray()
@export var override_start := false
@export var player_start := Vector2i.ZERO
@export var override_enemies := false
## kind, cell, axis. Sparx markers spawn immediately and replace the timed wave.
@export var enemies: Array[Dictionary] = []
var _arena_cache := {}

func arena(rim := 0) -> Dictionary:
	if not _arena_cache.has(rim):
		_arena_cache[rim] = SectorArena.from_rock(rock, grid_size, rim, true)
	return _arena_cache[rim]

func invalidate() -> void:
	_arena_cache.clear()
	emit_changed()

func rock_rectangles() -> Array:
	# Only hatch rock inside the playable bounding box; merge equal runs vertically.
	var bounds := Rect2i()
	var first := true
	for cell: Vector2i in arena().free_cells:
		if first:
			bounds = Rect2i(cell, Vector2i.ONE)
			first = false
		else: bounds = bounds.expand(cell)
	var rects: Array = []
	var previous := {}
	for y in range(bounds.position.y, bounds.end.y):
		var current := {}
		var x := bounds.position.x
		while x < bounds.end.x:
			if rock[y * grid_size.x + x] == 0:
				x += 1
				continue
			var begin := x
			while x < bounds.end.x and rock[y * grid_size.x + x] != 0: x += 1
			var key := Vector2i(begin, x - begin)
			var index: int = previous.get(key, -1)
			if index < 0:
				index = rects.size()
				rects.append(Rect2i(begin, y, x - begin, 1))
			else:
				var rect: Rect2i = rects[index]
				rect.size.y += 1
				rects[index] = rect
			current[key] = index
		previous = current
	return rects

func contains(cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, grid_size).has_point(cell)

func problems() -> PackedStringArray:
	var errors := PackedStringArray()
	if grid_size != Vector2i(160, 104) or rock.size() != grid_size.x * grid_size.y:
		errors.append("Roguelite terrain must be 160 x 104 cells.")
		return errors
	var built := arena()
	var mask: PackedByteArray = built.mask
	if override_terrain:
		for i in rock.size():
			if rock[i] == 0 and not EDITABLE.has_point(Vector2i(i % grid_size.x, i / grid_size.x)):
				errors.append("Keep terrain inside the editing area; the top and bottom bands hold the HUD.")
				break
	if built.free_cells.size() < 100: errors.append("Leave at least 100 open cells for captures and objectives.")
	if override_start and (not contains(player_start) or mask[player_start.y * grid_size.x + player_start.x] != 1):
		errors.append("The player must start on a safe rail (cyan cells).")
	if override_enemies:
		var anomalies := 0
		var occupied: Array[Vector2i] = []
		for enemy in enemies:
			var kind: String = enemy.get("kind", "")
			var cell: Vector2i = enemy.get("cell", Vector2i(-1, -1))
			if kind in MapCatalog.VOID_ENEMIES: anomalies += 1
			if kind not in MapCatalog.ENEMY_KINDS: errors.append("Unknown enemy type: " + kind)
			if not contains(cell) or mask[cell.y * grid_size.x + cell.x] != (1 if kind == "sparx" else 2):
				errors.append("%s at %s needs %s." % [kind.capitalize(), cell, "a safe rail" if kind == "sparx" else "open space"])
			if cell in occupied: errors.append("Two enemies share cell %s." % [cell])
			occupied.append(cell)
		if anomalies == 0: errors.append("Keep at least one void enemy (Anomaly, Gunner Orb, Ray Orb or Rotor) so territory captures work.")
	return errors
