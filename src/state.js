// Game state: creation, grid occupancy helpers, save / load.
import { BUILDINGS, WORLD, BUILD_MIN, BUILD_MAX, SAVE_KEY, NAMES, OFFLINE_CAP } from './config.js';

export function newGame() {
  const s = {
    version: 1,
    createdAt: Date.now(),
    lastSaved: Date.now(),
    resources: { serge: 600, jade: 600 },
    credits: 0,
    happinessMod: 0,
    decreeCooldowns: {},
    buildings: [],
    citizens: [],
    army: [],
    queues: { barracks_h: [], barracks_l: [] },
    king: { status: 'ready', healRemaining: 0 },
    nextId: 1,
    time: 0,
    season: 1,
    seasonTimer: 0,
    growthTimer: 0,
    stats: { battles: 0, wins: 0, stars: 0, looted: { serge: 0, jade: 0 }, soldiersLost: 0, born: 0, died: 0 },
    log: [],
  };
  addBuilding(s, 'castle', 20, 20, true);
  addBuilding(s, 'serge_mine', 15, 21, true);
  addBuilding(s, 'jade_mine', 27, 21, true);
  addBuilding(s, 'home', 18, 27, true);
  addBuilding(s, 'home', 24, 27, true);
  for (let i = 0; i < 5; i++) addCitizen(s, 18 + i * 6);
  // The King starts with one soldier and two creatures (GDD section 6).
  addUnit(s, 'knight'); addUnit(s, 'garuan'); addUnit(s, 'unitone');
  s.citizens[0].profession = 'Soldier';
  log(s, 'Welcome, my liege. Your kingdom awaits its first orders.');
  return s;
}

export function log(s, msg) {
  s.log.unshift({ t: s.time, msg });
  if (s.log.length > 30) s.log.length = 30;
}

export function addBuilding(s, type, x, y, done = false) {
  const d = BUILDINGS[type];
  const b = { id: s.nextId++, type, x, y, level: 1, buildRemaining: done ? 0 : d.time, stored: 0 };
  s.buildings.push(b);
  return b;
}

export function addCitizen(s, age) {
  const c = {
    id: s.nextId++,
    name: NAMES[Math.floor(Math.random() * NAMES.length)],
    age: age ?? 16 + Math.floor(Math.random() * 20),
    profession: 'Citizen',
  };
  s.citizens.push(c);
  return c;
}

export function addUnit(s, type) {
  const u = { id: s.nextId++, type, status: 'ready', healRemaining: 0 };
  s.army.push(u);
  return u;
}

// --- grid helpers -----------------------------------------------------------
export function footprint(b) {
  const d = BUILDINGS[b.type];
  return { x: b.x, y: b.y, w: d.w, h: d.h };
}

export function occupancy(buildings) {
  const g = new Int32Array(WORLD * WORLD);
  for (const b of buildings) {
    const d = BUILDINGS[b.type];
    for (let j = 0; j < d.h; j++) for (let i = 0; i < d.w; i++) g[(b.y + j) * WORLD + b.x + i] = b.id;
  }
  return g;
}

export function buildingAt(buildings, tx, ty) {
  for (const b of buildings) {
    const d = BUILDINGS[b.type];
    if (tx >= b.x && tx < b.x + d.w && ty >= b.y && ty < b.y + d.h) return b;
  }
  return null;
}

export function canPlace(buildings, type, x, y, ignoreId = 0) {
  const d = BUILDINGS[type];
  if (x < BUILD_MIN || y < BUILD_MIN || x + d.w > BUILD_MAX || y + d.h > BUILD_MAX) return false;
  for (const b of buildings) {
    if (b.id === ignoreId) continue;
    const o = BUILDINGS[b.type];
    if (x < b.x + o.w && x + d.w > b.x && y < b.y + o.h && y + d.h > b.y) return false;
  }
  return true;
}

export function countType(s, type) {
  return s.buildings.filter(b => b.type === type).length;
}

// --- persistence ------------------------------------------------------------
export function save(s) {
  s.lastSaved = Date.now();
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(s)); return true; } catch { return false; }
}

export function load() {
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (!raw) return null;
    const s = JSON.parse(raw);
    if (s.version !== 1) return null;
    s.offlineSeconds = Math.min(OFFLINE_CAP, Math.max(0, (Date.now() - (s.lastSaved || Date.now())) / 1000));
    return s;
  } catch { return null; }
}

export function wipe() {
  try { localStorage.removeItem(SAVE_KEY); } catch { /* ignore */ }
}
