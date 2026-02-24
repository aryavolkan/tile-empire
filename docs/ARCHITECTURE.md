# Tile-Empire Architecture

## Overview

Tile-Empire is a hex-grid turn-based strategy game where neural agents (evolved with NEAT) learn to build settlements, expand territory, and defeat CPU opponents. The system is split into three layers: the **game engine** (GDScript/Godot 4), the **AI layer** (NEAT evolution + observation/action interface), and the **training harness** (Python + W&B).

```
┌─────────────────────────────────────────────────────────────────┐
│                        Python Harness                           │
│  overnight_evolve.py  ←→  tile_empire_sweep.yaml  ←→  W&B     │
└────────────────────────┬────────────────────────────────────────┘
                         │ JSON metrics / sweep_config.json
┌────────────────────────▼────────────────────────────────────────┐
│                     Godot 4 Engine                              │
│                                                                 │
│  main.gd                                                        │
│    └── TrainingManager                                          │
│          ├── NeatEvolution (GDScript or Rust-accelerated)       │
│          │     └── Population of Genomes                        │
│          ├── AgentObserver  →  95-float observation vector      │
│          ├── AgentActions   →  14-action interface              │
│          ├── FitnessCalculator  →  3-objective NSGA-II          │
│          └── Game World                                         │
│                ├── HexGrid (odd-q offset layout)                │
│                ├── Settlement (entities)                        │
│                ├── Units (settler, warrior, worker, archer)     │
│                └── TerritoryManager                             │
│                                                                 │
│  Rust GDExtension (optional, 5–8× faster)                      │
│    ├── HexMath, InfluenceMap, TerritoryFrontier                 │
│    ├── CombatQuery, ResourceCounter, HexLOS                     │
│    └── RustNeatGenome, RustNeatSpecies                          │
└─────────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### Game Engine (GDScript)

| File | Role |
|------|------|
| `scripts/training_manager.gd` | Episode loop, metrics tracking, generation orchestration |
| `scripts/entities/settlement.gd` | Settlement state: stages, buildings, yields, happiness, trade |
| `scripts/ai/agent_actions.gd` | 14-action enum, validity checks, execution, softmax sampling |
| `scripts/ai/agent_observer.gd` | 95-input observation vector construction |
| `scripts/ai/fitness_calculator.gd` | 3-objective NSGA-II fitness computation |
| `scripts/ai/neat_evolution.gd` | GDScript NEAT: speciation, crossover, mutation |
| `scripts/map/hex_grid.gd` | Hex tile management (odd-q offset coordinates) |
| `scripts/map/territory_manager.gd` | Ownership, expansion, frontier detection |
| `scenes/main.gd` | Entry point: UI mode vs. headless auto-train |

### AI Interface

```
Game State
    │
    ▼
AgentObserver.get_observation(settlement, game_state)
    │  → PackedFloat32Array [95 floats, all normalized 0–1]
    ▼
NeatNetwork.forward(observation)
    │  → PackedFloat32Array [14 floats]
    ▼
AgentActions.select_and_execute(outputs, settlement)
    │  softmax → probability distribution
    │  sample → action index
    │  if invalid → best valid fallback
    ▼
Settlement / Game State mutation
```

### Data Flow: One Generation

```
1. Initialize population (pop_size genomes)
2. For each genome:
   a. Reset episode (new map, fresh settlement)
   b. Run episode:
      - Every action_interval ticks: observe → forward → act
      - Every 60 ticks: update metrics
      - End on max_ticks, victory, or defeat
   c. Compute 3-objective fitness vector
3. NSGA-II selection + elitism
4. Speciate survivors
5. Crossover + mutate offspring
6. Log metrics to metrics.jsonl / W&B
7. Repeat
```

## File Layout

```
tile-empire/
├── scenes/
│   ├── main.tscn / main.gd          # Entry point
│   └── game_world.tscn              # In-game scene
├── scripts/
│   ├── entities/
│   │   ├── settlement.gd            # Settlement simulation
│   │   └── unit.gd                  # Unit types
│   ├── ai/
│   │   ├── agent_actions.gd         # Action space
│   │   ├── agent_observer.gd        # Observation space
│   │   ├── fitness_calculator.gd    # Fitness
│   │   └── neat_evolution.gd        # Evolution engine
│   ├── map/
│   │   ├── hex_grid.gd              # Hex grid
│   │   └── territory_manager.gd     # Ownership
│   └── training_manager.gd          # Training loop
├── rust/
│   └── tile-empire-native/          # Rust GDExtension
│       └── src/
│           ├── hex_math.rs
│           ├── influence_map.rs
│           ├── territory_frontier.rs
│           ├── neat_genome.rs
│           └── neat_species.rs
├── tests/
│   └── run_tests.gd                 # GDUnit4 tests
├── overnight-agent/
│   ├── overnight_evolve.py          # Python training harness
│   └── tile_empire_sweep.yaml       # W&B sweep config
└── docs/                            # This directory
```

## Rust GDExtension

The Rust extension (`gdext`) provides optional high-performance implementations for compute-heavy operations. Each module exposes a GDScript-callable class:

| Class | Function | Speedup |
|-------|----------|---------|
| `HexMath` | Distance, neighbors, A* pathfinding | 3–5× |
| `InfluenceMap` | Per-player influence propagation | 4–6× |
| `TerritoryFrontier` | Frontier tile detection | 3–4× |
| `CombatQuery` | Unit range detection | 3–5× |
| `ResourceCounter` | Per-tile resource aggregation | 2–3× |
| `HexLOS` | Line-of-sight checks | 4–6× |
| `RustNeatGenome` | Genome distance, crossover, mutation | 5–8× |
| `RustNeatSpecies` | Speciation | 5–8× |

The GDScript layer falls back to pure-GDScript implementations if the extension is not built.

## Coordinate System

The map uses **odd-q offset** hex coordinates:
- Neighbors computed via cube-coordinate arithmetic
- A* pathfinding with hex distance as heuristic
- `OBSERVATION_RADIUS = 5` tiles around each settlement
