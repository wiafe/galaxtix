extends RefCounted
## A separate profile: Jump's save, currencies and upgrades are never borrowed.
const PATH := "user://galaxtix_roguelite.json"
const TRACKS := ["engines", "hull", "reactor", "scanner", "extractor", "containment"]
const MAX_RANK := 10
const SHIPS := ["surveyor", "lancer", "sapper"]
const SHIP_PRICE := 10
const Sectors = preload("res://scripts/roguelite_sectors.gd")
var salvage := 0
var runs := 0
var wins := 0
var ranks := {"engines": 0, "hull": 0, "reactor": 0, "scanner": 0, "extractor": 0, "containment": 0}
var best_sector := 1
var containment_unlocked := false
var salvage_fraction := 0.0
var ships := {"surveyor": true}
var selected_ship := "surveyor"

func read_profile() -> void:
	if not Save.enabled or not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		apply_profile(parsed)

func apply_profile(data: Dictionary) -> void:
	var saved_sector = data.get("best_sector", 1)
	best_sector = clampi(int(saved_sector), 1, Sectors.LIST.size()) if saved_sector is float or saved_sector is int else 1
	# Preserve access earned in the earlier three-sector prototype.
	var legacy: bool = data.get("version", 1) in [1, 2, 3]
	containment_unlocked = data.get("containment_unlocked", false) == true or best_sector >= Sectors.CORRUPTION_SECTOR or (legacy and best_sector >= 3) or (data.get("version", 1) == 4 and best_sector >= 6)
	var saved_fraction = data.get("salvage_fraction", 0.0)
	salvage_fraction = clampf(float(saved_fraction), 0.0, 0.999999) if saved_fraction is float or saved_fraction is int else 0.0
	ships = {"surveyor": true}
	var saved_ships = data.get("ships", {})
	if saved_ships is Dictionary:
		for id in SHIPS:
			if saved_ships.get(id, false) is bool and saved_ships.get(id, false):
				ships[id] = true
	var saved_ship = data.get("selected_ship", "surveyor")
	selected_ship = saved_ship if saved_ship is String and owns_ship(saved_ship) else "surveyor"
	for key in ["salvage", "runs", "wins"]:
		var value = data.get(key, 0)
		if value is float or value is int:
			set(key, clampi(int(value), 0, 100000000))
	# Version 6 denominates both earnings and costs in quarter-sized salvage units.
	# Keep the remainder so conversion loses neither currency nor upgrade progress.
	if int(data.get("version", 1)) < 6:
		var converted := (salvage + salvage_fraction) / 4.0
		salvage = floori(converted)
		salvage_fraction = converted - salvage
	var saved = data.get("ranks", {})
	if saved is Dictionary:
		for key in TRACKS:
			var value = saved.get(key, 0)
			if value is float or value is int:
				ranks[key] = clampi(int(value), 0, MAX_RANK)

func write_profile() -> bool:
	if not Save.enabled:
		return true
	var file := FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": 6, "salvage": salvage, "salvage_fraction": salvage_fraction, "best_sector": best_sector, "containment_unlocked": containment_unlocked, "runs": runs, "wins": wins, "ranks": ranks, "ships": ships, "selected_ship": selected_ship}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(PATH + ".tmp", PATH) == OK

func rank_of(track: String) -> int:
	return int(ranks.get(track, 0))

func owns_ship(id: String) -> bool:
	return SHIPS.has(id) and bool(ships.get(id, false))

func select_ship(id: String) -> bool:
	if not owns_ship(id):
		return false
	var previous := selected_ship
	selected_ship = id
	if not write_profile():
		selected_ship = previous
		return false
	return true

func buy_ship(id: String) -> bool:
	if not SHIPS.has(id) or owns_ship(id) or salvage < SHIP_PRICE:
		return false
	var previous := selected_ship
	salvage -= SHIP_PRICE
	ships[id] = true
	selected_ship = id
	if not write_profile():
		ships.erase(id)
		selected_ship = previous
		salvage += SHIP_PRICE
		return false
	return true

func cost(track: String) -> int:
	return node_cost(rank_of(track) + 1)

func node_cost(rank: int) -> int:
	return 2 + (rank - 1)

func buy(track: String) -> bool:
	if not track_available(track) or rank_of(track) >= MAX_RANK or salvage < cost(track):
		return false
	var price := cost(track)
	salvage -= price
	ranks[track] = rank_of(track) + 1
	if not write_profile():
		ranks[track] -= 1
		salvage += price
		return false
	return true

func track_available(track: String) -> bool:
	return TRACKS.has(track) and (track != "containment" or containment_unlocked or best_sector >= Sectors.CORRUPTION_SECTOR)
