extends Node
## Autoload "Save": the persistent incremental layer. Flux, upgrade levels, records, and the
## Beacon's offline income. Everything the run layer needs to know about upgrades is here.
##
## Economy (v2): Flux comes only from Flux nodes. A node is worth 1 Flux (+1 per Refinery level).
## A sector starts with its base nodes already on the field; the Prospector surfaces more over time.

const PATH := "user://galaxtix.json"
const OFFLINE_CAP_SEC := 8.0 * 3600.0
const SAVE_VERSION := 2

const UPGRADES := [
	{"id": "yield", "name": "REFINERY", "desc": "+1 FLUX PER NODE", "base": 5.0, "growth": 1.8, "max": 0},
	{"id": "prospect", "name": "PROSPECTOR", "desc": "EXTRA NODES SURFACE OVER TIME", "base": 6.0, "growth": 1.7, "max": 8},
	{"id": "thrust", "name": "THRUSTERS", "desc": "+10% SPEED", "base": 3.0, "growth": 1.5, "max": 15},
	{"id": "damp", "name": "DAMPENER", "desc": "-6% ANOMALY SPEED", "base": 4.0, "growth": 1.6, "max": 10},
	{"id": "jam", "name": "JAMMER", "desc": "-8% SPARX SPEED", "base": 3.0, "growth": 1.6, "max": 8},
	{"id": "hull", "name": "HULL PLATING", "desc": "+1 LIFE", "base": 8.0, "growth": 2.0, "max": 6},
	{"id": "bulk", "name": "BULKHEADS", "desc": "+1 CELL OF RIM PRE-CLAIMED", "base": 4.0, "growth": 1.7, "max": 12},
	{"id": "fuse", "name": "FUSE DELAY", "desc": "+0.5S BEFORE THE FUSE LIGHTS", "base": 2.0, "growth": 1.5, "max": 8},
	{"id": "beacon", "name": "BEACON", "desc": "+6 FLUX PER HOUR, EVEN OFFLINE", "base": 10.0, "growth": 2.0, "max": 0},
]

var data := {
	"version": SAVE_VERSION,
	"flux": 0.0,
	"upgrades": {},
	"best_level": 0,
	"runs": 0,
	"total_flux": 0.0,
	"last_ts": 0.0,
	"galaxy": "helix",
	"galaxy_best": {},
	"start_sector": 1,
	"isotope": 0,
	"ships": {},
	"ship": "surveyor",
	"ship_upgrades": {},
	"galaxy_clear": {},
	"endless_best": {},
	"starcharts": 0,
}
var enabled := true
var offline_gain := 0.0
var _save_timer := 0.0


func _ready() -> void:
	# smoke tests must never touch the real save (autoloads run before Main can say so)
	if OS.get_cmdline_user_args().has("--nosave"):
		enabled = false
	load_data()


func def(id: String) -> Dictionary:
	for u in UPGRADES:
		if u.id == id:
			return u
	return {}


func level(id: String) -> int:
	return int(data.upgrades.get(id, 0))


func cost(id: String) -> float:
	var u := def(id)
	return round(u.base * pow(u.growth, level(id)))


func maxed(id: String) -> bool:
	var u := def(id)
	return u.max > 0 and level(id) >= u.max


func can_buy(id: String) -> bool:
	return not maxed(id) and data.flux >= cost(id)


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	data.flux -= cost(id)
	data.upgrades[id] = level(id) + 1
	save_data()
	return true


func add_flux(v: float) -> void:
	data.flux += v
	data.total_flux += v


# --- derived stats used by the run ---
func node_value() -> int:
	return 1 + level("yield")


## Seconds between extra nodes surfacing; 0 = the Prospector is not installed.
func prospect_interval() -> float:
	var l := level("prospect")
	return 0.0 if l == 0 else 40.0 / float(l)


func speed_mult() -> float:
	return 1.0 + 0.10 * level("thrust")


func qix_mult() -> float:
	return max(0.4, 1.0 - 0.06 * level("damp"))


func sparx_mult() -> float:
	return max(0.35, 1.0 - 0.08 * level("jam"))


func extra_lives() -> int:
	return level("hull")


func rim() -> int:
	return level("bulk")


func fuse_delay() -> float:
	return 1.5 + 0.5 * level("fuse")


## Flux per second from the Beacon: 6 per hour per level.
func beacon_rate() -> float:
	return level("beacon") * 6.0 / 3600.0


# --- persistence ---
func save_data() -> void:
	if not enabled:
		return
	data.last_ts = Time.get_unix_time_from_system()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_data() -> void:
	if not enabled or not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for k in data.keys():
		if parsed.has(k):
			data[k] = parsed[k]
	if typeof(data.upgrades) != TYPE_DICTIONARY:
		data.upgrades = {}
	if typeof(data.galaxy_best) != TYPE_DICTIONARY:
		data.galaxy_best = {}
	if typeof(data.galaxy) != TYPE_STRING:
		data.galaxy = "helix"
	if typeof(data.ships) != TYPE_DICTIONARY:
		data.ships = {}
	if typeof(data.ship) != TYPE_STRING:
		data.ship = "surveyor"
	if typeof(data.ship_upgrades) != TYPE_DICTIONARY:
		data.ship_upgrades = {}
	if typeof(data.galaxy_clear) != TYPE_DICTIONARY:
		data.galaxy_clear = {}
	if typeof(data.endless_best) != TYPE_DICTIONARY:
		data.endless_best = {}
	# the Islander became the Leaper
	if data.ships.has("islander"):
		data.ships["leaper"] = data.ships["islander"]
		data.ships.erase("islander")
	if data.ship == "islander":
		data.ship = "leaper"
	for k in data.ship_upgrades.keys():
		if String(k).begins_with("islander:"):
			data.ship_upgrades["leaper:" + String(k).substr(9)] = data.ship_upgrades[k]
			data.ship_upgrades.erase(k)
	if int(data.get("version", 1)) < SAVE_VERSION:
		# v1 paid ~0.1 Flux per cell; v2 pays 1 Flux per node. Old balances would trivialise the new
		# prices, so the economy restarts. Records (best sector, jumps) are kept.
		data.flux = 0.0
		data.total_flux = 0.0
		data.upgrades = {}
		data.version = SAVE_VERSION
	var rate := beacon_rate()
	if rate > 0.0 and float(data.last_ts) > 0.0:
		var elapsed: float = clamp(Time.get_unix_time_from_system() - float(data.last_ts), 0.0, OFFLINE_CAP_SEC)
		offline_gain = elapsed * rate
		add_flux(offline_gain)


func _process(dt: float) -> void:
	var rate := beacon_rate()
	if rate > 0.0:
		add_flux(rate * dt)
	_save_timer += dt
	if _save_timer > 30.0:
		_save_timer = 0.0
		save_data()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_data()
