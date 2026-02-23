extends "res://ai/evolution_base.gd"
class_name NeatEvolution

const NSGA2 = preload("res://evolve-core/genetic/nsga2.gd")

## NEAT evolution manager: manages a population of NeatGenomes,
## organizes them into species, and produces new generations via
## species-proportionate reproduction with crossover and mutation.

var config: NeatConfig
var innovation_tracker: NeatInnovation
var species_list: Array = []  ## Array of NeatSpecies
var best_genome: NeatGenome = null
var all_time_best_genome: NeatGenome = null
var _next_species_id: int = 0

# Multi-objective support (MO-NEAT)
var objective_scores: Array = []  ## Array of Vector3 per individual; set via set_objectives()
var pareto_front: Array = []
var last_hypervolume: float = 0.0

func _init(p_config: NeatConfig) -> void:
    config = p_config
    super._init(config.population_size, 0.0, 0.0)
    innovation_tracker = NeatInnovation.new(p_config.input_count + p_config.output_count + int(p_config.use_bias))
    _initialize_population()


func _initialize_population() -> void:
    population.clear()
    for i in config.population_size:
        var genome := NeatGenome.create(config, innovation_tracker)
        genome.create_basic()
        population.append(genome)
    population_size = config.population_size
    generation = 0
    seed_lineage(population.size())
    _reset_scores()
    _reset_objective_scores()


func _reset_objective_scores() -> void:
    objective_scores.clear()
    for i in config.population_size:
        objective_scores.append(Vector3.ZERO)


func get_individual(index: int) -> NeatGenome:
    return population[index]


func get_network(index: int) -> NeatNetwork:
    ## Build a phenotype network for individual at index.
    return NeatNetwork.from_genome(population[index])


func set_fitness(index: int, fitness: float) -> void:
    population[index].fitness = fitness
    super.set_fitness(index, fitness)


func set_objectives(index: int, objectives: Vector3) -> void:
    ## MO-NEAT: store multi-objective scores. Actual fitness conversion happens
    ## at the start of evolve() via _apply_mo_fitness().
    if index >= 0 and index < objective_scores.size():
        objective_scores[index] = objectives
    # Set scalar fitness as sum for any immediate reads before evolve()
    var scalar := objectives.x + objectives.y + objectives.z
    if index >= 0 and index < population.size():
        population[index].fitness = scalar
    super.set_fitness(index, scalar)


func _apply_mo_fitness() -> void:
    ## Convert stored objective scores into MO fitness scalars using NSGA-II ranking.
    ## Assigns each genome a fitness that reflects its Pareto rank + crowding distance.
    ## Called at the start of evolve() when objectives have been set.
    if objective_scores.is_empty():
        return
    var has_objectives := false
    for obj in objective_scores:
        if obj != Vector3.ZERO:
            has_objectives = true
            break
    if not has_objectives:
        return

    var fronts: Array = NSGA2.non_dominated_sort(objective_scores)
    if fronts.is_empty():
        return

    # Update pareto_front for metrics reporting
    pareto_front = NSGA2.get_pareto_front(objective_scores)

    # Compute crowding distances per front
    var crowding_map: Dictionary = {}
    for front in fronts:
        var distances: PackedFloat32Array = NSGA2.crowding_distance(front, objective_scores)
        for i in front.size():
            crowding_map[front[i]] = distances[i]

    # Build flat rank lookup
    var rank_map: PackedInt32Array = NSGA2.build_rank_map(fronts, population.size())
    var num_fronts := float(fronts.size())

    # Normalization scale: use max raw scalar across population
    var max_scalar: float = 1.0
    for obj in objective_scores:
        max_scalar = maxf(max_scalar, obj.x + obj.y + obj.z)

    # Assign MO fitness to each genome:
    #   mo_fitness = raw_scalar + rank_bonus + crowd_bonus
    # rank_bonus: exponential decay per front (rank 0 → +max_scalar, rank 1 → +max_scalar/2, ...)
    # crowd_bonus: up to 10% of max_scalar for diversity preservation within a front
    for i in population.size():
        var rank: int = rank_map[i] if i < rank_map.size() else int(num_fronts)
        var raw: float = objective_scores[i].x + objective_scores[i].y + objective_scores[i].z
        var rank_bonus: float = max_scalar * pow(0.5, rank)
        var cd: float = crowding_map.get(i, 0.0)
        var crowd_bonus: float = (max_scalar * 0.1) if cd == INF else minf(cd / max(max_scalar, 1.0), 0.1) * max_scalar
        var mo_fitness: float = raw + rank_bonus + crowd_bonus
        population[i].fitness = mo_fitness
        fitness_scores[i] = mo_fitness


func evolve() -> void:
    ## Run one generation of NEAT evolution:
    ## 1. (MO-NEAT) Convert objectives to scalar fitness if set
    ## 2. Speciate
    ## 3. Evaluate fitness sharing
    ## 4. Track stagnation, cull stagnant species
    ## 5. Allocate offspring per species
    ## 6. Reproduce (crossover + mutation)
    ## 7. Adjust compatibility threshold
    _apply_mo_fitness()
    save_backup()

    # 1. Speciate
    var spec_result: Dictionary = NeatSpecies.speciate(population, species_list, config, _next_species_id)
    species_list = spec_result.species
    _next_species_id = spec_result.next_id

    if species_list.is_empty():
        # Shouldn't happen, but reinitialize if it does
        _initialize_population()
        return

    # 2. Fitness sharing + track best
    var total_fitness: float = 0.0
    var gen_best_fitness: float = -INF
    var gen_best_genome: NeatGenome = null

    for species in species_list:
        species.calculate_adjusted_fitness()
        species.update_best_fitness()
        var sp_best = species.get_best_genome()
        if sp_best and sp_best.fitness > gen_best_fitness:
            gen_best_fitness = sp_best.fitness
            gen_best_genome = sp_best

    best_fitness = gen_best_fitness
    best_genome = gen_best_genome.copy() if gen_best_genome else null

    if best_fitness > all_time_best_fitness:
        all_time_best_fitness = best_fitness
        all_time_best_genome = best_genome.copy() if best_genome else null

    # 3. Cull stagnant species (protect top N)
    _cull_stagnant_species()

    if species_list.is_empty():
        _initialize_population()
        return

    # 4. Compute offspring allocation proportional to adjusted fitness
    var total_adjusted: float = 0.0
    for species in species_list:
        total_adjusted += species.get_total_adjusted_fitness()

    var new_population: Array = []

    # Build genome → lineage ID map for tracking parents
    var genome_lid: Dictionary = {}  # genome ref → lineage_id
    if lineage:
        for i in population.size():
            if i < _lineage_ids.size():
                genome_lid[population[i]] = _lineage_ids[i]

    var new_lineage_ids: PackedInt32Array
    if lineage:
        new_lineage_ids.resize(config.population_size)

    # 5. Reproduce
    for species in species_list:
        var sp_adjusted: float = species.get_total_adjusted_fitness()
        var offspring_count: int
        if total_adjusted > 0:
            offspring_count = int(round(sp_adjusted / total_adjusted * config.population_size))
        else:
            offspring_count = int(ceil(float(config.population_size) / species_list.size()))

        offspring_count = maxi(offspring_count, 1)  # At least 1 offspring per species

        var sorted_members: Array = species.get_sorted_members()
        if sorted_members.is_empty():
            continue

        # Elite: keep best genome unchanged
        var elite_count: int = maxi(1, int(sorted_members.size() * config.elite_fraction))
        for i in mini(elite_count, offspring_count):
            new_population.append(sorted_members[i].copy())
            if lineage:
                var src_lid: int = genome_lid.get(sorted_members[i], -1)
                if new_population.size() - 1 < new_lineage_ids.size():
                    new_lineage_ids[new_population.size() - 1] = lineage.record_birth(generation + 1, src_lid, -1, sorted_members[i].fitness, "elite")

        # Breeding pool: top survival_fraction
        var pool_size: int = maxi(1, int(sorted_members.size() * config.survival_fraction))
        var pool: Array = sorted_members.slice(0, pool_size)

        # Fill remaining offspring
        var remaining: int = offspring_count - mini(elite_count, offspring_count)
        for i in remaining:
            var child: NeatGenome
            if randf() < config.crossover_rate and pool.size() >= 2:
                var parent_a: NeatGenome = pool[randi() % pool.size()]
                var parent_b: NeatGenome
                # Rare interspecies crossover
                if randf() < config.interspecies_crossover_rate and species_list.size() > 1:
                    var other_species = species_list[randi() % species_list.size()]
                    if not other_species.members.is_empty():
                        parent_b = other_species.members[randi() % other_species.members.size()]
                    else:
                        parent_b = pool[randi() % pool.size()]
                else:
                    parent_b = pool[randi() % pool.size()]
                child = NeatGenome.crossover(parent_a, parent_b)
                if lineage:
                    var lid_a: int = genome_lid.get(parent_a, -1)
                    var lid_b: int = genome_lid.get(parent_b, -1)
                    if new_population.size() < new_lineage_ids.size():
                        new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, lid_b, 0.0, "crossover")
            else:
                var parent: NeatGenome = pool[randi() % pool.size()]
                child = parent.copy()
                if lineage:
                    var lid_a: int = genome_lid.get(parent, -1)
                    if new_population.size() < new_lineage_ids.size():
                        new_lineage_ids[new_population.size()] = lineage.record_birth(generation + 1, lid_a, -1, 0.0, "mutation")

            child.mutate(config)
            new_population.append(child)

    # Compute average and min fitness from OLD population (before replacement)
    var avg_fitness: float = 0.0
    var min_fitness: float = INF
    for genome in population:
        avg_fitness += genome.fitness
        min_fitness = minf(min_fitness, genome.fitness)
    avg_fitness /= population.size() if not population.is_empty() else 1.0
    if min_fitness == INF:
        min_fitness = 0.0

    cache_stats(min_fitness, avg_fitness, best_fitness)

    # Trim or pad to exact population size
    while new_population.size() > config.population_size:
        new_population.pop_back()
    while new_population.size() < config.population_size:
        var src_idx: int = randi() % population.size()
        var filler = population[src_idx].copy()
        filler.mutate(config)
        new_population.append(filler)
        if lineage:
            var lid: int = genome_lid.get(population[src_idx], -1)
            if new_population.size() - 1 < new_lineage_ids.size():
                new_lineage_ids[new_population.size() - 1] = lineage.record_birth(generation + 1, lid, -1, 0.0, "mutation")

    population = new_population
    population_size = config.population_size
    if lineage:
        _lineage_ids = new_lineage_ids
    generation += 1

    # Reset innovation cache for next generation
    innovation_tracker.reset_generation_cache()

    # 7. Adjust compatibility threshold
    NeatSpecies.adjust_compatibility_threshold(species_list, config)

    _reset_scores()
    _reset_objective_scores()

    generation_complete.emit(generation, best_fitness, avg_fitness, min_fitness)


func _cull_stagnant_species() -> void:
    ## Remove species that have stagnated too long.
    ## Always protect the top min_species_protected species by best fitness.
    if species_list.size() <= config.min_species_protected:
        return

    # Sort species by best_fitness_ever descending
    var sorted_species := species_list.duplicate()
    sorted_species.sort_custom(func(a, b): return a.best_fitness_ever > b.best_fitness_ever)

    var surviving: Array = []
    for i in sorted_species.size():
        if i < config.min_species_protected:
            # Always keep top species
            surviving.append(sorted_species[i])
        elif sorted_species[i].is_stagnant(config.stagnation_kill_threshold):
            continue  # Kill stagnant species
        else:
            surviving.append(sorted_species[i])

    species_list = surviving


func get_species_count() -> int:
    return species_list.size()


func inject_immigrant(genome: NeatGenome) -> void:
    ## Replace worst individual with an immigrant genome.
    if population.is_empty():
        return
    var worst_idx := 0
    var worst_fit: float = population[0].fitness
    for i in range(1, population.size()):
        if population[i].fitness < worst_fit:
            worst_fit = population[i].fitness
            worst_idx = i
    population[worst_idx] = genome


func _get_additional_stats() -> Dictionary:
    return {
        "species_count": species_list.size(),
        "compatibility_threshold": config.compatibility_threshold,
    }


func _get_live_fitness_samples() -> Array:
    var samples: Array = []
    for genome in population:
        samples.append(genome.fitness)
    return samples


func _clone_individual(individual):
    return individual.copy()


func _get_all_time_best_entity():
    return all_time_best_genome


func _set_all_time_best_entity(entity) -> void:
    all_time_best_genome = entity


func _save_entity(path: String, entity) -> void:
    if not entity:
        return
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(entity.serialize()))
        file.close()


func _load_entity(path: String):
    if not FileAccess.file_exists(path):
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return null
    var json := JSON.new()
    var text := file.get_as_text()
    file.close()
    if json.parse(text) != OK:
        return null
    return NeatGenome.deserialize(json.data, config, innovation_tracker)


func _save_population_impl(path: String) -> void:
    var genomes: Array = []
    for genome in population:
        genomes.append(genome.serialize())
    var data := {
        "generation": generation,
        "best_fitness": best_fitness,
        "all_time_best_fitness": all_time_best_fitness,
        "all_time_best_genome": all_time_best_genome.serialize() if all_time_best_genome else null,
        "genomes": genomes,
    }
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data))
        file.close()


func _load_population_impl(path: String) -> bool:
    if not FileAccess.file_exists(path):
        return false
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return false
    var json := JSON.new()
    var text := file.get_as_text()
    file.close()
    if json.parse(text) != OK:
        return false
    var data: Dictionary = json.data

    population.clear()
    for genome_data in data.get("genomes", []):
        population.append(NeatGenome.deserialize(genome_data, config, innovation_tracker))

    population_size = population.size()
    generation = int(data.get("generation", 0))
    best_fitness = float(data.get("best_fitness", 0.0))
    all_time_best_fitness = float(data.get("all_time_best_fitness", 0.0))
    var atb_data = data.get("all_time_best_genome")
    if atb_data and atb_data is Dictionary:
        all_time_best_genome = NeatGenome.deserialize(atb_data, config, innovation_tracker)
    return true
