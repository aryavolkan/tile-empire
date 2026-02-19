class_name TerritoryManager
extends Node

## Manages territory ownership, expansion, and border conflicts

signal territory_expanded(player_id: int, new_tiles: Array[Tile])
signal territory_lost(player_id: int, lost_tiles: Array[Tile])
signal border_conflict(player1_id: int, player2_id: int, disputed_tiles: Array[Tile])
signal expansion_available(player_id: int, available_tiles: Array[Tile])

var tile_map: HexTileMap
var player_territories: Dictionary = {}  # player_id -> Array[Tile]
var _territory_frontier = null  # Rust-accelerated frontier finder
var expansion_costs: Dictionary = {}  # player_id -> int
var border_tensions: Dictionary = {}  # "player1_player2" -> float

const BASE_EXPANSION_COST = 10
const EXPANSION_COST_MULTIPLIER = 1.2
const BORDER_TENSION_THRESHOLD = 5.0

func initialize(map: HexTileMap) -> void:
	tile_map = map
	tile_map.territory_changed.connect(_on_territory_changed)
	if ClassDB.class_exists(&"TerritoryFrontier"):
		_territory_frontier = ClassDB.instantiate(&"TerritoryFrontier")

func claim_starting_tile(player_id: int, tile: Tile) -> bool:
	if tile.is_owned() or not tile.can_build_settlement():
		return false
	
	tile.set_owner(player_id)
	player_territories[player_id] = [tile]
	expansion_costs[player_id] = BASE_EXPANSION_COST
	
	# Reveal nearby tiles
	tile_map.reveal_tiles_around(tile.grid_position, 2, player_id)
	
	return true

func get_expandable_tiles(player_id: int) -> Array[Tile]:
	# Try Rust-accelerated frontier if available
	if _territory_frontier and tile_map:
		var w: int = tile_map.map_width if "map_width" in tile_map else 50
		var h: int = tile_map.map_height if "map_height" in tile_map else 50
		var owner_grid := PackedInt32Array()
		owner_grid.resize(w * h)
		owner_grid.fill(-1)
		for pid in player_territories:
			for tile in player_territories[pid]:
				var gp = tile.grid_position
				if gp.x >= 0 and gp.x < w and gp.y >= 0 and gp.y < h:
					owner_grid[gp.y * w + gp.x] = pid
		var frontier_positions: Array = _territory_frontier.get_frontier(owner_grid, player_id, w, h)
		var expandable: Array[Tile] = []
		for pos in frontier_positions:
			var tile = tile_map.get_tile_at(pos) if tile_map.has_method("get_tile_at") else null
			if tile and _can_expand_to(player_id, tile):
				expandable.append(tile)
		return expandable

	# GDScript fallback
	var expandable: Array[Tile] = []
	var territory = player_territories.get(player_id, [])
	
	var checked_tiles = {}
	for owned_tile in territory:
		for neighbor in owned_tile.neighbors:
			if checked_tiles.has(neighbor.grid_position):
				continue
			
			checked_tiles[neighbor.grid_position] = true
			
			if _can_expand_to(player_id, neighbor):
				expandable.append(neighbor)
	
	return expandable

func _can_expand_to(player_id: int, tile: Tile) -> bool:
	# Cannot expand to water or already owned tiles
	if tile.type == Tile.TileType.WATER or tile.is_owned():
		return false
	
	# Check if tile is adjacent to player's territory
	for neighbor in tile.neighbors:
		if neighbor.owner_id == player_id:
			return true
	
	return false

func expand_territory(player_id: int, target_tile: Tile) -> bool:
	if not _can_expand_to(player_id, target_tile):
		return false
	
	var cost = get_expansion_cost(player_id)
	# Here you would check if player has enough resources
	
	target_tile.set_owner(player_id)
	player_territories[player_id].append(target_tile)
	
	# Increase expansion cost
	expansion_costs[player_id] = int(cost * EXPANSION_COST_MULTIPLIER)
	
	# Check for border conflicts
	_check_border_conflicts(player_id, target_tile)
	
	# Reveal more tiles
	tile_map.reveal_tiles_around(target_tile.grid_position, 1, player_id)
	
	territory_expanded.emit(player_id, [target_tile])
	
	# Check for new expansion opportunities
	var new_expandable = get_expandable_tiles(player_id)
	if new_expandable.size() > 0:
		expansion_available.emit(player_id, new_expandable)
	
	return true

func get_expansion_cost(player_id: int) -> int:
	return expansion_costs.get(player_id, BASE_EXPANSION_COST)

func _check_border_conflicts(player_id: int, new_tile: Tile) -> void:
	var adjacent_players = {}
	
	for neighbor in new_tile.neighbors:
		if neighbor.is_owned() and neighbor.owner_id != player_id:
			adjacent_players[neighbor.owner_id] = true
	
	for other_player_id in adjacent_players:
		var tension_key = _get_tension_key(player_id, other_player_id)
		border_tensions[tension_key] = border_tensions.get(tension_key, 0.0) + 1.0
		
		if border_tensions[tension_key] >= BORDER_TENSION_THRESHOLD:
			var disputed = _get_border_tiles(player_id, other_player_id)
			border_conflict.emit(player_id, other_player_id, disputed)

func _get_tension_key(player1_id: int, player2_id: int) -> String:
	var ids = [player1_id, player2_id]
	ids.sort()
	return "%d_%d" % [ids[0], ids[1]]

func _get_border_tiles(player1_id: int, player2_id: int) -> Array[Tile]:
	var border_tiles: Array[Tile] = []
	var territory1 = player_territories.get(player1_id, [])
	
	for tile in territory1:
		for neighbor in tile.neighbors:
			if neighbor.owner_id == player2_id:
				border_tiles.append(tile)
				break
	
	return border_tiles

func transfer_territory(from_player_id: int, to_player_id: int, tiles: Array[Tile]) -> void:
	for tile in tiles:
		if tile.owner_id != from_player_id:
			continue
		
		tile.set_owner(to_player_id)
		player_territories[from_player_id].erase(tile)
		player_territories[to_player_id].append(tile)
	
	if tiles.size() > 0:
		territory_lost.emit(from_player_id, tiles)
		territory_expanded.emit(to_player_id, tiles)

func get_territory_size(player_id: int) -> int:
	return player_territories.get(player_id, []).size()

func get_territory_resources(player_id: int) -> Dictionary:
	var resources = {
		"food": 0,
		"production": 0,
		"gold": 0
	}
	
	var territory = player_territories.get(player_id, [])
	for tile in territory:
		resources.food += tile.get_food_yield()
		resources.production += tile.get_production_yield()
		resources.gold += tile.get_gold_yield()
	
	return resources

func _on_territory_changed(player_id: int, changed_tiles: Array[Tile]) -> void:
	for tile in changed_tiles:
		if not player_territories.has(player_id):
			player_territories[player_id] = []
		player_territories[player_id].append(tile)

func get_border_tension(player1_id: int, player2_id: int) -> float:
	var tension_key = _get_tension_key(player1_id, player2_id)
	return border_tensions.get(tension_key, 0.0)

func register_settlement(settlement: Node, player_id: int) -> void:
	# Register a settlement's starting tile
	if not player_territories.has(player_id):
		player_territories[player_id] = []
		expansion_costs[player_id] = BASE_EXPANSION_COST

func get_adjacent_unowned_tiles(world_position: Vector2, player_id: int) -> Array:
	# Get unowned tiles adjacent to player's territory (used by AI)
	return get_expandable_tiles(player_id)

func claim_tile(tile: Tile, player_id: int) -> bool:
	# Alias for expand_territory used by AI
	return expand_territory(player_id, tile)

signal tile_conquered(conqueror_id: int, prev_owner: int, tile: Tile)

func conquer_tile(tile: Tile, conqueror_id: int) -> bool:
	# Warriors/tanks can take any non-water tile, including enemy-owned ones
	if tile.type == Tile.TileType.WATER:
		return false
	if tile.owner_id == conqueror_id:
		return false  # already ours

	var prev_owner = tile.owner_id
	if prev_owner != -1 and player_territories.has(prev_owner):
		player_territories[prev_owner].erase(tile)

	tile.set_owner(conqueror_id)
	if not player_territories.has(conqueror_id):
		player_territories[conqueror_id] = []
	if not player_territories[conqueror_id].has(tile):
		player_territories[conqueror_id].append(tile)

	territory_expanded.emit(conqueror_id, [tile])
	tile_conquered.emit(conqueror_id, prev_owner, tile)
	return true

func get_threatened_border_tiles(player_id: int) -> Array:
	# Find border tiles where enemy tension is high
	var threatened: Array = []
	var territory = player_territories.get(player_id, [])
	for tile in territory:
		for neighbor in tile.neighbors:
			if neighbor.is_owned() and neighbor.owner_id != player_id:
				threatened.append(tile)
				break
	return threatened

func reduce_border_tension(player1_id: int, player2_id: int, amount: float) -> void:
	var tension_key = _get_tension_key(player1_id, player2_id)
	border_tensions[tension_key] = max(0.0, border_tensions.get(tension_key, 0.0) - amount)

func is_territory_contiguous(player_id: int) -> bool:
	# Check if player's territory is in one connected piece
	var territory = player_territories.get(player_id, [])
	if territory.is_empty():
		return true
	
	var visited = {}
	var to_visit = [territory[0]]
	
	while not to_visit.is_empty():
		var current = to_visit.pop_back()
		if visited.has(current.grid_position):
			continue
		
		visited[current.grid_position] = true
		
		for neighbor in current.neighbors:
			if neighbor.owner_id == player_id and not visited.has(neighbor.grid_position):
				to_visit.append(neighbor)
	
	return visited.size() == territory.size()