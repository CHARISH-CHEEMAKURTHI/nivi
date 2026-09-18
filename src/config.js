// ---------------------------------------------------------------------------
// Game data for Castle Level One.
// Every number in here is a PLACEHOLDER, mirroring the design document which
// states that all balancing values are first-pass and not final.
// ---------------------------------------------------------------------------

export const TILE = 16;            // logical pixels per tile
export const WORLD = 44;           // tiles per side of a base
export const BUILD_MIN = 4;        // buildable area is [BUILD_MIN, BUILD_MAX)
export const BUILD_MAX = 40;
export const BATTLE_TIME = 120;    // seconds
export const SEASON_SECONDS = 60;  // one "season" of in-game time (aging tick)
export const OFFLINE_CAP = 2 * 3600; // max seconds of offline progress applied on load
export const SAVE_KEY = 'nivi.save.v1';

export const RESOURCES = {
  serge: { name: 'Serge', color: '#ff9a3c' },
  jade: { name: 'Jade', color: '#3ddc97' },
};

// Building categories drive the build menu tabs.
export const CATEGORIES = [
  { id: 'core', name: 'Core' },
  { id: 'resource', name: 'Resources' },
  { id: 'military', name: 'Military' },
  { id: 'defense', name: 'Defense' },
  { id: 'support', name: 'Support' },
];

// Section 5 of the GDD: the confirmed Castle Level One building set.
export const BUILDINGS = {
  castle: {
    name: 'Castle', category: 'core', w: 4, h: 4, hp: 1500, buildable: false, limit: 1,
    cost: {}, time: 0,
    desc: 'Seat of the throne and a bunker. Shelters citizens during attacks. Upgrading to Castle Level Two is beyond this demo.',
    provides: { popCap: 6, housing: 6, storage: { serge: 1000, jade: 1000 } },
    loot: 0.3,
  },
  barracks_h: {
    name: 'Barracks H', category: 'military', w: 3, h: 3, hp: 500, limit: 1,
    cost: { serge: 150 }, time: 10,
    desc: 'Human training facility. Enlists citizens as Knights and Cavalry. Shares its yard with Barracks L but keeps its own training queue.',
    trains: ['knight', 'cavalry'],
  },
  barracks_l: {
    name: 'Barracks L', category: 'military', w: 3, h: 3, hp: 500, limit: 1,
    cost: { jade: 150 }, time: 10,
    desc: 'Creature training facility. Performs the summoning ritual that brings creatures over from the other world.',
    trains: ['unitone', 'firon', 'garuan'],
  },
  serge_mine: {
    name: 'Serge Mine', category: 'resource', w: 2, h: 2, hp: 400, limit: 3,
    cost: { jade: 100 }, time: 6,
    desc: 'Mines Serge from the ground. Tap to collect. Fills up if not collected.',
    produces: { resource: 'serge', perSecond: 1.2, capacity: 300 },
    loot: 0.1,
  },
  jade_mine: {
    name: 'Jade Mine', category: 'resource', w: 2, h: 2, hp: 400, limit: 3,
    cost: { serge: 100 }, time: 6,
    desc: 'Mines Jade crystals. Tap to collect. Fills up if not collected.',
    produces: { resource: 'jade', perSecond: 1.2, capacity: 300 },
    loot: 0.1,
  },
  serge_storage: {
    name: 'Serge Storage', category: 'resource', w: 2, h: 2, hp: 800, limit: 2,
    cost: { jade: 200 }, time: 12,
    desc: 'Dedicated storage for harvested Serge. Raises how much Serge the kingdom can hold.',
    provides: { storage: { serge: 1500 } },
    loot: 0.25,
  },
  jade_storage: {
    name: 'Jade Storage', category: 'resource', w: 2, h: 2, hp: 800, limit: 2,
    cost: { serge: 200 }, time: 12,
    desc: 'Dedicated storage for harvested Jade. Raises how much Jade the kingdom can hold.',
    provides: { storage: { jade: 1500 } },
    loot: 0.25,
  },
  home: {
    name: 'Home', category: 'support', w: 2, h: 2, hp: 300, limit: 6,
    cost: { serge: 80 }, time: 5,
    desc: 'Houses citizens. More homes let the population grow, and population feeds the creature roster.',
    provides: { popCap: 4 },
  },
  farm: {
    name: 'Farm', category: 'support', w: 3, h: 2, hp: 250, limit: 3,
    cost: { serge: 100 }, time: 6,
    desc: 'Feeds the kingdom. Well-fed citizens are happier.',
    provides: { happiness: 8, profession: 'Farmer' },
  },
  shop: {
    name: 'Shop', category: 'support', w: 2, h: 2, hp: 300, limit: 2,
    cost: { jade: 120 }, time: 6,
    desc: 'A market stall. Trade improves city happiness.',
    provides: { happiness: 5, profession: 'Merchant' },
  },
  tavern: {
    name: 'Tavern', category: 'support', w: 3, h: 2, hp: 350, limit: 1,
    cost: { serge: 120, jade: 40 }, time: 8,
    desc: 'Where the people unwind. A big boost to city happiness.',
    provides: { happiness: 10, profession: 'Innkeeper' },
  },
  hospital: {
    name: 'Hospital', category: 'support', w: 3, h: 2, hp: 400, limit: 1,
    cost: { jade: 200 }, time: 12,
    desc: 'Treats heavily injured soldiers and creatures so they can return to the roster much faster.',
    provides: { healSpeed: 4, profession: 'Healer' },
  },
  road: {
    name: 'Road', category: 'support', w: 1, h: 1, hp: 0, limit: 200,
    cost: { serge: 5 }, time: 0, flat: true, passable: true,
    desc: 'Cobblestone path. Purely decorative in this demo, but a tidy kingdom is a happy kingdom.',
    provides: { happiness: 0.25 },
  },
  wall: {
    name: 'Wall', category: 'defense', w: 1, h: 1, hp: 300, limit: 80,
    cost: { serge: 20 }, time: 0, wall: true,
    desc: 'Defensive perimeter. Attackers have to break through or walk around.',
  },
  guard_station: {
    name: 'Guard Station', category: 'military', w: 2, h: 2, hp: 500, limit: 2,
    cost: { serge: 100 }, time: 8,
    desc: 'Posting for soldiers and law enforcers on defense duty. Houses part of your army.',
    provides: { housing: 8 },
  },
  outpost: {
    name: 'Outpost', category: 'military', w: 2, h: 2, hp: 450, limit: 2,
    cost: { jade: 150 }, time: 8,
    desc: 'Additional defensive posting structure. Houses part of your army.',
    provides: { housing: 8 },
  },
  cavalry_outpost: {
    name: 'Cavalry Outpost', category: 'military', w: 3, h: 2, hp: 500, limit: 1,
    cost: { serge: 120, jade: 120 }, time: 10,
    desc: 'Law Enforcer Ground Cavalry Outpost. Exclusively houses cavalry: law enforcers who ride their creature into battle.',
    provides: { housing: 6, housingFor: 'cavalry' },
  },
  cannon: {
    name: 'Short-Fire Cannon', category: 'defense', w: 2, h: 2, hp: 350, limit: 3,
    cost: { serge: 150, jade: 50 }, time: 10,
    desc: 'Cannon Type A. Short range but a very fast rate of fire. Charged by a law enforcer channelling their creature\'s energy.',
    defense: { range: 3.5, rate: 0.35, damage: 4 },
  },
};

// Section 7: creature type ratios (Normal : Fire : Water). Placeholder values.
export const TYPE_RATIOS = {
  normal: { strength: 2, magic: 1, defense: 4, color: '#d8b27a' },
  fire:   { strength: 1, magic: 3, defense: 2, color: '#ff7a3c' },
  water:  { strength: 1, magic: 3, defense: 2, color: '#4fa8ff' },
};

// Section 7: sample creatures with their own stat layer.
export const CREATURES = {
  unitone: { name: 'Unitone', base: 'Horse', type: 'water', speed: 3, hp: 2, housing: 1 },
  firon:   { name: 'Firon', base: 'Bear', type: 'fire', speed: 1, hp: 3, housing: 2 },
  garuan:  { name: 'Garuan', base: 'Kangaroo', type: 'normal', speed: 2, hp: 2, housing: 1 },
};

// Turn the GDD stat layers into concrete combat numbers.
function creatureCombat(id) {
  const c = CREATURES[id];
  const t = TYPE_RATIOS[c.type];
  const magical = t.magic > t.strength;
  return {
    hp: c.hp * 32,
    atk: (t.strength + t.magic) * 5,
    rate: 1.0,
    range: magical ? 40 : 6,          // magic types cast bolts, physical types bite
    speed: 12 + c.speed * 10,
    armor: t.defense * 0.05,          // fraction of damage prevented
    housing: c.housing,
    element: c.type,
  };
}

export const UNITS = {
  knight: {
    name: 'Knight', kind: 'human', barracks: 'barracks_h',
    cost: { serge: 40 }, time: 8, housing: 1,
    hp: 70, atk: 15, rate: 1.0, range: 6, speed: 24, armor: 0.1, prefer: 'any',
    desc: 'Troop Soldier. Has a creature companion but does not ride it into battle. Sturdy all-rounder.',
  },
  cavalry: {
    name: 'Cavalry', kind: 'human', barracks: 'barracks_h',
    cost: { serge: 60, jade: 40 }, time: 15, housing: 3,
    hp: 130, atk: 27, rate: 0.8, range: 6, speed: 40, armor: 0.1, prefer: 'defense',
    desc: 'Cavalry Soldier. Rides their creature into battle. Fast, and goes straight for defenses.',
  },
  unitone: {
    name: 'Unitone', kind: 'creature', barracks: 'barracks_l',
    cost: { jade: 40 }, time: 10, prefer: 'any', ...creatureCombat('unitone'),
    desc: 'Water-type horse. Quick, casts water bolts from short range.',
  },
  firon: {
    name: 'Firon', kind: 'creature', barracks: 'barracks_l',
    cost: { jade: 70 }, time: 14, prefer: 'any', creditsRequired: 20, ...creatureCombat('firon'),
    desc: 'Fire-type bear. Slow and tough, hurls fire bolts. Only bonds with a well-regarded ruler (20+ credits).',
  },
  garuan: {
    name: 'Garuan', kind: 'creature', barracks: 'barracks_l',
    cost: { jade: 40 }, time: 10, prefer: 'resource', ...creatureCombat('garuan'),
    desc: 'Normal-type kangaroo. Heavily armoured brawler that loves to raid mines and storages.',
  },
  king: {
    name: 'The King', kind: 'hero', hidden: true,
    housing: 0, hp: 220, atk: 30, rate: 0.7, range: 6, speed: 30, armor: 0.15, prefer: 'any',
    desc: 'You. Present on the battlefield, directed by hand from the arm-guard hologram.',
  },
};

// Section 6: creature allocation by profession.
export const CREATURE_SLOTS = { civilian: 1, soldier: 2, king: 5 };

// Story-mode enemy kingdoms (all Castle Level One tech).
export const ENEMY_KINGDOMS = [
  { id: 'ashford', name: 'Ashford Hamlet', seed: 11, cannons: 1, wallRing: 1, homes: 3, loot: { serge: 260, jade: 220 }, desc: 'A sleepy hamlet with a single cannon. A good first raid.' },
  { id: 'greywater', name: 'Greywater Keep', seed: 23, cannons: 2, wallRing: 2, homes: 4, loot: { serge: 420, jade: 380 }, desc: 'Walled twice over with two cannons covering the gates.' },
  { id: 'emberfall', name: 'Emberfall', seed: 37, cannons: 3, wallRing: 2, homes: 5, loot: { serge: 640, jade: 600 }, desc: 'The strongest Castle-One kingdom on the border. Bring everything.' },
];

// Governance actions feed the Credit (karma) system.
export const DECREES = {
  festival: { name: 'Hold a Festival', cost: { serge: 60, jade: 60 }, happiness: 15, credits: 5, cooldown: 45,
    desc: 'Spend resources on the people. Happiness up, credits up.' },
  tax: { name: 'Raise Taxes', gain: { serge: 120, jade: 120 }, happiness: -15, credits: -5, cooldown: 45,
    desc: 'Squeeze the population for resources. Happiness down, credits down.' },
};

export const NAMES = ['Aldric', 'Bea', 'Cassian', 'Dara', 'Edwin', 'Fen', 'Greta', 'Hale', 'Ilsa', 'Joren', 'Kira', 'Lorne', 'Mira', 'Nils', 'Orla', 'Piet', 'Quinn', 'Rosa', 'Sten', 'Tova', 'Ulric', 'Vera', 'Wren', 'Yara', 'Zed'];
