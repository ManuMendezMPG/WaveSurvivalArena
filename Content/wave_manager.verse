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

    # HOW MANY enemies one button press spawns. Editable so the wave size can
    # be tuned from the Details panel without recompiling Verse.
    @editable
    EnemiesPerWave : int = 5

    # Distance in centimeters between two consecutive enemies in the row.
    # Also editable so the spacing can be eyeballed in-game and adjusted.
    @editable
    EnemySpacing : float = 200.0

    # Every entity spawned so far. `var` makes the field mutable; `[]entity` is
    # the Scene Graph entity array type (same one AddEntities takes).
    # Phase 2 only fills it - the live-enemy count will read it later.
    var SpawnedEnemies : []entity = array{}

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

    # Removes the enemies of the previous wave from the world and forgets them.
    #
    # This is what defines a "wave" as "the enemies currently alive": each
    # button press wipes the previous batch before spawning the next, so the
    # world never holds more than EnemiesPerWave enemies and successive waves
    # do not pile up on the same spot.
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

        Print("Cleared previous wave - {RemovedCount} enemies removed")

    # The event handler. Its signature must match what the event sends:
    # InteractedWithEvent sends an `agent`, so we receive one here.
    # (`InAgent` is the value; `agent` is the type — Verse is case-sensitive.)
    #
    # Phase 2: spawn a WAVE of enemy entities via Scene Graph. The per-enemy
    # spawn mechanism is unchanged (GetSimulationEntity -> AddEntities ->
    # SetGlobalTransform); it is just wrapped in a loop now.
    OnStartPressed(InAgent : agent) : void =
        Print("Start button pressed - spawning a wave of {EnemiesPerWave} enemies")

        # Wipe the previous wave FIRST, then spawn the new one. Clearing does
        # not depend on either guard below: on the very first press the array is
        # empty and this is a no-op.
        ClearCurrentWave()

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

                for (Index := 0..EnemiesPerWave - 1):
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

                    # Track it for the future live-enemy count.
                    set SpawnedEnemies += array{ Enemy }

                    set CurrentOffset += EnemySpacing

                # Now that each wave clears the previous one, SpawnedEnemies.Length
                # is the live enemy count, not a running total.
                Print("Wave spawned - {SpawnedEnemies.Length} enemies now alive, in a row from the SpawnMarker")
            else:
                Print("WARNING: SpawnMarker is not assigned - place a prop in the level and assign it in the wave_manager Details panel")
        else:
            Print("WARNING: no simulation entity available - cannot spawn")
