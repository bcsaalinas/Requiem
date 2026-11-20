# Audio System Validation

Run the project with Godot 4.7 or newer from `requiem/project.godot`.

1. Open **Project > Project Settings > Audio** and confirm Master, Music, Ambience, SFX, and UI. `default_bus_layout.tres` stores the layout; MusicDirector has a fallback for missing custom buses.
2. Launch the main menu. Open Audio settings and move every available bus slider; confirm settings persist after reopening the page.
3. Start tutorial and move between bedroom, hallway, forest, house, and loop. Confirm ambience crossfades and loops without starting another copy; in test mode ambience stays silent.
4. In the post-altar encounter, trigger a noise within hearing range. Confirm the entity still follows the same authored rule and the director changes to HUNT only when the FSM enters HUNT. Wait through its persistence/search cycle to observe SEARCH and PATROL transitions.
5. Hold, release, and forcibly gasp. Confirm only the Music bus mix ducks/restores; entity state and hearing radii are unchanged. Move from HUNT to SEARCH while holding breath and confirm the current state stays reflected after release.
6. Start/end an actual altar prayer in a scene that supports it. Confirm prayer state and return state. The tutorial's scripted house altar lesson is not a real altar interaction.
7. Die and restart/return to menu. Confirm the existing GameOverUi sting is not duplicated, reset restores EXPLORE, and no ambience/music loop remains from the prior scene.
8. Add a temporary exported test loop to `MusicDirector.music_tracks` and exercise crossfades. Without authored music, silence in Music is expected and no missing-file error should occur.

Audible clipping and perceived balance require listening with authored music assets; automated/headless validation can check state, buses and references but cannot judge mix quality.

## Automated suites

`python3 testing/run_checks.py` (or `--suite <name>`) runs these audio suites with the rest; `testing/README.md` says what each one checks.

- `test_audio_mix`: the bus layout and MixDirector, the only script that changes the mix.
- `test_entity_audio`: every animation cue of the entity maps to a sound set or is listed as silent.
- `test_awareness`: the four awareness cues; no detection is ever silent; the 0.7 s warning before the scream.
- `test_idle_voice`: the entity's idle talking and sniffing.
- `test_dread`: threat, and what the music and the world do at each moment of an encounter.
- `test_acoustics`: rings, walls and doorways in the real house.
- `test_rings`: what the rings and the doorway do to the entity's position sounds.
- `test_body_audio`: Viv's breathing, listening, self-masking and her heart in play.
- `test_heart`: the one heartbeat and its four reasons.
- `test_house_voice`: the house's own sounds, their gates, the answering knock and the door found ajar.
- `test_sparse_music`: the exploration drone coming and going on its own clock.
- `test_jump_scare_audit`: the audit of sudden rises and of house sounds played while gated.
- `test_prayer_audio`: prayer without voices, and its noise exactly as before.
- `test_entity_knock`: the entity's knock, behind its switch.
- `test_calm_beside_her`: every file of every sound the entity makes while calm, played 1.5 u from Viv in a silent house (and while she holds her breath); none may rise more than 17 dB on Master. Prints the table. About 2½ minutes.
