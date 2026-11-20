extends RefCounted
## The beta showcase rules (branch showcase/night-one-test): night one tuned for people who have
## never played a game, in about 15 minutes. Every number the booth build changes lives here.
##
## The tutorial turns these on when `enabled` is true and it is not running as a regression test
## (tutorial.gd `showcase`); a test that wants them sets the tutorial's `force_showcase`. With
## `enabled` false the game is the beta, unchanged.
##
## What changes, and why (the design notes are in docs/SHOWCASE_NIGHT_ONE.md):
## - the first catch is a near miss, not a death; only a second catch soon after kills her,
## - after a hunt, a near miss or a note she reads, the creature walks away and rests,
## - the Hacienda asks for three altars, not seven (Tía Rosa prayed at the other four),
## - the offerings lie in fixed rooms, one line says what to do next, and petals lead there,
## - her own sounds ripple on the floor, her air shows around her, the first gasp is soft,
## - the text is in Spanish and the prayer is wordless (no recorded Spanish prayer yet).

## Master switch for the booth rules.
static var enabled := true

# --- Being caught -------------------------------------------------------------------------
## A catch this many seconds after the last near miss is a death; any later catch is another near miss.
const NEAR_MISS_WINDOW := 60.0
## How far (px) she is shoved away from it when she tears loose.
const NEAR_MISS_SHOVE := 34.0
## Seconds it hears nothing at all after letting go of her.
const NEAR_MISS_DEAF := 6.0

# --- Breathing room (the creature backs off) ---------------------------------------------
## Seconds it walks away and rests after a near miss.
const REST_AFTER_NEAR_MISS := 30.0
## Seconds it rests after a hunt ends in nothing (it gave up the search).
const REST_AFTER_HUNT := 30.0
## Seconds of calm while she reads a note (only if it is not already hunting).
const REST_FOR_NOTE := 12.0
## Multiplier on what it hears while it rests: it is still there, just far less sharp.
const REST_HEARING := 0.5

# --- Altars -------------------------------------------------------------------------------
## The altars she prays at in night one, in order. The other four were Tía Rosa's.
const ALTARS := ["altar_1", "altar_4", "altar_7"]
## Seconds of prayer per altar (beta: 12).
const PRAY_DURATION := 7.0
## Seconds of prayer lost per second she is away from it (beta: all of it at once).
const PRAYER_DRAIN := 0.5

# --- Where things are (fixed, not shuffled) -----------------------------------------------
## Offering id -> [room as the notes name it, position on its floor]. Spots from mansion_story.gd.
const OFFERING_SPOTS := {
	"fountain_marigold": ["the music room east of the courtyard", Vector2(2000, 950)],
	"chapel_rosary": ["the library east of the chapel", Vector2(1552, 272)],
	"tapanco_thread": ["the picture gallery north of the stairs", Vector2(2096, 960)],
}
## Notes that stay in night one (the rest belong to altars Rosa already lit).
const NOTES := ["fountain_dedication", "chapel_note", "tapanco_note", "ancestors_letter"]

# --- Breath and stones --------------------------------------------------------------------
## Forced gasps (from running out of air) that only make a soft sound, per life.
const SOFT_GASPS := 1
## Radius (u) of a soft gasp (beta forced gasp: 7 u).
const SOFT_GASP_RADIUS_U := 2.0
## Stones she has when she reaches the Hacienda.
const ARRIVAL_STONES := 3

# --- Language -----------------------------------------------------------------------------
## Locale for the booth. Toggle with F9 in game.
const LOCALE := "es"
