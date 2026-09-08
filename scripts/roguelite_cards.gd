extends RefCounted
## Shared effects, described for each ship's capture mechanic. One installed copy, up to rank III.
const LIST := [
	{"id": "afterburner", "name": "AFTERBURNER", "kind": "Q", "desc": "Draw faster.", "stats": "+80% SPEED / 3S", "detail": "14S RECHARGE"},
	{"id": "hardlight", "name": "HARDLIGHT", "kind": "E", "desc": "Shield your trail.", "stats": "2S PROTECTION", "detail": "18S RECHARGE"},
	{"id": "anchor", "name": "ANCHOR", "kind": "AUTO", "desc": "Survive a lethal trail hit.", "stats": "RETURN TO COAST", "detail": "24S RECHARGE"},
	{"id": "ion", "name": "ION THREAD", "kind": "AUTO", "desc": "Trail contact repels enemies.", "stats": "1.5S GLOBAL FREEZE", "detail": "10S RECHARGE"},
	{"id": "clean", "name": "CLEAN SWEEP", "kind": "PASSIVE", "desc": "Captures cleanse corruption.", "stats": "6 CELL REACH", "detail": ""},
	{"id": "containment", "name": "CONTAINMENT", "kind": "PASSIVE", "desc": "Large cuts halt corruption.", "stats": "8% CUT / 8S HALT", "detail": ""},
	{"id": "slipstream", "name": "SLIPSTREAM", "kind": "PASSIVE", "desc": "Move safely to boost your next cut.", "stats": "2S CHARGE / +30% SPEED", "detail": "BOOST LASTS 2S"},
	{"id": "loop", "name": "REACTOR LOOP", "kind": "PASSIVE", "desc": "Every third cut refunds cooldowns.", "stats": "-6S COOLDOWNS", "detail": ""},
	{"id": "compression", "name": "COMPRESSION", "kind": "PASSIVE", "desc": "Small cuts build drawing speed.", "stats": "UNDER 4%: +15% / MAX +45%", "detail": "8% CUT RESETS"},
	{"id": "phase", "name": "PHASE LINE", "kind": "PASSIVE", "desc": "Start each cut with a shield.", "stats": "1.5S TRAIL PROTECTION", "detail": ""},
	{"id": "harvest", "name": "VOID HARVEST", "kind": "PASSIVE", "desc": "Trap nests or turrets for salvage.", "stats": "+5 SALVAGE EACH", "detail": ""},
	{"id": "stasis", "name": "STASIS WAKE", "kind": "PASSIVE", "desc": "Captures freeze enemies.", "stats": "1S FREEZE", "detail": ""},
]

static func definition(id: String, ship_id := "surveyor", rank := 1) -> Dictionary:
	for card in LIST:
		if card.id == id:
			var result: Dictionary = card.duplicate(true)
			if ship_id == "sapper":
				match id:
					"afterburner":
						result.desc = "Charge your blast faster."
						result.stats = "+80% CHARGE / 3S"
					"hardlight": result.desc = "Shield your charging disc."
					"anchor": result.desc = "Survive a hit. Return to safe ground."
					"ion":
						result.name = "ION FIELD"
						result.desc = "Disc contact repels enemies."
					"phase":
						result.name = "PHASE CHARGE"
						result.desc = "Start each charge with a shield."
						result.stats = "1.5S DISC PROTECTION"
					"slipstream": result.desc = "Move safely to boost your next charge."
					"compression": result.desc = "Small blasts build charging speed."
					"containment": result.desc = "Large blasts halt corruption."
			elif ship_id == "lancer":
				match id:
					"afterburner": result.desc = "Ride your lance faster."
					"slipstream": result.desc = "Move safely to boost your next lance."
					"compression": result.desc = "Small captures build riding speed."
					"phase": result.desc = "Start each lance with a shield."
			result.rank = clampi(rank, 1, 3)
			var power: float = 1.0 + 0.25 * (result.rank - 1)
			if result.rank > 1:
				match id:
					"afterburner": result.stats = "+%d%% %s / 3S" % [roundi(80 * power), "CHARGE" if ship_id == "sapper" else "SPEED"]
					"hardlight": result.stats = "%.1fS PROTECTION" % (2 * power)
					"anchor": result.detail = "%.1fS RECHARGE" % (24 / power)
					"ion": result.stats = "%.1fS GLOBAL FREEZE" % (1.5 * power)
					"phase": result.stats = "%.1fS PROTECTION" % (1.5 * power)
					"slipstream": result.stats = "2S CHARGE / +%d%% SPEED" % roundi(30 * power)
					"loop": result.stats = "-%.1fS COOLDOWNS" % (6 * power)
					"compression": result.stats = "SMALL CUT: +%d%% / MAX +%d%%" % [roundi(15 * power), roundi(45 * power)]
					"stasis": result.stats = "%.1fS FREEZE" % power
					"clean": result.stats = "%d CELL REACH" % roundi(6 * power)
					"containment": result.stats = "8%% CUT / %.1fS HALT" % (8 * power)
					"harvest": result.stats = "+%.1f SALVAGE EACH" % (5 * power)
			return result
	return {}

static func offer(owned: Array[String], rng: RandomNumberGenerator, excluded: Array[String] = []) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for card in LIST:
		if not owned.has(card.id) and not excluded.has(card.id):
			pool.append(card)
	var result: Array[Dictionary] = []
	while result.size() < 3 and not pool.is_empty():
		var pick := rng.randi_range(0, pool.size() - 1)
		result.append(pool[pick])
		pool.remove_at(pick)
	return result
