# UNWOUND

A singleplayer, time-bending roguelite FPS built in [Godot 4.7](https://godotengine.org/).
It plays like a stylised low-poly looter-shooter: fast movement, chunky guns, coin drops, loot beams
and big damage numbers. Your left hand bends time.

## The loop

- **Act** = 2 levels in one era (Ice Age → Ancient Egypt → The Far Future), each opening on its year.
- **Level** = 2 short combat rooms (waves of the Unwound) → the Clockmaker's shop → a portal on.
  The act's last level ends in a **boss** room.
- Every cleared fight drops an **hourglass**: pick 1 of 3 **time powers**.
- **Era select** (after hero and difficulty) starts the run in any era, or straight at its boss.
- The **shop** (Brotato-style) has 4 slots of weapons and stat items, with **reroll** and **lock**.
  Coins come from enemies and chests.

## Controls

| Key | Action |
|---|---|
| WASD / Space / Shift | Move / double jump / hero mobility move |
| LMB / RMB / R | Fire / aim / reload |
| 1 / 2 | First / second weapon |
| E | Hero skill (e.g. Pip's **Stasis**: freeze an enemy, a shot, or a falling rock to stand on) |
| Q | Ultimate, charged by dealing damage |
| F | Interact |
| Hold Tab | View your current stats |
| Esc | Pause |

## Code

All content is built at runtime from primitives (no imported models).

| File | What |
|---|---|
| `autoload/run.gd` | Run state and content tables: weapons, items, time powers, shop |
| `scripts/main.gd` | Game flow: title, rooms, menus, level advance |
| `scripts/arena.gd` | Room builder per biome (sky, fog, faceted rocks, cover), waves, rockfalls |
| `scripts/player.gd` / `gun.gd` | FPS controller and abilities / viewmodel, firing, reloading |
| `scripts/enemy.gd` / `boss.gd` | The Unwound enemy types, dressed per era / the era's boss |
| `tools/make_audio.py` | Synthesises the music loops and the room-clear chime (`python3 tools/make_audio.py`) |
| `scripts/cutscene.gd` | Boss intro and slow-mo boss death |
| `scripts/faller.gd`, `slow_field.gd`, `projectile.gd` | Time-aware objects |
| `scripts/hud.gd`, `screens.gd` | HUD and menus |
| `scripts/kit.gd` | Toon materials, ink outlines, faceted meshes, effects, sound |

## Test

```
godot --headless -- --autotest
```

The previous project (ONE ROUND) is kept in `old/one-round/` (Godot ignores it).
