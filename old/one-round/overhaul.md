# ONE ROUND: Overhaul Plan

ONE ROUND becomes a fast **co-op room-rush roguelite**. A run is 5–10 minutes: five short, randomly
ordered arena rooms, then a boss. LEON and NOEL still share **one revolver and one round**, and the
game is built around **charge and release**. Each player's kills power up the other's next move.
Standing still or passing slowly breaks the chain.

This plan replaces the slow "line it up, fire, wait, recall" pace. The dungeon visuals, networking,
room builder and most systems from the current build carry over (see "What we keep").

---

## 1. Core loop: charge and release

The 10-second cycle that repeats all game:

```
LEON fires ──► round pierces a line, lodges
      │           each kill CHARGES NOEL's recall
      │
      └─ throws gun ──► NOEL catches (mid-air / sliding = bonus chain)
                          │
               recall ◄── round tears back through a new line
                          │   each kill BUFFS LEON's next shot
                          │
               NOEL throws gun back ──► repeat
```

**Chain.** One shared team counter.
- +1 for each kill by the forward shot, +1 for each kill by the recall.
- +1 for a "flair catch": catching the gun while airborne, sliding, dashing or wall-running.
- The chain decays if no kill or catch happens for about 4 seconds.
- It resets to 0 if the gun hits the floor (a dropped catch) or a shot or recall kills nothing.

**Charge → release (starting values, all tunable):**

| Chain | LEON's next shot | NOEL's next recall |
|---|---|---|
| 0–1 | Normal pierce | Normal |
| 2–3 | +1 pierce, wider hit radius | Faster round, wider hit radius |
| 4 | Brief slow-mo on fire | Can **steer** the returning round (hold LMB) |
| 5+ | **Explosive lodge** (blast where the round lands) | **Explosive return** (blast at NOEL's feet when caught) |
| 8+ | Both: chain kills drop extra loot and add hourglass charge (see §3) | |

**Roles.** The abilities stay fixed: LEON only fires, NOEL only recalls.
- The **gun holder** is the *striker*: they line up the release.
- The **empty-handed** player is the *runner*. They move, punch, slide-kick enemies into the next
  line, use room devices, grab loot, and set up the catch.
- Throwing the gun swaps striker and runner, so neither player is ever idle.

**Hand-off.**
- Keep the physical throw (RMB).
- A mid-air or moving catch adds chain.
- A dropped gun breaks the chain, and either player can pick it up again.

---

## 2. Movement (both players, always)

Every move keeps momentum.

- **Slide:** sprint + crouch. Fits under gaps. A slide into an enemy is a **slide kick** (stun and knockback).
- **Vault / mantle:** automatic over low cover and onto ledges up to about 1.6 m.
- **Wall-run:** along any wall face for about 1.2 s. Jump off it to chain. Rooms get chasms built for it.
- **Dash:** a short burst with about a 3 s cooldown. It goes in your input direction, or the view direction while airborne.
- Movement upgrades extend these (see §6).

Moving fast feeds the chain through flair catches. Standing still is punished by rushers.

---

## 3. Time mechanics

**Hourglass meter (shared).**
- Filled by the chain: larger chains fill it faster.
- It has two spends, and either player can trigger one when it's full:
  - **Slow time:** about 4 s of team slow-mo, with enemies at 30% speed.
  - **Rewind (NOEL only):** the whole room rewinds 3 seconds. Enemies, enemy bullets, the round and
    broken objects all go back; players keep their positions. Used to undo a bad wave or
    reset a missed line.
- Hourglass pickups now add meter, instead of applying slow-mo directly.

**Temporal zones.**
- Rooms contain marked zones that run at different speeds:
  - **Fast zone (amber):** bullets and enemies inside move faster. The round gains extra pierce while passing through.
  - **Slow zone (cyan):** everything inside moves slowly. It's a safe aim pocket, and enemy bolts crawl through it.
- Some rooms have **fixed** zones. Upgrades and devices let players **create** them:
  - LEON's explosive lodge can leave a fast zone behind.
  - NOEL's caught recall can drop a slow zone.
- Zones fade after a few seconds.

---

## 4. Rooms

**Room pool.**
- 15–20 short hand-made ASCII arenas, each 30–90 seconds of play.
- Each run picks 5 at random (avoiding repeats), adds random **modifiers**, then ends on the boss room.
- The current room builder, legend and visuals stay.

**Pressure (every room):**
- **Waves + room timer:** 2–4 waves per room. A timer shows a par time, and beating it gives bonus loot.
- **Collapse / decay:** after the first wave, the room starts breaking up (floors crumble, fire
  grates spread, water rises). NOEL can rewind individual pieces, or slow it with a time spend.
- **Rushers:** see §5. They keep players moving.
- **Exit hold:** stepping on the exit plate triggers a final wave. Survive it with both agents in the lift.

**Puzzles folded into combat.** Puzzle pieces become quick combat tools, not separate puzzles.
- A forward-shot rune drops a **gate** on a group, or fires a trap.
- A recall rune slams a **pendulum** or extinguishes enemy cover fires.
- **Plates** under rushers' paths trigger spikes.
- **Braziers** NOEL keeps lit power a room-wide effect (light, or blocking a spawn door).
- **Bridges** LEON punches down drop whole waves into the chasm. NOEL restores them for the team.

**Modifiers** (rolled per room; some only appear as curses, see §6):
- Dark room (torches only, partner outline stronger)
- Double turrets
- Fragile floors (everything crumbles faster)
- Fast-zone room
- Armoured wave (more shield bearers)
- No hand-off flair (catches don't add chain, but loot ×1.5)

---

## 5. Enemies

| Enemy | Behaviour | Why it fits the loop |
|---|---|---|
| **Cultist** (current grunt) | Strafes, fires slow crossbow bolts | Baseline; bolts can be reversed by NOEL |
| **Rusher** (new) | Charges in melee, in groups of 2–4, in lines | Punishes standing still; lines are perfect pierces |
| **Shield bearer** (new) | Front shield blocks the forward shot, not the recall | Forces a recall kill or a flank by the runner |
| **Gargoyle sentry** (current turret) | Static and fires often | Area denial; must be pierced or avoided |
| **Lantern priest** (new) | Relights enemy braziers and re-breaks bridges, undoing NOEL | A priority target for the runner |
| **Anchor** (current) | Dies only to a pincer (shot + recall in the same cycle) | Mini-boss once per room at most; good chain fuel |

Waves mix these. Later rooms use more rushers and shield bearers.

---

## 6. Between rooms: the shop

After each room, the team spends shared loot. Three random offers appear, and each player picks
for themselves or for the team.

**Bullet mods**
- Ricochet: the shot banks off iron (gates, plates, braziers) once, twice at level 2.
- +1 base pierce.
- Curving recall: steer from chain 0 instead of chain 4.
- Lodge blast: explosive lodge at chain 3 instead of 5.
- Long lodge: the round can lodge in an enemy and drag them back on the recall.

**Movement mods**
- Extra dash charge.
- Longer wall-run.
- Slide kick knocks enemies into a line.
- Air dash refreshes on kill.

**Team mods**
- Faster catch window (bigger magnet).
- +1 revive charge (see §7).
- Revive from range.
- The chain decays more slowly.
- A larger hourglass meter.

**Curses for loot**
- Take a modifier on the next room (dark, double turrets, fragile floors, armoured wave) for about ×1.5–2 loot.
- Shown before the room starts.

---

## 7. Death and revive

- The current "un-die" is renamed **revive**.
- When LEON goes down, NOEL holds E on LEON's echo to rewind them back. This costs a revive charge;
  the run starts with 2.
- When NOEL goes down, LEON holds E on NOEL's body to pull them back up (forward heal). This costs the same charge.
- **No charges left and both down = the run ends.** The results screen shows the run's depth, chain
  record, loot and time.
- Revive charges can be bought in the shop, or found as rare echo orbs.

---

## 8. Boss: the Timekeeper

A fixed final room. The Order's timekeeper sits on the Throne of Hours.

- **Armoured like an Anchor:** only pincers damage it. It takes 3–5 pincers depending on curses.
- **Phase 1:** summons waves and fixed temporal zones.
- **Phase 2:** **rewinds the arena** every ~15 s. The round snaps back to where it was, so the team
  must pincer between rewinds. The hourglass rewind (NOEL) can cancel one.
- **Phase 3:** the arena collapses inward (decay). Fast-zone floor everywhere, and rushers keep coming.
- The run ends with victory and the results screen.

---

## 9. What we keep, change, cut

**Keep**
- Networking model (host-authoritative, request → broadcast), shared host clock
- One revolver / one round: fire, lodge, recall, throw, catch
- Dungeon visuals: shaders, materials, Humanoid bodies, lighting presets (F10/F11)
- ASCII room builder and legend
- Hazards (spikes, fire, blades)
- Glass system (bridges, crumble floors, urns, relics)
- Devices (runes, plates, gates, braziers)
- Pickups, HUD shell, cards, autotest framework

**Change**
- Room flow → waves + timer + exit hold. A room no longer "starts with N enemies".
- Restart-on-death → revive charges + run end.
- Hourglass pickup → fills the meter.
- Un-die → revive (and LEON can revive NOEL).
- Enemies → spawn in waves and move more aggressively.
- Rooms → shorter arenas, random order, modifiers.
- Puzzles → combat triggers.

**New**
- Chain / charge-and-release system and its HUD
- Hourglass meter, room rewind, temporal zones
- Movement kit (slide, vault/mantle, wall-run, dash)
- Rusher, shield bearer, lantern priest
- Shop + upgrades + curses
- Run structure (pool, modifiers, boss)

**Cut**
- The five fixed story rooms as a set sequence. They become pool rooms; story lines move to the
  intro, shop and boss cards.

---

## 10. Milestones

Each milestone should be playable and covered by the autotest before moving on.

1. **Feel first:** movement kit (slide, vault, wall-run, dash) in a test arena, plus networking
   check at speed.
2. **Chain:** charge-and-release tiers, flair catches, chain HUD, chain reset/decay.
3. **Rushers + waves:** wave spawner, room timer, exit hold. Convert the current 5 rooms.
4. **Time layer:** hourglass meter, slow time, NOEL's room rewind, temporal zones.
5. **Run structure:** room pool + random order, modifiers, revive charges, run end, results.
6. **Shop:** loot economy, upgrade offers, curses.
7. **More enemies:** shield bearer, lantern priest. Puzzle devices reworked as combat triggers.
8. **Boss:** the Timekeeper.
9. **Content:** grow the pool to 15–20 rooms, then balance and polish.

---

## 11. Open questions

- **Room rewind:** do players' positions rewind too, or only the world? The plan says only the world.
- **Rewind and networking:** a full room rewind needs every PC to snapshot enemies, bullets and
  glass state. How many seconds of history do we keep, and at what tick rate?
- **Wall-run walls:** do we need dedicated walls (e.g. marked brick), or does any wall work?
- **Shop picks:** does each player pick separately, or does the team vote on one offer?
- **Chain drops:** a dropped catch is a big punishment. Should it halve the chain rather than reset it?
- **Solo mode:** should solo test (one PC, Tab to swap) stay a supported way to play, or be dev-only?
