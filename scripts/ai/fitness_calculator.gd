extends Node

## Multi-objective fitness calculator for NSGA-2

class_name FitnessCalculator

# Episode tracking
var episode_start_ticks: int = 0
var max_episode_ticks: int = 3000  # 5 minutes at 60 ticks/sec
var initial_tiles: int = 1

# Victory conditions for bonus
const DOMINATION_THRESHOLD = 0.75  # Control 75% of map
const CULTURE_VICTORY_SCORE = 1000
const TECH_VICTORY_THRESHOLD = 0.95  # 95% of tech tree

func _init():
	pass

func calculate_fitness(agent_data: Dictionary, episode_data: Dictionary) -> Array:
	"""
	Calculate multi-objective fitness scores.
	Returns array of 3 objectives for NSGA-2:
	[territory_score, progression_score, survival_score]
	
	agent_data should contain:
	- tiles_owned: int
	- settlement_stage: int (0-4)
	- buildings_count: int
	- techs_unlocked: int
	- culture_score: float
	- units_killed: int
	- units_lost: int
	- resource_efficiency: float (optional, 0-1)
	- territory_growth_rate: float (optional, tiles/min)
	
	episode_data should contain:
	- ticks_survived: int
	- total_map_tiles: int
	- victory_achieved: bool
	- victory_type: String
	"""
	
	# Objective 1: Territory Control (0-1)
	var territory_score = _calculate_territory_score(
		agent_data.get("tiles_owned", 1),
		episode_data.get("total_map_tiles", 100)
	)
	
	# Objective 2: Progression (0-1)
	var progression_score = _calculate_progression_score(agent_data)
	
	# Objective 3: Survival (0-1)
	var survival_score = _calculate_survival_score(
		episode_data.get("ticks_survived", 0),
		max_episode_ticks
	)
	
	# Apply victory bonuses
	if episode_data.get("victory_achieved", false):
		var victory_multiplier = _get_victory_multiplier(episode_data.get("victory_type", ""))
		territory_score *= victory_multiplier
		progression_score *= victory_multiplier
		survival_score = 1.0  # Perfect survival on victory
	
	return [territory_score, progression_score, survival_score]

func _calculate_territory_score(tiles_owned: int, total_tiles: int) -> float:
	"""
	Territory control objective.
	Normalized by map size with diminishing returns.
	"""
	if total_tiles <= 0:
		return 0.0
	
	var raw_ratio = float(tiles_owned) / float(total_tiles)
	
	# Apply sigmoid for smoother scoring
	# This rewards early expansion but has diminishing returns
	var score = 2.0 / (1.0 + exp(-6.0 * (raw_ratio - 0.5)))
	
	# Bonus for achieving domination
	if raw_ratio >= DOMINATION_THRESHOLD:
		score = minf(score * 1.2, 1.0)
	
	return clampf(score, 0.0, 1.0)

func _calculate_progression_score(agent_data: Dictionary) -> float:
	"""
	Civilization progression objective.
	Combines settlement development, buildings, technology, and culture.
	"""
	var score = 0.0
	var max_possible = 0.0
	
	# Settlement stage (0-4) - worth 30%
	var stage_score = agent_data.get("settlement_stage", 0) / 4.0
	score += stage_score * 0.3
	max_possible += 0.3
	
	# Buildings count - worth 20%
	var buildings = agent_data.get("buildings_count", 0)
	var building_score = minf(buildings / 15.0, 1.0)  # Cap at 15 buildings
	score += building_score * 0.2
	max_possible += 0.2
	
	# Technology progress - worth 25%
	var techs = agent_data.get("techs_unlocked", 0)
	var tech_score = minf(techs / 20.0, 1.0)  # Assume ~20 techs total
	score += tech_score * 0.25
	max_possible += 0.25
	
	# Culture score - worth 15%
	var culture = agent_data.get("culture_score", 0)
	var culture_score = minf(culture / CULTURE_VICTORY_SCORE, 1.0)
	score += culture_score * 0.15
	max_possible += 0.15
	
	# Military effectiveness - worth 10%
	var units_killed = agent_data.get("units_killed", 0)
	var units_lost = agent_data.get("units_lost", 0)
	var military_score = 0.0
	if units_killed + units_lost > 0:
		military_score = float(units_killed) / float(units_killed + units_lost)
	score += military_score * 0.1
	max_possible += 0.1
	
	# Resource efficiency bonus (extra reward, doesn't change max_possible baseline)
	var efficiency = agent_data.get("resource_efficiency", 0.0)
	if efficiency > 0.0:
		score += clampf(efficiency, 0.0, 1.0) * 0.1
		max_possible += 0.1
	
	# Territory growth rate bonus (tiles per minute, rewards fast expansion)
	var growth_rate = agent_data.get("territory_growth_rate", 0.0)
	if growth_rate > 0.0:
		var growth_score = minf(growth_rate / 5.0, 1.0)  # Cap at 5 tiles/min
		score += growth_score * 0.05
		max_possible += 0.05

	# Happiness bonus (rewards keeping citizens content)
	var happiness = agent_data.get("happiness", 0)
	if happiness > 0:
		score += minf(float(happiness) / 10.0, 1.0) * 0.05
		max_possible += 0.05

	# Trade income bonus (rewards economic development)
	var trade_income = agent_data.get("trade_income", 0)
	if trade_income > 0:
		score += minf(float(trade_income) / 10.0, 1.0) * 0.05
		max_possible += 0.05

	var raw_score = clampf(score / max_possible, 0.0, 1.0)
	
	# Penalize high invalid action rates (encourages learning valid action masking)
	var invalid_rate = agent_data.get("invalid_action_rate", 0.0)
	if invalid_rate > 0.0:
		# Reduce score by up to 20% for agents that constantly pick invalid actions
		raw_score *= (1.0 - clampf(invalid_rate, 0.0, 1.0) * 0.2)
	
	return raw_score

func _calculate_survival_score(ticks_survived: int, max_ticks: int) -> float:
	"""
	Survival time objective.
	Rewards agents that can sustain their civilization.
	"""
	if max_ticks <= 0:
		return 0.0
	
	var raw_ratio = float(ticks_survived) / float(max_ticks)
	
	# Use exponential curve to strongly reward longer survival
	# But with diminishing returns after 80% survival
	var score = 1.0 - exp(-3.0 * raw_ratio)
	
	return clampf(score, 0.0, 1.0)

func _get_victory_multiplier(victory_type: String) -> float:
	"""Get bonus multiplier for achieving victory"""
	match victory_type:
		"domination":
			return 1.5
		"culture":
			return 1.4
		"technology":
			return 1.4
		"economic":
			return 1.3
		_:
			return 1.2

func get_metrics_dict(agent_data: Dictionary, episode_data: Dictionary) -> Dictionary:
	"""
	Get all metrics as a dictionary for logging.
	Includes both raw values and normalized fitness scores.
	"""
	var fitness_scores = calculate_fitness(agent_data, episode_data)
	
	return {
		# Fitness objectives
		"territory_score": fitness_scores[0],
		"progression_score": fitness_scores[1],
		"survival_score": fitness_scores[2],
		
		# Raw metrics
		"ticks_survived": episode_data.get("ticks_survived", 0),
		"settlement_stage": agent_data.get("settlement_stage", 0),
		"tiles_owned": agent_data.get("tiles_owned", 1),
		"buildings_count": agent_data.get("buildings_count", 0),
		"techs_unlocked": agent_data.get("techs_unlocked", 0),
		"culture_score": agent_data.get("culture_score", 0),
		"units_killed": agent_data.get("units_killed", 0),
		"units_lost": agent_data.get("units_lost", 0),
		"victory_achieved": episode_data.get("victory_achieved", false),
		"victory_type": episode_data.get("victory_type", "none"),
		"resource_efficiency": agent_data.get("resource_efficiency", 0.0),
		"territory_growth_rate": agent_data.get("territory_growth_rate", 0.0),
		"happiness": agent_data.get("happiness", 0),
		"trade_income": agent_data.get("trade_income", 0)
	}

func aggregate_fitness(fitness_array: Array) -> float:
	"""
	Aggregate multi-objective fitness to single value.
	Used for ranking when needed (e.g., elite selection).
	"""
	if fitness_array.size() != 3:
		return 0.0
	
	# Weighted sum with emphasis on territory and progression
	return (fitness_array[0] * 0.4 +  # territory
			fitness_array[1] * 0.4 +  # progression
			fitness_array[2] * 0.2)   # survival