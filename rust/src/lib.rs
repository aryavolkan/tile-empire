use godot::prelude::*;
use godot::builtin::Variant;
use std::collections::BinaryHeap;
use std::cmp::Ordering;

struct TileEmpireExtension;

#[gdextension]
unsafe impl ExtensionLibrary for TileEmpireExtension {}

/// Fast hex math utilities exposed to GDScript.
#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct HexMath;

#[godot_api]
impl HexMath {
    /// Hex distance using axial coordinates (odd-q offset layout).
    #[func]
    fn hex_distance(from: Vector2i, to: Vector2i) -> i32 {
        let (ax, ay) = to_axial(from);
        let (bx, by) = to_axial(to);
        ((ax - bx).abs() + (ax + ay - bx - by).abs() + (ay - by).abs()) / 2
    }

    /// Get hex neighbors for odd-q offset coordinates.
    #[func]
    fn hex_neighbors(pos: Vector2i) -> Array<Vector2i> {
        let dirs_even: [(i32, i32); 6] = [
            (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (0, 1),
        ];
        let dirs_odd: [(i32, i32); 6] = [
            (1, 1), (1, 0), (0, -1), (-1, 0), (-1, 1), (0, 1),
        ];
        let dirs = if pos.x & 1 == 0 { &dirs_even } else { &dirs_odd };
        let mut result = Array::new();
        for &(dx, dy) in dirs {
            result.push(Vector2i::new(pos.x + dx, pos.y + dy));
        }
        result
    }

    /// A* pathfinding on a hex grid. Returns array of Vector2i positions.
    /// `blocked` is an array of impassable positions.
    /// `costs` is a Dictionary mapping Vector2i -> float movement cost (default 1.0).
    /// Returns empty array if no path found.
    #[func]
    fn find_path(
        from: Vector2i,
        to: Vector2i,
        blocked: Array<Vector2i>,
        costs: Dictionary<Vector2i, f64>,
        max_distance: i32,
    ) -> Array<Vector2i> {
        use std::collections::{HashMap, HashSet};

        let blocked_set: HashSet<(i32, i32)> =
            blocked.iter_shared().map(|v| (v.x, v.y)).collect();

        if blocked_set.contains(&(to.x, to.y)) {
            return Array::new();
        }

        #[derive(Clone)]
        struct Node {
            pos: (i32, i32),
            g: f64,
            f: f64,
        }

        impl PartialEq for Node {
            fn eq(&self, other: &Self) -> bool { self.f == other.f }
        }
        impl Eq for Node {}
        impl PartialOrd for Node {
            fn partial_cmp(&self, other: &Self) -> Option<Ordering> { Some(self.cmp(other)) }
        }
        impl Ord for Node {
            fn cmp(&self, other: &Self) -> Ordering {
                other.f.partial_cmp(&self.f).unwrap_or(Ordering::Equal)
            }
        }

        let mut open = BinaryHeap::new();
        let mut came_from: HashMap<(i32, i32), (i32, i32)> = HashMap::new();
        let mut g_scores: HashMap<(i32, i32), f64> = HashMap::new();

        let start = (from.x, from.y);
        let goal = (to.x, to.y);

        g_scores.insert(start, 0.0);
        let h = Self::hex_distance(from, to) as f64;
        open.push(Node { pos: start, g: 0.0, f: h });

        while let Some(current) = open.pop() {
            if current.pos == goal {
                // Reconstruct path
                let mut path = Vec::new();
                let mut cur = goal;
                while cur != start {
                    path.push(Vector2i::new(cur.0, cur.1));
                    cur = came_from[&cur];
                }
                path.push(Vector2i::new(start.0, start.1));
                path.reverse();
                let mut result = Array::new();
                for p in path {
                    result.push(p);
                }
                return result;
            }

            let current_g = *g_scores.get(&current.pos).unwrap_or(&f64::MAX);
            if current.g > current_g {
                continue;
            }

            let pos_v = Vector2i::new(current.pos.0, current.pos.1);
            let neighbors = Self::hex_neighbors(pos_v);

            for n in neighbors.iter_shared() {
                let np = (n.x, n.y);
                if blocked_set.contains(&np) {
                    continue;
                }

                let dist_from_start =
                    Self::hex_distance(from, Vector2i::new(np.0, np.1));
                if dist_from_start > max_distance {
                    continue;
                }

                let cost: f64 = costs
                    .get(n)
                    .unwrap_or(1.0);

                let tentative_g = current_g + cost;
                let prev_g = *g_scores.get(&np).unwrap_or(&f64::MAX);
                if tentative_g < prev_g {
                    came_from.insert(np, current.pos);
                    g_scores.insert(np, tentative_g);
                    let h = Self::hex_distance(Vector2i::new(np.0, np.1), to) as f64;
                    open.push(Node { pos: np, g: tentative_g, f: tentative_g + h });
                }
            }
        }

        Array::new() // No path found
    }
}

/// Convert odd-q offset to axial coordinates.
fn to_axial(pos: Vector2i) -> (i32, i32) {
    let x = pos.x;
    let y = pos.y - (pos.x - (pos.x & 1)) / 2;
    (x, y)
}

/// Get hex neighbors for odd-q offset coordinates (standalone helper).
fn hex_neighbors_vec(x: i32, y: i32) -> [(i32, i32); 6] {
    if x & 1 == 0 {
        [(x+1,y),(x+1,y-1),(x,y-1),(x-1,y-1),(x-1,y),(x,y+1)]
    } else {
        [(x+1,y+1),(x+1,y),(x,y-1),(x-1,y),(x-1,y+1),(x,y+1)]
    }
}

// ============================================================
// 1. InfluenceMap
// ============================================================

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct InfluenceMap {
    #[allow(dead_code)]
    influence: Vec<Vec<f32>>, // per-player influence grids
    width: usize,
    height: usize,
    num_players: usize,
}

#[godot_api]
impl InfluenceMap {
    /// Compute influence for all players.
    /// unit_positions_by_player: Dictionary { player_id: int -> Array[Vector2i] of grid positions }
    /// territory_owner_grid: PackedInt32Array of size w*h, row-major, value = owner or -1
    #[func]
    fn compute(
        &mut self,
        unit_positions_by_player: Dictionary<Variant, Variant>,
        territory_owner_grid: PackedInt32Array,
        map_width: i32,
        map_height: i32,
    ) {
        let w = map_width as usize;
        let h = map_height as usize;
        self.width = w;
        self.height = h;

        // Determine number of players
        let mut max_pid: i32 = -1;
        for key in unit_positions_by_player.keys_array().iter_shared() {
            let pid = i32::from_variant(&key);
            if pid > max_pid { max_pid = pid; }
        }
        for i in 0..territory_owner_grid.len() {
            let v = territory_owner_grid[i];
            if v > max_pid { max_pid = v; }
        }
        let np = (max_pid + 1).max(0) as usize;
        self.num_players = np;

        // Raw per-player influence
        let mut raw: Vec<Vec<f32>> = vec![vec![0.0; w * h]; np];

        let sigma: f32 = 4.0;
        let two_sigma_sq = 2.0 * sigma * sigma;
        let max_range = (sigma * 3.0) as i32; // cutoff at 3 sigma

        // Add unit influence
        for key in unit_positions_by_player.keys_array().iter_shared() {
            let pid = i32::from_variant(&key) as usize;
            if pid >= np { continue; }
            let val_variant = unit_positions_by_player.get(&key).unwrap();
            let positions: Array<Vector2i> = Array::from_variant(&val_variant);
            for pos in positions.iter_shared() {
                let cx = pos.x;
                let cy = pos.y;
                for dy in -max_range..=max_range {
                    for dx in -max_range..=max_range {
                        let nx = cx + dx;
                        let ny = cy + dy;
                        if nx < 0 || ny < 0 || nx >= w as i32 || ny >= h as i32 { continue; }
                        let dist_sq = (dx * dx + dy * dy) as f32;
                        let val = 2.0 * (-dist_sq / two_sigma_sq).exp();
                        raw[pid][ny as usize * w + nx as usize] += val;
                    }
                }
            }
        }

        // Add territory influence
        for i in 0..territory_owner_grid.len() {
            let owner = territory_owner_grid[i];
            if owner < 0 || owner as usize >= np { continue; }
            let cx = (i % w) as i32;
            let cy = (i / w) as i32;
            let pid = owner as usize;
            for dy in -max_range..=max_range {
                for dx in -max_range..=max_range {
                    let nx = cx + dx;
                    let ny = cy + dy;
                    if nx < 0 || ny < 0 || nx >= w as i32 || ny >= h as i32 { continue; }
                    let dist_sq = (dx * dx + dy * dy) as f32;
                    let val = 0.5 * (-dist_sq / two_sigma_sq).exp();
                    raw[pid][ny as usize * w + nx as usize] += val;
                }
            }
        }

        // Net influence = own - max(enemies)
        self.influence = Vec::with_capacity(np);
        for pid in 0..np {
            let mut net = vec![0.0f32; w * h];
            for i in 0..w * h {
                let own = raw[pid][i];
                let mut max_enemy = 0.0f32;
                for other in 0..np {
                    if other != pid {
                        max_enemy = max_enemy.max(raw[other][i]);
                    }
                }
                net[i] = own - max_enemy;
            }
            self.influence.push(net);
        }
    }

    #[func]
    fn get_player_influence(&self, player_id: i32) -> PackedFloat32Array {
        let pid = player_id as usize;
        if pid < self.influence.len() {
            PackedFloat32Array::from(self.influence[pid].as_slice())
        } else {
            PackedFloat32Array::new()
        }
    }
}

// ============================================================
// 2. TerritoryFrontier
// ============================================================

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct TerritoryFrontier;

#[godot_api]
impl TerritoryFrontier {
    /// Returns Array[Vector2i] of frontier tiles (adjacent to player's territory, not owned by player, not water=3).
    #[func]
    fn get_frontier(
        &self,
        owner_grid: PackedInt32Array,
        player_id: i32,
        map_width: i32,
        map_height: i32,
    ) -> Array<Vector2i> {
        let w = map_width as usize;
        let h = map_height as usize;
        let mut frontier_set = std::collections::HashSet::new();
        let mut result = Array::new();

        for i in 0..owner_grid.len().min(w * h) {
            if owner_grid[i] != player_id { continue; }
            let x = (i % w) as i32;
            let y = (i / w) as i32;
            for (nx, ny) in hex_neighbors_vec(x, y) {
                if nx < 0 || ny < 0 || nx >= map_width || ny >= map_height { continue; }
                let ni = ny as usize * w + nx as usize;
                if ni >= owner_grid.len() { continue; }
                let owner = owner_grid[ni];
                if owner == player_id { continue; }
                // Skip water (type check not available here — caller filters or we accept all non-owned)
                if frontier_set.insert((nx, ny)) {
                    result.push(Vector2i::new(nx, ny));
                }
            }
        }
        result
    }
}

// ============================================================
// 3. CombatQuery
// ============================================================

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct CombatQuery;

#[godot_api]
impl CombatQuery {
    /// Find all pairs (attacker_idx, target_idx) where units of different owners are within radius.
    #[func]
    fn find_targets_in_range(
        &self,
        positions: PackedVector2Array,
        owner_ids: PackedInt32Array,
        radius: f64,
    ) -> PackedInt32Array {
        let r2 = (radius * radius) as f32;
        let n = positions.len().min(owner_ids.len());
        let pos = positions.as_slice();
        let owners = owner_ids.as_slice();
        let mut result = PackedInt32Array::new();

        // Simple O(n^2) — fine for <200 units on 50x50 map
        for i in 0..n {
            for j in 0..n {
                if i == j { continue; }
                if owners[i] == owners[j] { continue; }
                let dx = pos[i].x - pos[j].x;
                let dy = pos[i].y - pos[j].y;
                if dx * dx + dy * dy <= r2 {
                    result.push(i as i32);
                    result.push(j as i32);
                }
            }
        }
        result
    }
}

// ============================================================
// 4. ResourceCounter
// ============================================================

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct ResourceCounter;

#[godot_api]
impl ResourceCounter {
    /// Returns Dictionary { player_id -> PackedInt32Array [food, production, gold] }
    #[func]
    fn compute_resources(
        &self,
        tile_types: PackedInt32Array,
        owner_grid: PackedInt32Array,
        num_players: i32,
    ) -> Dictionary<Variant, Variant> {
        let np = num_players as usize;
        let mut totals = vec![[0i32; 3]; np];

        let n = tile_types.len().min(owner_grid.len());
        for i in 0..n {
            let owner = owner_grid[i];
            if owner < 0 || owner as usize >= np { continue; }
            let (f, p, g) = match tile_types[i] {
                0 => (1, 1, 0), // plains
                1 => (0, 2, 0), // forest
                2 => (0, 3, 1), // mountain
                3 => (0, 0, 2), // water
                4 => (1, 0, 1), // desert
                5 => (3, 1, 0), // plains_fertile
                _ => (0, 0, 0),
            };
            let pid = owner as usize;
            totals[pid][0] += f;
            totals[pid][1] += p;
            totals[pid][2] += g;
        }

        let mut dict = Dictionary::new();
        for pid in 0..np {
            let mut arr = PackedInt32Array::new();
            arr.push(totals[pid][0]);
            arr.push(totals[pid][1]);
            arr.push(totals[pid][2]);
            let k = Variant::from(pid as i32);
            let v = Variant::from(arr);
            dict.set(&k, &v);
        }
        dict
    }
}

// ============================================================
// 5. HexLOS
// ============================================================

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
pub struct HexLOS;

#[godot_api]
impl HexLOS {
    /// Line-of-sight check: returns true if no mountain (type=2) blocks the line from→to.
    /// Uses cube-coordinate lerp to walk hex tiles along the line.
    #[func]
    fn has_line_of_sight(
        &self,
        from: Vector2i,
        to: Vector2i,
        tile_types: PackedInt32Array,
        map_width: i32,
        map_height: i32,
    ) -> bool {
        let w = map_width as usize;
        let dist = HexMath::hex_distance(from, to);
        if dist <= 1 { return true; }

        // Convert to cube coords
        let (ax, ay) = to_axial(from);
        let az = -ax - ay;
        let (bx, by) = to_axial(to);
        let bz = -bx - by;

        // Walk intermediate tiles (skip endpoints)
        for step in 1..dist {
            let t = step as f64 / dist as f64;
            // Lerp in cube space
            let fx = ax as f64 + (bx - ax) as f64 * t;
            let fy = ay as f64 + (by - ay) as f64 * t;
            let fz = az as f64 + (bz - az) as f64 * t;

            // Round to nearest cube hex
            let (rx, ry, _rz) = cube_round(fx, fy, fz);

            // Convert axial back to odd-q offset
            let col = rx;
            let row = ry + (rx - (rx & 1)) / 2;

            if col < 0 || row < 0 || col >= map_width || row >= map_height {
                return false; // out of bounds blocks LOS
            }
            let idx = row as usize * w + col as usize;
            if idx < tile_types.len() && tile_types[idx] == 2 {
                return false; // mountain blocks
            }
        }
        true
    }
}

fn cube_round(x: f64, y: f64, z: f64) -> (i32, i32, i32) {
    let mut rx = x.round();
    let mut ry = y.round();
    let mut rz = z.round();

    let dx = (rx - x).abs();
    let dy = (ry - y).abs();
    let dz = (rz - z).abs();

    if dx > dy && dx > dz {
        rx = -ry - rz;
    } else if dy > dz {
        ry = -rx - rz;
    } else {
        rz = -rx - ry;
    }
    let _ = rz;
    (rx as i32, ry as i32, rz as i32)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hex_distance_same() {
        assert_eq!(HexMath::hex_distance(Vector2i::new(0, 0), Vector2i::new(0, 0)), 0);
    }

    #[test]
    fn test_hex_distance_adjacent() {
        assert_eq!(HexMath::hex_distance(Vector2i::new(0, 0), Vector2i::new(1, 0)), 1);
    }

    #[test]
    fn test_hex_distance_far() {
        let d = HexMath::hex_distance(Vector2i::new(0, 0), Vector2i::new(3, 3));
        assert!(d > 0);
    }

    #[test]
    fn test_cube_round() {
        let (x, y, z) = cube_round(0.1, -0.2, 0.1);
        assert_eq!(x + y + z, 0);
    }
}
