// Minimal pixel-canvas helper. Everything is drawn 1:1 into small offscreen
// canvases and later blitted with image smoothing disabled, which is what
// gives the game its crisp pixel-art look.

export class Pix {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.canvas = document.createElement('canvas');
    this.canvas.width = w; this.canvas.height = h;
    this.ctx = this.canvas.getContext('2d');
    this.ctx.imageSmoothingEnabled = false;
  }
  px(x, y, c) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
    this.ctx.fillStyle = c; this.ctx.fillRect(x | 0, y | 0, 1, 1);
  }
  rect(x, y, w, h, c) { this.ctx.fillStyle = c; this.ctx.fillRect(x, y, w, h); }
  hline(x, y, w, c) { this.rect(x, y, w, 1, c); }
  vline(x, y, h, c) { this.rect(x, y, 1, h, c); }
  outline(x, y, w, h, c) { this.hline(x, y, w, c); this.hline(x, y + h - 1, w, c); this.vline(x, y, h, c); this.vline(x + w - 1, y, h, c); }
  // checkerboard fill, used for texture / shading
  dither(x, y, w, h, c, phase = 0) {
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) if (((i + j + phase) & 1) === 0) this.px(x + i, y + j, c);
  }
  // Draw an ASCII sprite. rows: array of strings, palette: char -> color. '.' is transparent.
  art(x, y, rows, palette) {
    for (let j = 0; j < rows.length; j++) {
      const row = rows[j];
      for (let i = 0; i < row.length; i++) {
        const ch = row[i];
        if (ch === '.' || ch === ' ') continue;
        const col = palette[ch];
        if (col) this.px(x + i, y + j, col);
      }
    }
  }
  // Fill a rect, then outline it.
  box(x, y, w, h, fill, line) { this.rect(x, y, w, h, fill); this.outline(x, y, w, h, line); }
  // Tiny deterministic noise so tiles don't look flat.
  noise(x, y, w, h, c, seed, density = 0.15) {
    let s = seed | 0;
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      if ((s / 0x7fffffff) < density) this.px(x + i, y + j, c);
    }
  }
  flipX() {
    const out = new Pix(this.w, this.h);
    out.ctx.translate(this.w, 0); out.ctx.scale(-1, 1);
    out.ctx.drawImage(this.canvas, 0, 0);
    out.ctx.setTransform(1, 0, 0, 1, 0, 0);
    return out;
  }
  // Recolor every opaque pixel to a single color (used for hologram ghosts / flashes).
  tinted(color) {
    const out = new Pix(this.w, this.h);
    out.ctx.drawImage(this.canvas, 0, 0);
    out.ctx.globalCompositeOperation = 'source-in';
    out.ctx.fillStyle = color; out.ctx.fillRect(0, 0, this.w, this.h);
    out.ctx.globalCompositeOperation = 'source-over';
    return out;
  }
}

const cache = new Map();
export function cached(key, make) {
  let v = cache.get(key);
  if (!v) { v = make(); cache.set(key, v); }
  return v;
}

// Small seeded RNG (mulberry32) used for procedural layouts and art variation.
export function rng(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
