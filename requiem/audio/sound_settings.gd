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
## Presence is a second number from 0 to 1: how near its sound is, in any state (1 = on top of
## her, 0 = gone). It lags behind the facts by a random time in this range (shortest,
## longest), so it gives a feeling and never a position.
@export var presence_lag := Vector2(0.5, 2.0)
## And it moves slowly: how long it would take to go all the way from 0 to 1 or back.
@export_range(0.1, 10.0, 0.1, "suffix:s") var presence_time := 1.5
## An unaware entity on top of her makes the world recede this much of what a hunt does
## (0 = not at all, 1 = just as much). The stronger of threat and presence decides.
@export_range(0.0, 1.0, 0.05) var presence_world_share := 0.5

@export_group("Music")
## How long the music takes to change when nothing below says otherwise (menu, prayer, a new zone).
@export_range(0.0, 10.0, 0.05, "suffix:s") var music_fade := 1.4
## It heard something: the music is gone in this long. The silence is part of the warning.
@export_range(0.0, 2.0, 0.01, "suffix:s") var music_fade_heard := 0.1
## The hunt music comes in with the scream, over this long (under the scream's duck).
@export_range(0.0, 5.0, 0.05, "suffix:s") var music_fade_hunt := 0.25
## If a hunt begins and no scream is heard within this long, the hunt music starts anyway.
@export_range(0.1, 5.0, 0.05, "suffix:s") var music_hunt_latest := 0.8
## Level of the hunt music (assets/audio/music/hunt.wav, a loud recording: at 0 it would be
## about 11 dB louder than every other track). Up = the chase is louder.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var music_hunt_db := -8.0
## Level of the rising tone (pitch_riser_01) that starts with the scream.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var music_riser_db := -6.0
## It lost the trail: the hunt music gives way to the thin search tone over this long.
@export_range(0.0, 10.0, 0.05, "suffix:s") var music_fade_search := 2.5
## Level of that thin tone. Low: while it searches there is almost no music.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var music_search_db := -14.0
## It gave up: the exploration drone returns over a random time in this range (shortest, longest).
@export var music_fade_stand_down := Vector2(6.0, 8.0)
## The exploration drone comes and goes by itself, whatever the entity is doing, so that
## music or no music tells the player nothing. Seconds it stays each time (shortest, longest).
@export var music_drone_stay := Vector2(40.0, 90.0)
## Seconds it is away each time (shortest, longest). Its fade out is part of this time.
@export var music_drone_away := Vector2(40.0, 90.0)
## How long the drone takes to come in by itself, and to go. Slow: neither is an event.
@export_range(0.0, 30.0, 0.5, "suffix:s") var music_drone_fade_in := 8.0
@export_range(0.0, 30.0, 0.5, "suffix:s") var music_drone_fade_out := 10.0
## It caught her: the music is gone in this long, under the sounds of the catch.
@export_range(0.0, 5.0, 0.05, "suffix:s") var music_fade_catch := 0.3

@export_group("Death")
## On the game over screen Music, Ambience and World are lowered by this much: silence.
@export_range(-80.0, 0.0, 1.0, "suffix:dB") var death_duck_db := -60.0
## How long they take to fall silent once the screen is up.
@export_range(0.0, 5.0, 0.05, "suffix:s") var death_fade := 1.2
## How long they take to come back when she tries again.
@export_range(0.0, 5.0, 0.05, "suffix:s") var death_release := 1.0

@export_group("Viv: her body and her listening")
## What is added to her two mood breathing loops, in dB (0 or less). Both files are -32 LUFS.
## Calm (it knows nothing) is a breath you find when you listen for it, about -44 LUFS; nervous
## (it has heard something, searches or hunts) is a little more present, about -40 LUFS. Her
## panting has its own level below (viv_pant_db).
@export var viv_breath_db := {"viv/calm": -12.0, "viv/nervous": -8.0}
## Seconds for her breathing to change from one mood to another.
@export_range(0.1, 6.0, 0.1, "suffix:s") var viv_breath_crossfade := 1.5
## Her panting (the viv/panic file, -24 LUFS) says she is physically tired: it plays while she
## sprints with the exertion meter past its warning. What is added to it, in dB (0 or less):
## x at the warning, y just before the forced gasp; in between it follows how tired she is.
## The defaults give about -40 LUFS at the warning and -31 LUFS just before the gasp.
@export var viv_pant_db := Vector2(-16.0, -7.0)
## Seconds for her panting to come in once she is tired (a gentle way in).
@export_range(0.1, 6.0, 0.1, "suffix:s") var viv_pant_in := 2.0
## Seconds for her panting to fade once she stops sprinting (a short tail).
@export_range(0.1, 6.0, 0.1, "suffix:s") var viv_pant_tail := 2.5
## Seconds for her breathing to stop when she holds her breath.
@export_range(0.0, 1.0, 0.01, "suffix:s") var viv_breath_hold_fade := 0.15
## Seconds for it to come back once she breathes again (after the breath out has sounded).
@export_range(0.0, 3.0, 0.05, "suffix:s") var viv_breath_return := 0.8
## Moving costs information: while she walks, the entity's far-off sounds (ring 1) are this
## much quieter.
@export_range(-24.0, 0.0, 0.5, "suffix:dB") var mask_walk_db := -6.0
## And this much quieter while she sprints.
@export_range(-24.0, 0.0, 0.5, "suffix:dB") var mask_sprint_db := -12.0
## Faster than this (u/s) she counts as moving.
@export_range(0.0, 2.0, 0.05, "suffix:u/s") var mask_moving_speed_u := 0.3
## Seconds for a sprint's full masking to set in once she moves.
@export_range(0.0, 2.0, 0.05, "suffix:s") var mask_on_time := 0.3
## Seconds of standing still for a sprint's full masking to lift (a walk's lifts in half).
@export_range(0.1, 5.0, 0.1, "suffix:s") var mask_off_time := 1.0
## The masking sets in over this many units past where ring 1 begins, so there is no step.
@export_range(0.1, 4.0, 0.1, "suffix:u") var mask_blend_u := 1.0
## Holding her breath is listening: Music, Ambience and World are low-passed down to this.
@export_range(500.0, 20000.0, 50.0, "suffix:Hz") var listen_cutoff_hz := 2500.0
## Seconds for the house to go soft when she starts to hold.
@export_range(0.0, 2.0, 0.05, "suffix:s") var listen_in := 0.3
## Seconds for it to return when she lets go early. (A forced gasp snaps it back.)
@export_range(0.0, 2.0, 0.05, "suffix:s") var listen_out := 0.5
## While she listens, ring 1 reaches this many times further.
@export_range(1.0, 2.0, 0.05) var listen_reach_factor := 1.3
## While she listens, this share of the sounds that would be lost on the way still are
## (0.5 = half as many gaps).
@export_range(0.0, 1.0, 0.05) var listen_gap_factor := 0.5
## While she listens, everything the entity sounds comes up by this much.
@export_range(0.0, 6.0, 0.5, "suffix:dB") var listen_entity_db := 2.0

@export_group("Viv: her heart")
## There is one heartbeat (player/heart_audio.gd). How hard it beats is one amount from 0 to 1;
## running out of air, what the entity knows and how near it is each push it up their own
## distance, and the heart follows the highest. Its level at the faintest beat and at the
## hardest (the hardest is also the most it can ever be: the cap).
@export var heart_db := Vector2(-30.0, -3.0)
## Its speed at the faintest beat and at the hardest (1 = as recorded, 1.45 = 45% faster).
@export var heart_pitch := Vector2(0.95, 1.45)
## Below this amount it also fades towards silence, so it never starts with a step.
@export_range(0.01, 0.5, 0.01) var heart_edge := 0.05
## Seconds it would take to go all the way up, from silent to the hardest beat...
@export_range(0.05, 5.0, 0.05, "suffix:s") var heart_rise_time := 0.65
## ...and all the way down. Fast on purpose: the first breath out is the relief.
@export_range(0.05, 5.0, 0.05, "suffix:s") var heart_fall_time := 0.25
## Running out of air: the amount at the first strain, and with no air left (-22 to -3 dB).
@export var heart_strain := Vector2(0.3, 1.0)
## What the entity knows (threat, 0..1): at or below this nothing beats (a pause on its patrol
## is 0.1 and must tell her nothing)...
@export_range(0.0, 1.0, 0.01) var heart_threat_from := 0.3
## ...and from just above it up to a hunt, the amount goes from here to here. A hunt is
## about -13 dB, a search about -18.5, having heard something about -20.
@export var heart_threat := Vector2(0.15, 0.63)
## How near it is by ear (presence, 0..1), whatever it knows: at or below this nothing beats
## (about the edge of "near", ring 2)...
@export_range(0.0, 1.0, 0.01) var heart_presence_from := 0.6
## ...and from just above it up to on top of her, the amount goes from here to here: at most
## about -24 dB, clearly quieter than a search.
@export var heart_presence := Vector2(0.0, 0.22)
## While she prays her heart is audible: the amount at the deepest of the prayer (0.35 is a
## quiet, steady beat of about -20 dB). Anything the entity does that beats harder still wins.
@export_range(0.0, 1.0, 0.01) var heart_prayer := 0.35

@export_group("Viv: prayer")
## Praying is a state of its own (player/prayer_audio.gd). Music, Ambience and World are
## low-passed down to this at the deepest of the prayer. Holding her breath stops at 2500 Hz
## (listen_cutoff_hz): prayer goes further. The entity is never dulled.
@export_range(200.0, 8000.0, 10.0, "suffix:Hz") var prayer_cutoff_hz := 900.0
## Seconds for the house to sink all the way into the prayer once she starts. Slower than
## holding her breath (listen_in): it is a state she settles into, not a reflex.
@export_range(0.1, 10.0, 0.1, "suffix:s") var prayer_in := 2.5
## Seconds for the world to come all the way back once a whole prayer is over (completed or
## let go). A prayer let go early has less to come back from, so it is back sooner.
@export_range(0.1, 10.0, 0.1, "suffix:s") var prayer_return := 3.0
## Seconds for the world to come back when the prayer is cut: death, a new attempt, a teleport.
@export_range(0.0, 2.0, 0.01, "suffix:s") var prayer_cut := 0.2
## Her calm and nervous breathing play slower (and so a little lower) at the deepest of the
## prayer: 1 = as recorded, 0.85 = 15% slower. Their level does not change.
@export_range(0.5, 1.0, 0.01) var viv_breath_prayer_pitch := 0.85
## The prayer tone (any file in assets/audio/house/prayer_tone; empty = silent): what is added
## to it, in dB, at the start of the prayer (x) and at its end (y). It rises with her progress
## and leaves with the world.
@export var prayer_tone_db := Vector2(-18.0, -4.0)
## At an altar that says so (the Hacienda's), she prays aloud: one voice from the set
## viv/prayer_voice, on the sound-effects bus, never dulled. Its level is the set's (set_gain_db). When
## she lets go before the end, the voice is gone in this long; a prayer that is cut (death, a
## new attempt) cuts it at once. The noise that gives her away is the altar's own, not this.
@export_range(0.0, 2.0, 0.01, "suffix:s") var prayer_voice_fade := 0.25

@export_group("House: its own voice")
## No sound of the house may be louder than this (LUFS).
@export_range(-50.0, -10.0, 0.5, "suffix:LUFS") var house_max_lufs := -26.0
## The effects the house can make: the file, how loud the file itself is (LUFS, measured), and
## the caption shown with it. Files dropped in assets/audio/house/effects are added to these.
@export var house_effects: Array[Dictionary] = [
	{"file": "res://assets/audio/horror-jam-kit 2/WAV/Foley/door_knock_01.wav", "lufs": -28.9, "caption": "[Knocking, somewhere in the house]"},
	{"file": "res://assets/audio/horror-jam-kit 2/WAV/Foley/creak_02.wav", "lufs": -17.1, "caption": "[A door creaks]"},
	{"file": "res://assets/audio/horror-jam-kit 2/WAV/Impact/deep_impact_02.wav", "lufs": -14.0, "caption": "[Something falls]"},
	{"file": "res://tutorial/assets/audio/chair_scrape.wav", "lufs": -26.7, "caption": "[A chair drags]"},
]
## The effect used to answer something loud she did. One of house_effects.
@export_file("*.wav", "*.ogg") var house_knock := "res://assets/audio/horror-jam-kit 2/WAV/Foley/door_knock_01.wav"
## How loud the files in assets/audio/house/settle, house/effects and house/knock are made (LUFS).
@export_range(-50.0, -10.0, 0.5, "suffix:LUFS") var house_set_lufs := -26.0
## The caption for an effect that comes from assets/audio/house/effects.
@export var house_effect_caption := "[Something moves, somewhere in the house]"
## The knocks: the house's own signature while it is safe. Its knocks are house_knock (above)
## and every file dropped in assets/audio/house/knock. Of the effects (not the "nothing"),
## this share are knocks; the rest are the other effects. Higher: more knocks and fewer
## creaks, falls and chairs (1 = only knocks); 0 = the knock is just one effect among the
## others, as it was before. How often effects come at all is house_effect_gap.
@export_range(0.0, 1.0, 0.05) var house_knock_share := 0.6
## A knock plays at the loudest the house may be (house_max_lufs). A quiet knock file is turned
## up to get there, but by no more than this, so that its background hiss is not dragged up
## with it. Higher: a quiet file can be brought further up (louder knocks); 0: knocks are only
## ever turned down, like every other house sound.
@export_range(0.0, 12.0, 0.5, "suffix:dB") var house_knock_max_gain_db := 4.0
## The caption for a knock that comes from assets/audio/house/knock.
@export var house_knock_caption := "[Knocking, somewhere in the house]"
## Seconds from one effect to the next (a random time in this span). Never less than about 90.
@export var house_effect_gap := Vector2(90.0, 150.0)
## Once it is safe again, the house waits this long (a random time in this span) before an
## effect, so that it never speaks the moment the danger turns away.
@export var house_gate_settle := Vector2(4.0, 12.0)
## Seconds of quiet after any awareness cue of the entity before the house may sound.
@export_range(0.0, 120.0, 1.0, "suffix:s") var house_after_cue := 20.0
## One roll in this many is "nothing": the ambience thins instead of an effect.
@export_range(1, 20) var house_nothing_one_in := 6
## How far the ambience thins (below wherever the mood of the house already has it), for how
## long, and how long it takes to go and to return.
@export_range(-24.0, 0.0, 0.5, "suffix:dB") var house_nothing_db := -8.0
@export_range(0.5, 15.0, 0.5, "suffix:s") var house_nothing_time := 4.0
@export_range(0.0, 5.0, 0.1, "suffix:s") var house_nothing_fade := 1.2
## Seconds from one settling sound to the next (a random time in this span).
@export var house_settle_gap := Vector2(7.0, 18.0)
## Settling sounds play this far under the loudest the house may be.
@export_range(-30.0, 0.0, 0.5, "suffix:dB") var house_settle_db := -10.0
## A soft start: every house sound rises from this far down, over this long.
@export_range(-60.0, 0.0, 1.0, "suffix:dB") var house_attack_from_db := -24.0
@export_range(0.0, 0.5, 0.01, "suffix:s") var house_attack := 0.06
## The answering knock comes this long after what she did, and not again for this long.
@export_range(0.1, 5.0, 0.1, "suffix:s") var house_answer_delay := 1.1
@export_range(0.0, 120.0, 1.0, "suffix:s") var house_answer_gap := 12.0
## How many times the answer can come closer: if she keeps being loud, each answer comes from
## a little nearer than the last (never from her own room), up to this many steps.
@export_range(0, 10) var house_escalate_steps := 3
## Two loud things answered within this many seconds of each other make the next answer
## closer. Longer than house_answer_gap, or the answer could never come closer.
@export_range(1.0, 300.0, 1.0, "suffix:s") var house_escalate_window := 40.0
## After this many seconds with nothing loud from her, the answer is back where it started:
## the first one after it comes from anywhere, as quiet as any house sound.
@export_range(1.0, 600.0, 1.0, "suffix:s") var house_escalate_reset := 60.0
## The loudest the closest answer may be (LUFS). The limit rises step by step from
## house_max_lufs to this; the knock is only ever turned down to it, never up.
@export_range(-50.0, -10.0, 0.5, "suffix:LUFS") var house_escalate_max_lufs := -22.0
## An answer never comes from nearer than this, even from the next room.
@export_range(0.0, 30.0, 0.5, "suffix:u") var house_answer_min_u := 3.0
## The aftermath: after one of the rare effects, a door in a room she is not in may later be
## found ajar, with a creak she hears (the entity does not). Once per run. Off: never.
## The door is only drawn a little open: it stays shut for bodies, light and the entity.
@export var house_ajar := true
## The chance, after an effect, that a door is left ajar (0..1).
@export_range(0.0, 1.0, 0.05) var house_ajar_chance := 0.5
## Seconds after the effect before the door is found ajar (a random time in this span).
@export var house_ajar_delay := Vector2(8.0, 20.0)
## How far the leaf is drawn open (0 = shut, 1 = fully open).
@export_range(0.0, 1.0, 0.01) var house_ajar_swing := 0.2
## The door left ajar is at least this far from her, with a wall between them.
@export_range(0.0, 60.0, 0.5, "suffix:u") var house_ajar_min_u := 10.0
## The caption shown with its creak.
@export var house_ajar_caption := "[A door opens, somewhere in the house]"
## The creak, when the door has none of its own whose loudness is known (its own creak is
## used when it is this file or one of house_effects), and how loud the file is (LUFS,
## measured with ffmpeg ebur128). It plays turned down to house_max_lufs, like every house sound.
@export_file("*.wav", "*.ogg") var house_ajar_creak := "res://assets/audio/horror-jam-kit 2/WAV/Foley/creak_02.wav"
@export_range(-50.0, 0.0, 0.1, "suffix:LUFS") var house_ajar_creak_lufs := -17.1
## When the room she is in is not known, a house sound is never nearer than this.
@export_range(0.0, 30.0, 0.5, "suffix:u") var house_min_distance_u := 8.0

@export_group("Acoustics: how far its sound travels")
## How many times per second the way from each entity to Viv is measured. Never every frame.
@export_range(1.0, 20.0, 0.5, "suffix:/s") var acoustics_rate := 5.0
## The physics layers of the walls (a bit mask; layer 1 is 1). Doors are on another layer and
## never block sound.
@export_flags_2d_physics var acoustics_wall_mask := 1
## When a wall is in the way, the sound travels this far along the walking path (through the
## doorways) and the rest in a straight line: 0 = walls do nothing, 1 = it only ever travels
## around them.
@export_range(0.0, 1.0, 0.05) var acoustics_path_weight := 0.7
## A wall is in the way and there is no walking path at all: the sound counts as this many
## times further than the straight line.
@export_range(1.0, 6.0, 0.1) var acoustics_no_path_factor := 2.5
## Ring 3, "on top of you": the sound has travelled less than this.
@export_range(0.5, 40.0, 0.5, "suffix:u") var ring_on_top_u := 4.0
## Ring 2, "near" (the same room, or the next doorway): less than this.
@export_range(0.5, 60.0, 0.5, "suffix:u") var ring_near_u := 9.0
## Ring 1, "somewhere" (about a room away): less than this. Beyond it is ring 0, "gone".
@export_range(0.5, 120.0, 0.5, "suffix:u") var ring_somewhere_u := 18.0
## Clarity is 1 (every detail) up to this distance, and falls evenly to 0 where ring 1 ends.
@export_range(0.0, 60.0, 0.5, "suffix:u") var clarity_full_u := 4.0

@export_group("World: things she handles")
## A trunk's latch and lid when she opens it (tutorial/chest.gd): opened normally (x), and
## eased open on a held breath (y). How far it is heard by the entity is the chest's own.
@export var chest_open_db := Vector2(-7.0, -15.0)
## A fresh battery pushed into the flashlight.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var battery_insert_db := -5.0

@export_group("Sound sets")
## Each time a set plays, its pitch moves at random by up to this much either way (0.06 = 0.94 to 1.06).
@export_range(0.0, 0.3, 0.01) var set_pitch_range := 0.06
## Each time a set plays, its level moves at random by up to this much either way.
@export_range(0.0, 6.0, 0.1, "suffix:dB") var set_volume_range_db := 2.0
## What the game adds to a set when it plays, in dB: more than 0 turns it up, less turns it
## down. Sharp clicks and thuds cannot be made loud enough in the file without squashing them
## (assets/audio/SOUND_SETS.md, "Make-up"), so the difference is made up here; a set that is
## too present is turned down here the same way. Any set can be listed.
## The entity's calm breathing (entity/breath_calm) is turned down so it sits well under its
## mumbled phrases instead of covering them; towards 0 it is louder (0 is its file level).
## Its walking claw steps (entity/claws_walk) stay at their file level: with the calm trim
## (position_calm_near_db) a step right beside Viv in a silent house is not a sudden jump. List
## "entity/claws_walk" here with a value below 0 to turn them down.
@export var set_gain_db := {
	"entity/neck_click": 6.0,
	"entity/foot_slam": 5.0,
	"entity/pat_tap": 5.5,
	"entity/cloth_fall": 8.5,
	"entity/catch_grab": 1.5,
	"entity/claws_run": 0.5,
	"entity/breath_calm": -8.0,
	# Sounds that came in with the Hacienda, as recorded (not yet through tools/audio/prepare_sounds.py).
	# The bite that ends a catch (entity/kill): about as loud as the grab before it.
	"entity/kill": -1.0,
	# Viv praying aloud at an altar (viv/prayer_voice): a low voice, well under the entity.
	# Half of what it was (-6 dB): at -6 it was too loud in play.
	"viv/prayer_voice": -12.0,
}

@export_group("Entity: body")
## How many body sounds can overlap before the oldest is cut.
@export_range(2, 16) var entity_voices := 8
## Level change of single animation cues that reuse another cue's set: the grope while it
## scuttles is a softer scrape, the idle tick a much softer tap.
@export var cue_gain_db := {"claw_grope": -4.0, "claw_tick": -8.0}
## Its calm breathing (while it knows nothing) does not play all the time: it breathes for a
## spell of this long (shortest, longest)...
@export var breath_calm_spell := Vector2(6.0, 12.0)
## ...then sinks away and rests this long (shortest, longest), then breathes again. Longer
## rests: it breathes less often. (0, 0) = it never rests: it breathes all the time, as before.
@export var breath_calm_rest := Vector2(10.0, 22.0)
## How slowly it sinks away into a rest and comes back from one. Slow on purpose, so its return
## is never a sudden rise. Its loop keeps running underneath, so each spell starts at a
## different point of the take.
@export_range(0.1, 6.0, 0.1, "suffix:s") var breath_calm_fade := 2.0
## On: while Viv holds her breath to listen, a rest ends (over breath_calm_fade) and it keeps
## breathing at least as long as she holds, so listening always finds it. Off: its rests ignore
## her. (It breathes without rests anyway before it is shown and once it has heard something.)
@export var breath_found_by_listening := true
## How long its breath and drag loops take to fade in or out.
@export_range(0.0, 2.0, 0.01, "suffix:s") var loop_fade := 0.2
## Above this speed it counts as moving, and its shroud drags.
@export_range(0.0, 2.0, 0.005, "suffix:u/s") var moving_speed_u := 0.125

@export_group("Entity: where it is (Channel B)")
## Its breathing, talking, claws, drag and sniffing are the sounds that say where it is. They
## follow the way its sound really travels (Acoustics), not the straight line. They play at
## full level while that way is shorter than this...
@export_range(0.0, 20.0, 0.25, "suffix:u") var position_full_u := 2.0
## ...and get quieter from there on, down to this at the far edge of ring 1 ("somewhere")...
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var position_edge_db := -18.0
## ...along this curve (1 = evenly; higher = they stay loud longer and drop late; lower = most
## of the drop comes early).
@export_range(0.3, 3.0, 0.05) var position_falloff := 1.0
## Over the last stretch before ring 1 ends they fade to nothing, so nothing pops in or out.
@export_range(0.0, 8.0, 0.25, "suffix:u") var position_fade_u := 2.0
## While it knows nothing (unaware, or standing still on its patrol), its position sounds right
## beside her are held down by this much, so a tap in a silent house is near, not a jump. The
## difference shrinks with distance and is gone where ring 2 ends (ring_near_u); a room away
## nothing changes. While she holds her breath to listen that edge moves out with ring 1
## (listen_reach_factor), as the rest of the distance curve does, so nearer is never quieter.
## Once it has heard something its sounds are at their full level. 0 = off; no lower than
## about -7.5, or nearer would be quieter than further.
## The default is the smallest that keeps every calm sound beside her under the jump-scare
## audit's threshold, also while she holds her breath (testing/regression/test_calm_beside_her).
@export_range(-7.5, 0.0, 0.5, "suffix:dB") var position_calm_near_db := -6.5
## How long that holding down takes to come and to go when it stops or starts being calm.
@export_range(0.0, 5.0, 0.05, "suffix:s") var position_calm_fade := 1.0
## The way is measured 5 times per second; in between, what is heard glides over this long.
@export_range(0.0, 2.0, 0.01, "suffix:s") var position_smooth := 0.25
## Blur: below this clarity a single sound (a step, a tap, a phrase) plays on the far,
## dulled bus instead of the near one. Its loops crossfade between the two all the way.
@export_range(0.0, 1.0, 0.01) var far_below_clarity := 0.5
## Direction: in rings 3 and 2 its sounds are placed exactly. Across ring 1 the placing
## weakens down to this at the far edge (1 = exact, 0 = dead centre). Vague, never wrong.
@export_range(0.0, 1.0, 0.01) var far_panning := 0.35
## Direction behind a wall: on, its position sounds (breath, steps, talking) come from the
## doorway the sound really travels through, not straight through the wall. Off: from where
## it stands (only weakened with distance, as above). What it knows is never moved.
@export var doorway_panning := true
## A point of the walking path nearer to Viv than this gives no direction (she is standing on
## it), so the doorway is looked for further along.
@export_range(0.0, 4.0, 0.05, "suffix:u") var doorway_min_u := 0.75
## Small changes of where it comes from (Viv or the entity moving) glide over about this long.
@export_range(0.01, 2.0, 0.01, "suffix:s") var doorway_glide := 0.25
## Where it comes from moves more than this in one go (another doorway, or it stepped into
## view): no sweep across the wall. It jumps there at once and the placing goes vague, then
## comes back.
@export_range(0.1, 20.0, 0.1, "suffix:u") var doorway_switch_u := 2.0
## After such a jump, the placing comes back from dead centre to its full amount over this long.
@export_range(0.01, 3.0, 0.01, "suffix:s") var doorway_settle := 0.5
## Gaps: in ring 1 each body sound (a step, a tap, a scrape) only plays with a chance between
## these two: the first at the far edge, the second where ring 1 begins. Nearer, all play.
@export var gap_chance_body := Vector2(0.3, 0.7)
## The same for its voice (talking, sniffing): it gets through more often than its body.
@export var gap_chance_voice := Vector2(0.65, 0.95)

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

@export_group("Entity: knocking")
## The switch. On: when it stands still on its patrol next to a door, it now and then knocks on
## it, from where it stands. Off: it never knocks. Its knocks are the files in
## assets/audio/entity/knock/ (never the house's knock); while that folder is empty it never
## knocks, switch or not. A knock is only a sound: the entity does not hear it and nothing
## changes in what it does.
@export var entity_knocks_enabled := false
## The least time between two knocks.
@export_range(1.0, 600.0, 1.0, "suffix:s") var entity_knock_gap := 120.0
## It does not knock until it has been calm this long (unaware, on its patrol): never in the
## first moments of an encounter, nor just after it heard something or gave up a search.
@export_range(0.0, 300.0, 1.0, "suffix:s") var entity_knock_first := 30.0
## It has to have stood still this long (a real pause, not just turning) before it knocks.
@export_range(0.0, 3.0, 0.05, "suffix:s") var entity_knock_still := 0.4
## How near the middle of a doorway it has to stand to knock on that door.
@export_range(0.25, 10.0, 0.25, "suffix:u") var entity_knock_door_u := 1.5
## How loud a knock is, against its file (on top of anything set_gain_db lists for the set).
## It then loses what any sound of where it is loses on the way to Viv.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var entity_knock_db := -6.0

@export_group("Checks: the jump-scare audit")
## The audit (testing/tools/jump_scare_audit.gd, development only) logs every rise on Master of
## more than this many dB...
@export_range(3.0, 40.0, 0.5, "suffix:dB") var audit_jump_db := 18.0
## ...within this long.
@export_range(0.02, 1.0, 0.01, "suffix:s") var audit_jump_window := 0.1
## Quieter than this (peak on Master) counts as this, so a rise out of silence is measured
## from here. A rise of 18 dB from -26 dB ends near -8 dB peak, about where a sound of
## -16 LUFS sits: quieter things appearing in a quiet house are not jump scares.
@export_range(-80.0, 0.0, 1.0, "suffix:dB") var audit_floor_db := -26.0
## A rise this soon after the scream starts is the scream: counted, not logged.
@export_range(0.0, 5.0, 0.1, "suffix:s") var audit_scream_time := 1.4
## A rise this soon after a noise she made or a key she pressed is her own action.
@export_range(0.0, 1.0, 0.05, "suffix:s") var audit_own_action := 0.3
## Until this long after the heard-you cue a rise is that cue itself; from then on it was
## warned of (the contract's 0.7 s)...
@export_range(0.0, 5.0, 0.05, "suffix:s") var audit_warning := 0.7
## ...while the encounter is on, or ended no longer ago than this (the stand-down's own sound).
@export_range(0.0, 10.0, 0.5, "suffix:s") var audit_aftermath := 3.0
