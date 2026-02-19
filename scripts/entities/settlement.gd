class_name Settlement
extends Node2D

## Represents a settlement that can grow from hut to empire

signal upgraded(new_stage: SettlementStage)
signal production_completed(item: String)
signal population_changed(new_population: int)

enum SettlementStage {
	HUT,
	VILLAGE,
	TOWN,
	CITY,
	EMPIRE
}

@export var stage: SettlementStage = SettlementStage.HUT
@export var owner_id: int = -1
@export var settlement_name: String = "New Settlement"

var tile: Tile
var population: int = 1
var max_population: int = 2
var growth_progress: float = 0.0
var production_queue: Array = []
var current_production: Dictionary = {}
var buildings: Array[String] = []
var working_tiles: Array[Tile] = []

# Resource generation per turn
var base_food_yield: int = 2
var base_production_yield: int = 1
var base_gold_yield: int = 1
var base_science_yield: int = 0

# Stage requirements
const STAGE_REQUIREMENTS = {
	SettlementStage.VILLAGE: {
		"population": 5,
		"buildings": ["granary"],
		"territory": 6
	},
	SettlementStage.TOWN: {
		"population": 15,
		"buildings": ["granary", "barracks", "marketplace"],
		"territory": 15
	},
	SettlementStage.CITY: {
		"population": 30,
		"buildings": ["granary", "barracks", "marketplace", "temple", "library"],
		"territory": 25
	},
	SettlementStage.EMPIRE: {
		"population": 50,
		"buildings": ["granary", "barracks", "marketplace", "temple", "library", "palace"],
		"territory": 40
	}
}

# Building effects
const BUILDING_EFFECTS = {
	"granary": {"food": 2, "max_population": 3},
	"barracks": {"production": 2, "defense": 10},
	"marketplace": {"gold": 3, "trade_routes": 1},
	"temple": {"happiness": 2, "culture": 1},
	"library": {"science": 3, "culture": 1},
	"palace": {"all_yields": 2, "happiness": 3}
}

func initialize(on_tile: Tile, player_id: int, name: String = "") -> void:
	tile = on_tile
	owner_id = player_id
	self.player_id = player_id
	tile.settlement_id = get_instance_id()
	
	if name.is_empty():
		settlement_name = _generate_settlement_name()
	else:
		settlement_name = name
	
	position = tile.world_position
	working_tiles = [tile]
	
	_update_max_population()
	_update_visuals()

func _generate_settlement_name() -> String:
	var prefixes = ["New", "North", "South", "East", "West", "Old", "Fort", "Port"]
	var suffixes = ["haven", "shire", "ton", "ville", "burg", "field", "wood", "hill"]
	return prefixes[randi() % prefixes.size()] + suffixes[randi() % suffixes.size()]

func process_turn() -> void:
	_process_growth()
	_process_production()
	_check_upgrade_conditions()

func _process_growth() -> void:
	var food_yield = calculate_food_yield()
	var food_consumed = population * 2
	var food_surplus = food_yield - food_consumed
	
	if food_surplus > 0:
		growth_progress += food_surplus
		var growth_threshold = population * 15
		
		if growth_progress >= growth_threshold and population < max_population:
			population += 1
			growth_progress -= growth_threshold
			population_changed.emit(population)
			_assign_worker_to_best_tile()
	elif food_surplus < 0:
		growth_progress = max(0, growth_progress + food_surplus)
		# Starvation could reduce population here

func _process_production() -> void:
	if current_production.is_empty() and not production_queue.is_empty():
		current_production = production_queue.pop_front()
		current_production.progress = 0
	
	if not current_production.is_empty():
		var production_yield = calculate_production_yield()
		current_production.progress += production_yield
		
		if current_production.progress >= current_production.cost:
			_complete_production(current_production.type)
			current_production = {}

func _complete_production(item_type: String) -> void:
	match item_type:
		"settler":
			production_completed.emit("settler")
		"warrior":
			production_completed.emit("warrior")
		_:
			# Building completed
			if item_type in BUILDING_EFFECTS:
				buildings.append(item_type)
				_apply_building_effects(item_type)
				production_completed.emit(item_type)

func _apply_building_effects(building: String) -> void:
	var effects = BUILDING_EFFECTS.get(building, {})
	if "max_population" in effects:
		max_population += effects.max_population
	_update_visuals()

func calculate_food_yield() -> int:
	var total = base_food_yield
	
	# Add yields from worked tiles
	for worked_tile in working_tiles:
		total += worked_tile.get_food_yield()
	
	# Building bonuses
	if "granary" in buildings:
		total += BUILDING_EFFECTS.granary.food
	
	# Stage bonuses
	total += int(stage) * 2
	
	return total

func calculate_production_yield() -> int:
	var total = base_production_yield
	
	# Add yields from worked tiles
	for worked_tile in working_tiles:
		total += worked_tile.get_production_yield()
	
	# Building bonuses
	if "barracks" in buildings:
		total += BUILDING_EFFECTS.barracks.production
	
	# Stage bonuses
	total += int(stage) * 3
	
	return total

func calculate_gold_yield() -> int:
	var total = base_gold_yield
	
	# Add yields from worked tiles
	for worked_tile in working_tiles:
		total += worked_tile.get_gold_yield()
	
	# Building bonuses
	if "marketplace" in buildings:
		total += BUILDING_EFFECTS.marketplace.gold
	
	# Stage bonuses
	total += int(stage) * 2
	
	return total

func calculate_science_yield() -> int:
	var total = base_science_yield
	
	# Building bonuses
	if "library" in buildings:
		total += BUILDING_EFFECTS.library.science
	
	# Stage bonuses
	if stage >= SettlementStage.TOWN:
		total += int(stage) - 1
	
	return total

func can_work_tile(target_tile: Tile) -> bool:
	# Check if tile is within working distance (2 tiles)
	var distance = tile.get_distance(tile.grid_position, target_tile.grid_position)
	return distance <= 2 and target_tile.owner_id == owner_id

func _assign_worker_to_best_tile() -> void:
	# Find best unworked tile within range and assign new population to it
	if not tile:
		return
	var best_tile: Tile = null
	var best_yield: int = -1
	for neighbor in tile.neighbors:
		if neighbor.owner_id == owner_id and neighbor not in working_tiles:
			var total_yield = neighbor.get_food_yield() + neighbor.get_production_yield() + neighbor.get_gold_yield()
			if total_yield > best_yield:
				best_yield = total_yield
				best_tile = neighbor
	if best_tile:
		working_tiles.append(best_tile)

func add_to_production_queue(item_type: String, cost: int) -> void:
	production_queue.append({
		"type": item_type,
		"cost": cost,
		"progress": 0
	})

func can_build(building: String) -> bool:
	# Check prerequisites
	if building in buildings:
		return false
	
	match building:
		"library":
			return "marketplace" in buildings
		"palace":
			return stage >= SettlementStage.CITY
		_:
			return true

func _check_upgrade_conditions() -> void:
	var next_stage = stage + 1
	if next_stage > SettlementStage.EMPIRE:
		return
	
	var requirements = STAGE_REQUIREMENTS[next_stage]
	var can_upgrade = true
	
	# Check population
	if population < requirements.population:
		can_upgrade = false
	
	# Check buildings
	for required_building in requirements.buildings:
		if not required_building in buildings:
			can_upgrade = false
			break
	
	# Territory check would involve querying TerritoryManager
	
	if can_upgrade:
		_upgrade_settlement()

func _upgrade_settlement() -> void:
	stage += 1
	_update_max_population()
	_update_visuals()
	upgraded.emit(stage)

func _update_max_population() -> void:
	match stage:
		SettlementStage.HUT:
			max_population = 5
		SettlementStage.VILLAGE:
			max_population = 15
		SettlementStage.TOWN:
			max_population = 30
		SettlementStage.CITY:
			max_population = 50
		SettlementStage.EMPIRE:
			max_population = 100
	
	# Add building bonuses
	for building in buildings:
		var effects = BUILDING_EFFECTS.get(building, {})
		if "max_population" in effects:
			max_population += effects.max_population

func _update_visuals() -> void:
	# Update sprite/model based on stage
	# This would be implemented based on your visual assets
	pass

func get_defense_strength() -> float:
	var base_defense = 10.0 * (1 + int(stage))
	
	if "barracks" in buildings:
		base_defense += BUILDING_EFFECTS.barracks.defense
	
	# Terrain bonus
	base_defense *= tile.get_defense_bonus()
	
	return base_defense

# === AI Support Methods ===

var player_id: int = -1  # Player/AI identifier
var food: int = 100
var wood: int = 50
var stone: int = 50
var gold: int = 20
var iron: int = 0
var food_rate: float = 2.0
var production_rate: float = 1.0
var gold_rate: float = 1.0
var research_rate: float = 0.0
var ai_controller: Node = null
var ai_difficulty: String = "easy"

func set_ai_difficulty(difficulty: String) -> void:
	ai_difficulty = difficulty
	if not ai_controller:
		ai_controller = preload("res://scripts/ai/cpu_opponent.gd").new()
		add_child(ai_controller)
		ai_controller.initialize(self, player_id, difficulty)

func get_player_id() -> int:
	return player_id

func is_destroyed() -> bool:
	return population <= 0

func can_spawn_unit(unit_type: String) -> bool:
	match unit_type:
		"settler":
			return population > 5 and food >= 100 and production >= 100
		"warrior":
			return "barracks" in buildings and production >= 50
		"worker":
			return food >= 30
		"archer":
			return "barracks" in buildings and production >= 60 and wood >= 30
		_:
			return false

func spawn_unit(unit_type: String) -> bool:
	if not can_spawn_unit(unit_type):
		return false
	
	# Deduct costs
	match unit_type:
		"settler":
			food -= 100
			production -= 100
			population -= 1
		"warrior":
			production -= 50
		"worker":
			food -= 30
		"archer":
			production -= 60
			wood -= 30
	
	# Create unit (simplified - would actually spawn unit entity)
	print("Settlement ", settlement_name, " spawned ", unit_type)
	return true

func can_upgrade() -> bool:
	if stage >= SettlementStage.EMPIRE:
		return false
	
	var next_stage = stage + 1
	var requirements = STAGE_REQUIREMENTS[next_stage]
	
	# Check all requirements
	if population < requirements.population:
		return false
		
	for required_building in requirements.buildings:
		if not required_building in buildings:
			return false
	
	# Check resources
	var upgrade_cost = 100 * (1 + int(stage))
	return production >= upgrade_cost

func upgrade() -> bool:
	if not can_upgrade():
		return false
		
	var upgrade_cost = 100 * (1 + int(stage))
	production -= upgrade_cost
	
	_upgrade_settlement()
	return true

func get_building_count(building_type: String) -> int:
	return buildings.count(building_type)

func can_build_structure(structure_type: String) -> bool:
	if structure_type in buildings:
		return false
		
	match structure_type:
		"granary":
			return wood >= 50
		"barracks":
			return wood >= 60 and stone >= 40
		"marketplace":
			return wood >= 80 and gold >= 50
		"library":
			return "marketplace" in buildings and stone >= 100
		_:
			return false

func build_structure(structure_type: String) -> bool:
	if not can_build_structure(structure_type):
		return false
		
	# Deduct costs
	match structure_type:
		"granary":
			wood -= 50
		"barracks":
			wood -= 60
			stone -= 40
		"marketplace":
			wood -= 80
			gold -= 50
		"library":
			stone -= 100
	
	buildings.append(structure_type)
	_update_yields()
	print("Settlement ", settlement_name, " built ", structure_type)
	return true

func set_worker_priority(priority: String) -> void:
	# Adjust worker behavior based on priority
	print("Settlement ", settlement_name, " set worker priority to ", priority)

func get_garrison_strength() -> float:
	# Simplified garrison calculation
	return get_defense_strength()

func get_defensive_building_count() -> int:
	var count = 0
	if "barracks" in buildings:
		count += 1
	# Add walls, towers, etc. when implemented
	return count

# Resource properties for direct access
var production: int = 50

func _update_yields() -> void:
	# Recalculate resource rates based on buildings and worked tiles
	food_rate = calculate_food_yield()
	production_rate = calculate_production_yield()
	gold_rate = calculate_gold_yield()
	research_rate = calculate_science_yield()