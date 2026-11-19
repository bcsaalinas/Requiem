# Requiem — Audio Spotting

This map was checked against the current Godot 4.7 project. “Logical noise” means `NoiseManager.noise_emitted`, which is gameplay input to the blind entity; it is separate from the audio bus mix.

| Real gameplay event | Entity state / response | Music response | Existing SFX | Transition and owner |
|---|---|---|---|---|
| Tutorial zone entered (`enter_zone`) | Entity is disabled except for the post-altar house encounter; otherwise patrols | Ambience crossfades to the authored zone loop. Music state is EXPLORE once gameplay entity is bound | Zone assets in `tutorial.gd`; prayer loop in house | 2 s crossfade via `AmbienceManager.set_track`; `tutorial.gd` |
| Entity FSM changes PATROL / INVESTIGATE / SEARCH / HUNT | Entity base `_change_state`; accepted noise still goes directly to HUNT; hunt timeout can lead to SEARCH then PATROL | Follows what the entity knows (`audio/dread.gd`): silence when it hears, hunt music with the scream, a thin tone while it searches, the exploration drone back over 6–8 s when it gives up; uses the supplied Horror Jam Kit drone/tonal beds | PATROL: its calm breathing, idle mumbling and claws (`entities/entity_audio.gd`, Entity bus). Heard: `heard_voice` with the neck click, then silence. HUNT: inhale, scream and stomp, then its hunting breath. SEARCH: the `lost` groan and a sniff. Back to PATROL: `stand_down`. No stingers or risers. Viv's one heartbeat (`player/heart_audio.gd`) beats with what it knows | A fade time per transition (`audio/sound_settings.gd`, "Music"); cues on the entity's own signals (`listen_started`, `stood_down`, `state_changed`) |
| Heard player noise | Existing `NoiseManager.noise_emitted` filters and current per-state multipliers remain authoritative | No direct sound callback: music follows the resulting FSM transition, preventing duplicate cues | Footsteps, breath, throws, supplied `creak_02.wav` for door motion, altar and scripted noises | `FootstepNoise`, `HoldBreath`, object scripts → `NoiseManager` → entity `_on_noise_emitted` |
| Player starts / releases / cancels holding breath; forced gasp | Does not change entity FSM or hearing radii | Apply/release a 5 dB Music duck while preserving `current_state`; holding is also listening: Music, Ambience and World go soft (2500 Hz) and the entity comes up 2 dB | Viv's own sets (`viv/hold_in`, `exhale`, `gasp`, `forced_gasp`) and the exertion clip | `HoldBreath` signals → `MusicDirector` / `BodyAudio` → `MixDirector` (the only script that changes the mix) |
| Prayer starts / ends on a real altar | Existing altar/noise logic is unchanged | PRAYER / return to EXPLORE | No voices: the altar plays no clip. While she prays Music, Ambience and World are low-passed slowly, her breathing slows and her heart beats (`player/prayer_audio.gd`); a `house/prayer_tone` file would rise with her progress (folder empty today) | `GameState.prayer_started` / `prayer_ended` → `MusicDirector` |
| Player death / reset | Existing GameState behavior | DEATH / EXPLORE on reset | No stinger: the catch cues (`catch_grab`, `cloth_fall`, `sob_stops`) carry the moment, then Music, Ambience and World fall silent on the game over screen | `GameState.player_died` / `state_reset`; one-shot remains owned by GameOverUi |
| Catch or UI navigation | Tutorial catch uses its own checkpoint reset; UI does not feed the noise manager | No dedicated UI state/stinger currently | Existing catch clips and UI feedback | Existing entity/tutorial and UI owners; no new noise emission |

## Not currently implemented / content-dependent

- INVESTIGATE exists in the FSM enum but the current hearing rule sends an accepted sound directly to HUNT. The music state is ready, but it should only be heard if gameplay later makes the state reachable.
- The supplied kit provides short drones/tonal textures rather than a full authored score. The director uses those existing resources as temporary state beds; bespoke long-form loops/stems would improve continuity.
- Horizontal resequencing is supported through state-specific loop selection. Vertical remixing is prepared through optional synchronized `MusicDirector.music_stems` arrays; no authored compatible stems currently exist to exercise it.
- Existing ambience uses complete zone loops, so horizontal resequencing is not applicable to those recordings.
- Positional SFX remain `AudioStreamPlayer2D` where already authored; new ambience stays non-positional by design.
- No discrete stingers are used: the hunt stinger, search riser and death stinger were taken out of use; the entity's own cues carry those moments.

## Hearing invariant

Audible players use the Music, Ambience, World, Body, UI, Entity, EntityFar and SFX buses. Viv's one heartbeat (`player/heart_audio.gd`) is a player-perspective tension cue and never calls `NoiseManager`; bus gains and MusicDirector state do not change noise radii or influence entity hearing filters. Footstep audio and footstep logical noise remain separate systems.
