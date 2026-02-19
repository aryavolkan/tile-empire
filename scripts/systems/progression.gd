class_name ProgressionSystem
extends Node

## Handles empire stage transitions and victory conditions

signal empire_stage_changed(player_id: int, new_stage: EmpireStage)
signal milestone_reached(player_id: int, milestone: String)
signal victory_achieved(player_id: int, victory_type: String)

enum EmpireStage {
	TRIBAL,      # Starting stage - single hut
	EXPANDING,   # Early expansion - multiple settlements
	ESTABLISHED, # Mid-game - defined borders
	DOMINANT,    # Late game - major power
	IMPERIAL     # End game - empire status
}

enum VictoryType {
	DOMINATION,    # Control 65% of the map
	CULTURAL,      # Achieve maximum cultural development
	DIPLOMATIC,    # Unite all players in alliance
	SCORE,         # Highest score after time limit
	ASCENSION      # Complete the tech tree and build wonder
}

var player_stages: Dictionary = {}  # player_id -> EmpireStage
var player_milestones: Dictionary = {}  # player_id -> Array of achieved milestones
var player_scores: Dictionary = {}  # player_id -> score
var victory_progress: Dictionary = {}  # player_id -> Dictionary of victory progress

# Stage thresholds
const STAGE_REQUIREMENTS = {
	EmpireStage.EXPANDING: {
		"settlements": 2,
		"territory": 10,
		"population": 10
	},
	EmpireStage.ESTABLISHED: {
		"settlements": 4,
		"territory": 25,
		"population": 30,
		"technologies": 8
	},
	EmpireStage.DOMINANT: {
		"settlements": 7,
		"territory": 50,
		"population": 75,
		"technologies": 15,
		"cities": 2  # At least 2 settlements at city level
	},
	EmpireStage.IMPERIAL: {
		"settlements": 10,
		"territory": 100,
		"population": 150,
		"technologies": 25,
		"empire_capital": true  # At least one settlement at empire level
	}
}

# Milestones for progression bonuses
const MILESTONES = {
	"first_expansion": {"trigger": "expand_territory", "reward": {"science": 10}},
	"first_village": {"trigger": "settlement_upgraded", "reward": {"culture": 5}},
	"first_conflict": {"trigger": "combat_victory", "reward": {"military_exp": 20}},
	"peaceful_neighbor": {"trigger": "10_turns_no_conflict", "reward": {"diplomacy": 10}},
	"trade_network": {"trigger": "3_trade_routes", "reward": {"gold": 50}},
	"cultural_influence": {"trigger": "5_culture_buildings", "reward": {"culture": 20}},
	"technological_leader": {"trigger": "first_to_tech", "reward": {"science": 30}},
	"empire_builder": {"trigger": "reach_imperial", "reward": {"all_yields": 10}}
}

# Victory conditions
const VICTORY_CONDITIONS = {
	VictoryType.DOMINATION: {
		"territory_percent": 0.65,
		"eliminated_players": 0.5  # Eliminate half the players
	},
	VictoryType.CULTURAL: {
		"culture_points": 1000,
		"cultural_buildings": 20,
		"tourism": 100
	},
	VictoryType.DIPLOMATIC: {
		"alliances": "all_remaining",
		"trade_agreements": "all_remaining",
		"diplomatic_favor": 100
	},
	VictoryType.ASCENSION: {
		"technologies": "all",
		"wonder": "ascension_gate",
		"resources": {"gold": 1000, "production": 1000, "science": 1000}
	}
}

var territory_manager: TerritoryManager
var skill_tree: SkillTree

func initialize(t_manager: TerritoryManager, s_tree: SkillTree) -> void:
	territory_manager = t_manager
	skill_tree = s_tree

func initialize_player(player_id: int) -> void:
	player_stages[player_id] = EmpireStage.TRIBAL
	player_milestones[player_id] = []
	player_scores[player_id] = 0
	victory_progress[player_id] = {
		"domination": 0.0,
		"cultural": 0.0,
		"diplomatic": 0.0,
		"ascension": 0.0
	}

func update_player_stats(player_id: int, stats: Dictionary) -> void:
	# Update progression based on current stats
	var current_stage = player_stages[player_id]
	var next_stage = current_stage + 1
	
	if next_stage <= EmpireStage.IMPERIAL:
		if _check_stage_requirements(player_id, next_stage, stats):
			_advance_stage(player_id, next_stage)
	
	# Check milestones
	_check_milestones(player_id, stats)
	
	# Update victory progress
	_update_victory_progress(player_id, stats)
	
	# Calculate score
	_calculate_score(player_id, stats)

func _check_stage_requirements(player_id: int, stage: EmpireStage, stats: Dictionary) -> bool:
	var requirements = STAGE_REQUIREMENTS.get(stage, {})
	
	for req_name in requirements:
		var req_value = requirements[req_name]
		var player_value = stats.get(req_name, 0)
		
		if typeof(req_value) == TYPE_BOOL:
			if not player_value:
				return false
		else:
			if player_value < req_value:
				return false
	
	return true

func _advance_stage(player_id: int, new_stage: EmpireStage) -> void:
	player_stages[player_id] = new_stage
	empire_stage_changed.emit(player_id, new_stage)
	
	# Grant stage advancement bonuses
	var bonuses = _get_stage_bonuses(new_stage)
	# Apply bonuses through game systems

func _get_stage_bonuses(stage: EmpireStage) -> Dictionary:
	match stage:
		EmpireStage.EXPANDING:
			return {"free_settler": 1, "vision_range": 1}
		EmpireStage.ESTABLISHED:
			return {"free_technology": 1, "happiness": 2}
		EmpireStage.DOMINANT:
			return {"military_units": 3, "gold": 200}
		EmpireStage.IMPERIAL:
			return {"wonder_production": 100, "all_yields": 20}
		_:
			return {}

func _check_milestones(player_id: int, stats: Dictionary) -> void:
	var achieved = player_milestones[player_id]
	
	for milestone_id in MILESTONES:
		if milestone_id in achieved:
			continue
		
		var milestone = MILESTONES[milestone_id]
		if _is_milestone_achieved(milestone, stats):
			achieved.append(milestone_id)
			milestone_reached.emit(player_id, milestone_id)
			# Apply rewards

func _is_milestone_achieved(milestone: Dictionary, stats: Dictionary) -> bool:
	# Check specific milestone conditions based on trigger type
	# This would be expanded based on actual game events
	return false

func _update_victory_progress(player_id: int, stats: Dictionary) -> void:
	var progress = victory_progress[player_id]
	
	# Domination victory progress
	var total_territory = stats.get("total_map_tiles", 1000)
	var player_territory = stats.get("territory", 0)
	progress.domination = float(player_territory) / float(total_territory)
	
	# Cultural victory progress
	var cultural_score = stats.get("culture_points", 0)
	progress.cultural = min(1.0, cultural_score / float(VICTORY_CONDITIONS[VictoryType.CULTURAL].culture_points))
	
	# Diplomatic victory progress
	var total_players = stats.get("total_players", 8)
	var alliances = stats.get("alliances", 0)
	progress.diplomatic = float(alliances) / float(total_players - 1)
	
	# Ascension victory progress
	var total_techs = skill_tree.SKILLS.size()
	var player_techs = stats.get("technologies", 0)
	progress.ascension = float(player_techs) / float(total_techs)
	
	# Check for victory
	for victory_type in VictoryType.values():
		if _check_victory_condition(player_id, victory_type, stats):
			victory_achieved.emit(player_id, VictoryType.keys()[victory_type])
			break

func _check_victory_condition(player_id: int, victory_type: VictoryType, stats: Dictionary) -> bool:
	var conditions = VICTORY_CONDITIONS[victory_type]
	var progress = victory_progress[player_id]
	
	match victory_type:
		VictoryType.DOMINATION:
			return progress.domination >= conditions.territory_percent
		VictoryType.CULTURAL:
			return stats.get("culture_points", 0) >= conditions.culture_points
		VictoryType.DIPLOMATIC:
			var total_players = stats.get("active_players", 1)
			return stats.get("alliances", 0) >= total_players - 1
		VictoryType.ASCENSION:
			return progress.ascension >= 1.0 and stats.get("wonder_built", false)
		_:
			return false

func _calculate_score(player_id: int, stats: Dictionary) -> void:
	var score = 0
	
	# Territory score
	score += stats.get("territory", 0) * 10
	
	# Population score
	score += stats.get("population", 0) * 5
	
	# Technology score
	score += stats.get("technologies", 0) * 20
	
	# Culture score
	score += stats.get("culture_points", 0) * 2
	
	# Military score
	score += stats.get("military_strength", 0) * 3
	
	# Stage bonus
	score += int(player_stages[player_id]) * 100
	
	# Milestone bonuses
	score += player_milestones[player_id].size() * 50
	
	player_scores[player_id] = score

func get_player_stage(player_id: int) -> EmpireStage:
	return player_stages.get(player_id, EmpireStage.TRIBAL)

func get_player_score(player_id: int) -> int:
	return player_scores.get(player_id, 0)

func get_victory_progress(player_id: int) -> Dictionary:
	return victory_progress.get(player_id, {})

func get_culture_score(player_id: int) -> float:
	return float(victory_progress.get(player_id, {}).get("cultural", 0.0)) * float(VICTORY_CONDITIONS[VictoryType.CULTURAL].culture_points)

func get_leaderboard() -> Array:
	var leaderboard = []
	for player_id in player_scores:
		leaderboard.append({
			"player_id": player_id,
			"score": player_scores[player_id],
			"stage": player_stages[player_id]
		})
	
	leaderboard.sort_custom(func(a, b): return a.score > b.score)
	return leaderboard

func trigger_event(player_id: int, event_type: String, event_data: Dictionary = {}) -> void:
	# Handle game events for milestone tracking
	match event_type:
		"territory_expanded":
			if not "first_expansion" in player_milestones[player_id]:
				player_milestones[player_id].append("first_expansion")
				milestone_reached.emit(player_id, "first_expansion")
		"settlement_upgraded":
			if event_data.get("stage") == Settlement.SettlementStage.VILLAGE:
				if not "first_village" in player_milestones[player_id]:
					player_milestones[player_id].append("first_village")
					milestone_reached.emit(player_id, "first_village")