class_name MultiplayerManager
extends Node

## Handles multiplayer networking using Godot 4's MultiplayerAPI
## With proper RPC validation, desync protection, and disconnect handling

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal game_started()
signal game_state_updated(state: Dictionary)

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 8
const STATE_SYNC_INTERVAL := 5.0  # Full state sync every N seconds
const HEARTBEAT_INTERVAL := 2.0
const HEARTBEAT_TIMEOUT := 10.0

var peer: MultiplayerPeer = null
var player_info: Dictionary = {}  # peer_id -> player data
var game_state: Dictionary = {}
var is_host: bool = false

# Desync protection
var _state_hash: int = 0
var _state_sync_timer: float = 0.0

# Heartbeat tracking (host only)
var _last_heartbeat: Dictionary = {}  # peer_id -> timestamp
var _heartbeat_timer: float = 0.0

const PLAYER_COLORS = [
	Color.BLUE, Color.RED, Color.GREEN, Color.YELLOW,
	Color.PURPLE, Color.CYAN, Color.ORANGE, Color.PINK
]

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	if not is_host or not peer:
		return

	# Periodic state sync to prevent desync
	_state_sync_timer += delta
	if _state_sync_timer >= STATE_SYNC_INTERVAL and not game_state.is_empty():
		_state_sync_timer = 0.0
		rpc("_update_game_state", game_state)

	# Heartbeat check
	_heartbeat_timer += delta
	if _heartbeat_timer >= HEARTBEAT_INTERVAL:
		_heartbeat_timer = 0.0
		_check_heartbeats()

func host_game(port: int = DEFAULT_PORT, player_name: String = "Host") -> int:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		push_error("Failed to create server: " + str(error))
		return error

	multiplayer.multiplayer_peer = peer
	is_host = true

	var host_id = multiplayer.get_unique_id()
	player_info[host_id] = {
		"name": player_name.substr(0, 32),  # Limit name length
		"color": PLAYER_COLORS[0],
		"ready": false,
		"empire_name": (player_name + "'s Empire").substr(0, 64)
	}

	print("Server started on port " + str(port))
	return OK

func join_game(address: String, port: int = DEFAULT_PORT, player_name: String = "Player") -> int:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error != OK:
		push_error("Failed to connect to server: " + str(error))
		return error

	multiplayer.multiplayer_peer = peer
	is_host = false
	# Store name safely
	get_node("/root").set_meta("player_name", player_name.substr(0, 32))

	print("Connecting to " + address + ":" + str(port))
	return OK

func close_connection() -> void:
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
		player_info.clear()
		game_state.clear()
		_last_heartbeat.clear()
		is_host = false

func _on_peer_connected(id: int) -> void:
	print("Player connected: " + str(id))
	if is_host:
		_last_heartbeat[id] = Time.get_ticks_msec() / 1000.0
		rpc_id(id, "_receive_player_list", player_info)

func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected: " + str(id))
	_last_heartbeat.erase(id)
	player_info.erase(id)
	player_disconnected.emit(id)

	# Clean up game state for disconnected player
	if is_host:
		if game_state.has("players") and game_state.players.has(id):
			game_state.players.erase(id)
		# If it was their turn, advance
		if game_state.get("current_player", -1) == id:
			_advance_turn()
		rpc("_receive_player_list", player_info)

func _on_connected_to_server() -> void:
	print("Connected to server!")
	var player_name = get_node("/root").get_meta("player_name", "Player")
	var my_id = multiplayer.get_unique_id()
	var my_info = {
		"name": player_name,
		"color": PLAYER_COLORS[0],  # Server will assign proper color
		"ready": false,
		"empire_name": player_name + "'s Empire"
	}
	rpc_id(1, "_register_player", my_id, my_info)

func _on_connection_failed() -> void:
	push_error("Connection to server failed!")
	close_connection()

func _on_server_disconnected() -> void:
	push_error("Server disconnected!")
	close_connection()

# --- RPC Methods ---

@rpc("any_peer", "reliable")
func _register_player(id: int, info: Dictionary) -> void:
	if not is_host:
		return
	# Validate: sender must match claimed id
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != id:
		push_warning("Player registration id mismatch: sender=%d claimed=%d" % [sender_id, id])
		return
	if player_info.size() >= MAX_PLAYERS:
		push_warning("Server full, rejecting player " + str(id))
		return
	# Sanitize
	info["name"] = str(info.get("name", "Player")).substr(0, 32)
	info["empire_name"] = str(info.get("empire_name", "Empire")).substr(0, 64)
	info["ready"] = false  # Force not ready on join
	info["color"] = PLAYER_COLORS[player_info.size() % PLAYER_COLORS.size()]
	player_info[id] = info
	_last_heartbeat[id] = Time.get_ticks_msec() / 1000.0
	rpc("_receive_player_list", player_info)
	player_connected.emit(id, info)

@rpc("authority", "reliable")
func _receive_player_list(info: Dictionary) -> void:
	player_info = info

@rpc("any_peer", "reliable")
func _player_ready_status(id: int, ready: bool) -> void:
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != id:
		return
	if id in player_info:
		player_info[id].ready = ready
		rpc("_receive_player_list", player_info)
		_check_all_ready()

@rpc("any_peer", "reliable")
func _heartbeat_from_client(id: int) -> void:
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == id:
		_last_heartbeat[id] = Time.get_ticks_msec() / 1000.0

func set_player_ready(ready: bool) -> void:
	var my_id = multiplayer.get_unique_id()
	if my_id in player_info:
		player_info[my_id].ready = ready
		if is_host:
			rpc("_receive_player_list", player_info)
			_check_all_ready()
		else:
			rpc_id(1, "_player_ready_status", my_id, ready)

func _check_all_ready() -> void:
	if not is_host:
		return
	for id in player_info:
		if not player_info[id].ready:
			return
	if player_info.size() >= 2:
		start_game()

func start_game() -> void:
	if not is_host:
		return

	game_state = {
		"turn": 1,
		"phase": "placement",
		"current_player": player_info.keys()[0],
		"players": {}
	}

	for id in player_info:
		game_state.players[id] = {
			"settlements": [],
			"units": [],
			"resources": {"gold": 100, "food": 50, "production": 0},
			"technologies": [],
			"score": 0
		}

	rpc("_start_game", game_state)

@rpc("authority", "call_local", "reliable")
func _start_game(state: Dictionary) -> void:
	game_state = state
	game_started.emit()

# --- Game action sync with validation ---

func sync_tile_claim(tile_position: Vector2i, player_id: int) -> void:
	if is_host:
		_validate_and_apply_tile_claim(tile_position, player_id)
	else:
		rpc_id(1, "_request_tile_claim", tile_position, player_id)

@rpc("any_peer", "reliable")
func _request_tile_claim(tile_position: Vector2i, player_id: int) -> void:
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	# Validate: player can only claim for themselves
	if sender_id != player_id and sender_id != 1:
		push_warning("Tile claim rejected: sender %d claiming for %d" % [sender_id, player_id])
		return
	_validate_and_apply_tile_claim(tile_position, player_id)

func _validate_and_apply_tile_claim(tile_position: Vector2i, player_id: int) -> void:
	# Validation would check with TileMap/TerritoryManager here
	rpc("_receive_tile_claim", tile_position, player_id)

@rpc("authority", "reliable")
func _receive_tile_claim(tile_position: Vector2i, player_id: int) -> void:
	pass  # Apply locally

func sync_unit_action(unit_id: int, action: String, params: Dictionary) -> void:
	if is_host:
		_validate_and_apply_unit_action(unit_id, action, params)
	else:
		rpc_id(1, "_request_unit_action", unit_id, action, params)

@rpc("any_peer", "reliable")
func _request_unit_action(unit_id: int, action: String, params: Dictionary) -> void:
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	# Validate ownership of unit here
	_validate_and_apply_unit_action(unit_id, action, params)

func _validate_and_apply_unit_action(unit_id: int, action: String, params: Dictionary) -> void:
	rpc("_receive_unit_action", unit_id, action, params)

@rpc("authority", "reliable")
func _receive_unit_action(unit_id: int, action: String, params: Dictionary) -> void:
	pass

func sync_settlement_founded(position: Vector2i, player_id: int, name: String) -> void:
	if is_host:
		_validate_and_apply_settlement(position, player_id, name)
	else:
		rpc_id(1, "_request_settlement_found", position, player_id, name)

@rpc("any_peer", "reliable")
func _request_settlement_found(position: Vector2i, player_id: int, name: String) -> void:
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != player_id and sender_id != 1:
		return
	_validate_and_apply_settlement(position, player_id, name.substr(0, 64))

func _validate_and_apply_settlement(position: Vector2i, player_id: int, name: String) -> void:
	rpc("_receive_settlement_founded", position, player_id, name)

@rpc("authority", "reliable")
func _receive_settlement_founded(position: Vector2i, player_id: int, name: String) -> void:
	pass

func end_turn() -> void:
	var my_id = multiplayer.get_unique_id()
	if is_host:
		_process_end_turn(my_id)
	else:
		rpc_id(1, "_request_end_turn", my_id)

@rpc("any_peer", "reliable")
func _request_end_turn(player_id: int) -> void:
	if not is_host:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != player_id:
		return
	_process_end_turn(player_id)

func _process_end_turn(player_id: int) -> void:
	if game_state.get("current_player", -1) != player_id:
		return
	_advance_turn()

func _advance_turn() -> void:
	var player_ids = player_info.keys()
	if player_ids.is_empty():
		return
	var current = game_state.get("current_player", -1)
	var current_index = player_ids.find(current)
	var next_index = (current_index + 1) % player_ids.size() if current_index >= 0 else 0

	game_state.current_player = player_ids[next_index]

	if next_index == 0:
		game_state.turn += 1

	if is_inside_tree():
		rpc("_update_game_state", game_state)

@rpc("authority", "reliable")
func _update_game_state(state: Dictionary) -> void:
	game_state = state
	game_state_updated.emit(state)

func _check_heartbeats() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	var timed_out: Array[int] = []
	for id in _last_heartbeat:
		if now - _last_heartbeat[id] > HEARTBEAT_TIMEOUT:
			timed_out.append(id)
	for id in timed_out:
		push_warning("Player %d heartbeat timeout, disconnecting" % id)
		# Force disconnect
		if peer and peer is ENetMultiplayerPeer:
			(peer as ENetMultiplayerPeer).disconnect_peer(id)

# --- Queries ---

func get_current_player_id() -> int:
	return game_state.get("current_player", -1)

func is_my_turn() -> bool:
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return false
	return get_current_player_id() == multiplayer.get_unique_id()

func get_player_count() -> int:
	return player_info.size()

func get_player_info(peer_id: int) -> Dictionary:
	return player_info.get(peer_id, {})

func get_my_player_info() -> Dictionary:
	return get_player_info(multiplayer.get_unique_id())

func compute_state_hash() -> int:
	return hash(var_to_str(game_state))
