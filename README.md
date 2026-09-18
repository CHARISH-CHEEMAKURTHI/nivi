# Nivi

A kingdom builder in the spirit of Clash of Clans: raise a base on your island,
mine Serge and Jade, train soldiers and creatures, then lead a raid on your
neighbours in person.

Built in **Godot 4.3** as a native game. It runs in 3D with an isometric
camera, so the buildings have real volume and cast real shadows, and the same
project can grow into the first-person combat layer the design document plans
for later.

![The base](docs/base.png)

![A raid](docs/raid.png)

![Every Castle One building](docs/buildings.png)

## Running it

Install [Godot 4.3](https://godotengine.org/download) (the standard build, no
C# needed), then either:

- open Godot, press **Import**, pick this folder's `project.godot`, and hit **Play**; or
- from a terminal: `godot --path .`

The first launch imports the project, which takes a few seconds. Your kingdom
saves itself to Godot's user data folder and reloads when you return, crediting
up to two hours of mining you missed while away.

To export a standalone build, install the export templates in Godot
(**Editor, Manage Export Templates**) and use **Project, Export**. Presets for
Windows, Linux, macOS and Android are already set up in `export_presets.cfg`.

## Controls

| Action | Input |
| --- | --- |
| Pan | Drag, or `W` `A` `S` `D` / arrow keys |
| Zoom | Mouse wheel, or pinch |
| Inspect a building | Tap it |
| Collect a full mine | Tap it again, or press **Collect** |
| Build | **Build**, choose a building, drag it into place, press **Place** |
| Cancel | `Esc` or **Cancel** |
| Open the shop | `B` |
| Collect everything | `C` |

In a raid: pick a troop card, tap open ground to send them in, tap a troop to
select it, then tap a building to make that troop focus it. **Hold** and
**Proceed** apply to the selection, or to everyone when nothing is selected.
The King is deployed like a troop and walks wherever you tap.

## What is in the game

Everything the design document lists for Castle Level One, section 5:

| System | What it does |
| --- | --- |
| **Castle** | The seat of the throne and a bunker. Carries the base storage and shelters citizens. The upgrade to Castle Two is deliberately locked. |
| **Barracks H and L** | Two separate queues. H enlists citizens as Knights and Cavalry, L summons Unitone, Firon and Garuan. |
| **Serge and Jade mines, and their stores** | Mines fill over time and are tapped to collect. Stores raise the ceiling. |
| **Support buildings** | Homes, farms, shops, taverns, hospital, roads and walls. |
| **Military stationing** | Guard Stations and Outposts house the army; the Law Enforcer Ground Cavalry Outpost houses cavalry alone. |
| **Short-Fire Cannon** | The single Castle One defence: short range, fast rate of fire. |
| **Population** | Citizens take jobs from your buildings, age each season, are born when there is room, and die of old age. Civilians bond one creature, soldiers two, the King five. |
| **Creatures** | Stats derive from the placeholder Normal, Fire and Water ratios and the three sample creatures in section 7. |
| **Credits** | Festivals and taxes move happiness and karma. Firon only bonds with a ruler holding twenty credits or more. |
| **Raids** | Three enemy kingdoms with procedurally arranged bases. Troops pick targets, route around walls or break through them, and answer your orders mid-fight. Stars come from half the base, the enemy Castle, and a clean sweep. |
| **Consequence** | Soldiers who fall may be lost for good, taking their citizen with them. The rest are injured and recover, far faster once a Hospital stands. |

Left for later milestones, as the document recommends: the first-person combat
layer, Magic Circles, Commanders, the other six regions, multiplayer and
character creation.

## Sound

The soundtrack and every effect are synthesised in code at startup, so the game
still ships without a single audio file.

Two tracks loop under the game and cross-fade when you leave home or return: a
calm one in the kingdom, built on a warm pad, a plucked arpeggio and a simple
tune, and a driving one for raids with a pounding bass and a kit. Each is
rendered on a worker thread while the game is already on screen, and the join
is seamless because whatever is still ringing at the end of the loop is folded
back onto the start.

Seventeen effects cover the interface, the kingdom and the battlefield: clicks
and panel whooshes, a refusal buzz, the thud of a building set down, a chime
when one finishes, coins on collection, hammer on anvil, troops dropping in,
steel, creature bolts, the cannon, buildings collapsing, a star earned, and a
fanfare or a lament at the end of a raid. They play through a pool of voices so
overlapping sounds never cut each other off, and the busy battlefield ones are
thinned out so a hundred sword strikes a second do not turn to mush.

Music and sound have separate mixer buses and separate switches under **Menu**,
remembered between sessions in `user://nivi_settings.cfg`.

Samples of the result are in `docs/`: `music_kingdom.wav`, `music_raid.wav` and
`sound-effects.wav`.

## How the project is laid out

```
project.godot            Godot project file: open this folder in the editor
scenes/Main.tscn         Entry scene; everything else is built in code
scripts/Config.gd        All game data: buildings, units, creature ratios, enemy kingdoms
scripts/Game.gd          The kingdom: state, the clock, saving and loading
scripts/Main.gd          Application root; swaps between the base and a raid
scripts/art/MeshBuilder  Builds low-poly models from coloured primitives
scripts/art/Palette.gd   One shared colour palette
scripts/art/Buildings.gd A model for every Castle One building
scripts/art/Troops.gd    Models for soldiers, creatures and the King
scripts/world/Island.gd  The island: grass, beach, sea, trees and rocks
scripts/world/BaseWorld  Your kingdom in 3D: placement, selection, collection
scripts/world/CameraRig  Isometric camera: pan, zoom, tap
scripts/world/WorldEnv   Sun, sky and shadow settings shared by both scenes
scripts/battle/BattleState  Raid logic: enemy bases, troop AI, cannons, loot
scripts/battle/BattleWorld  The raid, drawn
scripts/ui/UiTheme.gd    The wood-and-gold interface theme, generated at startup
scripts/ui/Hud.gd        Resource bars, build menu, panels and windows
scripts/ui/BattleHud.gd  The raid interface
scripts/ui/Thumb.gd      Live 3D previews for the menu cards
scripts/audio/Synth.gd   A small software synthesiser: oscillators and envelopes
scripts/audio/Sfx.gd     Every sound effect, rendered at startup, plus the settings
scripts/audio/Music.gd   The two looping tracks, composed and rendered on a thread
scripts/Capture.gd       Development helper: render a frame, or simulate a raid
shaders/                 Water and grass
```

## Tuning

Every number lives in `scripts/Config.gd` and matches the design document's
placeholder values. Costs, timers, hitpoints, damage, production rates, enemy
kingdoms and decree effects can all be changed there without touching game
logic. Adding a building means adding an entry to `BUILDINGS` and a model
function in `scripts/art/Buildings.gd`.

There are no image or model files: every model, texture and interface panel is
generated in code at startup, which keeps the repository small and makes the
art easy to adjust.

## Checking your work without a desktop

`scripts/Capture.gd` reads command line arguments after `--`:

```bash
# render one frame of the game to a file
godot --path . -- --capture=/tmp/shot.png --after=60

# open a particular screen first
godot --path . -- --capture=/tmp/shot.png --after=90 --demo=build

# play a whole raid with no window and print what happened
godot --headless --path . -- --after=30 --demo=sim

# write every sound to /tmp/nivi_audio so it can be listened to
godot --headless --path . -- --after=30 --demo=audio
```
