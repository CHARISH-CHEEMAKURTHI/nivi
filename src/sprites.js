// Procedural pixel art for every building, unit and tile in the demo.
// Buildings are drawn in a 3/4 top-down view: the footprint is w*16 x h*16
// and the sprite extends `rise` pixels above the footprint for the walls.
import { Pix, cached, rng } from './pixel.js';
import { BUILDINGS, TILE } from './config.js';

export const C = {
  OUT: '#1b1526',
  GRASS: '#5da53f', GRASS_L: '#6fb84f', GRASS_D: '#4c8f33', GRASS_DD: '#3d7529',
  DIRT: '#8b6b45', DIRT_D: '#6b4f31',
  STONE: '#9aa0ad', STONE_D: '#6e7482', STONE_L: '#c3c8d2', STONE_DD: '#4c515c',
  WOOD: '#8a5a34', WOOD_D: '#5e3b20', WOOD_L: '#b07a48',
  RED: '#b5433a', RED_D: '#7e2c26', RED_L: '#d6675b',
  TEAL: '#2f8f8f', TEAL_D: '#1f5f5f', TEAL_L: '#54b8b0',
  THATCH: '#d9a441', THATCH_D: '#a3772a', THATCH_L: '#f0c665',
  SLATE: '#5c6b8a', SLATE_D: '#3d4860', SLATE_L: '#7f8fb0',
  PURPLE: '#6b4aa8', PURPLE_D: '#472f75', PURPLE_L: '#9370d8',
  PLASTER: '#e9dcc4', PLASTER_D: '#c9b797',
  SERGE: '#ff9a3c', SERGE_D: '#c9641a', SERGE_L: '#ffd08a',
  JADE: '#3ddc97', JADE_D: '#1f9a67', JADE_L: '#a6f5d4',
  GOLD: '#f2c94c', GOLD_D: '#b8901f',
  WHITE: '#f4f1ea', BLACK: '#22232b', GLOW: '#7ff7ff',
  SKIN: '#f1c6a0', HAIR: '#4a2e1c', STEEL: '#b9c2cf', STEEL_D: '#7c8694', BLUE: '#3b62b8', BLUE_D: '#243f80',
};

// ---------------------------------------------------------------------------
// helpers
function outlineRounded(p, x, y, w, h, c = C.OUT) {
  p.hline(x + 1, y, w - 2, c); p.hline(x + 1, y + h - 1, w - 2, c);
  p.vline(x, y + 1, h - 2, c); p.vline(x + w - 1, y + 1, h - 2, c);
}

function shingles(p, x, y, w, h, col, dark, light) {
  p.rect(x, y, w, h, col);
  for (let j = y + 3; j < y + h - 1; j += 3) {
    p.hline(x, j, w, dark);
    for (let i = x + ((j / 3) & 1) * 2; i < x + w; i += 4) p.px(i, j - 1, dark);
  }
  p.hline(x, y, w, light);
}

function windowAt(p, x, y, lit = true) {
  p.rect(x, y, 3, 3, lit ? C.GOLD : C.SLATE_D);
  p.outline(x - 1, y - 1, 5, 5, C.OUT);
  p.px(x + 1, y + 1, lit ? C.GOLD_D : C.SLATE);
}

function doorAt(p, x, y, w, h, col = C.WOOD_D) {
  p.rect(x, y, w, h, col);
  p.hline(x, y, w, C.OUT);
  p.vline(x, y, h, C.OUT); p.vline(x + w - 1, y, h, C.OUT);
  p.px(x + w - 2, y + (h >> 1), C.GOLD);
}

function timberWall(p, x, y, w, h) {
  p.rect(x, y, w, h, C.PLASTER);
  p.hline(x, y, w, C.PLASTER_D);
  for (let i = x + 4; i < x + w - 2; i += 8) p.vline(i, y, h, C.WOOD_D);
  p.hline(x, y + h - 1, w, C.WOOD_D);
}

function stoneWall(p, x, y, w, h, light = C.STONE, dark = C.STONE_D) {
  p.rect(x, y, w, h, light);
  for (let j = y; j < y + h; j += 3) {
    p.hline(x, j, w, dark);
    for (let i = x + ((j / 3) & 1) * 3; i < x + w; i += 6) p.px(i, j + 1, dark), p.px(i, j + 2, dark);
  }
}

function house(p, W, H, o) {
  const roofH = H - o.wallH;
  p.rect(1, 1, W - 2, H - 2, o.wall);
  shingles(p, 1, 1, W - 2, roofH - 1, o.roof, o.roofD, o.roofL);
  p.hline(0, roofH - 1, W, o.roofD);                 // eave
  if (o.timber) timberWall(p, 1, roofH, W - 2, o.wallH - 1); else stoneWall(p, 1, roofH, W - 2, o.wallH - 1, o.wall, o.wallD);
  if (o.door !== false) doorAt(p, (W >> 1) - 2, H - 1 - (o.wallH - 3), 4, o.wallH - 3);
  const wins = o.windows ?? 2;
  for (let i = 0; i < wins; i++) {
    const wx = Math.round(4 + i * ((W - 12) / Math.max(1, wins - 1)));
    if (Math.abs(wx - (W >> 1)) > 4) windowAt(p, wx, roofH + 2);
  }
  if (o.chimney) { p.rect(W - 9, 0, 4, 6, C.STONE_D); p.outline(W - 10, -1, 6, 8, C.OUT); p.px(W - 8, 1, C.STONE_L); }
  outlineRounded(p, 0, 0, W, H);
}

function crystals(p, x, y, col, colD, colL, n, seed) {
  const r = rng(seed);
  for (let i = 0; i < n; i++) {
    const cx = x + Math.floor(r() * 10), cy = y + Math.floor(r() * 4), h = 3 + Math.floor(r() * 3);
    p.vline(cx, cy - h, h + 2, colD); p.vline(cx + 1, cy - h + 1, h + 1, col); p.px(cx + 1, cy - h, colL); p.px(cx, cy - h - 1, C.OUT);
    p.px(cx + 2, cy - h + 1, C.OUT); p.px(cx - 1, cy - h + 1, C.OUT);
  }
}

// ---------------------------------------------------------------------------
// Buildings
const DRAW = {
  castle(p, W, H) {
    // outer curtain wall with corner towers, a courtyard and a central keep.
    p.rect(0, 12, W, H - 12, C.STONE_D);
    p.rect(2, 22, W - 4, 36, C.STONE_DD);                       // courtyard floor
    p.dither(2, 22, W - 4, 36, C.STONE_D, 0);
    // front wall face
    stoneWall(p, 1, 58, W - 2, 21);
    // battlements along the front wall top
    for (let i = 0; i < W; i += 6) { p.rect(i, 54, 4, 4, C.STONE); p.outline(i, 54, 4, 4, C.OUT); }
    p.hline(0, 58, W, C.STONE_L);
    // side walls
    stoneWall(p, 1, 14, 8, 44); stoneWall(p, W - 9, 14, 8, 44);
    // corner towers
    const tower = (x, y) => {
      stoneWall(p, x, y + 5, 10, 14, C.STONE_L, C.STONE);
      p.rect(x - 1, y + 2, 12, 4, C.PURPLE_D); p.rect(x, y, 10, 3, C.PURPLE); p.hline(x + 1, y, 8, C.PURPLE_L);
      p.outline(x - 1, y - 1, 12, 21, C.OUT);
      p.rect(x + 4, y + 9, 2, 4, C.SLATE_D);
    };
    tower(2, 4); tower(W - 12, 4); tower(2, 40); tower(W - 12, 40);
    // central keep
    stoneWall(p, 22, 14, 20, 32, C.STONE_L, C.STONE);
    p.outline(21, 13, 22, 34, C.OUT);
    for (let i = 22; i < 42; i += 5) { p.rect(i, 10, 3, 4, C.STONE); p.outline(i, 10, 3, 4, C.OUT); }
    p.rect(26, 0, 12, 4, C.PURPLE_D); p.rect(28, 2, 8, 9, C.PURPLE); p.hline(28, 2, 8, C.PURPLE_L);
    p.outline(27, 1, 10, 11, C.OUT); p.rect(31, 6, 2, 3, C.GOLD);
    // banner
    p.vline(32, -2, 4, C.OUT); p.rect(33, -2, 5, 3, C.GOLD); p.px(37, -1, C.RED);
    windowAt(p, 25, 20, false); windowAt(p, 36, 20, false); windowAt(p, 25, 30, false); windowAt(p, 36, 30, false);
    // gate
    p.rect(26, 63, 12, 16, C.WOOD_D); p.rect(27, 61, 10, 2, C.WOOD_D);
    p.outline(25, 60, 14, 20, C.OUT);
    for (let i = 28; i < 38; i += 3) p.vline(i, 64, 15, C.OUT);
    for (let j = 66; j < 78; j += 4) p.hline(27, j, 10, C.OUT);
    p.rect(30, 74, 4, 5, C.BLACK);
    outlineRounded(p, 0, 12, W, H - 12);
  },

  barracks_h(p, W, H) {
    house(p, W, H, { wallH: 16, wall: C.PLASTER, wallD: C.PLASTER_D, roof: C.RED, roofD: C.RED_D, roofL: C.RED_L, timber: true, windows: 2 });
    // shield emblem
    p.rect(W - 13, 2, 8, 9, C.BLUE); p.rect(W - 10, 2, 2, 9, C.WHITE); p.rect(W - 13, 5, 8, 2, C.WHITE);
    p.outline(W - 14, 1, 10, 11, C.OUT);
    // banner pole with sword
    p.vline(4, -2, 12, C.OUT); p.rect(5, -2, 5, 4, C.RED); p.px(9, -1, C.WHITE);
    // training dummy in the yard
    p.vline(6, H - 12, 9, C.WOOD_D); p.rect(4, H - 14, 5, 4, C.THATCH); p.outline(3, H - 15, 7, 6, C.OUT); p.hline(2, H - 9, 9, C.WOOD);
  },

  barracks_l(p, W, H) {
    house(p, W, H, { wallH: 16, wall: C.SLATE, wallD: C.SLATE_D, roof: C.TEAL, roofD: C.TEAL_D, roofL: C.TEAL_L, windows: 2 });
    // paw emblem
    p.rect(W - 12, 5, 6, 5, C.WHITE); p.px(W - 13, 3, C.WHITE); p.px(W - 10, 2, C.WHITE); p.px(W - 7, 2, C.WHITE); p.px(W - 5, 4, C.WHITE);
    p.outline(W - 14, 1, 10, 11, C.OUT);
    // magic circle glowing on the ground in front
    p.outline(2, H - 12, 12, 10, C.GLOW); p.px(7, H - 8, C.GLOW); p.px(8, H - 8, C.GLOW);
    p.px(4, H - 10, C.GLOW); p.px(11, H - 10, C.GLOW); p.px(4, H - 5, C.GLOW); p.px(11, H - 5, C.GLOW);
    // crystal on the roof pole
    p.vline(4, -2, 12, C.OUT); p.rect(3, -4, 3, 4, C.TEAL_L); p.px(4, -5, C.WHITE);
  },

  serge_mine(p, W, H) { mine(p, W, H, C.SERGE, C.SERGE_D, C.SERGE_L, 3); },
  jade_mine(p, W, H) { mine(p, W, H, C.JADE, C.JADE_D, C.JADE_L, 7); },

  serge_storage(p, W, H) {
    // wooden bin with an open top full of serge ore
    p.rect(1, 8, W - 2, H - 9, C.WOOD);
    for (let j = 10; j < H - 1; j += 4) p.hline(1, j, W - 2, C.WOOD_D);
    p.vline(1, 8, H - 9, C.WOOD_L); p.vline(W - 2, 8, H - 9, C.WOOD_D);
    p.rect(1, 1, W - 2, 8, C.WOOD_D);
    p.rect(3, 3, W - 6, 5, C.SERGE_D); p.dither(3, 3, W - 6, 5, C.SERGE, 1); p.hline(4, 3, W - 8, C.SERGE_L);
    crystals(p, 6, 6, C.SERGE, C.SERGE_D, C.SERGE_L, 4, 3);
    p.rect(2, 12, W - 4, 2, C.STEEL_D); p.rect(2, H - 6, W - 4, 2, C.STEEL_D);
    outlineRounded(p, 0, 0, W, H);
  },

  jade_storage(p, W, H) {
    // stone vault with jade gems on top
    stoneWall(p, 1, 9, W - 2, H - 10, C.STONE, C.STONE_D);
    p.rect(1, 1, W - 2, 8, C.STONE_DD);
    p.rect(3, 3, W - 6, 5, C.JADE_D); p.dither(3, 3, W - 6, 5, C.JADE, 0); p.hline(4, 3, W - 8, C.JADE_L);
    crystals(p, 6, 6, C.JADE, C.JADE_D, C.JADE_L, 4, 9);
    p.rect(2, 13, W - 4, 2, C.STEEL); p.rect(2, H - 6, W - 4, 2, C.STEEL);
    doorAt(p, (W >> 1) - 2, H - 9, 4, 8, C.STEEL_D);
    outlineRounded(p, 0, 0, W, H);
  },

  home(p, W, H) {
    house(p, W, H, { wallH: 12, wall: C.PLASTER, wallD: C.PLASTER_D, roof: C.THATCH, roofD: C.THATCH_D, roofL: C.THATCH_L, timber: true, windows: 2, chimney: true });
  },

  farm(p, W, H) {
    // fields on the left, a little hut on the right
    p.rect(1, 9, W - 2, H - 10, C.GRASS_D);
    for (let row = 0; row < 4; row++) {
      const y = 12 + row * 6;
      p.rect(2, y, 26, 4, C.DIRT); p.hline(2, y + 3, 26, C.DIRT_D);
      for (let i = 4; i < 28; i += 4) { p.px(i, y + 1, C.GRASS_L); p.px(i + 1, y, C.GRASS_L); p.px(i, y, C.JADE); }
    }
    // fence
    for (let i = 1; i < W - 1; i += 3) p.vline(i, H - 3, 3, C.WOOD_L);
    p.hline(1, H - 2, W - 2, C.WOOD);
    // hut
    p.rect(31, 6, 15, 22, C.PLASTER);
    shingles(p, 30, 2, 17, 12, C.THATCH, C.THATCH_D, C.THATCH_L);
    p.outline(30, 1, 17, 28, C.OUT); p.hline(30, 14, 17, C.THATCH_D);
    doorAt(p, 36, 20, 4, 8); windowAt(p, 33, 16);
    outlineRounded(p, 0, 0, W, H);
  },

  shop(p, W, H) {
    house(p, W, H, { wallH: 14, wall: C.PLASTER, wallD: C.PLASTER_D, roof: C.SLATE, roofD: C.SLATE_D, roofL: C.SLATE_L, timber: true, windows: 0, door: false });
    // striped awning across the front
    for (let i = 1; i < W - 1; i++) p.rect(i, H - 17, 1, 4, ((i >> 1) & 1) ? C.RED : C.WHITE);
    p.hline(1, H - 13, W - 2, C.OUT); p.hline(1, H - 17, W - 2, C.RED_D);
    // counter with goods
    p.rect(3, H - 8, W - 6, 6, C.WOOD); p.hline(3, H - 8, W - 6, C.WOOD_L); p.outline(2, H - 9, W - 4, 8, C.OUT);
    p.rect(5, H - 11, 3, 3, C.JADE); p.rect(10, H - 11, 3, 3, C.SERGE); p.rect(15, H - 11, 3, 3, C.RED); p.rect(20, H - 11, 3, 3, C.GOLD); p.rect(25, H - 11, 3, 3, C.PURPLE_L);
  },

  tavern(p, W, H) {
    house(p, W, H, { wallH: 16, wall: C.WOOD, wallD: C.WOOD_D, roof: C.SLATE_D, roofD: C.OUT, roofL: C.SLATE, windows: 3, chimney: true });
    // hanging sign with a mug
    p.hline(W - 14, H - 15, 6, C.OUT); p.rect(W - 13, H - 14, 8, 7, C.THATCH); p.outline(W - 14, H - 15, 10, 9, C.OUT);
    p.rect(W - 11, H - 12, 3, 4, C.GOLD); p.px(W - 8, H - 11, C.GOLD); p.hline(W - 11, H - 13, 3, C.WHITE);
    // lantern
    p.rect(5, H - 14, 3, 4, C.GOLD); p.outline(4, H - 15, 5, 6, C.OUT); p.px(6, H - 13, C.WHITE);
  },

  hospital(p, W, H) {
    house(p, W, H, { wallH: 16, wall: C.WHITE, wallD: C.PLASTER_D, roof: C.STONE, roofD: C.STONE_D, roofL: C.STONE_L, windows: 3 });
    p.rect(W - 13, 3, 8, 8, C.WHITE); p.rect(W - 12, 6, 6, 2, C.RED); p.rect(W - 10, 4, 2, 6, C.RED); p.outline(W - 14, 2, 10, 10, C.OUT);
    p.rect(3, H - 12, 6, 6, C.WHITE); p.rect(4, H - 10, 4, 2, C.RED); p.rect(5, H - 11, 2, 4, C.RED); p.outline(2, H - 13, 8, 8, C.OUT);
  },

  road(p, W, H) {
    p.rect(0, 0, W, H, C.DIRT);
    const r = rng(5);
    for (let j = 0; j < 4; j++) for (let i = 0; i < 4; i++) {
      const x = i * 4 + ((j & 1) ? 2 : 0), y = j * 4;
      p.rect((x + 0) % W, y, 3, 3, r() > 0.5 ? C.STONE : C.STONE_L);
      p.px((x + 1) % W, y + 3, C.DIRT_D);
    }
  },

  wall(p, W, H) {
    p.rect(0, 0, W, 6, C.STONE_L);                         // top face
    stoneWall(p, 0, 6, W, H - 6, C.STONE, C.STONE_D);      // front face
    p.hline(0, 6, W, C.STONE_DD);
    for (let i = 0; i < W; i += 4) p.rect(i + 1, 0, 2, 2, C.STONE);
    outlineRounded(p, 0, 0, W, H);
  },

  guard_station(p, W, H) {
    stoneWall(p, 1, 12, W - 2, H - 13);
    p.rect(1, 8, W - 2, 5, C.STONE_L);
    for (let i = 2; i < W - 2; i += 5) { p.rect(i, 5, 3, 4, C.STONE); p.outline(i, 5, 3, 4, C.OUT); }
    p.hline(1, 12, W - 2, C.STONE_DD);
    windowAt(p, 5, 18, false); windowAt(p, W - 8, 18, false);
    doorAt(p, (W >> 1) - 2, H - 11, 4, 10);
    // spear rack + banner
    p.vline(W - 5, -2, 12, C.OUT); p.rect(W - 4, -2, 4, 4, C.BLUE); p.px(W - 5, -3, C.STEEL);
    p.vline(3, 2, 8, C.WOOD_D); p.px(3, 1, C.STEEL); p.vline(5, 2, 8, C.WOOD_D); p.px(5, 1, C.STEEL);
    outlineRounded(p, 0, 5, W, H - 5);
  },

  outpost(p, W, H) {
    // wooden watchtower on stilts
    p.vline(4, 20, H - 21, C.WOOD_D); p.vline(5, 20, H - 21, C.WOOD); p.vline(W - 6, 20, H - 21, C.WOOD_D); p.vline(W - 5, 20, H - 21, C.WOOD);
    p.hline(4, 30, W - 8, C.WOOD_D); p.hline(4, 38, W - 8, C.WOOD_D);
    p.rect(3, 15, W - 6, 6, C.WOOD); p.hline(3, 15, W - 6, C.WOOD_L); p.outline(2, 14, W - 4, 8, C.OUT);
    for (let i = 4; i < W - 4; i += 3) p.vline(i, 10, 5, C.WOOD_L);
    p.hline(3, 10, W - 6, C.WOOD_D);
    shingles(p, 1, 1, W - 2, 9, C.RED, C.RED_D, C.RED_L); p.outline(0, 0, W, 11, C.OUT);
    p.rect(12, 11, 8, 4, C.SKIN); p.rect(13, 9, 6, 3, C.STEEL); // lookout guard
    p.vline(W - 3, -3, 6, C.OUT); p.rect(W - 2, -3, 3, 3, C.RED);
    // ladder
    for (let j = 24; j < H - 1; j += 3) p.hline(W / 2 - 2, j, 4, C.WOOD_L);
    p.vline(W / 2 - 2, 22, H - 23, C.WOOD_D); p.vline(W / 2 + 1, 22, H - 23, C.WOOD_D);
  },

  cavalry_outpost(p, W, H) {
    // stable on the left, fenced yard on the right
    p.rect(1, 1, 26, H - 2, C.WOOD);
    shingles(p, 1, 1, 26, 14, C.WOOD_D, C.OUT, C.WOOD);
    p.hline(0, 14, 28, C.OUT);
    for (let j = 16; j < H - 1; j += 4) p.hline(1, j, 26, C.WOOD_D);
    p.rect(8, H - 17, 12, 16, C.BLACK); p.rect(9, H - 19, 10, 2, C.BLACK); p.outline(7, H - 20, 14, 20, C.OUT);
    p.rect(11, H - 12, 6, 5, C.SKIN); p.rect(12, H - 15, 4, 3, C.BLUE); // a horse peeking out
    p.outline(0, 0, 28, H, C.OUT);
    // yard
    p.rect(28, 12, W - 29, H - 13, C.DIRT); p.dither(28, 12, W - 29, H - 13, C.DIRT_D, 0);
    p.rect(32, 16, 8, 6, C.THATCH); p.outline(31, 15, 10, 8, C.OUT); // hay bale
    for (let i = 28; i < W; i += 4) { p.vline(i, 8, 5, C.WOOD_L); p.vline(i, H - 5, 5, C.WOOD_L); }
    p.hline(28, 9, W - 28, C.WOOD); p.hline(28, 11, W - 28, C.WOOD); p.hline(28, H - 4, W - 28, C.WOOD); p.hline(28, H - 2, W - 28, C.WOOD);
    p.vline(W - 1, 8, H - 8, C.WOOD);
  },

  cannon(p, W, H) {
    // round stone base
    p.rect(2, 12, W - 4, H - 14, C.STONE_D);
    p.rect(4, 10, W - 8, H - 14, C.STONE); p.rect(2, 14, W - 4, H - 20, C.STONE);
    p.dither(4, 14, W - 8, H - 20, C.STONE_L, 0);
    p.outline(2, 14, W - 4, H - 20, C.OUT); p.hline(4, 10, W - 8, C.OUT); p.hline(4, H - 3, W - 8, C.OUT);
    p.vline(3, 11, 3, C.OUT); p.vline(W - 4, 11, 3, C.OUT); p.vline(3, H - 6, 3, C.OUT); p.vline(W - 4, H - 6, 3, C.OUT);
    // stubby barrel pointing down-right
    p.rect(9, 12, 10, 8, C.BLACK); p.rect(15, 16, 9, 7, C.BLACK);
    p.rect(10, 13, 8, 2, C.STEEL_D); p.rect(16, 17, 6, 2, C.STEEL_D);
    p.outline(8, 11, 12, 10, C.OUT); p.outline(14, 15, 11, 9, C.OUT);
    p.rect(21, 17, 3, 5, C.STONE_DD); // muzzle
    // wheel
    p.rect(6, 20, 6, 6, C.WOOD_D); p.outline(5, 19, 8, 8, C.OUT); p.px(8, 22, C.WOOD_L); p.px(9, 22, C.WOOD_L);
    // powder crystals (charged by a creature's energy)
    p.px(24, 12, C.GLOW); p.px(25, 11, C.GLOW); p.px(26, 13, C.GLOW);
  },
};

function mine(p, W, H, col, colD, colL, seed) {
  // rocky mound with a timber-framed entrance
  p.rect(1, 6, W - 2, H - 7, C.STONE_D);
  p.rect(3, 3, W - 6, H - 6, C.STONE);
  p.dither(3, 3, W - 6, 6, C.STONE_L, 0);
  p.noise(3, 8, W - 6, H - 12, C.STONE_D, seed, 0.2);
  p.rect(0, 12, 3, H - 14, C.STONE_D); p.rect(W - 3, 12, 3, H - 14, C.STONE_D);
  outlineRounded(p, 1, 2, W - 2, H - 2);
  p.px(2, 3, C.OUT); p.px(W - 3, 3, C.OUT); p.px(0, 12, C.OUT); p.px(W - 1, 12, C.OUT);
  // entrance
  p.rect(11, H - 13, 10, 12, C.BLACK);
  p.rect(9, H - 14, 2, 13, C.WOOD); p.rect(21, H - 14, 2, 13, C.WOOD); p.rect(9, H - 16, 14, 2, C.WOOD_L);
  p.outline(8, H - 17, 16, 17, C.OUT);
  // rails
  p.hline(12, H - 2, 8, C.STEEL_D); p.hline(12, H - 4, 8, C.STEEL_D);
  // ore veins and crystals
  crystals(p, 4, 6, col, colD, colL, 3, seed);
  crystals(p, 18, 8, col, colD, colL, 3, seed + 1);
  p.px(6, 16, col); p.px(7, 17, col); p.px(25, 14, col); p.px(26, 15, col); p.px(26, 20, col);
}

export function buildingRise(type) {
  const d = BUILDINGS[type];
  if (d.flat) return 0;
  if (type === 'castle') return 16;
  if (type === 'wall') return 6;
  if (type === 'outpost') return 16;
  if (d.w >= 3) return 12;
  return 8;
}

export function buildingSprite(type) {
  return cached('b:' + type, () => {
    const d = BUILDINGS[type];
    const W = d.w * TILE, rise = buildingRise(type), H = d.h * TILE + rise;
    const p = new Pix(W, H + 6);
    // draw with a 6px headroom for banners / chimneys that poke above the roof
    p.ctx.translate(0, 6);
    DRAW[type](p, W, H);
    p.ctx.setTransform(1, 0, 0, 1, 0, 0);
    p.offsetY = rise + 6; // how far above the footprint's top the sprite starts
    p.rise = rise;        // visible wall height above the footprint
    return p;
  });
}

export function rubbleSprite(w, h) {
  return cached(`rubble:${w}x${h}`, () => {
    const p = new Pix(w * TILE, h * TILE);
    const r = rng(w * 7 + h);
    p.rect(1, 1, w * TILE - 2, h * TILE - 2, C.DIRT_D);
    p.dither(1, 1, w * TILE - 2, h * TILE - 2, C.DIRT, 0);
    for (let i = 0; i < w * h * 4; i++) {
      const x = 1 + Math.floor(r() * (w * TILE - 5)), y = 1 + Math.floor(r() * (h * TILE - 5));
      p.rect(x, y, 3, 2, C.STONE_D); p.px(x, y, C.STONE); p.outline(x - 1, y - 1, 5, 4, C.OUT);
    }
    for (let i = 0; i < w * h * 3; i++) { const x = Math.floor(r() * w * TILE), y = Math.floor(r() * h * TILE); p.px(x, y, C.BLACK); }
    return p;
  });
}

export function scaffoldSprite(w, h) {
  return cached(`scaffold:${w}x${h}`, () => {
    const W = w * TILE, H = h * TILE + 8;
    const p = new Pix(W, H);
    p.rect(1, 9, W - 2, H - 10, C.DIRT); p.dither(1, 9, W - 2, H - 10, C.DIRT_D, 1);
    for (let i = 2; i < W - 2; i += 6) { p.vline(i, 2, H - 4, C.WOOD); p.vline(i + 1, 2, H - 4, C.WOOD_D); }
    for (let j = 4; j < H - 2; j += 8) p.hline(1, j, W - 2, C.WOOD_L);
    p.rect(W / 2 - 5, H - 9, 10, 6, C.THATCH); p.outline(W / 2 - 6, H - 10, 12, 8, C.OUT);
    outlineRounded(p, 0, 1, W, H - 1);
    p.offsetY = 8; p.rise = 8;
    return p;
  });
}

// ---------------------------------------------------------------------------
// Ground
export function grassTile(variant) {
  return cached('grass:' + variant, () => {
    const p = new Pix(TILE, TILE);
    p.rect(0, 0, TILE, TILE, C.GRASS);
    p.noise(0, 0, TILE, TILE, C.GRASS_L, 100 + variant, 0.12);
    p.noise(0, 0, TILE, TILE, C.GRASS_D, 200 + variant, 0.1);
    const r = rng(300 + variant);
    for (let i = 0; i < 3; i++) {
      const x = Math.floor(r() * 13), y = Math.floor(r() * 13);
      p.px(x, y + 1, C.GRASS_DD); p.px(x + 1, y, C.GRASS_DD); p.px(x + 2, y + 1, C.GRASS_DD);
    }
    if (variant === 3) { p.px(6, 6, C.WHITE); p.px(11, 3, C.GOLD); }
    if (variant === 5) { p.px(3, 10, C.RED_L); p.px(12, 12, C.WHITE); }
    return p;
  });
}

export function borderTile(variant) {
  return cached('border:' + variant, () => {
    const p = new Pix(TILE, TILE);
    p.rect(0, 0, TILE, TILE, C.GRASS_D);
    p.noise(0, 0, TILE, TILE, C.GRASS_DD, 400 + variant, 0.2);
    return p;
  });
}

export function treeSprite(variant) {
  return cached('tree:' + variant, () => {
    const p = new Pix(16, 22);
    const dark = variant % 2 ? C.GRASS_DD : '#2f6b2a', mid = variant % 2 ? C.GRASS_D : '#3f8a36', light = variant % 2 ? C.GRASS : '#58a84a';
    p.rect(6, 15, 4, 6, C.WOOD_D); p.px(7, 16, C.WOOD);
    p.rect(3, 6, 10, 10, dark); p.rect(4, 3, 8, 6, dark); p.rect(6, 1, 4, 3, dark);
    p.rect(4, 7, 8, 7, mid); p.rect(5, 4, 6, 4, mid); p.rect(7, 2, 2, 2, mid);
    p.px(5, 5, light); p.px(6, 4, light); p.px(5, 8, light); p.px(7, 6, light); p.px(9, 9, light);
    p.outline(2, 6, 12, 10, C.OUT); p.outline(3, 3, 10, 4, C.OUT); p.outline(5, 1, 6, 3, C.OUT);
    p.rect(4, 6, 8, 1, mid); p.rect(6, 3, 4, 1, mid);
    return p;
  });
}

export function groundLayer(seed) {
  return cached('ground:' + seed, () => {
    const r = rng(seed);
    const N = 44; // WORLD
    const p = new Pix(N * TILE, N * TILE);
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const inside = x >= 4 && x < 40 && y >= 4 && y < 40;
      const v = Math.floor(r() * 6);
      p.ctx.drawImage((inside ? grassTile(v) : borderTile(v)).canvas, x * TILE, y * TILE);
    }
    // trees around the border
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const inside = x >= 4 && x < 40 && y >= 4 && y < 40;
      if (inside || r() > 0.45) continue;
      p.ctx.drawImage(treeSprite(Math.floor(r() * 2)).canvas, x * TILE + Math.floor(r() * 3) - 1, y * TILE - 6 + Math.floor(r() * 3));
    }
    return p;
  });
}

// ---------------------------------------------------------------------------
// Units. Two walking frames each, facing right; the renderer flips for left.
const UP = { o: C.OUT, s: C.SKIN, h: C.HAIR, m: C.STEEL, M: C.STEEL_D, b: C.BLUE, B: C.BLUE_D, g: C.GOLD, r: C.RED, w: C.WHITE, p: C.PURPLE, P: C.PURPLE_D, k: C.BLACK,
  u: '#4fa8ff', U: '#2b6fc4', y: '#bfe4ff', f: '#ff7a3c', F: '#b8461b', e: '#ffd08a', n: '#d8b27a', N: '#a3804e', t: '#f2dfb5', c: C.GLOW };

const UNIT_ART = {
  knight: [[
    '...oooo...',
    '..ommmmo..',
    '..omMMmo..',
    '..osskso..',
    '.obbbbbo.o',
    'ombobbmoom',
    'o.obbbbo.o',
    '..oBooBo..',
    '..oBo.oB..',
    '..oo..oo..',
  ], [
    '...oooo...',
    '..ommmmo..',
    '..omMMmo..',
    '..osskso..',
    '.obbbbbo.o',
    'ombobbmoom',
    'o.obbbbo.o',
    '..oBoBo...',
    '...oBoBo..',
    '...oo.oo..',
  ]],
  cavalry: [[
    '.....oooo.....',
    '....ommmmo....',
    '....omMMmo....',
    '....osskso.o..',
    '...obbbbbo.m..',
    '...obbrbbooom.',
    'oo.oobbbbo.oo.',
    'ouuoouuuuuoo..',
    'oUuuuuuuuuuo..',
    '.ouuuuuuuuuuo.',
    '.oUUuuuUUuuUo.',
    '..oUo..oUooo..',
    '..oo...oo.....',
  ], [
    '.....oooo.....',
    '....ommmmo....',
    '....omMMmo....',
    '....osskso.o..',
    '...obbbbbo.m..',
    '...obbrbbooom.',
    'oo.oobbbbo.oo.',
    'ouuoouuuuuoo..',
    'oUuuuuuuuuuo..',
    '.ouuuuuuuuuuo.',
    '.oUUuuuUUuuUo.',
    '...oUo.oUo.o..',
    '....oo..oo....',
  ]],
  unitone: [[
    '............o.',
    'oo.........oyo',
    'oyoo.....oouuo',
    '.ouuuoooouuuo.',
    '.ouuuuuuuuko..',
    '..ouuuuuuuuo..',
    '..ouuuuuuuuo..',
    '.oUuuuuuuUuo..',
    '.oUo.ouoUoUo..',
    '.oo..oo.oooo..',
  ], [
    '............o.',
    'oo.........oyo',
    'oyoo.....oouuo',
    '.ouuuoooouuuo.',
    '.ouuuuuuuuko..',
    '..ouuuuuuuuo..',
    '..ouuuuuuuuo..',
    '.oUuuuuuuUuo..',
    '..oUoUooUoo...',
    '...oooo.oo....',
  ]],
  firon: [[
    '..oo........oo',
    '.ofFo......ofo',
    '.offfooooooffo',
    '..offffffffkfo',
    '.offffffffffo.',
    'offfffffffffo.',
    'offffffeeffo..',
    'oFffffffffFo..',
    '.oFfffffffFo..',
    '.oFFooooFFoo..',
    '.oooo..oooo...',
  ], [
    '..oo........oo',
    '.ofFo......ofo',
    '.offfooooooffo',
    '..offffffffkfo',
    '.offffffffffo.',
    'offfffffffffo.',
    'offfffffeeffo.',
    'oFffffffffFo..',
    '.oFfffffffFo..',
    '..oFFoooFFo...',
    '..ooo..ooo....',
  ]],
  garuan: [[
    '.........oo.o',
    '........onoon',
    'o.......onnko',
    'oo......onnno',
    '.oo....onnno.',
    '..onnnnnnno..',
    '..onnnnnnto..',
    '.oNnnnntnno..',
    '.oNNnnnnnno..',
    '.oNNoNoNNoo..',
    '.ooooo.oooo..',
  ], [
    '.........oo.o',
    '........onoon',
    'o.......onnko',
    'oo......onnno',
    '.oo....onnno.',
    '..onnnnnnno..',
    '..onnnnnnto..',
    '.oNnnnntnno..',
    '.oNNnnnnnno..',
    '..oNNoNoNo...',
    '...ooo.ooo...',
  ]],
  king: [[
    '..ogogo...',
    '..oggggo..',
    '..ohhhho..',
    '..osskso..',
    '.opppppo.o',
    'oPpgpgpoom',
    'o.opppppoo',
    '..oPpppPo.',
    '..oBo.oB..',
    '..oo..oo..',
  ], [
    '..ogogo...',
    '..oggggo..',
    '..ohhhho..',
    '..osskso..',
    '.opppppo.o',
    'oPpgpgpoom',
    'o.opppppoo',
    '..oPpppPo.',
    '..oBoBo...',
    '...oo.oo..',
  ]],
};

export function unitSprite(type, frame, flip) {
  return cached(`u:${type}:${frame}:${flip ? 1 : 0}`, () => {
    const rows = UNIT_ART[type][frame % 2];
    const w = rows[0].length, h = rows.length;
    let p = new Pix(w, h);
    p.art(0, 0, rows, UP);
    if (flip) p = p.flipX();
    return p;
  });
}

export function unitIcon(type) {
  return unitSprite(type, 0, false);
}

export function projectileSprite(kind) {
  return cached('proj:' + kind, () => {
    const p = new Pix(5, 5);
    if (kind === 'cannon') { p.rect(1, 1, 3, 3, C.BLACK); p.px(1, 1, C.STEEL_D); p.outline(0, 0, 5, 5, C.OUT); p.px(0, 0, 'rgba(0,0,0,0)'); }
    else if (kind === 'fire') { p.rect(1, 1, 3, 3, '#ff7a3c'); p.px(2, 2, '#ffd08a'); p.px(0, 2, '#b8461b'); p.px(4, 2, '#b8461b'); p.px(2, 0, '#b8461b'); p.px(2, 4, '#b8461b'); }
    else { p.rect(1, 1, 3, 3, '#4fa8ff'); p.px(2, 2, '#bfe4ff'); p.px(0, 2, '#2b6fc4'); p.px(4, 2, '#2b6fc4'); p.px(2, 0, '#2b6fc4'); p.px(2, 4, '#2b6fc4'); }
    return p;
  });
}
