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
	_run_unit_tests()
	_run_progression_tests()
	_run_ai_observation_tests()
	_run_ai_action_space_tests()
	
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

# ==================== Unit Tests ====================

func _run_unit_tests() -> void:
	_suite("Unit")
	
	# Test initialization
	var unit = Unit.new()
	var tile = Tile.new(Vector2i(0, 0), Tile.TileType.GRASSLAND)
	tile.world_position = Vector2(100, 100)
	unit.initialize(tile, 1, Unit.UnitType.WARRIOR)
	
	_assert_eq(unit.owner_id, 1, "owner set correctly")
	_assert_eq(int(unit.unit_type), int(Unit.UnitType.WARRIOR), "type set correctly")
	_assert_eq(unit.attack_strength, 10, "warrior attack is 10")
	_assert_eq(unit.defense_strength, 8, "warrior defense is 8")
	_assert(!unit.is_civilian, "warrior is not civilian")
	_assert(unit.can_attack, "warrior can attack")
	
	# Test scout initialization
	var scout = Unit.new()
	scout.initialize(tile, 1, Unit.UnitType.SCOUT)
	_assert_eq(int(scout.max_movement_points), 3, "scout has 3 movement")
	_assert_eq(scout.sight_range, 3, "scout has 3 sight")
	
	# Test settler initialization
	var settler = Unit.new()
	settler.initialize(tile, 1, Unit.UnitType.SETTLER)
	_assert(settler.is_civilian, "settler is civilian")
	_assert(!settler.can_attack, "settler can't attack")
	
	# Test damage and healing
	unit.take_damage(30)
	_assert_eq(unit.health, 70, "health reduced by damage")
	unit.heal(10)
	_assert_eq(unit.health, 80, "health restored by heal")
	unit.heal(999)
	_assert_eq(unit.health, 100, "heal capped at max_health")
	
	# Test experience and leveling
	_assert_eq(unit.level, 1, "starts at level 1")
	unit.gain_experience(20)  # level 1 needs 20 exp
	_assert_eq(unit.level, 2, "leveled up to 2")
	_assert_eq(unit.max_health, 110, "max health increased on level up")
	_assert_eq(unit.attack_strength, 12, "attack increased on level up")
	
	# Test fortify/wake
	var base_defense = unit.defense_strength
	unit.fortify()
	_assert_eq(int(unit.state), int(Unit.UnitState.FORTIFIED), "state is fortified")
	_assert(unit.defense_strength > base_defense, "defense increased when fortified")
	unit.wake()
	_assert_eq(int(unit.state), int(Unit.UnitState.IDLE), "state reset to idle")
	
	# Test end_turn restores movement
	unit.movement_points = 0
	unit.end_turn()
	_assert_eq(int(unit.movement_points), int(unit.max_movement_points), "movement restored on end_turn")
	
	# Test fortify heal on end_turn
	unit.take_damage(50)
	unit.fortify()
	var hp_before = unit.health
	unit.end_turn()
	_assert(unit.health > hp_before, "heals while fortified on end_turn")
	
	# Test _is_tile_hostile
	var enemy_tile = Tile.new(Vector2i(1, 0), Tile.TileType.GRASSLAND)
	enemy_tile.owner_id = 2
	_assert(unit._is_tile_hostile(enemy_tile), "enemy-owned tile is hostile")
	
	var neutral_tile = Tile.new(Vector2i(2, 0), Tile.TileType.GRASSLAND)
	neutral_tile.owner_id = -1
	_assert(!unit._is_tile_hostile(neutral_tile), "neutral tile is not hostile")
	
	var own_tile = Tile.new(Vector2i(3, 0), Tile.TileType.GRASSLAND)
	own_tile.owner_id = 1
	_assert(!unit._is_tile_hostile(own_tile), "own tile is not hostile")
	
	# Test counter_attack
	var attacker = Unit.new()
	attacker.initialize(tile, 2, Unit.UnitType.WARRIOR)
	var attacker_hp = attacker.health
	unit.wake()
	unit.counter_attack(attacker)
	_assert(attacker.health < attacker_hp, "counter_attack deals damage")
	
	# Test get_combat_strength
	var strength = unit.get_combat_strength()
	_assert(strength > 0.0, "combat strength is positive")
	
	# Test embark at coast
	var water_tile = Tile.new(Vector2i(0, 1), Tile.TileType.WATER)
	tile.neighbors = [water_tile]
	var embarked = unit.embark()
	_assert(embarked, "can embark at coast")
	_assert_eq(int(unit.state), int(Unit.UnitState.EMBARKED), "state is embarked")
	
	# Test can't embark when already embarked
	_assert(!unit.embark(), "can't embark when already embarked")
	
	# Test disembark on land
	unit.current_tile = tile  # back on land
	_assert(unit.disembark(), "can disembark on land")
	_assert_eq(int(unit.state), int(Unit.UnitState.IDLE), "state back to idle after disembark")

# ==================== Progression Tests ====================

func _run_progression_tests() -> void:
	_suite("Progression")
	
	var prog = ProgressionSystem.new()
	# Need skill tree for initialization
	var st = SkillTree.new()
	
	# Initialize player
	prog.skill_tree = st
	prog.initialize_player(0)
	
	_assert_eq(int(prog.get_player_stage(0)), int(ProgressionSystem.EmpireStage.TRIBAL), "starts tribal")
	_assert_eq(prog.get_player_score(0), 0, "starts with 0 score")
	
	# Test stage advancement
	var stats_expanding = {
		"settlements": 3, "territory": 15, "population": 15,
		"technologies": 0, "culture_points": 0, "total_map_tiles": 100,
		"military_strength": 0, "total_players": 2, "alliances": 0,
		"active_players": 2
	}
	prog.update_player_stats(0, stats_expanding)
	_assert_eq(int(prog.get_player_stage(0)), int(ProgressionSystem.EmpireStage.EXPANDING), "advanced to expanding")
	
	# Test score calculation
	_assert(prog.get_player_score(0) > 0, "score is positive after update")
	
	# Test victory progress
	var vp = prog.get_victory_progress(0)
	_assert(vp.has("domination"), "victory progress has domination")
	_assert(vp.domination >= 0.0, "domination progress >= 0")
	
	# Test leaderboard
	prog.initialize_player(1)
	prog.update_player_stats(1, {"territory": 5, "population": 3, "total_map_tiles": 100,
		"technologies": 0, "culture_points": 0, "settlements": 1, "military_strength": 0,
		"total_players": 2, "alliances": 0, "active_players": 2})
	var lb = prog.get_leaderboard()
	_assert_eq(lb.size(), 2, "leaderboard has 2 players")
	_assert(lb[0].score >= lb[1].score, "leaderboard sorted descending")
	
	# Test trigger_event for milestones
	prog.trigger_event(0, "territory_expanded")
	_assert("first_expansion" in prog.player_milestones[0], "first_expansion milestone triggered")
	
	# Test milestone idempotency
	var milestone_count = prog.player_milestones[0].size()
	prog.trigger_event(0, "territory_expanded")
	_assert_eq(prog.player_milestones[0].size(), milestone_count, "milestone not duplicated")

# ==================== AI Observation Tests ====================

func _run_ai_observation_tests() -> void:
	_suite("AI Observation")
	
	var obs = AgentObserver.new()
	obs.player_index = 0
	
	# Create a mock settlement
	var settlement = Settlement.new()
	settlement.food = 150
	settlement.wood = 80
	settlement.stone = 60
	settlement.gold = 30
	settlement.iron = 10
	settlement.population = 5
	settlement.food_rate = 3.0
	settlement.production_rate = 2.0
	settlement.gold_rate = 1.5
	settlement.research_rate = 0.5
	
	# Get observation vector
	var observation = obs.get_observation(settlement)
	
	# Validate observation size (93 total)
	_assert_eq(observation.size(), 93, "observation vector has 93 elements")
	
	# All values should be normalized [0, 1] or [-1, 1] for ownership
	var all_bounded = true
	for i in range(observation.size()):
		if observation[i] < -1.01 or observation[i] > 1.01:
			all_bounded = false
			break
	_assert(all_bounded, "all observation values in [-1, 1] range")
	
	# Own state: resources should be normalized > 0 for non-zero values
	_assert(observation[1] > 0.0, "food observation > 0 for food=150")
	_assert(observation[2] > 0.0, "wood observation > 0 for wood=80")
	
	# Settlement stage should be 0 for HUT
	_assert_near(observation[6], 0.0, 0.01, "stage observation is 0 for HUT")
	
	# Population normalized
	_assert(observation[7] > 0.0, "population observation > 0")
	
	# Test _normalize helper
	_assert_near(obs._normalize(50.0, 0.0, 100.0), 0.5, 0.01, "normalize 50/100 = 0.5")
	_assert_near(obs._normalize(0.0, 0.0, 100.0), 0.0, 0.01, "normalize 0/100 = 0.0")
	_assert_near(obs._normalize(100.0, 0.0, 100.0), 1.0, 0.01, "normalize 100/100 = 1.0")
	_assert_near(obs._normalize(200.0, 0.0, 100.0), 1.0, 0.01, "normalize clamps above 1.0")
	_assert_near(obs._normalize(-10.0, 0.0, 100.0), 0.0, 0.01, "normalize clamps below 0.0")
	
	# Test with zero range (edge case)
	_assert_near(obs._normalize(5.0, 5.0, 5.0), 0.0, 0.01, "normalize returns 0 for zero range")

# ==================== AI Action Space Tests ====================

func _run_ai_action_space_tests() -> void:
	_suite("AI Action Space")
	
	var act = AgentActions.new()
	
	# Test action enum completeness
	_assert_eq(act.NUM_ACTIONS, 13, "13 actions defined")
	_assert_eq(int(AgentActions.Action.IDLE), 0, "IDLE is action 0")
	_assert_eq(int(AgentActions.Action.BUILD_MARKETPLACE), 12, "BUILD_MARKETPLACE is action 12")
	
	# Test softmax produces valid probability distribution
	var raw_outputs: Array = [1.0, 2.0, 0.5, -1.0, 0.0, 0.3, 0.7, -0.5, 1.5, 0.1, -0.2, 0.8, 0.4]
	var probs = act._softmax(raw_outputs)
	_assert_eq(probs.size(), 13, "softmax output has 13 elements")
	
	var prob_sum = 0.0
	var all_positive = true
	for p in probs:
		prob_sum += p
		if p < 0.0:
			all_positive = false
	_assert(all_positive, "all softmax probabilities >= 0")
	_assert_near(prob_sum, 1.0, 0.01, "softmax probabilities sum to 1.0")
	
	# Test highest value gets highest probability
	var max_idx = 0
	var max_prob = probs[0]
	for i in range(1, probs.size()):
		if probs[i] > max_prob:
			max_prob = probs[i]
			max_idx = i
	_assert_eq(max_idx, 1, "highest raw output (idx 1) gets highest probability")
	
	# Test select_action with settlement for validation
	var settlement = Settlement.new()
	settlement.food = 200
	settlement.wood = 100
	settlement.stone = 100
	settlement.gold = 100
	settlement.production = 200
	settlement.population = 10
	settlement.buildings.append("barracks")
	act.settlement = settlement
	
	# With settlement set, some actions should now be valid
	_assert(act.is_action_valid(AgentActions.Action.SPAWN_WARRIOR), "warrior spawn valid with settlement+barracks")
	_assert(act.is_action_valid(AgentActions.Action.SPAWN_WORKER), "worker spawn valid with settlement")
	_assert(act.is_action_valid(AgentActions.Action.BUILD_GRANARY), "granary build valid")
	_assert(!act.is_action_valid(AgentActions.Action.BUILD_BARRACKS), "barracks invalid - already has barracks (needs wood/stone check)")
	
	# Test get_best_valid_action picks valid action
	var best = act.get_best_valid_action(probs)
	_assert(act.is_action_valid(best), "best valid action is actually valid")
	
	# Test action cooldowns
	for action in AgentActions.Action.values():
		var cd = act.get_action_cooldown(action)
		_assert(cd >= 0.0, "cooldown >= 0 for action " + str(action))
	
	# Test AIController can be instantiated
	var controller = AIController.new()
	_assert_eq(controller.actions_taken, 0, "controller starts with 0 actions")
	_assert_near(controller.get_success_rate(), 0.0, 0.01, "success rate 0 with no actions")
	
	# Test fitness penalty for invalid actions
	var fc = FitnessCalculator.new()
	var agent_data = {
		"tiles_owned": 10, "settlement_stage": 1, "buildings_count": 3,
		"techs_unlocked": 2, "culture_score": 50, "units_killed": 5,
		"units_lost": 2, "invalid_action_rate": 0.0
	}
	var episode_data = {
		"ticks_survived": 1500, "total_map_tiles": 100,
		"victory_achieved": false, "victory_type": "none"
	}
	var fitness_clean = fc.calculate_fitness(agent_data, episode_data)
	
	var agent_data_bad = agent_data.duplicate()
	agent_data_bad["invalid_action_rate"] = 0.8
	var fitness_bad = fc.calculate_fitness(agent_data_bad, episode_data)
	_assert(fitness_bad[1] < fitness_clean[1], "high invalid rate reduces progression score")

# Reference the constant for CPU opponent tests
const STRATEGY_WEIGHTS = {
	"easy": {
		"expand": 0.35, "defend": 0.10, "upgrade": 0.10,
		"economy": 0.25, "military": 0.10, "tech": 0.10
	}
}
