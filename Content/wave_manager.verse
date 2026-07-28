# `using` statements import Verse modules (like namespaces).
# Each device/type/function lives in a module, and you must import
# the module before you can reference its names.
using { /Fortnite.com/Devices }                     # button_device, creative_device
using { /Verse.org/Simulation }                     # agent (a player/AI actor)
using { /Verse.org/SceneGraph }                     # entity, GetSimulationEntity, AddEntities
# CAREFUL: two incompatible SpatialMath modules exist in UEFN.
#   /UnrealEngine.com/Temporary/SpatialMath -> classic vector3, fields X/Y/Z.
#   /Verse.org/SpatialMath                  -> Scene Graph vector3, fields
#                                              Left/Up/Forward (LUF).
# Their vector3/transform types do NOT convert into each other, so this file
# imports ONLY the Verse.org one: the bare name `vector3` always means LUF here.
#
# Devices and props are NOT stuck in the classic world. The `positional`
# interface they all inherit exposes BOTH getters:
#   Thing.GetTransform()       -> classic transform (X/Y/Z)   <- do NOT use here
#   Thing.GetGlobalTransform() -> Scene Graph transform (LUF)  <- use this one
# Picking the right getter is what keeps the two worlds from mixing.
using { /Verse.org/SpatialMath }                    # transform, vector3 (LUF)
using { /UnrealEngine.com/Temporary/Diagnostics }   # Print

# Wave Manager: entry point for the arena's game flow.
# Phase 1 goal: react to a button press. This is the core
# device-to-Verse event pattern used throughout the project.
#
# `class(creative_device)` means this class INHERITS from creative_device.
# A creative_device is the bridge between Verse and UEFN: once compiled,
# it shows up in the editor as a device you drop into the level, and it
# receives lifecycle callbacks like OnBegin.
wave_manager := class(creative_device):

    # @editable exposes this field in the UEFN Details panel, so a designer
    # can link the real Button placed in the level WITHOUT touching code.
    # The `= button_device{}` part is a required default value; it gets
    # overwritten by whatever button you assign in the editor.
    @editable
    StartButton : button_device = button_device{}

    # Second button: every press damages the whole current wave at once.
    @editable
    DamageButton : button_device = button_device{}

    # WHERE enemies spawn. Instead of hardcoding coordinates, drop any prop in
    # the level at the desired spot and assign it here in the Details panel:
    # the spawn point then becomes something you move visually in the editor.
    #
    # `creative_prop` is the right pick because it:
    #   * is `concrete`, so `creative_prop{}` is a legal default value;
    #   * inherits GetGlobalTransform() -> LUF transform, exactly what Scene
    #     Graph's SetGlobalTransform expects (no type conversion needed);
    #   * provides the failable IsValid[], which lets us detect the default
    #     placeholder above (i.e. "designer forgot to assign it").
    @editable
    SpawnMarker : creative_prop = creative_prop{}

    # Size of wave 1. Later waves derive their size from this - see StartWave.
    @editable
    EnemiesPerWave : int = 5

    # Extra enemies added per wave: 5, 7, 9, 11... with the defaults.
    @editable
    EnemiesIncrementPerWave : int = 2

    # Waves needed to win. Clearing this many ends the run instead of chaining.
    @editable
    MaxWaves : int = 5

    # Seconds of breathing room between clearing a wave and the next one.
    @editable
    TimeBetweenWaves : float = 3.0

    # Distance in centimeters between two consecutive enemies in the row.
    # Also editable so the spacing can be eyeballed in-game and adjusted.
    @editable
    EnemySpacing : float = 200.0

    # Damage dealt to EVERY living enemy per DamageButton press. With the
    # health_component default of 100 max health, 34.0 means three presses kill.
    @editable
    DamagePerHit : float = 34.0

    # EVERYTHING spawned in the current wave, alive or dead. This is NOT the
    # live-enemy list: dead enemies stay in here until the whole wave is
    # cleared. Its only job is to give ClearCurrentWave something to sweep, and
    # to give the damage pass something to iterate.
    #
    # Re-damaging a dead enemy through this list is harmless: health_component's
    # ApplyDamage ignores damage once CurrentHealth is 0, so it never fires
    # EliminatedEvent twice. That guard is what lets us skip all list surgery.
    var SpawnedEnemies : []entity = array{}

    # How many enemies of the current wave are still alive. THE authority on
    # "is the wave cleared" - deliberately not derived from SpawnedEnemies,
    # which can be mid-update when a death is processed (see OnEnemyDied).
    # Only OnEnemyDied decrements it; only the spawn loop and ClearCurrentWave
    # assign it.
    var LiveEnemyCount : int = 0

    # Which wave is running (1-based). Drives difficulty and the log messages.
    var CurrentWaveNumber : int = 0

    # Monotonic stamp bumped by EVERY StartWave call and never reset. Watchers
    # and the chaining task capture it and compare before acting, so anything
    # belonging to a previous wave becomes a no-op.
    #
    # This exists instead of comparing CurrentWaveNumber because wave numbers
    # REPEAT: press Start while a chain is sleeping and CurrentWaveNumber goes
    # back to 1, which the sleeping chain would read as "still my wave" and it
    # would then overwrite the wave you just asked for. A number that only ever
    # increases cannot be confused that way.
    var WaveGeneration : int = 0

    # OnBegin runs ONCE when the game starts. `<override>` says we are
    # replacing the empty base version defined in creative_device.
    # `<suspends>` marks this as an async function: it is allowed to
    # pause and resume (e.g. wait on events over time) without blocking
    # the game. OnBegin must always carry this specifier.
    OnBegin<override>()<suspends> : void =
        Print("Wave Manager started")
        # Subscribe registers a callback on an event. From now on, every
        # time a player interacts with StartButton, InteractedWithEvent
        # fires and calls OnStartPressed, passing along the interacting agent.
        StartButton.InteractedWithEvent.Subscribe(OnStartPressed)
        DamageButton.InteractedWithEvent.Subscribe(OnDamagePressed)

    # Removes the enemies of the previous wave from the world and forgets them.
    #
    # Called by StartWave before every spawn, so one wave's leftovers can never
    # pile up on the next one. With automatic chaining this is usually a no-op
    # on already-dead entities: the next wave only starts once the previous one
    # is at zero. It only really removes living enemies when the player presses
    # Start mid-wave.
    ClearCurrentWave() : void =
        # Read the count BEFORE clearing, so the log can report it.
        RemovedCount : int = SpawnedEnemies.Length

        for (Enemy : SpawnedEnemies):
            # RemoveFromParent is the Scene Graph way to take an entity out of
            # the world - it is the counterpart of AddEntities and the same call
            # the SpawnPrefabDevice.verse sample uses to despawn.
            # It is NOT failable (returns void, no `[]`), so it needs no guard,
            # and it cascades: the prefab's child entities and components run
            # their OnEndSimulation too, so the whole light post disappears.
            Enemy.RemoveFromParent()

        # Drop every reference. `array{}` is an empty array literal; its type is
        # inferred from the field, which is already declared as []entity.
        set SpawnedEnemies = array{}

        # Reset the live count too. The spawn loop overwrites this a moment
        # later, but not if it bails out on a failed guard - and a stale count
        # would leave the wave permanently "not cleared".
        #
        # NOTE: enemies wiped this way are removed WITHOUT dying, so their
        # WatchEnemyDeath tasks stay parked on Await() forever. Accepted for
        # now: `task` has no Cancel in this SDK, and the fix (race against a
        # wave-ended event) is a separate step.
        set LiveEnemyCount = 0

        Print("Cleared previous wave - {RemovedCount} enemies removed")

    # The event handler. Its signature must match what the event sends:
    # InteractedWithEvent sends an `agent`, so we receive one here.
    # (`InAgent` is the value; `agent` is the type — Verse is case-sensitive.)
    #
    # The button only kicks off the sequence at wave 1; every later wave is
    # chained automatically by ChainNextWave. Pressing it again always restarts
    # from wave 1, including after a victory - StartWave has no precondition.
    OnStartPressed(InAgent : agent) : void =
        Print("Start button pressed - restarting the run at wave 1")
        StartWave(1)

    # Spawns wave `WaveNumber`. THE single spawn path: both the button and the
    # automatic chaining go through here, so the spawn logic exists once.
    #
    # ATOMICITY - this is load-bearing. This function contains no suspension
    # point (no Await, no Sleep), and Verse is cooperatively scheduled on a
    # single thread. So it runs start to finish without any watcher, damage
    # press or chain task interleaving. That is what makes the sequence
    # clear -> restamp -> spawn -> set count safe without any locking.
    StartWave(WaveNumber : int) : void =
        # 1. Sweep the previous wave out of the world first, so nothing old is
        #    left behind and LiveEnemyCount starts from a known 0.
        ClearCurrentWave()

        # 2. Establish the new identity BEFORE any watcher for this wave exists,
        #    so every watcher below is stamped with the correct generation and
        #    anything still holding the old stamp is now invalid.
        set WaveGeneration += 1
        set CurrentWaveNumber = WaveNumber
        ThisGeneration : int = WaveGeneration

        # 3. Derive the size from the wave number rather than accumulating it in
        #    a variable: wave 1 -> EnemiesPerWave, and each wave after adds
        #    EnemiesIncrementPerWave. Pure integer arithmetic, and re-tuning the
        #    editable values re-shapes the whole progression from the next wave.
        EnemyCount : int = EnemiesPerWave + (WaveNumber - 1) * EnemiesIncrementPerWave

        Print("--- Wave {WaveNumber} of {MaxWaves} starting: {EnemyCount} enemies ---")

        # GetSimulationEntity[] returns the ROOT of the Scene Graph world.
        # It is failable (note the [] brackets), so we guard it with `if`.
        # We add spawned entities as children of this root.
        if:
            SimulationEntity := GetSimulationEntity[]
        then:
            # IsValid[] is failable. It fails when SpawnMarker is still the
            # default `creative_prop{}` placeholder, i.e. nothing was assigned
            # in the Details panel. Guarding here means a forgotten assignment
            # just logs a warning instead of spawning somewhere meaningless.
            if:
                SpawnMarker.IsValid[]
            then:
                # Read the marker's position ONCE, outside the loop: it is the
                # anchor every enemy is placed relative to.
                # GetGlobalTransform() (NOT GetTransform()) returns a
                # /Verse.org/SpatialMath transform, so its Translation is
                # already a LUF vector3 and needs no conversion.
                MarkerTranslation : vector3 = SpawnMarker.GetGlobalTransform().Translation

                # Placement pattern: a straight row along the LEFT axis.
                # Enemy 0 lands exactly on the marker, and each following one is
                # EnemySpacing centimeters further along Left. Up and Forward are
                # copied from the marker untouched, so the whole row shares its
                # height and depth and nobody floats or sinks.
                #
                # The offset is accumulated instead of computed as
                # `Index * EnemySpacing`: Index is an int and EnemySpacing a
                # float, and Verse has no implicit int-to-float conversion.
                var CurrentOffset : float = 0.0

                # Counts enemies that are actually WATCHABLE (component attached
                # and readable back). LiveEnemyCount is seeded from this, not
                # from EnemiesPerWave: an enemy nobody is watching can never
                # report its death, so counting it would leave the wave stuck
                # at "not cleared" forever.
                var WatchedCount : int = 0

                for (Index := 0..EnemyCount - 1):
                    # Instantiate a prefab. A prefab is a pre-assembled entity
                    # (mesh + components). `LightPost.P_LightPost{}` is used here
                    # as a visible PLACEHOLDER until we build a real enemy prefab.
                    Enemy : entity = LightPost.P_LightPost{}

                    # AddEntities inserts the new entity into the live world.
                    # Until this call, the prefab exists but is not "in the scene".
                    SimulationEntity.AddEntities(array{ Enemy })

                    # We build the translation field by field and rebuild the
                    # transform from scratch, so each enemy ignores whatever
                    # rotation/scale the marker prop happens to have and keeps
                    # identity rotation + scale 1 (upright, full size).
                    SpawnTranslation : vector3 = vector3{ Left := MarkerTranslation.Left + CurrentOffset, Up := MarkerTranslation.Up, Forward := MarkerTranslation.Forward }
                    SpawnTransform : transform = transform{ Translation := SpawnTranslation }
                    Enemy.SetGlobalTransform(SpawnTransform)

                    # Give the enemy its health.
                    #
                    # A component must be told its parent entity AT CONSTRUCTION:
                    # the digest states components "must have a parent entity
                    # pointer provided when being constructed" and can never be
                    # moved between parents. That is why `Entity` is the only
                    # field of `component` without a default value.
                    #
                    # This runs AFTER AddEntities and AFTER SetGlobalTransform on
                    # purpose. Per the AddComponents docs, OnBeginSimulation fires
                    # immediately when the entity is already simulating, so doing
                    # it last means the component starts up with the enemy already
                    # at its final position. Irrelevant for health, but it is the
                    # right habit before movement/range components arrive.
                    NewHealthComp : health_component = health_component{ Entity := Enemy }
                    Enemy.AddComponents(array{ NewHealthComp })

                    # Read the component BACK OFF the entity instead of reusing
                    # NewHealthComp. That is deliberate: it proves the
                    # entity -> component lookup works, which is the mechanism the
                    # live-enemy count will depend on. We keep no parallel array of
                    # components; the entity is the single source of truth.
                    if:
                        AttachedHealthComp := Enemy.GetComponent[health_component]
                    then:
                        Print("Enemy {Index} has a health_component with {AttachedHealthComp.MaxHealth} max health")

                        # Start listening for THIS enemy's death. One task per
                        # enemy is the only shape that works: Await() blocks on a
                        # single event, and sync{} needs a branch count fixed at
                        # compile time, so neither can cover a dynamic N.
                        #
                        # `spawn` launches the task without suspending us - the
                        # task runs until its Await() and parks there. Calling it
                        # from a non-suspends handler is fine; see
                        # EntityEnteredExampleComponent.verse:29 for the same shape.
                        #
                        # We hand it AttachedHealthComp (the one read back off the
                        # entity), not NewHealthComp, so we only ever watch a
                        # component that is genuinely attached.
                        #
                        # ThisGeneration is captured now and travels with the
                        # task, so when it finally wakes it can tell whether its
                        # wave is still the current one.
                        spawn { WatchEnemyDeath(AttachedHealthComp, ThisGeneration) }
                        set WatchedCount += 1
                    else:
                        Print("WARNING: enemy {Index} has no health_component after AddComponents")

                    # Track it so ClearCurrentWave can sweep it later. Note this
                    # keeps growing with dead enemies too - see the field comment.
                    set SpawnedEnemies += array{ Enemy }

                    set CurrentOffset += EnemySpacing

                # Seed the live count from the enemies we are actually watching.
                # Assigned once, after the loop: no death can have happened yet,
                # because nothing has damaged anyone.
                set LiveEnemyCount = WatchedCount

                Print("Wave {CurrentWaveNumber} spawned - {LiveEnemyCount} enemies alive")
            else:
                Print("WARNING: SpawnMarker is not assigned - place a prop in the level and assign it in the wave_manager Details panel")
        else:
            Print("WARNING: no simulation entity available - cannot spawn")

    # Applies one hit of damage to the whole wave.
    #
    # This handler no longer decides who died. It only deals damage; death is
    # detected by WatchEnemyDeath through EliminatedEvent. That split is the
    # whole point: when damage starts coming from weapons or traps there will be
    # no central place to check health, so death handling must live with the
    # component, not with whatever caused the hit.
    #
    # It walks the full SpawnedEnemies list, dead ones included. Harmless:
    # ApplyDamage returns early once CurrentHealth is 0, so a corpse absorbs
    # nothing and re-fires nothing.
    OnDamagePressed(InAgent : agent) : void =
        Print("Damage button pressed - {DamagePerHit} damage to the wave ({LiveEnemyCount} alive, {SpawnedEnemies.Length} tracked)")

        for (Enemy : SpawnedEnemies):
            if:
                HealthComp := Enemy.GetComponent[health_component]
            then:
                HealthComp.ApplyDamage(DamagePerHit)
            else:
                Print("WARNING: a tracked enemy has no health_component - cannot damage it")

        Print("Damage pass done - {LiveEnemyCount} still alive")

    # One instance of this task runs per living enemy, parked on Await() until
    # that specific enemy dies. Launched by the spawn loop via `spawn`.
    #
    # No cancellation: `task` in /Verse.org/Concurrency exposes only Await(),
    # not Cancel. So if a wave is wiped by ClearCurrentWave instead of being
    # killed, these tasks park forever. Accepted for now; the fix is to race
    # this against a wave-ended event, which is a separate step.
    WatchEnemyDeath(HealthComp : health_component, Generation : int)<suspends> : void =
        # Await returns the payload of EliminatedEvent, which is the entity that
        # died - so we do not need to capture the entity separately.
        DeadEntity : entity = HealthComp.EliminatedEvent.Await()

        # Removing from the world now happens HERE, at the moment of death,
        # rather than in the damage handler. Any future damage source gets this
        # behaviour for free.
        DeadEntity.RemoveFromParent()

        OnEnemyDied(Generation)

    # Single place where the live count goes down, and the only place that
    # decides a wave is cleared.
    #
    # No data race is possible: Verse is cooperatively scheduled, so a task runs
    # from resume to its next suspension point without interruption. There is no
    # Await or Sleep between the decrement and the check, so the two are atomic
    # and two near-simultaneous deaths are processed one after the other.
    #
    # What actually guarantees the count is trustworthy is health_component's
    # own `if (CurrentHealth > 0.0)` guard in ApplyDamage: it makes each enemy
    # fire EliminatedEvent at most once per life, so nobody is counted twice.
    OnEnemyDied(Generation : int) : void =
        # Stale-watcher guard. A watcher left over from an abandoned wave cannot
        # actually fire (its entity is out of the scene, so nothing damages it
        # and nothing signals its event), but comparing stamps turns that from
        # "should not happen" into "cannot happen": an old stamp means an old
        # wave, and old waves may not touch the current counter.
        if (Generation = WaveGeneration):
            set LiveEnemyCount -= 1
            Print("Enemy eliminated - {LiveEnemyCount} enemies left alive")

            # `<= 0` rather than `= 0` so an unexpected extra death can never
            # step over the condition and leave the wave permanently uncleared.
            if (LiveEnemyCount <= 0):
                Print("Wave {CurrentWaveNumber} cleared!")

                # The cap lives HERE, on the chaining decision, not in
                # StartWave. StartWave stays unconditional, which is what keeps
                # the Start button able to restart from wave 1 at any time,
                # including after a win.
                if (CurrentWaveNumber >= MaxWaves):
                    Print("All {MaxWaves} waves survived - you win!")
                else:
                    # Hand the wait to a separate task so THIS function stays
                    # non-suspending. Sleeping inline would put a suspension
                    # point between the decrement and the check above and
                    # destroy the atomicity the whole design relies on.
                    spawn { ChainNextWave(Generation) }

    # Waits out the gap between waves, then starts the next one.
    ChainNextWave(FromGeneration : int)<suspends> : void =
        Sleep(TimeBetweenWaves)

        # Re-check the stamp AFTER sleeping. During those seconds the player may
        # have pressed Start, which bumps WaveGeneration; chaining anyway would
        # wipe the wave they just asked for and skip ahead a number.
        if (FromGeneration = WaveGeneration):
            StartWave(CurrentWaveNumber + 1)
        else:
            Print("Wave chain cancelled - a new wave was started during the break")
