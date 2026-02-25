class_name HexTileMap
extends Node2D

## Manages the hex-based tile grid
## Uses Rust HexMath GDExtension for performance-critical hex calculations
## when available, with GDScript fallback.

# Rust HexMath singleton (null if native lib not loaded)
static var _hex_math: RefCounted = null
static var _hex_math_checked: bool = false

static func _get_hex_math():
    if not _hex_math_checked:
        _hex_math_checked = true
        if ClassDB.class_exists(&"HexMath"):
            _hex_math = ClassDB.instantiate(&"HexMath")
    return _hex_math

signal tile_clicked(tile: Tile)
signal tile_hovered(tile: Tile)
signal territory_changed(player_id: int, tiles: Array[Tile])

@export var map_width: int = 50
@export var map_height: int = 50
@export var hex_size: float = 32.0
@export var tile_scene: PackedScene

var tiles: Dictionary = {}  # Key: Vector2i, Value: Tile
var active_flashes: Array = []  # [{from, to, ttl}] shoot lines from main.gd
var tile_nodes: Dictionary = {}  # Key: Vector2i, Value: Node2D
var territory_overlay: Node2D

# Hex grid constants
var hex_width: float
var hex_height: float
var hex_horiz_spacing: float
var hex_vert_spacing: float

# Noise for terrain generation (cached, not recreated per tile)
var _terrain_noise: FastNoiseLite
var _map_seed: int = 42
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Hex neighbor offsets for offset coordinates (pointy-top, odd-r offset)
# Even rows and odd rows have different neighbor offsets
const HEX_NEIGHBORS_EVEN_ROW = [
    Vector2i(1, 0),   # E
    Vector2i(0, 1),   # SE
    Vector2i(-1, 1),  # SW
    Vector2i(-1, 0),  # W
    Vector2i(-1, -1), # NW
    Vector2i(0, -1),  # NE
]
const HEX_NEIGHBORS_ODD_ROW = [
    Vector2i(1, 0),   # E
    Vector2i(1, 1),   # SE
    Vector2i(0, 1),   # SW
    Vector2i(-1, 0),  # W
    Vector2i(0, -1),  # NW
    Vector2i(1, -1),  # NE
]

func _ready() -> void:
    _init_hex_dimensions()

    territory_overlay = Node2D.new()
    add_child(territory_overlay)

    generate()

func _init_hex_dimensions() -> void:
    # Calculate hex dimensions for pointy-top hexagons
    hex_width = sqrt(3) * hex_size
    hex_height = hex_size * 2
    hex_horiz_spacing = hex_width
    hex_vert_spacing = hex_size * 1.5

func set_seed(seed_value: int) -> void:
    _map_seed = seed_value
    _rng.seed = seed_value

func generate() -> void:
    # Clear existing map and regenerate
    tiles.clear()
    for key in tile_nodes:
        tile_nodes[key].queue_free()
    tile_nodes.clear()
    _generate_map()
    queue_redraw()

func _generate_map() -> void:
    # Set up noise
    _terrain_noise = FastNoiseLite.new()
    _terrain_noise.seed = _map_seed
    _terrain_noise.frequency = 0.05
    _rng.seed = _map_seed

    # Generate tiles with basic terrain
    for y in range(map_height):
        for x in range(map_width):
            var grid_pos = Vector2i(x, y)
            var world_pos = grid_to_world(grid_pos)

            # Create tile resource
            var tile_type = _get_terrain_type(x, y)
            var tile = Tile.new(grid_pos, tile_type)
            tile._assign_resources(_rng)
            tile.world_position = world_pos
            tiles[grid_pos] = tile

            # Create visual representation if scene provided
            if tile_scene:
                var tile_node = tile_scene.instantiate()
                tile_node.position = world_pos
                tile_node.set_meta("grid_position", grid_pos)
                tile_nodes[grid_pos] = tile_node
                add_child(tile_node)

    # Link neighbors
    for pos in tiles:
        var tile = tiles[pos]
        tile.neighbors = get_neighbors(tile)

func _get_terrain_type(x: int, y: int) -> Tile.TileType:
    var height = _terrain_noise.get_noise_2d(x * 10.0, y * 10.0)

    if height < -0.3:
        return Tile.TileType.WATER
    elif height < -0.1:
        return Tile.TileType.GRASSLAND
    elif height < 0.2:
        return Tile.TileType.FOREST
    elif height < 0.4:
        return Tile.TileType.MOUNTAIN
    else:
        return Tile.TileType.DESERT if _rng.randf() > 0.5 else Tile.TileType.TUNDRA

## Terrain colors — muted/earthy so player overlays pop
func _get_tile_color(tile_type: Tile.TileType) -> Color:
    match tile_type:
        Tile.TileType.GRASSLAND:  return Color(0.45, 0.62, 0.32)  # olive green
        Tile.TileType.FOREST:     return Color(0.18, 0.32, 0.16)  # dark moss
        Tile.TileType.MOUNTAIN:   return Color(0.50, 0.47, 0.42)  # stone brown
        Tile.TileType.WATER:      return Color(0.18, 0.38, 0.58)  # deep blue
        Tile.TileType.DESERT:     return Color(0.78, 0.65, 0.35)  # sandy brown
        Tile.TileType.TUNDRA:     return Color(0.70, 0.78, 0.80)  # icy blue-grey
        _:                        return Color(0.45, 0.55, 0.40)

## Player colors — vivid, clash-proof with terrain palette
## Index 0 = unused, 1-4 = players
const PLAYER_PALETTE = [
    Color(0.95, 0.90, 0.10),     # 0 yellow  — human
    Color(0.85, 0.15, 0.85),     # 1 magenta
    Color(1.00, 0.50, 0.05),     # 2 orange
    Color(0.05, 0.90, 0.75),     # 3 cyan
    Color(1.00, 1.00, 1.00),     # 4+ white fallback
]
func _get_player_color(player_id: int) -> Color:
    if player_id < 0:
        return Color.WHITE
    return PLAYER_PALETTE[min(player_id, PLAYER_PALETTE.size() - 1)]

func _get_hex_vertices(center: Vector2, size: float) -> PackedVector2Array:
    var points = PackedVector2Array()
    for i in range(6):
        var angle = PI / 3.0 * i - PI / 6.0
        points.append(center + Vector2(size * cos(angle), size * sin(angle)))
    return points

func _draw() -> void:
    if tiles.is_empty():
        return

    for pos in tiles:
        var tile: Tile = tiles[pos]
        var center = grid_to_world(tile.grid_position)
        var points = _get_hex_vertices(center, hex_size)
        var base_color = _get_tile_color(tile.type)
        var fill_color: Color
        if tile.owner_id != -1:
            var owner_color = _get_player_color(tile.owner_id)
            fill_color = base_color.lerp(owner_color, 0.45)
        else:
            fill_color = base_color
        draw_polygon(points, PackedColorArray([fill_color]))
        var border = PackedVector2Array(points)
        border.append(points[0])
        draw_polyline(border, fill_color.darkened(0.25), 1.0, true)
        if tile.owner_id != -1:
            var owner_color = _get_player_color(tile.owner_id)
            draw_polyline(border, owner_color, 4.0, true)

    for pos in tiles:
        var tile: Tile = tiles[pos]
        if tile.settlement_id != -1:
            var center = grid_to_world(tile.grid_position)
            draw_circle(center, hex_size * 0.45, Color.WHITE)
            draw_arc(center, hex_size * 0.45, 0, TAU, 16, Color.BLACK, 2.0)

    var world = get_parent()
    if world and world.name != "World":
        world = world.get_parent()
    if world:
        var units_node = world.get_node_or_null("Units")
        if units_node:
            for unit in units_node.get_children():
                if unit is Unit:
                    # Use the unit's actual pixel position (smoothly interpolated by main.gd)
                    var center = unit.position
                    var unit_color = _get_player_color(unit.owner_id)
                    var is_tank = (unit.unit_type == 6)  # UnitType.TANK
                    if is_tank:
                        # Tank: bold square/diamond rotated 45°
                        var s = hex_size * 0.52
                        var sq = PackedVector2Array([
                            center + Vector2(0, -s),
                            center + Vector2(s, 0),
                            center + Vector2(0, s),
                            center + Vector2(-s, 0),
                        ])
                        draw_polygon(sq, PackedColorArray([unit_color]))
                        var sq_b = PackedVector2Array(sq)
                        sq_b.append(sq[0])
                        draw_polyline(sq_b, Color.BLACK, 3.0, true)
                        # Inner cross to indicate armour
                        draw_line(center + Vector2(-s * 0.5, 0), center + Vector2(s * 0.5, 0), Color.BLACK, 1.5)
                        draw_line(center + Vector2(0, -s * 0.5), center + Vector2(0, s * 0.5), Color.BLACK, 1.5)
                    else:
                        # Warrior: upward triangle
                        var tri_size = hex_size * 0.50
                        var triangle = PackedVector2Array([
                            center + Vector2(0, -tri_size),
                            center + Vector2(tri_size, tri_size * 0.85),
                            center + Vector2(-tri_size, tri_size * 0.85),
                        ])
                        draw_polygon(triangle, PackedColorArray([unit_color]))
                        var tri_border = PackedVector2Array(triangle)
                        tri_border.append(triangle[0])
                        draw_polyline(tri_border, Color.BLACK, 2.0, true)

    # Shoot flash lines
    for flash in active_flashes:
        var alpha = clamp(flash.ttl / 0.18, 0.0, 1.0)
        draw_line(flash.from, flash.to, Color(1.0, 1.0, 0.2, alpha), 3.0, true)
        draw_circle(flash.to, 6.0, Color(1.0, 0.3, 0.0, alpha))

func grid_to_world(grid_pos: Vector2i) -> Vector2:
    # Convert hex grid coordinates to world position (pointy-top, odd-r)
    var x = hex_size * sqrt(3) * (grid_pos.x + 0.5 * (grid_pos.y & 1))
    var y = hex_size * 1.5 * grid_pos.y
    return Vector2(x, y)

func world_to_grid(world_pos: Vector2) -> Vector2i:
    # Convert world position to hex grid coordinates (pointy-top axial -> odd-r)
    var q = (sqrt(3) / 3.0 * world_pos.x - 1.0 / 3.0 * world_pos.y) / hex_size
    var r = (2.0 / 3.0 * world_pos.y) / hex_size
    return axial_to_offset(hex_round(Vector2(q, r)))

func hex_round(hex: Vector2) -> Vector2:
    var rx = round(hex.x)
    var ry = round(hex.y)
    var rz = round(-hex.x - hex.y)

    var x_diff = abs(rx - hex.x)
    var y_diff = abs(ry - hex.y)
    var z_diff = abs(rz - (-hex.x - hex.y))

    if x_diff > y_diff and x_diff > z_diff:
        rx = -ry - rz
    elif y_diff > z_diff:
        ry = -rx - rz

    return Vector2(rx, ry)

func offset_to_axial(offset: Vector2i) -> Vector2:
    # Odd-r offset to axial (pointy-top)
    var q = offset.x - (offset.y - (offset.y & 1)) / 2
    var r = offset.y
    return Vector2(q, r)

func axial_to_offset(axial: Vector2) -> Vector2i:
    # Axial to odd-r offset (pointy-top)
    var row = int(round(axial.y))
    var col = int(round(axial.x + (row - (row & 1)) / 2))
    return Vector2i(col, row)

func get_tile(grid_pos: Vector2i) -> Tile:
    return tiles.get(grid_pos, null)

func get_neighbors(tile: Tile) -> Array[Tile]:
    var neighbors: Array[Tile] = []
    var directions: Array
    if tile.grid_position.y & 1 == 0:
        directions = HEX_NEIGHBORS_EVEN_ROW
    else:
        directions = HEX_NEIGHBORS_ODD_ROW
    for dir in directions:
        var neighbor_pos = tile.grid_position + dir
        var neighbor = get_tile(neighbor_pos)
        if neighbor:
            neighbors.append(neighbor)
    return neighbors

func get_tiles_in_range(center: Vector2i, hex_range: int) -> Array[Tile]:
    var result: Array[Tile] = []
    var center_axial = offset_to_axial(center)

    for q in range(-hex_range, hex_range + 1):
        for r in range(max(-hex_range, -q - hex_range), min(hex_range, -q + hex_range) + 1):
            var axial = center_axial + Vector2(q, r)
            var offset = axial_to_offset(axial)
            var tile = get_tile(offset)
            if tile:
                result.append(tile)

    return result

func get_tiles_in_radius(center: Vector2, radius: int) -> Array:
    # Convert world position to grid, then get tiles in range
    var grid_pos = world_to_grid(center)
    return get_tiles_in_range(grid_pos, radius)

func get_total_tiles() -> int:
    return tiles.size()

func get_valid_spawn_positions() -> Array:
    # Return positions suitable for settlement placement (not water/mountain, not owned)
    var valid: Array = []
    for pos in tiles:
        var tile = tiles[pos]
        if tile.can_build_settlement() and not tile.is_owned():
            valid.append(tile.world_position)
    return valid

func get_distance(from: Vector2i, to: Vector2i) -> int:
    var hm = _get_hex_math()
    if hm:
        return hm.hex_distance(from, to)
    # GDScript fallback
    var a = offset_to_axial(from)
    var b = offset_to_axial(to)
    return int((abs(a.x - b.x) + abs(a.x + a.y - b.x - b.y) + abs(a.y - b.y)) / 2)

func get_territory_tiles(player_id: int) -> Array[Tile]:
    var territory: Array[Tile] = []
    for pos in tiles:
        var tile = tiles[pos]
        if tile.owner_id == player_id:
            territory.append(tile)
    return territory

func expand_territory(player_id: int, from_tile: Tile) -> Array[Tile]:
    var expanded: Array[Tile] = []
    for neighbor in from_tile.neighbors:
        if neighbor.owner_id == -1 and neighbor.type != Tile.TileType.WATER:
            neighbor.set_owner(player_id)
            expanded.append(neighbor)
            _update_territory_visual(neighbor)

    if expanded.size() > 0:
        territory_changed.emit(player_id, expanded)

    return expanded

func _update_territory_visual(tile: Tile) -> void:
    # Update visual representation of territory ownership
    if tile.owner_id != -1 and tile_nodes.has(tile.grid_position):
        var tile_node = tile_nodes[tile.grid_position]
        # This would typically update the tile's color or border
        # based on the owner's player color

func reveal_tiles_around(center: Vector2i, hex_range: int, player_id: int) -> void:
    var tiles_to_reveal = get_tiles_in_range(center, hex_range)
    for tile in tiles_to_reveal:
        tile.discover(player_id)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("tile_select"):
        var mouse_pos = get_global_mouse_position()
        var grid_pos = world_to_grid(mouse_pos)
        var tile = get_tile(grid_pos)
        if tile:
            tile_clicked.emit(tile)

func find_path(from: Vector2i, to: Vector2i, unit_type: String = "") -> Array[Vector2i]:
    # Try Rust A* first (much faster for large maps)
    var hm = _get_hex_math()
    if hm:
        var blocked: Array[Vector2i] = []
        var costs: Dictionary = {}  # Vector2i -> float
        for pos in tiles:
            var t: Tile = tiles[pos]
            var mc = t.get_movement_cost()
            if mc < 0:
                blocked.append(pos)
            elif mc != 1.0:
                costs[pos] = float(mc)
        var max_dist: int = max(map_width, map_height) * 2
        var result = hm.find_path(from, to, blocked, costs, max_dist)
        # Convert to typed array
        var typed: Array[Vector2i] = []
        for p in result:
            typed.append(p)
        return typed

    # GDScript fallback A*
    var open_set = PriorityQueue.new()
    var came_from = {}
    var g_score = {from: 0}
    var f_score = {from: get_distance(from, to)}

    open_set.push(from, f_score[from])

    while not open_set.is_empty():
        var current = open_set.pop()

        if current == to:
            return _reconstruct_path(came_from, current)

        var current_tile = get_tile(current)
        for neighbor in current_tile.neighbors:
            var neighbor_pos = neighbor.grid_position
            var movement_cost = neighbor.get_movement_cost()

            if movement_cost < 0:  # Impassable
                continue

            var tentative_g_score = g_score[current] + movement_cost

            if not g_score.has(neighbor_pos) or tentative_g_score < g_score[neighbor_pos]:
                came_from[neighbor_pos] = current
                g_score[neighbor_pos] = tentative_g_score
                f_score[neighbor_pos] = tentative_g_score + get_distance(neighbor_pos, to)

                if not open_set.has(neighbor_pos):
                    open_set.push(neighbor_pos, f_score[neighbor_pos])

    return []  # No path found

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
    var path: Array[Vector2i] = [current]
    while current in came_from:
        current = came_from[current]
        path.push_front(current)
    return path

# Simple priority queue for pathfinding
class PriorityQueue:
    var elements = []

    func push(item, priority: float) -> void:
        elements.append([priority, item])
        elements.sort_custom(func(a, b): return a[0] < b[0])

    func pop():
        return elements.pop_front()[1]

    func is_empty() -> bool:
        return elements.is_empty()

    func has(item) -> bool:
        for element in elements:
            if element[1] == item:
                return true
        return false