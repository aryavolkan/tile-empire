extends Node

## AI Controller - Manages AI agent behavior

class_name AIController

var observer: AgentObserver
var actions: AgentActions
var neural_network: NeuralNetwork
var settlement: Node
var player_id: int = 0

# Performance tracking
var actions_taken: int = 0
var successful_actions: int = 0
var last_action_time: float = 0.0

func _init():
	observer = AgentObserver.new()
	actions = AgentActions.new()

func initialize(settlement_node: Node, player_index: int, nn: NeuralNetwork = null) -> void:
	settlement = settlement_node
	player_id = player_index
	neural_network = nn
	
	# Set up observer and actions
	observer.player_index = player_index
	actions.player_index = player_index
	actions.settlement = settlement
	
	print("AI Controller initialized for player ", player_id)

func set_game_references(game_mgr: Node, territory_mgr: Node, tech_mgr: Node, unit_mgr: Node) -> void:
	# Pass references to both observer and actions
	observer.game_manager = game_mgr
	observer.territory_manager = territory_mgr
	observer.tech_tree = tech_mgr
	
	actions.game_manager = game_mgr
	actions.territory_manager = territory_mgr
	actions.tech_tree = tech_mgr
	actions.unit_manager = unit_mgr

func think_and_act() -> void:
	if not neural_network or not settlement:
		return
		
	# Get current observation
	var observation = observer.get_observation(settlement)
	
	# Run neural network
	var nn_outputs = neural_network.forward(observation)
	
	# Select and execute action
	var action = actions.select_action(nn_outputs)
	var success = actions.execute_action(action)
	
	# Track performance
	actions_taken += 1
	if success:
		successful_actions += 1
	
	last_action_time = Time.get_ticks_msec() / 1000.0

func update(delta: float) -> void:
	# Update action cooldowns
	actions.update_cooldowns(delta)

func get_success_rate() -> float:
	if actions_taken == 0:
		return 0.0
	return float(successful_actions) / float(actions_taken)