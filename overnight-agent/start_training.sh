#!/usr/bin/env bash
# Tile Empire NEAT Training Launcher
# Usage: ./start_training.sh [--sweep] [--generations N]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Auto-detect Godot path
if [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
    export GODOT_PATH="/Applications/Godot.app/Contents/MacOS/Godot"
elif command -v godot &>/dev/null; then
    export GODOT_PATH="$(command -v godot)"
else
    echo "ERROR: Godot not found. Set GODOT_PATH env var." >&2
    exit 1
fi

export TILE_EMPIRE_PATH="$PROJECT_DIR"

# Ensure Godot imports are up to date
echo "==> Importing Godot project..."
"$GODOT_PATH" --headless --path "$PROJECT_DIR" --import --quit 2>/dev/null || true

# Check for wandb
if ! python3 -c "import wandb" 2>/dev/null; then
    echo "WARNING: wandb not installed. Run: pip install wandb"
    echo "Training will still work but won't log to W&B."
fi

echo "==> Starting training..."
echo "    Godot: $GODOT_PATH"
echo "    Project: $TILE_EMPIRE_PATH"

if [ "${1:-}" = "--sweep" ]; then
    echo "    Mode: W&B Sweep"
    cd "$PROJECT_DIR"
    python3 overnight-agent/overnight_evolve.py --sweep
else
    cd "$PROJECT_DIR"
    python3 overnight-agent/overnight_evolve.py "$@"
fi
