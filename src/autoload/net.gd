extends Node
## Session layer (autoload `Net`): host / join by address over ENet, lobby roster,
## match start, return-to-lobby and reconnecting to a slot mid-run.
## The host is authoritative for everything.
##
## Reconnect: at match start the host privately hands each player a token. If a client
## drops mid-run, its avatar stays in the match (still subject to it) for
## Tuning.reconnect_grace seconds; the client retries the same address with the token
## and the host gives it its old slot back under the new connection, then sends the
## accepted world and current state. Tokens are only good for this run and this host.

signal roster_changed
signal status(msg: String)
signal match_begin(params: Dictionary)
signal returned_to_lobby
signal left_session(reason: String)
signal peer_left(peer_id: int)
signal peer_rejoined(old_id: int, new_id: int)

const D = preload("res://src/core/defs.gd")
const IslandGen = preload("res://src/worldgen/island_gen.gd")
const IslandWorld = preload("res://src/world/island_world.gd")

var roster: Dictionary = {}     # peer_id -> {"name": String, "slot": int, "away": bool}
var in_session := false
var in_match := false
var is_host := false
var forced_seed := -1           # --seed=N replays a world on purpose
var world_kind := "island"      # "island" (generated) or "clearing" (milestone 1-2 fixture)
var reconnecting := false       # client: trying to get back into a run

var _pending_name := ""
var _cached_island: RefCounted = null   # host: the island validated in start_match, reused by the match
var _match_params: Dictionary = {}      # host: what every peer needs to rebuild this run
var _tokens: Dictionary = {}            # host: token -> current peer id
# client side
var _token := ""
var _last_address := ""
var _last_port := 0
var _retry_until := 0.0


func take_cached_island(seed_value: int, attempt: int) -> RefCounted:
	var g := _cached_island
	_cached_island = null
	if g and g.seed_value == seed_value and g.attempt == attempt:
		return g
	return null


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_session(port: int, player_name: String) -> Error:
	leave_session()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, Tuning.max_players - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = p
	is_host = true
	in_session = true
	roster = {1: {"name": _clean_name(player_name, 0), "slot": 0, "away": false}}
	status.emit("Hosting on port %d. Friends join with your address." % port)
	roster_changed.emit()
	return OK


func join_session(address: String, port: int, player_name: String) -> Error:
	leave_session()
	_last_address = address
	_last_port = port
	return _connect(player_name)


func _connect(player_name: String) -> Error:
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(_last_address, _last_port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = p
	_pending_name = player_name
	in_session = true
	is_host = false
	status.emit(("Reconnecting to %s:%d ..." if reconnecting else "Connecting to %s:%d ...") % [_last_address, _last_port])
	return OK


func leave_session(reason: String = "") -> void:
	var was := in_session
	_close_peer()
	roster = {}
	in_session = false
	in_match = false
	is_host = false
	_tokens.clear()
	if not reconnecting:
		_token = ""
	if was:
		left_session.emit(reason)


func give_up_reconnect() -> void:
	reconnecting = false
	_token = ""
	leave_session("You left the run.")


func _close_peer() -> void:
	var mp := multiplayer.multiplayer_peer
	if mp != null and not (mp is OfflineMultiplayerPeer):
		mp.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func local_id() -> int:
	return multiplayer.get_unique_id()


## Dev / tests: simulate a dropped connection on a client (the reconnect logic takes over).
func debug_drop() -> void:
	if not is_host and in_match:
		_close_peer()
		_on_server_disconnected()


# ------------------------------------------------------------------ host side

func start_match() -> void:
	if not is_host or in_match:
		return
	if roster.size() < Tuning.min_players_to_start:
		status.emit("Need at least %d players." % Tuning.min_players_to_start)
		return
	var seed_value := forced_seed if forced_seed >= 0 else randi() % 1000000000
	var params := {"seed": seed_value, "roster": roster.duplicate(true), "world": world_kind}
	if world_kind == "island":
		# Generate and validate here so every peer rebuilds the same accepted attempt.
		var found := false
		for tries in 4:
			var gen := IslandGen.new()
			if gen.generate(seed_value):
				params["seed"] = seed_value
				params["attempt"] = gen.attempt
				params["checksum"] = IslandWorld.compute_checksum(gen)
				_cached_island = gen
				found = true
				break
			status.emit("Island %d failed validation (%s); trying another." % [seed_value, gen.reject_reason])
			if forced_seed >= 0:
				break
			seed_value = randi() % 1000000000
		if not found:
			status.emit("Could not generate a valid island. Try Start again.")
			return
	_match_params = params
	_tokens.clear()
	_begin_match.rpc(params)
	# Private reconnect tokens, one per player in this run.
	var crypto := Crypto.new()
	for id in roster.keys():
		if int(id) == 1:
			continue
		var token := crypto.generate_random_bytes(16).hex_encode()
		_tokens[token] = int(id)
		_rpc_token.rpc_id(int(id), token)


func return_to_lobby() -> void:
	if is_host:
		# Players who never came back don't belong in the next crew.
		for id in roster.keys():
			if roster[id].get("away", false):
				roster.erase(id)
		_tokens.clear()
		_sync_roster.rpc(roster)
		_return_lobby.rpc()


## The match's grace period ran out for a dropped player: free the slot for good.
func forget_peer(id: int) -> void:
	if not is_host:
		return
	roster.erase(id)
	for t in _tokens.keys():
		if _tokens[t] == id:
			_tokens.erase(t)
	_sync_roster.rpc(roster)
	roster_changed.emit()


func _on_peer_connected(id: int) -> void:
	# Clients also hear about each other, but only the host has direct ENet peers.
	if multiplayer.is_server():
		_relax_timeout(id)   # then wait for _register


## Building a generated island blocks a peer for a few seconds on slow PCs; don't drop
## the connection for that. ENet still notices a peer that is really gone (30 s).
func _relax_timeout(id: int) -> void:
	var mp := multiplayer.multiplayer_peer
	if mp is ENetMultiplayerPeer:
		var pp: ENetPacketPeer = mp.get_peer(id)
		if pp:
			pp.set_timeout(64, 20000, 30000)


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer %d disconnected" % id)
	if not multiplayer.is_server() or not roster.has(id):
		return
	if in_match:
		roster[id]["away"] = true   # keep the slot open for a reconnect
	else:
		roster.erase(id)
	_sync_roster.rpc(roster)
	roster_changed.emit()
	peer_left.emit(id)


@rpc("any_peer", "reliable")
func _register(pname: String, version: int, token: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != D.PROTOCOL_VERSION:
		_reject(id, "Version mismatch: update your build.")
		return
	if in_match:
		_try_rejoin(id, token)
		return
	if roster.size() >= Tuning.max_players:
		_reject(id, "The crew is full.")
		return
	var used := {}
	for r in roster.values():
		used[r["slot"]] = true
	var slot := 0
	while used.has(slot):
		slot += 1
	roster[id] = {"name": _clean_name(pname, slot), "slot": slot, "away": false}
	_sync_roster.rpc(roster)
	roster_changed.emit()


func _try_rejoin(id: int, token: String) -> void:
	# Validate the token and that its slot is really waiting for this player.
	if token == "" or not _tokens.has(token):
		_reject(id, "A run is already in progress.")
		return
	var old: int = _tokens[token]
	if not roster.has(old) or not roster[old].get("away", false):
		_reject(id, "That slot is still in use.")
		return
	var entry: Dictionary = roster[old]
	roster.erase(old)
	entry["away"] = false
	roster[id] = entry
	_tokens[token] = id
	print("[net] peer %d rejoined as %d (%s)" % [old, id, entry["name"]])
	peer_rejoined.emit(old, id)      # the match hands the avatar over and tells the others
	_sync_roster.rpc(roster)
	roster_changed.emit()
	var params := _match_params.duplicate(true)
	params["roster"] = roster.duplicate(true)
	params["rejoin"] = true
	_begin_match.rpc_id(id, params)


func _reject(id: int, reason: String) -> void:
	_rejected.rpc_id(id, reason)
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		var mp := multiplayer.multiplayer_peer
		if mp is ENetMultiplayerPeer:
			mp.disconnect_peer(id))


func _clean_name(n: String, slot: int) -> String:
	var s := n.strip_edges().substr(0, 16)
	if s.is_empty():
		s = "Survivor %d" % (slot + 1)
	return s


# ------------------------------------------------------------------ client side

func _on_connected() -> void:
	_relax_timeout(1)
	status.emit("Connected. Getting back into the run..." if reconnecting else "Connected. Joining crew...")
	_register.rpc_id(1, _pending_name, D.PROTOCOL_VERSION, _token if reconnecting else "")


func _on_connection_failed() -> void:
	if reconnecting:
		_retry_later()
		return
	leave_session("Could not reach the host. Check the address, port, and firewall / VPN.")


func _on_server_disconnected() -> void:
	print("[net] lost the host")
	if in_match and _token != "" and not is_host:
		# Lost the connection mid-run: keep trying to get back into our slot.
		if not reconnecting:
			reconnecting = true
			_retry_until = Time.get_ticks_msec() / 1000.0 + Tuning.reconnect_grace - 5.0
			leave_session("Connection lost. Reconnecting to your slot...")
		_retry_later()
		return
	reconnecting = false
	leave_session("The host closed the session.")


func _retry_later() -> void:
	_close_peer()
	if Time.get_ticks_msec() / 1000.0 > _retry_until or not reconnecting:
		reconnecting = false
		_token = ""
		left_session.emit("Couldn't get back into the run. The host may have ended it.")
		return
	status.emit("Connection lost. Retrying...")
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if reconnecting and not in_session:
			_connect(_pending_name))


@rpc("authority", "reliable")
func _rpc_token(token: String) -> void:
	_token = token


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	reconnecting = false
	_token = ""
	leave_session(reason)


@rpc("authority", "reliable")
func _sync_roster(r: Dictionary) -> void:
	roster = r
	roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func _begin_match(params: Dictionary) -> void:
	in_match = true
	reconnecting = false
	roster = params["roster"]
	match_begin.emit(params)


@rpc("authority", "call_local", "reliable")
func _return_lobby() -> void:
	in_match = false
	_tokens.clear()
	returned_to_lobby.emit()
