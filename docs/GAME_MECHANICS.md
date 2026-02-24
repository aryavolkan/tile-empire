# Game Mechanics

## Settlement Stages

Settlements evolve through 5 stages. Each stage unlocks new buildings and increases resource yields.

| Stage | ID | Max Population | Required Buildings | Required Territory |
|-------|----|---------------|--------------------|--------------------|
| Hut | 0 | 5 | — | — |
| Village | 1 | 15 | granary | 6 tiles |
| Town | 2 | 30 | granary, barracks, marketplace | 15 tiles |
| City | 3 | 50 | granary, barracks, marketplace, temple, library | 25 tiles |
| Empire | 4 | 100 | granary, barracks, marketplace, temple, library, palace | 40 tiles |

Upgrading costs production time and may have resource requirements defined in `can_upgrade_settlement()`.

---

## Buildings

### Effects Table

| Building | Food | Production | Gold | Science | Max Pop | Happiness | Culture | Defense | Unlocks |
|----------|:----:|:----------:|:----:|:-------:|:-------:|:---------:|:-------:|:-------:|---------|
| Granary | +2 | — | — | — | +3 | +1 | — | — | Stage 1+ |
| Barracks | — | +2 | — | — | — | — | — | +10 | Warriors, archers |
| Marketplace | — | — | +3 | — | — | — | — | — | Trade routes |
| Temple | — | — | — | — | — | +2 | +1 | — | Stage 3+ |
| Library | — | — | — | +3 | — | — | +1 | — | Stage 3+ |
| Palace | — | — | — | — | — | +3 | — | — | Stage 4+ |

### Build Costs

| Building | Resource Requirements |
|----------|-----------------------|
| Granary | (varies, stage dependent) |
| Barracks | (varies) |
| Marketplace | (varies) |
| Temple | granary built + stone ≥ 60 + gold ≥ 40 |
| Library | (varies) |
| Palace | (varies, high-tier) |

---

## Resource Yields

All yields are computed each turn in `_update_yields()`. Happiness and trade income are calculated first since production and gold depend on them.

### Food Yield
```
food_rate = 2                         # base
          + worked_tiles_food         # hex tile bonuses
          + (granary ? 2 : 0)         # building bonus
          + stage * 2                 # stage bonus
```

### Production Yield (happiness-modified)
```
raw_production = 1                    # base
               + worked_tiles_prod
               + (barracks ? 2 : 0)
               + stage * 3
production_rate = int(raw_production * happiness_modifier)
```

### Gold Yield
```
gold_rate = 1                         # base
          + worked_tiles_gold
          + (marketplace ? 3 : 0)
          + stage * 2
          + trade_income
```

### Science Yield
```
science_rate = 0                      # base
             + (library ? 3 : 0)
             + (stage >= TOWN ? stage_bonus : 0)
```

---

## Happiness System

Happiness is an integer clamped to `[-5, 10]` and updated each turn.

### Happiness Formula
```
happiness = 0
+ (granary ? 1 : 0)                   # Granary: +1
+ (temple ? 2 : 0)                    # Temple: +2
+ (palace ? 3 : 0)                    # Palace: +3
+ clamp(food_surplus / 2, -3, 2)      # Food surplus (hunger = negative)
+ war_weariness_penalty               # War: -1 per ongoing conflict
+ stage                               # Stage bonus: +0 to +4
happiness = clamp(happiness, -5, 10)
```

`food_surplus = food_rate - (population * 2)` (positive = surplus, negative = hunger).

### Happiness → Production Multiplier
| Happiness | Multiplier |
|-----------|-----------|
| ≤ 0 | 0.8× (−20% production) |
| 1–3 | 1.0× (no change) |
| 4–6 | 1.1× (+10% production) |
| ≥ 7 | 1.2× (+20% production) |

---

## Trade Routes

Trade income is unlocked by building a marketplace. It scales with settlement stage.

```
trade_income = 0 if no marketplace
trade_income = (stage + 1) * 2 if marketplace built
```

| Stage | Trade Income / Turn |
|-------|---------------------|
| Hut (0) | 2 |
| Village (1) | 4 |
| Town (2) | 6 |
| City (3) | 8 |
| Empire (4) | 10 |

Trade income is added directly to `gold_rate`.

---

## Population & Growth

- **Food consumption**: `population * 2` per turn
- **Net food surplus**: `food_rate - food_consumption`
- **Growth threshold**: `population * 15` accumulated food
- Growth progress increments by food surplus each turn; when it reaches the threshold, population increases by 1

If food surplus is negative, war weariness or starvation mechanics apply.

---

## Units

| Unit | Spawn Cost | Requirements | Role |
|------|------------|--------------|------|
| Settler | food ≥ 100, production ≥ 100, pop > 5 | — | Found new settlements |
| Warrior | production ≥ 50 | barracks | Basic melee combat |
| Worker | food ≥ 30 | — | Tile improvement |
| Archer | production ≥ 60, wood ≥ 30 | barracks | Ranged combat |

### Unit Actions (via AI)
- **MOVE_UNITS_AGGRESSIVE** (action 7): Move military units toward nearest enemy
- **MOVE_UNITS_DEFENSIVE** (action 8): Move military units to garrison / defend settlement

### Combat
- Military strength = sum of unit combat values
- Garrison strength = units in settlement tile
- Threat condition: `enemy_strength_ratio > 1.5 AND distance < 15 tiles`

---

## Territory

Territory is managed by `TerritoryManager`. Expansion requires adjacent unowned tiles and resources/time.

- **EXPAND_TERRITORY** (action 1): Claims one adjacent unowned tile (5 s cooldown)
- Territory size directly feeds into domination victory and fitness

### Victory Conditions
| Type | Condition |
|------|-----------|
| Domination | `territory / total_tiles >= 0.75` |
| Conquest | All CPU opponent settlements destroyed |
| Defeat | Own settlement destroyed |

---

## Technology

- Techs are researched via **RESEARCH_NEXT_TECH** (action 6, 2 s cooldown)
- Progress tracked as `research_progress ∈ [0, 1]` toward the current tech
- Tech victory: `techs_unlocked / total_techs >= 0.95`
- Library increases science yield (+3), accelerating research

---

## Map

Maps are hex grids using odd-q offset coordinates with three terrain types:

| Terrain | Properties |
|---------|-----------|
| Plains | Standard movement, balanced resources |
| Hills | Reduced movement, bonus production tiles |
| Mountains | Blocked movement, bonus stone |

- **OBSERVATION_RADIUS = 5**: Agent sees 12 sampled tiles within 5 hex distance
- **A* pathfinding**: Used for unit movement, implemented in Rust (`HexMath`) or GDScript fallback
- Map sizes: small (fewer tiles, 1 CPU), medium (2 CPUs), large (3 CPUs)

---

## CPU Opponents

CPU opponents run simplified rule-based logic at varying difficulty:

| Difficulty | Behavior |
|------------|---------|
| easy | Expands slowly, rarely attacks |
| medium | Balanced expansion and aggression |
| hard | Aggressive expansion, targets weakest neighbour |

CPU count by map size: small=1, medium=2, large=3.
