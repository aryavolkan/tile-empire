class_name SkillTree
extends Node

## Manages the skill/tech tree system for player progression

signal skill_unlocked(skill_id: String, player_id: int)
signal research_started(skill_id: String, player_id: int)
signal research_completed(skill_id: String, player_id: int)

var player_skills: Dictionary = {}  # player_id -> Dictionary of unlocked skills
var player_research: Dictionary = {}  # player_id -> current research progress

# Skill categories
enum SkillCategory {
	ECONOMY,
	MILITARY,
	EXPANSION,
	DIPLOMACY,
	CULTURE
}

# Define all skills with their properties
const SKILLS = {
	# Economy skills
	"agriculture": {
		"name": "Agriculture",
		"description": "Increases food production by 20%",
		"category": SkillCategory.ECONOMY,
		"cost": 50,
		"prerequisites": [],
		"effects": {"food_multiplier": 1.2}
	},
	"pottery": {
		"name": "Pottery",
		"description": "Enables granaries and increases food storage",
		"category": SkillCategory.ECONOMY,
		"cost": 75,
		"prerequisites": ["agriculture"],
		"effects": {"building_unlock": "granary", "food_storage": 50}
	},
	"currency": {
		"name": "Currency",
		"description": "Enables marketplaces and increases gold income by 30%",
		"category": SkillCategory.ECONOMY,
		"cost": 100,
		"prerequisites": ["pottery"],
		"effects": {"building_unlock": "marketplace", "gold_multiplier": 1.3}
	},
	"banking": {
		"name": "Banking",
		"description": "Reduces building costs by 15%",
		"category": SkillCategory.ECONOMY,
		"cost": 150,
		"prerequisites": ["currency"],
		"effects": {"building_cost_reduction": 0.15}
	},
	
	# Military skills
	"bronze_working": {
		"name": "Bronze Working",
		"description": "Enables warrior units and barracks",
		"category": SkillCategory.MILITARY,
		"cost": 80,
		"prerequisites": [],
		"effects": {"unit_unlock": "warrior", "building_unlock": "barracks"}
	},
	"archery": {
		"name": "Archery",
		"description": "Enables archer units with ranged attacks",
		"category": SkillCategory.MILITARY,
		"cost": 100,
		"prerequisites": ["bronze_working"],
		"effects": {"unit_unlock": "archer"}
	},
	"iron_working": {
		"name": "Iron Working",
		"description": "Upgrades all military units +25% strength",
		"category": SkillCategory.MILITARY,
		"cost": 150,
		"prerequisites": ["bronze_working"],
		"effects": {"military_strength": 1.25}
	},
	"tactics": {
		"name": "Military Tactics",
		"description": "Units gain +1 movement and flanking bonuses",
		"category": SkillCategory.MILITARY,
		"cost": 200,
		"prerequisites": ["iron_working", "archery"],
		"effects": {"unit_movement": 1, "flanking_bonus": true}
	},
	
	# Expansion skills
	"cartography": {
		"name": "Cartography",
		"description": "Reveals larger area when exploring",
		"category": SkillCategory.EXPANSION,
		"cost": 60,
		"prerequisites": [],
		"effects": {"sight_range": 1}
	},
	"masonry": {
		"name": "Masonry",
		"description": "Reduces territory expansion cost by 20%",
		"category": SkillCategory.EXPANSION,
		"cost": 90,
		"prerequisites": [],
		"effects": {"expansion_cost_reduction": 0.2}
	},
	"engineering": {
		"name": "Engineering",
		"description": "Enables roads and bridges, +1 movement on improved tiles",
		"category": SkillCategory.EXPANSION,
		"cost": 120,
		"prerequisites": ["masonry"],
		"effects": {"improvement_unlock": "road", "road_movement_bonus": 1}
	},
	"sailing": {
		"name": "Sailing",
		"description": "Allows crossing water tiles with boats",
		"category": SkillCategory.EXPANSION,
		"cost": 100,
		"prerequisites": ["cartography"],
		"effects": {"can_cross_water": true, "unit_unlock": "boat"}
	},
	
	# Diplomacy skills
	"writing": {
		"name": "Writing",
		"description": "Enables diplomacy and trade agreements",
		"category": SkillCategory.DIPLOMACY,
		"cost": 70,
		"prerequisites": [],
		"effects": {"enable_diplomacy": true}
	},
	"code_of_laws": {
		"name": "Code of Laws",
		"description": "Reduces unhappiness and border tensions",
		"category": SkillCategory.DIPLOMACY,
		"cost": 100,
		"prerequisites": ["writing"],
		"effects": {"happiness": 2, "border_tension_reduction": 0.3}
	},
	"trade": {
		"name": "Trade",
		"description": "Enables trade routes between settlements",
		"category": SkillCategory.DIPLOMACY,
		"cost": 120,
		"prerequisites": ["writing", "currency"],
		"effects": {"enable_trade_routes": true, "trade_income": 2}
	},
	"diplomacy": {
		"name": "Diplomacy",
		"description": "Allows alliances and reduces diplomatic penalties",
		"category": SkillCategory.DIPLOMACY,
		"cost": 150,
		"prerequisites": ["trade", "code_of_laws"],
		"effects": {"enable_alliances": true, "diplomatic_bonus": 20}
	},
	
	# Culture skills
	"mysticism": {
		"name": "Mysticism",
		"description": "Enables temples and provides happiness",
		"category": SkillCategory.CULTURE,
		"cost": 80,
		"prerequisites": [],
		"effects": {"building_unlock": "temple", "happiness": 1}
	},
	"philosophy": {
		"name": "Philosophy",
		"description": "Enables libraries and increases science output",
		"category": SkillCategory.CULTURE,
		"cost": 120,
		"prerequisites": ["mysticism", "writing"],
		"effects": {"building_unlock": "library", "science_multiplier": 1.5}
	},
	"drama": {
		"name": "Drama",
		"description": "Increases culture and reduces war weariness",
		"category": SkillCategory.CULTURE,
		"cost": 100,
		"prerequisites": ["philosophy"],
		"effects": {"culture": 3, "war_weariness_reduction": 0.4}
	},
	"education": {
		"name": "Education",
		"description": "Settlements grow 25% faster",
		"category": SkillCategory.CULTURE,
		"cost": 150,
		"prerequisites": ["philosophy"],
		"effects": {"growth_rate": 1.25}
	}
}

func initialize_player(player_id: int) -> void:
	player_skills[player_id] = {}
	player_research[player_id] = {}

func can_research(player_id: int, skill_id: String) -> bool:
	if not SKILLS.has(skill_id):
		return false
	
	# Check if already unlocked
	if has_skill(player_id, skill_id):
		return false
	
	# Check prerequisites
	var skill = SKILLS[skill_id]
	for prereq in skill.prerequisites:
		if not has_skill(player_id, prereq):
			return false
	
	return true

func start_research(player_id: int, skill_id: String) -> bool:
	if not can_research(player_id, skill_id):
		return false
	
	player_research[player_id] = {
		"skill_id": skill_id,
		"progress": 0,
		"cost": SKILLS[skill_id].cost
	}
	
	research_started.emit(skill_id, player_id)
	return true

func add_research_progress(player_id: int, amount: int) -> void:
	if not player_research.has(player_id) or player_research[player_id].is_empty():
		return
	
	var research = player_research[player_id]
	research.progress += amount
	
	if research.progress >= research.cost:
		_complete_research(player_id, research.skill_id)

func _complete_research(player_id: int, skill_id: String) -> void:
	player_skills[player_id][skill_id] = SKILLS[skill_id]
	player_research[player_id] = {}
	
	research_completed.emit(skill_id, player_id)
	skill_unlocked.emit(skill_id, player_id)

func has_skill(player_id: int, skill_id: String) -> bool:
	return player_skills.has(player_id) and player_skills[player_id].has(skill_id)

func get_skill_effect(player_id: int, effect_name: String) -> Variant:
	if not player_skills.has(player_id):
		return null
	
	for skill_id in player_skills[player_id]:
		var skill = player_skills[player_id][skill_id]
		if skill.effects.has(effect_name):
			return skill.effects[effect_name]
	
	return null

func get_all_skill_effects(player_id: int) -> Dictionary:
	var all_effects = {}
	
	if not player_skills.has(player_id):
		return all_effects
	
	for skill_id in player_skills[player_id]:
		var skill = player_skills[player_id][skill_id]
		for effect_name in skill.effects:
			if effect_name.ends_with("_multiplier"):
				# Multiply multipliers
				if all_effects.has(effect_name):
					all_effects[effect_name] *= skill.effects[effect_name]
				else:
					all_effects[effect_name] = skill.effects[effect_name]
			elif typeof(skill.effects[effect_name]) == TYPE_INT or typeof(skill.effects[effect_name]) == TYPE_FLOAT:
				# Add numeric values
				if all_effects.has(effect_name):
					all_effects[effect_name] += skill.effects[effect_name]
				else:
					all_effects[effect_name] = skill.effects[effect_name]
			else:
				# For non-numeric values, just set them
				all_effects[effect_name] = skill.effects[effect_name]
	
	return all_effects

func get_available_skills(player_id: int) -> Array[String]:
	var available: Array[String] = []
	
	for skill_id in SKILLS:
		if can_research(player_id, skill_id):
			available.append(skill_id)
	
	return available

func get_skill_tree_progress(player_id: int) -> Dictionary:
	var progress = {
		"total_skills": SKILLS.size(),
		"unlocked_skills": 0,
		"by_category": {}
	}
	
	if player_skills.has(player_id):
		progress.unlocked_skills = player_skills[player_id].size()
		
		for category in SkillCategory.values():
			progress.by_category[category] = 0
		
		for skill_id in player_skills[player_id]:
			var skill = SKILLS[skill_id]
			progress.by_category[skill.category] += 1
	
	return progress

func get_current_research(player_id: int) -> Dictionary:
	return player_research.get(player_id, {})

func cancel_research(player_id: int) -> void:
	if player_research.has(player_id):
		# Return half the progress as science points (would need to be handled by game logic)
		var refund = player_research[player_id].progress / 2
		player_research[player_id] = {}

func get_skill_cost(skill_id: String) -> int:
	return SKILLS.get(skill_id, {}).get("cost", 0)