@tool
class_name MapDefinition
extends Resource
const EDITABLE := Rect2i(0, 18, 160, 68) # Keep the gameplay HUD bands clear.
## Roguelite map source. Disabled overrides retain the procedural game's behavior.
@export var map_id := ""
@export var title := ""
@export_enum("Legacy", "Foundry", "Infestation", "Reactor") var act_theme := 0
@export var boss_id := "" # IDs from Roguelite Acts.BOSSES; empty for regular maps.
@export var sector := 1 # Arena shape, independent of encounter depth.
@export var grid_size := Vector2i(160, 104)
@export var override_terrain := false
@export var rock := PackedByteArray()
@export var override_start := false
@export var player_start := Vector2i.ZERO
@export var override_enemies := false
## kind, cell, axis. Sparx markers spawn immediately and replace the timed wave.
@export var enemies: Array[Dictionary] = []
@export var override_pickups := false
@export var pickups: Array[Dictionary] = [] # cell; each pickup uses the normal salvage award.
@export var encounters: Dictionary = {} # Per-kind rules and optional objective markers.
## Optional cell overlay: 0 = none, 1 = shield pocket, 2 = pulsing hazard.
@export var field_zones := PackedByteArray()
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
	var exterior := PackedByteArray()
	exterior.resize(rock.size())
	if act_theme > 0:
		var queue: Array[Vector2i] = [Vector2i.ZERO]
		exterior[0] = 1
		var head := 0
		while head < queue.size():
			var cell := queue[head]
			head += 1
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = cell + direction
				if not contains(next): continue
				var i := next.y * grid_size.x + next.x
				if rock[i] != 0 and exterior[i] == 0:
					exterior[i] = 1
					queue.append(next)
	var previous := {}
	for y in range(bounds.position.y, bounds.end.y):
		var current := {}
		var x := bounds.position.x
		while x < bounds.end.x:
			if rock[y * grid_size.x + x] == 0 or exterior[y * grid_size.x + x] == 1:
				x += 1
				continue
			var begin := x
			while x < bounds.end.x and rock[y * grid_size.x + x] != 0 and exterior[y * grid_size.x + x] == 0: x += 1
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
	if not boss_id.is_empty():
		if not preload("res://scripts/roguelite_acts.gd").BOSSES.has(boss_id): errors.append("Unknown boss ID: " + boss_id)
		if not override_enemies: errors.append("Boss arenas require enemy overrides and boss markers.")
	if grid_size != Vector2i(160, 104) or rock.size() != grid_size.x * grid_size.y:
		errors.append("Roguelite terrain must be 160 x 104 cells.")
		return errors
	var built := arena()
	var mask: PackedByteArray = built.mask
	if override_pickups:
		errors.append_array(marker_problems(pickups, mask, "Salvage", false))
	for kind in encounters:
		if kind not in preload("res://scripts/roguelite_sectors.gd").KINDS or not encounters[kind] is Dictionary:
			errors.append("Unknown encounter settings: " + str(kind))
			continue
		var config: Dictionary = encounters[kind]
		for key in ["goal", "seconds", "runs"]:
			if not config.has(key): continue
			var value = config[key]
			var limits: Vector2 = {"goal": Vector2(10, 95), "seconds": Vector2(10, 300), "runs": Vector2(1, 20)}[key]
			if not (value is int or value is float) or float(value) < limits.x or float(value) > limits.y:
				errors.append("%s %s must be between %d and %d." % [kind, key, limits.x, limits.y])
		if config.has("objectives"):
			if not config.objectives is Array:
				errors.append("Encounter objectives must be a marker list.")
				continue
			var markers: Array = config.objectives
			if kind not in ["beacon", "cargo", "breach", "rival"]:
				errors.append("This encounter uses no objective markers.")
			elif markers.is_empty() or (kind != "beacon" and markers.size() != 1) or markers.size() > 10:
				errors.append("%s needs %s." % [kind.capitalize(), "1 to 10 beacons" if kind == "beacon" else "one objective marker"])
			errors.append_array(marker_problems(markers, mask, String(kind).capitalize(), kind != "cargo"))
	if not field_zones.is_empty():
		if field_zones.size() != mask.size():
			errors.append("Zone painting must match the terrain dimensions.")
		else:
			for i in field_zones.size():
				if field_zones[i] > 2 or (field_zones[i] != 0 and (mask[i] == 0 or not EDITABLE.has_point(Vector2i(i % grid_size.x, i / grid_size.x)))):
					errors.append("Paint shield and hazard zones on playable cells only.")
					break
	if override_terrain:
		for i in rock.size():
			if rock[i] == 0 and not EDITABLE.has_point(Vector2i(i % grid_size.x, i / grid_size.x)):
				errors.append("Keep terrain inside the editing area; the top and bottom bands hold the HUD.")
				break
	if built.free_cells.size() < 100: errors.append("Leave at least 100 open cells for captures and objectives.")
	if override_start and (not contains(player_start) or mask[player_start.y * grid_size.x + player_start.x] != 1):
		errors.append("The player must start on a safe rail (cyan cells).")
	if override_enemies:
		if not boss_id.is_empty():
			if enemies.filter(func(e): return e.get("kind") == "boss_core").size() != 1: errors.append("Boss arenas need exactly one Boss Core.")
			if enemies.filter(func(e): return e.get("kind") == "boss_relay").size() != 3: errors.append("Boss arenas need exactly three Boss Relays.")
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
			if kind in ["boss_core", "boss_relay"]:
				var radius := 4 if kind == "boss_core" else 2
				for dy in range(-radius, radius + 1):
					for dx in range(-radius, radius + 1):
						var point := cell + Vector2i(dx, dy)
						if dx * dx + dy * dy <= radius * radius and (not contains(point) or mask[point.y * grid_size.x + point.x] != 2):
							errors.append("Leave open space around %s at %s." % [kind, cell])
				for other in enemies:
					if other != enemy and Vector2(other.cell - cell).length() < radius + 4: errors.append("Keep boss markers clear of other enemies and relays.")
		if anomalies == 0: errors.append("Keep at least one void enemy, such as an Anomaly, Chain Worm or Brood Carrier, so territory captures work.")
	return errors

func marker_problems(markers: Array, mask: PackedByteArray, label: String, disc: bool) -> PackedStringArray:
	var errors := PackedStringArray()
	var occupied := {}
	for marker in markers:
		if not marker is Dictionary or not marker.get("cell") is Vector2i:
			errors.append(label + " needs a cell position.")
			continue
		var cell: Vector2i = marker.cell
		var radius := int(marker.get("radius", 1)) if disc else 0
		if radius < 0 or radius > 10 or (disc and radius < 1):
			errors.append(label + " radius must be 1 to 10 cells.")
			continue
		var valid := true
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if x * x + y * y > radius * radius: continue
				var p := cell + Vector2i(x, y)
				if not contains(p) or mask[p.y * grid_size.x + p.x] != 2: valid = false
		if not valid: errors.append("%s at %s needs open space around its whole marker." % [label, cell])
		if occupied.has(cell): errors.append("Two %s markers share %s." % [label, cell])
		occupied[cell] = true
		if override_enemies:
			for enemy in enemies:
				var clearance := 4 if enemy.kind == "boss_core" else (2 if enemy.kind == "boss_relay" else 0)
				if cell.distance_squared_to(enemy.cell) <= clearance * clearance:
					errors.append(label + " overlaps " + String(enemy.kind).capitalize() + ".")
	return errors
