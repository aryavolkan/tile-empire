extends RefCounted
class_name NeatConfig

## All NEAT hyperparameters in one place for easy tuning.

# ============================================================
# NETWORK ARCHITECTURE
# ============================================================

var input_count: int = 86    ## From sensor.gd TOTAL_INPUTS
var output_count: int = 6     ## move_x, move_y, shoot_up/down/left/right
var use_bias: bool = false    ## Add a bias node to inputs
var allow_recurrent: bool = false  ## Allow recurrent (backward) connections

# ============================================================
# COMPATIBILITY / SPECIATION
# ============================================================

var compatibility_threshold: float = 3.0
var c1_excess: float = 1.0           ## Weight for excess genes
var c2_disjoint: float = 1.0         ## Weight for disjoint genes
var c3_weight_diff: float = 0.4      ## Weight for avg weight difference
var target_species_count: int = 8    ## Dynamic threshold adjusts toward this
var threshold_step: float = 0.3      ## How much to adjust threshold per generation

# ============================================================
# MUTATION RATES
# ============================================================

var weight_mutate_rate: float = 0.8        ## Chance to mutate weights at all
var weight_perturb_rate: float = 0.9       ## Of mutated: perturb vs full reset
var weight_perturb_strength: float = 0.3   ## Gaussian stddev for perturbation
var weight_reset_range: float = 2.0        ## Range for full weight reset [-r, r]
var add_node_rate: float = 0.03
var add_connection_rate: float = 0.05
var disable_connection_rate: float = 0.01

# ============================================================
# REPRODUCTION
# ============================================================

var population_size: int = 200
var elite_fraction: float = 0.1          ## Top fraction kept unchanged per species
var survival_fraction: float = 0.5       ## Only top fraction reproduces
var interspecies_crossover_rate: float = 0.001
var crossover_rate: float = 0.75         ## Probability of crossover vs cloning
var disabled_gene_inherit_rate: float = 0.75  ## Chance disabled gene stays disabled in child

# ============================================================
# STAGNATION
# ============================================================

var stagnation_threshold: int = 15   ## Gens without improvement → penalize
var stagnation_kill_threshold: int = 25  ## Hard kill (except top 2 species)
var min_species_protected: int = 2   ## Never kill these many top species

# ============================================================
# INITIAL POPULATION
# ============================================================

var initial_connection_fraction: float = 0.3  ## Fraction of input→output connections in initial genomes

# ============================================================
# PARSIMONY (optional complexity penalty)
# ============================================================

var parsimony_coefficient: float = 0.0  ## Fitness penalty per enabled connection (0 = off)


func _init() -> void:
    pass


func duplicate() -> NeatConfig:
    ## Create a copy of this config.
    var copy := NeatConfig.new()
    copy.input_count = input_count
    copy.output_count = output_count
    copy.use_bias = use_bias
    copy.allow_recurrent = allow_recurrent
    copy.compatibility_threshold = compatibility_threshold
    copy.c1_excess = c1_excess
    copy.c2_disjoint = c2_disjoint
    copy.c3_weight_diff = c3_weight_diff
    copy.target_species_count = target_species_count
    copy.threshold_step = threshold_step
    copy.weight_mutate_rate = weight_mutate_rate
    copy.weight_perturb_rate = weight_perturb_rate
    copy.weight_perturb_strength = weight_perturb_strength
    copy.weight_reset_range = weight_reset_range
    copy.add_node_rate = add_node_rate
    copy.add_connection_rate = add_connection_rate
    copy.disable_connection_rate = disable_connection_rate
    copy.population_size = population_size
    copy.elite_fraction = elite_fraction
    copy.survival_fraction = survival_fraction
    copy.interspecies_crossover_rate = interspecies_crossover_rate
    copy.crossover_rate = crossover_rate
    copy.disabled_gene_inherit_rate = disabled_gene_inherit_rate
    copy.stagnation_threshold = stagnation_threshold
    copy.stagnation_kill_threshold = stagnation_kill_threshold
    copy.min_species_protected = min_species_protected
    copy.initial_connection_fraction = initial_connection_fraction
    copy.parsimony_coefficient = parsimony_coefficient
    return copy
