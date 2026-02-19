use godot::prelude::*;
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
}
