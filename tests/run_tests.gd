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
