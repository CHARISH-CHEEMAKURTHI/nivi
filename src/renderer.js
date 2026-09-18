// Canvas renderer. The world is drawn in logical pixels and scaled up with
// image smoothing disabled so every sprite pixel stays crisp.
import { BUILDINGS, UNITS, TILE, WORLD, BUILD_MIN, BUILD_MAX, RESOURCES } from './config.js';
import { buildingSprite, rubbleSprite, scaffoldSprite, groundLayer, unitSprite, projectileSprite, C } from './sprites.js';
import { cached } from './pixel.js';

const flashOf = (key, sprite) => cached('flash:' + key, () => sprite.tinted('#ffffff'));
import { isBuilt } from './sim.js';

export class Camera {
  constructor() { this.x = 0; this.y = 0; this.zoom = 3; }
  toScreen(wx, wy) { return { x: (wx - this.x) * this.zoom, y: (wy - this.y) * this.zoom }; }
  toWorld(sx, sy) { return { x: sx / this.zoom + this.x, y: sy / this.zoom + this.y }; }
  centerOn(wx, wy, vw, vh) { this.x = wx - vw / this.zoom / 2; this.y = wy - vh / this.zoom / 2; }
  clamp(vw, vh) {
    const size = WORLD * TILE, margin = 4 * TILE;
    const minX = -margin, maxX = size + margin - vw / this.zoom;
    const minY = -margin, maxY = size + margin - vh / this.zoom;
    this.x = maxX < minX ? (minX + maxX) / 2 : Math.max(minX, Math.min(maxX, this.x));
    this.y = maxY < minY ? (minY + maxY) / 2 : Math.max(minY, Math.min(maxY, this.y));
  }
}

export class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.w = 0; this.h = 0;
    this.resize();
  }

  resize() {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.w = window.innerWidth; this.h = window.innerHeight;
    this.canvas.width = Math.floor(this.w * dpr); this.canvas.height = Math.floor(this.h * dpr);
    this.canvas.style.width = this.w + 'px'; this.canvas.style.height = this.h + 'px';
    this.dpr = dpr;
  }

  draw(v) {
    const ctx = this.ctx, cam = v.camera;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.imageSmoothingEnabled = false;
    ctx.fillStyle = v.battle ? '#0b1d2a' : '#2f5a26';
    ctx.fillRect(0, 0, this.w, this.h);
    // snap the camera to whole logical pixels to avoid shimmering
    const camX = Math.round(cam.x * cam.zoom) / cam.zoom, camY = Math.round(cam.y * cam.zoom) / cam.zoom;
    ctx.setTransform(this.dpr * cam.zoom, 0, 0, this.dpr * cam.zoom, -camX * cam.zoom * this.dpr, -camY * cam.zoom * this.dpr);

    ctx.drawImage(groundLayer(v.groundSeed || 1).canvas, 0, 0);
    if (v.showGrid) this.drawGrid(ctx);
    if (v.battle && v.deployMode) this.drawDeployZone(ctx, v);

    // buildings and units share one depth-sorted list so tall sprites overlap correctly
    const items = [];
    for (const b of v.buildings) items.push({ z: (b.y + BUILDINGS[b.type].h) * TILE, b });
    for (const u of (v.units || [])) if (!u.dead) items.push({ z: u.y + 0.01, u });
    for (const e of (v.effects || [])) if (e.kind === 'fall') items.push({ z: e.y, e });
    items.sort((a, b) => a.z - b.z);
    for (const it of items) {
      if (it.b) this.drawBuilding(ctx, it.b, v);
      else if (it.u) this.drawUnit(ctx, it.u, v);
      else this.drawFall(ctx, it.e);
    }
    for (const p of (v.projectiles || [])) { const s = projectileSprite(p.kind); ctx.drawImage(s.canvas, Math.round(p.x - 2), Math.round(p.y - 2)); }
    for (const e of (v.effects || [])) this.drawEffect(ctx, e);
    if (v.ghost) this.drawGhost(ctx, v.ghost);
    if (v.selection) this.drawSelection(ctx, v.selection, v.time);
    if (v.hoverTile && !v.ghost) {
      ctx.strokeStyle = 'rgba(255,255,255,0.35)'; ctx.lineWidth = 1 / cam.zoom;
      ctx.strokeRect(v.hoverTile.x * TILE + 0.5, v.hoverTile.y * TILE + 0.5, TILE - 1, TILE - 1);
    }
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
  }

  drawGrid(ctx) {
    ctx.strokeStyle = 'rgba(255,255,255,0.12)'; ctx.lineWidth = 0.5;
    ctx.beginPath();
    for (let i = BUILD_MIN; i <= BUILD_MAX; i++) {
      ctx.moveTo(i * TILE, BUILD_MIN * TILE); ctx.lineTo(i * TILE, BUILD_MAX * TILE);
      ctx.moveTo(BUILD_MIN * TILE, i * TILE); ctx.lineTo(BUILD_MAX * TILE, i * TILE);
    }
    ctx.stroke();
    ctx.strokeStyle = 'rgba(255,255,255,0.5)'; ctx.lineWidth = 1;
    ctx.strokeRect(BUILD_MIN * TILE, BUILD_MIN * TILE, (BUILD_MAX - BUILD_MIN) * TILE, (BUILD_MAX - BUILD_MIN) * TILE);
  }

  drawDeployZone(ctx, v) {
    // red halo around enemy buildings: nothing can be deployed there
    ctx.fillStyle = 'rgba(220,40,60,0.16)';
    for (const b of v.buildings) {
      if (b.hp <= 0) continue;
      const d = BUILDINGS[b.type];
      ctx.fillRect((b.x - 1) * TILE, (b.y - 1) * TILE, (d.w + 2) * TILE, (d.h + 2) * TILE);
    }
  }

  drawBuilding(ctx, b, v) {
    const d = BUILDINGS[b.type];
    if (b.hp !== undefined && b.hp <= 0) {
      const r = rubbleSprite(d.w, d.h);
      ctx.drawImage(r.canvas, b.x * TILE, b.y * TILE);
      return;
    }
    let s;
    if (!isBuilt(b)) s = scaffoldSprite(d.w, d.h); else s = buildingSprite(b.type);
    const x = b.x * TILE, y = b.y * TILE - s.offsetY;
    ctx.drawImage(s.canvas, x, y);
    if (b.hitFlash > 0) { b.hitFlash -= 1 / 60; ctx.globalAlpha = 0.5; ctx.drawImage(flashOf('b:' + b.type, s).canvas, x, y); ctx.globalAlpha = 1; }

    // construction progress
    if (!isBuilt(b)) {
      const total = d.time, done = 1 - b.buildRemaining / total;
      this.bar(ctx, b.x * TILE + 1, b.y * TILE - 6, d.w * TILE - 2, 3, done, '#7ff7ff');
    }
    // mines ready to collect
    if (d.produces && isBuilt(b) && b.stored >= d.produces.capacity * 0.2) {
      const bob = Math.round(Math.sin((v.time || 0) * 4) * 1.5);
      const col = RESOURCES[d.produces.resource].color;
      const cx = b.x * TILE + d.w * TILE / 2, cy = b.y * TILE - s.rise - 6 + bob;
      ctx.fillStyle = C.OUT; ctx.fillRect(cx - 4, cy - 4, 8, 8);
      ctx.fillStyle = col; ctx.fillRect(cx - 3, cy - 3, 6, 6);
      ctx.fillStyle = '#fff'; ctx.fillRect(cx - 2, cy - 2, 2, 2);
    }
    // enemy health bars
    if (b.hp !== undefined && b.hp < b.maxHp) this.bar(ctx, b.x * TILE + 1, b.y * TILE - s.rise - 5, d.w * TILE - 2, 3, b.hp / b.maxHp, '#ff5a5a');
    // cannon aim line
    if (b.type === 'cannon' && b.aim && !b.aim.dead) {
      ctx.strokeStyle = 'rgba(255,90,90,0.35)'; ctx.lineWidth = 0.5;
      ctx.beginPath(); ctx.moveTo((b.x + 1) * TILE, (b.y + 1) * TILE); ctx.lineTo(b.aim.x, b.aim.y); ctx.stroke();
    }
  }

  drawUnit(ctx, u, v) {
    const frame = Math.floor(u.anim) & 1;
    const s = unitSprite(u.type, frame, u.facing < 0);
    const x = Math.round(u.x - s.w / 2), y = Math.round(u.y - s.h);
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.fillRect(x + 2, Math.round(u.y) - 1, s.w - 4, 2);
    ctx.drawImage(s.canvas, x, y);
    if (u.hitFlash > 0) { ctx.globalAlpha = 0.7; ctx.drawImage(flashOf(`u:${u.type}:${frame}:${u.facing}`, s).canvas, x, y); ctx.globalAlpha = 1; }
    if (u.hp < u.maxHp) this.bar(ctx, x, y - 3, s.w, 2, u.hp / u.maxHp, UNITS[u.type].kind === 'hero' ? '#f2c94c' : '#7ff7ff');
    if (v.selectedUnit === u) {
      ctx.strokeStyle = '#7ff7ff'; ctx.lineWidth = 0.5;
      ctx.strokeRect(x - 1.5, y - 1.5, s.w + 3, s.h + 3);
    }
    if (u.directive === 'hold') { ctx.fillStyle = '#f2c94c'; ctx.fillRect(x + s.w - 2, y - 2, 3, 3); }
  }

  drawFall(ctx, e) {
    const s = unitSprite(e.unit, 0, e.facing < 0);
    ctx.globalAlpha = Math.max(0, e.t / 0.8);
    ctx.save(); ctx.translate(e.x, e.y); ctx.rotate(e.facing < 0 ? -Math.PI / 2 : Math.PI / 2);
    ctx.drawImage(s.canvas, -s.w / 2, -s.h); ctx.restore();
    ctx.globalAlpha = 1;
  }

  drawEffect(ctx, e) {
    if (e.kind === 'flash') { ctx.fillStyle = '#ffd08a'; ctx.fillRect(e.x - 2, e.y - 2, 4, 4); }
    else if (e.kind === 'hit') { ctx.fillStyle = 'rgba(255,255,255,0.8)'; ctx.fillRect(e.x - 1, e.y - 1, 3, 3); }
    else if (e.kind === 'magic') { ctx.fillStyle = 'rgba(127,247,255,0.8)'; const r = 3 + (0.2 - e.t) * 20; ctx.fillRect(e.x - r / 2, e.y - r / 2, r, r); }
    else if (e.kind === 'smoke') {
      ctx.fillStyle = `rgba(60,60,70,${e.t / 1.2 * 0.8})`;
      for (let i = 0; i < 5; i++) { const a = i * 1.3, r = (1.2 - e.t) * 14; ctx.fillRect(e.x + Math.cos(a) * r - 3, e.y + Math.sin(a) * r - 3 - (1.2 - e.t) * 8, 6, 6); }
    }
  }

  drawGhost(ctx, g) {
    const d = BUILDINGS[g.type];
    const s = buildingSprite(g.type);
    ctx.globalAlpha = 0.65;
    ctx.drawImage(s.canvas, g.x * TILE, g.y * TILE - s.offsetY);
    ctx.globalAlpha = 1;
    ctx.fillStyle = g.valid ? 'rgba(80,255,120,0.35)' : 'rgba(255,70,70,0.45)';
    ctx.fillRect(g.x * TILE, g.y * TILE, d.w * TILE, d.h * TILE);
    ctx.strokeStyle = g.valid ? '#7dff9a' : '#ff6b6b'; ctx.lineWidth = 0.5;
    ctx.strokeRect(g.x * TILE + 0.25, g.y * TILE + 0.25, d.w * TILE - 0.5, d.h * TILE - 0.5);
  }

  drawSelection(ctx, b, time) {
    const d = BUILDINGS[b.type];
    const pulse = 0.5 + Math.sin((time || 0) * 6) * 0.25;
    ctx.strokeStyle = `rgba(127,247,255,${pulse + 0.25})`; ctx.lineWidth = 1;
    ctx.strokeRect(b.x * TILE - 0.5, b.y * TILE - 0.5, d.w * TILE + 1, d.h * TILE + 1);
    ctx.fillStyle = 'rgba(127,247,255,0.15)';
    ctx.fillRect(b.x * TILE, b.y * TILE, d.w * TILE, d.h * TILE);
  }

  bar(ctx, x, y, w, h, frac, color) {
    ctx.fillStyle = C.OUT; ctx.fillRect(x - 1, y - 1, w + 2, h + 2);
    ctx.fillStyle = '#3a3a48'; ctx.fillRect(x, y, w, h);
    ctx.fillStyle = color; ctx.fillRect(x, y, Math.max(0, Math.round(w * Math.max(0, Math.min(1, frac)))), h);
  }
}
