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

@export_group("Threat: the mood of the house")
## Threat is one number from 0 to 1 that the mix follows. It only says what the entity knows,
## never how near it is. This is its value while the entity walks its patrol, unaware...
@export_range(0.0, 1.0, 0.01) var threat_unaware := 0.0
## ...while it stands still on its patrol (it may be about to hear something)...
@export_range(0.0, 1.0, 0.01) var threat_paused := 0.1
## ...once it has heard something and stands listening...
@export_range(0.0, 1.0, 0.01) var threat_heard := 0.6
## ...while it searches...
@export_range(0.0, 1.0, 0.01) var threat_searching := 0.7
## ...and while it hunts (and while it catches her).
@export_range(0.0, 1.0, 0.01) var threat_hunting := 1.0
## Threat rises quickly: how long it would take to climb all the way from 0 to 1.
@export_range(0.05, 5.0, 0.05, "suffix:s") var threat_rise_time := 0.5
## And falls slowly: how long it would take to sink all the way from 1 to 0. After a search
## (0.7) the house is back in about 7 s, the same time the music takes.
@export_range(0.5, 60.0, 0.5, "suffix:s") var threat_fall_time := 10.0
## A mood lags behind the facts: threat waits a random time in this range before it starts to
## follow a change (shortest, longest).
@export var threat_lag := Vector2(0.15, 0.5)
## At full threat Ambience and World are this much lower; in between, in proportion.
@export_range(-30.0, 0.0, 0.5, "suffix:dB") var threat_world_db := -10.0
## At full threat Viv's own body is this much louder, so she hears herself.
@export_range(0.0, 9.0, 0.5, "suffix:dB") var threat_body_db := 3.0

@export_group("Music")
## How long the music takes to change when nothing below says otherwise (menu, prayer, a new zone).
@export_range(0.0, 10.0, 0.05, "suffix:s") var music_fade := 1.4
## It heard something: the music is gone in this long. The silence is part of the warning.
@export_range(0.0, 2.0, 0.01, "suffix:s") var music_fade_heard := 0.1
## The hunt music comes in with the scream, over this long (under the scream's duck).
@export_range(0.0, 5.0, 0.05, "suffix:s") var music_fade_hunt := 0.25
## If a hunt begins and no scream is heard within this long, the hunt music starts anyway.
@export_range(0.1, 5.0, 0.05, "suffix:s") var music_hunt_latest := 0.8
## Level of the rising tone (pitch_riser_01) that starts with the scream.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var music_riser_db := -6.0
## It lost the trail: the hunt music gives way to the thin search tone over this long.
@export_range(0.0, 10.0, 0.05, "suffix:s") var music_fade_search := 2.5
## Level of that thin tone. Low: while it searches there is almost no music.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var music_search_db := -14.0
## It gave up: the exploration drone returns over a random time in this range (shortest, longest).
@export var music_fade_stand_down := Vector2(6.0, 8.0)
## It caught her: the music is gone in this long, under the sounds of the catch.
@export_range(0.0, 5.0, 0.05, "suffix:s") var music_fade_catch := 0.3

@export_group("Death")
## On the game over screen Music, Ambience and World are lowered by this much: silence.
@export_range(-80.0, 0.0, 1.0, "suffix:dB") var death_duck_db := -60.0
## How long they take to fall silent once the screen is up.
@export_range(0.0, 5.0, 0.05, "suffix:s") var death_fade := 1.2
## How long they take to come back when she tries again.
@export_range(0.0, 5.0, 0.05, "suffix:s") var death_release := 1.0

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

@export_group("Entity: what it knows (Channel A)")
## The heard-you cue plays at full level out to this distance. It must cover every place a
## detection can come from: the largest noise Viv can make (8 u: a thrown object, the prayer
## pulse) x its sharpest hearing (1.6) x 1.25 = 16 u. The fairness test fails if this is less.
@export_range(4.0, 60.0, 0.5, "suffix:u") var heard_full_u := 16.0
## Beyond that distance the heard-you cue drops by this much per unit...
@export_range(0.0, 3.0, 0.05, "suffix:dB/u") var heard_fall_db_per_u := 0.5
## ...but never below this: it never falls silent, wherever Viv stands.
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var heard_floor_db := -12.0
## What the voice of the heard-you cue gets on top of its file level, so it stands over any idle talking.
@export_range(-6.0, 12.0, 0.5, "suffix:dB") var heard_voice_gain_db := 2.0
## How long the cue waits for the animation's head snap before it plays without it.
@export_range(0.05, 1.0, 0.01, "suffix:s") var heard_click_wait := 0.25
## The scream (with its inhale and stomp) plays at full level out to this distance...
@export_range(1.0, 60.0, 0.5, "suffix:u") var scream_full_u := 6.0
## ...then drops by this much per unit...
@export_range(0.0, 3.0, 0.05, "suffix:dB/u") var scream_fall_db_per_u := 0.4
## ...and never below this: it reaches the whole house.
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var scream_floor_db := -14.0
## What the scream gets on top of its file level.
@export_range(-6.0, 12.0, 0.5, "suffix:dB") var scream_gain_db := 3.0
## A scream this soon after the last one...
@export_range(0.0, 120.0, 1.0, "suffix:s") var scream_repeat_window := 20.0
## ...plays this much quieter, so a second scream does not wear the first one out.
@export_range(-12.0, 0.0, 0.5, "suffix:dB") var scream_repeat_db := -4.0
## How far Music, Ambience and World drop under the scream, from its inhale on.
@export_range(-30.0, 0.0, 0.5, "suffix:dB") var scream_duck_db := -14.0
## How fast they drop.
@export_range(0.0, 1.0, 0.01, "suffix:s") var scream_duck_attack := 0.1
## How slowly they come back once it launches into the hunt.
@export_range(0.0, 6.0, 0.05, "suffix:s") var scream_duck_release := 1.5
## The duck lets go after this long even if the launch never comes (it was caught mid-scream).
@export_range(0.5, 6.0, 0.05, "suffix:s") var scream_duck_longest := 2.5
## How long a hunt start waits for the animation's inhale and scream before it plays them itself.
@export_range(0.05, 1.0, 0.01, "suffix:s") var scream_cue_wait := 0.25
## "It lost you" and "it gave up" play at full level out to this distance...
@export_range(1.0, 60.0, 0.5, "suffix:u") var far_full_u := 12.0
## ...then drop by this much per unit...
@export_range(0.0, 3.0, 0.05, "suffix:dB/u") var far_fall_db_per_u := 0.5
## ...and never below this.
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var far_floor_db := -15.0
## After "it lost you" starts, the one sniff follows this much later.
@export_range(0.0, 6.0, 0.05, "suffix:s") var lost_then_sniff := 2.4
## "It gave up" is an exhale. An exhale the animation asks for within this long of it is the
## same breath, and is not played a second time.
@export_range(0.0, 6.0, 0.05, "suffix:s") var stand_down_covers_exhale := 2.0
## When "it gave up" starts, a "lost you" groan still sounding fades out over this long.
@export_range(0.0, 2.0, 0.01, "suffix:s") var awareness_fade := 0.3
## A cue more than this far under its full level counts as too quiet to hear. No awareness
## cue may ever play below it (fairness test).
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var audible_db := -20.0

@export_group("Entity: idle voice")
## On patrol it mumbles one phrase every so often: the shortest and longest wait between two.
@export var talk_interval_patrol := Vector2(6.0, 15.0)
## While it searches it speaks less: the shortest and longest wait between two phrases.
@export var talk_interval_search := Vector2(10.0, 20.0)
## While it searches its voice is lower and slower: the pitch it speaks at (1 = as on patrol).
@export_range(0.5, 1.0, 0.01) var talk_pitch_search := 0.9
## The least silence between the end of one phrase and the start of the next.
@export_range(0.0, 10.0, 0.1, "suffix:s") var talk_min_gap := 2.0
## When it pauses on patrol, a phrase it was saying trails off over this long (breathing goes on).
@export_range(0.0, 2.0, 0.01, "suffix:s") var talk_pause_fade := 0.4
## It has to have stood still this long before the phrase trails off.
@export_range(0.0, 1.0, 0.01, "suffix:s") var talk_pause_grace := 0.25
## After it gives up a search, its idle talking resumes this long after the breath out starts.
@export var talk_after_stand_down := Vector2(4.0, 7.0)
## While it searches and scuttles it sniffs in short runs: how many sniffs in a run.
@export var sniff_run_count := Vector2i(2, 4)
## Time from one sniff of a run to the next. Picked once per run, so each run has a steady pace.
@export var sniff_run_pace := Vector2(0.34, 0.42)
## The first run comes this long after the single sniff that follows "it lost you".
@export var sniff_run_first := Vector2(1.0, 1.8)
## The wait between two runs after that.
@export var sniff_run_interval := Vector2(3.0, 6.0)
