extends Node

## Simple CPU Opponent for training AI agents

class_name CPUOpponent

var settlement: Node
var player_id: int = 1
var difficulty: String = "easy"  # easy, medium, hard

# Decision timing
var think_interval: float = 2.0  # seconds between decisions
var time_since_last_think: float = 0.0

# Behavior weights based on difficulty
var behavior_weights: Dictionary = {
	"easy": {
		"expand": 0.4,
		"military": 0.2,
		"economy": 0.3,
		"tech": 0.1
	},
	"medium": {
		"expand": 0.3,
		"military": 0.3,
		"economy": 0.2,
		"tech": 0.2
	},
	"hard": {
		"expand": 0.25,
		"military": 0.35,
		"economy": 0.2,
		"tech": 0.2
	}
}

# References
var game_manager: Node
var territory_manager: Node
var tech_tree: Node

func initialize(settlement_node: Node, player_index: int, diff: String = "easy") -> void:
	settlement = settlement_node
	player_id = player_index
	difficulty = diff
	
	# Adjust think interval based on difficulty
	match difficulty:
		"easy":
			think_interval = 3.0
		"medium":
			think_interval = 2.0
		"hard":
			think_interval = 1.5

func set_game_references(game_mgr: Node, territory_mgr: Node, tech_mgr: Node) -> void:
	game_manager = game_mgr
	territory_manager = territory_mgr
	tech_tree = tech_mgr

func update(delta: float) -> void:
	if not settlement or not is_instance_valid(settlement):
		return
		
	time_since_last_think += delta
	
	if time_since_last_think >= think_interval:
		time_since_last_think = 0.0
		_make_decision()

func _make_decision() -> void:
	# Choose behavior based on weighted random
	var weights = behavior_weights[difficulty]
	var behavior = _weighted_random_choice(weights)
	
	match behavior:
		"expand":
			_try_expand_territory()
		"military":
			_try_military_action()
		"economy":
			_try_economic_action()
		"tech":
			_try_research()

func _weighted_random_choice(weights: Dictionary) -> String:
	var total_weight = 0.0
	for weight in weights.values():
		total_weight += weight
	
	var random_val = randf() * total_weight
	var cumulative = 0.0
	
	for key in weights:
		cumulative += weights[key]
		if random_val <= cumulative:
			return key
	
	return weights.keys()[0]  # Fallback

func _try_expand_territory() -> void:
	if not territory_manager:
		return
		
	# Try to claim adjacent tiles
	var adjacent = territory_manager.get_adjacent_unowned_tiles(settlement.position, player_id)
	if adjacent.is_empty():
		return
	
	# Pick random adjacent tile (easy) or best tile (harder difficulties)
	var target_tile = null
	if difficulty == "easy":
		target_tile = adjacent[randi() % adjacent.size()]
	else:
		# Pick tile with highest value
		var best_value = -1
		for tile in adjacent:
			var value = tile.get("resource_value", 0) + randf() * 2.0  # Some randomness
			if value > best_value:
				best_value = value
				target_tile = tile
	
	if target_tile:
		territory_manager.claim_tile(target_tile, player_id)

func _try_military_action() -> void:
	if not settlement.has_method("can_spawn_unit"):
		return
		
	# Decide between spawning units or moving them
	if randf() < 0.7 and settlement.can_spawn_unit("warrior"):
		settlement.spawn_unit("warrior")
	elif randf() < 0.3 and settlement.can_spawn_unit("archer"):
		settlement.spawn_unit("archer")
	else:
		# Move existing units randomly
		_move_units_randomly()

func _try_economic_action() -> void:
	if not settlement:
		return
		
	# Try to build economic structures or spawn workers
	var action = randi() % 3
	match action:
		0:
			if settlement.has_method("can_spawn_unit") and settlement.can_spawn_unit("worker"):
				settlement.spawn_unit("worker")
		1:
			if settlement.has_method("can_build_structure") and settlement.can_build_structure("granary"):
				settlement.build_structure("granary")
		2:
			if settlement.has_method("can_build_structure") and settlement.can_build_structure("marketplace"):
				settlement.build_structure("marketplace")

func _try_research() -> void:
	if not tech_tree:
		return
		
	# Research random available tech
	var available = tech_tree.get_available_technologies(player_id)
	if not available.is_empty():
		var tech = available[randi() % available.size()]
		tech_tree.start_research(tech.id, player_id)

func _move_units_randomly() -> void:
	# Simple random movement for now
	# In a real implementation, this would command units to move
	pass

func is_destroyed() -> bool:
	return not is_instance_valid(settlement) or (settlement.has_method("is_destroyed") and settlement.is_destroyed())