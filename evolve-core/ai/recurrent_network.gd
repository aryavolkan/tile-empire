extends "res://evolve-core/ai/neural_network.gd"

## Recurrent neural network with Elman-style memory.
## Extends the base neural network with temporal sequence learning capabilities.
## When enabled, previous hidden state feeds back into hidden layer.

var use_memory: bool = false
var weights_hh: PackedFloat32Array  # Hidden to hidden (context weights)
var _prev_hidden: PackedFloat32Array  # Previous hidden activation


func _init(
        p_input_size: int = 64,
        p_hidden_size: int = 32,
        p_output_size: int = 8,
        p_randomize: bool = true,
        p_use_memory: bool = false
    ) -> void:
    super._init(p_input_size, p_hidden_size, p_output_size, p_randomize)

    if p_use_memory:
        enable_memory()


func enable_memory() -> void:
    ## Enable Elman recurrent memory.
    ## Allocates context weights (hidden_size x hidden_size) and hidden state buffer.
    if use_memory:
        return

    use_memory = true
    weights_hh.resize(hidden_size * hidden_size)
    _prev_hidden.resize(hidden_size)
    _prev_hidden.fill(0.0)

    # Initialize context weights with smaller scale to avoid instability
    var hh_scale := sqrt(2.0 / hidden_size)
    for i in weights_hh.size():
        weights_hh[i] = randf_range(-hh_scale, hh_scale)


func reset_memory() -> void:
    ## Reset recurrent state to zeros. Call between episodes/evaluations.
    if use_memory:
        _prev_hidden.fill(0.0)


func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
    ## Run forward pass through the network with optional recurrent connections.
    assert(inputs.size() == input_size, "Input size mismatch")

    # Hidden layer: h = tanh(W_ih @ inputs + W_hh @ prev_hidden + b_h)
    for h in hidden_size:
        var sum := bias_h[h]
        var weight_offset := h * input_size

        # Input connections
        for i in input_size:
            sum += weights_ih[weight_offset + i] * inputs[i]

        # Recurrent connections (if enabled)
        if use_memory:
            var hh_offset := h * hidden_size
            for prev_h in hidden_size:
                sum += weights_hh[hh_offset + prev_h] * _prev_hidden[prev_h]

        _hidden[h] = tanh(sum)

    # Store hidden state for next timestep
    if use_memory:
        _prev_hidden = _hidden.duplicate()

    # Output layer (same as base class)
    for o in output_size:
        var sum := bias_o[o]
        var weight_offset := o * hidden_size
        for h in hidden_size:
            sum += weights_ho[weight_offset + h] * _hidden[h]
        _output[o] = tanh(sum)

    return _output


func get_weights() -> PackedFloat32Array:
    ## Get all weights including recurrent weights if enabled
    var all_weights := super.get_weights()
    if use_memory:
        all_weights.append_array(weights_hh)
    return all_weights


func set_weights(weights: PackedFloat32Array) -> void:
    ## Set all weights including recurrent weights if enabled
    var base_count := super.get_weight_count()
    var base_weights := weights.slice(0, base_count)
    super.set_weights(base_weights)

    if use_memory and weights.size() > base_count:
        var idx := base_count
        for i in weights_hh.size():
            weights_hh[i] = weights[idx]
            idx += 1


func get_weight_count() -> int:
    var count := super.get_weight_count()
    if use_memory:
        count += weights_hh.size()
    return count


func clone():
    ## Create a deep copy including memory state
    var copy = get_script().new(input_size, hidden_size, output_size, false, use_memory)
    copy.weights_ih = weights_ih.duplicate()
    copy.bias_h = bias_h.duplicate()
    copy.weights_ho = weights_ho.duplicate()
    copy.bias_o = bias_o.duplicate()

    if use_memory:
        copy.weights_hh = weights_hh.duplicate()
        copy._prev_hidden = _prev_hidden.duplicate()

    return copy


func mutate(mutation_rate: float = 0.1, mutation_strength: float = 0.3) -> void:
    super.mutate(mutation_rate, mutation_strength)
    if use_memory:
        _mutate_array(weights_hh, mutation_rate, mutation_strength)


func save_to_dict() -> Dictionary:
    var data := super.save_to_dict()
    data["use_memory"] = use_memory
    if use_memory:
        data["memory_weights"] = weights_hh
        data["memory_state"] = _prev_hidden
    return data


func load_from_dict(data: Dictionary) -> void:
    super.load_from_dict(data)
    if data.has("use_memory") and data.use_memory:
        if not use_memory:
            enable_memory()
        weights_hh = data.memory_weights
        if data.has("memory_state"):
            _prev_hidden = data.memory_state