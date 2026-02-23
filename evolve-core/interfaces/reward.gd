class_name IReward
extends RefCounted

## Interface for reward/fitness calculation.
## Can be used for both single-objective and multi-objective optimization.

func calculate_reward(agent_data: Dictionary) -> float:
    ## Calculate single reward value
    ## agent_data contains relevant metrics (score, time, actions, etc.)
    push_error("calculate_reward() must be implemented")
    return 0.0


func calculate_rewards(agent_data: Dictionary) -> Variant:
    ## Calculate multiple reward values for multi-objective optimization
    ## Returns float for single objective, Array/Vector for multi-objective
    return calculate_reward(agent_data)


func get_reward_names() -> PackedStringArray:
    ## Return names of reward components for multi-objective
    return PackedStringArray(["fitness"])


func is_multi_objective() -> bool:
    ## Whether this uses multiple objectives
    return false


func combine_rewards(rewards: Variant) -> float:
    ## Combine multiple rewards into single fitness (for sorting)
    if rewards is float:
        return rewards
    elif rewards is Array:
        var total := 0.0
        for r in rewards:
            total += float(r)
        return total
    else:
        return float(rewards)