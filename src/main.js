// Entry point: wires state, simulation, rendering, input and UI together.
import { BUILDINGS, UNITS, TILE, WORLD, ENEMY_KINGDOMS } from './config.js';
import { newGame, load, save, wipe, buildingAt, canPlace, log } from './state.js';
import * as sim from './sim.js';
import { Camera, Renderer } from './renderer.js';
import { Input } from './input.js';
import { UI } from './ui.js';
import { Battle } from './battle.js';

class Game {
  constructor() {
    this.canvas = document.getElementById('game');
    this.renderer = new Renderer(this.canvas);
    this.camera = new Camera();
    this.ui = new UI(this);
    this.mode = 'base';
    this.placing = null;      // { type, x, y, moveId }
    this.selected = null;     // selected building (base)
    this.hover = null;
    this.battle = null;
    this.deployType = null;
    this.time = 0;
    this.hudTimer = 0; this.panelTimer = 0; this.saveTimer = 0;

    const loaded = load();
    if (loaded) {
      this.state = loaded;
      const off = loaded.offlineSeconds || 0;
      delete this.state.offlineSeconds;
      if (off > 5) { sim.advance(this.state, off); this.ui.toast(`Welcome back. ${Math.round(off / 60)} minute(s) passed while you were away.`, 3500); }
    } else {
      this.state = newGame();
      setTimeout(() => this.ui.showHelp(), 400);
    }
    sim.assignProfessions(this.state);

    this.input = new Input(this.canvas, this.camera, {
      onClick: (w) => this.onClick(w),
      onHover: (w) => this.onHover(w),
      onCancel: () => this.onCancel(),
      onPan: () => this.camera.clamp(this.renderer.w, this.renderer.h),
      onKey: (k) => this.onKey(k),
    });
    window.addEventListener('resize', () => {
      const c = this.camera.toWorld(this.renderer.w / 2, this.renderer.h / 2);
      this.renderer.resize();
      this.camera.centerOn(c.x, c.y, this.renderer.w, this.renderer.h);
      this.camera.clamp(this.renderer.w, this.renderer.h);
    });
    window.addEventListener('beforeunload', () => { if (this.mode === 'base') save(this.state); });
    document.addEventListener('visibilitychange', () => { if (document.hidden && this.mode === 'base') save(this.state); });

    this.camera.zoom = window.innerWidth < 700 ? 2 : 3;
    this.camera.centerOn(WORLD * TILE / 2, WORLD * TILE / 2 + 8, this.renderer.w, this.renderer.h);
    this.ui.refreshHUD();
    this.last = performance.now();
    requestAnimationFrame((t) => this.frame(t));
  }

  productionMultiplier() { return sim.productionMultiplier(this.state); }

  // --- main loop --------------------------------------------------------------------
  frame(t) {
    const dt = Math.min(0.1, (t - this.last) / 1000);
    this.last = t; this.time += dt;
    this.input.update(dt);

    if (this.mode === 'base') {
      sim.advance(this.state, dt);
      this.saveTimer += dt;
      if (this.saveTimer > 15) { this.saveTimer = 0; save(this.state); }
    } else if (this.battle) {
      this.battle.update(dt);
      if (this.battle.ended && !this.resultShown) { this.resultShown = true; setTimeout(() => this.showBattleResult(), 600); }
    }

    this.hudTimer += dt;
    if (this.hudTimer > 0.25) {
      this.hudTimer = 0;
      if (this.mode === 'base') this.ui.refreshHUD(); else this.ui.refreshBattle(this.battle);
    }
    this.panelTimer += dt;
    if (this.panelTimer > 1 && this.mode === 'base') { this.panelTimer = 0; this.ui.refreshPanel(); }

    this.renderer.draw(this.view());
    requestAnimationFrame((t2) => this.frame(t2));
  }

  view() {
    if (this.mode === 'battle') {
      return {
        camera: this.camera, buildings: this.battle.buildings, units: this.battle.units, projectiles: this.battle.projectiles,
        effects: this.battle.effects, battle: true, groundSeed: this.battle.kingdom.seed, time: this.time,
        selectedUnit: this.battle.selected, hoverTile: this.deployType && this.hover ? this.hover : null, deployMode: !!this.deployType,
      };
    }
    let ghost = null;
    if (this.placing) {
      const valid = canPlace(this.state.buildings, this.placing.type, this.placing.x, this.placing.y, this.placing.moveId || 0);
      ghost = { type: this.placing.type, x: this.placing.x, y: this.placing.y, valid };
    }
    return {
      camera: this.camera, buildings: this.placing?.moveId ? this.state.buildings.filter(b => b.id !== this.placing.moveId) : this.state.buildings,
      ghost, showGrid: !!this.placing, selection: this.selected, groundSeed: 1, time: this.time,
      hoverTile: null,
    };
  }

  // --- input routing ------------------------------------------------------------------
  onHover(w) {
    this.hover = { x: w.tx, y: w.ty };
    if (this.placing && !this.placing.locked) this.setGhost(w.tx, w.ty);
  }

  onClick(w) {
    if (this.mode === 'battle') return this.battleClick(w);
    if (this.placing) {
      const d = BUILDINGS[this.placing.type];
      const gx = w.tx - Math.floor(d.w / 2), gy = w.ty - Math.floor(d.h / 2);
      if (this.placing.x === gx && this.placing.y === gy) return this.confirmPlace();
      this.placing.locked = true;         // once tapped, the ghost stays put until the next tap (touch friendly)
      this.setGhost(w.tx, w.ty);
      return;
    }
    const b = buildingAt(this.state.buildings, w.tx, w.ty);
    if (b) {
      if (this.selected === b && BUILDINGS[b.type].produces && sim.isBuilt(b)) { this.collectBuilding(b.id); return; }
      this.selected = b;
      this.ui.openBuildingInfo(b);
    } else {
      this.selected = null;
      if (this.ui.panel?.kind === 'info') this.ui.closePanel();
    }
  }

  onCancel() {
    if (this.placing) return this.cancelPlace();
    if (this.mode === 'battle') { this.deployType = null; this.ui.selectedTroop = null; if (this.battle) this.battle.selected = null; return; }
    this.ui.closeModal(); this.ui.closePanel();
  }

  onKey(k) {
    if (this.mode !== 'base' || this.placing) return;
    if (k === 'b') this.ui.openBuild('resource');
    if (k === 'c') this.collectAll();
  }

  setGhost(tx, ty) {
    const d = BUILDINGS[this.placing.type];
    this.placing.x = tx - Math.floor(d.w / 2);
    this.placing.y = ty - Math.floor(d.h / 2);
  }

  // --- building actions -------------------------------------------------------------------
  startPlacing(type) {
    const err = sim.placeError(this.state, type, 20, 20);
    if (err && !err.startsWith('Cannot place')) return this.ui.toast(err);
    const c = this.camera.toWorld(this.renderer.w / 2, this.renderer.h / 2);
    this.placing = { type, x: 0, y: 0, moveId: 0, locked: true };
    this.setGhost(Math.floor(c.x / TILE), Math.floor(c.y / TILE));
    this.ui.closePanel();
    this.ui.showPlaceBar(`Placing ${BUILDINGS[type].name}`);
  }

  beginMove(id) {
    const b = this.state.buildings.find(b => b.id === id);
    if (!b) return;
    this.placing = { type: b.type, x: b.x, y: b.y, moveId: b.id, locked: true };
    this.ui.closePanel();
    this.ui.showPlaceBar(`Moving ${BUILDINGS[b.type].name}`);
  }

  confirmPlace() {
    const p = this.placing;
    if (!p) return;
    if (p.moveId) {
      const b = this.state.buildings.find(b => b.id === p.moveId);
      if (!sim.moveBuilding(this.state, b, p.x, p.y)) return this.ui.toast('Cannot place there.');
      this.placing = null; this.ui.hidePlaceBar();
      return;
    }
    const r = sim.build(this.state, p.type, p.x, p.y);
    if (r.error) return this.ui.toast(r.error);
    this.ui.refreshHUD();
    // walls and roads: keep placing for convenience
    const d = BUILDINGS[p.type];
    if ((d.wall || d.flat) && !sim.placeError(this.state, p.type, p.x, p.y + 1)) { this.placing.locked = true; return; }
    if (d.wall || d.flat) { this.ui.toast(sim.placeError(this.state, p.type, 4, 4) || 'Placed.'); }
    this.placing = null; this.ui.hidePlaceBar();
  }

  cancelPlace() { this.placing = null; this.ui.hidePlaceBar(); }

  collectBuilding(id) {
    const b = this.state.buildings.find(b => b.id === id);
    if (!b) return;
    const got = sim.collect(this.state, b);
    this.ui.toast(got > 0 ? `+${got} ${BUILDINGS[b.type].produces.resource === 'serge' ? 'Serge' : 'Jade'}` : 'Storage is full or nothing to collect.');
    this.ui.refreshHUD(); this.ui.refreshPanel();
  }

  collectAll() {
    const got = sim.collectAll(this.state);
    this.ui.toast(got.serge || got.jade ? `+${got.serge} Serge, +${got.jade} Jade` : 'Nothing to collect yet.');
    this.ui.refreshHUD();
  }

  removeBuilding(id) {
    const b = this.state.buildings.find(b => b.id === id);
    if (!b) return;
    if (!confirm(`Demolish this ${BUILDINGS[b.type].name}? You get half its cost back.`)) return;
    sim.removeBuilding(this.state, b);
    this.selected = null; this.ui.closePanel(); this.ui.refreshHUD();
  }

  focusBuilding(type) {
    const b = this.state.buildings.find(b => b.type === type);
    if (b) this.camera.centerOn((b.x + 1) * TILE, (b.y + 1) * TILE, this.renderer.w, this.renderer.h);
  }

  train(type) {
    const err = sim.train(this.state, type);
    if (err) return this.ui.toast(err);
    this.ui.toast(`${UNITS[type].name} training started.`);
    this.ui.refreshHUD(); this.ui.refreshPanel();
  }

  cancelTraining(barracks, idx) { sim.cancelTraining(this.state, barracks, idx); this.ui.refreshHUD(); this.ui.refreshPanel(); }

  decree(id) {
    const err = sim.decree(this.state, id);
    if (err) return this.ui.toast(err);
    this.ui.refreshHUD(); this.ui.refreshPanel();
  }

  save(announce) { if (save(this.state) && announce) this.ui.toast('Kingdom saved.'); }

  resetGame() {
    if (!confirm('Start a brand new kingdom? Your current save will be erased.')) return;
    wipe();
    this.state = newGame();
    this.selected = null; this.placing = null;
    this.ui.closeModal(); this.ui.closePanel(); this.ui.refreshHUD();
    this.camera.centerOn(WORLD * TILE / 2, WORLD * TILE / 2 + 8, this.renderer.w, this.renderer.h);
  }

  // --- battle -----------------------------------------------------------------------------
  startBattle(kingdomId) {
    const k = ENEMY_KINGDOMS.find(k => k.id === kingdomId);
    const ready = this.state.army.filter(u => u.status === 'ready');
    if (!ready.length && this.state.king.status !== 'ready') return this.ui.toast('Nobody is ready to fight.');
    save(this.state);
    this.battle = new Battle(k, ready, this.state.king.status === 'ready');
    this.mode = 'battle';
    this.resultShown = false;
    this.placing = null; this.selected = null; this.deployType = null;
    this.ui.enterBattle();
    this.ui.refreshBattle(this.battle);
    // zoom out so the whole enemy kingdom fits on the hologram
    this.baseZoom = this.camera.zoom;
    this.camera.zoom = Math.max(1.25, Math.min(3, Math.min(this.renderer.w, this.renderer.h) / (WORLD * TILE)));
    this.camera.centerOn(WORLD * TILE / 2, WORLD * TILE / 2, this.renderer.w, this.renderer.h);
  }

  selectTroop(type) {
    if (this.deployType === type) { this.deployType = null; this.ui.selectedTroop = null; }
    else { this.deployType = type; this.ui.selectedTroop = type; if (this.battle) this.battle.selected = null; }
    this.ui.troopKey = null; this.ui.refreshBattle(this.battle);
  }

  battleClick(w) {
    const b = this.battle;
    if (!b || b.ended) return;
    const unit = b.unitAt(w.wx, w.wy);
    const building = buildingAt(b.buildings, w.tx, w.ty);
    const liveBuilding = building && building.hp > 0 ? building : null;

    if (unit && !this.deployType) { b.selected = unit; this.ui.refreshBattle(b); return; }
    if (b.selected && !b.selected.dead) {
      if (liveBuilding) { b.focus(liveBuilding, b.selected); this.ui.toast(`${UNITS[b.selected.type].name} focusing ${BUILDINGS[liveBuilding.type].name}.`, 1200); return; }
      if (b.selected.type === 'king') { b.moveKing(w.wx, w.wy); return; }
    }
    if (this.deployType) {
      const err = b.deploy(this.deployType, w.tx, w.ty);
      if (err) return this.ui.toast(err, 1500);
      const left = b.availableCounts()[this.deployType] || 0;
      if (this.deployType === 'king' || left === 0) { this.deployType = null; this.ui.selectedTroop = null; }
      this.ui.troopKey = null; this.ui.refreshBattle(b);
      return;
    }
    if (liveBuilding && b.units.some(u => !u.dead)) { b.focus(liveBuilding); this.ui.toast(`All troops focusing ${BUILDINGS[liveBuilding.type].name}.`, 1200); }
  }

  cmdHold() { this.battle?.hold(this.battle.selected); this.ui.toast(this.battle.selected ? 'Holding position.' : 'All troops holding.', 1000); }
  cmdProceed() { this.battle?.proceed(this.battle.selected); this.ui.toast(this.battle.selected ? 'Proceeding.' : 'All troops proceeding.', 1000); }
  cmdDeselect() { if (this.battle) this.battle.selected = null; this.deployType = null; this.ui.selectedTroop = null; this.ui.troopKey = null; this.ui.refreshBattle(this.battle); }

  endBattle() {
    if (!this.battle || this.battle.ended) return;
    if (this.battle.started && !confirm('End the battle now? Deployed troops stay committed.')) return;
    this.battle.end(this.battle.started ? 'You called the retreat.' : 'No troops were committed.');
  }

  showBattleResult() {
    const result = this.battle.result();
    if (!this.battle.started) { this.finishBattle(); return; }
    this.pendingResult = result;
    const outcome = sim.applyBattleResult(this.state, result);
    save(this.state);
    this.ui.showResults(result, outcome);
  }

  finishBattle() {
    this.battle = null; this.mode = 'base'; this.deployType = null;
    this.ui.exitBattle(); this.ui.refreshHUD();
    if (this.baseZoom) this.camera.zoom = this.baseZoom;
    this.camera.centerOn(WORLD * TILE / 2, WORLD * TILE / 2 + 8, this.renderer.w, this.renderer.h);
  }
}

window.game = new Game();
