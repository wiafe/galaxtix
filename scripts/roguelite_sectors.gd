@tool
extends RefCounted
## Jump silhouettes fitted into Roguelite's wider viewport; cell size never changes.
const Acts = preload("res://scripts/roguelite_acts.gd")
const CORRUPTION_SECTOR := 17
const LENGTH := Acts.LENGTH

static func capture_goal(depth: int) -> int:
	return mini(90, 60 + (Acts.act_at(depth) - 1) * 5 + ((Acts.step_at(depth) - 1) / 2) * 5)

## Encounter kinds are one table: where a kind may appear and what its node promises.
## Forks pair Survey with another kind in random order; the middle merge rolls its kind too.
const KINDS := {
	"survey": {"min_depth": 1, "reward": ""},
	"salvage": {"min_depth": 2, "reward": "+2 SALVAGE PICKUPS"},
	"repair": {"min_depth": 2, "reward": "+1 HULL ON CLEAR"},
	"beacon": {"min_depth": 2, "reward": "+1 SALVAGE PER BEACON"},
	"cargo": {"min_depth": 3, "reward": "+2 SALVAGE PER DELIVERY"},
	"breach": {"min_depth": 5, "reward": "+3 SALVAGE ON SEAL"},
	"rival": {"min_depth": 3, "reward": "+3 SALVAGE ON WIN"},
	"race": {"min_depth": 3, "reward": "+3 SALVAGE ON WIN"},
	"boss": {"min_depth": 5, "reward": "BOSS SALVAGE + 1 HULL"},
}
const RACE_GOAL := 60
const RIVAL_SECONDS := 45.0
const RIVAL_RADIUS := 3
const BEACON_RADIUS := 5
const CARGO_PICKUP_RADIUS := 2.0 # Cells; forgiving contact for all three ships.
const BREACH_RADIUS := 4
const BREACH_LIMIT := 0.25 # Infected share of the arena that costs a hull; a playtest value.

static func turret_count(kind: String, depth: int) -> int:
	if kind == "salvage": return 2
	return 1 if depth >= 2 else 0

## Beacons to enclose, cargo runs to complete, or breaches to seal.
static func objective_count(kind: String, depth: int) -> int:
	match kind:
		"beacon": return 2 if depth <= 3 else 3
		"cargo": return 2 if depth <= 4 else 3
		"breach": return 1
	return 0

## Beacon and cargo sectors clear on their objective alone; the others keep the depth goal.
static func territory_goal(kind: String) -> bool:
	return kind not in ["beacon", "cargo", "rival", "race", "boss"]

static func reward_copy(kind: String) -> String:
	return String(KINDS.get(kind, {}).get("reward", ""))

static func objective_copy(kind: String, depth: int) -> String:
	match kind:
		"boss": return "CAPTURE THE THREE INSTALLATIONS, THEN ENCLOSE THE CORE."
		"race":
			return "FIRST TO %d%% WINS. SEPARATE ARENAS. LOSE: -1 HULL AND RETRY." % RACE_GOAL
		"beacon":
			return "ENCLOSE ALL %d BEACON DISCS. WAIT FOR GUARDING ANOMALIES TO MOVE OUT." % objective_count(kind, depth)
		"cargo":
			return "PICK UP CARGO, THEN RETURN TO SAFE LAND. ENCLOSING ALONE DOES NOT DELIVER."
		"breach":
			return "ENCLOSE THE BREACH AND CAPTURE %d%%. KEEP INFECTION BELOW 25%%." % capture_goal(depth)
		"rival":
			return "OWN MORE TERRITORY AT %d SECONDS. LOSE: -1 HULL AND RETRY." % int(RIVAL_SECONDS)
		"repair":
			return "CAPTURE %d%% TO CLEAR AND RESTORE ONE HULL." % capture_goal(depth)
		"salvage":
			return "CAPTURE %d%% TO CLEAR. ENCLOSE THE EXTRA SALVAGE PICKUPS FOR REWARDS." % capture_goal(depth)
	return "CAPTURE %d%% OF THE ARENA TO CLEAR." % capture_goal(depth)

static func alternate_kinds(depth: int) -> Array[String]:
	var kinds: Array[String] = []
	for kind: String in KINDS:
		if kind not in ["survey", "boss"] and int(KINDS[kind].min_depth) <= depth:
			kinds.append(kind)
	return kinds

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
	if level >= Acts.FIRST_MAP:
		return {"name": Acts.MAP_NAMES[clampi(level - Acts.FIRST_MAP, 0, Acts.MAP_NAMES.size() - 1)], "source": "belt", "level": 1, "source_half": Vector2(40, 40), "half": Vector2(40, 30)}
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
## Special encounters avoid repeating the previous special kind, including at the middle merge.
static func make_route(random: RandomNumberGenerator, length := LENGTH) -> Array:
	if length == Acts.LENGTH: return Acts.route(random)
	var route: Array = []
	# During playtesting, reserve one slot for each contest. Keeping these kinds
	# out of the remaining rolls prevents duplicates and consecutive special repeats.
	var contests := {}
	var eligible_depths: Array[int] = []
	for depth in range(3, length): eligible_depths.append(depth)
	if eligible_depths.size() >= 2:
		for kind in ["race", "rival"]:
			var slot := random.randi_range(0, eligible_depths.size() - 1)
			contests[eligible_depths[slot]] = kind
			eligible_depths.remove_at(slot)
	var previous_kind := ""
	for depth in range(1, length + 1):
		var row: Array = [{"depth": depth, "stage": depth, "kind": "survey"}]
		if depth == 4 and depth < length:
			var kinds := alternate_kinds(depth)
			if not contests.is_empty():
				kinds.erase("race")
				kinds.erase("rival")
			kinds.erase(previous_kind)
			kinds.append("survey")
			var kind: String = contests[depth] if contests.has(depth) else kinds[random.randi_range(0, kinds.size() - 1)]
			row[0].kind = kind
			if kind != "survey": previous_kind = kind
		elif depth not in [1, length]:
			var pool := [2, 3] if depth <= 3 else [4, 5, 6, 7]
			pool.erase(depth)
			var alternate: int = pool[random.randi_range(0, pool.size() - 1)]
			var kinds := alternate_kinds(depth)
			if not contests.is_empty():
				kinds.erase("race")
				kinds.erase("rival")
			if kinds.size() > 1: kinds.erase(previous_kind)
			var kind: String = contests[depth] if contests.has(depth) else kinds[random.randi_range(0, kinds.size() - 1)]
			previous_kind = kind
			row.append({"depth": depth, "stage": alternate, "kind": kind})
			if random.randi_range(0, 1) == 1: row.reverse()
		route.append(row)
	return route

static func draft_milestones(area: int) -> Array[int]:
	if area < 3800: return [35]
	if area < 4400: return [25, 55]
	return [20, 40, 60]
