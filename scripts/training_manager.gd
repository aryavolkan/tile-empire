extends Node

## Training Manager for Tile Empire AI
## Handles headless training episodes with NEAT genomes

class_name TrainingManager

const NeuralNetwork = preload("res://scripts/ai/neural_network.gd")

# Command line arguments
var genome_path: String = ""
var metrics_path: String = ""
var is_headless: bool = false
var map_seed: int = -1
var worker_id: String = ""

# Training configuration
var max_episode_ticks: int = 3000  # 50 seconds at 60 FPS
var action_interval: int = 30  # AI acts every 0.5 seconds
var map_size: String = "small"  # small/medium/large
var enable_cpu_opponents: bool = true
var cpu_difficulty: String = "easy"  # easy/medium/hard

# Episode state
var episode_ticks: int = 0
var episode_start_time: float = 0.0
var ai_agent: Node = null
var ai_settlement: Node = null
var cpu_opponents: Array = []

# Components
var game_manager: Node
var world_generator: Node
var observer: AgentObserver
var actions: AgentActions
var fitness_calc: FitnessCalculator
var neural_net: NeuralNetwork

# Metrics tracking
var agent_data: Dictionary = {}
var episode_data: Dictionary = {}

signal episode_finished(metrics: Dictionary)

func _ready():
	# Parse command line arguments
	_parse_command_line()
	
	# Set up headless mode if requested
	if is_headless:
		OS.set_low_processor_usage_mode(false)
		RenderingServer.render_loop_enabled = false
		
	# Initialize components
	observer = AgentObserver.new()
	actions = AgentActions.new()
	fitness_calc = FitnessCalculator.new()
	
	# Load genome if provided
	if genome_path != "":
		_load_genome()
	
	# Start training episode
	call_deferred("start_episode")

func _parse_command_line():
	"""Parse command line arguments"""
	var args = OS.get_cmdline_args()
	
	for i in range(args.size()):
		var arg = args[i]
		
		if arg == "--genome-path" and i + 1 < args.size():
			genome_path = args[i + 1]
		elif arg == "--metrics-path" and i + 1 < args.size():
			metrics_path = args[i + 1]
		elif arg == "--headless":
			is_headless = true
		elif arg == "--map-seed" and i + 1 < args.size():
			map_seed = int(args[i + 1])
		elif arg == "--worker-id" and i + 1 < args.size():
			worker_id = args[i + 1]
		elif arg == "--training":
			# Training mode flag - handled by main scene
			pass
		elif arg == "--max-ticks" and i + 1 < args.size():
			max_episode_ticks = int(args[i + 1])
		elif arg == "--action-interval" and i + 1 < args.size():
			action_interval = int(args[i + 1])
		elif arg == "--map-size" and i + 1 < args.size():
			map_size = args[i + 1]
		elif arg == "--disable-cpu":
			enable_cpu_opponents = false

func _load_genome():
	"""Load NEAT genome from JSON file"""
	var file = FileAccess.open(genome_path, FileAccess.READ)
	if not file:
		push_error("Failed to open genome file: " + genome_path)
		return
		
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		push_error("Failed to parse genome JSON: " + json.error_string)
		return
	
	var genome_data = json.data
	
	# Create neural network from genome
	neural_net = NeuralNetwork.new()
	neural_net.from_genome(genome_data)
	
	print("Loaded genome with ", genome_data.get("nodes", []).size(), " nodes and ",
		  genome_data.get("connections", []).size(), " connections")

func start_episode():
	"""Initialize a new training episode"""
	print("Starting training episode...")
	
	# Reset episode state
	episode_ticks = 0
	episode_start_time = Time.get_ticks_msec() / 1000.0
	agent_data.clear()
	episode_data.clear()
	
	# Get or create game manager
	game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		push_error("GameManager not found!")
		_finish_episode()
		return
	
	# Initialize world with seed
	if map_seed >= 0:
		game_manager.set_random_seed(map_seed)
	else:
		game_manager.set_random_seed(randi())
	
	# Set map size
	game_manager.set_map_size(map_size)
	
	# Generate world
	game_manager.generate_world()
	
	# Create AI player settlement
	_spawn_ai_player()
	
	# Spawn CPU opponents
	if enable_cpu_opponents:
		_spawn_cpu_opponents()
	
	# Connect components to game systems
	observer.game_manager = game_manager
	observer.territory_manager = game_manager.get_node_or_null("TerritoryManager")
	observer.tech_tree = game_manager.get_node_or_null("TechTree")
	
	actions.game_manager = game_manager
	actions.territory_manager = observer.territory_manager
	actions.tech_tree = observer.tech_tree
	actions.unit_manager = game_manager.get_node_or_null("UnitManager")
	actions.settlement = ai_settlement
	
	# Initialize agent data
	agent_data = {
		"tiles_owned": 1,
		"settlement_stage": 0,
		"buildings_count": 0,
		"techs_unlocked": 0,
		"culture_score": 0,
		"units_killed": 0,
		"units_lost": 0,
		"resource_efficiency": 0.0,
		"territory_growth_rate": 0.0,
		"_prev_tiles_owned": 1,
		"_total_resources_spent": 0,
		"_total_resources_gained": 0,
	}
	
	episode_data = {
		"total_map_tiles": game_manager.get_total_tiles(),
		"victory_achieved": false,
		"victory_type": "none"
	}

func _spawn_ai_player():
	"""Create the AI-controlled player settlement"""
	var spawn_positions = game_manager.get_valid_spawn_positions()
	if spawn_positions.is_empty():
		push_error("No valid spawn positions!")
		_finish_episode()
		return
	
	# Pick random spawn position
	var spawn_pos = spawn_positions[randi() % spawn_positions.size()]
	
	# Create settlement
	ai_settlement = game_manager.create_settlement(spawn_pos, 0)  # Player 0 is AI
	ai_agent = ai_settlement
	observer.player_index = 0
	actions.player_index = 0
	
	print("Spawned AI player at ", spawn_pos)

func _spawn_cpu_opponents():
	"""Create CPU-controlled opponents"""
	var num_opponents = 1
	if map_size == "medium":
		num_opponents = 2
	elif map_size == "large":
		num_opponents = 3
	
	var spawn_positions = game_manager.get_valid_spawn_positions()
	
	for i in range(num_opponents):
		if spawn_positions.is_empty():
			break
			
		var spawn_pos = spawn_positions[randi() % spawn_positions.size()]
		spawn_positions.erase(spawn_pos)
		
		var cpu_settlement = game_manager.create_settlement(spawn_pos, i + 1)
		cpu_settlement.set_ai_difficulty(cpu_difficulty)
		cpu_opponents.append(cpu_settlement)
		
		print("Spawned CPU opponent ", i + 1, " at ", spawn_pos)

func _process(delta: float):
	if not ai_settlement:
		return
		
	# Check if episode should end
	if episode_ticks >= max_episode_ticks:
		_finish_episode()
		return
	
	# Check for victory/defeat
	if _check_episode_end():
		_finish_episode()
		return
	
	# Update episode tick counter
	episode_ticks += 1
	
	# Update action cooldowns
	actions.update_cooldowns(delta)
	
	# AI acts every N ticks
	if episode_ticks % action_interval == 0:
		_ai_think_and_act()
	
	# Update metrics every second
	if episode_ticks % 60 == 0:
		_update_metrics()

func _ai_think_and_act():
	"""Run neural network and execute action"""
	if not neural_net or not ai_settlement:
		return
	
	# Get observation
	var observation = observer.get_observation(ai_settlement)
	
	# Run neural network
	var nn_outputs = neural_net.forward(observation)
	
	# Select and execute action
	var action = actions.select_action(nn_outputs)
	var success = actions.execute_action(action)
	
	if not is_headless:
		print("AI Action: ", AgentActions.Action.keys()[action], " (success: ", success, ")")

func _update_metrics():
	"""Update agent performance metrics"""
	if not ai_settlement:
		return
		
	var current_tiles = observer.get_territory_size(ai_settlement)
	agent_data["tiles_owned"] = current_tiles
	agent_data["settlement_stage"] = ai_settlement.stage
	agent_data["buildings_count"] = _get_total_buildings()
	agent_data["techs_unlocked"] = observer.get_unlocked_tech_count()
	agent_data["culture_score"] = observer.get_culture_score()
	# Units killed/lost would be tracked by combat system
	
	# Territory growth rate (tiles per minute)
	var elapsed_minutes = maxf(episode_ticks / 3600.0, 0.01)  # 60 ticks/sec
	agent_data["territory_growth_rate"] = float(current_tiles - 1) / elapsed_minutes
	
	# Resource efficiency: ratio of territory+buildings gained to time
	var total_output = current_tiles + agent_data["buildings_count"] + int(ai_settlement.stage) * 3
	agent_data["resource_efficiency"] = clampf(float(total_output) / maxf(elapsed_minutes * 10.0, 1.0), 0.0, 1.0)

func _get_total_buildings() -> int:
	"""Count total buildings owned by AI"""
	var total = 0
	total += observer.get_building_count(ai_settlement, "granary")
	total += observer.get_building_count(ai_settlement, "barracks")
	total += observer.get_building_count(ai_settlement, "marketplace")
	# Add other building types as implemented
	return total

func _check_episode_end() -> bool:
	"""Check if episode should end due to victory/defeat"""
	# Check if AI settlement was destroyed
	if not is_instance_valid(ai_settlement) or ai_settlement.is_destroyed():
		return true
	
	# Check victory conditions
	var domination_progress = observer.get_domination_progress()
	if domination_progress >= 0.75:
		episode_data["victory_achieved"] = true
		episode_data["victory_type"] = "domination"
		return true
	
	# Check if all opponents defeated
	var opponents_alive = false
	for cpu in cpu_opponents:
		if is_instance_valid(cpu) and not cpu.is_destroyed():
			opponents_alive = true
			break
	
	if not opponents_alive and enable_cpu_opponents:
		episode_data["victory_achieved"] = true
		episode_data["victory_type"] = "conquest"
		return true
	
	return false

func _finish_episode():
	"""End episode and write metrics"""
	var episode_time = Time.get_ticks_msec() / 1000.0 - episode_start_time
	
	episode_data["ticks_survived"] = episode_ticks
	
	# Update final metrics
	_update_metrics()
	
	# Calculate fitness
	var metrics = fitness_calc.get_metrics_dict(agent_data, episode_data)
	metrics["episode_time"] = episode_time
	metrics["worker_id"] = worker_id
	
	print("Episode finished in ", episode_time, "s. Fitness: ",
		  "T=", metrics.territory_score,
		  " P=", metrics.progression_score,
		  " S=", metrics.survival_score)
	
	# Write metrics to file
	if metrics_path != "":
		_write_metrics(metrics)
	
	# Emit signal
	episode_finished.emit(metrics)
	
	# Quit if headless
	if is_headless:
		get_tree().quit(0)

func _write_metrics(metrics: Dictionary):
	"""Write metrics to JSON file"""
	var file = FileAccess.open(metrics_path, FileAccess.WRITE)
	if not file:
		push_error("Failed to open metrics file: " + metrics_path)
		return
	
	var json_string = JSON.stringify(metrics, "\t")
	file.store_string(json_string)
	file.close()
	
	print("Metrics written to: ", metrics_path)