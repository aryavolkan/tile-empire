class_name IAgent
extends RefCounted

## Interface for AI agents.
## Defines the contract that all agents must implement.

func get_action(observations: PackedFloat32Array):
    ## Given observations, return an action
    push_error("get_action() must be implemented by agent")
    return null


func reset() -> void:
    ## Reset agent state for new episode
    pass


func get_network():
    ## Get the underlying neural network (if applicable)
    push_error("get_network() not implemented")
    return null


func set_network(network) -> void:
    ## Set the neural network (if applicable)
    push_error("set_network() not implemented")


func clone():
    ## Create a copy of this agent
    push_error("clone() must be implemented by agent")
    return null