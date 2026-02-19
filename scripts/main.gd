extends Node2D

## Main game controller

var tile_map_script = preload("res://scripts/world/tile_map.gd")
var territory_manager_script = preload("res://scripts/systems/territory_manager.gd")
var skill_tree_script = preload("res://scripts/systems/skill_tree.gd")
var progression_script = preload("res://scripts/systems/progression.gd")
var multiplayer_manager_script = preload("res://scripts/networking/multiplayer_manager.gd")
var training_manager_script = preload("res://scripts/training_manager.gd")

var tile_map: HexTileMap
var territory_manager: TerritoryManager
var skill_tree: SkillTree
var progression_system: ProgressionSystem
var multiplayer_manager: MultiplayerManager
var training_manager: TrainingManager

var camera: Camera2D
var is_training_mode: bool = false

func _ready() -> void:
	# Check if in training mode
	_check_training_mode()
	
	# Ensure expected scene nodes exist (autoloads won't have them)
	_ensure_scene_nodes()
	
	# Initialize core systems
	_setup_map()
	_setup_systems()
	if not is_training_mode:
		_setup_players()
	
	if not is_training_mode:
		_setup_camera()
		
		# Connect signals for normal gameplay
		tile_map.tile_clicked.connect(_on_tile_clicked)
		territory_manager.territory_expanded.connect(_on_territory_expanded)
		skill_tree.skill_unlocked.connect(_on_skill_unlocked)
		progression_system.empire_stage_changed.connect(_on_empire_stage_changed)
	else:
		# Training mode setup
		_setup_training()

func _check_training_mode() -> void:
	# Check command line args for training flag
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg == "--training" or arg == "--auto-train":
			is_training_mode = true
			break

func _ensure_scene_nodes() -> void:
	var world = get_node_or_null("World")
	if world == null:
		world = Node2D.new()
		world.name = "World"
		add_child(world)
	
	var tile_map_container = world.get_node_or_null("TileMap")
	if tile_map_container == null:
		tile_map_container = Node2D.new()
		tile_map_container.name = "TileMap"
		world.add_child(tile_map_container)
	
	for child_name in ["Units", "Settlements"]:
		if world.get_node_or_null(child_name) == null:
			var container = Node2D.new()
			container.name = child_name
			world.add_child(container)
	
	camera = get_node_or_null("Camera2D")
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.enabled = true
		add_child(camera)

func _setup_map() -> void:
	var tile_map_container = get_node_or_null("World/TileMap")
	if tile_map_container == null:
		push_error("TileMap container missing; cannot initialize map")
		return
	
	tile_map = tile_map_script.new()
	tile_map_container.add_child(tile_map)
	tile_map.generate()
	tile_map.queue_redraw()

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
	if camera == null:
		camera = get_node_or_null("Camera2D")
	if camera:
		camera.position = Vector2(640, 360)  # Center of default viewport

func _setup_players() -> void:
	if tile_map == null or territory_manager == null:
		return

	var candidates: Array[Tile] = []
	for pos in tile_map.tiles:
		var tile: Tile = tile_map.tiles[pos]
		if tile.can_build_settlement() and not tile.is_owned():
			candidates.append(tile)

	if candidates.is_empty():
		return

	candidates.shuffle()
	var player_ids = [1, 2, 3]
	var settlements_container = get_node_or_null("World/Settlements")

	for i in range(min(player_ids.size(), candidates.size())):
		var player_id = player_ids[i]
		var start_tile = candidates[i]
		territory_manager.claim_starting_tile(player_id, start_tile)

		var settlement = preload("res://scripts/entities/settlement.gd").new()
		settlement.initialize(start_tile, player_id, "AI %d" % player_id)
		settlement.set_ai_difficulty("easy")
		if settlements_container:
			settlements_container.add_child(settlement)
		else:
			add_child(settlement)

		territory_manager.register_settlement(settlement, player_id)
		if skill_tree:
			skill_tree.initialize_player(player_id)
		if progression_system:
			progression_system.initialize_player(player_id)

	if tile_map:
		tile_map.queue_redraw()

func _input(event: InputEvent) -> void:
	if camera == null:
		return
	
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

func _setup_training() -> void:
	# Create training manager
	training_manager = training_manager_script.new()
	add_child(training_manager)
	training_manager.game_manager = self
	training_manager.world_generator = tile_map
	
	# Disable unnecessary visuals in training mode
	if training_manager.is_headless:
		RenderingServer.render_loop_enabled = false

# === Public methods for training/AI access ===

func get_total_tiles() -> int:
	if tile_map:
		return tile_map.get_total_tiles()
	return 0

func get_valid_spawn_positions() -> Array:
	if tile_map:
		return tile_map.get_valid_spawn_positions()
	return []

func create_settlement(position: Vector2, player_id: int) -> Node:
	# Create and return a settlement node
	var settlement = preload("res://scripts/entities/settlement.gd").new()
	settlement.position = position
	settlement.player_id = player_id
	add_child(settlement)
	
	# Register with territory manager
	if territory_manager:
		territory_manager.register_settlement(settlement, player_id)
	
	return settlement

func set_random_seed(seed_value: int) -> void:
	seed(seed_value)
	if tile_map:
		tile_map.set_seed(seed_value)

func set_map_size(size: String) -> void:
	if tile_map:
		match size:
			"small":
				tile_map.map_width = 30
				tile_map.map_height = 30
			"medium":
				tile_map.map_width = 50
				tile_map.map_height = 50
			"large":
				tile_map.map_width = 70
				tile_map.map_height = 70

func generate_world() -> void:
	if tile_map:
		tile_map.generate()

func get_tiles_in_radius(center: Vector2, radius: int) -> Array:
	if tile_map:
		return tile_map.get_tiles_in_radius(center, radius)
	return []

func get_nearest_enemy(player_id: int) -> Node:
	# Find nearest enemy settlement
	var min_distance = INF
	var nearest = null
	
	for child in get_children():
		if child.has_method("get_player_id") and child.get_player_id() != player_id:
			var dist = child.position.distance_to(get_player_position(player_id))
			if dist < min_distance:
				min_distance = dist
				nearest = child
	
	return nearest

func get_player_position(player_id: int) -> Vector2:
	# Get position of player's main settlement
	for child in get_children():
		if child.has_method("get_player_id") and child.get_player_id() == player_id:
			return child.position
	return Vector2.ZERO

func get_domination_progress(player_id: int) -> float:
	if territory_manager:
		var owned_tiles = territory_manager.get_territory_size(player_id)
		var total_tiles = get_total_tiles()
		return float(owned_tiles) / float(total_tiles) if total_tiles > 0 else 0.0
	return 0.0

func get_culture_score(player_id: int) -> float:
	if progression_system:
		return progression_system.get_culture_score(player_id)
	return 0.0