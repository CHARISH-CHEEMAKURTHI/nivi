// Kingdom simulation: economy, construction, training, population, healing.
import { BUILDINGS, UNITS, DECREES, CREATURE_SLOTS, SEASON_SECONDS } from './config.js';
import { addBuilding, addCitizen, addUnit, canPlace, countType, log } from './state.js';

export function isBuilt(b) { return b.buildRemaining <= 0; }

// Aggregate everything the built structures provide.
export function capacities(s) {
  const cap = { storage: { serge: 0, jade: 0 }, popCap: 0, housing: 0, housingCav: 0, happiness: 0, healSpeed: 1, hospital: false };
  for (const b of s.buildings) {
    if (!isBuilt(b)) continue;
    const p = BUILDINGS[b.type].provides;
    if (!p) continue;
    if (p.storage) for (const k in p.storage) cap.storage[k] += p.storage[k];
    if (p.popCap) cap.popCap += p.popCap;
    if (p.housing) { if (p.housingFor === 'cavalry') cap.housingCav += p.housing; else cap.housing += p.housing; }
    if (p.happiness) cap.happiness += p.happiness;
    if (p.healSpeed) { cap.healSpeed = Math.max(cap.healSpeed, p.healSpeed); cap.hospital = true; }
  }
  return cap;
}

export function happiness(s) {
  const cap = capacities(s);
  let h = 50 + Math.min(cap.happiness, 40);
  const overcrowd = Math.max(0, s.citizens.length - cap.popCap);
  h -= overcrowd * 6;
  h += s.happinessMod;
  h += Math.max(-10, Math.min(10, s.credits / 4));
  return Math.max(0, Math.min(100, Math.round(h)));
}

export function productionMultiplier(s) { return 0.6 + happiness(s) / 100 * 0.8; }

// Housing used by units of a given housing pool ('army' or 'cavalry').
export function housingUsed(s, pool) {
  let used = 0;
  const count = (type) => { const u = UNITS[type]; if ((u.kind === 'human' && type === 'cavalry') === (pool === 'cavalry')) used += u.housing; };
  for (const u of s.army) count(u.type);
  for (const q of Object.values(s.queues)) for (const item of q) count(item.type);
  return used;
}

export function armySummary(s) {
  const cap = capacities(s);
  return {
    housing: housingUsed(s, 'army'), housingCap: cap.housing,
    cavalry: housingUsed(s, 'cavalry'), cavalryCap: cap.housingCav,
    ready: s.army.filter(u => u.status === 'ready').length,
    injured: s.army.filter(u => u.status === 'injured').length,
  };
}

// Section 6: creature allocation. Ready creatures bond to soldiers first
// (2 each), then to civilians (1 each). Purely informational for the demo.
export function bonding(s) {
  const creatures = s.army.filter(u => UNITS[u.type].kind === 'creature');
  const soldiers = s.army.filter(u => UNITS[u.type].kind === 'human');
  const map = new Map();
  let i = 0;
  for (const sol of soldiers) { map.set(sol.id, creatures.slice(i, i + CREATURE_SLOTS.soldier).map(c => c.id)); i += CREATURE_SLOTS.soldier; }
  const civilians = s.citizens.filter(c => c.profession !== 'Soldier');
  for (const c of civilians) { map.set(c.id, creatures.slice(i, i + CREATURE_SLOTS.civilian).map(c => c.id)); i += CREATURE_SLOTS.civilian; }
  return map;
}

// --- resources ---------------------------------------------------------------
export function canAfford(s, cost) { return Object.entries(cost || {}).every(([k, v]) => s.resources[k] >= v); }
export function spend(s, cost) { for (const k in cost) s.resources[k] -= cost[k]; }
export function addResources(s, delta) {
  const cap = capacities(s).storage;
  const gained = {};
  for (const k in delta) {
    const before = s.resources[k];
    s.resources[k] = Math.min(cap[k], s.resources[k] + delta[k]);
    gained[k] = s.resources[k] - before;
  }
  return gained;
}

export function collect(s, b) {
  const d = BUILDINGS[b.type];
  if (!d.produces || b.stored < 1) return 0;
  const amount = Math.floor(b.stored);
  const got = addResources(s, { [d.produces.resource]: amount });
  const taken = got[d.produces.resource];
  b.stored -= taken;
  return taken;
}

export function collectAll(s) {
  let total = { serge: 0, jade: 0 };
  for (const b of s.buildings) {
    const d = BUILDINGS[b.type];
    if (d.produces && isBuilt(b)) total[d.produces.resource] += collect(s, b);
  }
  return total;
}

// --- building actions ----------------------------------------------------------
export function placeError(s, type, x, y) {
  const d = BUILDINGS[type];
  if (!d || d.buildable === false) return 'Cannot build that.';
  if (countType(s, type) >= d.limit) return `Limit reached for ${d.name} at Castle Level One.`;
  if (!canAfford(s, d.cost)) return 'Not enough resources.';
  if (!canPlace(s.buildings, type, x, y)) return 'Cannot place there.';
  return null;
}

export function build(s, type, x, y) {
  const err = placeError(s, type, x, y);
  if (err) return { error: err };
  const d = BUILDINGS[type];
  spend(s, d.cost);
  const b = addBuilding(s, type, x, y, d.time === 0);
  if (d.time > 0) log(s, `Construction of ${d.name} has begun.`);
  assignProfessions(s);
  return { building: b };
}

export function moveBuilding(s, b, x, y) {
  if (!canPlace(s.buildings, b.type, x, y, b.id)) return false;
  b.x = x; b.y = y;
  return true;
}

export function removeBuilding(s, b) {
  const d = BUILDINGS[b.type];
  if (b.type === 'castle') return false;
  const refund = {};
  for (const k in d.cost) refund[k] = Math.floor(d.cost[k] * 0.5);
  s.buildings = s.buildings.filter(x => x.id !== b.id);
  addResources(s, refund);
  assignProfessions(s);
  log(s, `${d.name} demolished. Half its cost was recovered.`);
  return true;
}

export function hasBuilt(s, type) { return s.buildings.some(b => b.type === type && isBuilt(b)); }

// --- training ------------------------------------------------------------------
export function trainError(s, type) {
  const u = UNITS[type];
  if (!u || u.hidden) return 'Unknown unit.';
  if (!hasBuilt(s, u.barracks)) return `Requires a finished ${BUILDINGS[u.barracks].name}.`;
  if (u.creditsRequired && s.credits < u.creditsRequired) return `${u.name} only answers a ruler with ${u.creditsRequired}+ credits.`;
  if (!canAfford(s, u.cost)) return 'Not enough resources.';
  const cap = capacities(s);
  if (type === 'cavalry') { if (housingUsed(s, 'cavalry') + u.housing > cap.housingCav) return 'No room. Build a Cavalry Outpost.'; }
  else if (housingUsed(s, 'army') + u.housing > cap.housing) return 'No room. Build Guard Stations or Outposts.';
  if (u.kind === 'human' && !s.citizens.some(c => c.profession !== 'Soldier')) return 'No citizens left to enlist. Build Homes and let the population grow.';
  if (s.queues[u.barracks].length >= 8) return 'Training queue is full.';
  return null;
}

export function train(s, type) {
  const err = trainError(s, type);
  if (err) return err;
  const u = UNITS[type];
  spend(s, u.cost);
  if (u.kind === 'human') {
    // Enlisting turns a civilian into a soldier (their profession changes).
    const c = s.citizens.find(c => c.profession !== 'Soldier');
    c.profession = 'Soldier';
    s.queues[u.barracks].push({ type, remaining: u.time, citizenId: c.id });
  } else {
    s.queues[u.barracks].push({ type, remaining: u.time });
  }
  return null;
}

export function cancelTraining(s, barracks, index) {
  const item = s.queues[barracks][index];
  if (!item) return;
  s.queues[barracks].splice(index, 1);
  const u = UNITS[item.type];
  addResources(s, u.cost);
  if (item.citizenId) { const c = s.citizens.find(c => c.id === item.citizenId); if (c) c.profession = 'Citizen'; }
  assignProfessions(s);
}

// --- population ------------------------------------------------------------------
// Give civilians a profession based on the support buildings that exist.
export function assignProfessions(s) {
  const jobs = [];
  for (const b of s.buildings) {
    if (!isBuilt(b)) continue;
    const p = BUILDINGS[b.type].provides;
    if (p && p.profession) jobs.push(p.profession);
    if (BUILDINGS[b.type].produces) jobs.push('Miner');
  }
  let i = 0;
  for (const c of s.citizens) {
    if (c.profession === 'Soldier') continue;
    c.profession = jobs[i] || 'Citizen';
    i++;
  }
}

export function decree(s, id) {
  const d = DECREES[id];
  if ((s.decreeCooldowns[id] || 0) > 0) return 'Not yet. The people need time.';
  if (d.cost && !canAfford(s, d.cost)) return 'Not enough resources.';
  if (d.cost) spend(s, d.cost);
  if (d.gain) addResources(s, d.gain);
  s.happinessMod += d.happiness;
  s.credits = Math.max(-100, Math.min(100, s.credits + d.credits));
  s.decreeCooldowns[id] = d.cooldown;
  log(s, id === 'festival' ? 'The people celebrate. Your reputation grows.' : 'Taxes were raised. The people grumble.');
  return null;
}

// --- the main clock -----------------------------------------------------------------
export function advance(s, dt) {
  // Big jumps (offline progress) are applied in one-second slices so timers behave.
  while (dt > 0) {
    const step = Math.min(dt, 1);
    tick(s, step);
    dt -= step;
  }
}

function tick(s, dt) {
  s.time += dt;
  const cap = capacities(s);
  const mult = productionMultiplier(s);
  let dirty = false;

  for (const b of s.buildings) {
    const d = BUILDINGS[b.type];
    if (b.buildRemaining > 0) {
      b.buildRemaining -= dt;
      if (b.buildRemaining <= 0) { b.buildRemaining = 0; log(s, `${d.name} is complete.`); dirty = true; }
      continue;
    }
    if (d.produces) b.stored = Math.min(d.produces.capacity, b.stored + d.produces.perSecond * mult * dt);
  }

  for (const [barracks, q] of Object.entries(s.queues)) {
    if (!q.length || !hasBuilt(s, barracks)) continue;
    const item = q[0];
    item.remaining -= dt;
    if (item.remaining <= 0) {
      q.shift();
      const u = addUnit(s, item.type);
      if (item.citizenId) u.citizenId = item.citizenId;
      log(s, `${UNITS[item.type].name} has finished training.`);
    }
  }

  for (const u of s.army) {
    if (u.status === 'injured') { u.healRemaining -= dt * cap.healSpeed; if (u.healRemaining <= 0) { u.status = 'ready'; u.healRemaining = 0; } }
  }
  if (s.king.status === 'injured') { s.king.healRemaining -= dt * cap.healSpeed; if (s.king.healRemaining <= 0) s.king.status = 'ready'; }

  for (const k in s.decreeCooldowns) s.decreeCooldowns[k] = Math.max(0, s.decreeCooldowns[k] - dt);
  if (s.happinessMod > 0) s.happinessMod = Math.max(0, s.happinessMod - dt * 0.25);
  if (s.happinessMod < 0) s.happinessMod = Math.min(0, s.happinessMod + dt * 0.25);

  // population growth
  const hap = happiness(s);
  if (s.citizens.length < cap.popCap && hap >= 35) {
    s.growthTimer += dt * (0.5 + hap / 100);
    if (s.growthTimer >= 20) { s.growthTimer = 0; const c = addCitizen(s, 16); s.stats.born++; log(s, `${c.name} came of age and joined the kingdom.`); dirty = true; }
  }

  // seasons: aging and natural death
  s.seasonTimer += dt;
  if (s.seasonTimer >= SEASON_SECONDS) {
    s.seasonTimer -= SEASON_SECONDS;
    s.season++;
    for (const c of s.citizens) c.age++;
    const dead = s.citizens.filter(c => c.age >= 70 && Math.random() < 0.08 + (c.age - 70) * 0.02);
    for (const c of dead) {
      s.citizens = s.citizens.filter(x => x.id !== c.id);
      s.stats.died++;
      log(s, `${c.name} passed away peacefully at ${c.age}.`);
      // a soldier who dies of old age leaves the roster too
      const idx = s.army.findIndex(u => u.citizenId === c.id);
      if (idx >= 0) s.army.splice(idx, 1);
    }
    if (dead.length) dirty = true;
  }

  if (dirty) assignProfessions(s);
}

// --- after a battle -------------------------------------------------------------------
export function applyBattleResult(s, result) {
  s.stats.battles++;
  if (result.stars > 0) s.stats.wins++;
  s.stats.stars += result.stars;
  const got = addResources(s, result.loot);
  s.stats.looted.serge += got.serge || 0; s.stats.looted.jade += got.jade || 0;
  const cap = capacities(s);
  const baseHeal = cap.hospital ? 45 : 150;
  const outcome = { dead: [], injured: [] };
  for (const fallen of result.fallen) {
    if (fallen.type === 'king') { s.king.status = 'injured'; s.king.healRemaining = 60; continue; }
    const u = s.army.find(u => u.id === fallen.id);
    if (!u) continue;
    const isHuman = UNITS[u.type].kind === 'human';
    // Soldier death is permanent (section 13); heavily injured ones go to the hospital.
    if (isHuman && Math.random() < 0.4) {
      s.army = s.army.filter(x => x.id !== u.id);
      if (u.citizenId) s.citizens = s.citizens.filter(c => c.id !== u.citizenId);
      s.stats.soldiersLost++;
      outcome.dead.push(u);
    } else {
      u.status = 'injured'; u.healRemaining = baseHeal * (isHuman ? 1 : 0.7);
      outcome.injured.push(u);
    }
  }
  s.credits = Math.max(-100, Math.min(100, s.credits + (result.stars >= 2 ? 2 : 0) - (outcome.dead.length ? 1 : 0)));
  log(s, `Raid on ${result.enemyName}: ${result.stars} star(s), ${Math.round(result.destruction * 100)}% destroyed.`);
  assignProfessions(s);
  return outcome;
}
