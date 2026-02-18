extends Node2D

## Main game controller

var tile_map_script = preload("res://scripts/world/tile_map.gd")
var territory_manager_script = preload("res://scripts/systems/territory_manager.gd")
var skill_tree_script = preload("res://scripts/systems/skill_tree.gd")
var progression_script = preload("res://scripts/systems/progression.gd")
var multiplayer_manager_script = preload("res://scripts/networking/multiplayer_manager.gd")

var tile_map: TileMap
var territory_manager: TerritoryManager
var skill_tree: SkillTree
var progression_system: ProgressionSystem
var multiplayer_manager: MultiplayerManager

var camera: Camera2D

func _ready() -> void:
	# Initialize core systems
	_setup_map()
	_setup_systems()
	_setup_camera()
	
	# Connect signals
	tile_map.tile_clicked.connect(_on_tile_clicked)
	territory_manager.territory_expanded.connect(_on_territory_expanded)
	skill_tree.skill_unlocked.connect(_on_skill_unlocked)
	progression_system.empire_stage_changed.connect(_on_empire_stage_changed)

func _setup_map() -> void:
	tile_map = tile_map_script.new()
	$World/TileMap.add_child(tile_map)

func _setup_systems() -> void:
	# Territory management
	territory_manager = territory_manager_script.new()
	add_child(territory_manager)
	territory_manager.initialize(tile_map)
	
	# Skill/tech tree
	skill_tree = skill_tree_script.new()
	add_child(skill_tree)
	
	# Progression system
	progression_system = progression_script.new()
	add_child(progression_system)
	progression_system.initialize(territory_manager, skill_tree)
	
	# Multiplayer
	multiplayer_manager = multiplayer_manager_script.new()
	add_child(multiplayer_manager)

func _setup_camera() -> void:
	camera = $Camera2D
	camera.position = Vector2(640, 360)  # Center of default viewport

func _input(event: InputEvent) -> void:
	# Camera controls
	if event.is_action("camera_pan"):
		if event.is_pressed():
			camera.set_meta("panning", true)
			camera.set_meta("pan_start", event.position)
		else:
			camera.set_meta("panning", false)
	
	if event is InputEventMouseMotion and camera.get_meta("panning", false):
		var pan_start = camera.get_meta("pan_start", Vector2.ZERO)
		var delta = event.position - pan_start
		camera.position -= delta * 0.5
		camera.set_meta("pan_start", event.position)
	
	# Zoom controls
	if event.is_action_pressed("camera_zoom_in"):
		camera.zoom *= 1.1
		camera.zoom = camera.zoom.clamp(Vector2(0.5, 0.5), Vector2(2.0, 2.0))
	elif event.is_action_pressed("camera_zoom_out"):
		camera.zoom *= 0.9
		camera.zoom = camera.zoom.clamp(Vector2(0.5, 0.5), Vector2(2.0, 2.0))

func _on_tile_clicked(tile: Tile) -> void:
	print("Tile clicked: ", tile.grid_position, " Type: ", tile.type)
	# Handle tile interaction based on current game state

func _on_territory_expanded(player_id: int, new_tiles: Array[Tile]) -> void:
	print("Player ", player_id, " expanded territory by ", new_tiles.size(), " tiles")

func _on_skill_unlocked(skill_id: String, player_id: int) -> void:
	print("Player ", player_id, " unlocked skill: ", skill_id)

func _on_empire_stage_changed(player_id: int, new_stage: int) -> void:
	print("Player ", player_id, " advanced to empire stage: ", new_stage)