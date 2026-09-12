@tool
extends RefCounted
## Content pools are exclusive to each act. Add boss IDs here after authoring their arenas.
const LENGTH := 24
const ACT_LENGTH := 8
const FIRST_MAP := 9
const LAST_MAP := 35
## Jump's territory patterns, independent of enemy rules and the untinted void.
const TERRITORY := [
	{"coast": Color(0.22, 0.66, 1.0), "fill": Color(0.22, 0.66, 1.0), "dither": 0},
	{"coast": Color(0.50, 0.85, 0.32), "fill": Color(0.40, 0.78, 0.24), "dither": 1},
	{"coast": Color(0.72, 0.42, 1.0), "fill": Color(0.62, 0.30, 1.0), "dither": 2},
]
const MAP_NAMES := [
	"LOADING BAY", "PRESS WORKS", "ASSEMBLY", "COOLANT CHANNELS", "FOREMAN'S FLOOR",
	"NEST POCKETS", "ROOTWAYS", "BROOD CHAMBERS", "THE COIL", "QUEEN'S NEST",
	"REACTOR BRIDGE", "CONTAINMENT RINGS", "SHIELD ARRAY", "FRACTURED CORE", "REACTOR HEART",
	"SERVICE BAY", "TRANSFER PLATFORM", "FINAL ASSEMBLY",
	"SPORE EDGE", "SPLIT NEST", "HIVE APPROACH",
	"SHIELD ENTRY", "BEAM CHANNELS", "CORE APPROACH",
	"GRINDING FLOOR", "THORN GARDEN", "PRISM VAULT",
]
const ACTS := [
	{"name": "THE FOUNDRY", "color": Color("c89658"), "maps": [9, 24, 25, 10, 11, 12, 26], "bosses": ["foreman", "grinder"], "enemies": ["anomaly", "sparx", "turret", "rotor", "gunner_orb"]},
	{"name": "THE INFESTATION", "color": Color("95b875"), "maps": [27, 14, 28, 15, 16, 17, 29], "bosses": ["brood_queen", "thorn_maw"], "enemies": ["anomaly", "spawner", "brood_carrier", "chain_worm"]},
	{"name": "THE REACTOR", "color": Color("aa98ea"), "maps": [30, 19, 31, 20, 21, 22, 32], "bosses": ["reactor_heart", "prism_warden"], "enemies": ["anomaly", "sniper", "ray_orb", "siege"]},
]
const BOSSES := {
	"foreman": {"name": "THE FOREMAN", "act": 1, "map": 13, "targets": "WEAPONS", "reward": 5},
	"brood_queen": {"name": "BROOD QUEEN", "act": 2, "map": 18, "targets": "HATCHERIES", "reward": 7},
	"reactor_heart": {"name": "REACTOR HEART", "act": 3, "map": 23, "targets": "RELAYS", "reward": 10},
	"grinder": {"name": "THE GRINDER", "act": 1, "map": 33, "targets": "CUTTERS", "reward": 5},
	"thorn_maw": {"name": "THORN MAW", "act": 2, "map": 34, "targets": "THORNS", "reward": 7},
	"prism_warden": {"name": "PRISM WARDEN", "act": 3, "map": 35, "targets": "LENSES", "reward": 10},
}

static func act_at(depth: int) -> int:
	return clampi((depth - 1) / ACT_LENGTH + 1, 1, 3)

static func step_at(depth: int) -> int:
	return posmod(depth - 1, ACT_LENGTH) + 1

static func map_act(stage: int) -> int:
	for act in ACTS.size():
		if stage in ACTS[act].maps: return act + 1
		for boss_id in ACTS[act].bosses:
			if BOSSES[boss_id].map == stage: return act + 1
	return 0

static func map_depth(stage: int) -> int:
	var act := map_act(stage)
	if act == 0: return stage
	var index: int = ACTS[act - 1].maps.find(stage)
	return (act - 1) * ACT_LENGTH + (index + 1 if index >= 0 else ACT_LENGTH)

static func map_order() -> Array:
	var result: Array = range(1, FIRST_MAP)
	for definition in ACTS:
		result.append_array(definition.maps)
		for boss_id in definition.bosses: result.append(BOSSES[boss_id].map)
	return result

static func route(random: RandomNumberGenerator) -> Array:
	var result: Array = []
	var contests: Array = []
	for depth in range(3, LENGTH):
		if step_at(depth) in [3, 4, 5, 6, 7]: contests.append(depth)
	var race_at: int = contests.pop_at(random.randi_range(0, contests.size() - 1))
	var rival_at: int = contests[random.randi_range(0, contests.size() - 1)]
	for act in range(1, 4):
		var definition: Dictionary = ACTS[act - 1]
		var maps: Array = definition.maps.duplicate()
		var boss_id: String = definition.bosses[random.randi_range(0, definition.bosses.size() - 1)]
		var previous := ""
		for step in range(1, ACT_LENGTH + 1):
			var depth := (act - 1) * ACT_LENGTH + step
			if step == ACT_LENGTH:
				result.append([{"depth": depth, "act": act, "stage": BOSSES[boss_id].map, "kind": "boss", "boss": boss_id}])
				continue
			var row: Array = [{"depth": depth, "act": act, "stage": maps[step - 1], "kind": "survey"}]
			if depth > 1:
				var pool := ["salvage", "repair", "beacon"]
				if depth >= 3: pool.append("cargo")
				if act == 3: pool.append("breach")
				pool.erase(previous)
				var kind: String = "race" if depth == race_at else ("rival" if depth == rival_at else pool[random.randi_range(0, pool.size() - 1)])
				previous = kind
				row.append({"depth": depth, "act": act, "stage": maps[step - 1], "kind": kind})
				if step in [4, 6]: row = [row[1]] # Shared junction: either lane can reach the contest.
				if random.randf() < 0.5: row.reverse()
			result.append(row)
	return result

