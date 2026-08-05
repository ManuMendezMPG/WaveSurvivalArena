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
- **Arrival detection** per enemy, awaiting the movement component's
  `FinishedEvent`, guarded so a cow killed in transit never reports an arrival.
- **Crop health** (`CropHealth`, with editable max, per-tick damage and tick
  interval), clamped at zero. Crop health is run-scoped: it resets when a run
  starts, not per wave, so damage accumulates across the whole run.
- **Continuous grazing damage**, not a single bite on arrival. A cow that reaches
  the pasture keeps draining the crop on a timed loop for as long as it stands
  there, so what matters for balance is the *rate*. The loop re-checks four stop
  conditions before every subtraction — wave generation, `RunHasEnded`,
  `GetParent` and the cow's own health — so a cow that is sedated, killed, swept
  by a new wave or caught by the end of a run stops costing the player
  immediately, and the polling delay can never cost crop health.
- A **complete game loop with both endings**: victory for surviving `MaxWaves`,
  defeat when the crop reaches zero. Defeat announces itself, sweeps the
  surviving cows out of the world and invalidates everything in flight.
- Both endings close through a single shared latch (`RunHasEnded`), so they are
  mutually exclusive and each fires exactly once even when several cows arrive
  in the same instant. Pressing Start always begins a clean run.
- **Sedating cows by hand**: approach a cow and stay near it for a few seconds
  (`basic_interactable_component` with an editable duration, which drives
  Fortnite's native hold-progress bar). Walking away or moving off the cow
  cancels the attempt and the cow resumes its walk exactly where it left off.
  This is the first neutralization that comes from the player rather than from a
  debug affordance.
- Sedation travels the **same channel as death** (`health_component.EliminatedEvent`),
  so the live counter, the generation seal and the wave/victory decisions need no
  knowledge that sedation exists. An `IsSedated` flag on the component is the only
  thing that differs, and it decides one thing: a sedated cow's **body stays in
  the world** instead of being removed.
- **Visual feedback for "asleep"**: a sedated cow is flattened vertically, by
  rewriting its transform with a reduced vertical scale applied over the spawn
  scale cached per cow at spawn time (`sleep_visual_component`). It composes with
  the editable uniform enemy scale rather than replacing it, so the cow keeps its
  footprint and length and stays recognisable. The flatten factor is editable.
- **Visible grass in the pasture zone** as level decoration, so the area the cows
  are walking to can be seen rather than inferred from the log.

This is **mechanic-complete for a demo**: a full run can now be won or lost, and
the player has one real way to fight back — sedating cows by hand. The remaining
abstraction is that this is the *only* one: it is deliberately slow and
single-target, so the debug damage button is still what handles a whole wave.

### Known limitations (by design, for now)
- Movement is straight-line only — no navigation/pathfinding exists in the SDK.
  Spawn and pasture zones must have clear line of sight between them.
- Kinematic keyframe movement likely ignores collisions, so cows may pass
  through each other and through geometry.
- Orphaned death-watcher tasks leak if a wave is restarted mid-flight (tasks
  can't be cancelled in this SDK version). Acceptable; a `race`-based fix is
  noted for later.
- Arrival-watcher tasks leak the same way, but **during normal play**: every cow
  killed before it reaches the pasture leaves one parked forever. Bounded and
  harmless — the latch and generation seal neutralise their effects — but this
  is the strongest argument for the `race` fix, which would cancel both watchers
  at once.
- The crop is **a number, not a thing in the world**. There is nothing to look
  at, so its state is only visible in the log.
- The debug damage button is not gated by `RunHasEnded`. Pressing it after a run
  ends is harmless (the wave list is empty) but still logs a line.
- **Tinting the cow body from Verse is not available in UEFN 41.30**: the SDK
  exposes no material-parameter write API (no `SetControlValue` or equivalent),
  the `material` type is `epic_internal` with no setters, and the experimental
  Scene Graph flag that might expose such an API also blocks island publishing.
  Sleep state is therefore conveyed by flattening the mesh instead of tinting it
  blue. Revisit if a future UEFN version adds a material-parameter API without the
  publishing restriction.

## Roadmap phases (post-demo)

### Phase A — From "button damage" to real gameplay
- [DONE] Cows now **advance toward the pasture** instead of standing still
  (keyframed movement, oriented, per-enemy targets).
- [DONE] **First real damage source: hold-to-sedate.** The player approaches a cow
  and stays close for an editable duration to neutralize it; moving away cancels.
  It routes through `EliminatedEvent` like any death, and leaves the body in the
  world with a visible "asleep" state (flattened mesh).
- [TODO] A damage source that **scales to a whole wave**. Sedation is one cow at a
  time and deliberately slow, so the debug button is still doing the heavy
  lifting: proximity/zone damage, or a projectile if the player gets a weapon.
  This is now the largest remaining gap between the prototype and something
  playable.

### Phase B — The crop to protect
- [DONE] The **pasture zone** exists (two editable corner props, reusing
  `spawn_zone`) and cows move toward their own randomized point inside it.
- [DONE] Cows that reach the pasture **consume the crop continuously**: arrival is
  detected per enemy, and from then on a timed loop drains `CropHealth` for as long
  as that cow is still standing there and still a threat. Balance is a rate, so
  sedating fast is now the way to save the crop.
- [DONE] **Lose condition tied to crop health**, not player health — the run
  ends in defeat when the crop hits zero.
- [PARTIAL] **Grass is visible in the pasture**, but only as level decoration: it
  is not an entity, it is not tied to `CropHealth`, and eating it changes nothing
  about how it looks. The zone can now be seen; the crop still cannot.
- [TODO] Promote the grass to real **crop entities** — the thing that is actually
  being protected, rather than a number with scenery next to it.
- [TODO] Simple visual feedback for crop state (healthy → eaten), so the player
  can read how the run is going without the log. The sedated-cow flatten is the
  precedent to follow: state made readable without any UI.
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
