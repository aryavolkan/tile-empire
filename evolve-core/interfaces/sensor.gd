class_name ISensor
extends RefCounted

## Interface for sensors that provide observations to agents.
## Sensors convert game state into numerical arrays for neural networks.

func get_observation_size() -> int:
    ## Return the size of the observation vector this sensor produces
    push_error("get_observation_size() must be implemented by sensor")
    return 0


func get_observation() -> PackedFloat32Array:
    ## Get current observation from the environment
    push_error("get_observation() must be implemented by sensor")
    return PackedFloat32Array()


func reset() -> void:
    ## Reset sensor state
    pass


func get_observation_labels() -> PackedStringArray:
    ## Optional: Return human-readable labels for each observation element
    ## Useful for debugging and visualization
    return PackedStringArray()


func get_observation_ranges() -> Array:
    ## Optional: Return expected ranges for each observation element
    ## Format: [[min, max], [min, max], ...]
    ## Useful for normalization and debugging
    return []