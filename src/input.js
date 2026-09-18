// Pointer / touch / wheel handling for the map canvas: pan, zoom, tap.
import { TILE } from './config.js';

export class Input {
  constructor(canvas, camera, handlers) {
    this.canvas = canvas; this.cam = camera; this.h = handlers;
    this.pointers = new Map();
    this.dragging = false;
    this.pinchDist = 0;
    this.keys = new Set();
    canvas.addEventListener('pointerdown', e => this.down(e));
    canvas.addEventListener('pointermove', e => this.move(e));
    canvas.addEventListener('pointerup', e => this.up(e));
    canvas.addEventListener('pointercancel', e => this.up(e));
    canvas.addEventListener('wheel', e => this.wheel(e), { passive: false });
    canvas.addEventListener('contextmenu', e => e.preventDefault());
    window.addEventListener('keydown', e => {
      if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
      this.keys.add(e.key.toLowerCase());
      if (e.key === 'Escape') this.h.onCancel?.();
      else this.h.onKey?.(e.key);
    });
    window.addEventListener('keyup', e => this.keys.delete(e.key.toLowerCase()));
  }

  world(e) {
    const r = this.canvas.getBoundingClientRect();
    const w = this.cam.toWorld(e.clientX - r.left, e.clientY - r.top);
    return { wx: w.x, wy: w.y, tx: Math.floor(w.x / TILE), ty: Math.floor(w.y / TILE), button: e.button };
  }

  down(e) {
    this.canvas.setPointerCapture?.(e.pointerId);
    this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY, sx: e.clientX, sy: e.clientY, button: e.button });
    if (this.pointers.size === 2) {
      const [a, b] = [...this.pointers.values()];
      this.pinchDist = Math.hypot(a.x - b.x, a.y - b.y);
    }
  }

  move(e) {
    const p = this.pointers.get(e.pointerId);
    if (!p) { this.h.onHover?.(this.world(e)); return; }
    const dx = e.clientX - p.x, dy = e.clientY - p.y;
    p.x = e.clientX; p.y = e.clientY;
    if (this.pointers.size === 2) {
      const [a, b] = [...this.pointers.values()];
      const d = Math.hypot(a.x - b.x, a.y - b.y);
      if (this.pinchDist > 0) {
        const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
        this.zoomAt(mid.x, mid.y, this.cam.zoom * (d / this.pinchDist));
      }
      this.pinchDist = d;
      this.dragging = true;
      return;
    }
    if (!this.dragging && Math.hypot(e.clientX - p.sx, e.clientY - p.sy) > 6) this.dragging = true;
    if (this.dragging) {
      this.cam.x -= dx / this.cam.zoom; this.cam.y -= dy / this.cam.zoom;
      this.h.onPan?.();
    } else {
      this.h.onHover?.(this.world(e));
    }
  }

  up(e) {
    const p = this.pointers.get(e.pointerId);
    this.pointers.delete(e.pointerId);
    if (!p) return;
    if (this.pointers.size === 0) {
      if (!this.dragging) {
        const w = this.world(e); w.button = p.button;
        if (p.button === 2) this.h.onCancel?.(); else this.h.onClick?.(w);
      }
      this.dragging = false;
    }
  }

  wheel(e) {
    e.preventDefault();
    const r = this.canvas.getBoundingClientRect();
    const factor = e.deltaY < 0 ? 1.15 : 1 / 1.15;
    this.zoomAt(e.clientX - r.left, e.clientY - r.top, this.cam.zoom * factor);
  }

  zoomAt(sx, sy, newZoom) {
    newZoom = Math.max(1.25, Math.min(6, newZoom));
    const before = this.cam.toWorld(sx, sy);
    this.cam.zoom = newZoom;
    const after = this.cam.toWorld(sx, sy);
    this.cam.x += before.x - after.x; this.cam.y += before.y - after.y;
    this.h.onPan?.();
  }

  // keyboard panning, called every frame
  update(dt) {
    const v = 320 / this.cam.zoom * dt;
    let moved = false;
    if (this.keys.has('w') || this.keys.has('arrowup')) { this.cam.y -= v; moved = true; }
    if (this.keys.has('s') || this.keys.has('arrowdown')) { this.cam.y += v; moved = true; }
    if (this.keys.has('a') || this.keys.has('arrowleft')) { this.cam.x -= v; moved = true; }
    if (this.keys.has('d') || this.keys.has('arrowright')) { this.cam.x += v; moved = true; }
    if (moved) this.h.onPan?.();
  }
}
