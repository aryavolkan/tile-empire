# Training Guide

## Prerequisites

1. **Godot 4.2+** — for running episodes headlessly
2. **Rust toolchain** (stable) — to build the native GDExtension
3. **Python 3.10+** — for the overnight training harness
4. **Weights & Biases account** — for sweep tracking (optional)

### Build the Rust extension
```bash
cd rust/tile-empire-native
cargo build --release
# Copies .so/.dylib to res://bin/ automatically via build.rs
```

---

## Running a Single Training Session

### Headless (auto-train)
```bash
godot --headless --path . -- --auto-train
```

With a sweep config:
```bash
# Write sweep_config.json to the Godot user:// directory first
# Linux: ~/.local/share/godot/app_userdata/tile-empire/
# macOS: ~/Library/Application Support/Godot/app_userdata/tile-empire/
cp my_config.json ~/.local/share/godot/app_userdata/tile-empire/sweep_config.json
godot --headless --path . -- --auto-train
```

### With UI
```bash
godot --path .
```
Displays live settlement boards and a training dashboard.

---

## sweep_config.json Reference

All keys are optional; defaults are used when missing.

```json
{
  "population_size":    50,       // Number of genomes per generation
  "max_generations":    100,      // Stop after this many generations
  "eval_episodes":      2,        // Episodes per genome per generation
  "max_episode_ticks":  3000,     // Episode length (3000 = ~50s at 60fps)
  "action_interval":    30,       // Ticks between AI decisions (30 = ~0.5s)
  "map_size":          "small",   // "small" | "medium" | "large"
  "cpu_difficulty":    "easy",    // "easy" | "medium" | "hard"
  "enable_cpu_opponents": true,

  "elite_count":        5,        // Elites preserved unchanged
  "territory_weight":   0.4,      // Fitness weight for territory objective
  "progression_weight": 0.4,      // Fitness weight for progression objective
  "survival_weight":    0.2,      // Fitness weight for survival objective

  "compatibility_threshold": 3.0, // NEAT species distance threshold
  "c1":  1.0,                     // Excess gene coefficient
  "c2":  1.0,                     // Disjoint gene coefficient
  "c3":  0.4,                     // Weight difference coefficient
  "weight_mutation_rate":   0.8,  // Fraction of connections mutated
  "weight_mutation_power":  1.5,  // Max perturbation magnitude
  "add_node_rate":          0.03, // Probability of adding a hidden node
  "add_connection_rate":    0.05, // Probability of adding a connection
  "survival_threshold":     0.2   // Fraction of each species kept
}
```

---

## Episode Lifecycle

```
1. Reset game state
   ├── New map (size from config, seeded)
   ├── Spawn AI settlement at random valid hex
   └── Spawn CPU opponents (1 for small, 2 for medium, 3 for large)

2. Episode loop (runs up to max_episode_ticks)
   ├── Each tick:
   │   ├── Every action_interval ticks:
   │   │   ├── get_observation(settlement) → 95-float vector
   │   │   ├── genome.forward(obs) → 14-float logits
   │   │   └── select_and_execute_action(logits)
   │   └── Every 60 ticks: update_metrics()
   └── End conditions:
       ├── ticks >= max_episode_ticks
       ├── domination_progress >= 0.75 (victory)
       ├── all CPU settlements destroyed (victory)
       └── AI settlement destroyed (defeat)

3. Compute fitness
   ├── territory_score (sigmoid on map %)
   ├── progression_score (weighted component sum)
   └── survival_score (exponential ramp)
```

---

## Metrics Output

Metrics are written to `user://metrics.jsonl` (one JSON line per generation) and also accumulated in `user://metrics.json` (latest generation snapshot).

### Per-Generation Fields

| Key | Description |
|-----|-------------|
| `generation` | Current generation number |
| `best_aggregate_fitness` | Best single-value fitness this gen |
| `avg_aggregate_fitness` | Population mean aggregate fitness |
| `best_territory_score` | Best territory objective |
| `best_progression_score` | Best progression objective |
| `best_survival_score` | Best survival objective |
| `species_count` | Number of active species |
| `population_size` | Current population size |
| `avg_episode_ticks` | Mean episode length |
| `victory_rate` | Fraction of episodes ending in victory |
| `domination_rate` | Fraction ending in domination victory |
| `avg_happiness` | Mean happiness at episode end |
| `avg_trade_income` | Mean trade income at episode end |
| `avg_invalid_action_rate` | Mean fraction of invalid actions taken |
| `generation_time_sec` | Wall-clock time for this generation |

---

## Overnight / Sweep Training (Python)

### Setup
```bash
pip install wandb
wandb login
```

### Create a sweep
```bash
cd overnight-agent
wandb sweep tile_empire_sweep.yaml
```

### Launch workers
```bash
python overnight_evolve.py \
  --sweep-id <sweep-id> \
  --project tile-empire \
  --count 5 \
  --timeout-minutes 60
```

### Parallel workers (bash)
```bash
for i in 1 2 3 4; do
  python overnight_evolve.py --sweep-id <id> --count 1 &
done
wait
```

### Key CLI flags

| Flag | Default | Description |
|------|---------|-------------|
| `--sweep-id` | required | W&B sweep ID |
| `--project` | `tile-empire` | W&B project name |
| `--entity` | None | W&B entity (team or user) |
| `--count` | 1 | Runs this worker executes |
| `--visible` | false | Show Godot window |
| `--poll-interval` | 2.0 | Seconds between metrics reads |
| `--max-stale` | 300 | Poll cycles without new data before abort |
| `--timeout-minutes` | 60.0 | Hard timeout per run |
| `--worker-id` | auto | Fixed worker ID (for reproducibility) |

---

## Sweep Hyperparameter Ranges

The Bayesian sweep (`tile_empire_sweep.yaml`) optimises `best_aggregate_fitness` with Hyperband early stopping (max_iter=100).

| Parameter | Type | Range / Values |
|-----------|------|----------------|
| `population_size` | values | 50, 100, 150 |
| `compatibility_threshold` | uniform | [2.0, 6.0] |
| `c3` (weight coeff) | uniform | [0.2, 1.0] |
| `weight_mutation_rate` | uniform | [0.6, 0.9] |
| `weight_mutation_power` | uniform | [0.5, 2.5] |
| `add_node_rate` | uniform | [0.01, 0.05] |
| `add_connection_rate` | uniform | [0.02, 0.10] |
| `survival_threshold` | uniform | [0.10, 0.30] |
| `elite_count` | values | 2, 5, 10 |
| `max_episode_ticks` | values | 1800, 3000, 6000 |
| `action_interval` | values | 20, 30, 60 |
| `map_size` | values | small, medium |
| `cpu_difficulty` | values | easy, medium, hard |
| `eval_episodes` | values | 1, 2, 3 |
| `territory_weight` | values | 0.3, 0.5 |
| `progression_weight` | values | 0.3, 0.5 |
| `survival_weight` | values | 0.1, 0.3 |

---

## CI / Automated Checks

Every PR runs:

| Job | What it checks |
|-----|----------------|
| `lint` | `ruff`, GDScript `gdlint`, `cargo fmt`, `cargo clippy` |
| `python-tests` | pytest suite in `tests/python/` |
| `godot-tests` | Headless GDUnit4 test runner |

Run locally:
```bash
ruff check .
gdlint scripts/
cargo fmt --check --manifest-path rust/tile-empire-native/Cargo.toml
cargo clippy --manifest-path rust/tile-empire-native/Cargo.toml -- -D warnings
godot --headless --path . -s tests/run_tests.gd
```
