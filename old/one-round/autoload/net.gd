extends Node
## Connection, roles and the shared host clock.
##
## Command line (Debug > Customize Run Instances, or after `--` on the CLI):
##   --host [--role A|B]        host immediately, claim that agent and ready up (default A = LEON)
##   --join <ip>                join a host, claim the free agent and ready up
##   --solo                     start a one-PC test session (Tab swaps LEON/NOEL)
##
## Lobby: the host keeps `lobby` (peer id -> {role, ready}) and broadcasts it. Each player
## claims LEON or NOEL and readies; `roles` (peer id -> role) is derived from it for the game.

## Emitted whenever the lobby (and so `roles`) changes.
signal roles_changed
signal failed(reason: String)
signal lost(reason: String)

const PORT := 7777

## peer id -> "A" / "B" (only peers that have claimed an agent)
var roles := {}
## peer id -> {"role": "" | "A" | "B", "ready": bool}
var lobby := {}
var my_role := "A"
var cli := {}

var _offset := 0.0
var _best_rtt := INF
var _ping_timer := 0.0
var _pings_sent := 0


func _ready() -> void:
	_parse_cli()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _parse_cli() -> void:
	var args := OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if i + 1 < args.size() and not String(args[i + 1]).begins_with("--") and key in ["join", "role"]:
				cli[key] = args[i + 1]
				i += 1
			else:
				cli[key] = true
		i += 1


# --- Connecting --------------------------------------------------------------

func host(role := "") -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	lobby = {1: {"role": role, "ready": false}}
	_offset = 0.0
	_apply_lobby()
	return OK


func join(ip: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_best_rtt = INF
	_pings_sent = 0
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roles = {}
	lobby = {}


func is_host() -> bool:
	return multiplayer.is_server()


func is_connected_peer() -> bool:
	var p := multiplayer.multiplayer_peer
	return p != null and not p is OfflineMultiplayerPeer \
		and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func partner_connected() -> bool:
	return lobby.size() >= 2


func in_lobby() -> bool:
	return not lobby.is_empty()


func me() -> Dictionary:
	return lobby.get(multiplayer.get_unique_id(), {"role": "", "ready": false})


## Peer id holding `role` in the lobby, or 0.
func lobby_owner(role: String) -> int:
	for id: int in lobby:
		if lobby[id].role == role:
			return id
	return 0


## Both seats taken and both players ready.
func all_ready() -> bool:
	if lobby.size() < 2:
		return false
	for e: Dictionary in lobby.values():
		if e.role == "" or not e.ready:
			return false
	return true


## Claim an agent ("" releases yours). Clears your ready flag.
func pick(role: String) -> void:
	_request_pick.rpc_id(1, role)


func set_ready(on: bool) -> void:
	_request_ready.rpc_id(1, on)


@rpc("any_peer", "call_local", "reliable")
func _request_pick(role: String) -> void:
	if not is_host() or Game.in_run:
		return
	var id := _sender()
	if not lobby.has(id) or role not in ["", Util.A, Util.B]:
		return
	var holder := lobby_owner(role)
	if role != "" and holder != 0 and holder != id:
		return
	lobby[id] = {"role": role, "ready": false}
	_push_lobby()


@rpc("any_peer", "call_local", "reliable")
func _request_ready(on: bool) -> void:
	if not is_host() or Game.in_run:
		return
	var id := _sender()
	if not lobby.has(id) or (on and lobby[id].role == ""):
		return
	lobby[id].ready = on
	_push_lobby()


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


func _push_lobby() -> void:
	_sync_lobby.rpc(lobby)


@rpc("authority", "call_local", "reliable")
func _sync_lobby(l: Dictionary) -> void:
	lobby = l
	_apply_lobby()


func _apply_lobby() -> void:
	roles = {}
	for id: int in lobby:
		if lobby[id].role != "":
			roles[id] = lobby[id].role
	var mine: String = me().role
	if mine != "":
		my_role = mine
	roles_changed.emit()


func peer_for(role: String) -> int:
	for id: int in roles:
		if roles[id] == role:
			return id
	return 1


## True if the peer that sent the current RPC may act as this role.
func sender_is(role: String) -> bool:
	if Game.solo:
		return true
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	return roles.get(id, "") == role


func local_ips() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			out.append(ip)
	return out


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	if lobby.size() >= 2 or Game.in_run:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	lobby[id] = {"role": "", "ready": false}
	# Nobody can be ready while a seat is changing hands.
	for e: Dictionary in lobby.values():
		e.ready = false
	_push_lobby()


func _on_peer_disconnected(id: int) -> void:
	if lobby.has(id):
		lobby.erase(id)
		for e: Dictionary in lobby.values():
			e.ready = false
		if is_host():
			_push_lobby()
		else:
			_apply_lobby()
		if is_host():
			lost.emit("Partner left.")


func _on_connected() -> void:
	_ping_timer = 0.0


func _on_connection_failed() -> void:
	leave()
	failed.emit("Could not reach host.")


func _on_server_disconnected() -> void:
	leave()
	lost.emit("Host disconnected.")


# --- Shared clock --------------------------------------------------------------

## Seconds on the host's clock. Everyone agrees on this to within a few ms on LAN.
func now() -> float:
	return Time.get_ticks_usec() / 1000000.0 + _offset


func _local() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _process(delta: float) -> void:
	if is_host() or not is_connected_peer():
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = 0.2 if _pings_sent < 15 else 2.0
		_pings_sent += 1
		_ping.rpc_id(1, _local())


@rpc("any_peer", "unreliable")
func _ping(t: float) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), t, now())


@rpc("authority", "unreliable")
func _pong(t: float, host_t: float) -> void:
	var rtt := _local() - t
	if rtt <= _best_rtt * 1.5:
		_best_rtt = minf(_best_rtt, rtt)
		_offset = host_t + rtt * 0.5 - _local()
