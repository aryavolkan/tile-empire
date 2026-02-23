extends RefCounted
class_name NeatNetwork

## Phenotype network built from a NeatGenome.
## Performs a forward pass through a variable-topology network
## by computing nodes in topological order.

var _node_order: PackedInt32Array  ## Topologically sorted node IDs (input → hidden → output)
var _input_ids: PackedInt32Array
var _output_ids: PackedInt32Array
var _biases: Dictionary = {}  ## node_id → bias
var _connections: Array = []  ## [{in_id, out_id, weight}] — only enabled connections
var _activations: Dictionary = {}  ## node_id → current activation value

# Precomputed adjacency: node_id → Array of {in_id: int, weight: float}
# Avoids O(connections) scan per node in forward pass.
var _incoming: Dictionary = {}  ## node_id → [{in_id, weight}]
var _is_input: Dictionary = {}  ## node_id → true (for fast skip in forward)

# Cached output array (avoid allocation per forward call)
var _cached_outputs: PackedFloat32Array


static func from_genome(genome: NeatGenome) -> NeatNetwork:
    ## Build a phenotype network from a genome.
    var net := NeatNetwork.new()

    # Collect node IDs by type
    for node in genome.node_genes:
        net._biases[node.id] = node.bias
        net._incoming[node.id] = []
        if node.type == 0:
            net._input_ids.append(node.id)
            net._is_input[node.id] = true
        elif node.type == 2:
            net._output_ids.append(node.id)

    # Collect enabled connections and build adjacency lists
    for conn in genome.connection_genes:
        if conn.enabled:
            net._connections.append({
                "in_id": conn.in_id,
                "out_id": conn.out_id,
                "weight": conn.weight,
            })
            # Build incoming adjacency for O(1) lookup per node
            if net._incoming.has(conn.out_id):
                net._incoming[conn.out_id].append({"in_id": conn.in_id, "weight": conn.weight})

    # Topological sort
    net._node_order = net._topological_sort(genome)

    # Initialize activations
    for node in genome.node_genes:
        net._activations[node.id] = 0.0

    # Pre-allocate output array
    net._cached_outputs.resize(net._output_ids.size())

    return net


func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
    ## Feed inputs through the network and return outputs.
    ## Inputs must match the number of input nodes.

    # Set input activations (no activation function on inputs)
    for i in _input_ids.size():
        if i < inputs.size():
            _activations[_input_ids[i]] = inputs[i]
        else:
            _activations[_input_ids[i]] = 0.0

    # Process nodes in topological order (skip inputs, they're already set)
    for node_id in _node_order:
        if _is_input.has(node_id):
            continue

        # Sum weighted inputs + bias using precomputed adjacency
        var sum: float = _biases.get(node_id, 0.0)
        var incoming: Array = _incoming.get(node_id, [])
        for edge in incoming:
            sum += _activations.get(edge.in_id, 0.0) * edge.weight

        # tanh activation for hidden and output nodes
        _activations[node_id] = tanh(sum)

    # Collect outputs into cached array
    for i in _output_ids.size():
        _cached_outputs[i] = _activations.get(_output_ids[i], 0.0)

    return _cached_outputs


func get_input_count() -> int:
    return _input_ids.size()


func get_output_count() -> int:
    return _output_ids.size()


func get_node_count() -> int:
    return _node_order.size()


func get_connection_count() -> int:
    return _connections.size()


func reset() -> void:
    ## Clear all activations (useful between episodes).
    for key in _activations:
        _activations[key] = 0.0


func _topological_sort(genome: NeatGenome) -> PackedInt32Array:
    ## Kahn's algorithm for topological ordering.
    ## Falls back to type-based ordering if cycles exist (recurrent networks).

    # Build adjacency and in-degree from enabled connections
    var in_degree: Dictionary = {}
    var adjacency: Dictionary = {}  # node_id → [downstream_ids]

    for node in genome.node_genes:
        in_degree[node.id] = 0
        adjacency[node.id] = []

    for conn in genome.connection_genes:
        if not conn.enabled:
            continue
        if not in_degree.has(conn.out_id):
            continue
        in_degree[conn.out_id] = in_degree.get(conn.out_id, 0) + 1
        adjacency[conn.in_id].append(conn.out_id)

    # Start with nodes that have no incoming edges
    var queue: Array[int] = []
    var queue_head: int = 0  # Use index instead of pop_front to avoid O(n) shift
    for node_id in in_degree:
        if in_degree[node_id] == 0:
            queue.append(node_id)

    var order := PackedInt32Array()
    while queue_head < queue.size():
        var node_id: int = queue[queue_head]
        queue_head += 1
        order.append(node_id)
        for downstream in adjacency.get(node_id, []):
            in_degree[downstream] -= 1
            if in_degree[downstream] == 0:
                queue.append(downstream)

    # If not all nodes were sorted (cycle), fall back to type-based order
    if order.size() < genome.node_genes.size():
        order = PackedInt32Array()
        # Inputs first, then hidden, then outputs
        for node in genome.node_genes:
            if node.type == 0:
                order.append(node.id)
        for node in genome.node_genes:
            if node.type == 1:
                order.append(node.id)
        for node in genome.node_genes:
            if node.type == 2:
                order.append(node.id)

    return order
