extends Node

## AI Agent Observer - Converts game state to neural network inputs
## Input count: 95 total inputs

class_name AgentObserver

# Constants for normalization
const MAX_TILE_DISTANCE = 50.0  # Max map radius
const MAX_RESOURCE_COUNT = 1000.0
const MAX_POPULATION = 200.0
const MAX_UNITS = 50.0
const MAX_TECH_COUNT = 20.0
const OBSERVATION_RADIUS = 5

# Game references
var game_manager: Node
var territory_manager: Node
var tech_tree: Node
var player_index: int = 0

func _init():
	pass

func get_observation(settlement: Node) -> Array[float]:
	"""
	Get normalized observation vector for the neural network.
	Total inputs: 95
	- Own state: 15 inputs
	- Nearby tiles: 60 inputs (12 tiles * 5 features each)
	- Military: 8 inputs
	- Tech progress: 4 inputs
	- Enemy info: 3 inputs
	- Victory progress: 3 inputs
	- New mechanics: 2 inputs (happiness, trade income)
	"""
	var observation: Array[float] = []
	
	# === Own State (15 inputs) ===
	# Territory size (1)
	observation.append(_normalize(get_territory_size(settlement), 0.0, 100.0))
	
	# Resources (5)
	var resources = get_resources(settlement)
	observation.append(_normalize(resources.food, 0.0, MAX_RESOURCE_COUNT))
	observation.append(_normalize(resources.wood, 0.0, MAX_RESOURCE_COUNT))
	observation.append(_normalize(resources.stone, 0.0, MAX_RESOURCE_COUNT))
	observation.append(_normalize(resources.gold, 0.0, MAX_RESOURCE_COUNT))
	observation.append(_normalize(resources.iron, 0.0, MAX_RESOURCE_COUNT))
	
	# Settlement info (5)
	observation.append(_normalize(settlement.stage, 0.0, 4.0))  # 0=hut, 4=empire
	observation.append(_normalize(settlement.population, 0.0, MAX_POPULATION))
	observation.append(_normalize(get_building_count(settlement, "granary"), 0.0, 10.0))
	observation.append(_normalize(get_building_count(settlement, "barracks"), 0.0, 10.0))
	observation.append(_normalize(get_building_count(settlement, "marketplace"), 0.0, 10.0))
	
	# Resource generation rates (4)
	var rates = get_resource_rates(settlement)
	observation.append(_normalize(rates.food_rate, -10.0, 50.0))
	observation.append(_normalize(rates.production_rate, 0.0, 30.0))
	observation.append(_normalize(rates.gold_rate, 0.0, 20.0))
	observation.append(_normalize(rates.research_rate, 0.0, 15.0))
	
	# === Nearby Tiles (60 inputs) ===
	# Get 12 most relevant tiles in radius (sorted by importance)
	var nearby_tiles = get_nearby_tiles(settlement.position, OBSERVATION_RADIUS)
	nearby_tiles.resize(12)  # Ensure exactly 12 tiles
	
	for tile in nearby_tiles:
		if tile != null:
			# Terrain type (one-hot encoded, 3 values)
			var terrain = get_terrain_type(tile)
			observation.append(1.0 if terrain == "plains" else 0.0)
			observation.append(1.0 if terrain == "hills" else 0.0)
			observation.append(1.0 if terrain == "mountains" else 0.0)
			
			# Ownership (1 value: -1=enemy, 0=neutral, 1=owned)
			observation.append(get_ownership_normalized(tile, player_index))
			
			# Resources on tile (1 value: normalized resource value)
			observation.append(_normalize(get_tile_resource_value(tile), 0.0, 10.0))
		else:
			# Pad with zeros if less than 12 tiles
			observation.append_array([0.0, 0.0, 0.0, 0.0, 0.0])
	
	# === Military (8 inputs) ===
	var units = get_unit_counts(settlement)
	observation.append(_normalize(units.warriors, 0.0, MAX_UNITS))
	observation.append(_normalize(units.archers, 0.0, MAX_UNITS))
	observation.append(_normalize(units.cavalry, 0.0, MAX_UNITS))
	observation.append(_normalize(units.settlers, 0.0, 10.0))
	observation.append(_normalize(units.workers, 0.0, 20.0))
	observation.append(_normalize(units.total_strength, 0.0, 500.0))
	observation.append(_normalize(get_garrison_strength(settlement), 0.0, 100.0))
	observation.append(_normalize(get_defensive_buildings(settlement), 0.0, 5.0))
	
	# === Tech Progress (4 inputs) ===
	observation.append(_normalize(get_unlocked_tech_count(), 0.0, MAX_TECH_COUNT))
	observation.append(_normalize(get_current_research_progress(), 0.0, 1.0))
	observation.append(1.0 if is_researching() else 0.0)
	observation.append(_normalize(get_available_tech_count(), 0.0, 5.0))
	
	# === Enemy Info (3 inputs) ===
	var enemy_info = get_nearest_enemy_info(settlement)
	observation.append(_normalize(enemy_info.distance, 0.0, MAX_TILE_DISTANCE))
	observation.append(_normalize(enemy_info.strength_ratio, 0.0, 3.0))  # clamped
	observation.append(1.0 if enemy_info.is_threatening else 0.0)
	
	# === Victory Progress (3 inputs) ===
	observation.append(get_domination_progress())  # already 0-1
	observation.append(_normalize(get_culture_score(), 0.0, 1000.0))
	observation.append(_normalize(get_tech_victory_progress(), 0.0, 1.0))

	# === New Mechanics (2 inputs) ===
	observation.append(_normalize(get_happiness(settlement), -5.0, 10.0))
	observation.append(_normalize(get_trade_income(settlement), 0.0, 20.0))

	return observation

func _normalize(value: float, min_val: float, max_val: float) -> float:
	"""Normalize value to [0, 1] range"""
	if max_val <= min_val:
		return 0.0
	return clampf((value - min_val) / (max_val - min_val), 0.0, 1.0)

# === Helper functions (would connect to actual game systems) ===

func get_territory_size(settlement: Node) -> int:
	if territory_manager:
		return territory_manager.get_territory_size(player_index)
	return 1

func get_resources(settlement: Node) -> Dictionary:
	return {
		"food": settlement.get("food") if settlement.get("food") != null else 0,
		"wood": settlement.get("wood") if settlement.get("wood") != null else 0,
		"stone": settlement.get("stone") if settlement.get("stone") != null else 0,
		"gold": settlement.get("gold") if settlement.get("gold") != null else 0,
		"iron": settlement.get("iron") if settlement.get("iron") != null else 0,
	}

func get_building_count(settlement: Node, building_type: String) -> int:
	if settlement.has_method("get_building_count"):
		return settlement.get_building_count(building_type)
	return 0

func get_resource_rates(settlement: Node) -> Dictionary:
	return {
		"food_rate": settlement.get("food_rate") if settlement.get("food_rate") != null else 0,
		"production_rate": settlement.get("production_rate") if settlement.get("production_rate") != null else 0,
		"gold_rate": settlement.get("gold_rate") if settlement.get("gold_rate") != null else 0,
		"research_rate": settlement.get("research_rate") if settlement.get("research_rate") != null else 0,
	}

func get_nearby_tiles(position: Vector2, radius: int) -> Array:
	var tiles = []
	if game_manager and game_manager.has_method("get_tiles_in_radius"):
		tiles = game_manager.get_tiles_in_radius(position, radius)
	return tiles

func get_terrain_type(tile: Node) -> String:
	if tile and tile.has_method("get_terrain"):
		return tile.get_terrain()
	return "plains"

func get_ownership_normalized(tile: Node, my_player_index: int) -> float:
	if not tile or not tile.has_method("get_owner"):
		return 0.0
	var owner = tile.get_owner()
	if owner == my_player_index:
		return 1.0
	elif owner >= 0:
		return -1.0
	return 0.0

func get_tile_resource_value(tile: Node) -> float:
	if tile and tile.has_method("get_resource_value"):
		return tile.get_resource_value()
	return 0.0

func get_unit_counts(settlement: Node) -> Dictionary:
	var counts = {
		"warriors": 0,
		"archers": 0,
		"cavalry": 0,
		"settlers": 0,
		"workers": 0,
		"total_strength": 0.0
	}
	
	# Query game_manager for units belonging to this player
	if game_manager and game_manager.has_method("get_player_units"):
		var units = game_manager.get_player_units(player_index)
		for unit in units:
			var utype = unit.get("unit_type") if unit.has_method("get") else null
			if utype == null and "unit_type" in unit:
				utype = unit.unit_type
			match utype:
				Unit.UnitType.WARRIOR:
					counts.warriors += 1
				Unit.UnitType.ARCHER:
					counts.archers += 1
				Unit.UnitType.SCOUT:
					counts.cavalry += 1  # scouts fill cavalry slot
				Unit.UnitType.SETTLER:
					counts.settlers += 1
				Unit.UnitType.WORKER:
					counts.workers += 1
			if unit.has_method("get_combat_strength"):
				counts.total_strength += unit.get_combat_strength()
	
	return counts

func get_garrison_strength(settlement: Node) -> float:
	if settlement.has_method("get_garrison_strength"):
		return settlement.get_garrison_strength()
	return 0.0

func get_defensive_buildings(settlement: Node) -> int:
	if settlement.has_method("get_defensive_building_count"):
		return settlement.get_defensive_building_count()
	return 0

func get_unlocked_tech_count() -> int:
	if tech_tree and tech_tree.has_method("get_unlocked_count"):
		return tech_tree.get_unlocked_count()
	return 0

func get_current_research_progress() -> float:
	if tech_tree and tech_tree.has_method("get_research_progress"):
		return tech_tree.get_research_progress()
	return 0.0

func is_researching() -> bool:
	if tech_tree and tech_tree.has_method("is_researching"):
		return tech_tree.is_researching()
	return false

func get_available_tech_count() -> int:
	if tech_tree and tech_tree.has_method("get_available_tech_count"):
		return tech_tree.get_available_tech_count()
	return 0

func get_nearest_enemy_info(settlement: Node) -> Dictionary:
	var info = {
		"distance": MAX_TILE_DISTANCE,
		"strength_ratio": 1.0,
		"is_threatening": false
	}
	
	if not game_manager or not game_manager.has_method("get_enemy_settlements"):
		return info
	
	var enemies = game_manager.get_enemy_settlements(player_index)
	var my_pos = settlement.position if settlement else Vector2.ZERO
	var nearest_dist = MAX_TILE_DISTANCE
	var nearest_enemy = null
	
	for enemy in enemies:
		var dist = my_pos.distance_to(enemy.position) if enemy else MAX_TILE_DISTANCE
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_enemy = enemy
	
	info.distance = nearest_dist
	
	if nearest_enemy:
		var my_strength = settlement.get_garrison_strength() if settlement.has_method("get_garrison_strength") else 10.0
		var enemy_strength = nearest_enemy.get_garrison_strength() if nearest_enemy.has_method("get_garrison_strength") else 10.0
		info.strength_ratio = enemy_strength / maxf(my_strength, 1.0)
		info.is_threatening = info.strength_ratio > 1.5 and nearest_dist < 15.0
	
	return info

func get_domination_progress() -> float:
	if game_manager and game_manager.has_method("get_domination_progress"):
		return game_manager.get_domination_progress(player_index)
	return 0.0

func get_culture_score() -> float:
	if game_manager and game_manager.has_method("get_culture_score"):
		return game_manager.get_culture_score(player_index)
	return 0.0

func get_tech_victory_progress() -> float:
	if tech_tree and tech_tree.has_method("get_victory_progress"):
		return tech_tree.get_victory_progress()
	return 0.0

func get_happiness(settlement: Node) -> int:
	if settlement.has_method("calculate_happiness"):
		return settlement.calculate_happiness()
	var h = settlement.get("happiness")
	return h if h != null else 0

func get_trade_income(settlement: Node) -> int:
	if settlement.has_method("calculate_trade_income"):
		return settlement.calculate_trade_income()
	var t = settlement.get("trade_income")
	return t if t != null else 0