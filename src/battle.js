// Attack mode: the arm-guard hologram view of an enemy kingdom.
// Troops use a small rule-based AI (GDD section 10) and the player can
// direct them mid-battle: focus a target, hold, or proceed.
import { BUILDINGS, UNITS, TILE, WORLD, BATTLE_TIME } from './config.js';
import { canPlace, buildingAt } from './state.js';
import { rng } from './pixel.js';
import { buildCostGrid, findPath, ringAround } from './pathfind.js';

const CENTER = (b) => { const d = BUILDINGS[b.type]; return { x: (b.x + d.w / 2) * TILE, y: (b.y + d.h / 2) * TILE }; };

function distToRect(px, py, b) {
  const d = BUILDINGS[b.type];
  const x0 = b.x * TILE, y0 = b.y * TILE, x1 = x0 + d.w * TILE, y1 = y0 + d.h * TILE;
  const dx = Math.max(x0 - px, 0, px - x1), dy = Math.max(y0 - py, 0, py - y1);
  return Math.hypot(dx, dy);
}

// ---------------------------------------------------------------------------
export function generateEnemyBase(k) {
  const r = rng(k.seed);
  const list = [];
  let id = 1;
  const put = (type, x, y) => {
    if (!canPlace(list, type, x, y)) return null;
    const b = { id: id++, type, x, y, level: 1, buildRemaining: 0, hp: BUILDINGS[type].hp, maxHp: BUILDINGS[type].hp, stored: 0 };
    list.push(b); return b;
  };
  const ring = (x0, y0, x1, y1, gates) => {
    for (let x = x0; x <= x1; x++) { put('wall', x, y0); put('wall', x, y1); }
    for (let y = y0 + 1; y < y1; y++) { put('wall', x0, y); put('wall', x1, y); }
    for (const g of gates) list.splice(list.findIndex(b => b.type === 'wall' && b.x === g.x && b.y === g.y), 1);
  };
  put('castle', 20, 20);
  put('serge_storage', 16, 16); put('jade_storage', 26, 16);
  const cannonSpots = [[17, 25], [25, 25], [21, 15], [15, 20]];
  for (let i = 0; i < k.cannons; i++) put('cannon', cannonSpots[i][0], cannonSpots[i][1]);
  put('barracks_h', 25, 21) || put('guard_station', 26, 21);
  ring(14, 14, 29, 29, [{ x: 14 + 2 + Math.floor(r() * 12), y: 29 }]);
  if (k.wallRing > 1) ring(12, 12, 31, 31, [{ x: 12, y: 14 + Math.floor(r() * 16) }, { x: 31, y: 14 + Math.floor(r() * 16) }]);
  const outer = [[8, 9], [33, 9], [8, 32], [33, 32], [20, 7], [20, 34], [6, 20], [35, 20]];
  put('serge_mine', ...outer[0]); put('jade_mine', ...outer[1]); put('serge_mine', ...outer[2]); put('jade_mine', ...outer[3]);
  put('farm', 18, 35); put('guard_station', 8, 20); put('outpost', 33, 20);
  let placed = 0, tries = 0;
  while (placed < k.homes && tries++ < 200) {
    const x = 6 + Math.floor(r() * 32), y = 6 + Math.floor(r() * 32);
    if (x > 10 && x < 32 && y > 10 && y < 32) continue;
    if (put('home', x, y)) placed++;
  }
  return list;
}

// ---------------------------------------------------------------------------
export class Battle {
  constructor(kingdom, roster, kingReady) {
    this.kingdom = kingdom;
    this.buildings = generateEnemyBase(kingdom);
    this.grid = buildCostGrid(this.buildings);
    this.units = [];
    this.projectiles = [];
    this.effects = [];
    this.timeLeft = BATTLE_TIME;
    this.started = false;
    this.ended = false;
    this.endReason = '';
    this.elapsed = 0;
    this.selected = null;
    this.available = roster.map(u => ({ id: u.id, type: u.type }));
    this.kingAvailable = kingReady;
    this.kingDeployed = false;
    this.nextId = 1;
    this.lootTotal = { ...kingdom.loot };
    this.lootWeights = 0;
    for (const b of this.buildings) this.lootWeights += BUILDINGS[b.type].loot || 0;
    this.loot = { serge: 0, jade: 0 };
    this.emptyTimer = 0;
  }

  get countable() { return this.buildings.filter(b => !BUILDINGS[b.type].wall && !BUILDINGS[b.type].passable); }
  get destruction() { const c = this.countable; return c.filter(b => b.hp <= 0).length / c.length; }
  get castleDown() { const c = this.buildings.find(b => b.type === 'castle'); return c.hp <= 0; }
  get stars() { let s = 0; if (this.destruction >= 0.5) s++; if (this.castleDown) s++; if (this.destruction >= 1) s++; return s; }

  availableCounts() {
    const c = {};
    for (const u of this.available) c[u.type] = (c[u.type] || 0) + 1;
    return c;
  }

  canDeployAt(tx, ty) {
    if (tx < 1 || ty < 1 || tx >= WORLD - 1 || ty >= WORLD - 1) return false;
    for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
      const b = buildingAt(this.buildings, tx + i, ty + j);
      if (b && b.hp > 0) return false;
    }
    return true;
  }

  deploy(type, tx, ty) {
    if (this.ended) return 'The battle is over.';
    if (!this.canDeployAt(tx, ty)) return 'Deploy away from enemy buildings.';
    let rosterId = null;
    if (type === 'king') {
      if (!this.kingAvailable || this.kingDeployed) return 'The King is not available.';
      this.kingDeployed = true;
    } else {
      const idx = this.available.findIndex(u => u.type === type);
      if (idx < 0) return 'No more of those.';
      rosterId = this.available[idx].id;
      this.available.splice(idx, 1);
    }
    const def = UNITS[type];
    const u = {
      id: this.nextId++, rosterId, type, x: tx * TILE + TILE / 2 + (Math.random() * 6 - 3), y: ty * TILE + TILE / 2 + (Math.random() * 6 - 3),
      hp: def.hp, maxHp: def.hp, cooldown: 0, target: null, tempTarget: null, path: null, pathT: 0, repath: 0,
      directive: 'auto', focusId: null, moveTo: null, facing: 1, anim: Math.random() * 10, dead: false, hitFlash: 0,
    };
    this.units.push(u);
    this.started = true;
    return null;
  }

  // --- player directives ---------------------------------------------------
  unitAt(px, py) {
    let best = null, bd = 12;
    for (const u of this.units) { if (u.dead) continue; const d = Math.hypot(u.x - px, u.y - (py + 5)); if (d < bd) { bd = d; best = u; } }
    return best;
  }
  focus(building, unit = null) {
    const targets = unit ? [unit] : this.units.filter(u => !u.dead);
    for (const u of targets) { u.directive = 'focus'; u.focusId = building.id; u.target = null; u.path = null; u.moveTo = null; }
  }
  hold(unit = null) {
    for (const u of (unit ? [unit] : this.units)) { if (!u.dead) { u.directive = 'hold'; u.path = null; u.moveTo = null; } }
  }
  proceed(unit = null) {
    for (const u of (unit ? [unit] : this.units)) { if (!u.dead) { u.directive = 'auto'; u.focusId = null; u.target = null; u.path = null; u.moveTo = null; } }
  }
  moveKing(px, py) {
    const k = this.units.find(u => u.type === 'king' && !u.dead);
    if (!k) return;
    const tx = Math.floor(px / TILE), ty = Math.floor(py / TILE);
    if (tx < 0 || ty < 0 || tx >= WORLD || ty >= WORLD || this.grid[ty * WORLD + tx] === -1) return;
    k.directive = 'move'; k.moveTo = { x: tx, y: ty }; k.target = null; k.tempTarget = null;
    k.path = findPath(this.grid, Math.floor(k.x / TILE), Math.floor(k.y / TILE), [{ x: tx, y: ty }]);
    k.pathT = 0;
  }

  // --- simulation ----------------------------------------------------------------
  update(dt) {
    if (this.ended) return;
    if (this.started) { this.timeLeft -= dt; this.elapsed += dt; }
    for (const u of this.units) if (!u.dead) this.updateUnit(u, dt);
    this.separate();
    for (const b of this.buildings) if (b.type === 'cannon' && b.hp > 0) this.updateCannon(b, dt);
    this.updateProjectiles(dt);
    for (const e of this.effects) e.t -= dt;
    this.effects = this.effects.filter(e => e.t > 0);

    if (this.timeLeft <= 0) return this.end('Time is up.');
    if (this.destruction >= 1) return this.end('Total victory. The kingdom lies in ruins.');
    if (this.started && !this.units.some(u => !u.dead) && this.available.length === 0 && (!this.kingAvailable || this.kingDeployed)) {
      this.emptyTimer += dt;
      if (this.emptyTimer > 1.5) return this.end('Your army has fallen.');
    }
  }

  end(reason) {
    this.ended = true; this.endReason = reason;
  }

  aliveBuildings(filter) { return this.buildings.filter(b => b.hp > 0 && !BUILDINGS[b.type].passable && (!filter || filter(b))); }

  nearest(u, list) {
    let best = null, bd = Infinity;
    for (const b of list) { const d = distToRect(u.x, u.y, b); if (d < bd) { bd = d; best = b; } }
    return best;
  }

  chooseTarget(u) {
    const def = UNITS[u.type];
    if (u.directive === 'focus') {
      const f = this.buildings.find(b => b.id === u.focusId);
      if (f && f.hp > 0) return f;
      u.directive = 'auto'; u.focusId = null;
    }
    const nonWall = this.aliveBuildings(b => !BUILDINGS[b.type].wall);
    if (!nonWall.length) return this.aliveBuildings()[0] || null;
    if (def.prefer === 'defense') { const c = nonWall.filter(b => b.type === 'cannon'); if (c.length) return this.nearest(u, c); }
    if (def.prefer === 'resource') { const c = nonWall.filter(b => BUILDINGS[b.type].loot); if (c.length) return this.nearest(u, c); }
    return this.nearest(u, nonWall);
  }

  updateUnit(u, dt) {
    const def = UNITS[u.type];
    u.cooldown = Math.max(0, u.cooldown - dt);
    u.hitFlash = Math.max(0, u.hitFlash - dt);
    u.repath -= dt;

    // 1. who am I attacking? (a wall in the way takes priority)
    if (u.tempTarget && u.tempTarget.hp <= 0) { u.tempTarget = null; u.path = null; }
    if (u.target && u.target.hp <= 0) { u.target = null; u.path = null; }
    if (u.directive !== 'move' && !u.target) {
      u.target = this.chooseTarget(u);
      u.path = null;
      if (!u.target) return;
    }
    const atk = u.tempTarget || (u.directive === 'move' ? null : u.target);

    // 2. in range? then attack
    if (atk && distToRect(u.x, u.y, atk) <= def.range + 4) {
      u.anim += dt * 6;
      u.facing = CENTER(atk).x >= u.x ? 1 : -1;
      if (u.cooldown <= 0) {
        u.cooldown = def.rate;
        if (def.range > 10) this.projectiles.push({ kind: def.element === 'fire' ? 'fire' : 'water', x: u.x, y: u.y - 6, target: atk, speed: 140, damage: def.atk, fromUnit: true });
        else this.damageBuilding(atk, def.atk);
      }
      return;
    }
    if (u.directive === 'hold') return;

    // 3. otherwise walk along a path
    if (u.directive !== 'move' && !u.path && u.target && u.repath <= 0) {
      u.repath = 1.5;
      u.path = findPath(this.grid, Math.floor(u.x / TILE), Math.floor(u.y / TILE), ringAround(u.target, this.grid));
      u.pathT = 0;
      if (!u.path) { u.target = null; return; }
    }
    if (!u.path || u.pathT >= u.path.length) {
      if (u.directive === 'move') { u.directive = 'auto'; u.moveTo = null; }
      return;
    }
    const node = u.path[u.pathT];
    // a wall in the way: attack it first (only if it's still standing)
    const wallHere = buildingAt(this.buildings, node.x, node.y);
    if (wallHere && wallHere.hp > 0 && BUILDINGS[wallHere.type].wall && u.directive !== 'move') { u.tempTarget = wallHere; return; }
    const gx = node.x * TILE + TILE / 2, gy = node.y * TILE + TILE / 2;
    const dx = gx - u.x, dy = gy - u.y, dist = Math.hypot(dx, dy);
    const step = def.speed * dt;
    if (dist <= step) { u.x = gx; u.y = gy; u.pathT++; }
    else { u.x += dx / dist * step; u.y += dy / dist * step; }
    if (Math.abs(dx) > 0.5) u.facing = dx > 0 ? 1 : -1;
    u.anim += dt * 8;
  }

  // keep troops from stacking on the exact same pixel
  separate() {
    const alive = this.units.filter(u => !u.dead);
    for (let i = 0; i < alive.length; i++) for (let j = i + 1; j < alive.length; j++) {
      const a = alive[i], b = alive[j];
      let dx = b.x - a.x, dy = b.y - a.y;
      const d = Math.hypot(dx, dy);
      if (d >= 6) continue;
      if (d < 0.01) { dx = (i % 2 ? 1 : -1); dy = (j % 2 ? 1 : -1); }
      else { dx /= d; dy /= d; }
      a.x -= dx * 0.4; a.y -= dy * 0.4; b.x += dx * 0.4; b.y += dy * 0.4;
    }
  }

  damageBuilding(b, dmg) {
    if (b.hp <= 0) return;
    b.hp -= dmg;
    b.hitFlash = 0.1;
    if (b.hp <= 0) {
      b.hp = 0;
      this.effects.push({ kind: 'smoke', x: CENTER(b).x, y: CENTER(b).y, t: 1.2 });
      const w = BUILDINGS[b.type].loot || 0;
      if (w && this.lootWeights) for (const k in this.lootTotal) this.loot[k] += Math.round(this.lootTotal[k] * w / this.lootWeights);
      if (!BUILDINGS[b.type].passable) this.grid = buildCostGrid(this.buildings);
      for (const u of this.units) { if (u.target === b || u.tempTarget === b) { u.path = null; u.repath = 0; } }
    }
  }

  updateCannon(b, dt) {
    const d = BUILDINGS.cannon.defense;
    b.cool = Math.max(0, (b.cool || 0) - dt);
    const c = CENTER(b);
    let best = null, bd = d.range * TILE;
    for (const u of this.units) { if (u.dead) continue; const dist = Math.hypot(u.x - c.x, u.y - c.y); if (dist < bd) { bd = dist; best = u; } }
    b.aim = best;
    if (!best || b.cool > 0) return;
    b.cool = d.rate;
    this.projectiles.push({ kind: 'cannon', x: c.x + 6, y: c.y - 4, targetUnit: best, speed: 220, damage: d.damage });
    this.effects.push({ kind: 'flash', x: c.x + 8, y: c.y - 2, t: 0.08 });
  }

  updateProjectiles(dt) {
    for (const p of this.projectiles) {
      let tx, ty;
      if (p.targetUnit) { if (p.targetUnit.dead) { p.done = true; continue; } tx = p.targetUnit.x; ty = p.targetUnit.y - 5; }
      else { const c = CENTER(p.target); tx = c.x; ty = c.y; }
      const dx = tx - p.x, dy = ty - p.y, dist = Math.hypot(dx, dy), step = p.speed * dt;
      if (dist <= step) {
        p.done = true;
        if (p.targetUnit) this.damageUnit(p.targetUnit, p.damage);
        else this.damageBuilding(p.target, p.damage);
        this.effects.push({ kind: p.kind === 'cannon' ? 'hit' : 'magic', x: tx, y: ty, t: 0.2 });
      } else { p.x += dx / dist * step; p.y += dy / dist * step; }
    }
    this.projectiles = this.projectiles.filter(p => !p.done);
  }

  damageUnit(u, dmg) {
    const def = UNITS[u.type];
    u.hp -= dmg * (1 - (def.armor || 0));
    u.hitFlash = 0.12;
    if (u.hp <= 0) {
      u.hp = 0; u.dead = true;
      if (this.selected === u) this.selected = null;
      this.effects.push({ kind: 'fall', x: u.x, y: u.y, t: 0.8, unit: u.type, facing: u.facing });
    }
  }

  result() {
    const fallen = this.units.filter(u => u.dead).map(u => ({ id: u.rosterId, type: u.type }));
    return {
      enemyName: this.kingdom.name, stars: this.stars, destruction: this.destruction, loot: { ...this.loot },
      fallen, survivors: this.units.filter(u => !u.dead).length, reason: this.endReason,
    };
  }
}
