extends RefCounted
class_name NSGA2

## NSGA-II (Non-dominated Sorting Genetic Algorithm II)
## Multi-objective selection using Pareto dominance, non-dominated sorting,
## and crowding distance for diversity preservation.
##
## References:
##   Deb et al., "A Fast and Elitist Multiobjective Genetic Algorithm: NSGA-II" (2002)

## Number of objectives (survival_time, kill_score, powerup_score)
const NUM_OBJECTIVES := 3


static func dominates(a: Vector3, b: Vector3) -> bool:
	## Returns true if solution 'a' dominates solution 'b'.
	## A dominates B iff A >= B on ALL objectives AND A > B on at least one.
	var dominated_strictly := false
	if a.x < b.x or a.y < b.y or a.z < b.z:
		return false
	if a.x > b.x or a.y > b.y or a.z > b.z:
		dominated_strictly = true
	return dominated_strictly


static func non_dominated_sort(objectives: Array) -> Array:
	## Perform fast non-dominated sorting on a population.
	## Input: Array of Vector3 (one per individual)
	## Output: Array of Arrays — each sub-array is a front of individual indices.
	##   fronts[0] = Pareto-optimal (front rank 0)
	##   fronts[1] = next best, etc.
	## Complexity: O(MN²) where M=objectives, N=population size.
	
	var n := objectives.size()
	if n == 0:
		return []
	
	# For each individual: which individuals it dominates, and how many dominate it
	var domination_count: PackedInt32Array = PackedInt32Array()
	domination_count.resize(n)
	var dominated_set: Array = []  # Array of PackedInt32Array
	
	for i in n:
		dominated_set.append(PackedInt32Array())
		domination_count[i] = 0
	
	# Pairwise comparison
	for i in n:
		for j in range(i + 1, n):
			if dominates(objectives[i], objectives[j]):
				dominated_set[i].append(j)
				domination_count[j] += 1
			elif dominates(objectives[j], objectives[i]):
				dominated_set[j].append(i)
				domination_count[i] += 1
	
	# Build fronts
	var fronts: Array = []
	var current_front: Array = []
	
	for i in n:
		if domination_count[i] == 0:
			current_front.append(i)
	
	while not current_front.is_empty():
		fronts.append(current_front.duplicate())
		var next_front: Array = []
		for i in current_front:
			for j in dominated_set[i]:
				domination_count[j] -= 1
				if domination_count[j] == 0:
					next_front.append(j)
		current_front = next_front
	
	return fronts


static func crowding_distance(front: Array, objectives: Array) -> PackedFloat32Array:
	## Calculate crowding distance for individuals in a single front.
	## Input:
	##   front — Array of individual indices in this front
	##   objectives — Array of Vector3 for ALL individuals (indexed by individual index)
	## Output: PackedFloat32Array of crowding distances, one per front member (same order as front).
	
	var size := front.size()
	var distances := PackedFloat32Array()
	distances.resize(size)
	
	if size <= 2:
		for i in size:
			distances[i] = INF
		return distances
	
	# For each objective dimension, sort front members and assign distance
	for obj in NUM_OBJECTIVES:
		# Extract objective values for this dimension
		var obj_values: Array = []
		for i in size:
			var idx: int = front[i]
			var val: float
			match obj:
				0: val = objectives[idx].x
				1: val = objectives[idx].y
				2: val = objectives[idx].z
				_: val = 0.0
			obj_values.append({"front_pos": i, "value": val})
		
		# Sort by this objective
		obj_values.sort_custom(func(a, b): return a.value < b.value)
		
		# Boundary individuals get infinite distance
		distances[obj_values[0].front_pos] = INF
		distances[obj_values[size - 1].front_pos] = INF
		
		# Range for normalization
		var obj_range: float = obj_values[size - 1].value - obj_values[0].value
		if obj_range <= 0.0:
			continue  # All same value for this objective, skip
		
		# Interior individuals
		for i in range(1, size - 1):
			var dist: float = (obj_values[i + 1].value - obj_values[i - 1].value) / obj_range
			distances[obj_values[i].front_pos] += dist
	
	return distances


static func select(objectives: Array, target_size: int) -> Array:
	## NSGA-II environmental selection.
	## Input:
	##   objectives — Array of Vector3 for each individual
	##   target_size — number of individuals to select
	## Output: Array of selected individual indices.
	
	var n := objectives.size()
	if target_size >= n:
		var all: Array = []
		for i in n:
			all.append(i)
		return all
	
	var fronts := non_dominated_sort(objectives)
	var selected: Array = []
	
	for front in fronts:
		if selected.size() + front.size() <= target_size:
			# Entire front fits
			selected.append_array(front)
		else:
			# Partial front — select by crowding distance
			var remaining := target_size - selected.size()
			var distances := crowding_distance(front, objectives)
			
			# Create index-distance pairs and sort descending by distance
			var indexed: Array = []
			for i in front.size():
				indexed.append({"idx": front[i], "dist": distances[i]})
			indexed.sort_custom(func(a, b): return a.dist > b.dist)
			
			for i in remaining:
				selected.append(indexed[i].idx)
			break
	
	return selected


static func build_rank_map(fronts: Array, pop_size: int) -> PackedInt32Array:
	## Build a flat lookup array: individual index → front rank.
	## Call once after non_dominated_sort, then pass to tournament_select.
	var ranks := PackedInt32Array()
	ranks.resize(pop_size)
	ranks.fill(fronts.size())  # Default: worst rank
	for rank in fronts.size():
		for idx in fronts[rank]:
			if idx < pop_size:
				ranks[idx] = rank
	return ranks


static func tournament_select(objectives: Array, fronts: Array, crowding: Dictionary, rng: RandomNumberGenerator = null, rank_map: PackedInt32Array = PackedInt32Array()) -> int:
	## Binary tournament selection using NSGA-II crowded comparison.
	## Input:
	##   objectives — Array of Vector3
	##   fronts — result of non_dominated_sort (for rank lookup)
	##   crowding — Dictionary {individual_index: crowding_distance}
	##   rng — optional RNG
	##   rank_map — optional precomputed rank lookup (from build_rank_map)
	## Output: index of selected individual.
	
	var n := objectives.size()
	var a: int
	var b: int
	if rng:
		a = rng.randi() % n
		b = rng.randi() % n
	else:
		a = randi() % n
		b = randi() % n
	
	var rank_a: int
	var rank_b: int
	if rank_map.size() > 0:
		rank_a = rank_map[a] if a < rank_map.size() else fronts.size()
		rank_b = rank_map[b] if b < rank_map.size() else fronts.size()
	else:
		rank_a = _get_front_rank(a, fronts)
		rank_b = _get_front_rank(b, fronts)
	
	# Prefer lower rank (better front)
	if rank_a < rank_b:
		return a
	elif rank_b < rank_a:
		return b
	else:
		# Same rank — prefer higher crowding distance
		var dist_a: float = crowding.get(a, 0.0)
		var dist_b: float = crowding.get(b, 0.0)
		return a if dist_a >= dist_b else b


static func _get_front_rank(individual: int, fronts: Array) -> int:
	## Find which front rank an individual belongs to.
	## Note: Prefer using build_rank_map() + rank_map parameter for hot loops.
	for rank in fronts.size():
		if individual in fronts[rank]:
			return rank
	return fronts.size()  # Not found — worst rank


static func get_pareto_front(objectives: Array) -> Array:
	## Convenience: return just the Pareto-optimal individuals (front 0).
	## Returns Array of {index: int, objectives: Vector3}.
	var fronts := non_dominated_sort(objectives)
	if fronts.is_empty():
		return []
	var result: Array = []
	for idx in fronts[0]:
		result.append({"index": idx, "objectives": objectives[idx]})
	return result


static func hypervolume_2d(front: Array, ref_point: Vector2) -> float:
	## Calculate 2D hypervolume indicator for a Pareto front (maximization).
	## Input:
	##   front — Array of Vector2 (2 objectives per individual on the front)
	##   ref_point — reference point (should be dominated by all front members,
	##               i.e. worse than all of them on both objectives)
	## Output: hypervolume value (area dominated by the front above ref_point).
	
	if front.is_empty():
		return 0.0
	
	# Filter to points that dominate the reference point (both objectives > ref)
	var valid: Array = []
	for point in front:
		if point.x > ref_point.x and point.y > ref_point.y:
			valid.append(point)
	
	if valid.is_empty():
		return 0.0
	
	# Sort by x descending for sweep-line algorithm
	valid.sort_custom(func(a, b): return a.x > b.x)
	
	var hv := 0.0
	var prev_y := ref_point.y
	
	for point in valid:
		if point.y > prev_y:
			hv += (point.x - ref_point.x) * (point.y - prev_y)
			prev_y = point.y
	
	return hv
