extends Node

## Strategic CPU Opponent for Tile Empire
## Uses situational awareness to make smart decisions

class_name CPUOpponent

var settlement: Node
var player_id: int = 1
var difficulty: String = "easy"  # easy, medium, hard

# Decision timing
var think_interval: float = 2.0
var time_since_last_think: float = 0.0

# References
var game_manager: Node
var territory_manager: Node
var tech_tree: Node

# Strategic state
var _threat_cache: Dictionary = {}  # player_id -> threat_level
var _threat_cache_age: float = 0.0
const THREAT_CACHE_TTL: float = 5.0

# Priority weights per difficulty (expand, defend, upgrade, economy, military, tech)
const STRATEGY_WEIGHTS := {
	"easy": {
		"expand": 0.35, "defend": 0.10, "upgrade": 0.10,
		"economy": 0.25, "military": 0.10, "tech": 0.10
	},
	"medium": {
		"expand": 0.25, "defend": 0.15, "upgrade": 0.15,
		"economy": 0.15, "military": 0.15, "tech": 0.15
	},
	"hard": {
		"expand": 0.20, "defend": 0.20, "upgrade": 0.15,
		"economy": 0.10, "military": 0.20, "tech": 0.15
	}
}

func initialize(settlement_node: Node, player_index: int, diff: String = "easy") -> void:
	settlement = settlement_node
	player_id = player_index
	difficulty = diff
	match difficulty:
		"easy": think_interval = 3.0
		"medium": think_interval = 2.0
		"hard": think_interval = 1.0

func set_game_references(game_mgr: Node, territory_mgr: Node, tech_mgr: Node) -> void:
	game_manager = game_mgr
	territory_manager = territory_mgr
	tech_tree = tech_mgr

func update(delta: float) -> void:
	if not settlement or not is_instance_valid(settlement):
		return
	time_since_last_think += delta
	_threat_cache_age += delta
	if time_since_last_think >= think_interval:
		time_since_last_think = 0.0
		_make_decision()

func _make_decision() -> void:
	# Evaluate situation and adjust weights dynamically
	var weights = _get_situational_weights()
	var behavior = _weighted_random_choice(weights)

	match behavior:
		"expand":
			_try_expand_territory()
		"defend":
			_try_defend_borders()
		"upgrade":
			_try_upgrade_settlement()
		"economy":
			_try_economic_action()
		"military":
			_try_military_action()
		"tech":
			_try_research()

func _get_situational_weights() -> Dictionary:
	var base = STRATEGY_WEIGHTS[difficulty].duplicate()

	# Boost defense when threatened
	var threat = _get_max_threat_level()
	if threat > 0.5:
		base["defend"] += 0.15
		base["military"] += 0.10
		base["expand"] -= 0.10

	# Boost economy when resources are low
	if settlement.food < 30 or settlement.wood < 20:
		base["economy"] += 0.15
		base["expand"] -= 0.05
		base["military"] -= 0.05

	# Boost upgrade when close to threshold
	if settlement.can_upgrade():
		base["upgrade"] += 0.25
		base["expand"] -= 0.10

	# Boost expansion early game (small territory)
	if territory_manager and territory_manager.get_territory_size(player_id) < 5:
		base["expand"] += 0.15
		base["defend"] -= 0.05

	# Boost tech if nothing is being researched
	if tech_tree and not _is_researching():
		base["tech"] += 0.10

	# Clamp negatives
	for key in base:
		base[key] = maxf(base[key], 0.01)

	return base

func _get_max_threat_level() -> float:
	if _threat_cache_age < THREAT_CACHE_TTL and not _threat_cache.is_empty():
		var max_t = 0.0
		for t in _threat_cache.values():
			max_t = maxf(max_t, t)
		return max_t

	_threat_cache.clear()
	_threat_cache_age = 0.0

	if not territory_manager:
		return 0.0

	var threatened = territory_manager.get_threatened_border_tiles(player_id)
	if threatened.is_empty():
		return 0.0

	# Count border tiles per opponent
	var opponent_pressure: Dictionary = {}
	for tile in threatened:
		for neighbor in tile.neighbors:
			if neighbor.is_owned() and neighbor.owner_id != player_id:
				opponent_pressure[neighbor.owner_id] = opponent_pressure.get(neighbor.owner_id, 0) + 1

	var my_territory = maxf(territory_manager.get_territory_size(player_id), 1.0)
	var max_threat = 0.0
	for opp_id in opponent_pressure:
		var opp_territory = territory_manager.get_territory_size(opp_id)
		# Threat = pressure tiles / my territory * opponent size ratio
		var pressure_ratio = float(opponent_pressure[opp_id]) / my_territory
		var size_ratio = float(opp_territory) / my_territory
		var threat_level = clampf(pressure_ratio * 0.5 + size_ratio * 0.5, 0.0, 1.0)
		_threat_cache[opp_id] = threat_level
		max_threat = maxf(max_threat, threat_level)

	return max_threat

func _try_expand_territory() -> void:
	if not territory_manager:
		return

	var expandable = territory_manager.get_expandable_tiles(player_id)
	if expandable.is_empty():
		return

	# Score each tile
	var best_tile: Tile = null
	var best_score: float = -INF

	for tile in expandable:
		var score = _score_tile_for_expansion(tile)
		if score > best_score:
			best_score = score
			best_tile = tile

	if best_tile:
		territory_manager.expand_territory(player_id, best_tile)

func _score_tile_for_expansion(tile: Tile) -> float:
	var score := 0.0

	# Resource value (heavily weighted)
	score += tile.get_food_yield() * 2.0
	score += tile.get_production_yield() * 1.5
	score += tile.get_gold_yield() * 1.5
	score += tile.resource_yield * 1.0

	# Terrain preference
	match tile.type:
		Tile.TileType.GRASSLAND: score += 2.0
		Tile.TileType.FOREST: score += 1.5
		Tile.TileType.DESERT: score += 0.5
		Tile.TileType.MOUNTAIN: score += 1.0  # Defensive value

	# Strategic: prefer tiles that border enemies less (safer expansion)
	# But on hard difficulty, allow aggressive expansion toward enemies
	var enemy_neighbor_count := 0
	for neighbor in tile.neighbors:
		if neighbor.is_owned() and neighbor.owner_id != player_id:
			enemy_neighbor_count += 1

	if difficulty == "hard":
		score += enemy_neighbor_count * 0.5  # Aggressive
	else:
		score -= enemy_neighbor_count * 1.0  # Conservative

	# Add small randomness to avoid predictability
	score += randf() * 1.5

	return score

func _try_defend_borders() -> void:
	if not territory_manager:
		return

	var threatened = territory_manager.get_threatened_border_tiles(player_id)
	if threatened.is_empty():
		# No threats — fall back to military buildup
		_try_military_action()
		return

	# Reinforce: spawn defensive units if possible
	if settlement.has_method("can_spawn_unit"):
		if settlement.can_spawn_unit("warrior"):
			settlement.spawn_unit("warrior")
			return
		if settlement.can_spawn_unit("archer"):
			settlement.spawn_unit("archer")
			return

	# If can't spawn, build barracks
	if settlement.has_method("can_build_structure") and settlement.can_build_structure("barracks"):
		settlement.build_structure("barracks")

func _try_upgrade_settlement() -> void:
	if not settlement:
		return

	# Try direct upgrade first
	if settlement.has_method("can_upgrade") and settlement.can_upgrade():
		settlement.upgrade()
		return

	# Otherwise, build toward upgrade requirements
	var next_stage = settlement.stage + 1
	if next_stage > Settlement.SettlementStage.EMPIRE:
		return

	var requirements = Settlement.STAGE_REQUIREMENTS.get(next_stage, {})
	var required_buildings = requirements.get("buildings", [])

	for building in required_buildings:
		if building not in settlement.buildings:
			if settlement.has_method("can_build_structure") and settlement.can_build_structure(building):
				settlement.build_structure(building)
				return

func _try_economic_action() -> void:
	if not settlement:
		return

	# Priority: food > production buildings > workers
	if settlement.food < 50:
		if settlement.has_method("can_build_structure") and settlement.can_build_structure("granary"):
			settlement.build_structure("granary")
			return
		if settlement.has_method("set_worker_priority"):
			settlement.set_worker_priority("food")
			return

	if settlement.has_method("can_spawn_unit") and settlement.can_spawn_unit("worker"):
		settlement.spawn_unit("worker")
		return

	if settlement.has_method("can_build_structure"):
		if settlement.can_build_structure("marketplace"):
			settlement.build_structure("marketplace")
			return
		if settlement.can_build_structure("granary"):
			settlement.build_structure("granary")

func _try_military_action() -> void:
	if not settlement or not settlement.has_method("can_spawn_unit"):
		return

	# Build barracks first if we don't have one
	if "barracks" not in settlement.buildings:
		if settlement.has_method("can_build_structure") and settlement.can_build_structure("barracks"):
			settlement.build_structure("barracks")
			return

	# Prefer warriors, then archers
	if settlement.can_spawn_unit("warrior"):
		settlement.spawn_unit("warrior")
	elif settlement.can_spawn_unit("archer"):
		settlement.spawn_unit("archer")

func _try_research() -> void:
	if not tech_tree:
		return

	var available = tech_tree.get_available_technologies(player_id)
	if available.is_empty():
		return

	# Score techs by strategic value
	var best_tech = null
	var best_score: float = -INF

	for tech in available:
		var score = _score_tech(tech)
		if score > best_score:
			best_score = score
			best_tech = tech

	if best_tech:
		tech_tree.start_research(best_tech.id, player_id)

func _score_tech(tech: Dictionary) -> float:
	var score := 0.0
	var tech_id: String = tech.get("id", "")

	# Prioritize based on current needs
	var threat = _get_max_threat_level()

	# Economy techs when resources low
	if tech_id in ["agriculture", "pottery", "currency", "banking"]:
		score += 3.0
		if settlement.food < 50:
			score += 2.0

	# Military techs when threatened
	if tech_id in ["bronze_working", "archery", "iron_working", "tactics"]:
		score += 2.0 + threat * 5.0

	# Expansion techs early game
	if tech_id in ["cartography", "masonry", "engineering", "sailing"]:
		if territory_manager and territory_manager.get_territory_size(player_id) < 10:
			score += 3.0
		else:
			score += 1.0

	# Culture/diplomacy when stable
	if tech_id in ["mysticism", "philosophy", "writing", "code_of_laws"]:
		if threat < 0.3:
			score += 2.0

	# Lower cost = faster payoff
	var cost = tech.get("priority", 100)  # priority field holds cost
	score += 5.0 / maxf(float(cost) / 50.0, 0.5)

	# Randomness
	score += randf() * 1.0 if difficulty != "hard" else randf() * 0.3

	return score

func _is_researching() -> bool:
	if not tech_tree or not tech_tree.has_method("is_researching"):
		return false
	return tech_tree.is_researching()

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

	return weights.keys()[0]

func is_destroyed() -> bool:
	return not is_instance_valid(settlement) or (settlement.has_method("is_destroyed") and settlement.is_destroyed())

## --- Test helpers ---

func get_situational_weights() -> Dictionary:
	return _get_situational_weights()

func get_max_threat_level() -> float:
	return _get_max_threat_level()

func score_tile_for_expansion(tile: Tile) -> float:
	return _score_tile_for_expansion(tile)
