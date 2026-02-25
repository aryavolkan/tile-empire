class_name Tile
extends Resource

## Represents a single hex tile in the game world

enum TileType {
    GRASSLAND,
    FOREST,
    MOUNTAIN,
    WATER,
    DESERT,
    TUNDRA
}

enum ResourceType {
    NONE,
    FOOD,
    WOOD,
    STONE,
    GOLD,
    IRON
}

@export var grid_position: Vector2i = Vector2i.ZERO
@export var world_position: Vector2 = Vector2.ZERO
@export var type: TileType = TileType.GRASSLAND
@export var resource_type: ResourceType = ResourceType.NONE
@export var resource_yield: int = 0
@export var owner_id: int = -1  # -1 means unowned
@export var discovered_by: Array[int] = []  # Player IDs who have discovered this tile
@export var settlement_id: int = -1  # ID of settlement on this tile, -1 if none
@export var improvement_type: String = ""  # e.g., "farm", "mine", "road"

var neighbors: Array[Tile] = []

func _init(pos: Vector2i = Vector2i.ZERO, tile_type: TileType = TileType.GRASSLAND) -> void:
    grid_position = pos
    type = tile_type

func _assign_resources(rng: RandomNumberGenerator = null) -> void:
    # Assign resources based on tile type
    var _rng := rng if rng else RandomNumberGenerator.new()
    match type:
        TileType.GRASSLAND:
            if _rng.randf() > 0.7:
                resource_type = ResourceType.FOOD
                resource_yield = _rng.randi_range(2, 4)
        TileType.FOREST:
            resource_type = ResourceType.WOOD
            resource_yield = _rng.randi_range(3, 5)
        TileType.MOUNTAIN:
            if _rng.randf() > 0.6:
                resource_type = ResourceType.STONE if _rng.randf() > 0.5 else ResourceType.IRON
                resource_yield = _rng.randi_range(2, 4)
        TileType.DESERT:
            if _rng.randf() > 0.8:
                resource_type = ResourceType.GOLD
                resource_yield = _rng.randi_range(1, 3)

func is_owned() -> bool:
    return owner_id != -1

func is_discovered_by(player_id: int) -> bool:
    return player_id in discovered_by

func discover(player_id: int) -> void:
    if not is_discovered_by(player_id):
        discovered_by.append(player_id)

func set_owner(player_id: int) -> void:
    owner_id = player_id
    discover(player_id)

func has_settlement() -> bool:
    return settlement_id != -1

func can_build_settlement() -> bool:
    return not has_settlement() and type != TileType.WATER and type != TileType.MOUNTAIN

func get_movement_cost() -> float:
    match type:
        TileType.GRASSLAND, TileType.DESERT:
            return 1.0
        TileType.FOREST, TileType.TUNDRA:
            return 1.5
        TileType.MOUNTAIN:
            return 2.0
        TileType.WATER:
            return -1.0  # Impassable without boats
        _:
            return 1.0

func get_defense_bonus() -> float:
    match type:
        TileType.FOREST:
            return 1.25
        TileType.MOUNTAIN:
            return 1.5
        TileType.GRASSLAND, TileType.DESERT, TileType.TUNDRA:
            return 1.0
        TileType.WATER:
            return 0.75
        _:
            return 1.0

func get_food_yield() -> int:
    var base_yield = resource_yield if resource_type == ResourceType.FOOD else 0
    if improvement_type == "farm" and type == TileType.GRASSLAND:
        base_yield += 2
    return base_yield

func get_production_yield() -> int:
    var base_yield = 0
    match resource_type:
        ResourceType.WOOD, ResourceType.STONE, ResourceType.IRON:
            base_yield = resource_yield
    if improvement_type == "mine" and type == TileType.MOUNTAIN:
        base_yield += 1
    return base_yield

static func get_distance(from: Vector2i, to: Vector2i) -> int:
    # Hex distance using axial coordinates (odd-r offset)
    var ax = from.x - (from.y - (from.y & 1)) / 2
    var ay = from.y
    var bx = to.x - (to.y - (to.y & 1)) / 2
    var by = to.y
    return int((abs(ax - bx) + abs(ax + ay - bx - by) + abs(ay - by)) / 2)

func get_gold_yield() -> int:
    var base_yield = resource_yield if resource_type == ResourceType.GOLD else 0
    if improvement_type == "trade_post":
        base_yield += 1
    return base_yield