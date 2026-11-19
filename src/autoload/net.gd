extends Node
## Session layer (autoload `Net`): host / join by address over ENet, lobby roster,
## match start and return-to-lobby. The host is authoritative for everything.

signal roster_changed
signal status(msg: String)
signal match_begin(params: Dictionary)
signal returned_to_lobby
signal left_session(reason: String)
signal peer_left(peer_id: int)

const D = preload("res://src/core/defs.gd")
const IslandGen = preload("res://src/worldgen/island_gen.gd")
const IslandWorld = preload("res://src/world/island_world.gd")

var roster: Dictionary = {}     # peer_id -> {"name": String, "slot": int}
var in_session := false
var in_match := false
var is_host := false
var forced_seed := -1           # --seed=N replays a world on purpose
var world_kind := "island"      # "island" (generated) or "clearing" (milestone 1-2 fixture)

var _pending_name := ""
var _cached_island: RefCounted = null   # host: the island validated in start_match, reused by the match


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
	roster = {1: {"name": _clean_name(player_name, 0), "slot": 0}}
	status.emit("Hosting on port %d. Friends join with your address." % port)
	roster_changed.emit()
	return OK


func join_session(address: String, port: int, player_name: String) -> Error:
	leave_session()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = p
	_pending_name = player_name
	in_session = true
	is_host = false
	status.emit("Connecting to %s:%d ..." % [address, port])
	return OK


func leave_session(reason: String = "") -> void:
	var was := in_session
	var mp := multiplayer.multiplayer_peer
	if mp != null and not (mp is OfflineMultiplayerPeer):
		mp.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster = {}
	in_session = false
	in_match = false
	is_host = false
	if was:
		left_session.emit(reason)


func local_id() -> int:
	return multiplayer.get_unique_id()


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
	_begin_match.rpc(params)


func return_to_lobby() -> void:
	if is_host:
		_return_lobby.rpc()


func _on_peer_connected(id: int) -> void:
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
	if not multiplayer.is_server():
		return
	if roster.has(id):
		roster.erase(id)
		_sync_roster.rpc(roster)
		roster_changed.emit()
		peer_left.emit(id)


@rpc("any_peer", "reliable")
func _register(pname: String, version: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != D.PROTOCOL_VERSION:
		_reject(id, "Version mismatch: update your build.")
		return
	if in_match:
		_reject(id, "A run is already in progress.")
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
	roster[id] = {"name": _clean_name(pname, slot), "slot": slot}
	_sync_roster.rpc(roster)
	roster_changed.emit()


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
	status.emit("Connected. Joining crew...")
	_register.rpc_id(1, _pending_name, D.PROTOCOL_VERSION)


func _on_connection_failed() -> void:
	leave_session("Could not reach the host. Check the address, port, and firewall / VPN.")


func _on_server_disconnected() -> void:
	print("[net] lost the host")
	leave_session("The host closed the session.")


@rpc("authority", "reliable")
func _rejected(reason: String) -> void:
	leave_session(reason)


@rpc("authority", "reliable")
func _sync_roster(r: Dictionary) -> void:
	roster = r
	roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func _begin_match(params: Dictionary) -> void:
	in_match = true
	roster = params["roster"]
	match_begin.emit(params)


@rpc("authority", "call_local", "reliable")
func _return_lobby() -> void:
	in_match = false
	returned_to_lobby.emit()
