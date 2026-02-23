extends RefCounted
class_name NeatEvolutionRustIntegration

## Integration helpers for using Rust NEAT implementations.
## Drop-in replacements for hot path operations.

static var _rust_genome = null
static var _rust_species = null
static var _checked = false

static func _check_rust_available() -> void:
    if _checked:
        return
    _checked = true

    if ClassDB.class_exists(&"RustNeatGenome"):
        _rust_genome = ClassDB.instantiate(&"RustNeatGenome")
        if _rust_genome:
            print("[NEAT] ✓ Using Rust genome operations (distance, crossover, mutate)")
        else:
            print("[NEAT] ⚠ RustNeatGenome class exists but couldn't instantiate")

    if ClassDB.class_exists(&"RustNeatSpecies"):
        _rust_species = ClassDB.instantiate(&"RustNeatSpecies")
        if _rust_species:
            print("[NEAT] ✓ Using Rust speciation (5-8x faster)")
        else:
            print("[NEAT] ⚠ RustNeatSpecies class exists but couldn't instantiate")

## Calculate distance between two genomes using Rust if available
static func genome_distance(genome_a: NeatGenome, genome_b: NeatGenome, config: NeatConfig) -> float:
    _check_rust_available()

    if _rust_genome:
        # Convert genomes to dictionary format for Rust
        var dict_a = _genome_to_dict(genome_a)
        var dict_b = _genome_to_dict(genome_b)
        var config_dict = _config_to_dict(config)
        return _rust_genome.distance(dict_a, dict_b, config_dict)
    else:
        # Fallback to GDScript
        return genome_a.distance(genome_b, config)

## Perform crossover using Rust if available
static func crossover(parent_a: NeatGenome, parent_b: NeatGenome) -> NeatGenome:
    _check_rust_available()

    if _rust_genome:
        var dict_a = _genome_to_dict(parent_a)
        var dict_b = _genome_to_dict(parent_b)
        var child_dict = _rust_genome.crossover(dict_a, dict_b)
        return _dict_to_genome(child_dict, parent_a.config, parent_a.innovation_tracker)
    else:
        # Fallback to GDScript
        return NeatGenome.crossover(parent_a, parent_b)

## Mutate genome using Rust if available
static func mutate(genome: NeatGenome, config: NeatConfig) -> void:
    _check_rust_available()

    if _rust_genome:
        var genome_dict = _genome_to_dict(genome)
        var config_dict = _config_to_dict(config)
        _rust_genome.mutate(genome_dict, config_dict)
        # Update genome from mutated dictionary
        _update_genome_from_dict(genome, genome_dict)
    else:
        # Fallback to GDScript
        genome.mutate(config)

## Speciate population using Rust if available
static func speciate(population: Array, species_list: Array, config: NeatConfig, next_species_id: int) -> Dictionary:
    _check_rust_available()

    if _rust_species:
        # Convert to format Rust expects
        var pop_array = []
        for genome in population:
            pop_array.append(_genome_to_dict(genome))

        var species_array = []
        for species in species_list:
            species_array.append(_species_to_dict(species))

        var result = _rust_species.speciate(pop_array, species_array, _config_to_dict(config), next_species_id)

        # Convert result back to GDScript objects
        var new_species = []
        var species_data = result.get("species", [])
        for sp_dict in species_data:
            var species = NeatSpecies.new(sp_dict.get("id", 0), config)
            species.stagnant_generations = sp_dict.get("stagnant_generations", 0)
            species.best_fitness_ever = sp_dict.get("best_fitness", 0.0)
            # Add members
            for member_idx in sp_dict.get("members", []):
                species.add_member(population[member_idx])
            if species.members.size() > 0:
                var repr_idx = sp_dict.get("representative", 0)
                species.representative = population[repr_idx]
            new_species.append(species)

        return {
            "species": new_species,
            "next_id": result.get("next_id", next_species_id)
        }
    else:
        # Fallback to GDScript
        return NeatSpecies.speciate(population, species_list, config, next_species_id)

## Helper to convert NeatGenome to dictionary for Rust
static func _genome_to_dict(genome: NeatGenome) -> Dictionary:
    var connections = []
    for conn in genome.connections:
        connections.append({
            "from": conn.from,
            "to": conn.to,
            "weight": conn.weight,
            "enabled": conn.enabled,
            "innovation": conn.innovation
        })

    var nodes = []
    for node in genome.nodes:
        nodes.append({
            "id": node.id,
            "type": node.type
        })

    return {
        "connections": connections,
        "nodes": nodes,
        "fitness": genome.fitness,
        "input_count": genome.config.input_count,
        "output_count": genome.config.output_count
    }

## Helper to convert dictionary back to NeatGenome
static func _dict_to_genome(dict: Dictionary, config: NeatConfig, innovation_tracker: NeatInnovation) -> NeatGenome:
    var genome = NeatGenome.new(config, innovation_tracker)

    # Recreate nodes
    genome.nodes.clear()
    for node_data in dict.get("nodes", []):
        var node = NeatNode.new(node_data.id, node_data.type)
        genome.nodes.append(node)

    # Recreate connections
    genome.connections.clear()
    for conn_data in dict.get("connections", []):
        var conn = NeatConnection.new(
            conn_data.from,
            conn_data.to,
            conn_data.weight,
            conn_data.enabled,
            conn_data.innovation
        )
        genome.connections.append(conn)

    genome.fitness = dict.get("fitness", 0.0)
    return genome

## Update genome from mutated dictionary
static func _update_genome_from_dict(genome: NeatGenome, dict: Dictionary) -> void:
    # Update connections with mutated weights
    var conn_array = dict.get("connections", [])
    for i in min(genome.connections.size(), conn_array.size()):
        genome.connections[i].weight = conn_array[i].get("weight", genome.connections[i].weight)
        genome.connections[i].enabled = conn_array[i].get("enabled", genome.connections[i].enabled)

    # Handle removed connections
    while genome.connections.size() > conn_array.size():
        genome.connections.pop_back()

## Helper to convert NeatConfig to dictionary
static func _config_to_dict(config: NeatConfig) -> Dictionary:
    return {
        "population_size": config.population_size,
        "compatibility_excess_coeff": config.compatibility_excess_coeff,
        "compatibility_disjoint_coeff": config.compatibility_disjoint_coeff,
        "compatibility_weight_coeff": config.compatibility_weight_coeff,
        "compatibility_threshold": config.compatibility_threshold,
        "mutation_rate": config.mutation_rate,
        "weight_mutation_rate": config.weight_mutation_rate,
        "weight_mutation_strength": config.weight_mutation_strength,
        "weight_replace_rate": config.weight_replace_rate,
        "node_add_rate": config.node_add_rate,
        "conn_add_rate": config.conn_add_rate,
        "conn_delete_rate": config.conn_delete_rate,
        "conn_enable_rate": config.conn_enable_rate,
        "conn_disable_rate": config.conn_disable_rate,
    }

## Helper to convert NeatSpecies to dictionary
static func _species_to_dict(species: NeatSpecies) -> Dictionary:
    var members = []
    for i in species.members.size():
        members.append(i)  # Store indices

    return {
        "id": species.id,
        "members": members,
        "representative": 0,  # Will be set by Rust
        "stagnant_generations": species.stagnant_generations,
        "best_fitness": species.best_fitness_ever
    }