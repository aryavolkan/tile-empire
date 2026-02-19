extends Node

## AI Agent Action Space - Converts neural network outputs to game actions

class_name AgentActions

enum Action {
	IDLE,
	EXPAND_TERRITORY,
	SPAWN_SETTLER,
	SPAWN_WARRIOR,
	SPAWN_WORKER,
	UPGRADE_SETTLEMENT,
	RESEARCH_NEXT_TECH,
	MOVE_UNITS_AGGRESSIVE,
	MOVE_UNITS_DEFENSIVE,
	COLLECT_RESOURCES,
	BUILD_GRANARY,
	BUILD_BARRACKS,
	BUILD_MARKETPLACE
}

const NUM_ACTIONS = 13

# Game references
var game_manager: Node
var territory_manager: Node
var tech_tree: Node
var unit_manager: Node

# Agent state
var settlement: Node
var player_index: int = 0
var last_action: Action = Action.IDLE
var action_cooldowns: Dictionary = {}
var invalid_action_attempts: int = 0

func _init():
	# Initialize cooldowns
	for action in Action.values():
		action_cooldowns[action] = 0

func select_action(nn_outputs) -> Action:
	"""
	Select discrete action from neural network outputs using softmax.
	Expects NUM_ACTIONS outputs from the neural network.
	"""
	if nn_outputs.size() != NUM_ACTIONS:
		push_error("Invalid neural network output size: " + str(nn_outputs.size()))
		return Action.IDLE
	
	# Apply softmax to get probabilities
	var probabilities = _softmax(nn_outputs)
	
	# Sample action based on probabilities
	var action = _sample_action(probabilities)
	
	# Check if action is valid/available
	if not is_action_valid(action):
		invalid_action_attempts += 1
		# Find best valid action
		action = get_best_valid_action(probabilities)
	
	last_action = action
	return action

func execute_action(action: Action) -> bool:
	"""Execute the selected action. Returns true if successful."""
	if not is_action_valid(action):
		return false
	
	# Update cooldown
	action_cooldowns[action] = get_action_cooldown(action)
	
	match action:
		Action.IDLE:
			# Do nothing
			return true
			
		Action.EXPAND_TERRITORY:
			return expand_territory()
			
		Action.SPAWN_SETTLER:
			return spawn_unit("settler")
			
		Action.SPAWN_WARRIOR:
			return spawn_unit("warrior")
			
		Action.SPAWN_WORKER:
			return spawn_unit("worker")
			
		Action.UPGRADE_SETTLEMENT:
			return upgrade_settlement()
			
		Action.RESEARCH_NEXT_TECH:
			return research_next_tech()
			
		Action.MOVE_UNITS_AGGRESSIVE:
			return move_units_aggressive()
			
		Action.MOVE_UNITS_DEFENSIVE:
			return move_units_defensive()
			
		Action.COLLECT_RESOURCES:
			return focus_on_resources()
			
		Action.BUILD_GRANARY:
			return build_structure("granary")
			
		Action.BUILD_BARRACKS:
			return build_structure("barracks")
			
		Action.BUILD_MARKETPLACE:
			return build_structure("marketplace")
	
	return false

func update_cooldowns(delta: float):
	"""Update action cooldowns each frame"""
	for action in action_cooldowns:
		if action_cooldowns[action] > 0:
			action_cooldowns[action] -= delta

func is_action_valid(action: Action) -> bool:
	"""Check if an action can be performed"""
	# Check cooldown
	if action_cooldowns.get(action, 0) > 0:
		return false
	
	# Check specific requirements
	match action:
		Action.IDLE:
			return true
			
		Action.EXPAND_TERRITORY:
			return can_expand_territory()
			
		Action.SPAWN_SETTLER:
			return can_spawn_unit("settler")
			
		Action.SPAWN_WARRIOR:
			return can_spawn_unit("warrior")
			
		Action.SPAWN_WORKER:
			return can_spawn_unit("worker")
			
		Action.UPGRADE_SETTLEMENT:
			return can_upgrade_settlement()
			
		Action.RESEARCH_NEXT_TECH:
			return can_research()
			
		Action.MOVE_UNITS_AGGRESSIVE:
			return has_mobile_units()
			
		Action.MOVE_UNITS_DEFENSIVE:
			return has_mobile_units()
			
		Action.COLLECT_RESOURCES:
			return true  # Always valid, just changes focus
			
		Action.BUILD_GRANARY:
			return can_build_structure("granary")
			
		Action.BUILD_BARRACKS:
			return can_build_structure("barracks")
			
		Action.BUILD_MARKETPLACE:
			return can_build_structure("marketplace")
	
	return false

func get_best_valid_action(probabilities) -> Action:
	"""Find the highest probability valid action"""
	var best_action = Action.IDLE
	var best_prob = 0.0
	
	for i in range(NUM_ACTIONS):
		if probabilities[i] > best_prob and is_action_valid(i):
			best_action = i
			best_prob = probabilities[i]
	
	return best_action

func get_action_cooldown(action: Action) -> float:
	"""Get cooldown duration for an action in seconds"""
	match action:
		Action.EXPAND_TERRITORY:
			return 5.0
		Action.SPAWN_SETTLER:
			return 30.0
		Action.SPAWN_WARRIOR:
			return 10.0
		Action.SPAWN_WORKER:
			return 15.0
		Action.UPGRADE_SETTLEMENT:
			return 60.0
		Action.BUILD_GRANARY, Action.BUILD_BARRACKS, Action.BUILD_MARKETPLACE:
			return 20.0
		_:
			return 2.0

# === Action Implementation Functions ===

func expand_territory() -> bool:
	"""Expand to the highest value adjacent tile"""
	if not territory_manager:
		return false
		
	var adjacent_tiles = territory_manager.get_adjacent_unowned_tiles(settlement.position, player_index)
	if adjacent_tiles.is_empty():
		return false
	
	# Find best tile (highest resource value)
	var best_tile = null
	var best_value = -1
	for tile in adjacent_tiles:
		var value = tile.get("resource_value", 0) + tile.get("strategic_value", 0)
		if value > best_value:
			best_value = value
			best_tile = tile
	
	if best_tile:
		return territory_manager.claim_tile(best_tile, player_index)
	return false

func spawn_unit(unit_type: String) -> bool:
	"""Spawn a unit at the settlement"""
	if not settlement or not settlement.has_method("spawn_unit"):
		return false
	return settlement.spawn_unit(unit_type)

func upgrade_settlement() -> bool:
	"""Upgrade settlement to next stage"""
	if not settlement or not settlement.has_method("upgrade"):
		return false
	return settlement.upgrade()

func research_next_tech() -> bool:
	"""Research the next available technology"""
	if not tech_tree:
		return false
		
	var available_techs = tech_tree.get_available_technologies(player_index)
	if available_techs.is_empty():
		return false
	
	# Pick tech with highest priority
	var best_tech = available_techs[0]
	for tech in available_techs:
		if tech.get("priority", 0) > best_tech.get("priority", 0):
			best_tech = tech
	
	return tech_tree.start_research(best_tech.id, player_index)

func move_units_aggressive() -> bool:
	"""Move units toward nearest enemy"""
	if not unit_manager:
		return false
	
	var enemy_pos = get_nearest_enemy_position()
	if enemy_pos == Vector2.ZERO:
		return false
	
	return unit_manager.set_units_stance(player_index, "aggressive", enemy_pos)

func move_units_defensive() -> bool:
	"""Move units to defend borders"""
	if not unit_manager:
		return false
	
	var threatened_tiles = territory_manager.get_threatened_border_tiles(player_index)
	if threatened_tiles.is_empty():
		return false
	
	return unit_manager.set_units_stance(player_index, "defensive", threatened_tiles[0].position)

func focus_on_resources() -> bool:
	"""Set workers to prioritize resource collection"""
	if settlement and settlement.has_method("set_worker_priority"):
		settlement.set_worker_priority("resources")
		return true
	return false

func build_structure(structure_type: String) -> bool:
	"""Build a structure in the settlement"""
	if not settlement or not settlement.has_method("build_structure"):
		return false
	return settlement.build_structure(structure_type)

# === Helper Functions ===

func can_expand_territory() -> bool:
	if not territory_manager:
		return false
	return not territory_manager.get_adjacent_unowned_tiles(settlement.position, player_index).is_empty()

func can_spawn_unit(unit_type: String) -> bool:
	if not settlement:
		return false
	return settlement.has_method("can_spawn_unit") and settlement.can_spawn_unit(unit_type)

func can_upgrade_settlement() -> bool:
	if not settlement:
		return false
	return settlement.has_method("can_upgrade") and settlement.can_upgrade()

func can_research() -> bool:
	if not tech_tree:
		return false
	return not tech_tree.get_available_technologies(player_index).is_empty()

func has_mobile_units() -> bool:
	if not unit_manager:
		return false
	return unit_manager.get_unit_count(player_index, "mobile") > 0

func can_build_structure(structure_type: String) -> bool:
	if not settlement:
		return false
	return settlement.has_method("can_build_structure") and settlement.can_build_structure(structure_type)

func get_nearest_enemy_position() -> Vector2:
	if not game_manager or not game_manager.has_method("get_nearest_enemy"):
		return Vector2.ZERO
	var enemy = game_manager.get_nearest_enemy(player_index)
	return enemy.position if enemy else Vector2.ZERO

func _softmax(values) -> Array[float]:
	"""Convert raw values to probabilities using softmax"""
	var max_val: float = values[0]
	for i in range(1, values.size()):
		if values[i] > max_val:
			max_val = values[i]
	
	var exp_values: Array[float] = []
	var sum_exp = 0.0
	
	# Compute exp(x - max) for numerical stability
	for val in values:
		var exp_val = exp(float(val) - max_val)
		exp_values.append(exp_val)
		sum_exp += exp_val
	
	# Normalize
	var probabilities: Array[float] = []
	for exp_val in exp_values:
		probabilities.append(exp_val / sum_exp)
	
	return probabilities

func _sample_action(probabilities: Array[float]) -> Action:
	"""Sample action from probability distribution"""
	var rand_val = randf()
	var cumulative = 0.0
	
	for i in range(probabilities.size()):
		cumulative += probabilities[i]
		if rand_val <= cumulative:
			return i as Action
	
	return Action.IDLE  # Fallback