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