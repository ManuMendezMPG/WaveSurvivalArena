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

    # The event handler. Its signature must match what the event sends:
    # InteractedWithEvent sends an `agent`, so we receive one here.
    # (`InAgent` is the value; `agent` is the type — Verse is case-sensitive.)
    #
    # Phase 2, minimal step: spawn ONE enemy entity via Scene Graph.
    # This reuses the exact spawn pattern from SpawnPrefabDevice.verse.
    OnStartPressed(InAgent : agent) : void =
        Print("Start button pressed - spawning one enemy")
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
                # Instantiate a prefab. A prefab is a pre-assembled entity
                # (mesh + components). `LightPost.P_LightPost{}` is used here as
                # a visible PLACEHOLDER enemy until we build a real enemy prefab.
                Enemy : entity = LightPost.P_LightPost{}

                # AddEntities inserts the new entity into the live world.
                # Until this call, the prefab exists but is not "in the scene".
                SimulationEntity.AddEntities(array{ Enemy })

                # Read the marker's position. GetGlobalTransform() (NOT
                # GetTransform()) returns a /Verse.org/SpatialMath transform,
                # so its Translation is already a LUF vector3 and feeds
                # SetGlobalTransform directly, with no conversion.
                #
                # We take ONLY Translation and rebuild the transform, so the
                # enemy ignores whatever rotation/scale the marker prop happens
                # to have and keeps identity rotation + scale 1 (upright, full
                # size). No offset for now: it spawns exactly on the marker.
                SpawnTranslation : vector3 = SpawnMarker.GetGlobalTransform().Translation
                SpawnTransform : transform = transform{ Translation := SpawnTranslation }
                Enemy.SetGlobalTransform(SpawnTransform)

                Print("Enemy spawned at the SpawnMarker position")
            else:
                Print("WARNING: SpawnMarker is not assigned - place a prop in the level and assign it in the wave_manager Details panel")
        else:
            Print("WARNING: no simulation entity available - cannot spawn")
