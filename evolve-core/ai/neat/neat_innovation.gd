extends RefCounted
class_name NeatInnovation

## Global innovation tracker for NEAT.
## Ensures identical structural mutations receive the same innovation number,
## which is critical for crossover alignment.

var _next_innovation: int = 0
var _next_node_id: int = 0
var _innovation_cache: Dictionary = {}  # "in_id:out_id" → innovation number


func _init(initial_node_id: int = 0) -> void:
    _next_node_id = initial_node_id


func get_innovation(in_id: int, out_id: int) -> int:
    ## Get or assign an innovation number for a connection (in_id → out_id).
    ## Same structural mutation within a generation gets the same number.
    var key := "%d:%d" % [in_id, out_id]
    if _innovation_cache.has(key):
        return _innovation_cache[key]
    var innov := _next_innovation
    _innovation_cache[key] = innov
    _next_innovation += 1
    return innov


func allocate_node_id() -> int:
    ## Allocate a new unique node ID for add-node mutations.
    var id := _next_node_id
    _next_node_id += 1
    return id


func get_next_innovation() -> int:
    ## Read-only: current next innovation number (for debugging/stats).
    return _next_innovation


func get_next_node_id() -> int:
    ## Read-only: current next node ID (for debugging/stats).
    return _next_node_id


func reset_generation_cache() -> void:
    ## Clear the innovation cache between generations.
    ## Innovation numbers persist, but the cache that deduplicates
    ## same-generation mutations is cleared so new generations
    ## get fresh tracking.
    _innovation_cache.clear()
