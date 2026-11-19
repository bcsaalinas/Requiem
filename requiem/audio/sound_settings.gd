class_name SoundSettings
extends Resource
## Every number of the sound system, in one place.
##
## Open audio/sound_settings.tres in the Inspector to tune: each value shows its comment as
## a tooltip, and what you change is saved in that file. The values written here are the
## defaults a value falls back to when it is reset.
##
## The bus effects (limiter, reverbs, the far low-pass) are listed in default_bus_layout.tres so
## they show in the Audio panel, but their numbers are set from here when the game starts.
##
## Distances are in units (1 u = 32 px), times in seconds, levels in dB.

const PATH := "res://audio/sound_settings.tres"

static var _current: SoundSettings


## The settings the game runs on (audio/sound_settings.tres, loaded once).
static func current() -> SoundSettings:
	if _current == null:
		_current = load(PATH) as SoundSettings if ResourceLoader.exists(PATH) else null
		if _current == null:
			_current = SoundSettings.new()
	return _current


@export_group("Mix: buses")
## Ceiling of the limiter on Master. Nothing leaves the game louder than this.
@export_range(-12.0, 0.0, 0.1, "suffix:dB") var limiter_ceiling_db := -1.0
## Cutoff a muffled bus rests at when nothing muffles it: fully open.
@export_range(1000.0, 20500.0, 10.0, "suffix:Hz") var open_hz := 20500.0
## Entity bus reverb: size of the room it suggests (0 = closet, 1 = hall). The house is small.
@export_range(0.0, 1.0, 0.01) var entity_reverb_room := 0.3
## Entity bus reverb: how fast the highs die in it (1 = dull, soft walls).
@export_range(0.0, 1.0, 0.01) var entity_reverb_damping := 0.6
## Entity bus reverb: how much of it is mixed in. Small: the entity stays clear.
@export_range(0.0, 1.0, 0.01) var entity_reverb_wet := 0.1
## EntityFar bus: everything above this is cut, the "through the walls" sound.
@export_range(200.0, 8000.0, 10.0, "suffix:Hz") var far_cutoff_hz := 1200.0
## EntityFar bus reverb: size of the room. A little more than the Entity bus.
@export_range(0.0, 1.0, 0.01) var far_reverb_room := 0.45
## EntityFar bus reverb: how fast the highs die in it.
@export_range(0.0, 1.0, 0.01) var far_reverb_damping := 0.7
## EntityFar bus reverb: how much of it is mixed in.
@export_range(0.0, 1.0, 0.01) var far_reverb_wet := 0.2
## Both reverbs: the gap before the first reflection. Short: the walls are close.
@export_range(0.0, 100.0, 1.0, "suffix:ms") var reverb_predelay_ms := 12.0
## Both reverbs: how wide the reflections are spread between left and right.
@export_range(0.0, 1.0, 0.01) var reverb_spread := 0.6
## Both reverbs: how much low end is kept out of the reflections, so they never boom.
@export_range(0.0, 1.0, 0.01) var reverb_hipass := 0.2

## A duck or muffle whose owner left the scene without ending it lets go over this long.
@export_range(0.0, 2.0, 0.01, "suffix:s") var orphan_fade := 0.3

@export_group("Mix: holding breath")
## How far the music drops while Viv holds her breath.
@export_range(-24.0, 0.0, 0.5, "suffix:dB") var breath_duck_db := -5.0
## How long that drop, and the return from it, take.
@export_range(0.0, 2.0, 0.01, "suffix:s") var breath_duck_fade := 0.18
## Cutoff of Music and Ambience with no air left. It slides here from open_hz as the air runs out.
@export_range(200.0, 8000.0, 10.0, "suffix:Hz") var strain_shut_hz := 700.0
