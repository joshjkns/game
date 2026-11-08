# ONE ROUND

Two-player networked first-person co-op shooter, built with [Godot 4.7](https://godotengine.org/).
Two agents share **one revolver** with **one bullet**. **LEON** runs forward in time and can only
**fire**. **NOEL** is inverted and can only **recall**: the lodged round rips out of the wall and flies
back into the cylinder, hitting everything on the way. See `plan.md` for the full design.

## Getting started

1. Install Godot 4.7 (`brew install --cask godot` on macOS).
2. Open Godot, choose **Import**, and select `project.godot` in this folder.
3. Press **F5**. The title screen has HOST / JOIN / SOLO TEST.

### Two players on one machine (dev workflow)

Use **Debug > Customize Run Instances**: enable 2 instances.

| Instance | Launch arguments |
|---|---|
| 1 | `--host` |
| 2 | `--join 127.0.0.1` |

One press of F5 then gives a full two-player session. The host auto-starts as soon as the partner joins.
Add `--role B` to instance 1 to host as NOEL.

### Two PCs over LAN

The host clicks HOST GAME. The lobby shows the host's LAN IP. The partner types it in and clicks JOIN.
The port is **7777** (UDP), so allow it through the firewall on both machines. Venue Wi-Fi often isolates
clients from each other, so bring a travel router, use a phone hotspot or an Ethernet cable.

### Solo test

SOLO TEST on the title screen (or `--solo`) runs one PC with both agents. **Tab** swaps which agent you
control.

## Controls

| Input | With the gun | Hands free |
|---|---|---|
| LMB | LEON: fire. NOEL: recall (hold to steer it at chain 4+) | LEON: punch. NOEL: pull (yank a weapon away). Holding a prop: throw it |
| RMB | Throw the gun to your partner | Throw a held prop |
| E | – | LEON: grab a prop. NOEL: reverse an enemy bullet / rewind a dead brazier / un-throw a prop / restore a ward, bridge, cracked floor or relic / hold on LEON's echo to un-die |
| Q / MMB | Ping | Ping |
| WASD, Space | Move, jump. Run into low cover or a ledge (up to 1.6 m) to vault or mantle it. Jump beside a wall at speed to wall-run it (about 1.2 s); Space again jumps off | Same |
| Shift | Sprint | Sprint |
| Ctrl / C | Crouch. While sprinting: slide (fits under 1 m gaps); a slide into an enemy kicks it (stun and knockback) | Same |
| F | Dash: a short burst in your input direction (view direction in the air), 3 s cooldown | Same |
| R | Restart room | Restart room |
| Esc | Release mouse (click to recapture) | |
| F11 | Toggle fullscreen | |
| F10 | Toggle graphics quality (high / low) | |

Hit rules: bullets kill. Punches, thrown props and the thrown gun disarm first, then kill an
already-disarmed enemy. Rushers carry no weapon, so any hit kills them. Anchors die only to a
**temporal pincer**: LEON's shot cracks them, and NOEL's recall through a cracked Anchor finishes them.

## Room flow

- **Waves**: a room starts empty. Enemies arrive in 2–4 waves through red portals; the next wave
  lands once the current one is mostly down, or after 25 s. The HUD shows `WAVE 2/3`.
- **Enemies**: cultists strafe and fire slow bolts, gargoyle sentries sweep and fire often, an Anchor
  (at most one per room) needs a pincer, and **rushers** (amber eyes) sprint at you in single file
  and kill on contact. A line of rushers is one clean pierce.
- **Par**: the timer shows the room's par. Clear the waves inside it for bonus gems at the lift and
  an S rank.
- **Exit hold**: once the waves are down (and any exit seal is lit) the lift opens. Stepping into it
  brings a final wave. The room clears when that wave is dead and both agents stand in the lift.

## Chain

LEON and NOEL share one chain (bottom-left of the HUD). Each kill by the shot or the recall adds 1,
and so does a **flair catch**: catching the thrown gun while off the ground. The chain drops to 0
after 4 s without a kill or catch, when a shot or recall kills nothing, or when the thrown gun touches
the floor. The chain at the moment of release buffs that shot or recall:

| Chain | LEON's shot | NOEL's recall |
|---|---|---|
| 2+ | Wider hit radius | Faster round, wider hit radius |
| 4+ | Brief slow-mo | Hold LMB to bend the round towards your aim |
| 5+ | Blast where the round lodges | Blast at NOEL's feet on the catch |
| 8+ | Kills drop extra loot | Kills drop extra loot |

The round already pierces every enemy on its line, so the wider radius is the tier-2 buff. Blasts
never hurt players and do not break Anchors. The thresholds and values are the consts at the top
of `scripts/chain.gd`.

## Display and graphics

The game starts fullscreen with the **high** preset: SDFGI global illumination, SSIL, SSAO, SSR,
volumetric fog with light shafts, soft shadows on every torch, and FSR upscaling. The **low** preset
keeps shadows only on the key lights and turns off SDFGI/SSIL. Toggle in game with F10 / F11, or
launch with `--low` and/or `--windowed` (a 1600×900 window).

## Dungeon mechanics

- **Runes**: amber crystals light when LEON's shot passes through them, cyan when NOEL's recall does,
  and white seal crystals need both in one cycle (a pincer). A lit rune powers its channel.
- **Plates**: hold a channel while a player, an enemy or a resting prop stands on them.
- **Gates**: portcullises open while their channel is on. Bars stop bodies, not bullets: shoot and
  throw the gun through them. Glowing floor lines show which trigger drives which gate.
- **Braziers**: NOEL rewinds a dead brazier to full fire; it burns down. Some seals need several at once.
- **Bridges and cracked floors**: LEON punches a bridge down (dropping whoever is on it); NOEL restores
  bridges, crumbled floors and wards. Cracked floors give way under anyone who lingers.
- **Traps**: spikes, fire grates and pendulum blades run on a shared clock and kill cultists too.
- **Loot**: urns (smash them) and enemies drop coins and gems; NOEL restoring a shattered relic drops
  a gem. Hourglasses slow enemy time; echo orbs recharge NOEL's un-die. Loot totals show on the
  results and final cards.

## Tests

```sh
# Script compile check (all scripts, autoloads included)
godot --headless --path . res://tools/check.tscn

# Solo smoke test of the core loop, rooms, glass, props, reversal, un-die, restart, pincer,
# runes, plates, gates, braziers, bridges, crumbling floors, traps, loot, waves, rushers,
# par bonus, the exit hold, the chain and the movement kit (slide, slide kick, dash, vault,
# mantle, wall-run) in the test arena after the run's rooms
godot --headless --path . -- --solo --autotest

# Two-process network test (run in two terminals, host first)
godot --headless --path . -- --host --autotest
godot --headless --path . -- --join 127.0.0.1 --autotest

# Screenshots for a visual check (opens a window)
SHOTS_DIR=/some/dir godot --path . -- --solo --autotest --shots --windowed

# Wide shots of every room (TOUR_ROOMS=0,3 to pick rooms)
SHOTS_DIR=/some/dir godot --path . -- --solo --autotest --tour --windowed
```

## Layout

- `autoload/net.gd`: host/join, roles, shared host clock
- `autoload/game.gd`: run state, input map, scene changes, SFX and music helpers
- `scenes/main.tscn` (`scripts/main.gd`): title and lobby
- `scenes/game.tscn` (`scripts/world.gd`): room flow and every gameplay RPC
- `scripts/revolver.gd`: the one gun and round (fire, recall, throw, catch, previews)
- `scripts/rooms.gd`: ASCII room layouts, waves and story cards. `scripts/room.gd` builds them
- `scripts/waves.gd`: the wave director (when waves land, where, and the final wave in the lift)
- `scripts/chain.gd`: the team chain, its decay and the charge-and-release tiers
- `scripts/player.gd`, `viewmodel.gd`, `gun_model.gd`: agents, first-person hands and the revolver model
- `scripts/enemy.gd`, `enemy_bullet.gd`, `prop.gd`, `glass.gd`: world entities (`glass.gd` covers
  every break/restore object: wards, bridges, cracked floors, urns, relics)
- `scripts/device.gd`, `hazard.gd`, `pickup.gd`: puzzle triggers and gates, timed traps, floor loot
- `scripts/humanoid.gd`: the jointed, procedurally animated body shared by agents and enemies
- `scripts/mats.gd`, `shaders/`: procedural stone, water, flame, portal and rim materials, torches
- `scripts/hud.gd`, `cards.gd`, `ui.gd`: Persona-style HUD, cards and cut-in
- `assets/fonts/`: Anton and Bebas Neue (SIL OFL, licences included)
- `assets/audio/forward|reversed/`: generated SFX. Regenerate with `python3 tools/gen_sfx.py`
- `old/`: the earlier top-down prototype, kept for reference (ignored by Godot via `.gdignore`)

### Music slot

Drop a loop at `assets/audio/music.ogg` and a pre-reversed copy at `assets/audio/music_reversed.ogg`.
LEON's PC plays it forwards and NOEL's plays it reversed, both locked to the host clock.

### Editing rooms

Rooms are ASCII maps in `scripts/rooms.gd` (legend at the top of the file; 1 character = 1.5 m).
Every row must be the same length, and the exit lift `D` goes in the bottom wall row. Enemies are not
drawn on the map: mark spawn points with `! ? $ % &` and list the room's `waves` and `final` wave as
groups of `[kind, marker, count]`, e.g. `[["R", "$", 3], ["E", "!"]]`.
