class_name MultiplayerManager
extends Node

## Handles multiplayer networking using Godot 4's MultiplayerAPI

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal game_started()
signal game_state_updated(state: Dictionary)

const DEFAULT_PORT = 7000
const MAX_PLAYERS = 8

var peer: MultiplayerPeer = null
var player_info: Dictionary = {}  # peer_id -> player data
var game_state: Dictionary = {}
var is_host: bool = false

# Player colors for visual distinction
const PLAYER_COLORS = [
	Color.BLUE,
	Color.RED,
	Color.GREEN,
	Color.YELLOW,
	Color.PURPLE,
	Color.CYAN,
	Color.ORANGE,
	Color.PINK
]

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT, player_name: String = "Host") -> int:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	
	if error != OK:
		push_error("Failed to create server: " + str(error))
		return error
	
	multiplayer.multiplayer_peer = peer
	is_host = true
	
	# Add host player info
	var host_id = multiplayer.get_unique_id()
	player_info[host_id] = {
		"name": player_name,
		"color": PLAYER_COLORS[0],
		"ready": false,
		"empire_name": player_name + "'s Empire"
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
	
	# Store local player info to send after connection
	get_node("/root").set_meta("player_name", player_name)
	
	print("Connecting to " + address + ":" + str(port))
	return OK

func close_connection() -> void:
	if peer:
		peer.close()
		multiplayer.multiplayer_peer = null
		player_info.clear()
		game_state.clear()
		is_host = false

func _on_peer_connected(id: int) -> void:
	print("Player connected: " + str(id))
	
	# If we're the host, send current player list to new player
	if is_host:
		rpc_id(id, "_receive_player_list", player_info)

func _on_peer_disconnected(id: int) -> void:
	print("Player disconnected: " + str(id))
	player_info.erase(id)
	player_disconnected.emit(id)
	
	# Update remaining players
	if is_host:
		rpc("_receive_player_list", player_info)

func _on_connected_to_server() -> void:
	print("Connected to server!")
	
	# Send our player info to server
	var player_name = get_node("/root").get_meta("player_name", "Player")
	var my_id = multiplayer.get_unique_id()
	var my_info = {
		"name": player_name,
		"color": PLAYER_COLORS[player_info.size() % PLAYER_COLORS.size()],
		"ready": false,
		"empire_name": player_name + "'s Empire"
	}
	
	rpc_id(1, "_register_player", my_id, my_info)

func _on_connection_failed() -> void:
	push_error("Connection to server failed!")
	multiplayer.multiplayer_peer = null

func _on_server_disconnected() -> void:
	push_error("Server disconnected!")
	close_connection()

@rpc("any_peer", "reliable")
func _register_player(id: int, info: Dictionary) -> void:
	if not is_host:
		return
	
	# Assign a unique color
	info.color = PLAYER_COLORS[player_info.size() % PLAYER_COLORS.size()]
	player_info[id] = info
	
	# Update all clients with new player list
	rpc("_receive_player_list", player_info)

@rpc("authority", "reliable")
func _receive_player_list(info: Dictionary) -> void:
	player_info = info
	for id in info:
		if not id in player_info:
			player_connected.emit(id, info[id])

func set_player_ready(ready: bool) -> void:
	var my_id = multiplayer.get_unique_id()
	if my_id in player_info:
		player_info[my_id].ready = ready
		
		if is_host:
			rpc("_receive_player_list", player_info)
			_check_all_ready()
		else:
			rpc_id(1, "_player_ready_status", my_id, ready)

@rpc("any_peer", "reliable")
func _player_ready_status(id: int, ready: bool) -> void:
	if not is_host:
		return
	
	if id in player_info:
		player_info[id].ready = ready
		rpc("_receive_player_list", player_info)
		_check_all_ready()

func _check_all_ready() -> void:
	if not is_host:
		return
	
	var all_ready = true
	for id in player_info:
		if not player_info[id].ready:
			all_ready = false
			break
	
	if all_ready and player_info.size() >= 2:  # Need at least 2 players
		start_game()

func start_game() -> void:
	if not is_host:
		return
	
	# Initialize game state
	game_state = {
		"turn": 1,
		"phase": "placement",  # Initial settlement placement
		"current_player": player_info.keys()[0],
		"players": {}
	}
	
	# Initialize each player's game data
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

# Synchronize game actions
func sync_tile_claim(tile_position: Vector2i, player_id: int) -> void:
	if is_host:
		rpc("_receive_tile_claim", tile_position, player_id)
	else:
		rpc_id(1, "_request_tile_claim", tile_position, player_id)

@rpc("any_peer", "reliable")
func _request_tile_claim(tile_position: Vector2i, player_id: int) -> void:
	if not is_host:
		return
	
	# Validate the claim
	# This would check with the TileMap and TerritoryManager
	
	rpc("_receive_tile_claim", tile_position, player_id)

@rpc("authority", "reliable")
func _receive_tile_claim(tile_position: Vector2i, player_id: int) -> void:
	# Apply the tile claim locally
	# This would update the TileMap
	pass

func sync_unit_action(unit_id: int, action: String, params: Dictionary) -> void:
	if is_host:
		rpc("_receive_unit_action", unit_id, action, params)
	else:
		rpc_id(1, "_request_unit_action", unit_id, action, params)

@rpc("any_peer", "reliable")
func _request_unit_action(unit_id: int, action: String, params: Dictionary) -> void:
	if not is_host:
		return
	
	# Validate the action
	# This would check with the unit system
	
	rpc("_receive_unit_action", unit_id, action, params)

@rpc("authority", "reliable")
func _receive_unit_action(unit_id: int, action: String, params: Dictionary) -> void:
	# Apply the unit action locally
	pass

func sync_settlement_founded(position: Vector2i, player_id: int, name: String) -> void:
	if is_host:
		rpc("_receive_settlement_founded", position, player_id, name)
	else:
		rpc_id(1, "_request_settlement_found", position, player_id, name)

@rpc("any_peer", "reliable")
func _request_settlement_found(position: Vector2i, player_id: int, name: String) -> void:
	if not is_host:
		return
	
	# Validate the settlement placement
	
	rpc("_receive_settlement_founded", position, player_id, name)

@rpc("authority", "reliable")
func _receive_settlement_founded(position: Vector2i, player_id: int, name: String) -> void:
	# Create the settlement locally
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
	
	_process_end_turn(player_id)

func _process_end_turn(player_id: int) -> void:
	if game_state.current_player != player_id:
		return
	
	# Find next player
	var player_ids = player_info.keys()
	var current_index = player_ids.find(player_id)
	var next_index = (current_index + 1) % player_ids.size()
	
	game_state.current_player = player_ids[next_index]
	
	# Check if all players have taken their turn
	if next_index == 0:
		game_state.turn += 1
		# Process turn-based game logic
	
	rpc("_update_game_state", game_state)

@rpc("authority", "reliable")
func _update_game_state(state: Dictionary) -> void:
	game_state = state
	game_state_updated.emit(state)

func get_current_player_id() -> int:
	return game_state.get("current_player", -1)

func is_my_turn() -> bool:
	return get_current_player_id() == multiplayer.get_unique_id()

func get_player_count() -> int:
	return player_info.size()

func get_player_info(peer_id: int) -> Dictionary:
	return player_info.get(peer_id, {})

func get_my_player_info() -> Dictionary:
	return get_player_info(multiplayer.get_unique_id())