# Tile Empire

Real-time multiplayer strategy game where players expand empires tile by tile. Built with Godot 4.

Sister project to [evolve](https://github.com/aryavolkan/evolve) and [chess-evolve](https://github.com/aryavolkan/chess-evolve).

## Game Concept

### Core Gameplay Loop

- **Hex-based map**: Hexagonal tiles provide equidistant neighbors and natural-looking territories
- **Real-time multiplayer**: All players act simultaneously, no turn waiting
- **Empire progression**: Hut → Village → Town → City → Empire
- **Territory expansion**: Claim adjacent tiles to grow your empire
- **Skill tree**: Research technologies to unlock buildings, units, and abilities
- **Resource management**: Balance food, production, and gold
- **Conflict resolution**: Combat, diplomacy, or both

### Why Hex Grid?

We chose hexagonal tiles over square grids because:
- All six neighbors are equidistant (no diagonal movement complexity)
- More natural territory shapes and borders
- Better for influence/combat calculations
- Classic strategy game feel

## Tech Stack

- **Engine**: Godot 4.3+
- **Language**: GDScript
- **Networking**: Godot's MultiplayerAPI with ENet
- **Future**: Rust GDExtension for performance-critical systems and AI agents

## Architecture

### Core Systems

1. **Tile System** (`scripts/world/`)
   - `Tile`: Resource representing a hex tile with terrain, resources, and ownership
   - `TileMap`: Hex grid management, pathfinding, and territory queries

2. **Territory Management** (`scripts/systems/territory_manager.gd`)
   - Tracks empire boundaries
   - Handles expansion costs and border conflicts
   - Manages territory-based resources

3. **Settlements** (`scripts/entities/settlement.gd`)
   - Growth stages from hut to empire
   - Population and resource generation
   - Building construction and upgrades

4. **Units** (`scripts/entities/unit.gd`)
   - Settlers, warriors, archers, scouts, workers
   - Movement, combat, and special abilities
   - Experience and leveling system

5. **Skill Tree** (`scripts/systems/skill_tree.gd`)
   - Five categories: Economy, Military, Expansion, Diplomacy, Culture
   - Prerequisite chains and research costs
   - Unlocks buildings, units, and passive bonuses

6. **Progression** (`scripts/systems/progression.gd`)
   - Empire stage advancement
   - Victory conditions: Domination, Cultural, Diplomatic, Ascension
   - Milestone tracking and rewards

7. **Multiplayer** (`scripts/networking/multiplayer_manager.gd`)
   - Real-time synchronization
   - Host/client architecture
   - Up to 8 players

### Project Structure

```
tile-empire/
├── project.godot          # Godot project configuration
├── scenes/                # Scene files (.tscn)
│   ├── main.tscn         # Main game scene
│   ├── world/            # World-related scenes
│   ├── entities/         # Units and settlements
│   └── ui/               # User interface
├── scripts/              # GDScript files (.gd)
│   ├── world/           # Tile and map systems
│   ├── entities/        # Game objects
│   ├── systems/         # Core game systems
│   └── networking/      # Multiplayer code
└── assets/              # Graphics, audio, fonts
```

## How to Run

1. **Install Godot 4.3+** from [godotengine.org](https://godotengine.org/)

2. **Clone the repository**:
   ```bash
   git clone https://github.com/aryavolkan/tile-empire.git
   cd tile-empire
   ```

3. **Open in Godot**:
   - Launch Godot
   - Click "Import"
   - Navigate to the `tile-empire` folder
   - Select `project.godot`
   - Click "Import & Edit"

4. **Run the game**:
   - Press F5 or click the Play button
   - For multiplayer testing, run multiple instances

## Development Setup

### Code Style

- GDScript with `class_name` declarations
- Public variables before private
- No trailing whitespace
- Meaningful variable names
- Comments for complex logic

### Testing Multiplayer

1. Enable "Debug > Settings > Allow Multiple Instances" in Editor
2. Run 2+ instances
3. Host on one instance, join from others

## Roadmap

### Phase 1: Core (Current)
- [x] Hex-based tile system
- [x] Basic settlements and units
- [x] Territory expansion
- [x] Skill tree system
- [x] Multiplayer foundation
- [ ] Basic UI/HUD
- [ ] Visual tile representation

### Phase 2: Polish
- [ ] Tile graphics and animations
- [ ] Sound effects and music
- [ ] Improved UI/UX
- [ ] Save/load system
- [ ] AI opponents

### Phase 3: Advanced Features
- [ ] Rust extension for performance
- [ ] Neuroevolution AI agents
- [ ] Advanced diplomacy
- [ ] Mod support
- [ ] Procedural map generation

### Phase 4: Integration
- [ ] Cross-game AI tournaments
- [ ] Shared leaderboards with sister projects
- [ ] Meta-progression system

## AI/Neuroevolution Hooks

The game is designed with AI agents in mind:

- **State representation**: Clean tile/unit/resource state
- **Action space**: Well-defined actions (expand, build, move, attack)
- **Reward signals**: Multiple objectives for different AI strategies
- **Performance**: Rust extension planned for fast simulation

This allows for:
- Training neural networks to play
- Evolution of strategies
- AI vs AI tournaments
- Human vs AI challenges

## AI Training

Tile Empire now supports training neuroevolution AI agents using NEAT + NSGA-2, powered by the same system as the [evolve](https://github.com/aryavolkan/evolve) project.

### Quick Start

1. **Install dependencies**:
   ```bash
   # Use the wandb-worker virtual environment
   source ~/.venv/wandb-worker/bin/activate
   pip install wandb
   ```

2. **Test single training episode**:
   ```bash
   cd ~/projects/tile-empire
   python overnight-agent/overnight_evolve.py
   ```

3. **Create a W&B sweep**:
   ```bash
   python overnight-agent/overnight_evolve.py sweep
   # Outputs: Created sweep: <SWEEP_ID>
   ```

4. **Run training workers**:
   ```bash
   # In separate terminals/tmux panes:
   python overnight-agent/overnight_evolve.py agent <SWEEP_ID>
   ```

5. **Monitor progress** at [wandb.ai](https://wandb.ai/)

### Architecture

- **Observation Space** (93 inputs):
  - Own state: territory, resources, settlement stage, buildings
  - Nearby tiles: terrain, ownership, resources (5-tile radius)
  - Military: unit counts, strength, defenses
  - Tech progress: unlocked technologies, research status
  - Enemy info: distance, relative strength
  - Victory progress: domination %, culture score

- **Action Space** (13 discrete actions):
  - Territory expansion
  - Unit spawning (settler, warrior, worker)
  - Settlement upgrading
  - Technology research
  - Military movements (aggressive/defensive)
  - Building construction
  - Resource focus

- **Fitness Function** (Multi-objective NSGA-2):
  - Territory control (tiles owned / total tiles)
  - Progression (settlement stage, buildings, tech, culture)
  - Survival (episode duration)

### Training Configuration

Edit `sweeps/tile_empire_sweep.yaml` to adjust:
- Population size (50-150)
- Episode length (30s-100s)
- Map size (small/medium)
- CPU opponent difficulty
- NEAT mutation rates
- Multi-objective weights

### Headless Training

Training runs Godot in headless mode by default. Each worker:
1. Loads a NEAT genome from JSON
2. Initializes a game world with AI agent
3. Runs episode for N ticks
4. Writes fitness metrics to JSON
5. Python aggregates results and evolves population

### Using Trained Models

Best genomes are saved to `~/.local/share/godot/app_userdata/TileEmpire/`:
- `best_population_gen{N}.json` - Best population at generation N
- `final_population.json` - Final evolved population

To play against a trained AI:
```gdscript
# Load in Godot
var genome = load_genome_from_json("path/to/genome.json")
var nn = NeuralNetwork.new()
nn.from_genome(genome)

# Use in game
var ai_controller = AIController.new()
ai_controller.neural_network = nn
```

## Contributing

Feel free to open issues or submit PRs! Areas where help is welcome:

- Tile graphics and visual assets
- UI/UX improvements
- Balance testing
- AI opponent implementation
- Performance optimization

## License

MIT (consistent with sister projects)

---

**Note**: This is an early-stage project. Expect rapid changes and incomplete features.