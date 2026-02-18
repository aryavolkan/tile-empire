# Tile Empire - Evolve Core Integration Notes

## Overview

Tile Empire has been integrated with the shared `evolve-core` library located at `~/projects/evolve-core`. This integration reduces code duplication and provides a consistent framework for neuroevolution across the evolve family of projects.

## What Was Changed

### 1. Python Training Scripts

**Original**: `overnight-agent/overnight_evolve.py`
- Self-contained NEAT implementation
- Custom W&B worker logic
- Inline fitness aggregation

**Refactored**: `overnight-agent/overnight_evolve_refactored.py`
- Imports from `evolve-core`:
  - `NEATGenome` - Standardized genome representation
  - `NEATEvolution` - Shared NEAT algorithm implementation
  - `GodotWorker` - Base class for Godot-based training
  - `FitnessAggregator` - Multi-objective fitness utilities
  - `NSGA2Selection` - True multi-objective selection

### 2. Key Benefits

- **Code Reuse**: NEAT implementation is now shared across projects
- **Consistency**: Same evolution algorithms and parameters across all projects
- **Maintainability**: Bug fixes and improvements benefit all projects
- **Multi-objective**: Access to NSGA-II for true Pareto-optimal selection

### 3. New Features Available

With the evolve-core integration, tile-empire now has access to:

1. **True Multi-objective Optimization**:
   ```bash
   python overnight-agent/overnight_evolve_refactored.py --multi-objective
   ```

2. **Local Training Mode**:
   ```bash
   python overnight-agent/overnight_evolve_refactored.py --local
   ```

3. **Standardized Genome Serialization**: Compatible format across all evolve projects

## Migration Guide

### To Use the Refactored Version:

1. **Update sweep configuration**:
   - Use `sweeps/tile_empire_sweep_refactored.yaml` instead of the original
   - Or update the `program:` line in your existing sweep YAML

2. **Install evolve-core** (optional, but recommended):
   ```bash
   cd ~/projects/evolve-core/python
   pip install -e .
   ```

3. **Run training**:
   ```bash
   # Create new sweep
   wandb sweep sweeps/tile_empire_sweep_refactored.yaml
   
   # Or run locally
   python overnight-agent/overnight_evolve_refactored.py --local
   ```

### Backward Compatibility

The original `overnight_evolve.py` remains unchanged and will continue to work. You can:
- Continue using the original for ongoing experiments
- Migrate to the refactored version for new experiments
- Both versions write compatible genome formats

## What's Shared vs. Project-Specific

### Shared (from evolve-core):
- NEAT genome structure and mutations
- Evolution engine (selection, crossover, speciation)
- W&B worker base classes
- Multi-objective selection algorithms
- Fitness aggregation utilities

### Project-Specific (remains in tile-empire):
- Input/output dimensions (93 inputs, 13 outputs)
- Godot integration parameters (maps, difficulties, etc.)
- Evaluation metrics (territory, progression, survival)
- Game-specific command-line arguments

## Future Improvements

1. **GDScript Integration**: The shared `evolve-core/ai/neural_network.gd` could potentially replace tile-empire's custom implementation
2. **Shared Sweep Templates**: Common sweep configurations could be templated
3. **Metrics Standardization**: Common metrics (generation time, diversity, etc.) could be tracked consistently

## Troubleshooting

If you encounter import errors:
1. Ensure evolve-core is in your Python path
2. The refactored script adds it automatically: `sys.path.insert(0, os.path.expanduser("~/projects/evolve-core/python"))`
3. Or install evolve-core as a package: `pip install -e ~/projects/evolve-core/python`

## Commits

All changes have been made but not yet committed. To commit:

```bash
# In evolve-core
cd ~/projects/evolve-core
git add .
git commit -m "Add Python training utilities for NEAT and W&B integration"

# In tile-empire  
cd ~/projects/tile-empire
git add overnight-agent/overnight_evolve_refactored.py
git add sweeps/tile_empire_sweep_refactored.yaml
git add INTEGRATION_NOTES.md
git commit -m "Integrate with evolve-core shared library"
```