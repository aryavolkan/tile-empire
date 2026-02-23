class_name NetworkFactory
extends RefCounted

## Factory for creating neural networks with Rust acceleration support.
## Automatically uses accelerated implementations when available.

static var _rust_available: bool = false
static var _rust_checked: bool = false


static func create(
        input_size: int,
        hidden_size: int,
        output_size: int,
        use_memory: bool = false
    ):
    ## Create a neural network, using Rust implementation if available
    _check_rust_availability()

    if _rust_available and ClassDB.class_exists(&"RustNeuralNetwork"):
        var rust_net = ClassDB.instantiate(&"RustNeuralNetwork")
        if rust_net:
            rust_net.initialize(input_size, hidden_size, output_size)
            if use_memory:
                # Check if Rust network supports memory
                if rust_net.has_method("enable_memory"):
                    rust_net.enable_memory()
                else:
                    push_warning("RustNeuralNetwork doesn't support memory, falling back to GDScript")
                    return _create_gdscript_network(input_size, hidden_size, output_size, use_memory)
            return rust_net

    # Fallback to GDScript
    return _create_gdscript_network(input_size, hidden_size, output_size, use_memory)


static func _create_gdscript_network(
        input_size: int,
        hidden_size: int,
        output_size: int,
        use_memory: bool
    ):
    if use_memory:
        var RecurrentNet = preload("res://evolve-core/ai/recurrent_network.gd")
        return RecurrentNet.new(input_size, hidden_size, output_size, true, true)
    else:
        var NeuralNet = preload("res://evolve-core/ai/neural_network.gd")
        return NeuralNet.new(input_size, hidden_size, output_size, true)


static func _check_rust_availability() -> void:
    if _rust_checked:
        return

    _rust_checked = true
    _rust_available = ClassDB.class_exists(&"RustNeuralNetwork")

    if _rust_available:
        print("[NetworkFactory] ✓ Rust neural networks available for acceleration")
    else:
        print("[NetworkFactory] ℹ Using GDScript neural networks")


static func enable_memory(network) -> void:
    ## Enable memory on a network if supported
    if network.has_method("enable_memory"):
        network.enable_memory()
    else:
        push_error("Network doesn't support memory: " + str(network))


static func clone_network(network):
    ## Clone a network, preserving Rust/GDScript implementation
    if network.has_method("clone"):
        return network.clone()
    else:
        push_error("Network doesn't support cloning: " + str(network))
        return null