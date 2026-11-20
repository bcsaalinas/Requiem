# Beta checkpoint

`beta` is the team's shared checkpoint: one playable build from the main menu, through the
organic tutorial, into the Hacienda. It starts from `audio/sound-system` (the sound system,
with its latest follow-ups) and takes in `chest-and-prayer-audio`, which already contained
`map-and-dessign` and `new-sounds`. Every branch it was made from is still there, untouched.

This page says what is in it, what was checked, and what still looks or sounds odd.

## The route

1. **Main menu → bedroom → hallway → forest.** As before.
2. **End of the forest trail.** Walking on past the last petals is enough: the forest hands over
   to the old house without a key press. (The door prompt still works.)
3. **The old house.** The porch, the side window and the latch are kept. Once she stands in a
   room of the house, the porch and the forest outside are black; step back onto the porch and
   they return.
4. **Trapped, then the front door.** After the entity's arrival the front door leads to the
   impossible hallway, as before.
5. **The last door of the hallway.** It no longer ends the game: it takes her into the Hacienda,
   ground floor, at its entrance, with everything she carries (flashlight and its charge, spare
   batteries, stones). Arriving is a checkpoint.
6. **The Hacienda.** Two floors joined by the stairs (walk onto them). The entity patrols the
   floor she is on; it waits a few seconds after she arrives. Seven altars; the main gate stays
   sealed until all seven are prayed at, then the old ending plays there.
7. **Caught.** Game over, and Retry puts her back at the last checkpoint (arrival, or the last
   altar prayed) with the altar count kept.

## What was integrated

**The Hacienda map**: both floors, their props, altars, trunks, pickups, the gate, the stairs.
All its prompts and altar names are in English now (they were Spanish).

**The player UI**
- The arcs around Viv while she holds her breath. They turn amber and red at the same lung and
  exertion levels the rest of the game uses (they had their own numbers).
- The three meters (breath, exertion, battery). Their warning marks read the game's own
  thresholds live: the "tired" mark is where panting starts, the low-battery mark is the
  flashlight's own.
- The inventory slots (flashlight, spare cells, stones) and the altar counter ("ALTARS PRAYED").
- The minimap: it follows her on every area and on both floors of the Hacienda, and changes
  floor with her.

**The new sounds, each played once, by our sound system**

| Sound | File | When | Level setting (`audio/sound_settings.gd`) |
|---|---|---|---|
| Chase music | `assets/audio/music/hunt.wav` | while it hunts her (starts with the scream) | `music_hunt_db` (−8 dB) |
| Kill | `assets/audio/entity/kill/devour.wav` | once per catch, as she disappears | `set_gain_db` `"entity/kill"` (−1 dB) |
| Viv prays aloud | `assets/audio/viv/prayer_voice/prayer_female.mp3` | while she holds the prayer at a Hacienda altar; fades when she lets go | `set_gain_db` `"viv/prayer_voice"` (−6 dB), `prayer_voice_fade` |
| Battery | `tutorial/assets/audio/battery_insert.wav` | a spare battery goes in (B) | `battery_insert_db` (−5 dB) |
| Trunk | `tutorial/assets/audio/chest_latch_and_lid.wav` | a trunk opens | `chest_open_db` (−7 dB, −15 dB on a held breath) |

Praying aloud gives her away through the game's own noise system: the altar tells the entity
every half second (6 u around her, 8 u for a moment two seconds in). If it is that near, it
stops to listen and then comes. The voice itself is only sound; the entity hears the prayer,
not the file.

**Other sounds that came in and are not played yet**

| File | What it is | How to use it |
|---|---|---|
| `assets/audio/monster/hunt_scream.wav`, `investigate.wav`, `search_growl.wav`, `catch.wav` | entity cues from the other branch | our entity has its own sets for these; drop a file into the matching set folder to add it as a variation |
| `tutorial/assets/audio/chest_lid.mp3`, `chest_open.mp3` | other trunk takes | point the trunk's `creak` at one of them |
| `tutorial/assets/audio/prayer_ritual.mp3` | a second prayer voice | put it in `assets/audio/viv/prayer_voice/` and it alternates with the first |
| `tutorial/assets/audio/stone_throw.wav` | a throw whoosh | list it in the thrower's `piedra_release_clips` |
| `tutorial/assets/audio/pickup_hand_1..4.wav` | picking things up | no hook yet |
| `assets/audio/horror-jam-kit 2/WAV/Body/breath_texture_01.wav` | panting | belongs to the effects script below; Viv's own breathing covers it |

**From `audio/sound-system`, after the first merge**: the entity's calm breathing is quieter
and comes and goes (it was a steady rattle); everything it does while calm is softer right
beside her. The house knocks more: while the entity is far and calm, most of the house's rare
sounds are now a knock, at the loudest a house sound may be, and any file dropped in
`assets/audio/house/knock/` becomes one of its knocks. The house's own voice (creaks, knocks,
the answer to a loud noise) now also speaks in the Hacienda, from the places of the entity's
patrol, only while it is far and calm.

## Cleaned up on the way

- **One prompt per altar.** The altar drew its own floating prompt on top of the HUD's. It now
  only marks a prayed altar ("Prayed"); the HUD shows "E · Pray at … (hold)".
- **One prayer voice.** The altar played the prayer itself, on its own player, outside the
  mix. That player is gone; her prayer audio plays it.
- **`player/player_juice.gd` is in the repo but not attached to Viv.** It made its own noises
  the entity could hear (panting, a rejected flashlight click), played its own panting over
  hers, shook the camera and dimmed the lights on its own numbers. That is a second copy of
  mechanics the game already has. Its looks-only parts (dust, motes, vignette) are worth
  bringing back one at a time.
- **The other branch's own entity audio and its test** were not taken: the entity has one audio
  system.
- **Camera zoom and ambient light changes** from the other branch were not taken (they changed
  every area, not only the Hacienda).
- **The throw sound hook** uses the game's no-repeat pick and the World bus.
- **Small HUD texts** under the 20 px floor were raised to it.

## What was checked

**Automated checks** (from `requiem/`: `python3 testing/run_checks.py`), on the merged branch:

| Suite | Result | Suite | Result |
|---|---|---|---|
| Menu flow | 34/34 | Audio mix | 56/56 |
| Kiosk | 348/349 ¹ | Entity audio | 61/61 |
| Tutorial (with the Hacienda route) | 154/154 | Awareness | 76/76 ² |
| Doors and rooms | 23/23 | Idle voice | 34/34 |
| Breath events | 36/36 | Threat | 64/64 |
| Breath feedback | 49/49 | Acoustics | 48/48 |
| Throw feedback | 70/70 | Rings | 82/82 |
| Prayer feedback | 73/73 | Body audio | 100/100 |
| Sprint feedback | 62/63 ¹ | House voice | 118/118 |
| Footstep audio | 83/83 | Sparse music | 34/34 |
| Player action | 56/56 | Jump-scare audit | 68/68 |
| Player motion | 133/133 | Heart | 34/34 |
| Player pose | 24/24 | Prayer audio | 48/48 |
| Phantom camera | 166/170 ¹ | Entity knock | 57/57 |
| Level | 11/11 | Calm beside her | 25/25 |
| Test Lab | 120/121 ¹ | Minimap | 16/16 |

¹ The same checks fail on `audio/sound-system` before the merge (Kiosk "The last shot brings
out the entity", a Sprint feedback script error, four Phantom camera checks, Test Lab "Real
high-exertion holding shows strain"). Nothing new fails.

² 75/76 inside the full run ("one scrape, then silence"), 76/76 run alone: a timing flake that
suite already had.

The runner prints FAIL for a suite even at 34/34 when the engine reports leftovers at exit:
read the counts.

**A scripted play of the real game** (not test mode), from the main menu, 29 steps, all passed:
the menu's Play button; the bedroom; walking east past the end of the trail with the key held;
the porch in view, then black from inside; E on the hallway's last door, twice, into the
Hacienda with her gear, the altar counter and the minimap up, a checkpoint; sprinting moves the
exertion meter; holding her breath drains the lungs and shows the arcs; B puts a battery in with
its sound; a battery picked up; a trunk opened with its sound; walking onto the stairs, the
minimap changing floor, and back; a whole 12-second prayer aloud with one voice, "1 / 7", a
checkpoint; a second prayer with the entity beside her: it listens, hunts, the chase music
starts, it catches her, the grab and then the kill sound once, the game over screen; Retry back
in the Hacienda at "1 / 7" with her gear.

**What that play is not.** It was driven by a script that presses the keys and jumps the long
walks, and it ran with the sound card off. It proves the route, the HUD, the minimap, the retry
and that each sound plays once at its level. It does not prove how any of it feels or sounds:
nobody has listened to this build yet.

## What still looks or sounds odd

Sound
- **The chase music** is a 4.8-second loop, recorded about 11 dB louder than the track it
  replaced (−9.6 against −20.9 LUFS). It is held at −8 dB; in a long chase it will be heard as
  a loop.
- **The spoken prayer** is an mp3 straight from the source, with peaks at full scale, and has
  not been through `tools/audio/prepare_sounds.py`; neither have the other four new files. It is
  a whispered Ave Maria in Swedish. The tutorial's and the Test Lab's altars stay wordless.
- **The trunk's latch replaced our creak, the battery sound replaced the switch click.** Both
  were judged by level only.
- **The kill sound** follows the grab by about 0.7 s; they have not been heard together by a
  person.
- **The house's knocks are still quiet**: at their limit they peak only a few dB above the
  ambience. `house_max_lufs` makes every house sound louder; closer, drier knock recordings in
  `assets/audio/house/knock/` would carry better than the kit's file. With one knock file about
  half of the house's effects are knocks (a third in a row is refused); a second file brings it
  to the set 60 %.

Looks
- **The Hacienda is very dark**, and its walls and floors are generated tiles, not final art.
- **Rooms do not hide.** The old house shows only the room she is in; the Hacienda has no rooms
  set up, so everything is lit by her light alone.
- **The minimap is a coarse block plan** of each floor.
- **The altar keeps its own small progress bar** in the world, as well as the HUD.
- **"Prayed" can sit over the altar counter** when a prayed altar is near the top of the screen.
- **Six trunks are empty** ("Empty."). They were empty in the source branch too.

Play
- **The stairs are an instant change of floor**, with a door sound and "[Stairs creak]".
- **Changing floor moves the entity** to that floor's start, after a wait of 6 s (ground) or
  4 s (upstairs). It does not follow her up the stairs.
- **The tutorial's old ending now plays at the Hacienda's gate.**

Housekeeping
- `tutorial/zones/mansion_upper.tscn` carries a hand-written id (`uid://m4ns10nupp3r`). Godot
  warns and falls back to the path; it works. It should be re-saved from the editor.

## Decisions taken by default

- Our trunk flow, our entity audio, our camera and light kept; the other branch's versions of
  those not taken.
- All Hacienda text in English.
- The effects script not attached to Viv.
- She prays aloud only at altars that say so (`prayer_spoken`, on for the Hacienda's).
- Levels: chase music −8 dB, kill −1 dB, prayer voice −6 dB on the effects bus, trunk −7 / −15
  dB, battery −5 dB.
- The outside goes black whenever she stands in a room of the old house.
- The house's voice in the Hacienda: from the patrol's places, no doors found ajar.
