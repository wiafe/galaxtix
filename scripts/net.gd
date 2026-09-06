extends Node
## Friends-only Battle Royale: Steam lobby preferred, ENet fallback, one facade.
##
## The transport half is ported from chrono-pulp's `net.gd`, which had already paid for
## the non-obvious parts. Two transports sit behind it, both plain MultiplayerPeers so
## every RPC below is transport-agnostic:
##
##  - **Steam** (preferred): GodotSteam lobby + SteamMultiplayerPeer. Friends-only
##    lobby, overlay invites, Steam Datagram Relay - nobody needs port forwarding.
##  - **ENet** (fallback / LAN / automated tests): raw UDP. Used when Steam is absent,
##    not running, `--no-steam` is passed, or the join target looks like an address.
##
## THE THING THAT BREAKS EVERYTHING IF YOU FORGET IT: under SteamMultiplayerPeer the
## host is **not** peer 1 - peer ids are masked Steam ids. So:
##   * `@rpc("authority", ...)` is silently rejected. Every RPC here is `any_peer`
##     with an explicit sender check against `host_pid`.
##   * `multiplayer.is_server()` must never gate gameplay; use `is_authority()`.
##   * a guest's broadcast does NOT reach other guests. Only the host fans out.
##
## Authority split: the host runs the whole Battle Royale simulation, including the AI.
## Guests send only their own intent (direction, draw, abilities) and render snapshots.

const APP_ID := 480          # Spacewar dev appid; swap for the real one at ship
const NET_PROTO := 1         # bump when the snapshot or handshake changes shape
const PORT := 27016
const MAX_GUESTS := 3        # up to four humans; the other eight cutters stay AI
const LOBBY_TIMEOUT := 6.0   # a disconnected Steam client never calls back at all
const LOBBY_FRIENDS_ONLY := 1 # k_ELobbyTypeFriendsOnly

signal hosting_started()
signal joined()
signal join_failed(reason: String)
signal disconnected()
signal roster_changed()
signal match_started(seed: int, slots: Array)
signal snapshot_received(bytes: PackedByteArray)
signal input_received(peer: int, dir: Vector2i, draw: bool)
signal ability_received(peer: int, hard: bool)
signal board_requested(peer: int)

var peers: Array = []             # host-maintained, host first
var names: Dictionary = {}        # peer id -> display name (host authoritative, fanned out)
var host_pid: int = 1
var lobby_id: int = 0
var steam_ok: bool = false
var steam: Object = null          # the GodotSteam singleton, resolved at runtime so builds without it still parse
var allow_steam: bool = true
var _is_host: bool = false
var _hosting_pending := false
var _lobby_retried := false
var _pending_t := 0.0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if "--no-steam" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		allow_steam = false
	_init_steam()


func _init_steam() -> void:
	if not allow_steam or not ClassDB.class_exists("SteamMultiplayerPeer") \
			or not Engine.has_singleton("Steam"):
		return
	steam = Engine.get_singleton("Steam")
	var res: Dictionary = steam.steamInitEx(APP_ID, false)
	steam_ok = int(res.get("status", 1)) == 0
	if not steam_ok:
		print("[net] Steam init failed (%s) - falling back to ENet" % str(res))
		return
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	if steam.has_signal("join_requested"):
		steam.join_requested.connect(_on_join_requested)
	print("[net] Steam ready as %s" % steam.getPersonaName())


func _process(delta: float) -> void:
	if steam_ok:
		steam.run_callbacks()
	# A lobby request against a disconnected Steam client completes NEVER, not with an
	# error. Without this timeout the pending flag wedges every further Host press.
	if _hosting_pending:
		_pending_t += delta
		if _pending_t > LOBBY_TIMEOUT:
			_hosting_pending = false
			print("[net] Steam lobby request timed out - hosting over ENet instead")
			if not _host_enet():
				join_failed.emit("COULD NOT HOST ON EITHER TRANSPORT")


## The name other players see: Steam persona when available, else the OS user.
func local_name() -> String:
	var n := ""
	if steam_ok:
		n = steam.getPersonaName()
	if n == "":
		n = OS.get_environment("USERNAME")
	if n == "":
		n = OS.get_environment("USER")
	if n == "":
		n = "PILOT"
	return n


func display_name(peer: int) -> String:
	return String(names.get(peer, "PILOT %d" % (peer % 1000)))


# ---------------------------------------------------------------------------
# Hosting
# ---------------------------------------------------------------------------
## Steam: open a friends-only lobby (finishes in `_on_lobby_created`, so hosting is
## asynchronous on this path). ENet: open the UDP server immediately.
## Returns true when the attempt was *started*, not when it completed.
func host(port: int = -1) -> bool:
	if _hosting_pending or not is_offline():
		return false
	if steam_ok and steam.loggedOn():
		_hosting_pending = true
		_pending_t = 0.0
		_lobby_retried = false
		steam.createLobby(LOBBY_FRIENDS_ONLY, MAX_GUESTS + 1)
		return true
	if steam_ok:
		print("[net] Steam client is offline (loggedOn=false) - hosting over ENet")
	return _host_enet(port)


func _host_enet(port: int = -1) -> bool:
	var p := port if port > 0 else PORT
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p, MAX_GUESTS)
	if err != OK:
		join_failed.emit("COULD NOT OPEN PORT %d (ERROR %d)" % [p, err])
		return false
	multiplayer.multiplayer_peer = peer
	_become_host()
	return true


func _become_host() -> void:
	_is_host = true
	host_pid = multiplayer.get_unique_id()
	peers = [host_pid]
	names = {host_pid: local_name()}
	roster_changed.emit()
	hosting_started.emit()


func _on_lobby_created(connect_ok: int, p_lobby_id: int) -> void:
	_hosting_pending = false
	if connect_ok != 1:                       # k_EResultOK
		# The first createLobby on a cold session flakes now and then; one retry usually lands it.
		if not _lobby_retried and steam.loggedOn():
			_lobby_retried = true
			_hosting_pending = true
			_pending_t = 0.0
			print("[net] Steam lobby creation failed (%d) - retrying once" % connect_ok)
			steam.createLobby(LOBBY_FRIENDS_ONLY, MAX_GUESTS + 1)
			return
		print("[net] Steam lobby creation failed again (%d) - hosting over ENet" % connect_ok)
		if not _host_enet():
			join_failed.emit("COULD NOT HOST ON EITHER TRANSPORT")
		return
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer.create_host(0) != OK:
		print("[net] SteamMultiplayerPeer host failed - hosting over ENet instead")
		steam.leaveLobby(p_lobby_id)
		if not _host_enet():
			join_failed.emit("COULD NOT HOST ON EITHER TRANSPORT")
		return
	lobby_id = p_lobby_id
	multiplayer.multiplayer_peer = peer
	_become_host()


# ---------------------------------------------------------------------------
# Joining
# ---------------------------------------------------------------------------
## A purely numeric target on Steam is a lobby id; anything with dots - or Steam
## being unavailable - goes over ENet as an address.
func join(address: String, port: int = -1) -> bool:
	if not is_offline():
		return false
	var t := address.strip_edges()
	if steam_ok and t.is_valid_int():
		if not steam.loggedOn():
			join_failed.emit("STEAM IS OFFLINE - CANNOT JOIN A LOBBY ID")
			return false
		steam.joinLobby(int(t))
		return true
	var parsed := parse_address(t, port if port > 0 else PORT)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(parsed.host, parsed.port)
	if err != OK:
		join_failed.emit("COULD NOT REACH %s:%d (ERROR %d)" % [parsed.host, parsed.port, err])
		return false
	multiplayer.multiplayer_peer = peer
	_is_host = false
	return true


func _on_lobby_joined(lobby: int, _perms: int, _locked: bool, response: int) -> void:
	if _hosting_pending or not is_offline():   # our own membership callback as host
		return
	if response != 1:                          # k_EChatRoomEnterResponseSuccess
		join_failed.emit("COULD NOT ENTER THAT LOBBY (%d)" % response)
		return
	lobby_id = lobby
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer.create_client(steam.getLobbyOwner(lobby), 0) != OK:
		leave()
		join_failed.emit("COULD NOT CONNECT TO THE LOBBY OWNER")
		return
	multiplayer.multiplayer_peer = peer
	_is_host = false


func _on_join_requested(p_lobby_id: int, _friend_id: int) -> void:
	if not is_offline():
		return
	steam.joinLobby(p_lobby_id)


func leave() -> void:
	if steam_ok and lobby_id != 0:
		steam.leaveLobby(lobby_id)
	lobby_id = 0
	host_pid = 1
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_is_host = false
	_hosting_pending = false
	_lobby_retried = false
	peers.clear()
	names.clear()
	roster_changed.emit()


# ---------------------------------------------------------------------------
# Identity / invites
# ---------------------------------------------------------------------------
## Godot installs an `OfflineMultiplayerPeer` when unconfigured, so a null check
## alone reports "online" during solo play.
func is_offline() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer == null or peer is OfflineMultiplayerPeer


func is_host() -> bool:
	return _is_host and not is_offline()


## True when THIS process runs the authoritative simulation: solo, or session host.
func is_authority() -> bool:
	return is_offline() or is_host()


func is_guest() -> bool:
	return not is_offline() and not _is_host


func pending() -> bool:
	return _hosting_pending


func local_id() -> int:
	if is_offline():
		return 1
	return multiplayer.get_unique_id()


func from_host() -> bool:
	return multiplayer.get_remote_sender_id() == host_pid


## What a friend types to join: the Steam lobby id, or host:port over ENet.
func invite_code() -> String:
	if lobby_id != 0:
		return str(lobby_id)
	if is_host():
		return "%s:%d" % [local_ip(), PORT]
	return ""


func local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"


func overlay_available() -> bool:
	return steam_ok and lobby_id != 0 \
		and steam.has_method("isOverlayEnabled") and steam.isOverlayEnabled()


func open_invite_overlay() -> bool:
	if lobby_id == 0 or not steam_ok:
		return false
	steam.activateGameOverlayInviteDialog(lobby_id)
	return true


## Split "host" or "host:port". Static and side-effect free so tests can cover it.
static func parse_address(text: String, default_port: int) -> Dictionary:
	var host_part := text.strip_edges()
	var port := default_port
	var colon := host_part.rfind(":")
	if colon > 0:
		var maybe := host_part.substr(colon + 1).strip_edges()
		if maybe.is_valid_int():
			port = maybe.to_int()
			host_part = host_part.substr(0, colon)
	if host_part.is_empty():
		host_part = "127.0.0.1"
	return {"host": host_part, "port": port}


# ---------------------------------------------------------------------------
# Connection callbacks
# ---------------------------------------------------------------------------
func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	if peers.size() > MAX_GUESTS:
		_refuse.rpc_id(id, "LOBBY FULL")
		return
	if not peers.has(id):
		peers.append(id)
	# The handshake carries who the host is; a guest cannot validate host-only
	# messages until it knows `host_pid`, so this goes first and is not itself gated.
	_hello.rpc_id(id, host_pid, NET_PROTO)


func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	names.erase(id)
	roster_changed.emit()
	if is_host():
		_roster.rpc(peers, names)


func _on_connected() -> void:
	pass   # the roster arrives once the host has seen us and we have answered `_hello`


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	join_failed.emit("CONNECTION REFUSED")


func _on_server_disconnected() -> void:
	leave()
	disconnected.emit()


# ---------------------------------------------------------------------------
# Handshake and roster
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func _hello(pid: int, proto: int) -> void:
	if is_host():
		return
	if proto != NET_PROTO:
		push_error("[net] protocol mismatch: host speaks %d, this build speaks %d" % [proto, NET_PROTO])
		leave()
		join_failed.emit("VERSION MISMATCH - UPDATE ONE SIDE")
		return
	host_pid = pid
	_introduce.rpc_id(host_pid, local_name())
	joined.emit()


@rpc("any_peer", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	leave()
	join_failed.emit(reason)


@rpc("any_peer", "call_remote", "reliable")
func _introduce(name: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not peers.has(id):
		return
	names[id] = name.substr(0, 24)
	roster_changed.emit()
	_roster.rpc(peers, names)


@rpc("any_peer", "call_remote", "reliable")
func _roster(list: Array, name_map: Dictionary) -> void:
	if not from_host():
		return
	peers = list
	names = name_map
	roster_changed.emit()


# ---------------------------------------------------------------------------
# Match traffic
# ---------------------------------------------------------------------------
## Host only. `slots` is [[peer, racer_id, name], ...]; the host is always racer 0.
func start_match(seed: int, slots: Array) -> void:
	if not is_host():
		return
	_match_start.rpc(seed, slots)
	match_started.emit(seed, slots)


@rpc("any_peer", "call_remote", "reliable")
func _match_start(seed: int, slots: Array) -> void:
	if not from_host():
		return
	match_started.emit(seed, slots)


func send_snapshot(bytes: PackedByteArray, reliable := false) -> void:
	if not is_host():
		return
	if reliable:
		_snapshot_reliable.rpc(bytes)
	else:
		_snapshot.rpc(bytes)


func send_board(peer: int, bytes: PackedByteArray) -> void:
	if is_host():
		_snapshot_reliable.rpc_id(peer, bytes)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _snapshot(bytes: PackedByteArray) -> void:
	if from_host():
		snapshot_received.emit(bytes)


@rpc("any_peer", "call_remote", "reliable")
func _snapshot_reliable(bytes: PackedByteArray) -> void:
	if from_host():
		snapshot_received.emit(bytes)


func send_input(dir: Vector2i, draw: bool) -> void:
	if is_guest():
		_intent.rpc_id(host_pid, dir.x, dir.y, draw)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _intent(dx: int, dy: int, draw: bool) -> void:
	if is_host():
		input_received.emit(multiplayer.get_remote_sender_id(), Vector2i(clampi(dx, -1, 1), clampi(dy, -1, 1)), draw)


func send_ability(hard: bool) -> void:
	if is_guest():
		_ability.rpc_id(host_pid, hard)


@rpc("any_peer", "call_remote", "reliable")
func _ability(hard: bool) -> void:
	if is_host():
		ability_received.emit(multiplayer.get_remote_sender_id(), hard)


func request_board() -> void:
	if is_guest():
		_board_request.rpc_id(host_pid)


@rpc("any_peer", "call_remote", "reliable")
func _board_request() -> void:
	if is_host():
		board_requested.emit(multiplayer.get_remote_sender_id())


func diag_line() -> String:
	var transport := "steam" if lobby_id != 0 else ("enet" if not is_offline() else "offline")
	return "[net] %s host=%s peers=%d lobby=%d" % [transport, is_host(), peers.size(), lobby_id]
