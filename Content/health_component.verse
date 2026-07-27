# Same import block the sample components in this project use, plus the two
# extras this file needs.
using { /Verse.org }
using { /Verse.org/Native }
using { /Verse.org/SceneGraph }                     # component, entity
using { /Verse.org/Simulation }
using { /Verse.org/Verse }                          # event(t)
using { /UnrealEngine.com/Temporary/Diagnostics }   # Print

# Health for a single Scene Graph entity.
#
# This is a STANDALONE component: nothing wires it to wave_manager yet. Add it
# to an entity and it manages that entity's health, nothing more.
#
# `class<final_super>(component)` is the Scene Graph component shape used by
# every sample component in this project (see SimpleMovementComponent.verse).
# The base class gives us `Entity`, a reference to the entity we are attached
# to, which we use as the payload of the eliminated event.
health_component<public> := class<final_super>(component):

    # Health this entity starts with. @editable so each enemy can be tuned
    # from the Details panel without recompiling.
    @editable
    MaxHealth : float = 100.0

    # Health right now. Starts at 0.0 only because a field needs SOME default;
    # the real initial value is set in OnBeginSimulation below.
    var CurrentHealth : float = 0.0

    # Fired once when this entity's health reaches 0. The payload is the entity
    # that died, so a listener knows WHICH enemy it was.
    #
    # IMPORTANT - this is an `event`, not a `listenable`:
    #   * `event(t)` (Verse.digest.verse:2028) implements `signalable` +
    #     `awaitable`. It gives us Signal() and Await(), and it is the only
    #     event class Verse code can construct.
    #   * `listenable(t)` (:2074) is the one that also supports Subscribe(), and
    #     it is what built-in events like InteractedWithEvent use - but every
    #     implementation of it in the SDK is native/epic_internal, so a
    #     user-defined component cannot produce one.
    # So listeners consume this with `Await()` from an async context
    # (OnSimulate, or a spawn{} / loop block in a device), NOT with Subscribe().
    EliminatedEvent<public> : event(entity) = event(entity){}

    # OnBeginSimulation is the phase where a component's simulation state is set
    # up (the digest splits the lifetime into OnAddedToScene -> OnBeginSimulation
    # -> OnSimulate -> OnEndSimulation). Health is simulation state, so it
    # belongs here rather than in OnAddedToScene.
    OnBeginSimulation<override>() : void =
        (super:)OnBeginSimulation()
        set CurrentHealth = MaxHealth
        Print("health_component: initialized with {CurrentHealth} health")

    # Subtracts Amount from the current health, never going below 0.
    ApplyDamage<public>(Amount : float) : void =
        # Guard: once dead, further damage is ignored. This is what guarantees
        # EliminatedEvent fires at most once. Written as a positive condition
        # rather than an early return to keep the control flow flat.
        if (CurrentHealth > 0.0):
            NewHealth : float = CurrentHealth - Amount

            if (NewHealth > 0.0):
                set CurrentHealth = NewHealth
                Print("health_component: took {Amount} damage, {CurrentHealth}/{MaxHealth} left")
            else:
                # Clamp instead of storing the negative value, so CurrentHealth
                # is always a meaningful number to read or display.
                set CurrentHealth = 0.0
                Print("health_component: took {Amount} damage, ELIMINATED")

                # Signal resumes every task currently waiting in Await().
                EliminatedEvent.Signal(Entity)
