#!/usr/bin/env python3
"""
Tile Empire NEAT Training Worker
Adapted from evolve project for tile-empire neuroevolution
"""

import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

import wandb

# Enable line buffering for real-time logging
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

# Paths
GODOT_PATH = os.environ.get("GODOT_PATH", "/usr/local/bin/godot")
PROJECT_PATH = os.environ.get("TILE_EMPIRE_PATH", os.path.expanduser("~/projects/tile-empire"))
GODOT_USER_DIR = os.environ.get("GODOT_USER_DIR", os.path.expanduser("~/.local/share/godot/app_userdata/TileEmpire"))

# Generate unique worker ID
WORKER_ID = str(uuid.uuid4())[:8]

# Sweep configuration
sweep_config = {
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
    }
}


class TileEmpireNEAT:
    """NEAT implementation for Tile Empire"""
    
    def __init__(self, config):
        self.config = config
        self.population_size = config.population_size
        self.compatibility_threshold = config.compatibility_threshold
        self.c1 = config.c1
        self.c2 = config.c2
        self.c3 = config.c3
        
        self.innovation_counter = 0
        self.node_counter = 0
        
        # Neural network structure
        self.input_size = 93  # From agent_observer.gd
        self.output_size = 13  # From agent_actions.gd
        
        # Initialize population
        self.population = []
        self.species = []
        self.generation = 0
        
        self._initialize_population()
    
    def _initialize_population(self):
        """Create initial population with minimal topology"""
        for _ in range(self.population_size):
            genome = self._create_minimal_genome()
            self.population.append(genome)
    
    def _create_minimal_genome(self):
        """Create a minimal genome with input→output connections"""
        genome = {
            'id': str(uuid.uuid4())[:8],
            'nodes': [],
            'connections': [],
            'fitness': [0.0, 0.0, 0.0],  # Multi-objective
            'aggregate_fitness': 0.0,
            'species_id': None
        }
        
        # Add input nodes
        for i in range(self.input_size):
            genome['nodes'].append({
                'id': self.node_counter,
                'type': 'input',
                'bias': 0.0
            })
            self.node_counter += 1
        
        # Add output nodes
        for i in range(self.output_size):
            genome['nodes'].append({
                'id': self.node_counter,
                'type': 'output',
                'bias': random.uniform(-1, 1)
            })
            self.node_counter += 1
        
        # Add initial connections (sparse)
        connection_probability = 0.1  # Only connect 10% initially
        for i in range(self.input_size):
            for j in range(self.output_size):
                if random.random() < connection_probability:
                    genome['connections'].append({
                        'innovation': self.innovation_counter,
                        'from_node': i,
                        'to_node': self.input_size + j,
                        'weight': random.uniform(-2, 2),
                        'enabled': True
                    })
                    self.innovation_counter += 1
        
        return genome
    
    def evolve_generation(self):
        """Run one generation of evolution"""
        # Speciate
        self._speciate()
        
        # Create offspring
        offspring = []
        
        # Elite preservation
        elite = self._get_elite()
        offspring.extend(elite)
        
        # Generate rest of population
        while len(offspring) < self.population_size:
            # Tournament selection
            parent1 = self._tournament_select()
            
            if random.random() < 0.75:  # 75% sexual reproduction
                parent2 = self._tournament_select()
                child = self._crossover(parent1, parent2)
            else:  # 25% asexual reproduction
                child = copy.deepcopy(parent1)
            
            # Mutate
            self._mutate(child)
            
            offspring.append(child)
        
        self.population = offspring[:self.population_size]
        self.generation += 1
    
    def _mutate(self, genome):
        """Apply mutations to genome"""
        config = self.config
        
        # Weight mutations
        if random.random() < config.weight_mutation_rate:
            for conn in genome['connections']:
                if random.random() < 0.9:  # 90% perturb
                    conn['weight'] += random.uniform(-1, 1) * config.weight_mutation_power
                    conn['weight'] = max(-10, min(10, conn['weight']))  # Clamp
                else:  # 10% replace
                    conn['weight'] = random.uniform(-2, 2)
        
        # Add node mutation
        if random.random() < config.add_node_rate and genome['connections']:
            conn = random.choice([c for c in genome['connections'] if c['enabled']])
            self._add_node_mutation(genome, conn)
        
        # Add connection mutation
        if random.random() < config.add_connection_rate:
            self._add_connection_mutation(genome)
    
    def save_population(self, filepath):
        """Save population to JSON"""
        data = {
            'generation': self.generation,
            'population': self.population,
            'innovation_counter': self.innovation_counter,
            'node_counter': self.node_counter
        }
        
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)


import random
import copy


def evaluate_genome(genome, config, worker_id):
    """Evaluate a single genome by running Godot"""
    # Write genome to file
    genome_path = os.path.join(GODOT_USER_DIR, f"genome_{worker_id}.json")
    metrics_path = os.path.join(GODOT_USER_DIR, f"metrics_{worker_id}.json")
    
    os.makedirs(os.path.dirname(genome_path), exist_ok=True)
    
    with open(genome_path, 'w') as f:
        json.dump(genome, f)
    
    # Clear old metrics
    if os.path.exists(metrics_path):
        os.remove(metrics_path)
    
    # Run multiple episodes for more robust evaluation
    all_metrics = []
    
    for episode in range(config.eval_episodes):
        # Build Godot command
        cmd = [
            GODOT_PATH,
            "--path", PROJECT_PATH,
            "--headless",
            "--",
            "--training",
            "--genome-path", genome_path,
            "--metrics-path", metrics_path,
            "--max-ticks", str(config.max_episode_ticks),
            "--action-interval", str(config.action_interval),
            "--map-size", config.map_size,
            "--map-seed", str(random.randint(0, 999999)),  # Random seed per episode
            "--worker-id", worker_id
        ]
        
        if hasattr(config, 'disable_cpu') and config.disable_cpu:
            cmd.append("--disable-cpu")
        else:
            cmd.extend(["--cpu-difficulty", config.cpu_difficulty])
        
        # Run Godot
        timeout_seconds = (config.max_episode_ticks / 60.0) + 30  # Episode time + buffer
        
        try:
            proc = subprocess.run(cmd, capture_output=True, timeout=timeout_seconds)
            
            # Read metrics
            if os.path.exists(metrics_path):
                with open(metrics_path, 'r') as f:
                    metrics = json.load(f)
                    all_metrics.append(metrics)
                    
                    print(f"Episode {episode + 1}: T={metrics['territory_score']:.3f} "
                          f"P={metrics['progression_score']:.3f} S={metrics['survival_score']:.3f} "
                          f"RE={metrics.get('resource_efficiency', 0):.3f} "
                          f"GR={metrics.get('territory_growth_rate', 0):.3f}")
            else:
                print(f"Episode {episode + 1}: No metrics file generated")
                
        except subprocess.TimeoutExpired:
            print(f"Episode {episode + 1}: Timeout after {timeout_seconds}s")
        except Exception as e:
            print(f"Episode {episode + 1}: Error - {e}")
    
    # Aggregate metrics across episodes
    if all_metrics:
        avg_metrics = {
            'territory_score': sum(m['territory_score'] for m in all_metrics) / len(all_metrics),
            'progression_score': sum(m['progression_score'] for m in all_metrics) / len(all_metrics),
            'survival_score': sum(m['survival_score'] for m in all_metrics) / len(all_metrics),
        }
        
        # Calculate aggregate fitness
        avg_metrics['aggregate_fitness'] = (
            avg_metrics['territory_score'] * config.territory_weight +
            avg_metrics['progression_score'] * config.progression_weight +
            avg_metrics['survival_score'] * config.survival_weight
        )
        
        # Include best episode scores
        avg_metrics['best_territory'] = max(m['territory_score'] for m in all_metrics)
        avg_metrics['best_progression'] = max(m['progression_score'] for m in all_metrics)
        avg_metrics['best_survival'] = max(m['survival_score'] for m in all_metrics)
        avg_metrics['avg_resource_efficiency'] = sum(m.get('resource_efficiency', 0) for m in all_metrics) / len(all_metrics)
        avg_metrics['avg_territory_growth_rate'] = sum(m.get('territory_growth_rate', 0) for m in all_metrics) / len(all_metrics)
        
        return avg_metrics
    
    return None


def train():
    """Main training loop"""
    run = wandb.init()
    config = wandb.config
    
    # Create NEAT instance
    neat = TileEmpireNEAT(config)
    
    best_ever_fitness = 0.0
    generations_without_improvement = 0
    
    for generation in range(config.max_generations):
        print(f"\n=== Generation {generation + 1}/{config.max_generations} ===")
        
        # Evaluate population
        gen_best_fitness = 0.0
        gen_avg_fitness = 0.0
        
        for i, genome in enumerate(neat.population):
            print(f"Evaluating genome {i + 1}/{len(neat.population)}...")
            
            metrics = evaluate_genome(genome, config, WORKER_ID)
            
            if metrics:
                genome['fitness'] = [
                    metrics['territory_score'],
                    metrics['progression_score'],
                    metrics['survival_score']
                ]
                genome['aggregate_fitness'] = metrics['aggregate_fitness']
                
                gen_avg_fitness += genome['aggregate_fitness']
                if genome['aggregate_fitness'] > gen_best_fitness:
                    gen_best_fitness = genome['aggregate_fitness']
                    
                # Log to W&B
                wandb.log({
                    'generation': generation,
                    'genome_id': i,
                    'territory_score': metrics['territory_score'],
                    'progression_score': metrics['progression_score'],
                    'survival_score': metrics['survival_score'],
                    'aggregate_fitness': metrics['aggregate_fitness'],
                    'best_territory': metrics.get('best_territory', 0),
                    'best_progression': metrics.get('best_progression', 0),
                    'best_survival': metrics.get('best_survival', 0),
                    'resource_efficiency': metrics.get('avg_resource_efficiency', 0),
                    'territory_growth_rate': metrics.get('avg_territory_growth_rate', 0),
                })
        
        gen_avg_fitness /= len(neat.population)
        
        # Track improvement
        if gen_best_fitness > best_ever_fitness:
            best_ever_fitness = gen_best_fitness
            generations_without_improvement = 0
            
            # Save best genome
            best_genome = max(neat.population, key=lambda g: g['aggregate_fitness'])
            neat.save_population(os.path.join(GODOT_USER_DIR, f"best_population_gen{generation}.json"))
        else:
            generations_without_improvement += 1
        
        # Log generation summary
        wandb.log({
            'generation': generation,
            'gen_best_fitness': gen_best_fitness,
            'gen_avg_fitness': gen_avg_fitness,
            'best_aggregate_fitness': best_ever_fitness,
            'generations_without_improvement': generations_without_improvement,
            'species_count': len(neat.species)
        })
        
        print(f"Generation {generation + 1} complete. Best: {gen_best_fitness:.3f}, Avg: {gen_avg_fitness:.3f}")
        
        # Early stopping
        if generations_without_improvement > 20:
            print("No improvement for 20 generations. Stopping early.")
            break
        
        # Evolve to next generation
        neat.evolve_generation()
    
    # Save final population
    neat.save_population(os.path.join(GODOT_USER_DIR, "final_population.json"))
    print(f"Training complete! Best fitness: {best_ever_fitness:.3f}")


def main():
    """Entry point with sweep management"""
    if len(sys.argv) > 1 and sys.argv[1] == "sweep":
        # Create new sweep
        sweep_id = wandb.sweep(sweep_config, project="tile-empire-ai")
        print(f"Created sweep: {sweep_id}")
        print(f"Run workers with: python {sys.argv[0]} agent {sweep_id}")
    elif len(sys.argv) > 2 and sys.argv[1] == "agent":
        # Run sweep agent
        sweep_id = sys.argv[2]
        print(f"Starting sweep agent for: {sweep_id}")
        wandb.agent(sweep_id, function=train, project="tile-empire-ai")
    else:
        # Single run for testing
        print("Running single training session...")
        
        # Use test config
        test_config = {
            'population_size': 20,
            'compatibility_threshold': 3.0,
            'c1': 1.0,
            'c2': 1.0, 
            'c3': 0.5,
            'weight_mutation_rate': 0.8,
            'weight_mutation_power': 1.0,
            'add_node_rate': 0.03,
            'add_connection_rate': 0.05,
            'survival_threshold': 0.2,
            'elite_count': 2,
            'max_episode_ticks': 1800,
            'action_interval': 30,
            'map_size': 'small',
            'cpu_difficulty': 'easy',
            'territory_weight': 0.4,
            'progression_weight': 0.4,
            'survival_weight': 0.2,
            'max_generations': 10,
            'eval_episodes': 1
        }
        
        class Config:
            def __init__(self, d):
                for k, v in d.items():
                    setattr(self, k, v)
            
            def get(self, key, default=None):
                return getattr(self, key, default)
        
        neat = TileEmpireNEAT(Config(test_config))
        
        # Test single evaluation
        genome = neat.population[0]
        metrics = evaluate_genome(genome, Config(test_config), WORKER_ID)
        print(f"Test evaluation: {metrics}")


if __name__ == "__main__":
    main()