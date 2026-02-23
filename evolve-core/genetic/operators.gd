class_name GeneticOperators
extends RefCounted

## Common genetic operators for evolutionary algorithms.
## Provides selection, crossover, and mutation operations.

## Selection Methods

static func tournament_select(
        population: Array,
        fitness: PackedFloat32Array,
        tournament_size: int = 3
    ):
    ## Tournament selection - pick best from random subset
    assert(population.size() == fitness.size(), "Population and fitness size mismatch")
    assert(population.size() > 0, "Empty population")

    var best_idx := randi() % population.size()
    var best_fitness := fitness[best_idx]

    for i in range(1, tournament_size):
        var idx := randi() % population.size()
        if fitness[idx] > best_fitness:
            best_idx = idx
            best_fitness = fitness[idx]

    return population[best_idx]


static func roulette_select(
        population: Array,
        fitness: PackedFloat32Array
    ):
    ## Fitness-proportionate (roulette wheel) selection
    assert(population.size() == fitness.size(), "Population and fitness size mismatch")
    assert(population.size() > 0, "Empty population")

    # Calculate total fitness
    var total_fitness := 0.0
    for f in fitness:
        total_fitness += maxf(f, 0.0)  # Ensure non-negative

    if total_fitness <= 0.0:
        # Fallback to random selection if all fitness is zero/negative
        return population[randi() % population.size()]

    # Spin the wheel
    var target := randf() * total_fitness
    var cumulative := 0.0

    for i in population.size():
        cumulative += maxf(fitness[i], 0.0)
        if cumulative >= target:
            return population[i]

    # Shouldn't reach here, but return last individual just in case
    return population[-1]


static func rank_select(
        population: Array,
        fitness: PackedFloat32Array,
        selection_pressure: float = 1.5
    ):
    ## Rank-based selection (reduces impact of fitness outliers)
    assert(population.size() == fitness.size(), "Population and fitness size mismatch")
    assert(population.size() > 0, "Empty population")

    # Create and sort indices by fitness
    var indices := []
    for i in population.size():
        indices.append(i)
    indices.sort_custom(func(a, b): return fitness[a] > fitness[b])

    # Calculate rank probabilities
    var n := population.size()
    var total_prob := 0.0
    var probs := PackedFloat32Array()
    probs.resize(n)

    for i in n:
        # Linear ranking: p(i) = (2-SP)/N + 2*i*(SP-1)/(N*(N-1))
        var rank := n - i  # Best has rank n, worst has rank 1
        probs[i] = (2.0 - selection_pressure) / n + 2.0 * (rank - 1) * (selection_pressure - 1.0) / (n * (n - 1))
        total_prob += probs[i]

    # Select based on rank probabilities
    var target := randf() * total_prob
    var cumulative := 0.0

    for i in n:
        cumulative += probs[i]
        if cumulative >= target:
            return population[indices[i]]

    return population[indices[-1]]


static func elite_select(
        population: Array,
        fitness: PackedFloat32Array,
        elite_count: int
    ) -> Array:
    ## Select top individuals by fitness
    assert(population.size() == fitness.size(), "Population and fitness size mismatch")

    var elite_size := mini(elite_count, population.size())
    if elite_size <= 0:
        return []

    # Sort indices by fitness
    var indices := []
    for i in population.size():
        indices.append(i)
    indices.sort_custom(func(a, b): return fitness[a] > fitness[b])

    # Select top individuals
    var elite := []
    for i in elite_size:
        elite.append(population[indices[i]])

    return elite


## Crossover Methods

static func uniform_crossover(parent_a, parent_b, crossover_rate: float = 0.5):
    ## Uniform crossover - each gene has equal chance from either parent
    assert(parent_a.has_method("get_weights") and parent_b.has_method("get_weights"),
        "Parents must have get_weights() method")
    assert(parent_a.has_method("set_weights"), "Parents must have set_weights() method")

    var weights_a: PackedFloat32Array = parent_a.get_weights()
    var weights_b: PackedFloat32Array = parent_b.get_weights()
    assert(weights_a.size() == weights_b.size(), "Parent weight sizes must match")

    var child = parent_a.clone() if parent_a.has_method("clone") else parent_a.duplicate()
    var child_weights := PackedFloat32Array()
    child_weights.resize(weights_a.size())

    for i in weights_a.size():
        child_weights[i] = weights_a[i] if randf() > crossover_rate else weights_b[i]

    child.set_weights(child_weights)
    return child


static func single_point_crossover(parent_a, parent_b):
    ## Single-point crossover
    assert(parent_a.has_method("get_weights") and parent_b.has_method("get_weights"),
        "Parents must have get_weights() method")
    assert(parent_a.has_method("set_weights"), "Parents must have set_weights() method")

    var weights_a: PackedFloat32Array = parent_a.get_weights()
    var weights_b: PackedFloat32Array = parent_b.get_weights()
    assert(weights_a.size() == weights_b.size(), "Parent weight sizes must match")

    var child = parent_a.clone() if parent_a.has_method("clone") else parent_a.duplicate()
    var child_weights := PackedFloat32Array()
    child_weights.resize(weights_a.size())

    var crossover_point: int = randi() % weights_a.size()

    for i in weights_a.size():
        child_weights[i] = weights_a[i] if i < crossover_point else weights_b[i]

    child.set_weights(child_weights)
    return child


static func two_point_crossover(parent_a, parent_b):
    ## Two-point crossover (as used in neural networks)
    if parent_a.has_method("crossover_with"):
        # Use built-in crossover if available
        return parent_a.crossover_with(parent_b)

    # Otherwise implement it
    assert(parent_a.has_method("get_weights") and parent_b.has_method("get_weights"),
        "Parents must have get_weights() method")
    assert(parent_a.has_method("set_weights"), "Parents must have set_weights() method")

    var weights_a: PackedFloat32Array = parent_a.get_weights()
    var weights_b: PackedFloat32Array = parent_b.get_weights()
    assert(weights_a.size() == weights_b.size(), "Parent weight sizes must match")

    var child = parent_a.clone() if parent_a.has_method("clone") else parent_a.duplicate()
    var child_weights := PackedFloat32Array()
    child_weights.resize(weights_a.size())

    var p1: int = randi() % weights_a.size()
    var p2: int = randi() % weights_a.size()
    if p1 > p2:
        var tmp: int = p1; p1 = p2; p2 = tmp

    for i in weights_a.size():
        child_weights[i] = weights_b[i] if (i >= p1 and i < p2) else weights_a[i]

    child.set_weights(child_weights)
    return child


## Mutation Methods

static func gaussian_mutate(
        individual,
        mutation_rate: float = 0.1,
        mutation_strength: float = 0.3
    ) -> void:
    ## Apply Gaussian mutation to an individual
    if individual.has_method("mutate"):
        # Use built-in mutation if available
        individual.mutate(mutation_rate, mutation_strength)
    else:
        push_error("Individual doesn't have mutate() method")


static func reset_mutate(
        individual,
        mutation_rate: float = 0.01,
        reset_range: float = 1.0
    ) -> void:
    ## Reset mutation - randomly reset some weights
    assert(individual.has_method("get_weights") and individual.has_method("set_weights"),
        "Individual must have get/set_weights() methods")

    var weights: PackedFloat32Array = individual.get_weights()

    for i in weights.size():
        if randf() < mutation_rate:
            weights[i] = randf_range(-reset_range, reset_range)

    individual.set_weights(weights)


static func creep_mutate(
        individual,
        mutation_rate: float = 0.1,
        creep_rate: float = 0.9,
        mutation_strength: float = 0.3
    ) -> void:
    ## Creep mutation - small changes with occasional larger jumps
    assert(individual.has_method("get_weights") and individual.has_method("set_weights"),
        "Individual must have get/set_weights() methods")

    var weights: PackedFloat32Array = individual.get_weights()

    for i in weights.size():
        if randf() < mutation_rate:
            if randf() < creep_rate:
                # Small creep
                weights[i] += randfn(0.0, mutation_strength * 0.1)
            else:
                # Larger jump
                weights[i] += randfn(0.0, mutation_strength)

    individual.set_weights(weights)