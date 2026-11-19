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

@export_group("Sound sets")
## Each time a set plays, its pitch moves at random by up to this much either way (0.06 = 0.94 to 1.06).
@export_range(0.0, 0.3, 0.01) var set_pitch_range := 0.06
## Each time a set plays, its level moves at random by up to this much either way.
@export_range(0.0, 6.0, 0.1, "suffix:dB") var set_volume_range_db := 2.0
## What the game adds to a set when it plays, in dB. Sharp clicks and thuds cannot be made
## loud enough in the file without squashing them (assets/audio/SOUND_SETS.md, "Make-up"), so
## the difference is made up here. Any set can be listed to turn it up or down.
@export var set_gain_db := {
	"entity/neck_click": 6.0,
	"entity/foot_slam": 5.0,
	"entity/pat_tap": 5.5,
	"entity/cloth_fall": 8.5,
	"entity/catch_grab": 1.5,
	"entity/claws_run": 0.5,
}

@export_group("Entity: body")
## How many body sounds can overlap before the oldest is cut.
@export_range(2, 16) var entity_voices := 8
## Level change of single animation cues that reuse another cue's set: the grope while it
## scuttles is a softer scrape, the idle tick a much softer tap.
@export var cue_gain_db := {"claw_grope": -4.0, "claw_tick": -8.0}
## Distance at which its sounds have faded to nothing. For now the engine's own default
## (2000 px), as before; Phase 2 replaces it with distances along the way sound really travels.
@export_range(4.0, 120.0, 0.5, "suffix:u") var entity_reach_u := 62.5
## How fast they fade on the way there (1 = evenly, higher = most of the drop comes early).
@export_range(0.5, 4.0, 0.1) var entity_falloff := 1.0
## How long its breath and drag loops take to fade in or out.
@export_range(0.0, 2.0, 0.01, "suffix:s") var loop_fade := 0.2
## Above this speed it counts as moving, and its shroud drags.
@export_range(0.0, 2.0, 0.005, "suffix:u/s") var moving_speed_u := 0.125
