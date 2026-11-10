# Requiem — Audio Spotting

This map was checked against the current Godot 4.7 project. “Logical noise” means `NoiseManager.noise_emitted`, which is gameplay input to the blind entity; it is separate from the audio bus mix.

| Real gameplay event | Entity state / response | Music response | Existing SFX | Transition and owner |
|---|---|---|---|---|
| Tutorial zone entered (`enter_zone`) | Entity is disabled except for the post-altar house encounter; otherwise patrols | Ambience crossfades to the authored zone loop. Music state is EXPLORE once gameplay entity is bound | Zone assets in `tutorial.gd`; prayer loop in house | 2 s crossfade via `AmbienceManager.set_track`; `tutorial.gd` |
| Entity FSM changes PATROL / INVESTIGATE / SEARCH / HUNT | Entity base `_change_state`; accepted noise still goes directly to HUNT; hunt timeout can lead to SEARCH then PATROL | EXPLORE / INVESTIGATE / SEARCH / HUNT, via `state_changed` and `MusicDirector`; uses the supplied Horror Jam Kit drone/tonal beds | PATROL: slow-pitched monster breathing. INVESTIGATE: positional `breath_texture_01.ogg` cue. SEARCH: positional `riser_02.ogg` cue and breath becomes louder/faster. HUNT: `dread_stinger_01.ogg`, faster/louder breathing, plus the quiet player-perspective heartbeat | Loop crossfade (1.4 s); one-shot cues on FSM entry; state signal from `entities/entity_ai.gd` |
| Heard player noise | Existing `NoiseManager.noise_emitted` filters and current per-state multipliers remain authoritative | No direct sound callback: music follows the resulting FSM transition, preventing duplicate cues | Footsteps, breath, throws, supplied `creak_02.wav` for door motion, altar and scripted noises | `FootstepNoise`, `HoldBreath`, object scripts → `NoiseManager` → entity `_on_noise_emitted` |
| Player starts / releases / cancels holding breath; forced gasp | Does not change entity FSM or hearing radii | Apply/release a 5 dB Music bus duck while preserving `current_state` | Existing hold, release, gasp and exertion clips | `HoldBreath` signals → `MusicDirector`; immediate mix adjustment |
| Prayer starts / ends on a real altar | Existing altar/noise logic is unchanged | PRAYER / return to EXPLORE | Tutorial has its prayer loop; real altar effects depend on assigned clips | `GameState.prayer_started` / `prayer_ended` → `MusicDirector` |
| Player death / reset | Existing GameState behavior | DEATH / EXPLORE on reset | Supplied `jump_scare_02.wav` through the existing GameOverUi one-shot owner | `GameState.player_died` / `state_reset`; one-shot remains owned by GameOverUi |
| Catch or UI navigation | Tutorial catch uses its own checkpoint reset; UI does not feed the noise manager | No dedicated UI state/stinger currently | Existing catch clips and UI feedback | Existing entity/tutorial and UI owners; no new noise emission |

## Not currently implemented / content-dependent

- INVESTIGATE exists in the FSM enum but the current hearing rule sends an accepted sound directly to HUNT. The music state is ready, but it should only be heard if gameplay later makes the state reachable.
- The supplied kit provides short drones/tonal textures rather than a full authored score. The director uses those existing resources as temporary state beds; bespoke long-form loops/stems would improve continuity.
- Horizontal resequencing is supported through state-specific loop selection. Vertical remixing is prepared through optional synchronized `MusicDirector.music_stems` arrays; no authored compatible stems currently exist to exercise it.
- Existing ambience uses complete zone loops, so horizontal resequencing is not applicable to those recordings.
- Positional SFX remain `AudioStreamPlayer2D` where already authored; new ambience stays non-positional by design.
- Discrete stingers remain owned by the existing entity and GameOverUi players; they use supplied kit clips and do not duplicate playback in MusicDirector.

## Hearing invariant

Audible players use SFX/Ambience/Music/UI buses. The heartbeat is a player-perspective tension cue and never calls `NoiseManager`; bus gains and MusicDirector state do not change noise radii or influence entity hearing filters. Footstep audio and footstep logical noise remain separate systems.
