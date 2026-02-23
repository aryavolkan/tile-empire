class_name ConfigBase
extends RefCounted

## Base configuration class for evolution/training parameters.
## Provides common functionality for loading/saving configurations.

# Core evolution parameters
var population_size: int = 100
var mutation_rate: float = 0.1
var mutation_strength: float = 0.3
var elite_count: int = 10
var crossover_rate: float = 0.7

# Network architecture
var input_size: int = 64
var hidden_size: int = 32
var output_size: int = 8

# Training parameters
var max_generations: int = 1000
var target_fitness: float = INF
var stagnation_limit: int = 50

# Evaluation
var episodes_per_eval: int = 1
var max_episode_steps: int = 1000

# Feature flags
var use_parallel_evaluation: bool = true
var save_checkpoints: bool = true
var checkpoint_interval: int = 10

# Paths
var checkpoint_dir: String = "user://checkpoints/"
var best_network_path: String = "user://best_network.dat"
var population_path: String = "user://population.dat"

# Metadata
var config_name: String = "default"
var created_timestamp: int = 0
var last_modified: int = 0


func _init(p_config_name: String = "default") -> void:
    config_name = p_config_name
    created_timestamp = Time.get_unix_time_from_system()
    last_modified = created_timestamp


func load_from_dict(data: Dictionary) -> void:
    ## Load configuration from dictionary
    for key in data:
        if key in self:
            set(key, data[key])
    last_modified = Time.get_unix_time_from_system()


func save_to_dict() -> Dictionary:
    ## Save configuration to dictionary
    var data := {}

    # Get all properties
    for prop in get_property_list():
        var prop_name = prop.name
        # Skip built-in properties
        if prop_name.begins_with("_") or prop_name == "script":
            continue
        data[prop_name] = get(prop_name)

    return data


func load_from_file(path: String) -> bool:
    ## Load configuration from JSON file
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        push_error("Failed to open config file: " + path)
        return false

    var json_string := file.get_as_text()
    file.close()

    var json := JSON.new()
    var parse_result := json.parse(json_string)

    if parse_result != OK:
        push_error("Failed to parse config JSON: " + path)
        return false

    if json.data is Dictionary:
        load_from_dict(json.data)
        return true
    else:
        push_error("Invalid config format in: " + path)
        return false


func save_to_file(path: String) -> bool:
    ## Save configuration to JSON file
    var dir_path := path.get_base_dir()
    if not DirAccess.dir_exists_absolute(dir_path):
        DirAccess.make_dir_recursive_absolute(dir_path)

    var file := FileAccess.open(path, FileAccess.WRITE)
    if not file:
        push_error("Failed to create config file: " + path)
        return false

    var data := save_to_dict()
    data["last_modified"] = Time.get_unix_time_from_system()

    file.store_string(JSON.stringify(data, "\t"))
    file.close()
    return true


func validate() -> Array:
    ## Validate configuration and return any errors/warnings
    var issues := []

    if population_size <= 0:
        issues.append("Population size must be positive")

    if mutation_rate < 0.0 or mutation_rate > 1.0:
        issues.append("Mutation rate must be between 0 and 1")

    if elite_count < 0:
        issues.append("Elite count cannot be negative")

    if elite_count >= population_size:
        issues.append("Elite count must be less than population size")

    if hidden_size <= 0:
        issues.append("Hidden size must be positive")

    if input_size <= 0 or output_size <= 0:
        issues.append("Input/output sizes must be positive")

    return issues


func copy_from(other: ConfigBase) -> void:
    ## Copy configuration from another instance
    load_from_dict(other.save_to_dict())


func print_summary() -> void:
    ## Print configuration summary
    print("=== Configuration: %s ===" % config_name)
    print("Population: %d (elite: %d)" % [population_size, elite_count])
    print("Network: %d -> %d -> %d" % [input_size, hidden_size, output_size])
    print("Evolution: mutation=%.2f (σ=%.2f), crossover=%.2f" %
        [mutation_rate, mutation_strength, crossover_rate])
    print("Training: %d generations, %d eps/eval" %
        [max_generations, episodes_per_eval])
    print("========================")