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

Built and working as of the current phase:

- Wave spawning as Scene Graph entities, with editable count, spacing and marker.
- Per-enemy `health_component` (max health, `ApplyDamage`, `EliminatedEvent`).
- Damage application and elimination of dead enemies.
- Automatic wave chaining with scaling difficulty and a win condition
  (`MaxWaves`), protected by a generation-sealing mechanism against stale tasks.
- Enemy visual = cow prefab (`P_Cow`).

This foundation is **mechanic-complete for a demo** but cosmetic and abstract
(damage comes from a button, not from gameplay).

## Roadmap phases (post-demo)

### Phase A — From "button damage" to real gameplay
- Replace the debug damage button with a real damage source.
- Cows should **advance toward the crop** rather than stand still (movement
  component, likely built on the existing `SimpleMovementComponent`).
- Player action to stop cows: proximity/zone damage, or a projectile if the
  player gets a weapon.

### Phase B — The crop to protect
- Introduce **grass/crop entities** placed in the level as the defense target.
- Cows that reach the crop damage or consume it (lose condition tied to crop
  health, not player health).
- Simple visual feedback for crop state (healthy → eaten).

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
