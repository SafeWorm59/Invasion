extends Node

signal status_changed(message: String, is_error: bool)
signal roster_changed

const PORT: int = 24567
const MAX_PLAYERS: int = 4
const CONNECTION_TIMEOUT_SECONDS: float = 15.0
const PLAYER_SPEED: float = 200.0
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const LOBBY_SCENE: String = "res://scenes/multiplayer_lobby.tscn"
const MULTIPLAYER_MENU_SCENE: String = "res://scenes/multiplayer_menu.tscn"

var is_session_active: bool = false
var is_host: bool = false

var _lobby_peer_ids: Array[int] = []
var _match_started: bool = false
var _local_player: Node2D
var _network_players_root: Node2D
var _player_nodes: Dictionary = {}
var _remote_inputs: Dictionary = {}
var _remote_input_times: Dictionary = {}
var _spawn_origin := Vector2.ZERO
var _state_send_timer: float = 0.0
var _connection_timeout_remaining: float = 0.0
var _last_connection_error: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host_game() -> Error:
	if is_session_active:
		return ERR_ALREADY_IN_USE

	_last_connection_error = ""
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		status_changed.emit("Could not host on port %d (error %d)." % [PORT, err], true)
		return err

	_reset_session_state()
	is_session_active = true
	is_host = true
	_lobby_peer_ids = [1]
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Hosting LAN game on port %d." % PORT, false)

	err = get_tree().change_scene_to_file(LOBBY_SCENE)
	if err != OK:
		_clear_session()
		status_changed.emit("Could not open the multiplayer lobby (error %d)." % err, true)
	return err


func join_game(address: String) -> Error:
	address = address.strip_edges()
	if is_session_active:
		status_changed.emit("A multiplayer session is already active.", true)
		return ERR_ALREADY_IN_USE

	_last_connection_error = ""
	if not address.is_valid_ip_address() or not address.contains("."):
		status_changed.emit("Enter the PC host's LAN IPv4 address.", true)
		return ERR_INVALID_PARAMETER

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	if err != OK:
		status_changed.emit("Could not start the connection (error %d)." % err, true)
		return err

	_reset_session_state()
	is_session_active = true
	is_host = false
	_connection_timeout_remaining = CONNECTION_TIMEOUT_SECONDS
	multiplayer.multiplayer_peer = peer
	status_changed.emit("Connecting to %s:%d..." % [address, PORT], false)
	return OK


func get_local_ipv4_addresses() -> PackedStringArray:
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if (
			address.is_valid_ip_address()
			and address.contains(".")
			and not address.begins_with("127.")
			and not address.begins_with("169.254.")
			and address != "0.0.0.0"
			and not addresses.has(address)
		):
			addresses.append(address)
	return addresses


func get_local_ip_address() -> String:
	var addresses := get_local_ipv4_addresses()
	return addresses[0] if not addresses.is_empty() else ""


func consume_last_connection_error() -> String:
	var message := _last_connection_error
	_last_connection_error = ""
	return message


func get_lobby_peer_ids() -> Array[int]:
	if is_host and is_session_active:
		return _get_current_peer_ids()
	if not _lobby_peer_ids.is_empty():
		return _lobby_peer_ids.duplicate()

	var fallback: Array[int] = [1]
	if is_session_active and multiplayer.get_unique_id() != 1:
		fallback.append(multiplayer.get_unique_id())
	fallback.sort()
	return fallback


func start_match(scene_path: String) -> bool:
	if not is_session_active or not is_host:
		status_changed.emit("Only the host can start the match.", true)
		return false
	if _get_current_peer_ids().size() > MAX_PLAYERS:
		status_changed.emit("The lobby is full.", true)
		return false
	if not _is_known_level_path(scene_path):
		status_changed.emit("The selected level is unavailable.", true)
		return false

	_match_started = true
	_begin_match.rpc(scene_path)
	return true


func cancel_session() -> void:
	_clear_session()


func leave_session() -> void:
	_clear_session()
	var err := get_tree().change_scene_to_file(MULTIPLAYER_MENU_SCENE)
	if err != OK:
		push_error("MultiplayerSession: Could not return to multiplayer menu (error %d)." % err)


func register_local_player(player: Node2D) -> void:
	if not is_session_active or not _match_started or not is_instance_valid(player):
		return
	if _local_player == player:
		return

	_local_player = player
	var local_peer_id := multiplayer.get_unique_id()
	player.set_meta("network_peer_id", local_peer_id)
	player.set_multiplayer_authority(local_peer_id, true)

	var peer_ids := get_lobby_peer_ids()
	if not peer_ids.has(local_peer_id):
		peer_ids.append(local_peer_id)
	peer_ids.sort()

	_spawn_origin = player.global_position
	player.global_position = _spawn_position_for(local_peer_id, peer_ids)
	_player_nodes[local_peer_id] = player
	_ensure_network_players_root()

	for peer_id in peer_ids:
		if peer_id == local_peer_id:
			continue
		_spawn_remote_player(peer_id, peer_ids)

	if is_host:
		for peer_id in peer_ids:
			if peer_id != local_peer_id:
				_remote_inputs[peer_id] = Vector2.ZERO
				_remote_input_times[peer_id] = Time.get_ticks_msec()

	_state_send_timer = 0.0


func _process(delta: float) -> void:
	if _connection_timeout_remaining > 0.0:
		_connection_timeout_remaining = maxf(0.0, _connection_timeout_remaining - delta)
		if _connection_timeout_remaining == 0.0:
			var client_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if (
				is_session_active
				and not is_host
				and (
					client_peer == null
					or client_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED
				)
			):
				_clear_session()
				status_changed.emit(
					"Connection timed out. Check the PC's LAN IPv4 address, same-network Wi-Fi, "
					+ "and inbound UDP %d in Windows Firewall." % PORT,
					true
				)

	if (
		not is_session_active
		or not _match_started
		or not is_instance_valid(_local_player)
	):
		return

	_state_send_timer += delta
	if _state_send_timer < 0.05:
		return
	_state_send_timer = 0.0

	var local_peer_id := multiplayer.get_unique_id()
	if is_host:
		for peer_id in _player_nodes.keys():
			var network_player := _player_nodes.get(peer_id) as Node2D
			if is_instance_valid(network_player):
				_broadcast_player_position.rpc(int(peer_id), network_player.global_position)
	else:
		var movement_input: Vector2 = _local_player.get("network_movement_input")
		_submit_player_input.rpc_id(
			1,
			local_peer_id,
			movement_input
		)


func _physics_process(_delta: float) -> void:
	if not is_session_active or not is_host or not _match_started:
		return

	var now := Time.get_ticks_msec()
	for peer_id in _remote_inputs.keys():
		var remote_player := _player_nodes.get(peer_id) as CharacterBody2D
		if not is_instance_valid(remote_player):
			continue

		var input_received_at := int(_remote_input_times.get(peer_id, now))
		var movement_input: Vector2 = _remote_inputs.get(peer_id, Vector2.ZERO)
		if now - input_received_at > 300:
			movement_input = Vector2.ZERO

		remote_player.velocity = movement_input * PLAYER_SPEED
		remote_player.move_and_slide()


func _reset_session_state() -> void:
	_lobby_peer_ids.clear()
	_match_started = false
	_local_player = null
	_player_nodes.clear()
	_remote_inputs.clear()
	_remote_input_times.clear()
	_network_players_root = null
	_state_send_timer = 0.0
	_connection_timeout_remaining = 0.0


func _clear_session() -> void:
	if is_instance_valid(_network_players_root):
		_network_players_root.queue_free()

	var peer := multiplayer.multiplayer_peer
	is_session_active = false
	is_host = false
	if peer is ENetMultiplayerPeer:
		(peer as ENetMultiplayerPeer).close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_reset_session_state()


func _get_current_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = [1]
	if is_session_active:
		for peer_id in multiplayer.get_peers():
			var id := int(peer_id)
			if not peer_ids.has(id):
				peer_ids.append(id)
	peer_ids.sort()
	return peer_ids


func _is_known_level_path(scene_path: String) -> bool:
	for level in GameManager.get_levels():
		if String(level.get("scene_path", "")) == scene_path:
			return ResourceLoader.exists(scene_path)
	return false


func _ensure_network_players_root() -> void:
	if is_instance_valid(_network_players_root):
		return
	var current_scene := get_tree().current_scene
	if not is_instance_valid(current_scene):
		return
	_network_players_root = Node2D.new()
	_network_players_root.name = "NetworkPlayers"
	current_scene.add_child(_network_players_root)


func _spawn_remote_player(peer_id: int, peer_ids: Array[int]) -> void:
	if _player_nodes.has(peer_id) or not is_instance_valid(_network_players_root):
		return

	var remote_player := PLAYER_SCENE.instantiate() as Node2D
	remote_player.name = "Player_%d" % peer_id
	remote_player.set_meta("network_peer_id", peer_id)
	remote_player.set_multiplayer_authority(peer_id, true)
	_network_players_root.add_child(remote_player)
	remote_player.global_position = _spawn_position_for(peer_id, peer_ids)
	_player_nodes[peer_id] = remote_player


func _spawn_position_for(peer_id: int, peer_ids: Array[int]) -> Vector2:
	var index := peer_ids.find(peer_id)
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(36.0, 0.0),
		Vector2(-36.0, 0.0),
		Vector2(0.0, 36.0),
	]
	if index < 0 or index >= offsets.size():
		index = 0
	return _spawn_origin + offsets[index]


func _publish_lobby_roster() -> void:
	if not is_host or _match_started:
		return
	_set_lobby_roster.rpc(PackedInt32Array(_get_current_peer_ids()))


func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	if _match_started:
		var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if peer != null:
			peer.disconnect_peer(peer_id, true)
		return
	if _get_current_peer_ids().size() > MAX_PLAYERS:
		var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if peer != null:
			peer.disconnect_peer(peer_id, true)
		return
	_publish_lobby_roster()
	status_changed.emit("Player %d joined the lobby." % peer_id, false)


func _on_peer_disconnected(peer_id: int) -> void:
	if is_host and _match_started:
		_remove_player_proxy.rpc(peer_id)
		return
	_forget_player(peer_id)
	if is_host:
		_publish_lobby_roster()
		status_changed.emit("Player %d left the lobby." % peer_id, false)


func _forget_player(peer_id: int) -> void:
	var player := _player_nodes.get(peer_id) as Node2D
	if is_instance_valid(player) and player != _local_player:
		player.queue_free()
	_player_nodes.erase(peer_id)
	_remote_inputs.erase(peer_id)
	_remote_input_times.erase(peer_id)


func _on_connected_to_server() -> void:
	if not is_session_active:
		return
	_connection_timeout_remaining = 0.0
	_lobby_peer_ids = [1, multiplayer.get_unique_id()]
	_lobby_peer_ids.sort()
	roster_changed.emit()
	status_changed.emit("Connected to host.", false)
	var err := get_tree().change_scene_to_file(LOBBY_SCENE)
	if err != OK:
		status_changed.emit("Could not open the multiplayer lobby (error %d)." % err, true)
		_clear_session()


func _on_connection_failed() -> void:
	if not is_session_active:
		return
	_clear_session()
	status_changed.emit(
		"Connection failed. Verify the PC's LAN IPv4 address, that both devices are on the same "
		+ "network, and that inbound UDP %d is allowed in Windows Firewall." % PORT,
		true
	)


func _on_server_disconnected() -> void:
	if not is_session_active:
		return
	_clear_session()
	_last_connection_error = "The host disconnected. Check that the PC host is still running."
	status_changed.emit(_last_connection_error, true)
	var err := get_tree().change_scene_to_file(MULTIPLAYER_MENU_SCENE)
	if err != OK:
		push_error("MultiplayerSession: Could not return to multiplayer menu (error %d)." % err)


@rpc("authority", "call_local", "reliable")
func _remove_player_proxy(peer_id: int) -> void:
	_forget_player(peer_id)


@rpc("authority", "call_local", "reliable")
func _set_lobby_roster(peer_ids: PackedInt32Array) -> void:
	_lobby_peer_ids.clear()
	for peer_id in peer_ids:
		_lobby_peer_ids.append(int(peer_id))
	roster_changed.emit()


@rpc("authority", "call_local", "reliable")
func _begin_match(scene_path: String) -> void:
	if not _is_known_level_path(scene_path):
		status_changed.emit("The host selected an unavailable level.", true)
		return
	_match_started = true
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		status_changed.emit("Could not load the match scene (error %d)." % err, true)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_player_input(peer_id: int, movement_input: Vector2) -> void:
	if not is_session_active or not is_host or not _match_started:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1 or sender_id != peer_id:
		return
	if not _player_nodes.has(sender_id):
		return
	if not is_finite(movement_input.x) or not is_finite(movement_input.y):
		return
	if movement_input.length_squared() > 1.05:
		return

	_remote_inputs[sender_id] = movement_input.limit_length(1.0)
	_remote_input_times[sender_id] = Time.get_ticks_msec()


@rpc("authority", "call_local", "unreliable_ordered")
func _broadcast_player_position(peer_id: int, position: Vector2) -> void:
	var remote_player := _player_nodes.get(peer_id) as Node2D
	if is_instance_valid(remote_player):
		remote_player.global_position = position
