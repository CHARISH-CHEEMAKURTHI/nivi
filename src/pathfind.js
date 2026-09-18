// A* over the base grid. Walls are passable at a high cost (troops will break
// through them if there's no cheaper way around), other buildings block
// movement entirely unless they are the goal.
import { WORLD, BUILDINGS } from './config.js';

export const WALL_COST = 30;

// cost grid: 0 = free, -1 = blocked, >0 = extra cost (walls)
export function buildCostGrid(buildings) {
  const g = new Int16Array(WORLD * WORLD);
  for (const b of buildings) {
    if (b.hp <= 0) continue;
    const d = BUILDINGS[b.type];
    if (d.passable) continue;
    const v = d.wall ? WALL_COST : -1;
    for (let j = 0; j < d.h; j++) for (let i = 0; i < d.w; i++) g[(b.y + j) * WORLD + b.x + i] = v;
  }
  return g;
}

// Tiles edge-adjacent to a building's footprint (the places a melee unit can
// stand and still reach it). Diagonal corners are left out: from there the
// building is out of arm's reach.
export function ringAround(b, grid = null) {
  const d = BUILDINGS[b.type];
  const out = [];
  for (let y = b.y - 1; y < b.y + d.h + 1; y++) for (let x = b.x - 1; x < b.x + d.w + 1; x++) {
    if (x >= b.x && x < b.x + d.w && y >= b.y && y < b.y + d.h) continue;
    const outsideX = x < b.x || x >= b.x + d.w, outsideY = y < b.y || y >= b.y + d.h;
    if (outsideX && outsideY) continue;
    if (x < 0 || y < 0 || x >= WORLD || y >= WORLD) continue;
    if (grid && grid[y * WORLD + x] === -1) continue;   // occupied by another building
    out.push({ x, y });
  }
  return out;
}

const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];

export function findPath(grid, sx, sy, goals, allowIds = null) {
  const N = WORLD;
  const goalSet = new Set(goals.map(g => g.y * N + g.x));
  if (goalSet.size === 0) return null;
  const start = sy * N + sx;
  if (goalSet.has(start)) return [{ x: sx, y: sy }];
  const gScore = new Float32Array(N * N).fill(Infinity);
  const from = new Int32Array(N * N).fill(-1);
  const closed = new Uint8Array(N * N);
  const h = (i) => {
    const x = i % N, y = (i / N) | 0;
    let best = Infinity;
    for (const g of goals) { const d = Math.max(Math.abs(g.x - x), Math.abs(g.y - y)); if (d < best) best = d; }
    return best;
  };
  const open = [start];
  const f = new Float32Array(N * N).fill(Infinity);
  gScore[start] = 0; f[start] = h(start);
  let iterations = 0;
  while (open.length && iterations++ < 6000) {
    // pick lowest f (grid is small, a linear scan is fine)
    let bi = 0;
    for (let i = 1; i < open.length; i++) if (f[open[i]] < f[open[bi]]) bi = i;
    const cur = open[bi]; open[bi] = open[open.length - 1]; open.pop();
    if (goalSet.has(cur)) {
      const path = [];
      for (let c = cur; c !== -1; c = from[c]) path.push({ x: c % N, y: (c / N) | 0 });
      return path.reverse();
    }
    closed[cur] = 1;
    const cx = cur % N, cy = (cur / N) | 0;
    for (const [dx, dy] of DIRS) {
      const nx = cx + dx, ny = cy + dy;
      if (nx < 0 || ny < 0 || nx >= N || ny >= N) continue;
      const ni = ny * N + nx;
      if (closed[ni]) continue;
      const cell = grid[ni];
      if (cell === -1 && !goalSet.has(ni)) continue;
      // no corner cutting through blocked tiles
      if (dx && dy) {
        const a = grid[cy * N + nx], b = grid[ny * N + cx];
        if (a === -1 || b === -1 || a > 0 || b > 0) continue;
      }
      const step = (dx && dy ? 1.41 : 1) + (cell > 0 ? cell : 0);
      const ng = gScore[cur] + step;
      if (ng < gScore[ni]) {
        gScore[ni] = ng; from[ni] = cur; f[ni] = ng + h(ni);
        if (!open.includes(ni)) open.push(ni);
      }
    }
  }
  return null;
}
