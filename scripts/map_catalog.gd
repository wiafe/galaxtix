@tool
class_name MapCatalog
extends RefCounted
const ROOT := "res://maps/"
const ENEMY_KINDS := ["anomaly", "sparx", "turret", "spawner", "gunner_orb", "ray_orb", "rotor", "chain_worm", "brood_carrier", "sniper", "siege"]
const VOID_ENEMIES := ["anomaly", "gunner_orb", "ray_orb", "rotor", "chain_worm", "brood_carrier", "siege"]
const ENEMY_HELP := {
	"sniper": "Fixed turret. Locks a yellow aim line, then fires a red beam across land. Rock blocks it; enclose the turret to disable it.",
	"siege": "Slow void enemy. Marks a coastal patch before breaking captured land. Original rails and hardened walls resist it.",
	"anomaly": "Roaming beam. Keeps its region unclaimed and threatens trails.",
	"sparx": "Patrols safe rails. Capture the void beside its rail to cut it off and destroy it. Place on cyan cells; starts immediately.",
	"turret": "Fixed gun. Fires along the selected axis; enclose it to disable it.",
	"spawner": "Fixed nest. Breeds chasing mites; enclose it to disable it.",
	"gunner_orb": "Roams, flashes orange, then stops to fire a five-shot fan. Safe land blocks its shots.",
	"ray_orb": "Roams, locks its aim with a dashed warning, then extends a beam in both directions. Land blocks the beam.",
	"rotor": "A rotating bar with a fixed centre. Reverses at land or rock. Enclose its centre to destroy it.",
	"chain_worm": "A roaming head with six trailing links. The whole body cuts trails; wait for its tail to pass.",
	"brood_carrier": "Drops eggs that hatch into chasing mites after 6 seconds. Capture eggs first for salvage. Up to four eggs or mites per carrier.",
}
static var testing := {} # Isolated resource overrides for smoke tests; never serialized.

static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for sector in range(1, 9):
		result.append({"id": "roguelite_%02d" % sector, "sector": sector, "title": "%02d / %s" % [sector, preload("res://scripts/roguelite_sectors.gd").stage(sector).name.capitalize()]})
	return result

static func path_for(id: String) -> String:
	return ROOT + id.validate_filename() + ".tres"

static func default_path(id: String) -> String:
	return ROOT + "defaults/" + id.validate_filename() + ".tres"

static func read(stage: int, refresh := false) -> MapDefinition:
	var id := "roguelite_%02d" % stage
	if testing.has(id): return testing[id]
	var path := path_for(id)
	if not ResourceLoader.exists(path): path = default_path(id)
	if not ResourceLoader.exists(path): return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE if refresh else ResourceLoader.CACHE_MODE_REUSE) as MapDefinition

static func nearest(mask: PackedByteArray, size: Vector2i, cell: Vector2i, value: int) -> Vector2i:
	if Rect2i(Vector2i.ZERO, size).has_point(cell) and mask[cell.y * size.x + cell.x] == value: return cell
	var best := cell
	var distance := INF
	for i in mask.size():
		if mask[i] != value: continue
		var candidate := Vector2i(i % size.x, i / size.x)
		var d := Vector2(candidate - cell).length_squared()
		if d < distance:
			distance = d
			best = candidate
	return best
