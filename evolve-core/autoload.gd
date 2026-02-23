extends Node

## Evolve Core Autoload
## Registers shared components and provides convenient access

const VERSION = "1.0.0"

# Preload commonly used classes
const NeuralNetwork = preload("res://evolve-core/ai/neural_network.gd")
const RecurrentNetwork = preload("res://evolve-core/ai/recurrent_network.gd")
const NetworkFactoryClass = preload("res://evolve-core/ai/network_factory.gd")
const EvolutionBaseClass = preload("res://evolve-core/genetic/evolution_base.gd")
const GeneticOperatorsClass = preload("res://evolve-core/genetic/operators.gd")
const StatsTrackerClass = preload("res://evolve-core/utils/stats_tracker.gd")
const ConfigBaseClass = preload("res://evolve-core/utils/config_base.gd")

# Interfaces
const IAgentClass = preload("res://evolve-core/interfaces/agent.gd")
const ISensorClass = preload("res://evolve-core/interfaces/sensor.gd")
const IRewardClass = preload("res://evolve-core/interfaces/reward.gd")


func _ready() -> void:
    print("[EvolveCore] v%s initialized" % VERSION)


func create_network(input_size: int, hidden_size: int, output_size: int, use_memory: bool = false):
    ## Convenience method to create a neural network
    return NetworkFactory.create(input_size, hidden_size, output_size, use_memory)


func create_stats_tracker(window_size: int = 100) -> StatsTracker:
    ## Create a new statistics tracker
    return StatsTracker.new(window_size)

func create_config(new_name: String = "default") -> ConfigBaseClass:
    ## Create a new configuration
    return ConfigBaseClass.new(new_name)
