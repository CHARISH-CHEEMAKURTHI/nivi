// Headless tests for the kingdom simulation and the battle rules.
// Run with: npm test
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { newGame, canPlace, countType } from '../src/state.js';
import * as sim from '../src/sim.js';
import { BUILDINGS, UNITS, ENEMY_KINGDOMS, TILE } from '../src/config.js';
import { Battle } from '../src/battle.js';
import { findPath, buildCostGrid, ringAround } from '../src/pathfind.js';

test('a new kingdom starts with the castle, the king\'s soldier and two creatures', () => {
  const s = newGame();
  assert.equal(countType(s, 'castle'), 1);
  assert.equal(s.army.filter(u => UNITS[u.type].kind === 'human').length, 1);
  assert.equal(s.army.filter(u => UNITS[u.type].kind === 'creature').length, 2);
  assert.ok(s.citizens.length > 0);
});

test('every Castle Level One building from the design document exists', () => {
  const expected = ['castle', 'barracks_h', 'barracks_l', 'serge_mine', 'jade_mine', 'serge_storage', 'jade_storage',
    'shop', 'farm', 'road', 'hospital', 'tavern', 'home', 'wall', 'guard_station', 'outpost', 'cavalry_outpost', 'cannon'];
  for (const id of expected) assert.ok(BUILDINGS[id], `missing ${id}`);
});

test('building respects placement, cost and per-level limits', () => {
  const s = newGame();
  const before = s.resources.jade;
  const r = sim.build(s, 'serge_mine', 8, 8);
  assert.ok(r.building);
  assert.equal(s.resources.jade, before - BUILDINGS.serge_mine.cost.jade);
  assert.ok(sim.build(s, 'serge_mine', 8, 8).error, 'overlapping placement must fail');
  assert.ok(sim.build(s, 'castle', 30, 30).error, 'castle is pre-built');
  assert.ok(!canPlace(s.buildings, 'home', 0, 0), 'outside the buildable area');
  s.resources.serge = 10000; s.resources.jade = 10000;
  sim.build(s, 'serge_mine', 12, 8);
  assert.match(sim.build(s, 'serge_mine', 30, 8).error, /Limit/);
});

test('mines fill up over time and collecting respects storage capacity', () => {
  const s = newGame();
  const mine = s.buildings.find(b => b.type === 'serge_mine');
  sim.advance(s, 60);
  assert.ok(mine.stored > 30, 'mine should produce serge');
  s.resources.serge = sim.capacities(s).storage.serge;
  assert.equal(sim.collect(s, mine), 0, 'nothing collected when storage is full');
  s.resources.serge = 0;
  const got = sim.collect(s, mine);
  assert.ok(got > 0);
  assert.equal(s.resources.serge, got);
});

test('training needs a barracks, housing and a citizen to enlist', () => {
  const s = newGame();
  assert.match(sim.trainError(s, 'knight'), /Barracks H/);
  s.resources.serge = 5000; s.resources.jade = 5000;
  sim.build(s, 'barracks_h', 8, 8);
  sim.build(s, 'barracks_l', 8, 12);
  for (const b of s.buildings) b.buildRemaining = 0;
  const civiliansBefore = s.citizens.filter(c => c.profession !== 'Soldier').length;
  assert.equal(sim.train(s, 'knight'), null);
  assert.equal(s.citizens.filter(c => c.profession !== 'Soldier').length, civiliansBefore - 1, 'enlisting converts a civilian');
  sim.advance(s, UNITS.knight.time + 1);
  assert.equal(s.army.filter(u => u.type === 'knight').length, 2);
  assert.match(sim.trainError(s, 'firon'), /credits/, 'Firon is gated by the credit system');
  s.credits = 25;
  assert.equal(sim.trainError(s, 'firon'), null);
  // fill the housing
  while (!sim.trainError(s, 'garuan')) sim.train(s, 'garuan');
  assert.match(sim.trainError(s, 'garuan'), /No room/);
});

test('decrees move happiness and credits', () => {
  const s = newGame();
  const h0 = sim.happiness(s);
  assert.equal(sim.decree(s, 'tax'), null);
  assert.ok(sim.happiness(s) < h0);
  assert.ok(s.credits < 0);
  assert.match(sim.decree(s, 'tax'), /Not yet/);
});

test('population grows toward capacity and citizens age each season', () => {
  const s = newGame();
  const pop0 = s.citizens.length, age0 = s.citizens[0].age;
  sim.advance(s, 130);
  assert.ok(s.citizens.length > pop0);
  assert.equal(s.citizens[0].age, age0 + 2);
});

test('pathfinding walks around walls when there is a gap and through them otherwise', () => {
  const walls = [];
  for (let y = 5; y < 15; y++) walls.push({ id: y, type: 'wall', x: 10, y, hp: 300 });
  const grid = buildCostGrid(walls);
  const p = findPath(grid, 5, 10, [{ x: 15, y: 10 }]);
  assert.ok(p);
  assert.ok(!p.some(n => n.x === 10 && n.y >= 5 && n.y < 15), 'should route around the short wall');
  const ring = ringAround({ type: 'castle', x: 20, y: 20 });
  assert.ok(!ring.some(t => t.x === 19 && t.y === 19), 'corner tiles are not valid melee positions');
});

test('a full army can take an enemy kingdom for stars and loot', () => {
  const roster = ['knight', 'knight', 'cavalry', 'garuan', 'garuan', 'unitone', 'unitone', 'firon'].map((t, i) => ({ id: i + 1, type: t }));
  const b = new Battle(ENEMY_KINGDOMS[0], roster, true);
  assert.equal(b.deploy('knight', 21, 21), 'Deploy away from enemy buildings.');
  let i = 0;
  for (const u of roster) { assert.equal(b.deploy(u.type, 3 + (i % 5) * 2, 4 + Math.floor(i / 5) * 2), null); i++; }
  assert.equal(b.deploy('king', 3, 10), null);
  for (let t = 0; t < 120 && !b.ended; t += 1 / 30) b.update(1 / 30);
  assert.ok(b.destruction >= 0.5, `expected at least half the base destroyed, got ${b.destruction}`);
  assert.ok(b.stars >= 1);
  assert.ok(b.loot.serge > 0 && b.loot.jade > 0);
  const r = b.result();
  assert.equal(r.stars, b.stars);
});

test('battle results apply loot and casualties to the kingdom', () => {
  const s = newGame();
  const knight = s.army.find(u => u.type === 'knight');
  const serge0 = s.resources.serge;
  const outcome = sim.applyBattleResult(s, { enemyName: 'Test', stars: 2, destruction: 0.7, loot: { serge: 100, jade: 0 }, fallen: [{ id: knight.id, type: 'knight' }, { id: null, type: 'king' }] });
  assert.equal(s.resources.serge, serge0 + 100);
  assert.equal(s.king.status, 'injured');
  assert.equal(outcome.dead.length + outcome.injured.length, 1);
  assert.equal(s.stats.battles, 1);
});
