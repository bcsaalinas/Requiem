# Audio Asset Checklist

The project includes a Horror Jam Kit in `assets/audio/horror-jam-kit`, `assets/audio/horror-jam-kit 2`, and `assets/audio/horror-jam-kit 3`. The implementation now uses those supplied files for transitional state beds, threat heartbeat, hunt/death stingers, and door creaks. The original WAV and OGG copies are kept in their supplied folders; no assets were invented. These short textures work as a minimum reactive layer, but they are not a replacement for a composed long-form score.

The included kit license allows use in commercial and non-commercial projects and does not require credit. Suggested credit: “Sound effects: Horror Jam Kit by ahustga (ahustga.itch.io).” Do not redistribute the source files as a separate sound pack; the supplied license is included beside the assets.

| Suggested resource | Type / use | Recommended characteristics |
|---|---|---|
| `horror-jam-kit/WAV/Drone/drone_tension_02.wav` | Menu / explore bed | Supplied 10.95 s low tension drone; currently looped by MusicDirector |
| `horror-jam-kit/WAV/Drone/drone_tension_03.wav` | Investigate bed | Supplied 11.11 s rising tension drone; currently looped by MusicDirector |
| `horror-jam-kit 3/OGG/Tonal/high_tension_tone_01.ogg` | Search bed | Supplied 6.55 s tonal texture; currently looped at SEARCH |
| `horror-jam-kit 3/OGG/Drone/drone_tension_03.ogg` | Hunt bed | Supplied compressed tension drone; currently looped at HUNT |
| `horror-jam-kit 3/OGG/Tonal/eerie_music_box_02.ogg` | Prayer bed | Supplied 3.50 s tonal texture; currently looped while an actual altar prayer is active |
| `horror-jam-kit 3/OGG/Body/heartbeat_01.ogg` | Search / hunt tension cue | Supplied heartbeat loop; lower level in SEARCH, raised in HUNT, ducks while holding breath; not heard by entity logic |
| `horror-jam-kit 3/OGG/Body/breath_texture_01.ogg` | Entity INVESTIGATE cue | Positional one-shot when the entity enters INVESTIGATE |
| `horror-jam-kit 3/OGG/Riser/riser_02.ogg` | Entity SEARCH cue | Positional one-shot when the entity enters SEARCH |
| `horror-jam-kit 3/OGG/Stinger/dread_stinger_01.ogg` | Entity hunt stinger | Assigned to the existing EntityAI hunt-stinger slot |
| `horror-jam-kit 2/WAV/Stinger/jump_scare_02.wav` | Death stinger | Assigned to the existing GameOverUi one-shot player |
| `horror-jam-kit 2/WAV/Foley/creak_02.wav` | Door open/close creak | Assigned to current Door creak slot; the existing noise radius/event remains unchanged |
| Entity breath variations | Existing entity SFX | Monster breathing already exists; additional calm/hunted recordings with varied length/pitch would improve variation |
| UI navigation/select/back sounds | UI SFX | Optional 80–400 ms soft, low transient sounds; route only to UI bus and never to NoiseManager |
| Zone ambience recordings | Existing ambience | Current four zone loops are present; ensure loop points are seamless and headroom retained |

## Optional vertical remix stems

To use vertical remix with future compatible stems, assign them to `MusicDirector.music_stems["HUNT"]`. The current kit clips have different lengths, so the implementation does not incorrectly sync them as stems. The director accepts up to four aligned layers, crossfades states, and exposes `set_stem_mix(HUNT, [1.0, 0.0, 0.0])` / `[1.0, 0.65, 1.0]` for layer balance once aligned stems are acquired.
