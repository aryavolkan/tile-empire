extends RefCounted
class_name NeatSpecies

## A species in NEAT: a group of genomes with similar topology.
## Tracks fitness history for stagnation detection and provides
## adjusted fitness (fitness sharing) to prevent large species
## from dominating the population.

var id: int
var representative: NeatGenome  ## The genome new members are compared against
var members: Array = []  ## Array of NeatGenome
var best_fitness: float = 0.0
var best_fitness_ever: float = 0.0
var generations_without_improvement: int = 0
var age: int = 0  ## How many generations this species has existed


func _init(p_id: int, p_representative: NeatGenome) -> void:
    id = p_id
    representative = p_representative
    members = [p_representative]


func add_member(genome: NeatGenome) -> void:
    members.append(genome)


func clear_members() -> void:
    ## Remove all members but keep representative for next-gen comparison.
    members.clear()


func update_representative() -> void:
    ## Pick a random member as the new representative for next generation.
    if not members.is_empty():
        representative = members[randi() % members.size()]


func calculate_adjusted_fitness() -> void:
    ## Fitness sharing: divide each member's fitness by species size.
    ## This prevents large species from dominating.
    var species_size: float = members.size()
    if species_size == 0:
        return
    for genome in members:
        genome.adjusted_fitness = genome.fitness / species_size


func update_best_fitness() -> void:
    ## Track best fitness and stagnation.
    var current_best: float = 0.0
    for genome in members:
        current_best = maxf(current_best, genome.fitness)

    if current_best > best_fitness_ever:
        best_fitness_ever = current_best
        generations_without_improvement = 0
    else:
        generations_without_improvement += 1

    best_fitness = current_best
    age += 1


func get_total_adjusted_fitness() -> float:
    ## Sum of adjusted fitness for all members (used for offspring allocation).
    var total: float = 0.0
    for genome in members:
        total += genome.adjusted_fitness
    return total


func get_best_genome() -> NeatGenome:
    ## Return the fittest member.
    var best: NeatGenome = null
    var best_fit: float = -INF
    for genome in members:
        if genome.fitness > best_fit:
            best_fit = genome.fitness
            best = genome
    return best


func get_sorted_members() -> Array:
    ## Return members sorted by fitness descending.
    var sorted := members.duplicate()
    sorted.sort_custom(func(a, b): return a.fitness > b.fitness)
    return sorted


func is_stagnant(threshold: int) -> bool:
    return generations_without_improvement >= threshold


func is_empty() -> bool:
    return members.is_empty()


static func speciate(
    population: Array,
    existing_species: Array,
    config: NeatConfig,
    next_species_id: int
) -> Dictionary:
    ## Assign each genome in population to a species.
    ## Returns {"species": Array[NeatSpecies], "next_id": int}

    # Clear existing species members but keep representatives
    for species in existing_species:
        species.clear_members()

    var new_species_list: Array = existing_species.duplicate()
    var current_id: int = next_species_id

    for genome in population:
        var placed := false
        for species in new_species_list:
            var dist: float = genome.compatibility(species.representative, config)
            if dist < config.compatibility_threshold:
                species.add_member(genome)
                placed = true
                break

        if not placed:
            # Create new species with this genome as representative
            var new_sp := NeatSpecies.new(current_id, genome)
            new_species_list.append(new_sp)
            current_id += 1

    # Remove empty species (no members assigned this generation)
    new_species_list = new_species_list.filter(func(s): return not s.is_empty())

    # Update representatives for next generation
    for species in new_species_list:
        species.update_representative()

    return {"species": new_species_list, "next_id": current_id}


static func adjust_compatibility_threshold(
    species_list: Array,
    config: NeatConfig
) -> void:
    ## Dynamically adjust compatibility threshold to target species count.
    var current_count: int = species_list.size()
    if current_count < config.target_species_count:
        config.compatibility_threshold -= config.threshold_step
    elif current_count > config.target_species_count:
        config.compatibility_threshold += config.threshold_step
    # Clamp to reasonable range
    config.compatibility_threshold = maxf(config.compatibility_threshold, 0.3)
