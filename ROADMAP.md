# WaveSurvivalArena — Product Roadmap

> Living document. Captures the long-term vision beyond the current learning
> prototype. The wave-survival mechanic built so far is the technical
> foundation; this roadmap describes where the concept is heading.

## Vision

A wave-based **"farm defense"** game with a light, absurd tone. The player
protects their crops (grass) from waves of cows that advance to eat them. The
existing Scene Graph example assets are repurposed into a coherent concept:

- **Cows** → the enemies. They arrive in escalating waves and threaten the crop.
- **Grass / crop** → what the player must protect (and, later, plant and grow).
- **UFO** → a special ability. Once charged, the player can send it to abduct a
  single cow or a cluster of cows in an area.

The design leans into the original Scene Graph demo (a UFO abducting cows), so
the assets are used with their grain, not against it.

## Current status (learning prototype)

Built and working:

- Wave spawning as Scene Graph entities (cow prefab `P_Cow`), scattered
  randomly without overlap inside a rectangular **spawn zone** defined by two
  editable corner props (`spawn_zone` struct + `MakeZoneFromCorners`).
- Per-enemy `health_component` (max health, `ApplyDamage`, `EliminatedEvent`).
- Damage application and elimination of dead enemies.
- Automatic wave chaining with scaling difficulty and a win condition
  (`MaxWaves`), protected by a generation-sealing mechanism against stale tasks.
- Per-enemy async death watchers + atomic live counter for wave-clear detection.
- Editable uniform enemy scale.
- **Pasture zone** defined the same way (two corner props), reusing `spawn_zone`.
- Enemies **move in a straight line toward the pasture** via keyframed movement
  (`keyframed_movement_component`), each to its own randomized target, at an
  editable speed, and **oriented toward their direction of travel** (yaw from
  `ArcTan`, with an editable facing offset to correct for the asset's model).

This is **mechanic-complete for a demo**. The main remaining abstraction is
that damage still comes from a debug button, not from real gameplay.

### Known limitations (by design, for now)
- Movement is straight-line only — no navigation/pathfinding exists in the SDK.
  Spawn and pasture zones must have clear line of sight between them.
- Kinematic keyframe movement likely ignores collisions, so cows may pass
  through each other and through geometry.
- Orphaned death-watcher tasks leak if a wave is restarted mid-flight (tasks
  can't be cancelled in this SDK version). Acceptable; a `race`-based fix is
  noted for later.

## Roadmap phases (post-demo)

### Phase A — From "button damage" to real gameplay
- [DONE] Cows now **advance toward the pasture** instead of standing still
  (keyframed movement, oriented, per-enemy targets).
- [TODO] Replace the debug damage button with a real damage source: proximity/
  zone damage as the player approaches cows, or a projectile if the player
  gets a weapon.

### Phase B — The crop to protect
- [PARTIAL] The **pasture zone** already exists and cows already move toward it.
  What's missing is making it a real defense target rather than just a
  destination.
- [TODO] Introduce **grass/crop entities** in the pasture as the thing to protect.
- [TODO] Cows that reach the pasture damage or consume the crop (lose condition
  tied to crop health, not player health) — currently cows just arrive and stop.
- [TODO] Simple visual feedback for crop state (healthy → eaten).
- [FUTURE] Multiple pasture zones, with each cow heading to the nearest one
  (the `spawn_zone` design already makes multiple zones cheap to add).

### Phase C — Planting and growth
- Let the player **plant new grass** during or between waves.
- Grass has a growth timer before it counts as "protected value".
- Introduces a resource/economy loop (planting costs something).

### Phase D — The UFO special ability
- The UFO becomes a **chargeable special**: a meter fills over time or with kills.
- When ready, the player triggers it to **abduct a cow or an area of cows**.
- Reuses the abduction logic already present in the Scene Graph example
  (`FindOverlapHitsExampleComponent` finds cows in a volume; the UFO animation
  and beam assets already exist).

### Phase E — A proper level
- Move from the current Scene Graph example corridor to a **larger, open level**
  suited to defending a field.
- Consider a minimap / overview of the farm.
- Reposition the wave system, spawn markers and crop targets in the new level.

## Deferred / open questions
- Enemy variety (fast cows, tanky cows?).
- Multiple crop plots vs. a single field.
- Scoring / progression between runs (ties into the persistence phase from the
  original plan).
- UI/UX pass (deliberately deferred to late in the project).

## Guiding principles (unchanged from the learning project)
- English for all code, comments, names and player-facing text.
- Minimal reliance on legacy Fortnite devices; logic in Verse + Scene Graph.
- Small, verifiable steps; compile after each change.
- UI/UX comes last, once mechanics are stable.
