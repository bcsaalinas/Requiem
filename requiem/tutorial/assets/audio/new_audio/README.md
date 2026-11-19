# new_audio — raw sound picks (ElevenLabs)

Raw, unprocessed MP3s. **Every file here is meant to be used.** Several files in one folder = variations of the same sound, to be played at random so it never feels repetitive.
One folder = one sound set. Folder name = set name in the game (`res://assets/audio/<entity|viv>/<set>/` after processing).

## entity/
| Folder | When it plays |
|---|---|
| `mumble` | Idle talking while it roams and has not heard you (random, every few seconds) |
| `breath_calm` | Breathing loop while calm |
| `breath_hunt` | Breathing loop while hunting |
| `heard_voice` | It heard something (the one sound players must learn) |
| `neck_click` | The head snap at that same moment |
| `inhale` | The breath before the scream |
| `scream` | Hunt starts |
| `foot_slam` | The stomp with the scream |
| `lost` | It lost you (hunt ends) |
| `exhale` | It relaxes / gives up |
| `sniff` | While it searches |
| `claws_walk` | Walking steps (several steps per file: cut into single steps) |
| `claws_scuttle` | Crawling steps while it searches (cut into single steps) |
| `claw_scrape` | Claws dragged on the floor (listening, feeling the floor) |
| `pat_tap` | Claws tapping the floor while it searches |
| `catch_grab` | The grab when it catches Viv |

All entity sets are present. Also: `claws_run` (running steps, cut into single steps), `drag` (cloth dragging loop while it moves), `cloth_fall` and `sob_stops` (the end of the catch, after `catch_grab`).

## viv/
| Folder | When it plays |
|---|---|
| `hold_in` | She starts holding her breath (quick, quiet) |
| `exhale` | She lets go early (quiet) |
| `gasp` | She lets go late (louder) |
| `forced_gasp` | She ran out of air (the entity hears this) |
| `calm` | Breathing loop, calm |
| `nervous` | Breathing loop, the entity is alert |
| `panic` | Breathing loop, hunted or sprinting |

