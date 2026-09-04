class_name Galaxies
## The galaxy map: each galaxy is a hazard vocabulary (Fortix's "lands"), with its own best
## sector record. Securing sector UNLOCK_AT of a galaxy opens the next one.

const UNLOCK_AT := 5
const LENGTH := 8          # sectors per galaxy; sector 8 is the boss; 9+ is endless once cleared

const LIST := [
	{"id": "helix", "name": "HELIX REACH", "desc": "THE ANOMALY AND ITS SPARX.",
		"turrets": 0, "spawners": 0, "qix_mult": 1.0, "node_bonus": 0,
		"boss": "twin", "boss_name": "TWIN HELIX", "boss_desc": "TWO ANOMALIES, ONE LETHAL BOND. SPLIT THEM.",
		"coast": Color(0.22, 0.66, 1.00), "fill": Color(0.22, 0.66, 1.00), "dither": 0, "qix_shift": 0, "shape": "none"},
	{"id": "belt", "name": "TURRET BELT", "desc": "TURRETS SWEEP THE VOID. ENCLOSE THEM.",
		"turrets": 2, "spawners": 0, "qix_mult": 1.15, "node_bonus": 1,
		"boss": "bastion", "boss_name": "BASTION", "boss_desc": "FOUR TURNING CORE TURRETS. ENCLOSE ALL FOUR.",
		"coast": Color(1.00, 0.64, 0.18), "fill": Color(1.00, 0.55, 0.12), "dither": 1, "qix_shift": 5, "shape": "pillar"},
	{"id": "deep", "name": "SPAWNER DEEP", "desc": "SPAWNERS BREED MITES. ENCLOSE EVERYTHING.",
		"turrets": 2, "spawners": 1, "qix_mult": 1.3, "node_bonus": 2,
		"boss": "brood", "boss_name": "THE BROOD", "boss_desc": "A ROAMING MOTHER SPAWNER. ENCLOSE IT.",
		"coast": Color(0.72, 0.42, 1.00), "fill": Color(0.62, 0.30, 1.00), "dither": 2, "qix_shift": 2, "shape": "none"},
]


static func cleared(id: String) -> bool:
	return bool(Save.data.galaxy_clear.get(id, false))


static func endless_best(id: String) -> int:
	return int(Save.data.endless_best.get(id, 0))


static func get_galaxy(id: String) -> Dictionary:
	for g in LIST:
		if g.id == id:
			return g
	return LIST[0]


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i].id == id:
			return i
	return 0


static func best(id: String) -> int:
	return int(Save.data.galaxy_best.get(id, 0))


static func unlocked(id: String) -> bool:
	var i := index_of(id)
	if i == 0:
		return true
	return best(LIST[i - 1].id) >= UNLOCK_AT


static func unlock_hint(id: String) -> String:
	var i := index_of(id)
	if i == 0:
		return ""
	return "SECURE SECTOR %02d OF %s" % [UNLOCK_AT, LIST[i - 1].name]


## Hazard counts for a sector of this galaxy.
static func turret_count(g: Dictionary, level: int) -> int:
	if int(g.turrets) == 0:
		return 0
	return mini(6, int(g.turrets) + (level - 1) / 2)


static func spawner_count(g: Dictionary, level: int) -> int:
	if int(g.spawners) == 0:
		return 0
	return mini(3, int(g.spawners) + (level - 1) / 3)
