## class_name EvolutionBase (conflicts with ai/evolution_base.gd — removed)
extends RefCounted

## Base class for evolutionary algorithms.
## Provides common functionality for population-based evolution.

signal generation_complete(generation: int, stats: Dictionary)

var population_size: int
var population: Array = []
var fitness_scores: PackedFloat32Array
var generation: int = 0

var mutation_rate: float
var mutation_strength: float

var best_fitness: float = -INF
var all_time_best = null
var all_time_best_fitness: float = -INF

# Statistics tracking
var generation_stats: Dictionary = {}


func _init(
        p_population_size: int = 100,
        p_mutation_rate: float = 0.1,
        p_mutation_strength: float = 0.3
    ) -> void:
    population_size = p_population_size
    mutation_rate = p_mutation_rate
    mutation_strength = p_mutation_strength

    fitness_scores.resize(p_population_size)
    fitness_scores.fill(0.0)


func initialize_population() -> void:
    ## Override in subclasses to create initial population
    push_error("initialize_population() must be implemented in subclass")


func evaluate_fitness() -> void:
    ## Override in subclasses to evaluate population fitness
    push_error("evaluate_fitness() must be implemented in subclass")


func reset_fitness() -> void:
    ## Reset fitness scores to zero
    fitness_scores.fill(0.0)
    generation_stats.clear()


func set_fitness(index: int, fitness: float) -> void:
    ## Set fitness score for an individual
    if index >= 0 and index < population_size:
        fitness_scores[index] = fitness

        # Track best
        if fitness > best_fitness:
            best_fitness = fitness

        if all_time_best == null or fitness > all_time_best_fitness:
            if population[index].has_method("clone"):
                all_time_best = population[index].clone()
            else:
                all_time_best = population[index]
            all_time_best_fitness = fitness
    else:
        push_error("Invalid population index: " + str(index))


func get_individual(index: int):
    ## Get individual from population
    if index >= 0 and index < population.size():
        return population[index]
    return null


func evolve() -> void:
    ## Run one generation of evolution
    var new_population := _create_next_generation()
    population = new_population
    generation += 1

    # Update statistics
    _update_statistics()

    # Reset for next generation
    reset_fitness()

    # Emit signal
    generation_complete.emit(generation, generation_stats)


func _create_next_generation() -> Array:
    ## Override in subclasses to implement selection/reproduction
    push_error("_create_next_generation() must be implemented in subclass")
    return []


func _update_statistics() -> void:
    ## Calculate generation statistics
    var total_fitness := 0.0
    var min_fitness := INF
    var max_fitness := -INF

    for i in population_size:
        var f := fitness_scores[i]
        total_fitness += f
        min_fitness = minf(min_fitness, f)
        max_fitness = maxf(max_fitness, f)

    generation_stats = {
        "generation": generation,
        "best_fitness": best_fitness,
        "avg_fitness": total_fitness / population_size if population_size > 0 else 0.0,
        "min_fitness": min_fitness,
        "max_fitness": max_fitness,
        "all_time_best": all_time_best_fitness
    }


func get_best_individual():
    ## Get the best individual from current generation
    var best_idx := _get_best_index()
    if best_idx >= 0:
        return population[best_idx]
    return null


func _get_best_index() -> int:
    ## Find index of best individual by fitness
    var best_idx := -1
    var best_fit := -INF

    for i in population_size:
        if fitness_scores[i] > best_fit:
            best_fit = fitness_scores[i]
            best_idx = i

    return best_idx


func get_average_fitness() -> float:
    ## Calculate average fitness of current population
    if population_size == 0:
        return 0.0

    var total := 0.0
    for f in fitness_scores:
        total += f

    return total / population_size


func save_population(path: String) -> void:
    ## Save entire population to file
    var data := {
        "generation": generation,
        "population_size": population_size,
        "mutation_rate": mutation_rate,
        "mutation_strength": mutation_strength,
        "best_fitness": best_fitness,
        "all_time_best_fitness": all_time_best_fitness,
        "individuals": []
    }

    for individual in population:
        if individual.has_method("save_to_dict"):
            data.individuals.append(individual.save_to_dict())

    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data))
        file.close()
        print("Population saved to: ", path)
    else:
        push_error("Failed to save population to: " + path)


func load_population(path: String) -> bool:
    ## Load population from file
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        push_error("Failed to load population from: " + path)
        return false

    var json_string := file.get_as_text()
    file.close()

    var json := JSON.new()
    var parse_result := json.parse(json_string)

    if parse_result != OK:
        push_error("Failed to parse population file: " + path)
        return false

    var data: Dictionary = json.data

    # Restore settings
    generation = data.get("generation", 0)
    best_fitness = data.get("best_fitness", -INF)
    all_time_best_fitness = data.get("all_time_best_fitness", -INF)

    print("Population loaded from: ", path)
    return true