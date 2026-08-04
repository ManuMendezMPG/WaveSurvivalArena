# Same import block the other components in this project use (see
# health_component.verse and SimpleMovementComponent.verse), plus SpatialMath
# for vector3.
using { /Verse.org }
using { /Verse.org/Native }
using { /Verse.org/SceneGraph }                     # component, entity
using { /Verse.org/Simulation }
using { /Verse.org/SpatialMath }                    # vector3 (LUF)

# Remembers the scale a cow was spawned at, so the sleep visual can flatten it
# without having to know anything about EnemyScale.
#
# PURE DATA, NO BEHAVIOUR. It has no OnBeginSimulation, no tick, no event. It
# exists only so that the value the spawn loop already computed is still readable
# later, from the unrelated place that learns a cow fell asleep.
#
# WHY A COMPONENT AND NOT A LIST ON wave_manager: the alternatives are worse.
# A `[]vector3` running parallel to SpawnedEnemies would have to be kept index-
# aligned with it forever, and an `[entity]vector3` map depends on `entity` being
# usable as a map key, which is unverified in this beta. A component travels WITH
# the entity: it is created with it, removed with it when RemoveFromParent
# cascades, and read back off it with the same GetComponent lookup the wave logic
# already uses for health, movement and interaction. There is no second thing to
# keep in sync, so there is no way for it to fall out of sync.
#
# The digest recommends exactly this - "keep logic and data in components" - and
# health_component is the precedent already in this project.
sleep_visual_component<public> := class<final_super>(component):

    # The cow's scale as spawned, before any flattening: the uniform
    # vector3{EnemyScale, EnemyScale, EnemyScale} the spawn loop built.
    #
    # NO DEFAULT VALUE, deliberately. `Entity` on the base component is declared
    # the same way, and for the same reason: a value that must come from the
    # construction site should be impossible to forget rather than silently
    # defaulted to a zero vector, which would flatten a cow out of existence.
    StandingScale<public> : vector3
