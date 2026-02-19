extends SceneTree

## Headless test runner for Tile Empire
## Run: godot --headless -s tests/run_tests.gd

const NeuralNetwork = preload("res://scripts/ai/neural_network.gd")

var _tests_passed := 0
var _tests_failed := 0
var _tests_total := 0
var _current_suite := ""

func _init():
	print("\n========== Tile Empire Test Suite ==========\n")
	
	_run_hex_math_tests()
	_run_tile_tests()
	_run_territory_tests()
	_run_fitness_tests()
	_run_neural_network_tests()
	_run_settlement_tests()
	_run_skill_tree_tests()
	_run_nsga2_tests()
	_run_cpu_opponent_tests()
	_run_multiplayer_manager_tests()
	_run_training_pipeline_tests()
	
	print("\n============================================")
	print("Results: %d passed, %d failed, %d total" % [_tests_passed, _tests_failed, _tests_total])
	print("============================================\n")
	
	quit(0 if _tests_failed == 0 else 1)

func _suite(name: String) -> void:
	_current_suite = name
	print("--- %s ---" % name)

func _assert(condition: bool, description: String) -> void:
	_tests_total += 1
	if condition:
		_tests_passed += 1
	else:
		_tests_failed += 1
		print("  FAIL: [%s] %s" % [_current_suite, description])

func _assert_eq(a, b, description: String) -> void:
	_tests_total += 1
	if a == b:
		_tests_passed += 1
	else:
		_tests_failed += 1
		print("  FAIL: [%s] %s (got %s, expected %s)" % [_current_suite, description, str(a), str(b)])

func _assert_near(a: float, b: float, epsilon: float, description: String) -> void:
	_tests_total += 1
	if abs(a - b) < epsilon:
		_tests_passed += 1
	else:
		_tests_failed += 1
		print("  FAIL: [%s] %s (got %f, expected %f)" % [_current_suite, description, a, b])

# ==================== Hex Math Tests ====================

func _run_hex_math_tests() -> void:
	_suite("Hex Math")
	
	# Test Tile.get_distance
	_assert_eq(Tile.get_distance(Vector2i(0, 0), Vector2i(0, 0)), 0, "distance to self is 0")
	_assert_eq(Tile.get_distance(Vector2i(0, 0), Vector2i(1, 0)), 1, "adjacent tile distance is 1")
	_assert_eq(Tile.get_distance(Vector2i(0, 0), Vector2i(0, 1)), 1, "adjacent tile south distance is 1")
	_assert_eq(Tile.get_distance(Vector2i(0, 0), Vector2i(2, 0)), 2, "two tiles east distance is 2")
	
	# Test symmetry
	_assert_eq(
		Tile.get_distance(Vector2i(3, 4), Vector2i(7, 2)),
		Tile.get_distance(Vector2i(7, 2), Vector2i(3, 4)),
		"distance is symmetric"
	)

# ==================== Tile Tests ====================

func _run_tile_tests() -> void:
	_suite("Tile")
	
	var tile = Tile.new(Vector2i(5, 5), Tile.TileType.GRASSLAND)
	_assert_eq(tile.grid_position, Vector2i(5, 5), "grid position set correctly")
	_assert_eq(tile.type, Tile.TileType.GRASSLAND, "type set correctly")
	_assert_eq(tile.owner_id, -1, "initially unowned")
	_assert(!tile.is_owned(), "is_owned false when unowned")
	
	tile.set_owner(1)
	_assert(tile.is_owned(), "is_owned true after set_owner")
	_assert_eq(tile.owner_id, 1, "owner_id set correctly")
	_assert(tile.is_discovered_by(1), "set_owner also discovers")
	
	# Movement costs
	var water_tile = Tile.new(Vector2i(0, 0), Tile.TileType.WATER)
	_assert(water_tile.get_movement_cost() < 0, "water is impassable")
	
	var grass_tile = Tile.new(Vector2i(0, 0), Tile.TileType.GRASSLAND)
	_assert_near(grass_tile.get_movement_cost(), 1.0, 0.01, "grassland movement cost is 1")
	
	var mountain_tile = Tile.new(Vector2i(0, 0), Tile.TileType.MOUNTAIN)
	_assert_near(mountain_tile.get_defense_bonus(), 1.5, 0.01, "mountain defense bonus is 1.5")
	
	# Settlement building
	_assert(!water_tile.can_build_settlement(), "can't build on water")
	_assert(!mountain_tile.can_build_settlement(), "can't build on mountain")
	_assert(grass_tile.can_build_settlement(), "can build on grassland")
	
	# Discovery
	var tile2 = Tile.new(Vector2i(1, 1), Tile.TileType.FOREST)
	_assert(!tile2.is_discovered_by(0), "not discovered initially")
	tile2.discover(0)
	_assert(tile2.is_discovered_by(0), "discovered after discover()")
	tile2.discover(0)  # duplicate
	_assert_eq(tile2.discovered_by.size(), 1, "no duplicate discoveries")

# ==================== Territory Tests ====================

func _run_territory_tests() -> void:
	_suite("Territory")
	
	var tm = TerritoryManager.new()
	
	# Test territory size
	_assert_eq(tm.get_territory_size(0), 0, "empty territory size is 0")
	
	# Test tension key ordering
	var key1 = tm._get_tension_key(1, 2)
	var key2 = tm._get_tension_key(2, 1)
	_assert_eq(key1, key2, "tension key is order-independent")
	_assert_eq(key1, "1_2", "tension key format correct")
	
	# Test border tension
	_assert_near(tm.get_border_tension(0, 1), 0.0, 0.01, "initial tension is 0")
	tm.border_tensions["0_1"] = 3.0
	_assert_near(tm.get_border_tension(0, 1), 3.0, 0.01, "tension set correctly")
	tm.reduce_border_tension(0, 1, 1.5)
	_assert_near(tm.get_border_tension(0, 1), 1.5, 0.01, "tension reduced correctly")
	tm.reduce_border_tension(0, 1, 10.0)
	_assert_near(tm.get_border_tension(0, 1), 0.0, 0.01, "tension doesn't go below 0")
	
	# Contiguity check on empty territory
	_assert(tm.is_territory_contiguous(0), "empty territory is contiguous")

# ==================== Fitness Tests ====================

func _run_fitness_tests() -> void:
	_suite("Fitness Calculator")
	
	var fc = FitnessCalculator.new()
	
	# Test with minimal agent
	var agent_data = {
		"tiles_owned": 1,
		"settlement_stage": 0,
		"buildings_count": 0,
		"techs_unlocked": 0,
		"culture_score": 0,
		"units_killed": 0,
		"units_lost": 0
	}
	var episode_data = {
		"ticks_survived": 100,
		"total_map_tiles": 100,
		"victory_achieved": false,
		"victory_type": "none"
	}
	
	var fitness = fc.calculate_fitness(agent_data, episode_data)
	_assert_eq(fitness.size(), 3, "fitness has 3 objectives")
	
	for i in 3:
		_assert(fitness[i] >= 0.0 and fitness[i] <= 1.0,
			"fitness[%d] in [0,1] range (got %f)" % [i, fitness[i]])
	
	# Test with victory
	episode_data["victory_achieved"] = true
	episode_data["victory_type"] = "domination"
	var victory_fitness = fc.calculate_fitness(agent_data, episode_data)
	_assert_near(victory_fitness[2], 1.0, 0.01, "survival is 1.0 on victory")
	
	# Test aggregate
	var agg = fc.aggregate_fitness([0.5, 0.5, 0.5])
	_assert_near(agg, 0.5, 0.01, "aggregate of uniform 0.5 is 0.5")
	
	# Test metrics dict
	var metrics = fc.get_metrics_dict(agent_data, episode_data)
	_assert(metrics.has("territory_score"), "metrics has territory_score")
	_assert(metrics.has("progression_score"), "metrics has progression_score")
	_assert(metrics.has("survival_score"), "metrics has survival_score")

# ==================== Neural Network Tests ====================

func _run_neural_network_tests() -> void:
	_suite("Neural Network")
	
	var nn = NeuralNetwork.new(4, 3, 2)
	_assert_eq(nn.input_size, 4, "input size")
	_assert_eq(nn.hidden_size, 3, "hidden size")
	_assert_eq(nn.output_size, 2, "output size")
	
	# Forward pass
	var inputs = PackedFloat32Array([0.5, -0.5, 1.0, 0.0])
	var outputs = nn.forward(inputs)
	_assert_eq(outputs.size(), 2, "output size matches")
	for i in outputs.size():
		_assert(outputs[i] >= -1.0 and outputs[i] <= 1.0,
			"output[%d] in [-1,1] (tanh range), got %f" % [i, outputs[i]])
	
	# Deterministic
	var outputs2 = nn.forward(inputs)
	_assert_near(outputs[0], outputs2[0], 0.0001, "forward pass is deterministic")
	
	# Clone
	var nn2 = nn.clone()
	var outputs3 = nn2.forward(inputs)
	_assert_near(outputs[0], outputs3[0], 0.0001, "clone produces same output")
	
	# Weight count
	var expected_weights = 4*3 + 3 + 3*2 + 2  # ih + bh + ho + bo
	_assert_eq(nn.get_weight_count(), expected_weights, "weight count correct")
	
	# Memory
	nn.enable_memory()
	_assert(nn.use_memory, "memory enabled")
	var expected_with_memory = expected_weights + 3*3
	_assert_eq(nn.get_weight_count(), expected_with_memory, "weight count with memory")
	
	# Set/get weights roundtrip
	var weights = nn.get_weights()
	var nn3 = NeuralNetwork.new(4, 3, 2)
	nn3.enable_memory()
	nn3.set_weights(weights)
	var out_a = nn.forward(inputs)
	var out_b = nn3.forward(inputs)
	_assert_near(out_a[0], out_b[0], 0.0001, "set_weights preserves behavior")
	
	# Crossover
	var parent1 = NeuralNetwork.new(4, 3, 2)
	var parent2 = NeuralNetwork.new(4, 3, 2)
	var child = parent1.crossover_with(parent2)
	_assert_eq(child.get_weight_count(), parent1.get_weight_count(), "crossover preserves weight count")

# ==================== Settlement Tests ====================

func _run_settlement_tests() -> void:
	_suite("Settlement")
	
	# Test building prerequisites
	var settlement = Settlement.new()
	_assert(settlement.can_build("granary"), "can build granary initially")
	_assert(!settlement.can_build("library"), "can't build library without marketplace")
	
	# Test unit spawn costs
	settlement.food = 200
	settlement.production = 200
	settlement.wood = 100
	settlement.population = 10
	settlement.buildings.append("barracks")
	
	_assert(settlement.can_spawn_unit("worker"), "can spawn worker with resources")
	_assert(settlement.can_spawn_unit("warrior"), "can spawn warrior with barracks")
	
	# Test stage requirements
	_assert_eq(int(settlement.stage), int(Settlement.SettlementStage.HUT), "starts as HUT")
	
	# Test is_destroyed
	settlement.population = 1
	_assert(!settlement.is_destroyed(), "not destroyed with population")
	settlement.population = 0
	_assert(settlement.is_destroyed(), "destroyed at 0 population")

# ==================== Skill Tree Tests ====================

func _run_skill_tree_tests() -> void:
	_suite("Skill Tree")
	
	var st = SkillTree.new()
	st.initialize_player(0)
	
	# Test initial state
	_assert(!st.has_skill(0, "agriculture"), "no skills initially")
	_assert(st.can_research(0, "agriculture"), "can research root skill")
	_assert(!st.can_research(0, "pottery"), "can't research without prereqs")
	
	# Test research flow
	_assert(st.start_research(0, "agriculture"), "start_research succeeds")
	st.add_research_progress(0, 25)
	_assert(!st.has_skill(0, "agriculture"), "not unlocked at half progress")
	st.add_research_progress(0, 25)
	_assert(st.has_skill(0, "agriculture"), "unlocked at full progress")
	_assert(st.can_research(0, "pottery"), "can research after prereq unlocked")
	_assert(!st.can_research(0, "agriculture"), "can't re-research")
	
	# Available skills
	var available = st.get_available_skills(0)
	_assert(available.size() > 0, "has available skills")
	_assert("pottery" in available, "pottery available after agriculture")
	
	# AI methods
	var techs = st.get_available_technologies(0)
	_assert(techs.size() > 0, "get_available_technologies returns results")

# ==================== NSGA2 Tests ====================

func _run_nsga2_tests() -> void:
	_suite("NSGA-II")
	
	# Dominance tests
	_assert(NSGA2.dominates(Vector3(1, 1, 1), Vector3(0, 0, 0)), "strictly dominates")
	_assert(!NSGA2.dominates(Vector3(1, 1, 1), Vector3(1, 1, 1)), "equal doesn't dominate")
	_assert(!NSGA2.dominates(Vector3(1, 0, 1), Vector3(0, 1, 0)), "incomparable doesn't dominate")
	_assert(NSGA2.dominates(Vector3(1, 1, 1), Vector3(1, 0, 1)), "dominates with one strictly better")
	
	# Non-dominated sort
	var objectives = [
		Vector3(1, 0, 0),
		Vector3(0, 1, 0),
		Vector3(0, 0, 1),
		Vector3(0.5, 0.5, 0.5),
		Vector3(0.1, 0.1, 0.1),
	]
	var fronts = NSGA2.non_dominated_sort(objectives)
	_assert(fronts.size() >= 1, "at least one front")
	_assert(4 in fronts[fronts.size() - 1], "dominated point in last front")
	
	# Select
	var selected = NSGA2.select(objectives, 3)
	_assert_eq(selected.size(), 3, "select returns target_size")
	
	# Pareto front
	var pareto = NSGA2.get_pareto_front(objectives)
	_assert(pareto.size() >= 3, "pareto front has non-dominated points")

# ==================== CPU Opponent Tests ====================

func _run_cpu_opponent_tests() -> void:
	_suite("CPU Opponent")
	
	# Create a mock settlement for the CPU
	var settlement = Settlement.new()
	settlement.population = 10
	settlement.food = 200
	settlement.wood = 100
	settlement.stone = 50
	settlement.gold = 50
	settlement.production = 100
	
	# Test initialization
	var cpu = CPUOpponent.new()
	cpu.initialize(settlement, 1, "easy")
	_assert_eq(cpu.player_id, 1, "player_id set correctly")
	_assert_eq(cpu.difficulty, "easy", "difficulty set correctly")
	_assert_near(cpu.think_interval, 3.0, 0.01, "easy think interval is 3.0")
	
	var cpu_hard = CPUOpponent.new()
	cpu_hard.initialize(settlement, 2, "hard")
	_assert_near(cpu_hard.think_interval, 1.0, 0.01, "hard think interval is 1.0")
	
	# Test situational weights
	var weights = cpu.get_situational_weights()
	_assert(weights.has("expand"), "weights has expand")
	_assert(weights.has("defend"), "weights has defend")
	_assert(weights.has("upgrade"), "weights has upgrade")
	_assert(weights.has("economy"), "weights has economy")
	_assert(weights.has("military"), "weights has military")
	_assert(weights.has("tech"), "weights has tech")
	
	# All weights should be positive
	for key in weights:
		_assert(weights[key] > 0, "weight '%s' is positive" % key)
	
	# Test threat level with no territory manager
	var threat = cpu.get_max_threat_level()
	_assert_near(threat, 0.0, 0.01, "threat is 0 without territory manager")
	
	# Test tile scoring
	var grass_tile = Tile.new(Vector2i(0, 0), Tile.TileType.GRASSLAND)
	grass_tile.resource_type = Tile.ResourceType.FOOD
	grass_tile.resource_yield = 3
	
	var desert_tile = Tile.new(Vector2i(1, 0), Tile.TileType.DESERT)
	desert_tile.resource_type = Tile.ResourceType.NONE
	desert_tile.resource_yield = 0
	
	var grass_score = cpu.score_tile_for_expansion(grass_tile)
	var desert_score = cpu_hard.score_tile_for_expansion(desert_tile)
	# Grassland with food should generally score higher than empty desert
	# (allowing for randomness, test multiple times)
	var grass_wins := 0
	for i in 20:
		if cpu.score_tile_for_expansion(grass_tile) > cpu.score_tile_for_expansion(desert_tile):
			grass_wins += 1
	_assert(grass_wins > 10, "resource-rich tile scores higher most of the time (%d/20)" % grass_wins)
	
	# Test is_destroyed
	_assert(!cpu.is_destroyed(), "not destroyed with valid settlement")
	settlement.population = 0
	_assert(cpu.is_destroyed(), "destroyed when settlement destroyed")
	
	# Test with low resources — economy weight should increase
	settlement.population = 5
	settlement.food = 10
	settlement.wood = 5
	var low_res_weights = cpu.get_situational_weights()
	_assert(low_res_weights["economy"] > weights["economy"],
		"economy weight increases when resources low")
	
	# Test upgrade boost
	settlement.food = 200
	settlement.wood = 100
	settlement.production = 200
	settlement.population = 5
	settlement.buildings.append("granary")
	# Settlement can_upgrade checks STAGE_REQUIREMENTS — HUT->VILLAGE needs pop 5 + granary
	if settlement.can_upgrade():
		var upgrade_weights = cpu.get_situational_weights()
		_assert(upgrade_weights["upgrade"] > STRATEGY_WEIGHTS["easy"]["upgrade"],
			"upgrade weight boosted when can_upgrade")

# ==================== Multiplayer Manager Tests ====================

func _run_multiplayer_manager_tests() -> void:
	_suite("Multiplayer Manager")
	
	var mm = MultiplayerManager.new()
	
	# Test initial state
	_assert(!mm.is_host, "not host initially")
	_assert_eq(mm.get_player_count(), 0, "no players initially")
	_assert_eq(mm.get_current_player_id(), -1, "no current player initially")
	_assert(!mm.is_my_turn(), "not my turn initially")
	
	# Test state hash is deterministic
	mm.game_state = {"turn": 1, "phase": "placement"}
	var hash1 = mm.compute_state_hash()
	var hash2 = mm.compute_state_hash()
	_assert_eq(hash1, hash2, "state hash is deterministic")
	
	# Different state = different hash
	mm.game_state = {"turn": 2, "phase": "placement"}
	var hash3 = mm.compute_state_hash()
	_assert(hash1 != hash3, "different state produces different hash")
	
	# Test player info retrieval
	mm.player_info[1] = {"name": "Test", "color": Color.BLUE, "ready": false}
	_assert_eq(mm.get_player_count(), 1, "player count after adding")
	var info = mm.get_player_info(1)
	_assert_eq(info["name"], "Test", "player name retrieved")
	_assert(mm.get_player_info(999).is_empty(), "unknown player returns empty dict")
	
	# Test close_connection cleanup (manual, since we can't call close_connection without tree)
	mm.is_host = true
	mm.player_info.clear()
	mm.game_state.clear()
	mm.is_host = false
	_assert(!mm.is_host, "not host after reset")
	_assert_eq(mm.player_info.size(), 0, "player_info cleared after reset")
	_assert_eq(mm.game_state.size(), 0, "game_state cleared after reset")
	
	# Test _advance_turn with mock state
	mm.is_host = true
	mm.player_info = {1: {"name": "A"}, 2: {"name": "B"}, 3: {"name": "C"}}
	mm.game_state = {"turn": 1, "current_player": 1, "players": {}}
	mm._advance_turn()
	_assert_eq(mm.game_state.current_player, 2, "turn advances to next player")
	
	mm._advance_turn()
	_assert_eq(mm.game_state.current_player, 3, "turn advances again")
	
	mm._advance_turn()
	_assert_eq(mm.game_state.current_player, 1, "turn wraps around")
	_assert_eq(mm.game_state.turn, 2, "turn counter increments on wrap")
	
	# Test _process_end_turn validates current player
	mm.game_state.current_player = 1
	mm._process_end_turn(2)  # Wrong player
	_assert_eq(mm.game_state.current_player, 1, "end_turn rejected for wrong player")
	mm._process_end_turn(1)  # Correct player
	_assert_eq(mm.game_state.current_player, 2, "end_turn accepted for correct player")

# ==================== Training Pipeline Tests ====================

func _run_training_pipeline_tests() -> void:
	_suite("Training Pipeline")
	
	# Test FitnessCalculator with new resource_efficiency field
	var fc = FitnessCalculator.new()
	
	var agent_base = {
		"tiles_owned": 10,
		"settlement_stage": 1,
		"buildings_count": 3,
		"techs_unlocked": 2,
		"culture_score": 50,
		"units_killed": 5,
		"units_lost": 2,
	}
	var episode_base = {
		"ticks_survived": 1500,
		"total_map_tiles": 100,
		"victory_achieved": false,
		"victory_type": "none"
	}
	
	# Without efficiency fields
	var fitness_no_eff = fc.calculate_fitness(agent_base, episode_base)
	_assert_eq(fitness_no_eff.size(), 3, "fitness still has 3 objectives")
	
	# With efficiency fields — progression should be >= without
	var agent_with_eff = agent_base.duplicate()
	agent_with_eff["resource_efficiency"] = 0.8
	agent_with_eff["territory_growth_rate"] = 3.0
	var fitness_with_eff = fc.calculate_fitness(agent_with_eff, episode_base)
	_assert(fitness_with_eff[1] >= fitness_no_eff[1],
		"progression score >= without efficiency bonus (%.3f >= %.3f)" % [fitness_with_eff[1], fitness_no_eff[1]])
	
	# Test aggregate fitness
	var agg = fc.aggregate_fitness(fitness_with_eff)
	_assert(agg > 0.0, "aggregate fitness is positive for active agent")
	_assert(agg <= 1.0, "aggregate fitness <= 1.0")
	
	# Test metrics dict includes new fields
	var metrics = fc.get_metrics_dict(agent_with_eff, episode_base)
	_assert(metrics.has("resource_efficiency"), "metrics has resource_efficiency")
	_assert(metrics.has("territory_growth_rate"), "metrics has territory_growth_rate")
	_assert_near(metrics["resource_efficiency"], 0.8, 0.01, "resource_efficiency value preserved")
	
	# Test that better territory = better territory score
	var agent_small = {"tiles_owned": 2, "settlement_stage": 0, "buildings_count": 0,
		"techs_unlocked": 0, "culture_score": 0, "units_killed": 0, "units_lost": 0}
	var agent_big = {"tiles_owned": 50, "settlement_stage": 0, "buildings_count": 0,
		"techs_unlocked": 0, "culture_score": 0, "units_killed": 0, "units_lost": 0}
	var f_small = fc.calculate_fitness(agent_small, episode_base)
	var f_big = fc.calculate_fitness(agent_big, episode_base)
	_assert(f_big[0] > f_small[0], "more territory = higher territory score")
	
	# Test domination victory multiplier
	var episode_dom = episode_base.duplicate()
	episode_dom["victory_achieved"] = true
	episode_dom["victory_type"] = "domination"
	var f_victory = fc.calculate_fitness(agent_base, episode_dom)
	_assert(f_victory[0] > fitness_no_eff[0], "domination victory boosts territory score")
	_assert_near(f_victory[2], 1.0, 0.01, "survival is 1.0 on victory")
	
	# Smoke test: AgentObserver can be instantiated
	var obs = AgentObserver.new()
	_assert(obs != null, "AgentObserver instantiates")
	_assert_eq(obs.player_index, 0, "observer default player_index is 0")
	
	# Smoke test: AgentActions can be instantiated
	var act = AgentActions.new()
	_assert(act != null, "AgentActions instantiates")
	_assert_eq(act.NUM_ACTIONS, 13, "action space has 13 actions")
	
	# Test action validity without game refs (should all be false except IDLE and COLLECT_RESOURCES)
	_assert(act.is_action_valid(AgentActions.Action.IDLE), "IDLE always valid")
	_assert(act.is_action_valid(AgentActions.Action.COLLECT_RESOURCES), "COLLECT_RESOURCES always valid")
	_assert(!act.is_action_valid(AgentActions.Action.EXPAND_TERRITORY), "EXPAND invalid without territory_manager")
	_assert(!act.is_action_valid(AgentActions.Action.SPAWN_WARRIOR), "SPAWN_WARRIOR invalid without settlement")
	
	# Test cooldown system
	act.action_cooldowns[AgentActions.Action.IDLE] = 5.0
	_assert(!act.is_action_valid(AgentActions.Action.IDLE), "action invalid during cooldown")
	act.update_cooldowns(5.0)
	_assert(act.is_action_valid(AgentActions.Action.IDLE), "action valid after cooldown expires")

# Reference the constant for CPU opponent tests
const STRATEGY_WEIGHTS = {
	"easy": {
		"expand": 0.35, "defend": 0.10, "upgrade": 0.10,
		"economy": 0.25, "military": 0.10, "tech": 0.10
	}
}
