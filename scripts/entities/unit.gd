class_name Unit
extends Node2D

## Represents a game unit (warrior, settler, etc.)

signal moved(from_tile: Tile, to_tile: Tile)
signal action_performed(action_type: String)
signal health_changed(new_health: int)
signal destroyed()

enum UnitType {
	SETTLER,
	WARRIOR,
	ARCHER,
	SCOUT,
	WORKER,
	BOAT
}

enum UnitState {
	IDLE,
	MOVING,
	FORTIFIED,
	WORKING,
	EMBARKED
}

@export var unit_type: UnitType = UnitType.WARRIOR
@export var owner_id: int = -1
@export var unit_name: String = "Unit"

var current_tile: Tile
var state: UnitState = UnitState.IDLE
var health: int = 100
var max_health: int = 100
var movement_points: float = 2.0
var max_movement_points: float = 2.0
var attack_strength: int = 10
var defense_strength: int = 8
var sight_range: int = 2
var experience: int = 0
var level: int = 1

# Unit-specific properties
var is_civilian: bool = false
var can_attack: bool = true
var can_capture: bool = false
var work_turns_remaining: int = 0
var embarked_on: Node = null

# Unit stats by type
const UNIT_STATS = {
	UnitType.SETTLER: {
		"movement": 2,
		"sight": 2,
		"civilian": true,
		"can_attack": false,
		"ability": "found_city"
	},
	UnitType.WARRIOR: {
		"movement": 2,
		"sight": 2,
		"attack": 10,
		"defense": 8,
		"civilian": false,
		"can_capture": true
	},
	UnitType.ARCHER: {
		"movement": 2,
		"sight": 3,
		"attack": 8,
		"defense": 5,
		"civilian": false,
		"ranged": true,
		"range": 2
	},
	UnitType.SCOUT: {
		"movement": 3,
		"sight": 3,
		"attack": 5,
		"defense": 4,
		"civilian": false,
		"ignore_terrain": true
	},
	UnitType.WORKER: {
		"movement": 2,
		"sight": 2,
		"civilian": true,
		"can_attack": false,
		"ability": "improve_tile"
	},
	UnitType.BOAT: {
		"movement": 4,
		"sight": 2,
		"naval": true,
		"transport_capacity": 2,
		"civilian": true
	}
}

func initialize(on_tile: Tile, player_id: int, type: UnitType = UnitType.WARRIOR) -> void:
	unit_type = type
	owner_id = player_id
	current_tile = on_tile
	position = on_tile.world_position
	
	_apply_unit_stats()
	unit_name = _generate_unit_name()

func _apply_unit_stats() -> void:
	var stats = UNIT_STATS[unit_type]
	
	max_movement_points = stats.get("movement", 2)
	movement_points = max_movement_points
	sight_range = stats.get("sight", 2)
	attack_strength = stats.get("attack", 0)
	defense_strength = stats.get("defense", 0)
	is_civilian = stats.get("civilian", false)
	can_attack = stats.get("can_attack", true)
	can_capture = stats.get("can_capture", false)

func _generate_unit_name() -> String:
	match unit_type:
		UnitType.WARRIOR:
			return "1st Warriors"
		UnitType.ARCHER:
			return "1st Archers"
		UnitType.SCOUT:
			return "Scout Team"
		UnitType.SETTLER:
			return "Settler Group"
		UnitType.WORKER:
			return "Worker Corps"
		UnitType.BOAT:
			return "Transport Ship"
		_:
			return "Unit"

func can_move_to(tile: Tile) -> bool:
	# Check if unit has movement points
	if movement_points <= 0:
		return false
	
	# Check terrain
	var movement_cost = tile.get_movement_cost()
	if movement_cost < 0 and not _can_cross_terrain(tile):
		return false
	
	# Check if tile is occupied by enemy
	if _is_tile_hostile(tile):
		return can_attack and not is_civilian
	
	return true

func _can_cross_terrain(tile: Tile) -> bool:
	# Boats can cross water
	if unit_type == UnitType.BOAT:
		return tile.type == Tile.TileType.WATER
	
	# Embarked units can cross water
	if state == UnitState.EMBARKED:
		return tile.type == Tile.TileType.WATER
	
	# Scouts can cross mountains
	if unit_type == UnitType.SCOUT and UNIT_STATS[unit_type].get("ignore_terrain", false):
		return tile.type != Tile.TileType.WATER
	
	return false

func _is_tile_hostile(tile: Tile) -> bool:
	# Check if tile has enemy units or settlements
	# This would need to check with the game's unit manager
	return false

func move_to(tile: Tile, path: Array[Vector2i] = []) -> bool:
	if not can_move_to(tile):
		return false
	
	var movement_cost = tile.get_movement_cost()
	if path.is_empty():
		# Direct movement
		movement_cost = max(1.0, movement_cost)
	else:
		# Calculate path cost
		movement_cost = 0
		for i in range(path.size() - 1):
			var path_tile = current_tile  # Would need tile_map reference
			movement_cost += max(1.0, path_tile.get_movement_cost())
	
	if movement_cost > movement_points:
		return false
	
	var from_tile = current_tile
	current_tile = tile
	position = tile.world_position
	movement_points -= movement_cost
	
	# Reveal tiles around new position
	# This would call tile_map.reveal_tiles_around()
	
	moved.emit(from_tile, tile)
	return true

func end_turn() -> void:
	movement_points = max_movement_points
	
	# Process ongoing work
	if state == UnitState.WORKING and work_turns_remaining > 0:
		work_turns_remaining -= 1
		if work_turns_remaining == 0:
			_complete_work()
	
	# Heal if fortified
	if state == UnitState.FORTIFIED:
		heal(10)

func fortify() -> void:
	if not is_civilian:
		state = UnitState.FORTIFIED
		defense_strength = int(defense_strength * 1.5)
		action_performed.emit("fortify")

func wake() -> void:
	if state == UnitState.FORTIFIED:
		state = UnitState.IDLE
		defense_strength = UNIT_STATS[unit_type].get("defense", 8)

func attack(target: Node) -> void:
	if not can_attack or is_civilian:
		return
	
	# Calculate combat result
	var damage = calculate_damage(target)
	target.take_damage(damage)
	
	# Counter-attack if target survives and can attack back
	if target.has_method("counter_attack"):
		target.counter_attack(self)
	
	# Gain experience
	gain_experience(10)
	
	# Use all movement points
	movement_points = 0
	
	action_performed.emit("attack")

func calculate_damage(target: Node) -> int:
	var base_damage = attack_strength
	
	# Terrain bonuses
	if target.has_method("get_defense_bonus"):
		base_damage = int(base_damage / target.get_defense_bonus())
	
	# Level difference
	if target.has_method("get_level"):
		var level_diff = level - target.get_level()
		base_damage += level_diff * 2
	
	# Random factor
	base_damage = int(base_damage * randf_range(0.8, 1.2))
	
	return max(1, base_damage)

func take_damage(damage: int) -> void:
	health -= damage
	health_changed.emit(health)
	
	if health <= 0:
		_destroy()

func heal(amount: int) -> void:
	var old_health = health
	health = min(health + amount, max_health)
	if health != old_health:
		health_changed.emit(health)

func gain_experience(amount: int) -> void:
	experience += amount
	
	# Check for level up
	var required_exp = level * 20
	if experience >= required_exp:
		level += 1
		experience -= required_exp
		
		# Increase stats
		max_health += 10
		health = max_health
		attack_strength += 2
		defense_strength += 1

func get_level() -> int:
	return level

func get_defense_bonus() -> float:
	if current_tile:
		return current_tile.get_defense_bonus()
	return 1.0

# Special abilities
func found_city() -> bool:
	if unit_type != UnitType.SETTLER:
		return false
	
	if not current_tile or not current_tile.can_build_settlement():
		return false
	
	# This would create a new settlement
	action_performed.emit("found_city")
	_destroy()  # Settler is consumed
	return true

func improve_tile(improvement_type: String) -> void:
	if unit_type != UnitType.WORKER:
		return
	
	state = UnitState.WORKING
	work_turns_remaining = _get_improvement_time(improvement_type)
	
	action_performed.emit("improve_tile")

func _get_improvement_time(improvement_type: String) -> int:
	match improvement_type:
		"farm":
			return 4
		"mine":
			return 5
		"road":
			return 2
		"trade_post":
			return 6
		_:
			return 3

func _complete_work() -> void:
	state = UnitState.IDLE
	# Apply improvement to current tile
	# This would modify the tile's improvement_type
	action_performed.emit("work_completed")

func embark() -> bool:
	if unit_type == UnitType.BOAT or state == UnitState.EMBARKED:
		return false
	
	# Check if at coast
	var at_coast = false
	for neighbor in current_tile.neighbors:
		if neighbor.type == Tile.TileType.WATER:
			at_coast = true
			break
	
	if not at_coast:
		return false
	
	state = UnitState.EMBARKED
	movement_points = max_movement_points * 0.5  # Reduced movement when embarked
	defense_strength = int(defense_strength * 0.5)  # Vulnerable when embarked
	
	action_performed.emit("embark")
	return true

func disembark() -> bool:
	if state != UnitState.EMBARKED:
		return false
	
	if current_tile.type == Tile.TileType.WATER:
		return false
	
	state = UnitState.IDLE
	movement_points = 0  # Use all movement to disembark
	defense_strength = UNIT_STATS[unit_type].get("defense", 8)
	
	action_performed.emit("disembark")
	return true

func _destroy() -> void:
	destroyed.emit()
	queue_free()