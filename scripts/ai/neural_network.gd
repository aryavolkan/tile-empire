extends RefCounted
class_name NeuralNetwork

## Tile Empire's neural network with evolvable weights and optional Elman recurrent memory.
## Architecture: inputs -> hidden (tanh) -> outputs (tanh)
## When use_memory is true, previous hidden state feeds back into hidden layer
## via context weights, enabling temporal sequence learning (Elman network).
##
## NOTE: This is intentionally a SEPARATE copy from evolve-core/ai/recurrent_network.gd.
## Reasons this local copy must stay:
## 1. Game-specific save/load: save_to_file/load_from_file with binary format + JSON NEAT genome loading
## 2. Custom weight initialization: sqrt(8.0/N) instead of sqrt(2.0/N) for sparse tile-empire inputs
## 3. crossover_with() uses two-point crossover tuned for this game
## 4. load_from_file references res://ai/neat_network.gd and res://ai/neat_genome.gd (game-specific)
## See evolve-core/ai/recurrent_network.gd for the generic reusable version.

var input_size: int
var hidden_size: int
var output_size: int

# Elman memory flag - when false, behaves as pure feedforward (backward compatible)
var use_memory: bool = false

# Weight matrices (stored as flat arrays for easy mutation)
var weights_ih: PackedFloat32Array  # Input to hidden
var bias_h: PackedFloat32Array      # Hidden bias
var weights_ho: PackedFloat32Array  # Hidden to output
var bias_o: PackedFloat32Array      # Output bias
var weights_hh: PackedFloat32Array  # Hidden to hidden (Elman context weights)

# Recurrent state
var _prev_hidden: PackedFloat32Array  # Previous hidden activation

# Cached arrays for forward pass (avoid allocations)
var _hidden: PackedFloat32Array
var _output: PackedFloat32Array


func _init(p_input_size: int = 64, p_hidden_size: int = 32, p_output_size: int = 8) -> void:
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

    # Random initialization (Xavier-like)
    randomize_weights()


func enable_memory() -> void:
    ## Enable Elman recurrent memory. Call after construction.
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


func randomize_weights() -> void:
    # Larger weights to produce meaningful outputs with sparse inputs
    # (only ~25% of sensor inputs are typically non-zero)
    var ih_scale := sqrt(8.0 / input_size)  # 4x larger than standard Xavier
    var ho_scale := sqrt(8.0 / hidden_size)

    for i in weights_ih.size():
        weights_ih[i] = randf_range(-ih_scale, ih_scale)

    for i in bias_h.size():
        bias_h[i] = randf_range(-0.5, 0.5)  # Non-zero bias for variety

    for i in weights_ho.size():
        weights_ho[i] = randf_range(-ho_scale, ho_scale)

    for i in bias_o.size():
        bias_o[i] = randf_range(-0.5, 0.5)  # Non-zero bias for variety


func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
    ## Run forward pass through the network.
    ## Returns output array with values in [-1, 1] (tanh activation).

    assert(inputs.size() == input_size, "Input size mismatch")

    # Hidden layer: h = tanh(W_ih @ inputs + W_hh @ prev_hidden + b_h)
    for h in hidden_size:
        var sum := bias_h[h]
        var weight_offset := h * input_size
        for i in input_size:
            sum += weights_ih[weight_offset + i] * inputs[i]
        # Add recurrent context if memory is enabled
        if use_memory:
            var ctx_offset := h * hidden_size
            for ph in hidden_size:
                sum += weights_hh[ctx_offset + ph] * _prev_hidden[ph]
        _hidden[h] = tanh(sum)

    # Store current hidden state for next timestep
    if use_memory:
        for h in hidden_size:
            _prev_hidden[h] = _hidden[h]

    # Output layer: o = tanh(W_ho @ hidden + b_o)
    for o in output_size:
        var sum := bias_o[o]
        var weight_offset := o * hidden_size
        for h in hidden_size:
            sum += weights_ho[weight_offset + h] * _hidden[h]
        _output[o] = tanh(sum)

    return _output


func get_weights() -> PackedFloat32Array:
    ## Return all weights as a flat array for evolution.
    ## When memory is enabled, context weights are appended after base weights.
    var all_weights := PackedFloat32Array()
    all_weights.append_array(weights_ih)
    all_weights.append_array(bias_h)
    all_weights.append_array(weights_ho)
    all_weights.append_array(bias_o)
    if use_memory:
        all_weights.append_array(weights_hh)
    return all_weights


func set_weights(weights: PackedFloat32Array) -> void:
    ## Set all weights from a flat array.
    var idx := 0

    for i in weights_ih.size():
        weights_ih[i] = weights[idx]
        idx += 1

    for i in bias_h.size():
        bias_h[i] = weights[idx]
        idx += 1

    for i in weights_ho.size():
        weights_ho[i] = weights[idx]
        idx += 1

    for i in bias_o.size():
        bias_o[i] = weights[idx]
        idx += 1

    if use_memory and idx < weights.size():
        for i in weights_hh.size():
            weights_hh[i] = weights[idx]
            idx += 1


func get_weight_count() -> int:
    ## Total number of trainable parameters.
    var count := weights_ih.size() + bias_h.size() + weights_ho.size() + bias_o.size()
    if use_memory:
        count += weights_hh.size()
    return count


func clone():
    ## Create a deep copy of this network.
    var script = get_script()
    var copy = script.new(input_size, hidden_size, output_size)
    if use_memory:
        copy.enable_memory()
    copy.set_weights(get_weights())
    return copy


func mutate(mutation_rate: float = 0.1, mutation_strength: float = 0.3) -> void:
    ## Apply Gaussian mutations to weights.
    ## mutation_rate: probability of mutating each weight
    ## mutation_strength: standard deviation of mutation noise

    for i in weights_ih.size():
        if randf() < mutation_rate:
            weights_ih[i] += randfn(0.0, mutation_strength)

    for i in bias_h.size():
        if randf() < mutation_rate:
            bias_h[i] += randfn(0.0, mutation_strength)

    for i in weights_ho.size():
        if randf() < mutation_rate:
            weights_ho[i] += randfn(0.0, mutation_strength)

    for i in bias_o.size():
        if randf() < mutation_rate:
            bias_o[i] += randfn(0.0, mutation_strength)

    if use_memory:
        for i in weights_hh.size():
            if randf() < mutation_rate:
                weights_hh[i] += randfn(0.0, mutation_strength)


func crossover_with(other):
    ## Create a child network by combining weights from two parents.
    ## Uses two-point crossover to preserve weight patterns from each parent.
    var script = get_script()
    var child = script.new(input_size, hidden_size, output_size)
    if use_memory:
        child.enable_memory()
    var weights_a: PackedFloat32Array = get_weights()
    var weights_b: PackedFloat32Array = other.get_weights()
    var child_weights := PackedFloat32Array()
    child_weights.resize(weights_a.size())

    # Two-point crossover: pick two random points and swap the middle segment
    var point1 := randi() % weights_a.size()
    var point2 := randi() % weights_a.size()
    if point1 > point2:
        var tmp := point1
        point1 = point2
        point2 = tmp

    for i in weights_a.size():
        if i >= point1 and i < point2:
            child_weights[i] = weights_b[i]
        else:
            child_weights[i] = weights_a[i]

    child.set_weights(child_weights)
    return child


func save_to_file(path: String) -> void:
    ## Save network to a file.
    ## Format: [in, hid, out, use_memory_flag, weight_count, weights...]
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_32(input_size)
        file.store_32(hidden_size)
        file.store_32(output_size)
        file.store_32(1 if use_memory else 0)
        var weights := get_weights()
        file.store_32(weights.size())
        for w in weights:
            file.store_float(w)
        file.close()


static func load_from_file(path: String):
    ## Load network from a file. Supports binary format, legacy binary, and
    ## JSON NEAT genome format (saved by rtNEAT/NEAT evolution).
    ## Falls back to res://models/<basename> for packaged .pck demos.
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        var fallback := "res://models/" + path.get_file()
        file = FileAccess.open(fallback, FileAccess.READ)
        if not file:
            return null

    # Detect JSON format by peeking at first byte
    var first_byte := file.get_8()
    file.seek(0)

    if first_byte == 0x7B:  # '{' — JSON NEAT genome
        var json_text := file.get_as_text()
        file.close()
        return _load_from_json(json_text)

    # Binary format
    var in_size := file.get_32()
    var hid_size := file.get_32()
    var out_size := file.get_32()

    # Sanity check sizes to catch corrupt files
    if in_size > 10000 or hid_size > 10000 or out_size > 10000:
        push_error("Network file appears corrupt (unreasonable sizes: in=%d hid=%d out=%d)" % [in_size, hid_size, out_size])
        file.close()
        return null

    # Format detection: 4th u32 is use_memory flag (0 or 1) or legacy weight_count (>1)
    var fourth := file.get_32()
    var has_memory: bool
    var weight_count: int

    if fourth > 1:
        # Legacy format: 4th field was weight_count directly
        has_memory = false
        weight_count = fourth
    else:
        # New format: 4th field is memory flag, 5th is weight_count
        has_memory = (fourth == 1)
        weight_count = file.get_32()

    # Sanity check weight count
    var max_expected: int = (in_size * hid_size + hid_size + hid_size * out_size + out_size + hid_size * hid_size) * 2
    if weight_count > max_expected or weight_count > 1000000:
        push_error("Network file appears corrupt (weight_count=%d, max_expected=%d)" % [weight_count, max_expected])
        file.close()
        return null

    var weights := PackedFloat32Array()
    weights.resize(weight_count)
    for i in weight_count:
        weights[i] = file.get_float()

    file.close()

    var script := load("res://ai/neural_network.gd")
    var network = script.new(in_size, hid_size, out_size)
    if has_memory:
        network.enable_memory()
    network.set_weights(weights)
    return network


static func _load_from_json(json_text: String):
    ## Load a NEAT genome from JSON and return a NeatNetwork for playback.
    var json := JSON.new()
    var err := json.parse(json_text)
    if err != OK:
        push_error("Failed to parse network JSON: " + json.get_error_message())
        return null

    var data: Dictionary = json.data
    if not data.has("connections") or not data.has("nodes"):
        push_error("JSON file missing 'connections' or 'nodes' — not a valid NEAT genome")
        return null

    # Build a NeatNetwork directly from the serialized data without needing
    # NeatConfig/NeatInnovation (which are only needed for evolution, not playback).
    var NeatNetworkScript = load("res://ai/neat_network.gd")
    var NeatGenomeScript = load("res://ai/neat_genome.gd")

    # Reconstruct a minimal genome for network building
    var genome = NeatGenomeScript.new()
    for node_data in data.get("nodes", []):
        var node = NeatGenomeScript.NodeGene.new(int(node_data.id), int(node_data.type))
        node.bias = float(node_data.bias)
        genome.node_genes.append(node)

    for conn_data in data.get("connections", []):
        var conn = NeatGenomeScript.ConnectionGene.new(
            int(conn_data["in"]),
            int(conn_data.out),
            float(conn_data.weight),
            int(conn_data.innovation),
        )
        conn.enabled = bool(conn_data.enabled)
        genome.connection_genes.append(conn)

    return NeatNetworkScript.from_genome(genome)
