class_name SimpleEvolution
extends EvolutionBase

## Simple genetic algorithm implementation using evolve-core components.
## Single-objective evolution with tournament selection.

const Operators = preload("res://evolve-core/genetic/operators.gd")
const NetworkFactory = preload("res://evolve-core/ai/network_factory.gd")

var network_input_size: int
var network_hidden_size: int
var network_output_size: int

var elite_count: int
var crossover_rate: float
var tournament_size: int = 3
var use_memory: bool = false


func _init(
        p_population_size: int = 100,
        p_input_size: int = 64,
        p_hidden_size: int = 32,
        p_output_size: int = 8,
        p_elite_count: int = 10,
        p_mutation_rate: float = 0.1,
        p_mutation_strength: float = 0.3,
        p_crossover_rate: float = 0.7
    ) -> void:
    super._init(p_population_size, p_mutation_rate, p_mutation_strength)

    network_input_size = p_input_size
    network_hidden_size = p_hidden_size
    network_output_size = p_output_size
    elite_count = p_elite_count
    crossover_rate = p_crossover_rate


func initialize_population() -> void:
    ## Create initial population of neural networks
    population.clear()

    for i in population_size:
        var net = NetworkFactory.create(
            network_input_size,
            network_hidden_size,
            network_output_size,
            use_memory
        )
        population.append(net)

    generation = 0


func _create_next_generation() -> Array:
    ## Create next generation using genetic operators
    var new_population := []

    # Elitism - preserve best individuals
    var elite := Operators.elite_select(population, fitness_scores, elite_count)
    for individual in elite:
        new_population.append(individual.clone() if individual.has_method("clone") else individual)

    # Fill rest of population
    while new_population.size() < population_size:
        # Tournament selection
        var parent1 = Operators.tournament_select(population, fitness_scores, tournament_size)

        var offspring

        # Crossover or clone
        if randf() < crossover_rate:
            var parent2 = Operators.tournament_select(population, fitness_scores, tournament_size)
            offspring = Operators.two_point_crossover(parent1, parent2)
        else:
            offspring = parent1.clone() if parent1.has_method("clone") else parent1

        # Mutation
        Operators.gaussian_mutate(offspring, mutation_rate, mutation_strength)

        new_population.append(offspring)

    # Trim to exact size if needed
    while new_population.size() > population_size:
        new_population.pop_back()

    return new_population


func set_memory_enabled(enabled: bool) -> void:
    ## Enable/disable memory for all networks
    use_memory = enabled
    if population.is_empty():
        return

    for net in population:
        if enabled and net.has_method("enable_memory"):
            net.enable_memory()
        elif not enabled and net.has_method("reset_memory"):
            net.reset_memory()


func get_network_architecture() -> Dictionary:
    ## Get network architecture info
    return {
        "input_size": network_input_size,
        "hidden_size": network_hidden_size,
        "output_size": network_output_size,
        "use_memory": use_memory
    }


func save_best_network(path: String) -> bool:
    ## Save the best network to file
    var best = get_best_individual()
    if not best or not best.has_method("save_to_dict"):
        push_error("Best individual cannot be saved")
        return false

    var data := {
        "architecture": get_network_architecture(),
        "generation": generation,
        "fitness": all_time_best_fitness,
        "network": best.save_to_dict()
    }

    var file := FileAccess.open(path, FileAccess.WRITE)
    if not file:
        push_error("Failed to open file: " + path)
        return false

    file.store_string(JSON.stringify(data))
    file.close()
    return true


func load_best_network(path: String):
    ## Load a network from file
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        push_error("Failed to open file: " + path)
        return null

    var json_string := file.get_as_text()
    file.close()

    var json := JSON.new()
    var parse_result := json.parse(json_string)

    if parse_result != OK:
        push_error("Failed to parse network file")
        return null

    var data: Dictionary = json.data
    var arch = data.get("architecture", {})

    # Create network with saved architecture
    var net = NetworkFactory.create(
        arch.get("input_size", network_input_size),
        arch.get("hidden_size", network_hidden_size),
        arch.get("output_size", network_output_size),
        arch.get("use_memory", use_memory)
    )

    # Load weights
    if net.has_method("load_from_dict"):
        net.load_from_dict(data.get("network", {}))

    return net