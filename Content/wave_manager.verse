# `using` statements import Verse modules (like namespaces).
# Each device/type/function lives in a module, and you must import
# the module before you can reference its names.
using { /Fortnite.com/Devices }                     # button_device, creative_device
using { /Fortnite.com/Characters }                  # fort_character, GetFortCharacter
using { /UnrealEngine.com/ControlInput }            # GetPlayerInput, player_input, input_events
# Imported at the SUBMODULE level, not as /Fortnite.com/Input. That is deliberate:
# this form brings in the module's members (Reload, WeaponPrimary, RangedWeaponMapping
# ...) without bringing in the name `Character`, which would otherwise collide with the
# local `Character` that TryUfoAttack binds for the fort_character.
using { /Fortnite.com/Input/Character }             # Reload
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
using { /Verse.org/Verse }                          # Min, Max, Sin
using { /UnrealEngine.com/Temporary/Diagnostics }   # Print
# The two UI modules, and both are needed: /Fortnite.com/UI has text_block while
# player_ui, GetPlayerUI, player_ui_slot and ui_input_mode all live in the other. The
# Fortnite one `using`s the UnrealEngine one internally, but Verse usings are not
# transitive, so importing it here does not import them here.
#
# NOTE the `Temporary` in the second path. It is the same kind of transitional
# namespace as /UnrealEngine.com/Temporary/SpatialMath, so this API may move.
#
# It does NOT drag classic SpatialMath into this file. The UI module uses classic
# vector2/vector3 internally, but because usings are not transitive the bare `vector3`
# in this file still means the LUF one. That matters here more than usual - mixing the
# two is a trap this project has already hit once.
using { /Fortnite.com/UI }                          # text_block
using { /UnrealEngine.com/Temporary/UI }            # GetPlayerUI, player_ui, player_ui_slot, ui_input_mode

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

# The text Fortnite shows in the interaction prompt while a player is able to
# start the hold on a cow.
#
# WHY <localizes> AND NOT A PLAIN string: `message` is declared
# `class<epic_internal>` (Verse.digest.verse:2096), so `message{}` cannot be
# constructed from our code, and the factory the engine itself uses -
# `MakeMessageInternal` (:2123) - is `epic_internal` too. There is no third door.
# The `<localizes>` specifier IS the route from Verse source to a `message`
# value: it tells the compiler to register this literal for translation and hand
# back a message built through that internal factory.
#
# CONFIDENCE. The specifier is real and legal on a message-typed definition - the
# digests use it themselves, at Fortnite.digest.verse:19 and
# UnrealEngine.digest.verse:1020, both `DefaultText<localizes>...:message`. What
# the digests cannot show is the syntax of a definition we WRITE, because every
# declaration in them is native with an `= external {}` body. So the shape below
# (a data definition whose body is a string literal) is the one genuinely
# unverified line in this sub-step. It is also trivially revertible - see the
# note on ConfigureInteractPrompt.
#
# WHAT THE TEXT HAS TO TEACH. The engine's duration interaction is not a real
# hold: the player presses once, and the bar then fills only while they stay in
# range and do not move - moving or being pushed out of range is what cancels it.
# "Sedate the cow" named the action but taught none of that, leaving the player to
# discover the cancel rule by failing.
#
# "Stay still" rather than "Stay close", even though both are true, because the
# prompt is only ever on screen when the player is ALREADY in range - proximity is
# not the news. Standing still is: it is the condition they are about to break,
# and it implies staying close, so one phrase covers both rules.
#
# NO KEY NAME IN THE TEXT, and no "hold": Fortnite draws the key or the gamepad
# glyph itself next to this label, so a hardcoded "E" would be wrong on a
# controller and duplicated on a keyboard - and "hold" would describe a keypress
# the mechanic does not actually require.
SedateCowPrompt<localizes> : message = "Stay still to sedate"

# The crop readout shown on the HUD.
#
# A `<localizes>` FUNCTION WITH PARAMETERS, not a plain field like the prompt above.
# text_base.SetText takes a `message` and nothing else - there is no string overload -
# so a value that changes has to arrive through a message built at call time, and this
# is the shape that does it.
#
# INTS, NOT FLOATS. Crop health is a float internally, and interpolating one here would
# print "80.000000". The caller rounds before calling, which also sidesteps the question
# of whether a float interpolates into a message at all.
#
# `MaxValue` AND NOT `Max`: this file imports /Verse.org/Verse for Min/Max/Sin, and a
# parameter called Max makes the interpolation below ambiguous between the parameter and
# the standard function. The other single-name functions worth avoiding as parameter
# names here are Min, Abs, Round, Int, Clamp, Floor, Ceil, Sin, Cos, Tan, Sqrt, ToString,
# Concatenate and Err. `Current` is safe - no such identifier exists in any digest.
CropHealthDisplay<localizes>(Current : int, MaxValue : int) : message = "Crop: {Current} / {MaxValue}"

# One instance of this per living enemy. It exists for exactly one reason: to
# answer "which cow was that?" when an interaction succeeds.
#
# THE PROBLEM. interactable_component.SucceededEvent is a `listenable(agent)`,
# so its payload is the PLAYER who interacted, not the cow that was interacted
# with. A single shared handler on wave_manager would therefore receive "player
# X finished an interaction" and have no way to tell which of the five cows in
# the field it belonged to.
#
# THE SOLUTION - one handler OBJECT per cow, holding that cow's own
# health_component as a field. Verse has no closures to capture a variable at
# subscription time, so the captured state is made explicit: this object IS the
# capture. The subscription is per component (each cow has its own interactable,
# each interactable gets its own handler), so when SucceededEvent fires, the
# handler that runs is the one belonging to that cow, and `HealthComp` is
# already the right cow's health. No lookup, no search, no ambiguity.
#
# Why it stores the health_component and not the entity: the handler's only job
# is to damage, and holding the component directly removes a GetComponent[]
# failure case from the hot path. The entity is still reachable as
# HealthComp.Entity if it is ever needed.
#
# WHY Subscribe IS CALLED FROM INSIDE THIS CLASS (the Attach method) rather
# than from wave_manager: passing `OnInteractSucceeded` unqualified inside the
# class body is the same shape already proven to compile in this project -
# `StartButton.InteractedWithEvent.Subscribe(OnStartPressed)` in OnBegin, and
# `InteractableComponent.SucceededEvent.Subscribe(OnInteractFinished)` in
# LanternInteractionComponent.verse:19. wave_manager just builds the handler and
# calls Attach; it never needs to name a method on someone else's instance.
#
# Lifetime: nothing in wave_manager keeps a reference to these handlers. They
# stay alive because the subscription holds the bound callback, which holds this
# object - and the subscription itself is owned by the cow's interactable
# component. Handler and cow therefore die together, which is exactly right.
enemy_interaction_handler := class:

    # The health of the ONE cow this handler speaks for. Set at construction and
    # never reassigned - this is the whole association mechanism.
    HealthComp : health_component

    # The interactable of that same cow, so a completed sedation can switch the
    # prompt off. Held as a field rather than looked up at event time because
    # AttachEnemyInteraction already has it in hand when it builds this handler -
    # it is inside the `if` that found it - so storing it removes a lookup that
    # could fail. The movement component is the odd one out and must stay a lazy
    # lookup, but only because of the spawn-loop ordering; see OnInteractStarted.
    InteractableComp : interactable_component

    # Damage applied on a successful interaction. Large enough to always take the
    # cow to 0 health in one go. Passed in rather than read from wave_manager so
    # this class has no dependency on the device.
    #
    # NOTE ON THE NAME: since 4b this damage SEDATES rather than kills - it is the
    # vehicle that drives health to 0 so the single "no longer a threat" channel
    # fires. The name is kept because the editable feeding it, InteractKillDamage,
    # is assigned in the UEFN Details panel, and renaming an @editable makes the
    # editor lose the designer's value.
    KillDamage : float

    # Index within its wave. Log-only, so the output can be matched up with the
    # spawn lines above it.
    EnemyIndex : int

    # True while THIS handler is the reason its cow is standing still.
    #
    # A one-shot latch, not a toggle: OnInteractStarted raises it only when it
    # genuinely paused a moving cow, and OnInteractCanceled consumes it. That is
    # what makes "resume" impossible to get wrong, because Play() is only ever
    # called to undo a Pause() this handler actually performed.
    #
    # It matters because Play() on a cow that was NOT paused by a hold is a real
    # hazard, not a no-op. A cow that already reached the pasture has a FINISHED
    # animation and is still interactable, and the digest does not specify what
    # Play() does to a finished one-shot - if it replays it, that cow walks the
    # route again and damages the crop a second time. This latch means we never
    # find out.
    #
    # Per COW, not per agent: MaxSimultaneousInteractors is unset (unlimited), so
    # two players can hold the same cow at once. "Is this cow paused because of a
    # hold" is a property of the cow, so one flag per handler is the right
    # granularity. See OnInteractStarted for what the overlap actually does.
    var DidPauseForHold : logic = false

    # Wires this handler to a cow's interactable component.
    #
    # Not <suspends> and not a task: Subscribe registers a callback and returns
    # immediately, so the spawn loop stays atomic. The returned `cancelable` is
    # ignored, the same as every other Subscribe in this project - the
    # subscription is meant to last as long as the component does.
    # All three events of the interaction lifecycle are wired, not just the one
    # that kills: with a hold duration in play, "did the hold start" and "was it
    # canceled" are the two questions the log has to be able to answer. Without
    # them a hold that never begins and a hold that begins and gets interrupted
    # look identical from the outside - nothing happens in both cases.
    #
    # All three carry the same agent payload and the same per-cow association, so
    # they all resolve to THIS handler's cow. See the class comment.
    Attach() : void =
        InteractableComp.StartedEvent.Subscribe(OnInteractStarted)
        InteractableComp.SucceededEvent.Subscribe(OnInteractSucceeded)
        InteractableComp.CanceledEvent.Subscribe(OnInteractCanceled)

    # Runs when a player BEGINS holding the interact key on this cow, and freezes
    # the cow where it stands so it cannot walk out of the player's reach mid-hold.
    #
    # The cow is still not damaged or marked - only stopped. Nothing here is
    # irreversible, which is what lets OnInteractCanceled put it back exactly as
    # it was.
    #
    # WHY THE MOVEMENT COMPONENT IS LOOKED UP HERE AND NOT HELD AS A FIELD: in the
    # spawn loop, AttachEnemyInteraction runs BEFORE MoveEnemyToPasture, so the
    # keyframed_movement_component does not exist yet when this handler is built -
    # there is nothing to store. Reading it off the entity at event time also
    # handles the no-pasture case for free: no pasture means no movement component,
    # the lookup fails, and there is simply nothing to pause. The entity stays the
    # single source of truth for its components, as everywhere else in this file.
    #
    # Pause(), never Stop(): the digest says Stop() "reset[s] transform to the
    # initial state", which would teleport the cow back to its spawn point. Pause()
    # resumes from the exact point it froze at.
    #
    # IsPlaying[] is part of the CONDITION, not an afterthought. Pausing something
    # that is not playing would raise the latch and licence a later Play() on a
    # cow that was standing still for some other reason - a finished route being
    # the dangerous one. See the DidPauseForHold comment.
    #
    # MULTIPLE OVERLAPPING HOLDS: with two players on one cow, the first hold
    # pauses and latches; the second finds IsPlaying[] already false, takes the
    # else branch and changes nothing. The first cancel to arrive resumes the cow
    # while the other player may still be holding - cosmetically imperfect, never
    # incorrect. Capping MaxSimultaneousInteractors at 1 removes the overlap
    # entirely and is on the list for a later sub-step.
    OnInteractStarted(InAgent : agent) : void =
        Print("Interaction started on enemy {EnemyIndex} - hold to complete")

        if:
            MovementComp := HealthComp.Entity.GetComponent[keyframed_movement_component]
            MovementComp.IsPlaying[]
        then:
            MovementComp.Pause()
            set DidPauseForHold = true
            Print("Enemy {EnemyIndex} paused while the hold lasts")
        else:
            Print("Enemy {EnemyIndex} was not moving - nothing to pause")

    # Runs when a hold ends WITHOUT completing: the player released the key,
    # walked out of range, or something else interrupted it.
    #
    # An abandoned hold must leave the cow exactly as it was, so this undoes the
    # one thing OnInteractStarted did - and ONLY if it did it. The latch is the
    # whole test: no latch, no Play(). A cancel with no matching pause (a cow that
    # was already still, a second player's cancel after the first already resumed)
    # therefore does nothing at all.
    #
    # The latch is consumed BEFORE Play() rather than after, and unconditionally -
    # outside the component lookup. Two reasons: a missing movement component must
    # not leave the latch stuck true, and clearing first means that even if Play()
    # somehow re-entered this handler, the latch is already spent.
    #
    # NOTE - the digest warns that the base interactable_component "cannot be
    # canceled" and that CanceledEvent exists for subclasses to fire. That is not
    # a problem here: the subclass we attach is basic_interactable_component, and
    # its InteractableDuration is documented as cancelable while the duration is
    # active. So this only ever fires because the duration exists, which makes it
    # a direct test that the hold is real.
    OnInteractCanceled(InAgent : agent) : void =
        Print("Interaction canceled on enemy {EnemyIndex} - hold not completed")

        if (DidPauseForHold?):
            set DidPauseForHold = false

            if:
                MovementComp := HealthComp.Entity.GetComponent[keyframed_movement_component]
            then:
                MovementComp.Play()
                Print("Enemy {EnemyIndex} resumed walking to the pasture")
            else:
                Print("WARNING: enemy {EnemyIndex} was paused for a hold but has no keyframed_movement_component to resume")
        else:
            Print("Enemy {EnemyIndex} was not paused by a hold - leaving it as it is")

    # Runs when a player completes the hold on THIS cow. The cow falls ASLEEP: it
    # stops where it stands, stops being a threat, and its body stays in the world.
    #
    # InAgent is the interacting player - received because the event sends it,
    # and unused for now: the sedation is not attributed to anyone.
    #
    # The cow is neutralized through the EXISTING elimination channel, not a new
    # one: ApplyDamage -> EliminatedEvent -> WatchEnemyDeath -> OnEnemyDied -> the
    # live counter and the wave/run endings. The only thing that changes anywhere
    # downstream is that WatchEnemyDeath leaves the body standing instead of
    # removing it - see there. The counter, its guards and its atomicity are
    # untouched, which is the whole reason for routing sedation this way: the
    # `if (CurrentHealth > 0.0)` guard in ApplyDamage already makes "this enemy is
    # out" fire exactly once per cow, so the counter cannot be told twice. It also
    # means a sedated cow absorbs nothing from the damage button afterwards - its
    # health is already 0 - with no special case anywhere.
    #
    # THE ORDER OF THESE FIVE STEPS IS LOAD-BEARING. Nothing here suspends, so the
    # whole block is atomic, but each step still has to precede the one after it:
    #
    #   1. IsSedated first. ApplyDamage signals EliminatedEvent, and the digest
    #      does not say whether Signal resumes a waiting task synchronously inside
    #      the same transaction. Setting the flag first is correct under both
    #      readings; setting it after the damage would be a race under one of them.
    #   2. Seal DidPauseForHold before anything can emit a cancel. Step 4 may well
    #      cancel other agents' in-flight holds on this cow, and each cancel calls
    #      OnInteractCanceled - which would Play() the movement and send a sleeping
    #      cow walking to the crop. With the latch already spent, that path is shut.
    #   3. Pause unconditionally, no IsPlaying[] test. "Sedated implies not moving"
    #      is an invariant, not an optimisation: normally step 1 of the hold already
    #      paused it, but with InteractHoldSeconds at 0 the started event may have
    #      had nothing to pause. Pause() on an already-paused animation is a no-op.
    #   4. Disable the interactable so the prompt disappears and the cow cannot be
    #      sedated twice. Belt and braces only - the health guard is what actually
    #      guarantees single neutralization even if a second success got through.
    #   5. ApplyDamage last, once the cow's world state is fully settled, because
    #      this is the step that announces the neutralization to everyone else.
    OnInteractSucceeded(InAgent : agent) : void =
        Print("Interaction completed on enemy {EnemyIndex} - sedating it")

        # 1. Tell the elimination channel this is a sedation, not a kill.
        set HealthComp.IsSedated = true

        # 2. Shut the resume path before step 4 can trigger any cancel.
        set DidPauseForHold = false

        # 3. A sleeping cow does not walk. Pause(), never Stop() - Stop would
        #    teleport the body back to its spawn point.
        if:
            MovementComp := HealthComp.Entity.GetComponent[keyframed_movement_component]
        then:
            MovementComp.Pause()
        else:
            Print("Enemy {EnemyIndex} has no keyframed_movement_component - nothing to stop")

        # 4. No more prompts on this cow. The digest: "Disabled components do not
        #    provide interaction prompts."
        InteractableComp.Disable()

        # 5. Neutralize. Everything downstream is the existing pipeline.
        HealthComp.ApplyDamage(KillDamage)

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

    # Third button: the UFO area attack. Every press eliminates every cow within
    # UfoRadius of the player who pressed it.
    #
    # A button for now, and it will not stay one: a button is a fixed object in the
    # world, so you cannot stand where you want the attack to land AND reach it.
    # That is fine while the area is centred on the player, and it is the reason
    # aiming is a later sub-step rather than part of this one.
    @editable
    UfoButton : button_device = button_device{}

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

    # Damage applied to a single cow when a player completes an interaction with
    # it. Deliberately far above any sane MaxHealth so an interaction is a
    # one-hit kill regardless of how health is tuned later.
    @editable
    InteractKillDamage : float = 100000.0

    # How long a player must HOLD the interact key on a cow to kill it, in
    # seconds. Fed into the interactable's interactable_duration, which is what
    # drives Fortnite's native hold progress bar.
    #
    # 0.0 or less is legal and means "instant", per the digest - it reverts the
    # behaviour to what sub-step 1 shipped. So this dial can turn the hold off
    # without touching code.
    @editable
    InteractHoldSeconds : float = 2.0

    # The crop's health at the start of a run. What the player is defending.
    @editable
    CropMaxHealth : float = 100.0

    # How much crop health ONE cow destroys per damage tick while it stands in the
    # pasture. A cow that arrives keeps eating until it is sedated or killed, so
    # this is a rate, not a one-off cost.
    #
    # This replaces the old CropDamagePerCow, which was deliberately removed
    # rather than reused: its meaning changed from "cost of one arrival" to "cost
    # per second", and its 20.0 would have wiped the crop in five seconds under
    # the new reading. A field whose name no longer matches its meaning is worse
    # than a field that is gone.
    #
    # WHAT MATTERS FOR BALANCE IS THE RATE, CropDamagePerTick / CropDamageInterval.
    # At the 4.0 / 1.0 defaults that is 4 health per second: one cow alone needs
    # 25 s to destroy a 100-health crop, three cows need about 8 s, five need 5 s.
    #
    # This started at 2.0 while the drain loop was being verified, which was
    # deliberately forgiving. 4.0 is the playable value: it lands close to the old
    # one-bite-per-arrival punishment - five arrivals used to zero the crop
    # instantly, and now they take five seconds - so arrivals still hurt but are
    # recoverable if the player sedates fast. Tune from here by feel.
    @editable
    CropDamagePerTick : float = 4.0

    # Seconds between damage ticks from one cow in the pasture.
    #
    # Shorter means a smoother drain, not a harder game - halving this while
    # halving CropDamagePerTick leaves the rate unchanged. Nothing is logged per
    # tick any more, so a shorter interval costs no log noise either.
    #
    # It is also the polling period of the drain loop, so it doubles as the worst
    # case delay before a stopped cow's loop notices and exits. That delay costs
    # task lifetime only, never crop health: the guards are re-checked before
    # every subtraction. See DrainCropWhileAtPasture.
    @editable
    CropDamageInterval : float = 1.0

    # Radius of the UFO attack, in centimeters, measured from the pressing player.
    #
    # 800 cm is 8 metres, which is a couple of cow-lengths in each direction - big
    # enough to be worth using, small enough that it does not clear the field. This
    # is the one number worth tuning by eye first.
    #
    # It means centimeters unconditionally: OnUfoPressed forces the query
    # transform's scale to 1 rather than inheriting the player's, so this radius is
    # never silently multiplied by something else.
    @editable
    UfoRadius : float = 800.0

    # Damage dealt to each cow caught in the attack. A code constant, not a dial,
    # and deliberately NOT a reuse of InteractKillDamage: that one is named for the
    # sedation interaction, and two abilities sharing one number is how a later
    # "make the UFO do partial damage" change accidentally reballances sedation.
    #
    # Same reasoning as InteractKillDamage for the size, though: far above any sane
    # MaxHealth, so the attack is lethal however health gets tuned later.
    UfoKillDamage : float = 100000.0

    # Seconds between UFO attacks. The cost of the ability: without it the button
    # can be spammed and the whole field clears for free.
    #
    # 8 s is a starting guess, not a tuned value - it wants to be long enough that
    # sedating by hand stays the bread and butter and the UFO is the answer to a
    # cluster you cannot reach in time. Tune against how fast a wave arrives.
    @editable
    UfoCooldownSeconds : float = 8.0

    # How high above the target the UFO hovers, in centimeters.
    #
    # 600 cm is roughly two storeys - high enough to read as "a ship above you"
    # rather than a prop in your face, low enough to stay on screen while you are
    # looking at the ground. Tune with the camera, not with a ruler.
    @editable
    UfoHoverHeightCm : float = 600.0

    # Uniform size multiplier for the spawned UFO: 1.0 is the prefab's authored size,
    # 2.0 is double. Same meaning and same shape as EnemyScale, so the two read the
    # same way in the Details panel.
    #
    # Applied to all three axes, so the ship only gets bigger or smaller and never
    # deforms.
    #
    # It replaces the prefab's authored scale rather than multiplying it, because
    # SetGlobalTransform writes an absolute transform - exactly as EnemyScale does for
    # cows. That is only "the authored size" at 1.0 if the prefab was authored at
    # scale 1, which is the same assumption the cow path already makes.
    @editable
    UfoScale : float = 2.0

    # How long the cows take to rise into the ship, in seconds.
    #
    # Unused in this sub-step - nothing rises yet - and defined now because it is
    # half of how long the UFO stays on screen, and because the rise animation and
    # the wait for it have to be derived from ONE number or the ship will leave
    # before the cows arrive.
    @editable
    UfoRiseSeconds : float = 2.0

    # Extra seconds the UFO stays after the rise finishes, so the beam does not cut
    # out on the same frame the last cow disappears. Purely for feel.
    @editable
    UfoBeamLingerSeconds : float = 0.5

    # How far a grazing cow swells and shrinks, as a fraction of its own size.
    # 0.2 means it breathes between 120% and 80% of its spawn scale.
    #
    # RELATIVE, NOT ABSOLUTE. It multiplies the scale THAT cow was spawned at, so a
    # big cow pulses by a big amount and a small one by a small amount, and both
    # read as the same gesture. 0.0 disables the pulse without removing the code.
    @editable
    EatPulseAmount : float = 0.2

    # Seconds for one full swell-and-shrink of a grazing cow. LOWER IS FASTER.
    #
    # FULLY INDEPENDENT OF CropDamageInterval. The pulse runs in its own task with
    # its own Sleep, so the cow can breathe several times per damage tick, and
    # retuning either rhythm leaves the other alone. Naming follows
    # CropDamageInterval's convention - seconds, not a speed multiplier - so the two
    # rhythms are directly comparable when reading the Details panel.
    @editable
    EatPulseCycleSeconds : float = 0.5

    # How many scale writes make up one cycle. A code constant, not a dial: it
    # controls smoothness, not rhythm, and 8 samples of a sine already look smooth.
    #
    # It also sets the wake-up rate, at EatPulseCycleSeconds / this seconds apart.
    # Raising it costs task wake-ups per eating cow for no visible gain.
    EatPulseSamplesPerCycle : float = 8.0

    # Floor for EatPulseCycleSeconds, which is also what bounds the wake-up rate:
    # at 0.2 s per cycle over 8 samples the pulse task wakes 40 times a second per
    # eating cow, and that is as fast as this is allowed to get. It also keeps the
    # divisions below away from zero.
    MinEatPulseCycleSeconds : float = 0.2

    # One full turn in radians. Verse has Sin and Cos but ships no Pi constant, so
    # the period of the wave has to be written out here.
    TwoPiRadians : float = 6.283185307179586

    # How much of its height a sedated cow keeps. 1.0 is no change; 0.4 leaves it
    # at 40% of its standing height, which reads as deflated onto the ground.
    #
    # A MULTIPLIER, NOT A HEIGHT. It is applied to the scale the cow was SPAWNED
    # at, so it composes with EnemyScale rather than replacing it - see
    # ApplySleepFlatten. Only the vertical axis is touched, so the cow keeps its
    # footprint and its length and stays recognisable as a cow.
    @editable
    SleepFlattenFactor : float = 0.4

    # Floor for SleepFlattenFactor. A vertical scale of zero or less does not
    # flatten a mesh, it collapses or mirrors it, so the editable is clamped
    # rather than trusted.
    MinSleepFlattenFactor : float = 0.05

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

    # Simulation time at which the UFO attack becomes usable again. THE WHOLE
    # COOLDOWN, in one number.
    #
    # A DEADLINE, NOT A COUNTDOWN, and that distinction is what removes a whole class
    # of bug rather than guarding against it. Nothing has to tick it down and nothing
    # has to be woken up to clear it: "is the UFO ready" is answered by comparing the
    # clock against this, so the answer is always computed from scratch and can never
    # be stale. Simulation time only ever increases, so a value in the past means
    # ready, forever, with no maintenance.
    #
    # It replaces a latch plus a start-stamp plus a spawned task that slept and
    # lowered the latch. That version worked but had a real hole: a task from a
    # previous run could wake mid-way through a NEW cooldown and clear it early,
    # which needed a re-check to patch. There is no task here to wake late, so the
    # hole does not exist to be patched.
    #
    # ONLY TWO WRITERS, both synchronous: TryUfoAttack sets it forward when an attack
    # actually happens, and OnStartPressed sets it to 0.0 to hand the ability back at
    # the start of a run. Nothing writes it from a suspended context.
    #
    # GLOBAL, NOT PER PLAYER - a prototype decision rather than a design one. This is
    # single-player for now, so a map keyed by player would be state to maintain for a
    # case that cannot arise yet. It is the one thing here that multiplayer changes.
    var UfoReadyAt : float = 0.0

    # The HUD text showing the crop's health, kept so it can be re-written later.
    #
    # A widget has no "find me again" lookup, so the only way to call SetText after
    # AddWidget is to have held on to the instance. Optional because there is nothing to
    # hold until a player exists and WireCropHudForPlayers runs.
    #
    # ONE FIELD, NOT ONE PER PLAYER, which is the accepted limit of this step. With two
    # players both would get a widget but only the last one created would ever update.
    # Multiplayer wants a map keyed by player, the same shape the input wiring will need
    # when PlayerAddedEvent arrives.
    var CropHealthText : ?text_block = false

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
        UfoButton.InteractedWithEvent.Subscribe(OnUfoPressed)

        # Second trigger for the same attack: a key. The button above stays wired on
        # purpose - see WireUfoKeyForPlayers.
        WireUfoKeyForPlayers()

        # Put the crop readout on screen. After the key wiring, so if the UI ever
        # interfered with input the log order would make that obvious.
        WireCropHudForPlayers()

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

        # HUD change 1 of 2. Cosmetic and additive - see UpdateCropHealthHud.
        UpdateCropHealthHud()

        # Unlatch, so a run that ended in victory or defeat can be played again.
        # StartWave deliberately has no precondition, so it does not matter how
        # the previous run finished - and the generation bump inside it
        # invalidates anything still in flight from it.
        set RunHasEnded = false

        # Hand the UFO back, so a cooldown left over from the previous run does not
        # eat into the new one. Run-scoped, like the crop above and for the same
        # reason: "pressing Start always begins a clean run" is a promise this file
        # makes elsewhere, and an ability the player cannot use for the first few
        # seconds would quietly break it.
        #
        # 0.0 rather than "now" because simulation time only grows: a deadline in the
        # past means ready and stays meaning ready. And unlike the latch-plus-task
        # version this replaced, there is nothing in flight that could undo it.
        set UfoReadyAt = 0.0

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

    # Makes one enemy killable by hand: gives it an interactable component and
    # points a handler at its health.
    #
    # Same three-step shape as the movement wiring in MoveEnemyToPasture - check
    # whether the prefab already brought one, create it if not, then read it back
    # off the entity - so the driving code below exists once instead of being
    # duplicated in both branches. Both branches log, so the first run tells us
    # which case P_Cow actually is.
    #
    # The CHECK is for the base `interactable_component` while the thing ADDED is
    # a `basic_interactable_component`. That asymmetry is intentional:
    # SucceededEvent is declared on the base, so any interactable variant a
    # prefab might ship (offer_interactable_component, an item pickup, ...) is
    # good enough to subscribe to and must not be duplicated. basic_ is simply
    # the plain subclass to add when there is nothing there - it is the one with
    # the composable feature set (cooldowns, duration, success limits) that later
    # sub-steps will need.
    #
    # The interaction is a HOLD, not a key press: InteractableDuration carries an
    # interactable_duration whose InteractDuration is InteractHoldSeconds, which
    # is what makes Fortnite draw its native progress bar and lets the hold be
    # canceled midway. See ConfigureHoldDuration for why the value is also
    # re-applied after construction.
    #
    # Nothing here suspends, so StartWave stays atomic.
    AttachEnemyInteraction(Enemy : entity, EnemyHealthComp : health_component, Index : int) : void =
        if:
            ExistingInteractable := Enemy.GetComponent[interactable_component]
        then:
            Print("Enemy {Index} already had an interactable_component")
        else:
            Print("Enemy {Index} had no interactable_component - adding a basic_interactable_component")

            # `?interactable_duration` is an OPTION field, so the value has to be
            # wrapped: `option{ ... }` is the constructor (same form as
            # FindSweepHitsExampleComponent.verse:62), and a bare `false` would be
            # the empty option. Assigning the interactable_duration directly would
            # be a type error - Verse does not auto-wrap into an option.
            #
            # interactable_duration is `class<concrete>`, so `interactable_duration{}`
            # alone would be legal too; we override InteractDuration in the
            # archetype and leave MaxSimultaneousInteractors at its default
            # (unlimited), which is right while only one player is testing.
            HoldDuration : interactable_duration = interactable_duration:
                InteractDuration := InteractHoldSeconds

            NewInteractable : basic_interactable_component = basic_interactable_component:
                Entity := Enemy
                InteractableDuration := option{ HoldDuration }

            Enemy.AddComponents(array{ NewInteractable })

        # Make sure the hold duration is actually in effect, whichever branch ran.
        ConfigureHoldDuration(Enemy, Index)

        # Cosmetic only, and safe to delete on its own - see the function.
        ConfigureInteractPrompt(Enemy, Index)

        # Fetch it again: present now by either route.
        if:
            Interactable := Enemy.GetComponent[interactable_component]
        then:
            # Build this cow's own handler and hand it the cow's own health. See
            # the enemy_interaction_handler comment for why the association has
            # to be an object rather than a shared callback.
            Handler : enemy_interaction_handler = enemy_interaction_handler:
                HealthComp := EnemyHealthComp
                InteractableComp := Interactable
                KillDamage := InteractKillDamage
                EnemyIndex := Index

            Handler.Attach()

            Print("Enemy {Index} is now interactable - one interaction deals {InteractKillDamage} damage")
        else:
            Print("WARNING: enemy {Index} has no interactable_component after AddComponents - it cannot be killed by hand")

    # Forces this cow's hold length to InteractHoldSeconds and reports what it
    # found. Called for every enemy, right after the attach step.
    #
    # WHY THIS EXISTS AT ALL, given the archetype above already sets the duration:
    #
    #   1. `InteractableDuration` is NOT a `var` in the digest, so it can only
    #      ever be assigned at construction. When the prefab brings its own
    #      interactable, we never construct it - so the archetype above cannot
    #      reach it and the editable value would silently do nothing on that path.
    #      The inner `InteractDuration` IS a var, so going one level deeper is the
    #      only way in. (Same trick as LanternInteractionComponent.verse:23,
    #      writing a var field through a reference we did not build.)
    #
    #   2. It turns the setting into something the log can PROVE. The archetype
    #      only records what we asked for; this reads the value back off the live
    #      component, so a wrong or missing duration shows up on the first run
    #      instead of being debugged through the progress bar.
    #
    # The lookup is for basic_interactable_component specifically, not the base
    # interactable_component, because InteractableDuration is declared on the
    # subclass. A prefab shipping some other interactable variant therefore lands
    # in the else branch and keeps whatever timing it was authored with.
    ConfigureHoldDuration(Enemy : entity, Index : int) : void =
        if:
            BasicInteractable := Enemy.GetComponent[basic_interactable_component]
            # `?` unwraps the option, and FAILS when it is empty - so this line is
            # both the unwrap and the "does it have a duration at all" test.
            HoldDuration := BasicInteractable.InteractableDuration?
        then:
            set HoldDuration.InteractDuration = InteractHoldSeconds
            Print("Enemy {Index} hold duration is {HoldDuration.InteractDuration} s")
        else:
            Print("Enemy {Index} has no interactable_duration - its interaction will be immediate")

    # Replaces the engine's generic interaction prompt with our own text.
    #
    # PURELY COSMETIC, AND DELIBERATELY ISOLATED. Nothing else in the file depends
    # on this running, and the interaction works identically without it - it just
    # shows the default prompt. If `SedateCowPrompt` turns out not to compile, the
    # whole feature reverts by deleting three things and nothing else moves:
    # this function, its one call in AttachEnemyInteraction, and the
    # SedateCowPrompt definition at the top of the file.
    #
    # CanInteractMessage is a `var` in the digest, unlike InteractableDuration, so
    # it can be written after construction - which is why this needs no change to
    # the archetype and works on the prefab-already-had-one path too. It is also
    # `@editable`, so a designer could set it in the Details panel on a
    # hand-placed interactable; runtime-added components like ours have no panel,
    # hence doing it in code.
    #
    # It is gated `@available {MinUploadedAtFNVersion := 4020}`. The digests here
    # are generated from Fortnite Release-41.30, comfortably past that, so the
    # member exists - but this is the second thing to suspect if the build
    # complains, after the <localizes> syntax itself.
    #
    # Only the CAN-interact message is set. The digest also exposes
    # CannotInteractMessage, shown when CanInteract fails; we never fail
    # CanInteract, so it would be dead text.
    ConfigureInteractPrompt(Enemy : entity, Index : int) : void =
        if:
            BasicInteractable := Enemy.GetComponent[basic_interactable_component]
        then:
            set BasicInteractable.CanInteractMessage = SedateCowPrompt

            # Read it BACK and Localize it for the log, rather than logging the
            # literal we just wrote. Localize (Verse.digest.verse:2099) is the
            # public message -> string direction and is the only way to see a
            # message's content from code, so this proves two things at once: the
            # assignment landed on the live component, and the message resolves to
            # the text we expect instead of an empty or missing translation.
            Print("Enemy {Index} interact prompt set to: {Localize(BasicInteractable.CanInteractMessage)}")
        else:
            Print("Enemy {Index} has no basic_interactable_component - keeping the engine's default prompt")

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

                    # Cache the size this cow was spawned at, so that if it is
                    # ever sedated the sleep visual can flatten it relative to
                    # this instead of guessing.
                    #
                    # Attached HERE because this is where SpawnScale exists, and
                    # after AddEntities because a component is added to an entity
                    # that is already in the scene. The facing rewrite further
                    # down re-sends the very same SpawnScale, so this stays the
                    # truth whether or not a pasture is defined.
                    #
                    # Purely cosmetic bookkeeping: nothing in the wave, counter,
                    # damage or movement logic reads this component.
                    NewSleepVisualComp : sleep_visual_component = sleep_visual_component:
                        Entity := Enemy
                        StandingScale := SpawnScale

                    Enemy.AddComponents(array{ NewSleepVisualComp })

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

                        # Make it killable by hand. Wired INSIDE this block, not
                        # after it, for two reasons: AttachedHealthComp is the
                        # health the handler must damage and it only exists here,
                        # and an enemy with no health component could not die
                        # anyway - giving it an interaction that visibly does
                        # nothing would be worse than having no prompt at all.
                        # That case already logs its own warning below.
                        AttachEnemyInteraction(Enemy, AttachedHealthComp, Index)
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

    # The UFO area attack: eliminates every cow within UfoRadius of the pressing
    # player, at most once every UfoCooldownSeconds. No aiming and no visuals yet.
    #
    # IT ADDS NO DEATH PATH OF ITS OWN. It ends with the same ApplyDamage every other
    # damage source uses, so EliminatedEvent, WatchEnemyDeath, RemoveFromParent, the
    # live counter and the wave/victory decisions all handle these cows without
    # knowing the UFO exists. Nothing here is coordinated with any of them.
    #
    # THE AREA QUERY IS THE EXAMPLE'S, almost verbatim: the shape of
    # FindOverlapHitsExampleComponent.PerformOverlapCheck, with the example's
    # collision_capsule swapped for a collision_sphere. The capsule was dimensioned
    # for a narrow beam hanging under the ship; an area attack wants a ball.
    #
    # WHY THE SIMULATION ENTITY IS THE QUERY CONTEXT: the digest says of this
    # overload that the entity "defines the context (scene) for the query but does
    # not otherwise take part in the sweep" - it is a handle to the scene, not a
    # participant, and the area is defined entirely by the transform and the volume.
    # The simulation entity is the one scene handle a creative_device has, and it is
    # the same one StartWave already uses.
    #
    # LIKE THE DAMAGE BUTTON, THIS IS NOT GATED BY RunHasEnded. Pressing it after a
    # run ends is harmless - every cow is already gone, so the query finds nothing -
    # but it still logs, and it inherits that known limitation rather than fixing it
    # here.
    #
    # THE COOLDOWN IS A GATE IN FRONT OF THE ATTACK, not a change to it. The refusal
    # branch is new; everything under `TryUfoAttack` is the previous version of this
    # handler, extracted whole so that adding the gate needed no re-indentation of
    # working code and no second level of nesting in one function.
    # Puts the crop readout on screen for every player already in the game.
    #
    # SAME SHAPE AS WireUfoKeyForPlayers, because the UI has the same constraint the
    # input does: GetPlayerUI takes a player, so there is nothing to add until players
    # exist. Kept as a separate function and a separate loop rather than folded into the
    # input one - they cost nothing apart and it means a failure in one cannot take the
    # other down with it.
    #
    # Players who join later get nothing. That is the same gap the input wiring has and
    # the same fix (PlayerAddedEvent), deferred for the same reason: single-player.
    #
    # NO CANVAS. AddWidget's one-argument form places the widget with a default slot
    # configuration, which is enough to prove the pipeline works. Putting it in a corner
    # needs a canvas and MakeCanvasSlot, and that is a separate step.
    WireCropHudForPlayers() : void =
        var AddedCount : int = 0

        for (CurrentPlayer : GetPlayspace().GetPlayers()):
            if:
                # Failable per the digest - "fails if there is no player_ui associated
                # with Player" - so a player without one is skipped rather than taking
                # the loop down.
                PlayerUI := GetPlayerUI[CurrentPlayer]
            then:
                NewCropText : text_block = text_block{}

                # THE SLOT IS THE WHOLE REASON THIS IS NOT THE ONE-ARGUMENT AddWidget.
                #
                # ui_input_mode has two values, None and All, and All means the widget
                # "consumes all inputs". A HUD readout that swallowed input would kill
                # the Reload key wired a few lines below this - the R press would never
                # reach the UFO. The digest does not state what the default is, so it is
                # passed EXPLICITLY rather than assumed.
                #
                # ZOrder is left at its default: with one widget there is nothing to
                # order it against.
                HudSlot : player_ui_slot = player_ui_slot:
                    InputMode := ui_input_mode.None

                PlayerUI.AddWidget(NewCropText, HudSlot)

                set CropHealthText = option{ NewCropText }
                set AddedCount += 1
            else:
                # NOT SILENT, for the same reason the input wiring is not: "the HUD
                # never appeared" is a horrible thing to debug from an empty log.
                Print("WARNING: could not get player UI for a player - they will not see the crop readout")

        # The starting value, written now rather than through DefaultText on the widget.
        # DefaultText is documented as "used only during initialization and not modified
        # by SetText", so having one code path that always writes the text - this one -
        # avoids two places that can disagree about what the HUD says.
        UpdateCropHealthHud()

        Print("Crop HUD added for {AddedCount} player(s)")

    # Re-writes the crop readout from whatever CropHealth currently is.
    #
    # THE ONLY PLACE THAT TOUCHES THE HUD TEXT, called from the two - and only two -
    # places in this file where CropHealth changes: the reset in OnStartPressed and the
    # subtraction in DrainCropWhileAtPasture. No polling loop, no tick: the value cannot
    # change without one of those running.
    #
    # Everything failable is gathered here so the two call sites stay single lines.
    # Round is <decides> - it can fail on a value that is not finite - and the widget
    # reference is an optional that is empty until a player has been wired.
    #
    # Failing is a no-op on purpose: a HUD that cannot be written is a cosmetic problem
    # and must never interrupt the crop logic that called it.
    UpdateCropHealthHud() : void =
        if:
            CurrentCrop := Round[CropHealth]
            MaxCrop := Round[CropMaxHealth]
            CropText := CropHealthText?
        then:
            CropText.SetText(CropHealthDisplay(CurrentCrop, MaxCrop))

    # Wires the Reload key to the UFO attack for every player already in the game.
    #
    # WHY A KEY CANNOT BE A DEDICATED KEY. Both `input_action` and `input_mapping` are
    # `epic_internal` in the digest, so Verse cannot construct either, and the project's
    # Assets digest exposes no input assets, so the editor cannot author one either.
    # Every bindable action in the whole SDK belongs to Epic: Reload, WeaponPrimary,
    # WeaponSecondary, Crouch, Sprint, Jump, plus menu-only actions. So the ability
    # rides on an existing action rather than getting its own.
    #
    # RELOAD IS THE LEAST INTRUSIVE ONE AVAILABLE. Nothing in this project ever gives
    # the player a weapon, and reloading without one does nothing observable. The day
    # a weapon appears, pressing R will both reload and call the UFO - that coupling is
    # unavoidable without an action of our own, and there is no way to get one.
    #
    # PER PLAYER, NOT GLOBAL, and that is the real structural difference from the
    # button. GetPlayerInput takes a player, so there is nothing to subscribe until
    # players exist. This wires the ones present at OnBegin only; players who join
    # later are a separate step (PlayerAddedEvent) and do not matter while this is
    # single-player.
    WireUfoKeyForPlayers() : void =
        var WiredCount : int = 0

        for (CurrentPlayer : GetPlayspace().GetPlayers()):
            if:
                # Failable per the digest, so a player whose input is unavailable is
                # skipped rather than crashing the wiring for everyone else.
                PlayerInput := GetPlayerInput[CurrentPlayer]
            then:
                # Reload comes from the `using` on /Fortnite.com/Input/Character at the
                # top of the file. The qualified form `(/Fortnite.com/Input/Character:)Reload`
                # does NOT resolve here - the compiler asks for the using explicitly -
                # and importing the submodule turned out to be safe anyway: it brings
                # in the module's members, not the name `Character`.
                ReloadEvents : input_events(logic) = PlayerInput.GetInputEvents(Reload)
                ReloadEvents.ActivationTriggeredEvent.Subscribe(OnUfoKeyPressed)

                set WiredCount += 1
            else:
                # NOT SILENT, deliberately. "The key does nothing" is miserable to
                # debug from an empty log, and this is the one failure that produces
                # exactly that symptom.
                Print("WARNING: could not get player input for a player - the UFO key will not work for them")

        Print("UFO key wired to Reload for {WiredCount} player(s) - the UFO button still works too")

    # Runs when a wired player presses Reload.
    #
    # THE PAYLOAD IS A TUPLE. ActivationTriggeredEvent is a
    # `listenable(tuple(player, t))`, and for Reload - an `input_action(logic)` - that
    # is `tuple(player, logic)`. This is declared as two parameters rather than one
    # tuple parameter because in Verse a parameter list IS a tuple, so this signature
    # already has the type the Subscribe callback wants. If the compiler disagrees, the
    # fallback is a single `Payload : tuple(player, logic)` parameter read with
    # `Payload(0)`.
    #
    # `player` derives from `agent` in the digest, so it flows straight into the
    # existing handler with no conversion and no change to the attack.
    #
    # IT ENTERS THROUGH OnUfoPressed, NOT TryUfoAttack, and that distinction matters:
    # the cooldown gate lives in OnUfoPressed. Calling the attack directly would give
    # the key an ability the button does not have - firing with no cooldown at all.
    # Both triggers go through the same door so they cannot drift apart.
    # InputValue is received and not used. It has to stay in the signature - that is
    # what makes this match tuple(player, logic) - but it cannot be logged: there is no
    # ToString overload for `logic`, so interpolating it does not compile. It carries no
    # information worth converting here anyway, since ActivationTriggeredEvent only
    # fires when the input has already succeeded.
    OnUfoKeyPressed(InPlayer : player, InputValue : logic) : void =
        Print("UFO key pressed")
        OnUfoPressed(InPlayer)

    OnUfoPressed(InAgent : agent) : void =
        Now : float = GetSimulationElapsedTime()

        if (Now < UfoReadyAt):
            # The remaining time IS the state - a subtraction, not a stored value, so
            # it cannot disagree with whether the gate is closed. No Max clamp needed
            # either: this branch only runs when the difference is already positive.
            Print("UFO on cooldown - {UfoReadyAt - Now} s left")
        else:
            TryUfoAttack(InAgent)

    # The attack itself, unchanged from step 1. Split out of OnUfoPressed only so the
    # cooldown gate could go in front of it without touching any of this.
    #
    # IT ARMS THE COOLDOWN ITSELF, at the bottom of the `then` branch, and that
    # placement is the point: the cooldown starts only if the attack ACTUALLY RAN. A
    # press that cannot resolve a fort_character did nothing, so charging it a
    # cooldown would punish the player for an engine hiccup.
    TryUfoAttack(InAgent : agent) : void =
        if:
            # The pressing player's body. GetFortCharacter is failable - the digest
            # says it "fails if InAgent is not a fort_character" - so a press from
            # anything that is not a live player simply does nothing.
            Character := InAgent.GetFortCharacter[]
        then:
            # THE ATTACK NO LONGER KILLS ANYTHING HERE. Up to sub-step 2 this function
            # ran the area query and applied lethal damage on the spot, and the UFO was
            # a flourish over an already-empty stage. Now the query, the damage and the
            # ship all live in RunUfoAbduction, in that order and spread over time, so
            # the cows die when the beam has finished lifting them rather than the
            # instant the button is pressed.
            #
            # What is left here is what has to happen synchronously with the press:
            # work out WHERE, and charge the cooldown.
            #
            # Built FROM the character's own transform rather than from scratch, which
            # is what the example does too. A `transform` literal given only a
            # Translation would take the DEFAULT for Scale - a zero vector - and it is
            # not documented whether that would collapse the query volume. Taking a
            # known-good transform and overwriting what we mean to change avoids having
            # to find out.
            #
            # fort_character inherits `positional`, so GetGlobalTransform() hands back
            # LUF directly. This is the whole reason the un-aimed version is the safe
            # first step: there is no classic-to-LUF conversion anywhere in it.
            var GroundTransform : transform = Character.GetGlobalTransform()

            # Scale forced to unit so UfoRadius means centimeters and nothing else.
            # Inheriting the player's scale would silently multiply the radius.
            set GroundTransform.Scale = vector3{ Left := 1.0, Up := 1.0, Forward := 1.0 }

            # ONE transform is passed, not two. RunUfoAbduction derives the ship's
            # hover point from this, which is what guarantees the ship is exactly above
            # the area it is emptying - they cannot drift apart because there is only
            # one source for both.
            #
            # WaveGeneration is captured NOW, by value, so the task carries the wave it
            # belongs to and can tell whether that wave is still current when it wakes.
            spawn { RunUfoAbduction(GroundTransform, WaveGeneration) }

            # Arm the cooldown: one assignment, no task, nothing to clean up later.
            #
            # The clock is read fresh rather than passed down from OnUfoPressed. There
            # is no suspension point between the two reads, so it is the same instant
            # either way, and reading it here keeps this function's cooldown behaviour
            # self-contained instead of depending on a value its caller measured.
            #
            # KEEP UfoCooldownSeconds >= UfoRiseSeconds + UfoBeamLingerSeconds, or a
            # second press can put a second ship in the sky while the first is still
            # there. Not enforced in code on purpose: UfoReadyAt is already the gate,
            # and a second latch for the same job would be duplicated state.
            set UfoReadyAt = GetSimulationElapsedTime() + UfoCooldownSeconds
        else:
            Print("WARNING: UFO attack could not run - the presser has no fort_character, or there is no simulation entity")

    # Puts a UFO in the sky over the target, holds it there, and takes it away again.
    #
    # SUB-STEP 1 OF THE CHOREOGRAPHY, and deliberately hollow: no beam, no cows, no
    # damage. Everything that kills still happens instantly in TryUfoAttack. This
    # exists to answer two questions before anything is built on top of it - does the
    # ship appear where we asked, and does it leave again - because both of those are
    # cheap to check now and expensive to debug later underneath a beam.
    #
    # LINEAR, WITH THE CLEANUP ON THE FALL-THROUGH PATH. There is no `break` and no
    # early exit between the ship existing and RemoveFromParent, and there must never
    # be one: this SDK has no cancellation and Verse has no `finally`, so the only
    # thing guaranteeing the sky gets emptied is that every path reaches the last
    # line. A guard added later must skip WORK, never skip the ending.
    #
    # The one `if` that does wrap the ending is the simulation-entity lookup, and that
    # is not the same hazard: if it fails, no ship was ever created, so there is
    # nothing left behind to clean up.
    RunUfoAbduction(GroundTransform : transform, Generation : int)<suspends> : void =
        if:
            SimulationEntity := GetSimulationEntity[]
        then:
            # The ship's hover point: the attack's own ground centre lifted straight
            # up, so it is always exactly above the area it empties. Derived here
            # rather than passed in so the two cannot disagree.
            var HoverTransform : transform = GroundTransform
            set HoverTransform.Translation.Up = HoverTransform.Translation.Up + UfoHoverHeightCm
            set HoverTransform.Scale = vector3{ Left := UfoScale, Up := UfoScale, Forward := UfoScale }

            # Same three-line spawn the wave loop uses for cows: instantiate the
            # prefab, put it in the world, then place it. AddEntities has to come
            # first - until then the prefab exists but its components are not in the
            # scene.
            UfoEntity : entity = Prefabs.P_UFO{}
            SimulationEntity.AddEntities(array{ UfoEntity })
            UfoEntity.SetGlobalTransform(HoverTransform)

            # DISARM THE PATROL THE PREFAB BROUGHT WITH IT.
            #
            # P_UFO ships with a simple_movement_component, whose OnBeginSimulation
            # (SimpleMovementComponent.verse:24-33) calls SetKeyframes with the
            # prefab's authored keyframes in Loop mode, and whose AutoPlay defaults to
            # true. So this entity configured itself a flight path the instant
            # AddEntities put it in the scene, and it did so BEFORE the line above
            # placed it - SetKeyframes rebases on the current transform, so that path
            # is anchored to wherever the prefab's default position was.
            #
            # It probably would not play: the Play() call hangs off
            # FortRoundManager.SubscribeRoundStarted, and a ship spawned mid-round
            # never receives RoundStarted. "Probably" is not a guarantee, so Pause()
            # makes it certain.
            #
            # PAUSE AND NOT STOP. Stop() is documented as resetting the transform to
            # the initial state, which here means throwing the ship back to wherever
            # the prefab was authored - the same trap the sedation path documents for
            # cows. Pause() freezes without moving anything.
            #
            # Both branches fall through: a prefab with no movement component is
            # nothing to fix, it just means there was never a patrol to disarm.
            if:
                UfoMovementComp := UfoEntity.GetComponent[keyframed_movement_component]
            then:
                UfoMovementComp.Pause()
                Print("UFO patrol paused - the ship should now hold still")
            else:
                Print("UFO has no keyframed_movement_component - nothing to disarm")

            # KNOWN STATE FIRST. The prefab's authored Enabled flags are not visible
            # from the digest, so whether it arrives with the beam already lit is a
            # coin toss. Turning it off before turning it on means the sequence below
            # does not depend on the answer.
            #
            # It buys something real on the sound as well as being documentation: the
            # beam sound may be on AutoPlay, and Stop-then-Play starts it cleanly
            # instead of calling Play on an already-playing source.
            DisableAbductionBeam(UfoEntity)
            EnableAbductionBeam(UfoEntity)

            Print("UFO arrived {UfoHoverHeightCm} cm above the target (wave generation {Generation})")

            # The cows caught in the beam, remembered so they can be killed once the
            # rise has finished. Declared out here, OUTSIDE the guard below, so the
            # damage pass and the cleanup that follow always have something valid to
            # walk even when the query never ran.
            var AbductedCows : []entity = array{}

            # THE GENERATION GUARD SKIPS THE QUERY, NEVER THE ENDING. If the run ended
            # or the wave moved on between the press and this line, the ship still
            # appears and still leaves - a half-second of harmless theatre - but it
            # takes nobody with it. Both branches fall through to the Sleep below.
            #
            # Same pair of conditions the drain loop uses, and for the same reason:
            # the generation catches a new wave and the defeat's bump, the latch
            # catches either ending.
            if:
                Generation = WaveGeneration
                not RunHasEnded?
            then:
                QuerySphere : collision_sphere = collision_sphere{ Radius := UfoRadius }

                # Counted separately on purpose, because the two numbers fail in
                # different ways. TotalHits counts EVERYTHING the query returned -
                # ground, props, the lot. AbductedCows counts what survived the cast
                # and the filters.
                #
                # That distinction is the diagnostic: cows but no hits means the area
                # is empty or too small, while ZERO hits of any kind points at the
                # query itself - a Queryable flag turned off, or a radius of nothing.
                var TotalHits : int = 0

                for (Overlap : SimulationEntity.FindOverlapHits(GroundTransform, QuerySphere)):
                    set TotalHits += 1

                    if:
                        # The cast IS the filter, exactly as in the example: SM_Toy_Cow
                        # is the generated class for the cow's mesh component, so a
                        # component that casts to it belongs to a cow and nothing else.
                        # `.Entity` then walks back from the component to the cow.
                        CowMesh := Meshes.SM_Toy_Cow[Overlap.TargetComponent]
                        CowEntity := CowMesh.Entity

                        # Skip cows that are already out of the fight. A sedated cow is
                        # parented and healthy-looking to a query but has 0 health, and
                        # watching a flattened body float up would read as a bug. It
                        # would also be pointless: the counter already forgot it.
                        CowHealthComp := CowEntity.GetComponent[health_component]
                        CowHealthComp.CurrentHealth > 0.0

                        # DEDUPLICATION, and the reason it is needed: the digest says a
                        # mesh target reports one hit per overlapping collision element,
                        # so a single cow can come back many times from one query. Two
                        # rise animations on one cow means the second SetKeyframes
                        # rebases mid-flight and the cow visibly jumps.
                        #
                        # The interactable does double duty as the marker. It has to be
                        # switched off anyway - a cow being carried away must not still
                        # offer a "sedate me" prompt - so its enabled state is exactly
                        # "this cow has not been processed yet". IsEnabled is failable,
                        # so a second hit on the same cow simply fails this line.
                        #
                        # A cow with no interactable at all is skipped entirely. That
                        # only happens on the path that already logs a warning at spawn
                        # time, so it is a known-broken cow rather than a new hole.
                        CowInteractableComp := CowEntity.GetComponent[interactable_component]
                        CowInteractableComp.IsEnabled[]
                    then:
                        # FOUR OPERATIONS, AND THE ORDER IS LOAD-BEARING.
                        #
                        # 1. The flag FIRST, before anything can observe a death. The
                        #    ApplyDamage at the end of this block signals EliminatedEvent,
                        #    and health_component's own comment records that the digest
                        #    does not say whether Signal resumes waiters synchronously. If
                        #    WatchEnemyDeath ran inside that call with the flag still
                        #    down, it would take the `else` branch and RemoveFromParent
                        #    the cow - out of the scene before it had risen an inch.
                        #
                        # 2. The prompt off. A cow being carried away must not still offer
                        #    to be sedated. This also remains the deduplication marker for
                        #    repeat hits from the same query.
                        #
                        # 3. THE RISE BEFORE THE DAMAGE, not just the flag. StartCowRise
                        #    reads components, reads the live transform and calls
                        #    SetKeyframes - which rebases the path on that transform - and
                        #    all of it wants an entity that is still placed and simulating.
                        #    Handing the keyframes over while the cow is unambiguously
                        #    alive removes the question entirely.
                        #
                        # 4. The damage LAST, which is the whole point of variant B: the
                        #    cow stops being a threat as the beam takes hold rather than
                        #    two seconds later. The drain loop and the grazing pulse both
                        #    fail their `CurrentHealth > 0.0` guard on their next wake, and
                        #    the live counter drops now.
                        #
                        # No suspension point exists between any of the four, so no other
                        # task can observe a half-applied state.
                        set CowHealthComp.IsBeingAbducted = true
                        CowInteractableComp.Disable()
                        StartCowRise(CowEntity, HoverTransform.Translation)
                        CowHealthComp.ApplyDamage(UfoKillDamage)

                        # Remembered so the rise can be cleaned up when it finishes. The
                        # abduction owns these bodies now - WatchEnemyDeath deliberately
                        # leaves them alone - so this list is the only thing that will
                        # ever remove them.
                        set AbductedCows += array{ CowEntity }

                Print("UFO beam caught {AbductedCows.Length} cows within {UfoRadius} cm ({TotalHits} total overlaps)")
            else:
                Print("UFO beam caught nothing - its wave moved on or the run ended before it arrived")

            # THE RISE. One wait for every cow, and the same UfoRiseSeconds that each
            # cow's keyframe was given as its Duration - so the ship cannot leave
            # before they arrive, by construction rather than by tuning two numbers to
            # match.
            Sleep(UfoRiseSeconds)

            # NOW the bodies go. They died two seconds ago, when the beam took hold -
            # health, EliminatedEvent, the live counter and the crop all settled then.
            # What is left is purely disposal, and it belongs here because the third
            # branch of WatchEnemyDeath deliberately declined to do it: an abducted cow
            # has to survive long enough to finish rising, so the abduction owns the body
            # and this is where that ownership ends.
            #
            # NO ApplyDamage HERE ANY MORE. It used to be the killing blow, applied after
            # the rise, and that is exactly what let a rising cow keep eating the crop for
            # UfoRiseSeconds. Its health guard would make a second call harmless, but a
            # harmless call that looks like the kill would be misleading to read.
            #
            # NOT generation-guarded, and it must not be. If the wave turned over during
            # the rise, ClearCurrentWave already detached these cows and this is a no-op
            # on each - the same no-op ClearCurrentWave itself performs every wave when it
            # walks its list of already-dead enemies. A guard here could only skip a
            # cleanup that must always happen.
            for (AbductedCow : AbductedCows):
                AbductedCow.RemoveFromParent()

            # The beam holds a moment longer than the cows, so it does not cut out on
            # the same frame the last one disappears.
            Sleep(UfoBeamLingerSeconds)

            # Beam off before the ship goes. Strictly speaking redundant - the
            # RemoveFromParent below cascades and destroys these components anyway -
            # and kept for two reasons: it stops the beam sound cleanly instead of
            # having it cut off mid-sample by destruction, and it is the hook a later
            # sub-step needs if the beam should ever switch off BEFORE the ship leaves
            # rather than with it.
            DisableAbductionBeam(UfoEntity)

            # The ending. Unconditional, last, and the reason this whole function is
            # shaped the way it is. Removing the parent cascades, so the meshes, the
            # beam, the light and the sounds all go with it in one call.
            UfoEntity.RemoveFromParent()
            Print("UFO left")
        else:
            Print("WARNING: no simulation entity available - cannot spawn the UFO")

    # Starts one cow floating up towards the ship. Returns immediately - the flight
    # itself is played by the engine.
    #
    # ADAPTED FROM THE EXAMPLE'S AbductCow, with two changes.
    #
    # FIRST, IT DOES NOT WAIT AND IT DOES NOT SUSPEND. The example ended with
    # `CowMesh.EntityEnteredEvent.Await()` - an unbounded wait for the cow to touch the
    # ship, which parks forever if it never does, and this project already carries two
    # documented parked-task leaks. Replacing it with a Sleep would have fixed the
    # unboundedness but still cost one task per cow. Handing the keyframes to the
    # engine and returning costs none: RunUfoAbduction does the single Sleep for all
    # of them, which is also what makes the ship and the cows share one clock.
    #
    # SECOND, IT DOES NOT KILL OR REMOVE THE COW. The example's version finished with
    # RemoveFromParent, which would bypass health, EliminatedEvent and the live
    # counter. Here the caller applies ordinary lethal damage when the rise ends and
    # the existing death pipeline disposes of the body.
    #
    # What is kept is the example's flight: the delta from the cow to the ship, the
    # ease-in curve so it starts slow and accelerates upward, and the cow's own sound.
    StartCowRise(CowEntity : entity, ShipTranslation : vector3) : void =
        if:
            MovementComp := CowEntity.GetComponent[keyframed_movement_component]
        then:
            # Keyframes are RELATIVE, so the translation is the difference between the
            # cow and the ship.
            #
            # Scale MUST be all zeros, the same trap MoveEnemyToPasture documents:
            # translation and scale are applied ADDITIVELY, so leaving Scale at its
            # default would grow the cow all the way up. Rotation is left alone, so the
            # cow rises upright rather than tumbling.
            #
            # SetKeyframes destroys whatever path this component was holding, which
            # here is the walk to the pasture. That is fine and intended - the cow is
            # leaving - but it is also irreversible: a cow whose abduction was somehow
            # interrupted would be left with no route and would simply stand still.
            # One more reason RunUfoAbduction must never abort half way.
            RiseDelta : transform = transform:
                Translation := ShipTranslation - CowEntity.GetGlobalTransform().Translation
                Scale := vector3{ Left := 0.0, Up := 0.0, Forward := 0.0 }

            # The Duration IS UfoRiseSeconds, the same field the caller sleeps on.
            # Ease-in because a tractor beam should take hold gently and then pull.
            RiseKeyframe : keyframed_movement_delta = keyframed_movement_delta:
                Transform := RiseDelta
                Duration := UfoRiseSeconds
                Easing := ease_in_cubic_bezier_easing_function{}

            MovementComp.SetKeyframes(array{ RiseKeyframe }, oneshot_keyframed_movement_playback_mode{})
            MovementComp.Play()

            # The cow's own sound component - MSS_Cow_Upset, four moo variations. It is
            # already on every P_Cow, so an abducted cow complains on the way up for
            # free. Optional in the sense that a cow without one still flies.
            if (CowSoundComp := CowEntity.GetComponent[sound_component]):
                CowSoundComp.Play()
        else:
            Print("WARNING: a cow caught in the beam has no keyframed_movement_component - it will die in place instead of rising")

    # Lights the abduction beam on a spawned UFO: the beam mesh, the spot light and
    # the beam sound.
    #
    # ADAPTED FROM THE EXAMPLE, one change only. In
    # FindOverlapHitsExampleComponent.EnableAbductionBeam these are methods on a
    # component, so they walk the component's own implicit `Entity`. wave_manager is a
    # creative_device and has no `Entity`, so the ship comes in as a parameter. The
    # bodies are otherwise the example's.
    #
    # WHY FindDescendantComponents AND NOT GetComponent: these components do not live
    # on the prefab's root entity. P_UFO owns child entities - AbductionBeamMesh,
    # AbductionLight and the two sound components are spread across them - and this
    # call walks the whole subtree "to and including InEntity" per the digest.
    #
    # THE COUNTS ARE THE DIAGNOSTIC. Three separate lookups can fail independently,
    # and a silent zero would look exactly like a beam that is on but invisible. If the
    # log says 0 for one of the three, that lookup is the problem and not the artwork.
    EnableAbductionBeam(UfoEntity : entity) : void =
        var BeamMeshCount : int = 0
        var BeamLightCount : int = 0
        var BeamSoundCount : int = 0

        for (BeamMesh : UfoEntity.FindDescendantComponents(Meshes.S_EV_SimpleLightBeam_01)):
            BeamMesh.Enable()
            set BeamMeshCount += 1

        # Every spot light in the hierarchy, which is the one the example targets too.
        # P_UFO carries exactly one, AbductionLight - if a second is ever added to the
        # prefab this would light that as well.
        for (BeamLight : UfoEntity.FindDescendantComponents(spot_light_component)):
            BeamLight.Enable()
            set BeamLightCount += 1

        # Play, not Enable: sound_component's Play is what starts the asset. Targeting
        # MSS_Ship_Beam specifically leaves MSS_Ship_Hover_Loop alone, so the ship's
        # engine hum is not touched by the beam going on and off.
        for (BeamSound : UfoEntity.FindDescendantComponents(Sounds.MSS_Ship_Beam)):
            BeamSound.Play()
            set BeamSoundCount += 1

        Print("Abduction beam ON - {BeamMeshCount} beam mesh, {BeamLightCount} spot light, {BeamSoundCount} sound")

    # The mirror of EnableAbductionBeam. Silent on purpose: it is called twice per
    # visit and the counts it would report are the same ones Enable already logged.
    DisableAbductionBeam(UfoEntity : entity) : void =
        for (BeamMesh : UfoEntity.FindDescendantComponents(Meshes.S_EV_SimpleLightBeam_01)):
            BeamMesh.Disable()

        for (BeamLight : UfoEntity.FindDescendantComponents(spot_light_component)):
            BeamLight.Disable()

        for (BeamSound : UfoEntity.FindDescendantComponents(Sounds.MSS_Ship_Beam)):
            BeamSound.Stop()

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

        # One of the two log lines that replaced the per-tick spam. It carries the
        # crop's value AND the rate, so the drain that follows is predictable from
        # this line alone without printing anything while it runs.
        Print("cow reached the pasture - it starts eating {CropDamagePerTick} every {CropDamageInterval} s. Crop at {CropHealth} / {CropMaxHealth}")

        # Hand over to the drain. A plain call, NOT a new spawn: this task already
        # exists per cow and has nothing left to wait for, so the eating happens on
        # the same thread of execution. MovementComp is not needed past this point.
        #
        # Every guard that used to sit here now lives inside the loop, because with
        # continuous damage they have to be re-checked before every subtraction
        # rather than once on arrival.
        # Start the cow breathing. A `spawn`, unlike the drain below, precisely
        # BECAUSE the drain is a plain call that does not return until the cow stops
        # eating: the two have to run concurrently to keep independent rhythms.
        #
        # Launched BEFORE the drain call for that reason - anything written after it
        # would not run until the eating was already over.
        #
        # Cosmetic only. Removing this line removes the pulse and changes nothing
        # else. See PulseWhileEating.
        spawn { PulseWhileEating(Enemy, Generation) }

        DrainCropWhileAtPasture(Enemy, Generation)

    # Drains the crop, one tick every CropDamageInterval, for as long as this ONE
    # cow is still standing in the pasture and still a threat.
    #
    # THE INVARIANT THIS FUNCTION EXISTS TO PROTECT:
    #   No `set CropHealth` may ever run without the guards having been checked in
    #   the same suspension-free span.
    # Sleep is the only suspension point in the loop, and it sits at the very end
    # of the iteration - so the check, the subtraction and the defeat test are one
    # uninterrupted block. Verse is cooperatively scheduled on a single thread, so
    # that contiguity is a guarantee, not a hope.
    #
    # THE STRUCTURAL RULE, non-negotiable: every iteration either sleeps or breaks.
    # The Sleep in the `then` branch is unconditional, and the `else` branch ends
    # in an unconditional `break`. An `else` that neither slept nor broke would be
    # a busy loop with no suspension point, which on a single cooperative thread
    # would freeze the entire game - not just this cow. That is why the shape is
    # this rigid. It carried a temporary tick-count backstop through its first
    # build; that has been removed now the four real guards are verified to stop
    # the loop in every case (sedation, death, wave end, game over, manual Start).
    #
    # WHY `CurrentHealth > 0.0` RATHER THAN `not IsSedated?`: 4b established that
    # reaching 0 health means "no longer a threat", with dying and falling asleep
    # as the two ways to get there. So "is this cow still a threat" IS the stop
    # condition, and health is where it is written. It is a strict superset of the
    # sedation flag: it catches sedated cows, killed cows, and the window between
    # Signal firing and WatchEnemyDeath resuming, in which health is already 0 but
    # no body has been removed yet. One condition instead of two, and it is the
    # same latch the live counter relies on.
    #
    # POLLING LATENCY COSTS TASK LIFETIME, NEVER CROP HEALTH. A cow sedated just
    # after a tick keeps this task alive for up to one more interval, but when it
    # wakes the guard fails and it exits without subtracting anything. Maximum
    # crop damage dealt after a game over is therefore exactly 0.0.
    #
    # This also FIXES rather than inherits the parked-watcher leak for the
    # post-arrival half: a polling loop exits on its own when its cow is
    # neutralized or swept, where the old one-shot Await could park forever.
    DrainCropWhileAtPasture(Enemy : entity, Generation : int)<suspends> : void =
        loop:
            if:
                # Guard 1: the wave this cow belonged to must still be the current
                # one. Catches a new wave starting and the generation bump the
                # defeat below performs.
                Generation = WaveGeneration

                # Guard 2: the run must still be going. After either ending,
                # eating stops entirely - no damage, not even a log line.
                not RunHasEnded?

                # Guard 3: the cow must still be in the scene. GetParent[] is
                # failable and the digest says it "fails if there is currently no
                # parent entity" - exactly the state RemoveFromParent leaves a
                # killed cow, or any cow swept by ClearCurrentWave, in. A direct
                # liveness test needing no coordination with the death watcher.
                Enemy.GetParent[]

                # Guard 4: the cow must still be a threat. This is the one that
                # stops a SEDATED cow, which is neutralized but still standing and
                # therefore still passes guard 3.
                HealthComp := Enemy.GetComponent[health_component]
                HealthComp.CurrentHealth > 0.0
            then:
                # The cow eats. Max clamps at 0 so the crop never goes negative.
                #
                # NO DATA RACE, even with several cows eating on the same interval.
                # A task runs from resume to its next suspension point without
                # interruption, and there is no Await or Sleep between reading
                # CropHealth, writing it and testing for defeat. Ticks are
                # therefore processed one after another, never interleaved, and no
                # subtraction can be lost.
                #
                # DELIBERATELY SILENT. Logging here meant one line per second per
                # cow, which buried everything else in the output. The crop's value
                # is reported at the two moments that matter instead - when a cow
                # starts eating and when it stops - plus the game over line.
                set CropHealth = Max(0.0, CropHealth - CropDamagePerTick)

                # HUD change 2 of 2. Placed immediately after the subtraction and before
                # the defeat test, so it adds no suspension point and the "no data race"
                # argument below is untouched: reading CropHealth, writing it, showing it
                # and testing for defeat all still happen in one uninterrupted stretch.
                UpdateCropHealthHud()

                # DEFEAT - moved in here unchanged from the old arrival handler.
                # The `not RunHasEnded?` is belt and braces: guard 2 above already
                # established it and nothing in between suspends. It is kept so
                # this block stays correct on its own terms.
                #
                # SEVERAL COWS CANNOT TRIGGER DEFEAT TWICE, for two independent
                # reasons: the latch is set before anything else can re-enter, and
                # the other cows' loops fail guard 2 on their next wake so they
                # never even reach this test.
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
                    # other drain loops, and any ChainNextWave still sleeping -
                    # without relying on each of them remembering to check the
                    # latch.
                    #
                    # Note this also invalidates THIS loop: guards 1, 2 and 3 all
                    # fail on the next wake, so the loop that caused the defeat
                    # shuts itself down. No explicit break is added here on
                    # purpose - one exit mechanism, not two.
                    set WaveGeneration += 1

                # The only suspension point, unconditional, and last.
                Sleep(CropDamageInterval)
            else:
                # Exactly one exit. The if/else below only chooses what to SAY; the
                # break is unconditional and last, exactly as before.
                #
                # WORKING OUT THE REASON: a cow that is still parented but has 0
                # health is precisely a SEDATED one - a killed cow gets
                # RemoveFromParent, so it cannot pass the first test. That makes
                # the interesting case exactly identifiable. Everything else -
                # killed, swept by ClearCurrentWave, wave replaced, run over -
                # shares one honest message rather than pretending to a precision
                # these two lookups cannot give.
                #
                # This re-tests conditions instead of remembering which guard
                # failed on purpose: no new state, and the guards above stay
                # untouched.
                if:
                    Enemy.GetParent[]
                    StoppedHealthComp := Enemy.GetComponent[health_component]
                    StoppedHealthComp.CurrentHealth <= 0.0
                then:
                    Print("cow stopped eating - sedated. Crop left at {CropHealth} / {CropMaxHealth}")
                else:
                    Print("cow stopped eating - it left the field, or its wave or run ended. Crop left at {CropHealth} / {CropMaxHealth}")

                break

    # Makes a grazing cow breathe: a sine swell-and-shrink around the scale it was
    # spawned at, for as long as it is actually eating.
    #
    # ONE TASK PER EATING COW, running alongside DrainCropWhileAtPasture rather than
    # inside it. That separation is the entire point: the two have unrelated rhythms.
    # Damage is a balance number tuned in whole seconds; breathing is a cosmetic
    # gesture that needs several writes per second to not look like a strobe. Sharing
    # one Sleep welded them together and forced the pulse to the damage cadence.
    # With its own loop, DrainCropWhileAtPasture is untouched - its Sleep is still
    # its only suspension point, and the damage rate is still exactly
    # CropDamagePerTick / CropDamageInterval.
    #
    # PURELY COSMETIC AND PURELY ADDITIVE. It reads the guards' state and writes only
    # the transform's scale. Nothing in the drain, the counter, the waves or the
    # sedation reads anything this writes. Delete this method and its single spawn and
    # the game plays identically.
    #
    # SAME FOUR GUARDS AS THE DRAIN, deliberately duplicated rather than shared: they
    # are the definition of "this cow is still eating", and re-testing them here means
    # this task ends on its own terms without any coordination with the drain. Like
    # the drain, it is a polling loop, so it self-terminates and adds no parked task
    # to the leak the death and arrival watchers document.
    #
    # EVERY WRITE IS ABSOLUTE, computed from the cached spawn scale and never from the
    # cow's current scale. That is the invariant that makes three writers of one
    # transform safe: no write can compound on another, so no sequence of them can
    # leave a size that is not one of the three known-good values.
    PulseWhileEating(Enemy : entity, Generation : int)<suspends> : void =
        # Where in the breath this cow is, in radians. A LOCAL, not a field: one task
        # runs per cow, so each carries its own phase for free and cows that arrived
        # at different moments breathe out of sync - a herd, not a chorus line.
        var PulsePhase : float = 0.0

        # Derived once, outside the loop. Retuning the dial mid-run therefore only
        # affects cows that start eating afterwards, which is the right trade: a cow
        # already breathing keeps a steady rhythm instead of lurching.
        SafeCycleSeconds : float = Max(MinEatPulseCycleSeconds, EatPulseCycleSeconds)
        PhaseStepRadians : float = TwoPiRadians / EatPulseSamplesPerCycle
        StepSeconds : float = SafeCycleSeconds / EatPulseSamplesPerCycle

        loop:
            if:
                # Guards 1-4 are the drain's, verbatim and in the same order.
                Generation = WaveGeneration
                not RunHasEnded?
                Enemy.GetParent[]
                HealthComp := Enemy.GetComponent[health_component]
                HealthComp.CurrentHealth > 0.0

                # Guard 5 is this task's own: without the cached spawn scale there is
                # no baseline to pulse around, and guessing one is how a cow ends up
                # the wrong size.
                SleepVisualComp := Enemy.GetComponent[sleep_visual_component]
            then:
                StandingScale : vector3 = SleepVisualComp.StandingScale

                # A sine, not the square wave this had while it lived in the drain
                # loop. At one write per second a square read as a slow throb, which
                # was fine; at eight writes per cycle it would read as a strobe.
                PulseFactor : float = 1.0 + EatPulseAmount * Sin(PulsePhase)

                # Uniform on all three axes. The sedated flatten is vertical-only, so
                # keeping this uniform means the two states never speak the same
                # visual language and cannot be mistaken for one another.
                PulsedScale : vector3 = vector3:
                    Left := StandingScale.Left * PulseFactor
                    Up := StandingScale.Up * PulseFactor
                    Forward := StandingScale.Forward * PulseFactor

                # Translation and Rotation carried across from the live transform: the
                # cow must not move or turn. Written out explicitly because a field
                # omitted from a `transform` literal takes its DEFAULT, not its
                # current value.
                CurrentTransform : transform = Enemy.GetGlobalTransform()

                PulsedTransform : transform = transform:
                    Translation := CurrentTransform.Translation
                    Rotation := CurrentTransform.Rotation
                    Scale := PulsedScale

                Enemy.SetGlobalTransform(PulsedTransform)

                # Wrapped rather than left to grow forever, so the argument to Sin
                # stays in a range where its precision is not worth thinking about.
                set PulsePhase += PhaseStepRadians
                if (PulsePhase > TwoPiRadians):
                    set PulsePhase -= TwoPiRadians

                # The only suspension point, unconditional, and last - same shape as
                # the drain loop, and the line that makes this rhythm independent.
                Sleep(StepSeconds)
            else:
                # Exactly one exit, and the break is unconditional and last.
                #
                # UNDO THE PULSE: a single absolute write back to the cached spawn
                # scale, so a cow can never be left frozen mid-breath. Not
                # interpolated - there is no "part of the way back" that looks better
                # than simply being the right size.
                #
                # SEDATION WINS, AND THIS IS WHERE THAT IS ENFORCED. IsSedated is set
                # by OnInteractSucceeded BEFORE the ApplyDamage that brings health to
                # 0, so by the time this loop wakes and fails guard 4 the flag is
                # already readable and true. Reading the flag the sedation path
                # already sets is why the flatten needed no new state and no change.
                #
                # WHY THE FLAG RATHER THAN HEALTH: health reaches 0 for killed cows
                # too, and those DO want their scale put back - harmlessly, since they
                # are detached a moment later. The flag is what distinguishes asleep
                # from dead, which is exactly the distinction the restore needs.
                #
                # THE RESULT IS ORDER-INDEPENDENT. If this task wrote last,
                # ApplySleepFlatten overwrites it absolutely from the same cache and
                # the cow ends up flattened. If the flatten wrote first, this block
                # skips and the cow stays flattened. Neither order can leave a
                # breathing-and-flattened hybrid, because no write is ever relative to
                # the current scale.
                #
                # GetParent[] guards the pointless case: a cow already swept out of the
                # world has no scale worth correcting.
                #
                # SILENT. The drain already logs when a cow stops eating; a second
                # line per cow would be noise.
                if:
                    Enemy.GetParent[]
                    RestoredHealthComp := Enemy.GetComponent[health_component]
                    not RestoredHealthComp.IsSedated?
                    RestoreVisualComp := Enemy.GetComponent[sleep_visual_component]
                then:
                    RestoredTransform : transform = Enemy.GetGlobalTransform()

                    CleanTransform : transform = transform:
                        Translation := RestoredTransform.Translation
                        Rotation := RestoredTransform.Rotation
                        Scale := RestoreVisualComp.StandingScale

                    Enemy.SetGlobalTransform(CleanTransform)

                break

    # Squashes a sedated cow vertically, so a sleeping body reads as asleep rather
    # than as a cow that merely stopped walking.
    #
    # PURELY COSMETIC AND PURELY ADDITIVE. It reads nothing the game logic owns and
    # writes nothing the game logic reads - not health, not IsSedated, not the live
    # counter, not the keyframes, not the crop. Delete this method and its single
    # call and the game plays exactly as before, just without the tell.
    #
    # NOTE ON THE API: there is no SetScale. Scale is not a property of
    # mesh_component at all - that component exposes only Enable/Disable,
    # Collidable, Queryable and Visible. Scale lives in the transform, so the only
    # way to write it is to write a whole transform, which is why the two fields we
    # are NOT changing have to be carried across by hand below.
    #
    # WHY CALLED FROM WatchEnemyDeath AND NOT FROM OnInteractSucceeded: this is the
    # one place that decides a body stays standing, so it is the one place that
    # knows a body needs to look asleep. Any future sedation source - a dart, a
    # trap - gets the visual for free. Same argument as the RemoveFromParent it
    # sits next to. It also keeps the dial in scope: SleepFlattenFactor lives on
    # wave_manager, and enemy_interaction_handler would have to be handed it as a
    # constructor field.
    #
    # IT RUNS WITH THE MOVEMENT ALREADY PAUSED, and that is load-bearing rather
    # than lucky. OnInteractSucceeded pauses the keyframed_movement_component
    # BEFORE the ApplyDamage that fires the event this hangs off, and a paused
    # animation stops writing the transform - so the scale written here survives.
    # The same write applied to a PLAYING animation would be undone on the next
    # pre-physics tick.
    ApplySleepFlatten(SleepingEnemy : entity) : void =
        # The cached spawn scale is the whole point, and it is why nothing here
        # mentions EnemyScale. The spawn loop wrote Scale as a uniform vector3 of
        # EnemyScale on all three axes and handed that same vector to
        # sleep_visual_component; we read it straight back and multiply ONLY its Up
        # component. The cow ends up at EnemyScale on Left and Forward and at
        # EnemyScale * SleepFlattenFactor on Up: same footprint, same length,
        # lower. Retune EnemyScale in the Details panel and this keeps working with
        # no change here, because the number is never restated.
        #
        # Reading the CACHE rather than the cow's current scale also makes this
        # immune to how keyframed movement treats scale. That component applies
        # scale ADDITIVELY, which MoveEnemyToPasture already has to defend against
        # by zeroing the delta's Scale; if that defence ever changed, a
        # read-modify-write of the live transform would silently flatten the wrong
        # number. The cache cannot drift that way.
        if:
            SleepVisualComp := SleepingEnemy.GetComponent[sleep_visual_component]
        then:
            StandingScale : vector3 = SleepVisualComp.StandingScale
            SafeFlattenFactor : float = Max(MinSleepFlattenFactor, SleepFlattenFactor)

            FlattenedScale : vector3 = vector3:
                Left := StandingScale.Left
                Up := StandingScale.Up * SafeFlattenFactor
                Forward := StandingScale.Forward

            # Translation and Rotation come from the cow's CURRENT transform, not
            # from the cache: it has to stay exactly where and how it fell asleep.
            # Only the scale is being replaced.
            #
            # Both are written out explicitly because `transform` is a struct - a
            # field omitted from the literal takes its DEFAULT, not its current
            # value, so omitting them would teleport the cow to the world origin
            # and face it north. Same trap the facing write in the spawn loop
            # documents.
            CurrentTransform : transform = SleepingEnemy.GetGlobalTransform()

            FlattenedTransform : transform = transform:
                Translation := CurrentTransform.Translation
                Rotation := CurrentTransform.Rotation
                Scale := FlattenedScale

            SleepingEnemy.SetGlobalTransform(FlattenedTransform)

            Print("Sedated cow flattened to {SafeFlattenFactor} of its standing height")
        else:
            # Not fatal, and deliberately not compensated for by guessing a scale:
            # a cow that cannot be flattened should stay the right size rather than
            # be resized to a number we made up.
            Print("WARNING: sedated cow has no sleep_visual_component - it will stay standing at full height")

    # One instance of this task runs per living enemy, parked on Await() until
    # that specific enemy STOPS BEING A THREAT - by dying, or by being sedated.
    # Launched by the spawn loop via `spawn`.
    #
    # EliminatedEvent means "this enemy is out", not strictly "this enemy died".
    # Both endings travel this one channel on purpose: ApplyDamage's
    # `if (CurrentHealth > 0.0)` guard makes it fire at most once per enemy, so
    # this task resumes at most once and OnEnemyDied is called at most once,
    # whatever neutralized the cow. That is what keeps the live counter correct
    # without the counter knowing sedation exists.
    #
    # No cancellation: `task` in /Verse.org/Concurrency exposes only Await(),
    # not Cancel. So if a wave is wiped by ClearCurrentWave instead of being
    # killed, these tasks park forever. Accepted for now; the fix is to race
    # this against a wave-ended event, which is a separate step.
    WatchEnemyDeath(HealthComp : health_component, Generation : int)<suspends> : void =
        # Await returns the payload of EliminatedEvent, which is the entity that
        # was neutralized - so we do not need to capture the entity separately.
        DeadEntity : entity = HealthComp.EliminatedEvent.Await()

        # THE ONLY PLACE the two endings diverge, and it decides one thing only:
        # what happens to the body. A sedated cow keeps standing where it fell
        # asleep; a killed one is removed from the world.
        #
        # The flag is guaranteed to be readable here: OnInteractSucceeded sets it
        # before the ApplyDamage that signals this event, so it is already true
        # whether Signal resumed us synchronously or later.
        #
        # Removing from the world happens HERE, at the moment of neutralization,
        # rather than in whatever dealt the damage. Any future damage source gets
        # that behaviour for free.
        # THREE OUTCOMES NOW, in strict order of precedence: abduction, then sedation,
        # then an ordinary death. Abduction is tested FIRST because it is the only one
        # that must override the others - a cow can be caught by the beam while it is
        # grazing, and it must neither be flattened nor removed here.
        #
        # Written as a nested if/else rather than an `else if` chain because this project
        # has no precedent for that form and this is not the place to find out.
        if (HealthComp.IsBeingAbducted?):
            # DELIBERATELY DOES NOTHING TO THE BODY. RunUfoAbduction owns it: the cow has
            # to stay in the scene long enough to finish rising into the ship, and that
            # task removes it when the rise ends. Removing it here would delete the cow
            # mid-flight - and, because Signal may resume this task synchronously inside
            # ApplyDamage, possibly before it had moved at all.
            Print("Enemy taken by the UFO - the beam owns the body until the rise ends")
        else:
            if (HealthComp.IsSedated?):
                Print("Enemy sedated - it is asleep and no longer a threat, body left standing")

                # The body stays, so make it read as asleep rather than as a cow that
                # merely stopped walking. Cosmetic only - see ApplySleepFlatten.
                ApplySleepFlatten(DeadEntity)
            else:
                DeadEntity.RemoveFromParent()

        # Called identically on both paths. The counter, its generation guard, its
        # run-ended latch and the wave/victory decisions are all unchanged: as far
        # as they are concerned one more enemy is simply out of the fight.
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

                    # Sweep the field, so a win leaves it as empty as a loss does.
                    #
                    # WHY THIS WAS MISSING AND WHY IT SHOWS. "Wave cleared" means
                    # LiveEnemyCount reached zero, and a SEDATED cow reaches zero
                    # without leaving the world - that is the whole point of the
                    # flag. So on the final wave every cow the player put to sleep
                    # was still lying in the field after the win, flattened, while
                    # the defeat path had been sweeping them all along. This is the
                    # same call, on the other ending.
                    #
                    # ORDER MATTERS AND MIRRORS THE DEFEAT PATH: latch, announce,
                    # then sweep. RunHasEnded is already true by the time a single
                    # entity leaves the scene, so nothing the sweep disturbs can
                    # re-enter this function - OnEnemyDied's own `not RunHasEnded?`
                    # guard turns any late death into a no-op.
                    #
                    # IT CANNOT RE-TRIGGER WAVE LOGIC. RemoveFromParent does not
                    # signal EliminatedEvent, and OnEnemyDied is only ever reached
                    # through that event, so removing bodies announces nothing.
                    #
                    # IT CANNOT UNBALANCE THE COUNTER. ClearCurrentWave assigns
                    # LiveEnemyCount = 0, and we are inside the `<= 0` branch, so
                    # the assignment is either a no-op or it normalises a count that
                    # had gone negative. Either way it cannot go out of step.
                    #
                    # NO GENERATION BUMP HERE, unlike defeat. Defeat bumps because
                    # it can strike with a wave fully alive and a ChainNextWave
                    # sleeping, and the stamp invalidates both in one stroke. At
                    # victory there is nothing of the sort in flight - the wave is
                    # cleared by definition and the chaining task is on the other
                    # branch of this `if` - and RunHasEnded is the stronger latch
                    # that every one of those guards checks anyway.
                    ClearCurrentWave()
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
