# Hackathon Plan: ONE ROUND (working title)

**Theme:** Time
**Target prizes:** Best Co-op Game, Most Innovative Use of Theme
**Engine:** Godot 4.7, 3D, first person
**Players:** 2, on two separate PCs, connected over LAN by direct IP
**Time box:** 24-hour hackathon
**Status:** Draft v2. See "Decisions Log" and "Open Questions" at the bottom.
**Input:** mouse and keyboard only

## Pitch

A two-player, networked, first-person co-op shooter set in a dark cyberpunk city. Two agents share **one revolver** with **one bullet**.

- **LEON (Agent A) runs forward in time.** With the revolver, A can only **fire**.
- **NOEL (Agent B) is inverted.** Their name is LEON's backwards. With the revolver, B can only **recall**: the lodged bullet rips out of the wall and flies back into the cylinder, hitting everything on the way.
- The player **without** the gun is the one who can actually touch the world: punching, throwing, smashing, or, for B, un-throwing, un-breaking and reversing enemy bullets in mid-air.

World time runs normally forward for everyone. B is the odd one out: everything B does plays backwards on both screens.

Enemies fire slow, visible bullets. Everyone dies in one hit. Clear the room, then a stylish results card snaps in.

## Inspirations: What We Take From Each

| Game / film | What we take | What we leave |
|---|---|---|
| **SUPERHOT** | Slow, visible bullets you can dodge. One-hit deaths and instant restart. Throwing guns and props. Short, readable rooms. | The "time moves when you move" rule. Our time is stable, and the inversion lives in B. |
| **Tenet** | The forward/inverted pair. Inverted bullets fly back into the gun. The **temporal pincer**: hitting the same target from both ends of time. | The plot. |
| **Persona 5** | Loud, slanted, high-contrast UI. Kinetic menu and screen transitions. A comic-style **cut-in** on a big co-op finisher. Results cards. | The art style in 3D, the turn-based combat and the calendar. UI style only, with our own art. |
| **Cyberpunk 2077 / Ghostrunner** | Dark neon interiors, corp setting, one-hit lethality, a sleek weapon as the hero object. | Open world, RPG systems, over-the-top neon. |
| **Katana ZERO** | Time-themed one-hit action, with rewind as a narrative device. Short story cards between rooms. | 2D. |
| **It Takes Two / Portal 2 co-op** | Each player has a different, complementary kit, so neither can win alone. Pings and markers for coordination. | Split screen. |
| **Hotline Miami** | Room-by-room fights where you plan, die, restart and nail it. | Top-down. |

## Core Loop

1. **A** holds the loaded revolver and fires. The bullet pierces enemies and **lodges** in the first solid surface.
2. **A throws** the revolver to **B**, who catches it.
3. **B** finds a spot where the line from the lodged bullet to B's muzzle passes through more enemies, then **recalls**. The bullet flies back into the cylinder and kills everything on that line.
4. **B throws** it back to A. Repeat.

While the gun is travelling between them, the person without it is punching, throwing, dodging and reversing bullets. Two handoffs per shot means constant talking.

### Revolver State

| Holder | Bullet in cylinder | Bullet lodged in the world |
|---|---|---|
| A | **Fire** | Can only throw the gun |
| B | Can only throw the gun | **Recall** (needs line of sight to the bullet) |
| Nobody (in the air or on the floor) | Catch or pick it up | Catch or pick it up |

Whoever holds the gun can **only** use the gun (fire/recall) or throw it. No punching, grabbing or interacting while holding it. That is the trade-off of carrying it.

### Gun Handoff: Throw and Catch

- Throw on a fast, flat arc (holder presses throw).
- Catch is generous. If the gun passes within about 1.5 m of the partner, it snaps into their hand with a flourish (the revolver spins on the finger).
- A missed throw clatters to the floor. Walk over it to pick it up.
- A thrown gun that hits an enemy **stuns** them (SUPERHOT-style), which is a valid emergency move.
- If the gun ends up somewhere unreachable for 5 seconds, it rewinds back to the last holder (an on-theme fail-safe).

## Abilities

### Gun Holder (Either Player)

| | A (forward) | B (inverted) |
|---|---|---|
| Primary | **Fire.** Muzzle flash, a bright amber trail, and the bullet lodges in a wall. | **Recall.** Shows a preview line from the lodged bullet to the muzzle. On commit, the bullet tears out (the hole un-cracks) and flies back along the line in cyan. |
| Throw gun | Normal throw | Normal throw, with a reversed sound and spin |

### Hands Free (Without the Gun)

| | A (forward) | B (inverted) |
|---|---|---|
| Melee | **Punch.** Knocks an enemy down and disarms them. | **Pull.** Yanks the weapon or prop out of an enemy's hands towards B, which disarms them. |
| Props | **Grab and throw** bottles, stools and trays. A hit stuns. | **Un-throw.** Props fly from where they are into B's hand, hitting anything in the way. |
| Environment | **Break** glass, crates and vents to open paths and sightlines. | **Un-break.** Restores broken glass or crates to block enemy fire or trap enemies. |
| Bullets | Dodge them | **Reverse an enemy bullet.** Look at a slow bullet within about 6 m and press interact. It flips direction, turns cyan, and is lethal to its own shooter. **3 s cooldown.** |
| Partner | | **Un-die A** once per room. See "Death and Restart". |

Enemy weapons are **biometric smart-guns**: they brick when their owner is disarmed or killed. So disarmed guns can be thrown but never fired, and the revolver stays the only gun that matters. This gives a lore reason for the one-gun rule.

### What Makes B "Inverted" (Presentation)

B's controls are normal. The inversion is shown, not felt, so players spend their effort talking, not fighting the inputs. Both players see B's inversion.

- B's animations are A's played backwards (`AnimationPlayer.play_backwards()`, or tweens with reversed curves). Fire reversed = recall, throw reversed = catch, punch reversed = pull.
- Particles run in reverse: debris gathers inwards, sparks fly into impact points, glass reassembles.
- Sound effects are pre-reversed `.wav` copies, made once in Audacity and loaded instead of the forward versions.
- The revolver cylinder spins anticlockwise for B.
- B's colour is cyan and A's is amber everywhere: trails, HUD accents, outlines and pings.
- **B's screen is colour-graded differently:** slightly colder and less saturated, with a faint chromatic edge, through a `WorldEnvironment` adjustment and a light post-process shader on B's PC only. With both monitors side by side, judges see "forward" and "inverted" at a glance.
- **Music:** one dark synth loop (CC0/CC-BY). LEON's PC plays it forwards and NOEL's plays a pre-reversed copy, kept in sync by starting both from the host's clock.

## Enemies

All enemies die in one hit from the revolver bullet (either direction), a reversed bullet or a lethal thrown prop. Stuns come from thrown props, a thrown gun or a punch.

| Enemy | Behaviour | Notes |
|---|---|---|
| **Grunt** | Walks towards the nearest player on the navmesh. Stops at range and fires a slow red bullet (about 8 m/s) every 2 s. | The bread and butter. Glowing red visor for readability. |
| **Turret** | Static. Fires a fixed pattern. | Cheap AI. Good for teaching dodging and bullet reversal. |
| **Anchor** (elite) | Wears temporal armour and **can only die to a pincer**: it must be hit by A's forward shot **and** B's recall in the same cycle. | Triggers the co-op finisher. The first forward hit cracks the armour (it glows amber), and the recall finishes it. |

### The Pincer Finisher (Persona-style Cut-in)

When a recall passes through an Anchor that the forward shot already cracked:
1. The world freezes for about 1 second on both screens.
2. A slanted, high-contrast comic **cut-in** slams across the screen: A's panel on the left, B's on the right, with a big "TEMPORAL PINCER" title.
3. The Anchor shatters (the forward half amber, the reversed half cyan), and play resumes.

This is the moment we put in the trailer and the moment judges remember.

## Death and Restart

- **Everyone dies in one hit.**
- **If A dies:** A's body freezes as a translucent "echo". B can walk to it and hold interact for 1.5 s to **un-die** A. A's death plays backwards, and A stands up where they fell. Once per room.
- **If B dies, or A dies a second time:** a hard cut to a red/black "TIME FRACTURED" card, then the room restarts in about 1 second. Both players respawn and enemies reset.
- No checkpoints inside rooms. Rooms are short (under 90 s once mastered).

## Look and Feel

**Direction:** dark cyberpunk interiors, restrained. Mostly dark concrete, metal and wet floors, with a few neon accent strips per room for colour and wayfinding. Not a wall of signs.

- **Lighting:** `WorldEnvironment` with volumetric fog, glow/bloom, and SDFGI or baked lightmaps (whichever is quicker to look good). Emissive strip materials do most of the lighting work.
- **Colour language** (strict, for readability):
  - Amber means A and forward: A's trails, cracks and the HUD accent.
  - Cyan means B and inverted: B's trails, un-break effects and reversed bullets.
  - Red means enemies and their bullets.
  - White-hot is the one revolver bullet itself, with a trail in the colour of whoever moved it last.
- **The revolver is the hero object.** It needs a strong silhouette, an exposed six-chamber cylinder with **only one chamber lit**, and an emissive strip that shows the loaded state. Its life comes from code-driven animation (tweens): recoil kick, cylinder spin on fire, reverse spin on recall, a twirl on catch, and an idle inspect. Use a CC0 model (check Kenney, Quaternius, Poly Pizza and Sketchfab CC0), or kitbash one from primitives if none look right.
- **Enemies:** simple low-poly humanoids or capsules with a glowing visor. Silhouette over detail.
- **Bullets:** emissive capsule plus a `GPUParticles3D` or trail mesh. They must be visible at 30 m in a dark room.

### UI (Persona 5-style, Our Own Art)

- Slanted panels, hard black/white/red blocks, jagged accent shapes, oversized condensed type (e.g. Anton or Bebas Neue from Google Fonts), plus small amber/cyan accents per player.
- **HUD:** revolver state in the bottom right (a cylinder icon with the one chamber lit or empty, and who holds it), a partner indicator, the ability cooldown, and an off-screen arrow to the lodged bullet.
- **Transitions:** the title, lobby, room intro card, results card and death card all slide in at an angle with a snap. Use `Tween` on `Control` nodes plus a shader for the diagonal wipe.
- **Story cards** between rooms: 1 to 3 lines of text over a slanted panel with character silhouettes.
- **Results card** per room: time, deaths, pincers and a rank from S to C.

### World Readability Aids (First Person Hides a Lot)

- The **lodged bullet** has a beacon visible through walls for both players.
- The **partner** is outlined through walls in their role colour.
- **Ping:** press middle mouse / Q to drop a marker where you look ("go here", or "enemy" if on an enemy). The marker shows on both screens.
- **Recall preview:** when B holds the gun and the bullet is lodged, both players see the thin cyan line from the bullet to B's muzzle, with enemies on the line highlighted.
- **Aim line:** A sees a faint amber line showing where the shot will lodge and which enemies it passes through.

## Story Framing (Minimal)

Cards only, no cutscenes. A starting point:

> NEO-somewhere, 20XX. A megacorp is smuggling *inverted* hardware: objects moving backwards through time. You have stolen one sample: a revolver, and one inverted round.
> LEON keeps time. NOEL lost it, and now lives it backwards.
> One gun. One round. Two directions.

- The first card reveals the names: **LEON**, then the letters slide back into **NOEL**.
- Cards show silhouettes with amber (LEON) or cyan (NOEL) rims, and one line from each agent. NOEL's lines can occasionally reference things "before" they happen, as a small inverted-time joke.

Each room is one floor of the corp tower: Alley, Noodle Bar, Server Floor, Penthouse.

## Networking

### Model

- **Godot high-level multiplayer** with `ENetMultiplayerPeer`, port `7777`.
- **Host** = server + one player. **Client** = the other player. The host's lobby screen shows its LAN IP. The client types it in and joins.
- Roles are picked in the lobby and are **fixed for the whole run** (LEON = A, NOEL = B).

### Authority

| Thing | Authority | Sync method |
|---|---|---|
| Each player's movement and camera | **That player's own PC** (`set_multiplayer_authority(peer_id)`) | `MultiplayerSynchronizer`: position, yaw, pitch, with interpolation on the remote side |
| Revolver state (holder, bullet state, lodged position) | Host | Reliable RPCs on change |
| The one bullet's flight (fire and recall) | Host decides hits; everyone animates | RPC `on_fire(origin, dir, t0)` / `on_recall(from, to, t0)`. Each PC moves the visual along the known line. |
| Enemies (AI, position, death) | Host | `MultiplayerSynchronizer` on the host-owned enemy nodes |
| Enemy bullets | Host spawns them; motion is deterministic | RPC `spawn_bullet(id, origin, dir, speed, t0)`. Every PC computes `origin + dir * speed * (now - t0)`, so there is no per-frame sync. |
| Hits on players | **Victim's PC decides** | Each PC checks enemy bullets against its own capsule and reports `i_died`. Dodges that look clean are clean, which matters in a one-hit game. |
| Thrown gun / props | Host simulates the `RigidBody3D` | Position sync, plus a catch check on the host |
| Breakables, room reset, finisher freeze | Host | Reliable RPCs |

**Pattern for every action:** the client sends `request_X(...)` to the host. The host checks it's legal (e.g. A holds the gun and the bullet is in it), resolves it, and broadcasts `on_X(...)` to everyone, including itself. One code path, two PCs.

**Freeze for the cut-in:** use a `world_frozen` flag that game logic checks, not `Engine.time_scale`. That keeps the network ticking and stops the PCs drifting apart.

### Dev Workflow (Important for Speed)

- Use Godot's **Debug > Customize Run Instances**: run 2 instances, the first with `--host`, the second with `--join 127.0.0.1 --role B`. One press of F5 gives a full two-player session on one laptop.
- Test on the **two real PCs early** (by hour 4), not just at the end.
- **Venue Wi-Fi risk:** hackathon and uni Wi-Fi often isolate clients from each other, so they can't connect. Bring a travel router, use a phone hotspot, or use an Ethernet cable between the laptops. Check the OS firewall allows the game on port 7777 on both machines.

## Levels

Levels are hand-built scenes using CSG boxes (greybox), then dressed with neon strips and a few props. Each room has a `NavigationRegion3D` for the grunts. Goal of every room: kill all enemies, then both players walk into the exit lift.

Top-down sketches. Legend: `#` wall, `A` / `B` start, `G` gun, `E` grunt, `T` turret, `X` Anchor, `|` glass, `c` crate, `p` throwable props, `D` exit lift.

### Room 1: Alley (tutorial)
Teaches fire, throw, recall, and that the return trip is a second shot.

```
#################
#..........E....#
#..A.G.....c....#
#...............#
#..B.......E....#
#.......c.......#
########D########
```
- A fires through the top grunt into the wall. A throws to B. B lines up the lodged bullet with the second grunt and recalls.
- Grunts shoot slowly here (every 3 s), to teach dodging.

### Room 2: Noodle Bar
Teaches the hands-free kit: throwing, breaking/un-breaking, and reversing bullets.

```
###################
#..T......|....E..#
#.........|.......#
#..p.p....|..p....#
#..A......|.....E.#
#..G..B...|.......#
#########D#########
```
- The turret pins the players down. B reverses a turret bullet back into it.
- Grunts sit behind a glass partition. A smashes the glass by throwing a stool. Later, B un-breaks it to block fire while the gun is in the air.

### Room 3: Server Floor
Introduces the Anchor and the pincer.

```
###################
#.......X.........#
#..##..##..##..##.#
#..##..##..##..##.#
#.................#
#.A.G..E.....E..B.#
#########D#########
```
- Server racks make narrow aisles, so lines matter. A shoots through the Anchor down an aisle into the back wall. B moves into a different aisle whose recall line passes back through the Anchor: **pincer**.

### Room 4: Penthouse (finale)
Everything at once: two Anchors, grunts, a turret and glass walls to the balcony. Should take a few attempts and end on a double pincer.

### Level Design Rules
- The obvious shot should leave a bad recall angle, which forces the players to talk.
- The player without the gun must always have a job: props nearby, glass to break, or bullets to reverse.
- Rooms are compact (about 20 x 15 m) so the partner is never far away and lines are short.
- Use the colour language. If something can be broken or un-broken, it gets a subtle cyan/amber rim.

## Project Structure (Fresh Start)

The old top-down prototype moves to `old/` for reference. A fresh structure, built for multiplayer from the start:

```
autoload/
  net.gd           # host/join, peer ids, roles, RPC helpers, server time
  game.gd          # room flow, restart, results, pincer freeze
scenes/
  main.tscn        # title + lobby (Persona-style)
  game.tscn        # loads rooms, spawns players
  player.tscn      # CharacterBody3D, camera, viewmodel, hands
  revolver.tscn    # viewmodel + world (thrown) version
  bullet.tscn      # the one round (visual only; host resolves hits)
  enemy_grunt.tscn, enemy_turret.tscn, enemy_anchor.tscn
  enemy_bullet.tscn
  prop.tscn, breakable_glass.tscn
  rooms/room_01_alley.tscn ... room_04_penthouse.tscn
  ui/hud.tscn, ui/card.tscn, ui/cutin.tscn, ui/results.tscn
scripts/           # one script per scene above
audio/  forward/ and reversed/ variants of each SFX
```

## Priorities (What Gets Cut First)

**P0, the game exists** (must be done by about hour 10):
- [ ] Host/join over LAN. Both players see each other moving in first person.
- [ ] Revolver: A fires, the bullet lodges, B recalls along the line, both directions kill.
- [ ] Throw and catch the gun between players, plus pick up from the floor.
- [ ] Grunts chase and fire slow bullets. One-hit deaths. Room restart.
- [ ] HUD revolver state, lodged-bullet beacon, recall preview line.
- [ ] Room 1 playable start to finish on two PCs.

**P1, the game is good:**
- [ ] A: punch, grab and throw props. B: pull / un-throw.
- [ ] B reverses enemy bullets.
- [ ] Glass break and un-break.
- [ ] Anchor + pincer cut-in.
- [ ] Un-die A.
- [ ] Rooms 2 and 3.
- [ ] Lighting/neon pass, revolver model and animations.
- [ ] Persona-style title, lobby, room cards and death card.

**P2, polish:**
- [ ] Room 4.
- [ ] Reversed SFX and particles for B everywhere.
- [ ] Results card with rank.
- [ ] Ping system.
- [ ] Turrets.
- [ ] Music loop (forwards for LEON, reversed for NOEL).
- [ ] NOEL's colour grade and post-process.

## 24-Hour Schedule

| Hours | Goal | Checkpoint |
|---|---|---|
| 0-1 | Project skeleton, autoloads, host/join, two run instances | Two capsules see each other move |
| 1-4 | FPS controller, mouse look, sync, greybox Room 1, revolver fire/lodge/recall, networked | **Test on the two real PCs** |
| 4-6 | Throw/catch, HUD state, bullet beacon, recall preview | Full core loop with two people |
| 6-9 | Grunts: navmesh chase, slow bullets, one-hit deaths, restart | Room 1 is a real fight |
| 9-10 | **Playtest.** Is the loop fun? If not, adjust before adding more. | Go/no-go on direction |
| 10-13 | Hands-free kit: punch, props, pull, reverse bullets, glass | |
| 13-15 | Anchor + pincer cut-in, Rooms 2 and 3 greybox | |
| 15-16 | Un-die | |
| 16-20 | Art pass: lighting, neon, revolver model, Persona UI, cards, SFX | Looks like a game in screenshots |
| 20-22 | Room 4, results card, bug fixing | **Feature freeze at hour 22** |
| 22-24 | Export builds for both PCs, test on the venue network, record clips, write the submission | Submitted |

If behind at hour 10, cut straight to P1 items that make the demo memorable: **pincer cut-in > bullet reverse > Persona UI > everything else**.

## Risks

- **Networking eats the day.** Mitigation: networking goes in at hour 0, not bolted on later. Every feature is built and tested with two instances from the start.
- **Venue network blocks peer-to-peer.** Mitigation: bring a router, hotspot or cable, and test at the venue early.
- **First person hides information.** Mitigation: beacons, outlines through walls, recall preview, pings.
- **Idle partner.** Mitigation: the hands-free kit, plus rooms designed with something nearby to grab or reverse.
- **Dark look hurts readability.** Mitigation: strict colour language, emissive bullets, enemy visors. Test in a bright room on a laptop screen.
- **Persona UI takes too long.** Mitigation: build one reusable slanted-panel component and a single wipe shader, then reuse them everywhere.
- **Scope.** Mitigation: the P0/P1/P2 list. Feature freeze at hour 22, no exceptions.

## Decisions Log

| Topic | Decision |
|---|---|
| Core | Keep one gun, one bullet, fire/recall. Ported to first person. |
| Time | World time runs normally forward. B's actions look reversed on both screens. No SUPERHOT-style time stop. |
| From SUPERHOT | Slow visible bullets, one-hit deaths with instant restart, throw/melee/pick up. |
| From Persona | UI style and transitions (our own visuals), plus a co-op finisher cut-in. |
| Gun holder | Can only fire/recall or throw. Hands-free player does the world interaction. B's interactions are inverted. |
| Network | LAN with direct IP (ENet). Judges will have two PCs. |
| Enemies | Shoot back with slow bullets. Anchor elites need a pincer. |
| Handoff | Throw and catch, with floor pickup as a fallback. |
| Death | B can un-die A once per room. Otherwise the room restarts. |
| Comms | Talk out loud, plus pings, outlines and beacons. |
| Hands-free kit | Melee and props, B reverses bullets (3 s cooldown), break/un-break. |
| Roles | Fixed all game. LEON = A (forward), NOEL = B (inverted). |
| Look | Dark cyberpunk, restrained, with a hero revolver. B's screen is subtly colder. |
| Audio | One synth loop, reversed on NOEL's PC. |
| Story | Minimal Persona-style text cards. |
| Code | Start fresh. Old prototype moves to `old/`. |
| Title | Undecided. Working title ONE ROUND. |

## Open Questions

- Final title? ("ONE ROUND", "PALINDROME", "REWIND // RELOAD", ...)
- Do enemies target the gun holder first, the nearest player, or whoever last killed something?
- Room 4 layout: a balcony with a fall hazard, or keep it flat?
- Is a rank screen (S to C) worth it in 24h, or just show the time?
