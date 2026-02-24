# AI System

## Overview

Agents are evolved using **NEAT** (NeuroEvolution of Augmenting Topologies) with multi-objective fitness (NSGA-II). Each agent receives a 95-float observation vector and outputs 14 action logits per step.

---

## Observation Space (95 inputs)

All inputs are normalized to approximately [0, 1] unless noted.

### Own State (15 inputs)

| Index | Name | Normalization |
|-------|------|---------------|
| 0 | Territory size | `/ 100.0` |
| 1 | Food resources | `/ 1000.0` |
| 2 | Wood resources | `/ 1000.0` |
| 3 | Stone resources | `/ 1000.0` |
| 4 | Gold resources | `/ 1000.0` |
| 5 | Iron resources | `/ 1000.0` |
| 6 | Settlement stage (0–4) | `/ 4.0` |
| 7 | Population | `/ 200.0` |
| 8 | Granary count | `/ 10.0` |
| 9 | Barracks count | `/ 10.0` |
| 10 | Marketplace count | `/ 10.0` |
| 11 | Food rate | range `[-10, 50]`, normalized |
| 12 | Production rate | `/ 30.0` |
| 13 | Gold rate | `/ 20.0` |
| 14 | Research rate | `/ 15.0` |

### Nearby Tiles (60 inputs, 12 tiles × 5 values)

Sampled within `OBSERVATION_RADIUS = 5` tiles of the settlement. Tiles are zero-padded if fewer than 12 exist.

| Offset within tile | Name | Values |
|-------------------|------|--------|
| +0 | Plains (one-hot) | 0 or 1 |
| +1 | Hills (one-hot) | 0 or 1 |
| +2 | Mountains (one-hot) | 0 or 1 |
| +3 | Ownership | -1 = enemy, 0 = neutral, 1 = owned |
| +4 | Resources | `/ 10.0` |

### Military (8 inputs)

| Index | Name | Normalization |
|-------|------|---------------|
| 75 | Warriors | `/ 50.0` |
| 76 | Archers | `/ 50.0` |
| 77 | Cavalry | `/ 50.0` |
| 78 | Settlers | `/ 10.0` |
| 79 | Workers | `/ 20.0` |
| 80 | Total strength | `/ 500.0` |
| 81 | Garrison strength | `/ 100.0` |
| 82 | Defensive buildings | `/ 5.0` |

### Tech Progress (4 inputs)

| Index | Name | Normalization |
|-------|------|---------------|
| 83 | Unlocked tech count | `/ 20.0` |
| 84 | Research progress | `[0, 1]` |
| 85 | Is researching | boolean |
| 86 | Available tech count | `/ 5.0` |

### Enemy Info (3 inputs)

| Index | Name | Normalization |
|-------|------|---------------|
| 87 | Distance to nearest enemy | `/ 50.0` (MAX_TILE_DISTANCE) |
| 88 | Strength ratio | `/ 3.0` |
| 89 | Is threatening | boolean (true when ratio > 1.5 AND distance < 15) |

### Victory Progress (3 inputs)

| Index | Name | Normalization |
|-------|------|---------------|
| 90 | Domination progress | `[0, 1]` |
| 91 | Culture score | `/ 1000.0` |
| 92 | Tech victory progress | `[0, 1]` |

### Happiness & Trade (2 inputs, indices 93–94)

| Index | Name | Formula |
|-------|------|---------|
| 93 | Happiness | `(happiness + 5) / 15.0` (maps [-5, 10] → [0, 1]) |
| 94 | Trade income | `trade_income / 20.0` (max ~10 for stage 4) |

---

## Action Space (14 actions)

Action selection uses softmax over the 14 output logits followed by weighted sampling. If the sampled action is invalid, the highest-probability valid action is used instead. Invalid attempts increment `invalid_action_attempts`.

| Index | Action | Cooldown | Validity Condition |
|-------|--------|----------|--------------------|
| 0 | IDLE | 2.0 s | Always |
| 1 | EXPAND_TERRITORY | 5.0 s | Adjacent unowned tiles exist |
| 2 | SPAWN_SETTLER | 30.0 s | pop > 5, food ≥ 100, production ≥ 100 |
| 3 | SPAWN_WARRIOR | 10.0 s | barracks built, production ≥ 50 |
| 4 | SPAWN_WORKER | 15.0 s | food ≥ 30 |
| 5 | UPGRADE_SETTLEMENT | 60.0 s | Stage requirements met |
| 6 | RESEARCH_NEXT_TECH | 2.0 s | Tech available |
| 7 | MOVE_UNITS_AGGRESSIVE | 2.0 s | Mobile units exist |
| 8 | MOVE_UNITS_DEFENSIVE | 2.0 s | Mobile units exist |
| 9 | COLLECT_RESOURCES | 2.0 s | Always |
| 10 | BUILD_GRANARY | 20.0 s | `can_build_structure("granary")` |
| 11 | BUILD_BARRACKS | 20.0 s | `can_build_structure("barracks")` |
| 12 | BUILD_MARKETPLACE | 20.0 s | `can_build_structure("marketplace")` |
| 13 | BUILD_TEMPLE | 20.0 s | granary built, stone ≥ 60, gold ≥ 40 |

### Softmax Action Selection (numerical stability)
```
max_val = max(outputs)
probs[i] = exp(outputs[i] - max_val)
probs /= sum(probs)
action = weighted_random_sample(probs)
if not is_valid(action):
    action = argmax over valid actions only
```

---

## Fitness (3-Objective NSGA-II)

### Objective 1 — Territory Score
```
ratio = tiles_owned / total_map_tiles
score = 2.0 / (1.0 + exp(-6.0 * (ratio - 0.5)))   # sigmoid
if ratio >= 0.75:
    score = min(score * 1.2, 1.0)                   # domination bonus
```

### Objective 2 — Progression Score (weighted sum)
| Component | Weight | Formula |
|-----------|--------|---------|
| Settlement stage | 30% | `stage / 4.0` |
| Buildings | 20% | `min(count / 15, 1.0)` |
| Technology | 25% | `min(techs / 20, 1.0)` |
| Culture | 15% | `min(culture / 1000, 1.0)` |
| Military efficiency | 10% | `kills / (kills + losses)` |
| Resource efficiency | 10% | `clamp(0, 1)` |
| Territory growth rate | 5% | `min(rate / 5.0 tiles/min, 1.0)` |
| Happiness | 5% | `min(happiness / 10, 1.0)` |
| Trade income | 5% | `min(trade_income / 10, 1.0)` |

Invalid action penalty: reduces progression score by up to 20% proportional to `invalid_action_rate`.

### Objective 3 — Survival Score
```
score = 1.0 - exp(-3.0 * (ticks_survived / max_ticks))
```
Exponential ramp with diminishing returns; perfect survival = 1.0.

### Victory Multipliers (applied to all objectives)
| Victory Type | Multiplier |
|-------------|------------|
| Domination (≥ 75% map) | 1.5× |
| Culture (culture ≥ 1000) | 1.4× |
| Technology (≥ 95% tech tree) | 1.4× |
| Economic | 1.3× |
| Default win | 1.2× |

### Aggregate Fitness (single scalar for ranking)
```
aggregate = territory_score * 0.4 + progression_score * 0.4 + survival_score * 0.2
```

---

## NEAT Genome Structure

```gdscript
genome = {
    "id": String,
    "nodes": [
        { "id": int, "type": "input"|"hidden"|"output", "bias": float }
    ],
    "connections": [
        {
            "innovation": int,
            "from_node": int,
            "to_node": int,
            "weight": float,   # clamped to [-10, 10]
            "enabled": bool
        }
    ],
    "fitness": [float, float, float],   # 3 objectives
    "aggregate_fitness": float,
    "species_id": int
}
```

### Initialization
- 95 input nodes + 14 output nodes
- ~10% initial connection probability (random input→output pairs)
- Connection weights: uniform `[-2, 2]`
- Node biases: uniform `[-1, 1]`

### Mutation Operations
| Operation | Rate | Behavior |
|-----------|------|----------|
| Weight perturb | 90% of weight mutations | `weight += randf() * power` |
| Weight replace | 10% of weight mutations | `weight = randf_range(-2, 2)` |
| Add node | `add_node_rate` | Split connection, insert hidden node |
| Add connection | `add_connection_rate` | New random connection, weight `[-2, 2]` |

### Crossover
Aligns genes by innovation number. For matching genes, randomly takes from either parent. Excess/disjoint genes always taken from the fitter parent.

### Speciation
```
distance = c1 × excess_genes + c2 × disjoint_genes + c3 × avg_weight_diff
```
Genomes with `distance < compatibility_threshold` are placed in the same species. Representatives are updated each generation.

---

## Hall of Fame

The training manager maintains a hall of fame of the best individuals across generations. HoF members serve as opponents for new generations, preventing strategy cycling in coevolution.

- Selection: Elo-weighted random (higher Elo = more likely to be chosen as opponent)
- Elo starts at 1200, updated after each game using K=32
- Max size: 20 members per side (white/black equivalent)
