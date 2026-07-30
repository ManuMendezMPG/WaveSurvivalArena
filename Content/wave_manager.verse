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
using { /Verse.org/SceneGraph/KeyframedMovement }   # keyframed_movement_component, deltas, easing
using { /Verse.org/SpatialMath }                    # transform, vector3 (LUF), Distance, DistanceForwardLeft
using { /Verse.org/Random }                         # GetRandomFloat
using { /Verse.org/Verse }                          # Min, Max
using { /UnrealEngine.com/Temporary/Diagnostics }   # Print

# An axis-aligned rectangular area of the world, in Scene Graph LUF
# centimeters. Held as min/max per axis rather than centre+size because that is
# what random placement actually needs: GetRandomFloat takes a low and a high.
#
# `Up` is a single value, not a range: areas are flat, and everything placed in
# one sits on that height.
#
# Rotation is ignored on purpose - the rectangle is always aligned to the world
# axes. A room set at an angle will not be followed exactly.
#
# This type exists to be REUSED: the upcoming pasture area will be another
# spawn_zone built the same way, with its own pair of corner props.
spawn_zone := struct:
    MinLeft : float
    MaxLeft : float
    MinForward : float
    MaxForward : float
    Up : float

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

    # The spawn area, defined by two props dropped at OPPOSITE CORNERS of the
    # rectangle. Drag them to the corners of the room you want covered and the
    # zone is sized visually, with no numbers to guess.
    #
    # Which one is A and which is B does not matter: MakeZoneFromCorners takes
    # the min and max of each axis, so any diagonal pair works.
    #
    # Two positions rather than one prop plus a Scale: `transform.Scale` is a
    # multiplier, so turning it into centimeters would need the marker mesh's
    # base size as an extra calibration value. Two corner positions are already
    # LUF centimeters - nothing to convert, which is the whole point.
    #
    # `creative_prop` is the right pick because it:
    #   * is `concrete`, so `creative_prop{}` is a legal default value;
    #   * inherits GetGlobalTransform() -> LUF transform, exactly what Scene
    #     Graph's SetGlobalTransform expects (no type conversion needed);
    #   * provides the failable IsValid[], which detects the default
    #     placeholder above (i.e. "designer forgot to assign it").
    @editable
    SpawnAreaCornerA : creative_prop = creative_prop{}

    @editable
    SpawnAreaCornerB : creative_prop = creative_prop{}

    # The PASTURE area, defined exactly like the spawn area above: two props at
    # opposite corners, fed through the same MakeZoneFromCorners. This is the
    # reuse the spawn_zone struct was designed for.
    #
    # Nothing moves towards it yet - this step only defines and logs the zone.
    @editable
    PastureCornerA : creative_prop = creative_prop{}

    @editable
    PastureCornerB : creative_prop = creative_prop{}

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

    # How far apart two enemies of the same wave should ideally be, in
    # centimeters, measured on the ground plane.
    @editable
    MinDistanceBetweenEnemies : float = 200.0

    # How many random points to try before giving up and accepting a spot that
    # is too close. A cap, not a target - see PickSpawnPosition.
    @editable
    MaxPlacementAttempts : int = 10

    # How fast enemies walk to the pasture, in centimeters per second. Travel
    # time is derived from this and the distance, so enemies starting further
    # away take proportionally longer instead of all arriving together.
    #
    # 0 or less means "do not move" and is handled explicitly - see
    # MoveEnemyToPasture. Never used as a divisor without that check.
    @editable
    EnemySpeed : float = 100.0

    # Correction added to the computed facing angle, in degrees.
    #
    # Two things this code cannot know decide whether enemies end up facing the
    # right way: which local axis the P_Cow model was authored looking down, and
    # the exact sign convention of the LUF yaw. Both fail the same way - every
    # enemy turned by the same fixed amount - and both are fixed by the same
    # constant. So it is a dial you turn in the editor (try 90, -90 or 180)
    # instead of a guess baked into the code.
    @editable
    EnemyFacingOffsetDegrees : float = 0.0

    # Uniform size multiplier for spawned enemies: 1.0 is the prefab's authored
    # size, 2.0 is double. Applied to all three axes, so cows keep their
    # proportions and only get bigger or smaller.
    @editable
    EnemyScale : float = 2.0

    # Damage dealt to EVERY living enemy per DamageButton press. With the
    # health_component default of 100 max health, 34.0 means three presses kill.
    @editable
    DamagePerHit : float = 34.0

    # The crop's health at the start of a run. What the player is defending.
    @editable
    CropMaxHealth : float = 100.0

    # How much crop health one cow destroys by reaching the pasture. At the
    # defaults, five arrivals wipe the crop out.
    @editable
    CropDamagePerCow : float = 20.0

    # Crop health right now. Starts at 0.0 only because a field needs SOME
    # default; the real value is assigned in OnStartPressed - see there for why
    # that spot and not StartWave.
    #
    # Nothing reads it before then: it takes a wave to produce a cow, and a wave
    # only exists after Start.
    var CropHealth : float = 0.0

    # One-shot latch: true once the run has finished, by EITHER ending.
    #
    # It covers victory as well as defeat on purpose. Without that, the last
    # enemy of the final wave dying at the same moment another cow reaches the
    # crop would print "you win" AND "game over" - you would win and lose at
    # once. Whichever ending fires first now closes the door on the other.
    #
    # It is also what makes each ending fire only ONCE: several cows can arrive
    # in the same instant, and without a latch each of them would see a crop
    # already at 0 and announce the defeat again. Same idea as the
    # `CurrentHealth > 0.0` guard in health_component, one level up.
    #
    # Distinct from WaveGeneration by design: the generation answers "which wave
    # do you belong to", which cannot express "the run is over" - a fresh
    # generation is exactly what a new wave looks like.
    var RunHasEnded : logic = false

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

        # Reset the crop HERE and not in StartWave, because this is the only
        # entry point that begins a RUN. StartWave is shared: the button calls
        # it for wave 1, but ChainNextWave also calls it for every wave after -
        # so resetting there would heal the crop back to full at the start of
        # each wave and the damage would never accumulate across the run.
        #
        # The crop is run-scoped state. Enemies and their counters are
        # wave-scoped. Those two lifetimes reset in two different places.
        set CropHealth = CropMaxHealth
        Print("Crop restored to {CropHealth} health")

        # Unlatch, so a run that ended in victory or defeat can be played again.
        # StartWave deliberately has no precondition, so it does not matter how
        # the previous run finished - and the generation bump inside it
        # invalidates anything still in flight from it.
        set RunHasEnded = false

        StartWave(1)

    # Builds a spawn_zone from two props placed at opposite corners.
    #
    # Min/Max per axis means the caller can assign the corners in either order:
    # any diagonal pair describes the same rectangle.
    #
    # Both positions come from GetGlobalTransform() (NOT GetTransform()), so
    # they are already /Verse.org/SpatialMath LUF centimeters. Nothing is
    # converted anywhere in this function - that is the reason two corners beat
    # one prop plus a Scale multiplier.
    #
    # `Up` is taken from corner A alone. If the two props sit at different
    # heights, B's height is simply ignored and the area stays flat.
    MakeZoneFromCorners(CornerA : creative_prop, CornerB : creative_prop) : spawn_zone =
        A : vector3 = CornerA.GetGlobalTransform().Translation
        B : vector3 = CornerB.GetGlobalTransform().Translation

        spawn_zone:
            MinLeft := Min(A.Left, B.Left)
            MaxLeft := Max(A.Left, B.Left)
            MinForward := Min(A.Forward, B.Forward)
            MaxForward := Max(A.Forward, B.Forward)
            Up := A.Up

    # Returns a random point inside `Zone`, trying to stay
    # MinDistanceBetweenEnemies away from everything in `PlacedPositions`.
    #
    # Method: sample a random point, measure it against the ones already placed,
    # and resample if it is too close - up to MaxPlacementAttempts times. This
    # is a best effort, NOT a guarantee.
    #
    # When the attempts run out we return the last candidate anyway rather than
    # looping forever or refusing to place. Two enemies slightly too close is a
    # cosmetic problem; a wave that spawns fewer enemies than asked, or a
    # function that never returns, is not.
    #
    # Effects: reads editable fields and calls GetRandomFloat, which is
    # <transacts>. Nothing here suspends, so StartWave stays atomic.
    PickSpawnPosition(Zone : spawn_zone, PlacedPositions : []vector3) : vector3 =
        # Seeded with a corner of the zone purely so the variable has a value;
        # the loop below always overwrites it on its first pass.
        var ChosenPosition : vector3 = vector3{ Left := Zone.MinLeft, Up := Zone.Up, Forward := Zone.MinForward }
        var Accepted : logic = false

        for (Attempt := 0..MaxPlacementAttempts - 1):
            if (not Accepted?):
                # The zone's min/max feed GetRandomFloat directly - no centre
                # and no half-extents needed. Up is the zone's single height,
                # never randomised, so the whole wave stays on one ground plane.
                Candidate : vector3 = vector3:
                    Left := GetRandomFloat(Zone.MinLeft, Zone.MaxLeft)
                    Up := Zone.Up
                    Forward := GetRandomFloat(Zone.MinForward, Zone.MaxForward)

                # Count how many already-placed enemies this candidate crowds.
                # DistanceForwardLeft is the 2-D distance, ignoring Up - the
                # right measure for spacing things out on the ground.
                var TooCloseCount : int = 0
                for (Placed : PlacedPositions):
                    if (DistanceForwardLeft(Candidate, Placed) < MinDistanceBetweenEnemies):
                        set TooCloseCount += 1

                # Keep the newest candidate regardless, so that if every attempt
                # fails we still hand back a real point inside the area.
                set ChosenPosition = Candidate

                if (TooCloseCount = 0):
                    set Accepted = true

        ChosenPosition

    # Returns the rotation that turns an enemy at `From` to face `To`.
    #
    # There is no look-at helper in the SDK - no LookAt, no RotationFromTo, no
    # direction-to-rotation function anywhere in the digest - so the angle is
    # computed by hand.
    MakeFacingRotation(From : vector3, To : vector3) : rotation =
        Direction : vector3 = To - From

        # ArcTan(Y, X) is atan2: the angle from the +X axis round to the ray
        # (X, Y). Mapping that onto LUF, Forward plays X (the reference axis a
        # zero angle points down) and Left plays Y (the axis a positive angle
        # turns towards). Sanity check: a pure +Forward direction gives
        # ArcTan(0, positive) = 0, i.e. no rotation, which is exactly right.
        #
        # The digest guarantees it returns 0.0 when both arguments are 0, so an
        # enemy that somehow spawns on top of its destination is safe.
        Yaw : float = ArcTan(Direction.Left, Direction.Forward)

        OffsetRadians : float = EnemyFacingOffsetDegrees * PiFloat / 180.0

        # Euler over LUF, turning ONLY the Up axis: enemies swivel on the spot
        # and stay upright. MakeRotationFromEulerRadians is used rather than the
        # YawPitchRoll variant because the latter documents its yaw as a rotation
        # about the DOWN axis - an inverted sign waiting to happen.
        MakeRotationFromEulerRadians(0.0, Yaw + OffsetRadians, 0.0)

    # Starts one enemy walking from `CurrentPosition` to `Target`.
    #
    # Uses keyframed movement, following the pattern proven in
    # FindOverlapHitsExampleComponent.verse:105-117. SetKeyframes rebases the
    # path on the entity's CURRENT transform, which is why callers must place
    # the enemy with SetGlobalTransform BEFORE calling this.
    #
    # The movement itself is synchronous: SetKeyframes and Play both return void
    # and neither suspends, so the engine does the animating. The one task this
    # starts (WatchEnemyArrival) is launched with `spawn`, which also does not
    # suspend, so StartWave stays atomic either way.
    #
    # `Generation` is only carried through to stamp that arrival task.
    MoveEnemyToPasture(Enemy : entity, CurrentPosition : vector3, Target : vector3, Generation : int) : void =
        # Speed guards the division below. Zero or negative means "stay put",
        # which is a legitimate setting, so we skip rather than substitute some
        # made-up duration the designer never asked for.
        if (EnemySpeed > 0.0):
            # Make sure the entity has a movement component, whether or not the
            # prefab shipped with one. Both branches log, so the first run tells
            # us which case P_Cow actually is.
            if:
                ExistingMovementComp := Enemy.GetComponent[keyframed_movement_component]
            then:
                Print("Enemy already had a keyframed_movement_component")
            else:
                Print("Enemy had no keyframed_movement_component - adding one")
                Enemy.AddComponents(array{ keyframed_movement_component{ Entity := Enemy } })

            # Fetch it again: present now by either route, so the driving code
            # below exists once instead of being duplicated in both branches.
            if:
                MovementComp := Enemy.GetComponent[keyframed_movement_component]
            then:
                TravelDistance : float = Distance(CurrentPosition, Target)
                TravelDuration : float = TravelDistance / EnemySpeed

                # Keyframes are RELATIVE, so the translation is the difference
                # between here and there.
                #
                # Scale MUST be all zeros. The digest states translation and
                # scale are applied ADDITIVELY, so leaving Scale at its default
                # would add to the enemy's size every step of the journey and
                # the cow would swell as it walked.
                DeltaTransform : transform = transform:
                    Translation := Target - CurrentPosition
                    Scale := vector3{ Left := 0.0, Up := 0.0, Forward := 0.0 }

                # Linear easing, not the ease-in the abduction sample uses: a
                # walking animal should hold a constant speed, not accelerate.
                Keyframe : keyframed_movement_delta = keyframed_movement_delta:
                    Transform := DeltaTransform
                    Duration := TravelDuration
                    Easing := linear_easing_function{}

                MovementComp.SetKeyframes(array{ Keyframe }, oneshot_keyframed_movement_playback_mode{})
                MovementComp.Play()

                # Start listening for the end of THIS journey. Launched from
                # here, rather than from the spawn loop, because this is where
                # the movement component is already in hand and where we know
                # the animation actually started.
                spawn { WatchEnemyArrival(Enemy, MovementComp, Generation) }

                Print("Enemy walking to pasture - {TravelDistance} cm over {TravelDuration} s")
            else:
                Print("WARNING: could not get a keyframed_movement_component - enemy will not move")
        else:
            Print("WARNING: EnemySpeed must be greater than 0 - enemy will not move")

    # Spawns wave `WaveNumber`. THE single spawn path: both the button and the
    # automatic chaining go through here, so the spawn logic exists once.
    #
    # ATOMICITY - this is load-bearing. This function contains no suspension
    # point (no Await, no Sleep), and Verse is cooperatively scheduled on a
    # single thread. So it runs start to finish without any watcher, damage
    # press or chain task interleaving. That is what makes the sequence
    # clear -> restamp -> spawn -> set count safe without any locking.
    # GetRandomFloat is <transacts>, not <suspends>, so the random placement
    # does not break this.
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

        # Resolve the pasture area and work out where enemies walk to.
        #
        # Deliberately OUTSIDE the spawn guards below and with its own
        # independent check: a missing pasture must never stop enemies from
        # spawning. It is a warning, not a blocker - without it they simply
        # stand still.
        #
        # These two are `var`s declared out here rather than bindings inside the
        # `if` below, because a binding is only visible within its own block and
        # the spawn loop sits several levels deeper. The dummy zone is never read
        # unless HasPasture is true.
        var PastureZone : spawn_zone = spawn_zone{ MinLeft := 0.0, MaxLeft := 0.0, MinForward := 0.0, MaxForward := 0.0, Up := 0.0 }
        var HasPasture : logic = false

        if:
            PastureCornerA.IsValid[]
            PastureCornerB.IsValid[]
        then:
            set PastureZone = MakeZoneFromCorners(PastureCornerA, PastureCornerB)
            Print("Pasture zone - Left {PastureZone.MinLeft} to {PastureZone.MaxLeft}, Forward {PastureZone.MinForward} to {PastureZone.MaxForward}, Up {PastureZone.Up}")
            set HasPasture = true
        else:
            Print("WARNING: pasture area not defined - assign BOTH PastureCornerA and PastureCornerB in the wave_manager Details panel")

        # GetSimulationEntity[] returns the ROOT of the Scene Graph world.
        # It is failable (note the [] brackets), so we guard it with `if`.
        # We add spawned entities as children of this root.
        if:
            SimulationEntity := GetSimulationEntity[]
        then:
            # IsValid[] is failable. It fails when a corner is still the default
            # `creative_prop{}` placeholder, i.e. nothing was assigned in the
            # Details panel. BOTH corners are required - one alone cannot
            # describe a rectangle. Listing the two tests in the same `if` block
            # means the guard only passes when both succeed.
            if:
                SpawnAreaCornerA.IsValid[]
                SpawnAreaCornerB.IsValid[]
            then:
                # Build the zone ONCE, outside the loop: the corners do not move
                # while a wave is spawning.
                Zone : spawn_zone = MakeZoneFromCorners(SpawnAreaCornerA, SpawnAreaCornerB)

                # Positions chosen so far THIS wave, used to keep enemies apart.
                # Local, so it resets with every wave and adds no class state.
                var PlacedPositions : []vector3 = array{}

                # The same idea for the other end of the journey: pasture
                # destinations handed out so far, so PickSpawnPosition spreads
                # arrivals out instead of stacking the whole herd on one spot.
                # Separate list because it lives in a different area entirely.
                var PastureTargets : []vector3 = array{}

                # Counts enemies that are actually WATCHABLE (component attached
                # and readable back). LiveEnemyCount is seeded from this, not
                # from EnemiesPerWave: an enemy nobody is watching can never
                # report its death, so counting it would leave the wave stuck
                # at "not cleared" forever.
                var WatchedCount : int = 0

                for (Index := 0..EnemyCount - 1):
                    # Instantiate a prefab. A prefab is a pre-assembled entity
                    # (mesh + components). `Prefabs.P_Cow{}` is still a
                    # PLACEHOLDER until we build a real enemy prefab, but it
                    # reads as a target far better than the light post did.
                    # Swapping it is a one-identifier change because P_Cow is
                    # declared `class<final>(entity)` exactly like P_LightPost.
                    Enemy : entity = Prefabs.P_Cow{}

                    # AddEntities inserts the new entity into the live world.
                    # Until this call, the prefab exists but is not "in the scene".
                    SimulationEntity.AddEntities(array{ Enemy })

                    # Pick a random spot in the zone, keeping clear of the
                    # enemies already placed this wave.
                    #
                    # We rebuild the transform from scratch around that
                    # translation, so each enemy ignores whatever rotation the
                    # corner props happen to have and stands upright.
                    #
                    # Scale is now set explicitly instead of being left at its
                    # default. transform.Scale is a vector3, so a uniform size
                    # means repeating EnemyScale on all three LUF axes. Rotation
                    # is still left alone.
                    SpawnTranslation : vector3 = PickSpawnPosition(Zone, PlacedPositions)
                    SpawnScale : vector3 = vector3{ Left := EnemyScale, Up := EnemyScale, Forward := EnemyScale }
                    SpawnTransform : transform = transform{ Translation := SpawnTranslation, Scale := SpawnScale }
                    Enemy.SetGlobalTransform(SpawnTransform)

                    # Remember it so the next enemy of this wave avoids it.
                    set PlacedPositions += array{ SpawnTranslation }

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

                    # Send it walking to the pasture, if one is defined.
                    #
                    # The destination is its OWN random point in the pasture,
                    # from the very same PickSpawnPosition used to scatter the
                    # spawn - just pointed at the other zone and fed a different
                    # list of taken spots. Sending everyone to the centre would
                    # make the whole herd converge on one point and interpenetrate
                    # on arrival.
                    #
                    # Placed here, after SetGlobalTransform, because SetKeyframes
                    # rebases the path on the entity's current transform.
                    if (HasPasture?):
                        PastureTarget : vector3 = PickSpawnPosition(PastureZone, PastureTargets)

                        # Turn it to face where it is about to walk.
                        #
                        # This re-writes the transform set a few lines above,
                        # now including the facing. Doing it here rather than
                        # reordering the loop keeps the change confined to this
                        # block, and the no-pasture case above keeps its original
                        # behaviour untouched.
                        #
                        # Because movement is a straight line, the facing worked
                        # out now stays correct for the whole journey - nothing
                        # needs re-orienting in flight, and the keyframe carries
                        # no rotation of its own.
                        #
                        # All three fields are written explicitly so neither the
                        # position nor EnemyScale is lost in this second write.
                        # It must also happen BEFORE MoveEnemyToPasture, since
                        # SetKeyframes rebases its path on the current transform.
                        FacingRotation : rotation = MakeFacingRotation(SpawnTranslation, PastureTarget)
                        FacingTransform : transform = transform:
                            Translation := SpawnTranslation
                            Rotation := FacingRotation
                            Scale := SpawnScale
                        Enemy.SetGlobalTransform(FacingTransform)

                        MoveEnemyToPasture(Enemy, SpawnTranslation, PastureTarget, ThisGeneration)

                        # Remember it so the next enemy aims somewhere else.
                        set PastureTargets += array{ PastureTarget }

                    # Track it so ClearCurrentWave can sweep it later. Note this
                    # keeps growing with dead enemies too - see the field comment.
                    set SpawnedEnemies += array{ Enemy }

                # Seed the live count from the enemies we are actually watching.
                # Assigned once, after the loop: no death can have happened yet,
                # because nothing has damaged anyone.
                set LiveEnemyCount = WatchedCount

                Print("Wave {CurrentWaveNumber} spawned - {LiveEnemyCount} enemies alive")
            else:
                Print("WARNING: spawn area not defined - assign BOTH SpawnAreaCornerA and SpawnAreaCornerB in the wave_manager Details panel")
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

    # One instance of this task runs per walking enemy, parked until that
    # enemy's journey to the pasture ends. Launched by MoveEnemyToPasture.
    #
    # FinishedEvent is a `listenable(tuple())` (Verse.digest.verse:670-671).
    # Being engine-provided it supports both Await and Subscribe; we use Await
    # because the payload is EMPTY, so a Subscribe callback would have no way of
    # telling which enemy arrived. Inside a task, the task itself is the context.
    # The empty payload is simply discarded.
    #
    # Same no-cancellation caveat as WatchEnemyDeath: if the enemy dies before
    # arriving, this task may park forever. Unlike the death watcher, that now
    # happens in NORMAL play rather than only when a wave is abandoned. Accepted
    # for this step; racing the two watchers against each other is the fix and
    # is a separate step.
    WatchEnemyArrival(Enemy : entity, MovementComp : keyframed_movement_component, Generation : int)<suspends> : void =
        MovementComp.FinishedEvent.Await()

        # Guard 1: the wave this enemy belonged to must still be the current one.
        #
        # Guard 2: the enemy must still be in the scene. GetParent[] is failable
        # and the digest says it "fails if there is currently no parent entity" -
        # which is exactly the state RemoveFromParent leaves a dead enemy in. So
        # this is a direct liveness test, with no coordination with the death
        # watcher needed.
        #
        # That second guard matters because it is NOT documented whether the
        # engine fires FinishedEvent when an entity is removed mid-animation. If
        # it does, this check is what stops a corpse from reporting an arrival.
        # Guard 3: the run must still be going. After either ending, arrivals
        # stop counting entirely - no crop damage, not even a log line.
        if:
            Generation = WaveGeneration
            Enemy.GetParent[]
            not RunHasEnded?
        then:
            # The cow eats. Max clamps at 0 so the crop never goes negative.
            #
            # NO DATA RACE, even with several cows landing in the same instant.
            # Verse is cooperatively scheduled on one thread: a task runs from
            # resume to its next suspension point without interruption, and
            # there is no Await or Sleep between reading CropHealth, writing it
            # and logging it. Arrivals are therefore processed one after the
            # other, never interleaved, and no subtraction can be lost.
            set CropHealth = Max(0.0, CropHealth - CropDamagePerCow)

            Print("cow reached the pasture - crop health: {CropHealth} / {CropMaxHealth}")

            # DEFEAT. The `not RunHasEnded?` here is belt and braces: the guard
            # above already established it, and nothing in between suspends. It
            # is kept so this block is correct on its own terms if the code above
            # is ever rearranged.
            if:
                CropHealth <= 0.0
                not RunHasEnded?
            then:
                # Latch FIRST, before anything else can re-enter.
                set RunHasEnded = true
                Print("Game over - the crop was destroyed")

                # Sweep the surviving cows out of the world, so the end of the
                # run is unambiguous on screen and the field is clean for the
                # next Start.
                ClearCurrentWave()

                # Defence in depth: bumping the generation invalidates every
                # stamped thing still in flight in one stroke - death watchers,
                # other arrival watchers, and any ChainNextWave still sleeping -
                # without relying on each of them remembering to check the latch.
                set WaveGeneration += 1

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
        #
        # The second test stops a death from counting once the run is over. It
        # matters most in the reverse of the race below: if the crop falls first,
        # enemies dying immediately afterwards must not go on to declare a wave
        # cleared, or worse, a victory.
        if:
            Generation = WaveGeneration
            not RunHasEnded?
        then:
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
                    # VICTORY. Latch here too, not just on defeat: a cow may be
                    # a fraction of a second from reaching the crop as the final
                    # enemy dies, and without this the arrival would go on to
                    # announce a defeat straight after the win.
                    set RunHasEnded = true
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

        # Re-check AFTER sleeping - this is the one place in the codebase where
        # seconds of real time pass mid-function, so anything may have changed.
        #
        # The stamp catches the player pressing Start during the break, which
        # bumps WaveGeneration; chaining anyway would wipe the wave they just
        # asked for and skip ahead a number. The latch catches the run ending
        # during the break, which is exactly what a cow reaching the crop while
        # the field is empty between waves would do.
        if:
            not RunHasEnded?
            FromGeneration = WaveGeneration
        then:
            StartWave(CurrentWaveNumber + 1)
        else:
            Print("Wave chain cancelled - the run ended, or a new wave was started, during the break")
