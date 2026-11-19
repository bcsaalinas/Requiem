class_name AudioBus
extends RefCounted
## Names of the audio buses (default_bus_layout.tres). Every bus plays into Master.
##
## A class with constants, like Units: usable from any script, tool scripts included, with
## nothing to register.

const MASTER := &"Master"
const MUSIC := &"Music"
const AMBIENCE := &"Ambience"
## The house: doors, knocks, things that fall, the tutorial's story sounds.
const WORLD := &"World"
## Viv herself: breath, footsteps, heartbeat.
const BODY := &"Body"
const UI := &"UI"
## The entity, near and clear.
const ENTITY := &"Entity"
## The entity as it sounds through the walls.
const ENTITY_FAR := &"EntityFar"
## Anything not sorted into the buses above yet.
const SFX := &"SFX"

## Layout order, after Master.
const ALL: Array[StringName] = [MUSIC, AMBIENCE, WORLD, BODY, UI, ENTITY, ENTITY_FAR, SFX]
## The player's "SFX" volume slider is the volume of all of these.
const SFX_FAMILY: Array[StringName] = [SFX, WORLD, BODY, ENTITY, ENTITY_FAR]
## The only buses that may ever be muffled. Never the entity, never Viv's body.
const MUFFLEABLE: Array[StringName] = [MUSIC, AMBIENCE, WORLD]
## Buses whose level the mix may move (ducks and focus). Master and UI are left alone.
const MIXABLE: Array[StringName] = [MUSIC, AMBIENCE, WORLD, BODY, ENTITY, ENTITY_FAR]
