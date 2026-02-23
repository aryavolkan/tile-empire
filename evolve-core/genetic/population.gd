class_name Population
extends RefCounted

## Manages a population of individuals for evolutionary algorithms.
## Handles creation, evaluation, and generation transitions.

signal evaluation_needed(index: int, individual)
signal evaluation_complete(index: int, fitness: float)

var size: int
var individuals: Array = []
var fitness_scores: PackedFloat32Array
var metadata: Array = []  # Optional metadata per individual

var network_factory_func: Callable
var fitness_func: Callable


func _init(p_size: int = 100) -> void:
    size = p_size
    fitness_scores.resize(p_size)
    metadata.resize(p_size)


func initialize(factory_func: Callable) -> void:
    ## Initialize population with factory function
    network_factory_func = factory_func
    individuals.clear()

    for i in size:
        individuals.append(factory_func.call())
        metadata[i] = {}

    reset_fitness()


func reset_fitness() -> void:
    ## Reset all fitness scores
    fitness_scores.fill(0.0)
    for i in metadata.size():
        metadata[i] = {}


func set_fitness(index: int, fitness: float, meta: Dictionary = {}) -> void:
    ## Set fitness and optional metadata for an individual
    if index >= 0 and index < size:
        fitness_scores[index] = fitness
        metadata[index] = meta
        evaluation_complete.emit(index, fitness)


func get_individual(index: int):
    if index >= 0 and index < individuals.size():
        return individuals[index]
    return null


func get_fitness(index: int) -> float:
    if index >= 0 and index < fitness_scores.size():
        return fitness_scores[index]
    return 0.0


func get_metadata(index: int) -> Dictionary:
    if index >= 0 and index < metadata.size():
        return metadata[index]
    return {}


func evaluate_all(evaluator: Callable) -> void:
    ## Evaluate entire population with given function
    fitness_func = evaluator
    for i in size:
        evaluation_needed.emit(i, individuals[i])
        var result = evaluator.call(individuals[i])
        if result is Dictionary:
            set_fitness(i, result.get("fitness", 0.0), result)
        else:
            set_fitness(i, float(result))


func get_best_index() -> int:
    ## Find index of best individual
    var best_idx := 0
    var best_fitness := fitness_scores[0]

    for i in range(1, size):
        if fitness_scores[i] > best_fitness:
            best_fitness = fitness_scores[i]
            best_idx = i

    return best_idx


func get_best():
    ## Get best individual
    var idx := get_best_index()
    return individuals[idx] if idx >= 0 else null


func get_worst_index() -> int:
    ## Find index of worst individual
    var worst_idx := 0
    var worst_fitness := fitness_scores[0]

    for i in range(1, size):
        if fitness_scores[i] < worst_fitness:
            worst_fitness = fitness_scores[i]
            worst_idx = i

    return worst_idx


func get_sorted_indices() -> Array:
    ## Get indices sorted by fitness (descending)
    var indices := []
    for i in size:
        indices.append(i)

    indices.sort_custom(func(a, b): return fitness_scores[a] > fitness_scores[b])
    return indices


func get_elite(count: int) -> Array:
    ## Get top individuals by fitness
    var sorted := get_sorted_indices()
    var elite := []

    for i in mini(count, size):
        elite.append(individuals[sorted[i]])

    return elite


func replace_individual(index: int, new_individual) -> void:
    ## Replace an individual in the population
    if index >= 0 and index < size:
        individuals[index] = new_individual
        fitness_scores[index] = 0.0
        metadata[index] = {}


func get_statistics() -> Dictionary:
    ## Calculate population statistics
    var total := 0.0
    var min_fit := INF
    var max_fit := -INF

    for f in fitness_scores:
        total += f
        min_fit = minf(min_fit, f)
        max_fit = maxf(max_fit, f)

    var avg := total / size if size > 0 else 0.0

    # Calculate standard deviation
    var variance := 0.0
    for f in fitness_scores:
        var diff := f - avg
        variance += diff * diff
    variance /= size if size > 0 else 1.0

    return {
        "size": size,
        "average": avg,
        "min": min_fit,
        "max": max_fit,
        "std_dev": sqrt(variance),
        "best_index": get_best_index()
    }


func save_to_dict() -> Dictionary:
    ## Serialize population
    var data := {
        "size": size,
        "fitness_scores": fitness_scores,
        "metadata": metadata,
        "individuals": []
    }

    for ind in individuals:
        if ind.has_method("save_to_dict"):
            data.individuals.append(ind.save_to_dict())

    return data


func load_from_dict(data: Dictionary, factory_func: Callable) -> void:
    ## Deserialize population
    size = data.get("size", size)
    fitness_scores = data.get("fitness_scores", PackedFloat32Array())
    metadata = data.get("metadata", [])

    individuals.clear()
    var saved_individuals = data.get("individuals", [])

    for i in size:
        var ind = factory_func.call()
        if i < saved_individuals.size() and ind.has_method("load_from_dict"):
            ind.load_from_dict(saved_individuals[i])
        individuals.append(ind)