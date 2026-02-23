#!/usr/bin/env python3
"""
Tile Empire NEAT Training Worker - Refactored to use evolve-core
"""

import os
import random
import sys

# Add evolve-core to path
sys.path.insert(0, os.path.expanduser("~/projects/evolve-core/python"))

import wandb
from evolve_core import FitnessAggregator, GodotWorker, NEATEvolution, NEATGenome, NSGA2Selection

# Paths
GODOT_PATH = os.environ.get("GODOT_PATH", "/Applications/Godot.app/Contents/MacOS/Godot")
PROJECT_PATH = os.environ.get("TILE_EMPIRE_PATH", os.path.expanduser("~/Projects/tile-empire"))
GODOT_USER_DIR = os.environ.get("GODOT_USER_DIR", os.path.expanduser("~/.local/share/godot/app_userdata/TileEmpire"))


class TileEmpireWorker(GodotWorker):
    """Tile Empire specific W&B worker"""
    
    def __init__(self):
        super().__init__(
            project_name="tile-empire-neat",
            godot_path=GODOT_PATH,
            project_path=PROJECT_PATH,
            user_data_dir=GODOT_USER_DIR
        )
        
        # Tile Empire specific dimensions
        self.input_size = 93  # From agent_observer.gd
        self.output_size = 13  # From agent_actions.gd
    
    def get_sweep_config(self) -> dict:
        """Return Tile Empire sweep configuration"""
        return {
            'method': 'bayes',
            'metric': {'name': 'best_aggregate_fitness', 'goal': 'maximize'},
            'parameters': {
                # NEAT parameters
                'population_size': {'values': [50, 100, 150]},
                'compatibility_threshold': {'distribution': 'uniform', 'min': 2.0, 'max': 6.0},
                'c1': {'value': 1.0},  # Excess coefficient
                'c2': {'value': 1.0},  # Disjoint coefficient
                'c3': {'distribution': 'uniform', 'min': 0.2, 'max': 1.0},  # Weight coefficient
                
                # Mutation rates
                'weight_mutation_rate': {'distribution': 'uniform', 'min': 0.6, 'max': 0.9},
                'weight_mutation_power': {'distribution': 'uniform', 'min': 0.5, 'max': 2.5},
                'add_node_rate': {'distribution': 'uniform', 'min': 0.01, 'max': 0.05},
                'add_connection_rate': {'distribution': 'uniform', 'min': 0.02, 'max': 0.1},
                
                # Selection
                'survival_threshold': {'distribution': 'uniform', 'min': 0.1, 'max': 0.3},
                'elite_count': {'values': [2, 5, 10]},
                
                # Episode parameters
                'max_episode_ticks': {'values': [1800, 3000, 6000]},  # 30s, 50s, 100s
                'action_interval': {'values': [20, 30, 60]},  # Act every N ticks
                'map_size': {'values': ['small', 'medium']},
                'cpu_difficulty': {'values': ['easy', 'medium', 'hard']},
                
                # Multi-objective weights (for aggregation)
                'territory_weight': {'distribution': 'uniform', 'min': 0.3, 'max': 0.5},
                'progression_weight': {'distribution': 'uniform', 'min': 0.3, 'max': 0.5},
                'survival_weight': {'distribution': 'uniform', 'min': 0.1, 'max': 0.3},
                
                # Training
                'max_generations': {'value': 100},
                'eval_episodes': {'values': [1, 2, 3]},  # Episodes per genome
                'early_stop_generations': {'value': 20},
            }
        }
    
    def create_evolution_engine(self, config: wandb.Config) -> NEATEvolution:
        """Create NEAT evolution engine"""
        evolution = NEATEvolution(dict(config))
        evolution.initialize_population(self.input_size, self.output_size)
        return evolution
    
    def evaluate_genome(self, genome: NEATGenome, config: wandb.Config) -> dict:
        """Evaluate a genome in Tile Empire"""
        all_metrics = []
        
        # Run multiple episodes
        for _episode in range(config.eval_episodes):
            # Extra args specific to Tile Empire
            extra_args = [
                "--max-ticks", str(config.max_episode_ticks),
                "--action-interval", str(config.action_interval),
                "--map-size", config.map_size,
                "--map-seed", str(random.randint(0, 999999)),
            ]
            
            if hasattr(config, 'disable_cpu') and config.disable_cpu:
                extra_args.append("--disable-cpu")
            elif hasattr(config, 'cpu_difficulty'):
                extra_args.extend(["--cpu-difficulty", config.cpu_difficulty])
            
            # Run evaluation
            metrics = self.run_godot_evaluation(genome, config, extra_args)
            
            if 'error' not in metrics:
                all_metrics.append(metrics)
        
        # Aggregate metrics across episodes
        if not all_metrics:
            return {
                'fitness': [0.0, 0.0, 0.0],
                'aggregate_fitness': 0.0,
                'error': True
            }
        
        # Average each objective across episodes
        avg_territory = sum(m.get('territory_score', 0) for m in all_metrics) / len(all_metrics)
        avg_progression = sum(m.get('progression_score', 0) for m in all_metrics) / len(all_metrics)
        avg_survival = sum(m.get('survival_time', 0) for m in all_metrics) / len(all_metrics)
        
        # Multi-objective fitness
        fitness = [avg_territory, avg_progression, avg_survival / config.max_episode_ticks]
        
        # Aggregate using configured weights
        weights = {
            'territory': config.territory_weight,
            'progression': config.progression_weight,
            'survival': config.survival_weight
        }
        
        objectives = {
            'territory': fitness[0],
            'progression': fitness[1],
            'survival': fitness[2]
        }
        
        aggregate = FitnessAggregator.weighted_sum(objectives, weights)
        
        return {
            'fitness': fitness,
            'aggregate_fitness': aggregate,
            'territory_score': avg_territory,
            'progression_score': avg_progression,
            'survival_time': avg_survival,
            'episodes_played': len(all_metrics)
        }
    
    def train_multi_objective(self):
        """Alternative training using NSGA-II for true multi-objective optimization"""
        run = wandb.init()
        config = wandb.config
        
        print(f"Starting multi-objective training with config: {dict(config)}")
        
        # Create evolution engine
        evolution = self.create_evolution_engine(config)
        
        for generation in range(config.get('max_generations', 100)):
            print(f"\n=== Generation {generation} ===")
            
            # Evaluate population
            population_data = []
            for i, genome in enumerate(evolution.population):
                metrics = self.evaluate_genome(genome, config)
                
                # Store fitness in genome and create dict for NSGA-II
                genome.fitness = metrics['fitness']
                genome.aggregate_fitness = metrics['aggregate_fitness']
                
                population_data.append({
                    'genome': genome,
                    'fitness': metrics['fitness'],
                    'index': i
                })
                
                # Log metrics
                log_data = {f"genome_{i}/{k}": v for k, v in metrics.items()}
                wandb.log(log_data)
            
            # Apply NSGA-II selection
            selected = NSGA2Selection.select_population(
                population_data, 
                int(evolution.population_size * config.get('survival_threshold', 0.2))
            )
            
            # Update population with selected genomes
            evolution.population = [item['genome'] for item in selected]
            
            # Continue with standard evolution
            evolution.evolve_generation()
            
            # Log generation stats
            fronts = NSGA2Selection.non_dominated_sort(population_data)
            wandb.log({
                'generation': generation,
                'num_fronts': len(fronts),
                'pareto_front_size': len(fronts[0]) if fronts else 0,
                'num_species': len([s for s in evolution.species if s])
            })
        
        run.finish()


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Tile Empire NEAT Training')
    parser.add_argument('--sweep-id', type=str, help='W&B sweep ID to join')
    parser.add_argument('--multi-objective', action='store_true', 
                       help='Use true multi-objective optimization with NSGA-II')
    parser.add_argument('--local', action='store_true',
                       help='Run single local training without W&B sweep')
    
    args = parser.parse_args()
    
    worker = TileEmpireWorker()
    
    if args.local:
        # Run single training locally
        print("Running local training...")
        if args.multi_objective:
            worker.train_multi_objective()
        else:
            worker.train()
    else:
        # Run W&B sweep
        worker.run_sweep(args.sweep_id)


if __name__ == "__main__":
    main()