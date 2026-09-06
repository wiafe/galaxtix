class_name Ships
## The hangar: each ship breaks one Qix rule while keeping "enclose to claim" as the verb.
## Ships are bought with Isotope (rare nodes) and picked in the dock before a jump. Each ship
## has its own short upgrade line, bought with Flux, shown in the dock when the ship is selected.

const LIST := [
	{"id": "surveyor", "name": "SURVEYOR", "cost": 0,
		"rule": "CLASSIC RULES",
		"desc": "HOLD SPACE AND MOVE TO DRAW. RETURN TO SAFE GROUND TO CAPTURE AREA.",
		"upgrades": [
			{"id": "slip", "name": "SLIPSTREAM", "desc": "+10% SPEED WHILE DRAWING", "base": 4.0, "growth": 1.6, "max": 5},
			{"id": "shield", "name": "SHIELD", "desc": "+0.5S SHIELD AFTER RESPAWN", "base": 3.0, "growth": 1.6, "max": 4},
			{"id": "slowb", "name": "SLOW BONUS", "desc": "+1 FLUX PER NODE ON SLOW DRAW", "base": 6.0, "growth": 1.8, "max": 3},
		]},
	{"id": "bulwark", "name": "BULWARK", "cost": 3,
		"rule": "BREAKS: FRAGILE TRAIL",
		"desc": "YOUR LINE HARDENS INTO A WALL. RELEASE SPACE TO HARDEN IT FASTER. CLOSED LOOPS CAPTURE ONCE HARDENED.",
		"upgrades": [
			{"id": "temper", "name": "TEMPER", "desc": "+1 CELL/S HARDENING", "base": 4.0, "growth": 1.6, "max": 5},
			{"id": "front", "name": "FRONTLINE", "desc": "+2 CELLS HARDENED AT THE START", "base": 5.0, "growth": 1.7, "max": 3},
		]},
	{"id": "leaper", "name": "LEAPER", "cost": 8,
		"rule": "BREAKS: THE PEN",
		"desc": "HOLD SPACE TO AIM; USE ARROWS TO TURN. RELEASE TO JUMP AND BUILD A WALL.",
		"upgrades": [
			{"id": "stride", "name": "STRIDE", "desc": "+25% LINE BUILD SPEED", "base": 4.0, "growth": 1.6, "max": 3},
			{"id": "arm", "name": "LONG ARM", "desc": "+5 CELLS MAX LINE", "base": 3.0, "growth": 1.6, "max": 4},
			{"id": "pad", "name": "LANDING PAD", "desc": "ISLANDS ARE 5X5", "base": 6.0, "growth": 2.0, "max": 1},
			{"id": "tide", "name": "TIDE", "desc": "ISLANDS GROW A RING EVERY 10S, +1 RING PER LEVEL", "base": 6.0, "growth": 1.8, "max": 3},
		]},
	{"id": "lancer", "name": "LANCER", "cost": 10,
		"rule": "BREAKS: THE WALK",
		"desc": "PRESS SPACE TO FIRE A LINE AND RIDE IT TO SAFE GROUND.",
		"upgrades": [
			{"id": "cap", "name": "CAPACITOR", "desc": "-1S LANCE RECHARGE", "base": 4.0, "growth": 1.7, "max": 4},
			{"id": "rails", "name": "RAILS", "desc": "+50% RIDE SPEED", "base": 4.0, "growth": 1.6, "max": 3},
			{"id": "bend", "name": "BEND", "desc": "+1 MID-RIDE RE-LANCE: STEER + SPACE", "base": 5.0, "growth": 1.8, "max": 2},
			{"id": "lattice", "name": "LATTICE", "desc": "TETHER AHEAD SURVIVES ONE CUT", "base": 8.0, "growth": 2.0, "max": 1},
		]},
	{"id": "sapper", "name": "SAPPER", "cost": 8,
		"rule": "BREAKS: NO TRAIL",
		"desc": "MOVE ANYWHERE. HOLD SPACE TO GROW A CIRCLE. RELEASE TO CAPTURE IT.",
		"upgrades": [
			{"id": "payload", "name": "PAYLOAD", "desc": "+1 CELL MAX DISC", "base": 4.0, "growth": 1.7, "max": 4},
			{"id": "quick", "name": "QUICK FUSE", "desc": "+25% CHARGE RATE", "base": 5.0, "growth": 1.8, "max": 3},
			{"id": "primer", "name": "PRIMER", "desc": "THE DISC STARTS AT 2 CELLS", "base": 5.0, "growth": 2.0, "max": 1},
			{"id": "shock", "name": "SHOCKWAVE", "desc": "BLAST CLEARS MITES, BOLTS AND SPARX +2 CELLS OUT", "base": 6.0, "growth": 1.8, "max": 2},
			{"id": "insul", "name": "INSULATED", "desc": "THE DISC SURVIVES ONE HIT PER CHARGE", "base": 8.0, "growth": 2.0, "max": 1},
		]},
]


static func get_ship(id: String) -> Dictionary:
	for s in LIST:
		if s.id == id:
			return s
	return LIST[0]


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i].id == id:
			return i
	return 0


static func owned(id: String) -> bool:
	return id == "surveyor" or bool(Save.data.ships.get(id, false))


static func can_buy(id: String) -> bool:
	return not owned(id) and int(Save.data.isotope) >= int(get_ship(id).cost)


static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	Save.data.isotope = int(Save.data.isotope) - int(get_ship(id).cost)
	Save.data.ships[id] = true
	Save.data.ship = id
	Save.save_data()
	return true


# --- per-ship upgrade lines (Flux) ---
static func upgrades(ship_id: String) -> Array:
	return get_ship(ship_id).upgrades


static func up_def(ship_id: String, up_id: String) -> Dictionary:
	for u in upgrades(ship_id):
		if u.id == up_id:
			return u
	return {}


static func up_level(ship_id: String, up_id: String) -> int:
	return int(Save.data.ship_upgrades.get(ship_id + ":" + up_id, 0))


static func up_cost(ship_id: String, up_id: String) -> float:
	var u := up_def(ship_id, up_id)
	return round(u.base * pow(u.growth, up_level(ship_id, up_id)))


static func up_maxed(ship_id: String, up_id: String) -> bool:
	var u := up_def(ship_id, up_id)
	return int(u.max) > 0 and up_level(ship_id, up_id) >= int(u.max)


static func can_buy_up(ship_id: String, up_id: String) -> bool:
	return owned(ship_id) and not up_maxed(ship_id, up_id) and Save.data.flux >= up_cost(ship_id, up_id)


static func buy_up(ship_id: String, up_id: String) -> bool:
	if not can_buy_up(ship_id, up_id):
		return false
	Save.data.flux -= up_cost(ship_id, up_id)
	Save.data.ship_upgrades[ship_id + ":" + up_id] = up_level(ship_id, up_id) + 1
	Save.save_data()
	return true
