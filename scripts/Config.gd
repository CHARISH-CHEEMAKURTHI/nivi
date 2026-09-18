extends Node
## All game data for Castle Level One, in one place.
## Every number here is a PLACEHOLDER, matching the design document's note that
## balancing values are first-pass and not final.

## The home island. Ten times the buildable area of the original Castle One
## plot (114x114 tiles against the original 36x36), so a full army of
## buildings no longer tiles the whole ground by Castle Level Two.
const GRID := 126                 ## home island tiles across, edge to edge
const BUILD_MIN := 6              ## buildable area is [BUILD_MIN, BUILD_MAX)
const BUILD_MAX := 120

## Raids keep the original, smaller map: the enemy layouts in battle.gd are
## hand-placed around its centre and do not need to grow with the home base.
const BATTLE_GRID := 40
const BATTLE_BUILD_MIN := 2
const BATTLE_BUILD_MAX := 38

const BATTLE_TIME := 150.0        ## seconds per raid
const SEASON_SECONDS := 60.0      ## one season of in-game time (aging tick)
const OFFLINE_CAP := 7200.0       ## most offline seconds credited on load
const SAVE_PATH := "user://nivi_save.json"
const SAVE_VERSION := 4   ## bumped: the forest, wild Nivians and catching

## Castle Level One's hard cap on standing soldiers, independent of housing:
## fifteen is plenty to take any of the three story kingdoms, so that is what
## the design settles on until a later castle level raises it. Each soldier
## always carries exactly BONDED_PER_SOLDIER creatures with them, so this
## also caps how many creatures the army can field.
const MAX_SOLDIERS := 15
const BONDED_PER_SOLDIER := 2
const BONDED_FOR_KING := 5
## A civilian usually bonds one creature; this is how often they bond a
## second, rarer one instead.
const RARE_SECOND_CREATURE_CHANCE := 0.15

## The forest: a second, smaller island off the home island's east coast,
## joined to it by a bridge. Wild Nivians live there. A soldier who loses a
## bonded Nivian in a raid walks over on their own and comes back with
## another after CATCH_SECONDS; the King has to go and catch his in person.
const FOREST_GRID := 36            ## forest island tiles across
const FOREST_GAP := 14.0           ## open water between the two islands' grass
const WILD_NIVIANS := 8            ## how many roam the forest at once
const WILD_RESPAWN_SECONDS := 18.0 ## a caught one is replaced after this long
const THROW_RANGE := 4.5           ## how far the King can throw a Nivian ball
const CATCH_CHANCE := 0.72         ## odds at point-blank; falls off with distance
const CATCH_SECONDS := 45.0        ## a soldier's trip to re-bond a lost Nivian
const KING_WALK_SPEED := 5.0       ## tiles per second on foot

const RESOURCES := {
	"serge": {"name": "Serge", "color": Color("ff9a3c")},
	"jade": {"name": "Jade", "color": Color("3ddc97")},
}

const CATEGORIES := [
	{"id": "core", "name": "Core"},
	{"id": "resource", "name": "Mines"},
	{"id": "military", "name": "Army"},
	{"id": "defense", "name": "Defense"},
	{"id": "support", "name": "Town"},
]

## Section 5 of the design document: the confirmed Castle Level One building set.
const BUILDINGS := {
	"castle": {
		"name": "Castle", "category": "core", "w": 4, "h": 4, "hp": 1500, "buildable": false, "limit": 1,
		"cost": {}, "time": 0.0, "loot": 0.30,
		"desc": "Seat of the throne and a bunker. Shelters citizens during attacks. Upgrading to Castle Level Two is beyond this demo.",
		"provides": {"pop_cap": 6, "storage": {"serge": 1000, "jade": 1000}},
	},
	"barracks_h": {
		"name": "Barracks H", "category": "military", "w": 3, "h": 3, "hp": 500, "limit": 1,
		"cost": {"serge": 150}, "time": 10.0,
		"desc": "Human training ground. Enlists citizens as Knights and Cavalry, each already bonded with their own Nivians.",
		"trains": ["knight", "cavalry"],
	},
	"serge_mine": {
		"name": "Serge Mine", "category": "resource", "w": 2, "h": 2, "hp": 400, "limit": 3,
		"cost": {"jade": 100}, "time": 6.0, "loot": 0.10,
		"desc": "Mines Serge from the rock. Tap to collect. Fills up if left alone.",
		"produces": {"resource": "serge", "per_second": 1.2, "capacity": 300},
	},
	"jade_mine": {
		"name": "Jade Mine", "category": "resource", "w": 2, "h": 2, "hp": 400, "limit": 3,
		"cost": {"serge": 100}, "time": 6.0, "loot": 0.10,
		"desc": "Mines Jade crystal. Tap to collect. Fills up if left alone.",
		# A touch faster than the Serge mine: walls, roads and homes are
		# Serge-heavy sinks elsewhere in this list, so Jade gets a small edge
		# to keep the two currencies moving at a comparable pace.
		"produces": {"resource": "jade", "per_second": 1.4, "capacity": 300},
	},
	"serge_storage": {
		"name": "Serge Storage", "category": "resource", "w": 2, "h": 2, "hp": 800, "limit": 1,
		"cost": {"jade": 200}, "time": 12.0, "loot": 0.25,
		"desc": "Dedicated store for harvested Serge. Raises how much the kingdom can hold.",
		"provides": {"storage": {"serge": 1500}},
	},
	"jade_storage": {
		"name": "Jade Storage", "category": "resource", "w": 2, "h": 2, "hp": 800, "limit": 1,
		"cost": {"serge": 200}, "time": 12.0, "loot": 0.25,
		"desc": "Dedicated store for harvested Jade. Raises how much the kingdom can hold.",
		"provides": {"storage": {"jade": 1500}},
	},
	"home": {
		"name": "Home", "category": "support", "w": 2, "h": 2, "hp": 300, "limit": 6,
		"cost": {"serge": 55, "jade": 25}, "time": 5.0,
		"desc": "Houses citizens. More homes let the population grow, and population feeds the creature roster.",
		"provides": {"pop_cap": 4},
	},
	"farm": {
		"name": "Farm", "category": "support", "w": 3, "h": 2, "hp": 250, "limit": 3,
		"cost": {"serge": 70, "jade": 30}, "time": 6.0,
		"desc": "Feeds the kingdom. Well-fed citizens are happier.",
		"provides": {"happiness": 8, "profession": "Farmer"},
	},
	"shop": {
		"name": "Shop", "category": "support", "w": 2, "h": 2, "hp": 300, "limit": 2,
		"cost": {"jade": 85, "serge": 35}, "time": 6.0,
		"desc": "A market stall. Trade lifts the mood of the town.",
		"provides": {"happiness": 5, "profession": "Merchant"},
	},
	"tavern": {
		"name": "Tavern", "category": "support", "w": 3, "h": 2, "hp": 350, "limit": 1,
		"cost": {"serge": 120, "jade": 40}, "time": 8.0,
		"desc": "Where the people unwind. The biggest single lift to happiness.",
		"provides": {"happiness": 10, "profession": "Innkeeper"},
	},
	"hospital": {
		"name": "Hospital", "category": "support", "w": 3, "h": 2, "hp": 400, "limit": 1,
		"cost": {"jade": 140, "serge": 60}, "time": 12.0,
		"desc": "Treats heavily injured soldiers and creatures so they rejoin the roster far sooner.",
		"provides": {"heal_speed": 4, "profession": "Healer"},
	},
	"road": {
		"name": "Road", "category": "support", "w": 1, "h": 1, "hp": 0, "limit": 40,
		"cost": {"serge": 3, "jade": 2}, "time": 0.0, "flat": true, "passable": true,
		"desc": "Cobbled path. Decorative, but a tidy kingdom is a happy one.",
		"provides": {"happiness": 0.25},
	},
	"wall": {
		"name": "Wall", "category": "defense", "w": 1, "h": 1, "hp": 300, "limit": 50,
		"cost": {"serge": 14, "jade": 6}, "time": 0.0, "wall": true,
		"desc": "Defensive perimeter. Attackers must break through or walk around.",
	},
	"guard_station": {
		"name": "Guard Station", "category": "military", "w": 2, "h": 2, "hp": 500, "limit": 2,
		"cost": {"serge": 70, "jade": 30}, "time": 8.0,
		"desc": "Posting for soldiers and law enforcers on defence duty. Houses part of your army.",
		"provides": {"housing": 8},
	},
	"outpost": {
		"name": "Outpost", "category": "military", "w": 2, "h": 2, "hp": 450, "limit": 2,
		"cost": {"jade": 105, "serge": 45}, "time": 8.0,
		"desc": "Additional defensive posting structure. Houses part of your army.",
		"provides": {"housing": 8},
	},
	"cavalry_outpost": {
		"name": "Cavalry Outpost", "category": "military", "w": 3, "h": 2, "hp": 500, "limit": 1,
		"cost": {"serge": 120, "jade": 120}, "time": 10.0,
		"desc": "Law Enforcer Ground Cavalry Outpost. Houses only cavalry: law enforcers who ride their creature into battle.",
		"provides": {"housing": 6, "housing_for": "cavalry"},
	},
	"cannon": {
		"name": "Short-Fire Cannon", "category": "defense", "w": 2, "h": 2, "hp": 350, "limit": 3,
		"cost": {"serge": 150, "jade": 50}, "time": 10.0,
		"desc": "Cannon Type A. Short range but a very fast rate of fire, charged by a law enforcer channelling their creature's energy.",
		"defense": {"range": 4.0, "rate": 0.35, "damage": 4.0},
	},
}

## Section 7: type ratios (Normal : Fire : Water). Placeholder values.
const TYPE_RATIOS := {
	"normal": {"strength": 2, "magic": 1, "defense": 4},
	"fire": {"strength": 1, "magic": 3, "defense": 2},
	"water": {"strength": 1, "magic": 3, "defense": 2},
}

## Section 7: the three sample Nivians and their own stat layer. There are no
## animals in this world -- these are Nivians through and through, not
## reskinned wildlife -- so "kin" names their elemental affinity rather than
## an earthly species.
const CREATURES := {
	"unitone": {"name": "Unitone", "kin": "Water-kin", "type": "water", "speed": 3, "hp": 2},
	"firon": {"name": "Firon", "kin": "Fire-kin", "type": "fire", "speed": 1, "hp": 3},
	"garuan": {"name": "Garuan", "kin": "Ground-kin", "type": "normal", "speed": 2, "hp": 2},
}

## Nivians are no longer trained on their own: every citizen and soldier
## already carries their bonded Nivians (see Game.gd's population/bonding
## code), so these three entries exist only to supply combat stats when a
## bonded Nivian fights alongside its person. Only Knight and Cavalry are
## ever trained directly, at Barracks H.
const UNITS := {
	"knight": {
		"name": "Knight", "kind": "human", "barracks": "barracks_h",
		"cost": {"serge": 40}, "time": 8.0, "housing": 1,
		"hp": 70.0, "atk": 15.0, "rate": 1.0, "range": 0.7, "speed": 1.7, "armor": 0.10, "prefer": "any",
		"desc": "Troop Soldier. Their two bonded Nivians fight alongside them, not ridden into battle. A sturdy all-rounder.",
	},
	"cavalry": {
		"name": "Cavalry", "kind": "human", "barracks": "barracks_h",
		"cost": {"serge": 60, "jade": 40}, "time": 15.0, "housing": 3,
		"hp": 130.0, "atk": 27.0, "rate": 0.8, "range": 0.7, "speed": 2.7, "armor": 0.10, "prefer": "defense",
		"desc": "Cavalry Soldier. Rides a bonded Unitone into battle. Fast, and goes straight for the defences.",
	},
	"unitone": {
		"name": "Unitone", "kind": "creature", "element": "water",
		"hp": 64.0, "atk": 20.0, "rate": 1.0, "range": 3.0, "speed": 2.1, "armor": 0.10, "prefer": "any",
		"desc": "Water-kin. Quick, and casts water bolts from a short distance.",
	},
	"firon": {
		"name": "Firon", "kind": "creature", "element": "fire", "credits_required": 20,
		"hp": 96.0, "atk": 20.0, "rate": 1.0, "range": 3.0, "speed": 1.5, "armor": 0.10, "prefer": "any",
		"desc": "Fire-kin. Slow and tough, hurls fire from a distance. Only bonds with a well-regarded ruler.",
	},
	"garuan": {
		"name": "Garuan", "kind": "creature", "element": "normal",
		"hp": 64.0, "atk": 15.0, "rate": 1.0, "range": 0.7, "speed": 1.8, "armor": 0.20, "prefer": "resource",
		"desc": "Ground-kin. Heavily armoured brawler that loves to raid mines and stores.",
	},
	"king": {
		"name": "The King", "kind": "hero", "hidden": true,
		"housing": 0, "hp": 220.0, "atk": 30.0, "rate": 0.7, "range": 0.8, "speed": 2.2, "armor": 0.15, "prefer": "any",
		"desc": "You, present on the battlefield and directed by hand.",
	},
}

## Section 6: creature allocation by profession.
const CREATURE_SLOTS := {"civilian": 1, "soldier": 2, "king": 5}

const ENEMY_KINGDOMS := [
	{"id": "ashford", "name": "Ashford Hamlet", "seed": 11, "cannons": 1, "wall_rings": 1, "homes": 3,
		"loot": {"serge": 260, "jade": 220}, "desc": "A sleepy hamlet behind one ring of wall. A good first raid."},
	{"id": "greywater", "name": "Greywater Keep", "seed": 23, "cannons": 2, "wall_rings": 2, "homes": 4,
		"loot": {"serge": 420, "jade": 380}, "desc": "Walled twice over, with two cannons covering the gates."},
	{"id": "emberfall", "name": "Emberfall", "seed": 37, "cannons": 3, "wall_rings": 2, "homes": 5,
		"loot": {"serge": 640, "jade": 600}, "desc": "The strongest Castle One kingdom on the border. Bring everything."},
]

const DECREES := {
	"festival": {"name": "Hold a Festival", "cost": {"serge": 60, "jade": 60}, "happiness": 15, "credits": 5, "cooldown": 45.0,
		"desc": "Spend resources on the people. Happiness up, credits up."},
	"tax": {"name": "Raise Taxes", "gain": {"serge": 120, "jade": 120}, "happiness": -15, "credits": -5, "cooldown": 45.0,
		"desc": "Squeeze the population for resources. Happiness down, credits down."},
}

const NAMES := ["Aldric", "Bea", "Cassian", "Dara", "Edwin", "Fen", "Greta", "Hale", "Ilsa", "Joren",
	"Kira", "Lorne", "Mira", "Nils", "Orla", "Piet", "Quinn", "Rosa", "Sten", "Tova", "Ulric", "Vera", "Wren", "Yara", "Zed"]

## Turn a tile coordinate into the world position of that tile's centre.
## `grid` picks which island this is measured against: the home island (the
## default) or, when raiding, the smaller BATTLE_GRID.
static func tile_to_world(tx: int, ty: int, grid: int = GRID) -> Vector3:
	return Vector3(float(tx) - grid * 0.5 + 0.5, 0.0, float(ty) - grid * 0.5 + 0.5)

## Turn a world position into the tile it falls on.
static func world_to_tile(p: Vector3, grid: int = GRID) -> Vector2i:
	return Vector2i(int(floor(p.x + grid * 0.5)), int(floor(p.z + grid * 0.5)))

## Where the forest island sits: its grass edge FOREST_GAP east of the home
## island's grass edge, centred on the bridge that joins them along z = 0.
static func forest_center() -> Vector3:
	return Vector3(GRID * 0.5 + 3.0 + FOREST_GAP + FOREST_GRID * 0.5 + 3.0, 0.0, 0.0)

## World position for the centre of a building's footprint.
static func building_origin(tx: int, ty: int, w: int, h: int, grid: int = GRID) -> Vector3:
	var c := tile_to_world(tx, ty, grid)
	return c + Vector3((w - 1) * 0.5, 0.0, (h - 1) * 0.5)
