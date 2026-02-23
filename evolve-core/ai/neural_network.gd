extends RefCounted

## Core feedforward neural network with evolvable weights.
## Architecture: inputs -> hidden (tanh) -> outputs (tanh)
## This is the base implementation used across evolve projects.

var input_size: int
var hidden_size: int
var output_size: int

# Weight matrices (stored as flat arrays for easy mutation)
var weights_ih: PackedFloat32Array  # Input to hidden
var bias_h: PackedFloat32Array      # Hidden bias
var weights_ho: PackedFloat32Array  # Hidden to output
var bias_o: PackedFloat32Array      # Output bias

# Cached arrays for forward pass (avoid allocations)
var _hidden: PackedFloat32Array
var _output: PackedFloat32Array


func _init(
        p_input_size: int = 64,
        p_hidden_size: int = 32,
        p_output_size: int = 8,
        p_randomize: bool = true
    ) -> void:
    input_size = p_input_size
    hidden_size = p_hidden_size
    output_size = p_output_size

    # Initialize weight arrays
    weights_ih.resize(input_size * hidden_size)
    bias_h.resize(hidden_size)
    weights_ho.resize(hidden_size * output_size)
    bias_o.resize(output_size)

    # Cache arrays
    _hidden.resize(hidden_size)
    _output.resize(output_size)

    # Random initialization
    if p_randomize:
        randomize_weights()


func randomize_weights() -> void:
    ## Xavier-like initialization with configurable scale
    var ih_scale := sqrt(2.0 / input_size)
    var ho_scale := sqrt(2.0 / hidden_size)

    for i in weights_ih.size():
        weights_ih[i] = randf_range(-ih_scale, ih_scale)

    for i in bias_h.size():
        bias_h[i] = randf_range(-0.1, 0.1)

    for i in weights_ho.size():
        weights_ho[i] = randf_range(-ho_scale, ho_scale)

    for i in bias_o.size():
        bias_o[i] = randf_range(-0.1, 0.1)


func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
    ## Run forward pass through the network.
    ## Returns output array with values in [-1, 1] (tanh activation).
    assert(inputs.size() == input_size, "Input size mismatch")

    # Hidden layer: h = tanh(W_ih @ inputs + b_h)
    for h in hidden_size:
        var sum := bias_h[h]
        var weight_offset := h * input_size
        for i in input_size:
            sum += weights_ih[weight_offset + i] * inputs[i]
        _hidden[h] = tanh(sum)

    # Output layer: o = tanh(W_ho @ hidden + b_o)
    for o in output_size:
        var sum := bias_o[o]
        var weight_offset := o * hidden_size
        for h in hidden_size:
            sum += weights_ho[weight_offset + h] * _hidden[h]
        _output[o] = tanh(sum)

    return _output


func get_weights() -> PackedFloat32Array:
    ## Get all weights as a flat array for serialization/evolution
    var all_weights := PackedFloat32Array()
    all_weights.append_array(weights_ih)
    all_weights.append_array(bias_h)
    all_weights.append_array(weights_ho)
    all_weights.append_array(bias_o)
    return all_weights


func set_weights(weights: PackedFloat32Array) -> void:
    ## Set all weights from a flat array
    var idx := 0
    for i in weights_ih.size():
        weights_ih[i] = weights[idx]; idx += 1
    for i in bias_h.size():
        bias_h[i] = weights[idx]; idx += 1
    for i in weights_ho.size():
        weights_ho[i] = weights[idx]; idx += 1
    for i in bias_o.size():
        bias_o[i] = weights[idx]; idx += 1


func get_weight_count() -> int:
    return weights_ih.size() + bias_h.size() + weights_ho.size() + bias_o.size()


func clone():
    ## Create a deep copy of this network
    var copy = get_script().new(input_size, hidden_size, output_size, false)
    copy.weights_ih = weights_ih.duplicate()
    copy.bias_h = bias_h.duplicate()
    copy.weights_ho = weights_ho.duplicate()
    copy.bias_o = bias_o.duplicate()
    return copy


func mutate(mutation_rate: float = 0.1, mutation_strength: float = 0.3) -> void:
    ## Apply Gaussian mutation to weights
    _mutate_array(weights_ih, mutation_rate, mutation_strength)
    _mutate_array(bias_h, mutation_rate, mutation_strength)
    _mutate_array(weights_ho, mutation_rate, mutation_strength)
    _mutate_array(bias_o, mutation_rate, mutation_strength)


func _mutate_array(arr: PackedFloat32Array, mutation_rate: float, mutation_strength: float) -> void:
    ## Efficient geometric-skip mutation
    if mutation_rate <= 0.0 or arr.is_empty():
        return
    if mutation_rate >= 1.0:
        for i in arr.size():
            arr[i] += randfn(0.0, mutation_strength)
        return

    # Use geometric distribution to skip non-mutated elements efficiently
    var log1mp := log(1.0 - mutation_rate)
    var i := int(floor(log(maxf(randf(), 1e-15)) / log1mp))
    while i < arr.size():
        arr[i] += randfn(0.0, mutation_strength)
        i += 1 + int(floor(log(maxf(randf(), 1e-15)) / log1mp))


func crossover_with(other):
    ## Two-point crossover with another network
    assert(other.input_size == input_size and other.hidden_size == hidden_size and other.output_size == output_size,
        "Networks must have same architecture for crossover")

    var child = get_script().new(input_size, hidden_size, output_size, false)
    var total := get_weight_count()
    var p1 := randi() % total
    var p2 := randi() % total
    if p1 > p2:
        var tmp := p1; p1 = p2; p2 = tmp

    var offset := 0
    _crossover_segment(child.weights_ih, weights_ih, other.weights_ih, p1, p2, offset)
    offset += weights_ih.size()
    _crossover_segment(child.bias_h, bias_h, other.bias_h, p1, p2, offset)
    offset += bias_h.size()
    _crossover_segment(child.weights_ho, weights_ho, other.weights_ho, p1, p2, offset)
    offset += weights_ho.size()
    _crossover_segment(child.bias_o, bias_o, other.bias_o, p1, p2, offset)
    return child


func _crossover_segment(
        dst: PackedFloat32Array,
        a: PackedFloat32Array,
        b: PackedFloat32Array,
        p1: int, p2: int, offset: int
    ) -> void:
    for i in a.size():
        var gi := offset + i
        dst[i] = b[i] if (gi >= p1 and gi < p2) else a[i]


func save_to_dict() -> Dictionary:
    ## Serialize network to dictionary for saving
    return {
        "input_size": input_size,
        "hidden_size": hidden_size,
        "output_size": output_size,
        "weights": get_weights()
    }


func load_from_dict(data: Dictionary) -> void:
    ## Load network from dictionary
    assert(data.input_size == input_size and data.hidden_size == hidden_size and data.output_size == output_size,
        "Architecture mismatch in loaded data")
    set_weights(data.weights)