extends RefCounted
class_name NeatGenome

## A NEAT genome: variable-topology neural network encoded as node and connection genes.
## Uses historical markings (innovation numbers) for crossover alignment.

# Inner classes for genes
class NodeGene:
    var id: int
    var type: int  # 0: input, 1: hidden, 2: output
    var bias: float = 0.0

    func _init(_id: int, _type: int):
        id = _id
        type = _type
        bias = randf_range(-1.0, 1.0)

    func copy() -> NodeGene:
        var new_node = NodeGene.new(id, type)
        new_node.bias = bias
        return new_node

class ConnectionGene:
    var in_id: int
    var out_id: int
    var weight: float
    var enabled: bool = true
    var innovation: int

    func _init(_in: int, _out: int, _weight: float, _innovation: int):
        in_id = _in
        out_id = _out
        weight = _weight
        innovation = _innovation

    func copy() -> ConnectionGene:
        var new_conn = ConnectionGene.new(in_id, out_id, weight, innovation)
        new_conn.enabled = enabled
        return new_conn

# Genome properties
var node_genes: Array = []
var connection_genes: Array = []
var fitness: float = 0.0
var adjusted_fitness: float = 0.0
var config: NeatConfig
var innovation_tracker: NeatInnovation


static func create(p_config: NeatConfig, p_tracker: NeatInnovation) -> NeatGenome:
    ## Factory: create a minimal genome with input + output nodes (no connections).
    var genome := NeatGenome.new()
    genome.config = p_config
    genome.innovation_tracker = p_tracker

    # Create input nodes
    for i in p_config.input_count:
        genome.node_genes.append(NodeGene.new(i, 0))

    # Create output nodes
    for i in p_config.output_count:
        genome.node_genes.append(NodeGene.new(p_config.input_count + i, 2))

    # Add bias node if configured
    if p_config.use_bias:
        genome.node_genes.append(NodeGene.new(p_config.input_count + p_config.output_count, 0))

    # Ensure innovation tracker knows about these node IDs
    var max_node_id: int = p_config.input_count + p_config.output_count + int(p_config.use_bias)
    while p_tracker.get_next_node_id() < max_node_id:
        p_tracker.allocate_node_id()

    return genome


func create_basic() -> void:
    ## Add connections from every input to every output (fully connected).
    var input_count: int = config.input_count + int(config.use_bias)
    for inp in range(input_count):
        for out in range(config.output_count):
            var out_idx: int = input_count + out
            if config.use_bias:
                out_idx = config.input_count + int(config.use_bias) + out
            else:
                out_idx = config.input_count + out
            var conn = ConnectionGene.new(
                node_genes[inp].id,
                node_genes[out_idx].id,
                randf_range(-2.0, 2.0),
                innovation_tracker.get_innovation(node_genes[inp].id, node_genes[out_idx].id)
            )
            connection_genes.append(conn)


# ============================================================
# TOPOLOGY MUTATIONS
# ============================================================

func mutate_add_connection() -> void:
    ## Add a new connection between two previously unconnected nodes.
    var possible_inputs = node_genes.filter(func(n): return n.type != 2)  # Not outputs
    var possible_outputs = node_genes.filter(func(n): return n.type != 0)  # Not inputs

    if possible_inputs.is_empty() or possible_outputs.is_empty():
        return

    # Try a few times to find a valid pair
    for _attempt in 10:
        var in_node = possible_inputs[randi() % possible_inputs.size()]
        var out_node = possible_outputs[randi() % possible_outputs.size()]

        # Skip self-connections
        if in_node.id == out_node.id:
            continue

        # Skip if connection already exists
        if connection_genes.any(func(c): return c.in_id == in_node.id and c.out_id == out_node.id):
            continue

        # Avoid recurrent connections if not allowed
        if not config.allow_recurrent and _would_create_cycle(in_node.id, out_node.id):
            continue

        var new_conn = ConnectionGene.new(
            in_node.id,
            out_node.id,
            randf_range(-2.0, 2.0),
            innovation_tracker.get_innovation(in_node.id, out_node.id)
        )
        connection_genes.append(new_conn)
        return


func mutate_add_node() -> void:
    ## Split an existing connection with a new hidden node.
    var enabled_conns = connection_genes.filter(func(c): return c.enabled)
    if enabled_conns.is_empty():
        return

    var conn = enabled_conns[randi() % enabled_conns.size()]
    conn.enabled = false

    var new_node_id: int = innovation_tracker.allocate_node_id()
    var new_node = NodeGene.new(new_node_id, 1)  # Hidden
    node_genes.append(new_node)

    # in → new_node with weight 1.0 (preserves signal)
    var conn1 = ConnectionGene.new(
        conn.in_id,
        new_node_id,
        1.0,
        innovation_tracker.get_innovation(conn.in_id, new_node_id)
    )
    # new_node → out with original weight (preserves behavior)
    var conn2 = ConnectionGene.new(
        new_node_id,
        conn.out_id,
        conn.weight,
        innovation_tracker.get_innovation(new_node_id, conn.out_id)
    )
    connection_genes.append(conn1)
    connection_genes.append(conn2)


func mutate_weights() -> void:
    ## Mutate connection weights: perturb or reset.
    for conn in connection_genes:
        if randf() < config.weight_mutate_rate:
            if randf() < config.weight_perturb_rate:
                # Perturb: add gaussian noise
                conn.weight += _randn() * config.weight_perturb_strength
            else:
                # Reset: random new weight
                conn.weight = randf_range(-config.weight_reset_range, config.weight_reset_range)


func mutate_disable_connection() -> void:
    ## Randomly disable one enabled connection.
    var enabled_conns = connection_genes.filter(func(c): return c.enabled)
    if enabled_conns.is_empty():
        return
    enabled_conns[randi() % enabled_conns.size()].enabled = false


func mutate(p_config: NeatConfig) -> void:
    ## Apply all mutation operators according to configured rates.
    if randf() < p_config.weight_mutate_rate:
        mutate_weights()
    if randf() < p_config.add_connection_rate:
        mutate_add_connection()
    if randf() < p_config.add_node_rate:
        mutate_add_node()
    if randf() < p_config.disable_connection_rate:
        mutate_disable_connection()


# ============================================================
# COMPATIBILITY DISTANCE (for speciation)
# ============================================================

func compatibility(other: NeatGenome, p_config: NeatConfig) -> float:
    ## Compute compatibility distance between this genome and another.
    ## Used to group genomes into species.
    ## Formula: d = (c1 * E / N) + (c2 * D / N) + (c3 * W)
    ## where E=excess, D=disjoint, W=avg weight diff, N=normalizing gene count.
    ##
    ## Optimized: builds innovation→weight maps without sorting, avoids
    ## third "all_innovations" dict by iterating each map once.
    var genes_a := connection_genes
    var genes_b := other.connection_genes

    if genes_a.is_empty() and genes_b.is_empty():
        return 0.0

    # Build innovation → weight maps (no sorting needed)
    var map_a: Dictionary = {}
    var max_innov_a: int = 0
    for g in genes_a:
        map_a[g.innovation] = g.weight
        if g.innovation > max_innov_a:
            max_innov_a = g.innovation

    var map_b: Dictionary = {}
    var max_innov_b: int = 0
    for g in genes_b:
        map_b[g.innovation] = g.weight
        if g.innovation > max_innov_b:
            max_innov_b = g.innovation

    var smaller_max: int = mini(max_innov_a, max_innov_b)

    var excess: int = 0
    var disjoint: int = 0
    var weight_diff_sum: float = 0.0
    var matching_count: int = 0

    # Iterate map_a: check for matching or disjoint/excess vs map_b
    for innov in map_a:
        if map_b.has(innov):
            weight_diff_sum += absf(map_a[innov] - map_b[innov])
            matching_count += 1
        elif innov > smaller_max:
            excess += 1
        else:
            disjoint += 1

    # Iterate map_b: only count genes NOT in map_a (skip matching, already counted)
    for innov in map_b:
        if not map_a.has(innov):
            if innov > smaller_max:
                excess += 1
            else:
                disjoint += 1

    # Normalizing factor N (use 1 if both genomes are small)
    var n: float = maxf(genes_a.size(), genes_b.size())
    if n < 20:
        n = 1.0

    var avg_weight_diff: float = weight_diff_sum / matching_count if matching_count > 0 else 0.0

    return (p_config.c1_excess * excess / n) + \
        (p_config.c2_disjoint * disjoint / n) + \
        (p_config.c3_weight_diff * avg_weight_diff)


# ============================================================
# CROSSOVER
# ============================================================

static func crossover(parent_a: NeatGenome, parent_b: NeatGenome) -> NeatGenome:
    ## NEAT crossover: align genes by innovation number.
    ## Matching genes inherited randomly from either parent.
    ## Disjoint/excess genes inherited from the fitter parent.
    ## If equal fitness, inherit disjoint/excess from both.
    var child := NeatGenome.new()
    child.config = parent_a.config
    child.innovation_tracker = parent_a.innovation_tracker

    # Ensure parent_a is the fitter (or equal) parent
    var a := parent_a
    var b := parent_b
    if b.fitness > a.fitness:
        a = parent_b
        b = parent_a

    var equal_fitness: bool = absf(a.fitness - b.fitness) < 0.001

    # Build innovation → connection maps
    var map_a: Dictionary = {}
    for conn in a.connection_genes:
        map_a[conn.innovation] = conn
    var map_b: Dictionary = {}
    for conn in b.connection_genes:
        map_b[conn.innovation] = conn

    # Collect all innovation numbers
    var all_innovs: Dictionary = {}
    for key in map_a:
        all_innovs[key] = true
    for key in map_b:
        all_innovs[key] = true

    # Inherit connection genes
    var child_conns: Array = []
    for innov in all_innovs:
        var in_a: bool = map_a.has(innov)
        var in_b: bool = map_b.has(innov)

        if in_a and in_b:
            # Matching gene: randomly pick from either parent
            var source = map_a[innov] if randf() < 0.5 else map_b[innov]
            var gene_copy = source.copy()
            # If disabled in either parent, chance it stays disabled
            if not map_a[innov].enabled or not map_b[innov].enabled:
                gene_copy.enabled = randf() >= a.config.disabled_gene_inherit_rate
            child_conns.append(gene_copy)
        elif in_a:
            # Disjoint/excess from fitter parent — always inherit
            child_conns.append(map_a[innov].copy())
        elif in_b and equal_fitness:
            # Disjoint/excess from other parent — only if equal fitness
            child_conns.append(map_b[innov].copy())
        # else: disjoint/excess from less fit parent — skip

    child.connection_genes = child_conns

    # Inherit node genes: collect all node IDs referenced by child connections,
    # plus all input/output nodes from the fitter parent
    var needed_node_ids: Dictionary = {}
    for node in a.node_genes:
        if node.type == 0 or node.type == 2:  # input or output
            needed_node_ids[node.id] = true
    for conn in child_conns:
        needed_node_ids[conn.in_id] = true
        needed_node_ids[conn.out_id] = true

    # Build node maps from both parents
    var node_map_a: Dictionary = {}
    for node in a.node_genes:
        node_map_a[node.id] = node
    var node_map_b: Dictionary = {}
    for node in b.node_genes:
        node_map_b[node.id] = node

    var child_nodes: Array = []
    for node_id in needed_node_ids:
        if node_map_a.has(node_id):
            child_nodes.append(node_map_a[node_id].copy())
        elif node_map_b.has(node_id):
            child_nodes.append(node_map_b[node_id].copy())

    # Sort nodes: inputs first, then hidden, then outputs
    child_nodes.sort_custom(func(x, y):
        if x.type != y.type:
            return x.type < y.type
        return x.id < y.id
    )
    child.node_genes = child_nodes

    return child


# ============================================================
# COPY
# ============================================================

func copy() -> NeatGenome:
    ## Deep copy this genome. Shares config and innovation_tracker references.
    var new_genome := NeatGenome.new()
    new_genome.config = config
    new_genome.innovation_tracker = innovation_tracker
    new_genome.node_genes = node_genes.map(func(n): return n.copy())
    new_genome.connection_genes = connection_genes.map(func(c): return c.copy())
    new_genome.fitness = fitness
    new_genome.adjusted_fitness = adjusted_fitness
    return new_genome


# ============================================================
# HELPERS
# ============================================================

func _would_create_cycle(from_id: int, to_id: int) -> bool:
    ## Check if adding from_id → to_id would create a cycle.
    ## Uses DFS from to_id to see if we can reach from_id.
    var visited: Dictionary = {}
    var stack: Array[int] = [to_id]
    while not stack.is_empty():
        var current: int = stack.pop_back()
        if current == from_id:
            return true
        if visited.has(current):
            continue
        visited[current] = true
        for conn in connection_genes:
            if conn.enabled and conn.in_id == current:
                stack.append(conn.out_id)
    return false


func get_max_node_id() -> int:
    ## Get the highest node ID in this genome.
    var max_id: int = 0
    for node in node_genes:
        max_id = maxi(max_id, node.id)
    return max_id


func get_enabled_connection_count() -> int:
    ## Count enabled connections (for parsimony pressure).
    var count: int = 0
    for conn in connection_genes:
        if conn.enabled:
            count += 1
    return count


# ============================================================
# SERIALIZATION
# ============================================================

func serialize() -> Dictionary:
    ## Serialize genome to a JSON-compatible dictionary.
    var nodes: Array = []
    for node in node_genes:
        nodes.append({"id": node.id, "type": node.type, "bias": node.bias})
    var connections: Array = []
    for conn in connection_genes:
        connections.append({
            "in": conn.in_id,
            "out": conn.out_id,
            "weight": conn.weight,
            "enabled": conn.enabled,
            "innovation": conn.innovation,
        })
    return {"nodes": nodes, "connections": connections, "fitness": fitness}


static func deserialize(data: Dictionary, p_config: NeatConfig, p_tracker: NeatInnovation) -> NeatGenome:
    ## Reconstruct a genome from a serialized dictionary.
    var genome := NeatGenome.new()
    genome.config = p_config
    genome.innovation_tracker = p_tracker

    for node_data in data.get("nodes", []):
        var node := NodeGene.new(int(node_data.id), int(node_data.type))
        node.bias = float(node_data.bias)
        genome.node_genes.append(node)

    for conn_data in data.get("connections", []):
        var conn := ConnectionGene.new(
            int(conn_data["in"]),
            int(conn_data.out),
            float(conn_data.weight),
            int(conn_data.innovation),
        )
        conn.enabled = bool(conn_data.enabled)
        genome.connection_genes.append(conn)

    genome.fitness = float(data.get("fitness", 0.0))
    return genome


static func _randn() -> float:
    ## Approximate standard normal using Box-Muller.
    var u1 := randf()
    var u2 := randf()
    if u1 < 0.0001:
        u1 = 0.0001
    return sqrt(-2.0 * log(u1)) * cos(TAU * u2)
