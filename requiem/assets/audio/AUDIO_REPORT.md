# Requiem — Audio report

The sound system of the brief, Steps 1 to 18, on the branch `audio/sound-system`. Nothing is pushed.

How to read it. "Viv" is the player. "The entity" is the blind creature. Distances are in units: 1 u = 32 px, about one step and a half. Levels are in dB (decibels: 6 dB is about twice as loud, 10 dB sounds about twice as loud to the ear, 18 dB is a big jump). LUFS is a measure of how loud a sound feels over its whole length (−12 LUFS is loud, −32 LUFS is a whisper). "Set" means one folder of sounds under `assets/audio/`: the game picks one file of the folder at random each time, never the same one twice in a row.

The two channels of the entity, used all through this report:

- **Channel A, what it knows**: heard-you, scream, lost-you, stand-down. Carries far, always recognisable.
- **Channel B, where it is**: breathing, idle talking, claws, cloth drag, sniffing. Clear when near, fragments a room away, nothing beyond.

Contents: 1 What each step delivered · 2 Decisions taken by default · 3 Reverted or could not do · 4 Empty sound folders · 5 Your source files · 6 Values to tune · 7 The encounter checklist · 8 Checks · 9 Known issues · 10 File by file.

---

## 1. What each step delivered

**Step 1 — Prepare the sounds** (`f6e52b7`, follow-up `155bf66`). Her raw picks in `tutorial/assets/audio/new_audio/` became game sounds in `assets/audio/entity/<set>/` and `assets/audio/viv/<set>/`: mono, 48 kHz, peaks at −1 dB, levelled to the brief's targets. Loops (breathing, the drag) are OGG files that loop without a click; claws, taps and scrapes are cut into single hits; screams are trimmed to their loudest second; long mumbles are split at their pauses; sniffs are cut into single sniffs; `entity/stand_down` is built from the exhale, 15 % slower. The script that does it is `tools/audio/prepare_sounds.py` (re-run it after adding raw files); it writes the table `assets/audio/SOUND_SETS.md`. Sharp clicks that cannot reach their target without being squashed are turned up when they play instead (`set_gain_db`). The raw folder is left out of exported builds.

**Step 2 — Buses and one owner of the mix** (`f8f0890`). Eight sound channels ("buses") now: Music, Ambience, World (the house: doors, chests, thrown things, the tutorial's story sounds), Body (Viv), UI, Entity, EntityFar (the entity through walls: dulled above 1200 Hz) and SFX, all into Master with a limiter at −1 dB (`default_bus_layout.tres`). One script, `audio/mix_director.gd` (MixDirector), is the only one allowed to change the mix; others ask it to duck or muffle, with a priority (scream > holding breath > prayer > threat). Muffling can only touch Music, Ambience and World, never the entity or Viv. The SFX slider moves World, Body, Entity and EntityFar with it. Viv carries the ears (`player/ears.gd`), so sound pans from where she stands, not from the camera. Every number of the system lives in `audio/sound_settings.gd`.

**Step 3 — The entity's body plays its animation cues** (`36a80b1`). `entities/entity_audio.gd` (EntityAudio, inside `entities/entity.tscn`) plays every sound the animations ask for on its exact frame, from the entity, on the Entity bus: claws, taps, scrapes, the neck click, the catch. Its breathing (calm on patrol and searching, harder while hunting) and its cloth drag are loops that follow what it does, and stop at once while it listens, screams or catches. `audio/sound_library.gd` turns a folder into a set. Removed from use: the hunt stinger, the search riser, `behind_wall.wav` as the drag; the NonCommercial breathing file was deleted.

**Step 4 — Channel A, the awareness cues** (`939ab14`). The four things it knows have their own sounds. It heard something: everything of it stops, then `heard_voice` and the neck click together, one scrape, silence. It is hunting: inhale, scream, stomp, while Music, Ambience and World duck 14 dB. It lost the trail: `lost`, then one sniff. It gave up: `stand_down`. These carry far and never fall silent with distance (`entity_audio.gd`; two small signals added to `tutorial/entity.gd`, no timing changed). The scream never repeats the same file twice running and is 4 dB quieter within 20 s of the last one.

**Step 5 — The idle voice** (`11a50e6`). On patrol it mumbles a phrase every 6–15 s while it walks; a phrase trails off when it pauses. While it searches its voice is lower (pitch 0.9) and rarer (10–20 s), and it sniffs in short runs as it scuttles. Never while it listens, screams or hunts; a phrase in progress is cut the instant it hears something (`entity_audio.gd`).

**Step 6 — Threat: the music and the world react to what it knows** (`b8ba43e`). `audio/dread.gd` (Dread) holds one number, threat, from what it knows (unaware 0, paused 0.1, heard 0.6, searching 0.7, hunting 1), never from its distance. As threat rises, Ambience and World pull back (−10 dB at full) and Viv's body comes forward (+3 dB). The music (`autoloads/music_director.gd`) cuts to silence when it hears, starts the hunt music with the scream, plays a thin tone while it searches, and brings the drone back over 6–8 s when it gives up. Death has no stinger: the catch sounds, then silence. The Test Lab gained the **Sound Audition** (`testing/experiments/sound_audition.gd`).

**Step 7 — Acoustics** (`4561832`). `audio/acoustics.gd` (Acoustics) measures, five times a second, how far the entity's sound really travels to Viv: the straight line when nothing is in the way, otherwise mostly the walking path through the doorways. From that comes a clarity (0–1) and a ring: 3 on top of you (under 4 u), 2 near (under 9 u), 1 somewhere (under 18 u), 0 gone. It only measures; it plays nothing.

**Step 8 — The rings applied to Channel B** (`d18471f`). Position sounds follow that measure: in the same room all of them, sharp and placed exactly; a room away quieter, dulled (EntityFar), vaguely placed, and some lost on the way; beyond ring 1 silent. Channel A ignores all of it. How near it is (presence) reaches Dread late and smoothly, and the world recedes by the stronger of threat and presence. The music ignores presence (`entity_audio.gd`, `dread.gd`, `mix_director.gd`).

**Step 9 — Viv: her body and her listening** (`0c76df6`). Her breath takes are her own sets (`viv/hold_in`, `exhale`, `gasp`, `forced_gasp`, in `player/player.tscn`), noise radii unchanged. `player/body_audio.gd` gives her a breathing loop (calm, nervous, panting) that stops while she holds her breath. Holding her breath is listening: Music, Ambience and World go soft (2500 Hz), the entity comes up 2 dB, ring 1 reaches 1.3 times further, half its gaps close. Walking hides 6 dB of the entity's far sounds, sprinting 12 dB.

**Step 10 — The house voice** (`9ffd908`). `audio/house_voice.gd` (HouseVoice): quiet settling sounds (folder empty, so silent), rare effects (a knock, a creak, something falling, a chair) 90–150 s apart, and one roll in six "nothing" (the ambience thins for 4 s). Always from a room she is not in, on World, no louder than −26 LUFS, with a soft start. It is silent while the entity is alert, inside ring 2, within 20 s of an awareness cue, or while she prays, and it says why in words. One loud thing she does may be answered by one knock about a second later. The tutorial's own unease before the key now plays through it.

**Step 11 — Sparse music** (`64e86ee`). During exploration the drone stays 40–90 s and is away 40–90 s on its own clock, fading slowly both ways, whatever the entity does. Every awareness reaction of Step 6 still wins (`music_director.gd`).

**Step 12 — Debug view and tests** (`3eaeb01`). F3 in any Test Lab scene shows an audio read-out: threat, presence, her heart, the entity's ring, clarity, wall, where its sounds come from, the last cue on each channel, why the house is silent, and the **jump-scare audit** (`testing/tools/jump_scare_audit.gd`, `testing/tools/noise_debug.gd`). The audit watches Master for any rise of more than 18 dB within 0.1 s; the scream is counted and left out, every other rise is logged with what explains it, and anything unexplained is printed as UNEXPLAINED. It also logs any house sound that played while its gates were closed.

**Step 13 — Viv's footsteps by surface** (`9c1c70d`). Her steps take their sounds from what she walks on: wood in the bedroom, hallway, house and last room; forest floor in the forest (`player/footstep_audio.gd`, the table in `tutorial/tutorial.gd`). Both folders, `viv/steps_wood` and `viv/steps_forest`, are empty, so today she still walks on the eight concrete steps. Files dropped in become her steps with no code change. What the entity hears of her steps is untouched.

**Step 14 — One heartbeat** (`2111edd`). Viv has one heart (`player/heart_audio.gd`, on Body). How hard it beats follows the highest of: running out of air, what the entity knows (from above "paused"), and how near it is (any state, also unaware). Level and speed rise together: about −24 dB at most when an unaware entity is next to her, −20 heard, −18.5 searching, −13 hunting, −3 with no air left (the cap). The two old heartbeats (the music's and the strain's) are gone. No camera shake.

**Fix between 14 and 15 — Viv's breathing** (`872d46c`). Her calm breathing was loud enough to be mistaken for the entity's. It is now quiet (calm −12 dB, nervous −8 dB under the file), nervous while the entity has heard, searches or hunts, and panting (`viv/panic`) plays only while she sprints past the exertion warning (65 %, the same number that makes the HUD's bar pulse). The entity's hidden breathing is off in every tutorial zone. Her breath, throw, flashlight and prayer takes never repeat twice running (`body_audio.gd`, `sound_library.gd`, `hold_breath.gd`, `tutorial/vital_meters.gd`, `tutorial/tutorial.gd`).

**Step 15 — Sound through the doorway** (`048e938`). When a wall is between them, the entity's position sounds come from the doorway the sound really travels through, at the entity's real distance, so the loudness and dulling are unchanged and only the direction moves. Small changes glide; a jump to another doorway goes vague for half a second instead of sweeping across the wall. Channel A is not moved. Switch: `doorway_panning` (`acoustics.gd`, `acoustic_reading.gd`, `entity_audio.gd`).

**Step 16 — Prayer without voices** (`4b20647`). The whispering file is out of `altar/altar.tscn`. Praying is now a state of its own (`player/prayer_audio.gd`): Music, Ambience and World sink into a low-pass (900 Hz after 2.5 s, slower and deeper than holding breath), her breathing slows, her heart beats quietly (about −20 dB), and the world returns over 3 s. A file in `house/prayer_tone` would rise with her progress (empty: silent). The entity is never dulled, and the prayer's noise for the entity is exactly what it was.

**Step 17 — The house escalates** (`1890203`). If she keeps being loud, each answering knock comes from a little nearer (never from her room, never nearer than 3 u, at most 3 steps), and a quiet minute resets it. After one of the rare effects, once per run, a door she cannot see may be found ajar 8–20 s later with a creak: only its leaf is drawn 20 % open; the door stays shut for her, the light and the entity, and the entity does not hear the creak (`house_voice.gd`, `tutorial.gd`).

**Step 18 — The entity knocks, behind a switch** (`a7254b0`). `entity_knocks_enabled`, off. When on: once in a patrol pause next to a door (within 1.5 u), calm for 30 s, at most every 120 s, only when Viv hears it in ring 2 or 1, it knocks, from where it stands, on the Entity bus, never heard by itself. Its sounds are its own set, `entity/knock`, which is empty: no file, no knock. In the Sound Audition, N turns it on for the session.

---

## 2. Decisions taken by default

Each line: what was chosen, and how to change it. Values named here are in `audio/sound_settings.gd` (see section 6).

| Step | Decision | To change it |
|---|---|---|
| 1 | Quiet clicks and thuds are turned up when they play, not squashed in the file (`set_gain_db`: neck click +6, foot slam +5, pat tap +5.5, cloth fall +8.5, catch grab +1.5, claws run +0.5 dB). | Edit `set_gain_db`; any set can be listed. |
| 1 | Sniffs are cut into single sniffs (37 files), so the game can play one or a short run. | Re-cut in `prepare_sounds.py`. |
| 3 | The old entity clip slots stay in `entity_ai.gd` but are silent whenever EntityAudio is present, so nothing plays twice. | — |
| 4 | The heard-you cue waits up to 0.25 s for the head snap of the animation, then plays without it. A hunt start without an animation still plays its scream ("no scream, no hunt"). | `heard_click_wait`, `scream_cue_wait`. |
| 5 | A phrase trails off over 0.4 s when it pauses on patrol (a fade, not a cut); it is cut at once only when it hears something. | `talk_pause_fade`. |
| 6 | No extra sound on the game over screen: the catch cues, then Music, Ambience and World fall silent. | `death_duck_db`, `death_fade`. |
| 7 | Furniture on the wall layer is looked past; doors never block sound. | `acoustics_wall_mask`. |
| 10 | The house's effects are the tutorial's files (knock, creak, something falling, a chair), plus anything in `house/effects`. | `house_effects`. |
| 11 | After a prayer the drone is wherever its own clock has it; after an encounter, the menu or a death it always comes back. | — |
| 12 | The audit measures rises from a floor of −26 dB, so a quiet sound appearing in a silent house is not a jump scare. | `audit_floor_db`. |
| 13 | A surface set never plays when the concrete steps on her footstep node are empty (the automated tutorial silences her steps that way). New files in a folder are read once per launch. | — |
| 14 | No camera shake (the game has none to reuse). | — |
| 14 | One scale for the heart's level and speed: it beats faster in a hunt (speed about 1.27) than the old heartbeat did. | `heart_db`, `heart_pitch`. |
| 14 | The heart starts when it hears something, not at the scream; on a zone change mid-hunt it calms down over a few seconds instead of stopping on the doorstep. It stops at once on death and on a new attempt. | `heart_threat_from`, `heart_threat`. |
| 14 | One heart, so the two old heartbeats were removed. The WAV copy (kit 2) is used; it is the same recording as the OGG the music used, same loudness. | — |
| fix | Hunting gives the nervous breath, not panting. Panting needs sprinting **and** being past the exertion warning. No animation cue on Viv (the HUD is the visual cue). | `viv_breath_db`, `viv_pant_db`; the warning is `exertion_warn_percent` on HoldBreath in `player/player.tscn`. |
| fix | Starting levels: calm −12 dB, nervous −8 dB under the files; panting −16 dB at the warning to −7 dB before the forced gasp. | `viv_breath_db`, `viv_pant_db`. |
| fix | Her breath takes, the throw, the flashlight click and the prayer clips never repeat twice running. | — |
| 15 | Behind a wall, its position sounds come from the doorway, at the entity's real distance (loudness and dulling unchanged). Small moves glide over 0.25 s; a jump to another doorway goes vague and comes back over 0.5 s. Channel A is never moved. | `doorway_panning` (off = Step 8's placing), `doorway_glide`, `doorway_settle`. |
| 15 | No real place in the house puts the doorway on the other side of Viv from the entity (the walls all run north–south), so left/right is tested in a small room built for the test. | — |
| 16 | The whispering file stays on disk, unused (`assets/audio/193812__geoneo0__four_voices_whispering_6.wav`). | Delete it if not wanted. |
| 16 | Eli's low praying in the tutorial (`tutorial/assets/audio/prayer.wav`) was left alone: it is a story sound of the friend, not Viv's prayer. **Yours to judge**: is it "a voice saying words"? | `tutorial/tutorial.gd`, `prayer_audio`. |
| 16 | One return time (3 s) for a completed and a let-go prayer (a short prayer has less to come back from). Her breathing slows by playing 15 % slower. The heart's fourth reason is prayer (0.35, about −20 dB). | `prayer_return`, `viv_breath_prayer_pitch`, `heart_prayer`. |
| 16 | The prayer tone would play on the SFX bus (the slider reaches it, nothing ducks it). The music box still plays during prayer, low-passed with the rest. | — |
| 16 | Holding her breath mid-prayer starts listening from where the prayer has the house (no jump from 900 Hz to open and back). | — |
| 17 | "A short window" = 40 s between two answered loud things; "a quiet minute" = 60 s. "A little closer" = the farthest allowed place that is nearer than the last answer. The level limit rises −26 → −22 LUFS with the step; the knock is only turned down to it, never up. | `house_escalate_window`, `house_escalate_reset`, `house_escalate_steps`, `house_escalate_max_lufs`. |
| 17 | The door "found ajar" is only drawn 20 % open, never really opened (`level/door/door.gd` untouched), so it stays shut for bodies, light and the entity. Its creak is `creak_02` at the house level; the entity cannot hear it. Once per run: a retry is not a new run. On by default, half the times after an effect. | `house_ajar`, `house_ajar_chance`, `house_ajar_swing`, `house_ajar_delay`. |
| 18 | Off by default. Heard from where it stands, also through a wall (the brief says "true position"), not from the doorway like its other position sounds. Rings 2 and 1 only. One knock per pause. No animation. The 30 s first wait counts calm time (unaware, on patrol), restarting after any alert. | `entity_knocks_enabled`, `entity_knock_first`, `entity_knock_gap`, `entity_knock_door_u`, `entity_knock_db`. |

---

## 3. Reverted, could not do, or only measured

Nothing was reverted. Every step was committed.

- **Hearing.** Nothing was heard by ear: every level in this report was measured (in the suites, or live through the read-outs). What a sound is like, whether two sounds are told apart, and balance are for your ears (section 7 lists what to listen to first).
- **Bus meters live.** The live game could not read the bus meters through the Godot connection (it cannot reach the audio server); levels live were read from the read-outs and the players' own settings, and bus levels were measured in the suites.
- **Step 16:** the 3 s return after a prayer was measured in the suite, not caught live (each live read takes seconds).
- **Step 17:** the knock file (`door_knock_01`, −28.9 LUFS) is already under every limit, and the house never turns a sound up, so the answering knock today gets **nearer but not louder**. Captions are off in this install's preferences, so the door's caption was checked only in the suite.
- **Step 18:** with today's patrol route **the entity can never knock in the house**: none of its six patrol stops is within 1.5 u of a door; the nearest (Patrol5) is about 4 u from the front and kitchen doors. Hearing it in play needs a patrol stop by a door (entity plan) or a larger `entity_knock_door_u`, plus files in `entity/knock`.
- **Step 13:** `tools/audio/prepare_sounds.py` treats a new Viv set as whole one-shots levelled to −28 LUFS: it would level raw footstep files to the breath level (likely quiet for steps) and does not cut a take that holds several steps. Finished one-step files dropped straight into the folders work.
- **The scream's variety:** the selection never repeats a file, but `entity_scream_erupts_01` and `erupts_02` are near twins (their shapes match at 0.82), so in practice it alternates between two screams. A third distinct take needs a new recording, not code.
- **`SOUND_SETS.md`** is written by `prepare_sounds.py`. Its "Plays:" line for `viv/panic` was corrected by hand (panting: sprinting past the exertion warning). That text comes from the README beside your raw files (`tutorial/assets/audio/new_audio/README.md`, which is yours and was not edited), not from a table in the tool, so the next run of the tool will bring back "hunted or sprinting". Change that README line to keep the correction.

---

## 4. Sound folders that are still empty

Folders under `assets/audio/entity`, `assets/audio/viv` and `assets/audio/house` with no audio file:

| Folder | What plays today instead | What to drop in |
|---|---|---|
| `entity/knock` | Nothing: no file, no knock (and the switch is off). | Single knocks on wood, one per file, WAV mono 48 kHz, peak −1 dB, about −20 LUFS (the other entity one-shots). At least two. |
| `viv/steps_wood` | Her eight concrete steps (`assets/audio/footsteps/concrete_step_0x.wav`). | One step per file on wooden floor, WAV mono 48 kHz, no loop, peak −1 dB or lower, peak around −4.5 dBFS like the concrete steps. At least two. Trim with `set_gain_db` (`"viv/steps_wood": dB`). |
| `viv/steps_forest` | The same concrete steps. | The same, on earth, leaves and twigs. |
| `house/settle` | Silence: the house has no settling sounds. | Very quiet wood creaks and pipe ticks, single short files; they are levelled to −26 LUFS and played 10 dB under it. |
| `house/effects` | The four effects listed in `house_effects`: a knock, a creak, something falling, a chair. | More rare, ambiguous house sounds; each joins the four, levelled to −26 LUFS, with the caption `house_effect_caption`. |
| `house/prayer_tone` | Silence during prayer (the music box still plays, low-passed). | One soft looping tone (OGG with loop on); it rises from −18 dB to −4 dB under the file with her progress. |

**Sets with a single take** (they cannot avoid repeating; a second file would let them vary):

- Entity: `breath_calm`, `catch_grab`, `cloth_fall`, `drag`, `exhale`, `inhale`, `sob_stops`, `stand_down` (built from the exhale).
- Viv: `calm`, `nervous`, `panic`, `gasp`.

The loops (breathing, drag, Viv's calm/nervous/panic) repeat by nature; a second take would let them change from one encounter to the next.

---

## 5. Your source files

All 53 audio files in `tutorial/assets/audio/new_audio/` (in 27 set folders, 20 for the entity and 7 for Viv) have at least one processed file in the matching folder under `assets/audio/`, and every one of those sets is played by the game: the entity's through `entities/entity_audio.gd`, Viv's breath takes through `player/player.tscn` (`hold_in`, `exhale`, `gasp`, `forced_gasp`) and her breathing loops through `player/body_audio.gd` (`calm`, `nervous`, `panic`). **No file is unused.** Nothing in `new_audio` was edited, moved or deleted (it is read only, and kept out of exported builds).

---

## 6. The values you are most likely to tune

**Where they live.** Every number is in `audio/sound_settings.gd`. In the Godot editor, open `audio/sound_settings.tres` in the Inspector: every value shows with its comment as a tooltip, grouped as below. The `.tres` file itself stores none of them today (it uses the script's defaults); what you change in the Inspector is saved into it.

**"Is it too loud / too quiet when it hears me or screams?"** (group "Entity: what it knows")

| Value | Now | What moving it does |
|---|---|---|
| `heard_floor_db` | −12 dB | The quietest the heard-you cue can be, however far away. Lower: far detections are softer (the fairness test fails below `audible_db`, −20). |
| `heard_voice_gain_db` | +2 dB | How far the heard-you voice stands over the idle mumbling. |
| `scream_gain_db` | +3 dB | The scream on top of its file. |
| `scream_duck_db` | −14 dB | How far Music, Ambience and World drop under the scream. |
| `far_floor_db` | −15 dB | The quietest "it lost you" and "it gave up" can be. |

**"Near it, too loud / a room away, too clear or too hidden"** (groups "Entity: where it is", "Acoustics")

| Value | Now | What moving it does |
|---|---|---|
| `position_edge_db` | −18 dB | How quiet its position sounds are at the far edge of ring 1. Lower: a room away is quieter. |
| `position_full_u` | 2 u | Out to this distance they play at full level. |
| `ring_somewhere_u` | 18 u | Where ring 1 ends and it goes silent (Channel B). |
| `gap_chance_body` | 0.3–0.7 | In ring 1, the chance a step, tap or scrape gets through (far edge – near edge). |
| `far_panning` | 0.35 | How exactly sounds are placed at the far edge of ring 1 (1 exact, 0 centre). |
| `set_gain_db` | see §2 | Turn one set up or down, e.g. `"entity/pat_tap": 5.5`. |

**"Her breathing / her listening"** (group "Viv: her body and her listening")

| Value | Now | What moving it does |
|---|---|---|
| `viv_breath_db` | calm −12, nervous −8 dB | Her own breathing loops. |
| `viv_pant_db` | −16 → −7 dB | Her panting, at the exertion warning → just before the forced gasp. |
| `mask_walk_db` / `mask_sprint_db` | −6 / −12 dB | How much of its far sounds her walking / sprinting hides. |
| `listen_cutoff_hz` | 2500 Hz | How soft the house goes while she holds her breath (lower = softer). |
| `listen_entity_db` | +2 dB | How much the entity comes up while she holds her breath. |
| `listen_reach_factor` | 1.3 | How much further ring 1 reaches while she holds her breath. |

**"Her heart"** (group "Viv: her heart")

| Value | Now | What moving it does |
|---|---|---|
| `heart_db` | −30 → −3 dB | Faintest and hardest beat (the hardest is the cap). |
| `heart_presence` | 0 → 0.22 | How hard an unaware entity next to her makes it beat (0.22 ≈ −24 dB). |
| `heart_threat` | 0.15 → 0.63 | From "heard" to "hunting" (0.63 ≈ −13 dB). |

**"The music and the mood"** (groups "Threat", "Music")

| Value | Now | What moving it does |
|---|---|---|
| `threat_world_db` | −10 dB | How far Ambience and World pull back at full threat. |
| `threat_fall_time` | 10 s | How slowly the house comes back after danger. |
| `music_drone_stay` / `music_drone_away` | 40–90 s / 40–90 s | How long the drone stays and is away on its own clock. |
| `music_fade_stand_down` | 6–8 s | How slowly the drone returns once it gives up. |

**"The house is too busy / too quiet"** (group "House: its own voice")

| Value | Now | What moving it does |
|---|---|---|
| `house_effect_gap` | 90–150 s | Time between two rare effects. |
| `house_max_lufs` | −26 LUFS | The loudest any house sound may be. |
| `house_after_cue` | 20 s | Quiet after any awareness cue before the house may speak. |
| `house_nothing_one_in` | 6 | One roll in this many is "nothing" (the ambience thins). |
| `house_ajar_chance` | 0.5 | Chance a door is found ajar after an effect (once per run). `house_ajar` off = never. |
| `house_escalate_window` / `house_escalate_reset` | 40 s / 60 s | What counts as "keeps being loud" and as "a quiet minute". |

**"Prayer"** (group "Viv: prayer")

| Value | Now | What moving it does |
|---|---|---|
| `prayer_cutoff_hz` | 900 Hz | How deep the house sinks while she prays. |
| `prayer_in` / `prayer_return` | 2.5 s / 3 s | How slowly it sinks, and comes back. |
| `heart_prayer` | 0.35 | Her heart while she prays (≈ −20 dB). |

**"The doorway"** (group "Entity: where it is")

| Value | Now | What moving it does |
|---|---|---|
| `doorway_panning` | on | Behind a wall its position sounds come from the doorway. Off: from where it stands, only vaguer with distance (Step 8). |
| `doorway_settle` | 0.5 s | After a jump to another doorway, how long the placing stays vague. |

**"The knock"** (group "Entity: knocking")

| Value | Now | What moving it does |
|---|---|---|
| `entity_knocks_enabled` | off | The switch. Needs files in `entity/knock`. |
| `entity_knock_door_u` | 1.5 u | How near a doorway it must pause to knock. Today no patrol stop is that near (about 4 u at best). |
| `entity_knock_gap` / `entity_knock_first` | 120 s / 30 s | Least time between knocks / calm time before the first. |
| `entity_knock_db` | −6 dB | The knock against its file. |

---

## 7. The encounter checklist

**How this was checked.** Nothing here was heard: it was measured in the running game (Test Lab → Sound Audition, F3 read-out on, "Viv is safe" on), driven through the Godot connection, on 19 November 2026. Levels are what the game sets (each cue's level against its full level, the read-outs, the audit's readings of Master), not what a listener perceives. What remains for your ears is said under each question.

**The encounter, moment by moment** (times in seconds from the moment the entity heard; Viv about 10 u away and in the same open space when it heard, then the entity ran to her). Screenshots of the read-out, full size, in `~/Library/Application Support/Godot/app_userdata/Requiem/screenshots/`: `final_0_unaware.png`, `final_1_heard.png`, `final_2_hunting.png`, `final_3_lost.png`, `final_4_gave_up.png` (they are outside the repository).

| Time | What it knows (`Dread.awareness`) | Channel A cue (set) | Music | World mix (Ambience/World, Body) | Viv's heart / breathing | House voice |
|---|---|---|---|---|---|---|
| before | UNAWARE, threat 0.00 | — | drone (EXPLORE) | −3 dB / +0.9 dB (presence only) | heart 0.00; calm breath | settling, next effect in 108 s |
| 0.0 | HEARD | heard-you (`entity/heard_voice`) + neck click (`entity/neck_click`), at full level (0 dB) | silent (HEARD) within 0.1 s | −3.2 / +1.0 | heart starts; breath turning nervous (23 %) | silent: "it is alert (heard)" |
| 0.87 | (still listening) | inhale (`entity/inhale`) | silent | Music/Ambience/World duck 14 dB for the scream | — | silent |
| 1.06 | HUNTING, threat 1.00 | scream (`entity/scream`) + stomp (`entity/foot_slam`, −1.1 dB against full) | hunt music with the scream | −10 / +3.0 | heart 0.63 (threat), about −13 dB; nervous breath | silent: "it is alert (hunting)" |
| 7.2 | SEARCHING, threat 0.76 falling to 0.7 | lost (`entity/lost`), then one sniff (`entity/sniff`) 2.4 s later, full level | thin search tone | −7.6 / +2.3 | heart 0.47 (threat); nervous | silent: "it is alert (searching)" |
| 12.2 | UNAWARE, back on patrol | stand-down (`entity/stand_down`), full level | drone returning (EXPLORE) | −5.0 / +1.5, easing back | heart 0.22 (presence, it is next to her); calm again | silent: "it is near (ring 2/3)" |

The warning before the first loud sound (the scream) was 1.06 s of heard-you cue and silence (the rule is at least 0.7 s). The loudest Master reading over the whole encounter was −1.1 dB (the limiter's ceiling is −1 dB). A second encounter a few minutes later gave the same order: heard → inhale 0.58 s → scream and stomp 0.78 s → lost 3.4 s (key 2 skipped the hunt) → sniff → stand-down.

**1. Can I tell it heard something? That it is hunting? That it lost me? That it gave up?**
Measured: each of the four moments has its own sound, from four different sets: `heard_voice` with the neck click and a hard silence after (and the music cuts out); `inhale` → `scream` → `foot_slam` (the hunt music starts with it, the house ducks 14 dB); `lost` (a groan) then one `sniff` (the music thins to a tone); `stand_down` (a slow exhale; the drone comes back over 6–8 s). No two moments share a set. Each played at full level here; the suites (`test_awareness`) check that from every distance and position a detection can come from, the heard-you cue is never quieter than −20 dB against full, and the scream, lost and stand-down never fall below their floors (−14, −15, −15 dB).
For your ears: the four are different files, but whether `lost` (a groan) and `stand_down` (a slowed exhale) are told apart easily at a distance, and whether the two near-twin screams feel like one sound, is yours to judge.

**2. Near it (ring 3), can I tell what it is doing?**
Measured over about 50 s beside the walking entity (unaware patrol): 41 claw steps (`claws_walk`), 4 mumbled phrases (`mumble`), 7 claw taps (`pat_tap`, only in its pauses), its calm breathing loop (`breath_calm`, about −11 dB) and its cloth drag (`drag`, while it moves). Over the 8.5 s from a second heard-you cue to the end of its search, beside it: 8 scrapes (`claw_scrape`, one of them the scrape that follows the heard-you cue), 5 scuttling steps (`claws_scuttle`), 4 sniffs (`sniff`, the first is the one after 'lost') and one running step (`claws_run`), no mumbling. Hunting: running steps (`claws_run`) and its hunting breath. So walking, standing (taps, breathing, no steps), searching (scuttle, scrapes, sniffs) and hunting each have their own sets. In ring 3 everything plays, at full level, undulled, placed exactly (read-out: "position sounds −0 dB · 0 % dulled · placed 100 %").
For your ears: whether the taps of a pause read as "it stopped" and the sniffing as "it is searching".

**3. A room away, am I unable to point to it unless I stand still or hold my breath?**
Measured with the entity held on the kitchen side of the kitchen door and Viv in the next room, a wall between them:

| Where Viv is | Standing | Walking | Sprinting | Holding her breath |
|---|---|---|---|---|
| Ring 2, 8 u by ear (7.6 u straight) | −7 dB, 29 % dulled, placed 100 % | — | — | −5 dB, placed 100 %, ring 1 reaches 23.4 u instead of 18 |
| Ring 1, 12–15 u by ear | −11 to −14 dB, 59–76 % dulled, placed 59–77 % | her steps cover 3 dB more after 0.9 s (6 dB when settled) | her steps cover 12 dB | −9 dB, placed 85 %, reach 23.4 u, half the gaps closed |

In both places the read-out said `heard from: the doorway (left)`: its sounds were placed at the doorway (about 1.8 u from the entity, towards the opening), at the entity's real distance, not straight through the wall. While she held her breath the music also dropped 5 dB and Music, Ambience and World went soft (2500 Hz). In ring 1 some of its sounds are dropped on the way (30–70 % of body sounds get through, more of its voice).
For your ears: whether, walking, a room away is really "somewhere over there" and not a direction, and whether standing still or holding the breath is enough to point to it. This is the question that most needs listening.

**4. Does any loud sound arrive without warning?**
During the two encounters: one sudden rise in the second one, the heard-you cue itself (+22 dB, from −26 to −3.8 dB peak), explained by the audit as the warning; the scream came after it, with 0.78–1.06 s of warning. No other rise in either encounter, and none UNEXPLAINED while the entity was hunting, searching or standing down.
**But**, around the encounters, with the entity unaware and next to her, the audit logged **19 UNEXPLAINED rises** over about 3 minutes (2 of them 4 and 8 s after the second stand-down, as it walked off beside her), all on the Entity bus, **+18 to +21 dB, from the quiet floor (−26 dB) to about −5 to −8 dB peak**:
- 17 came right after one of its claw steps (`entity/claws_walk`) as it walked beside her or up to her (1.3–2 u);
- 1 came while it was held still next to her, 6 s after a mumble (most likely its breathing or a phrase; the audit names the last sound only);
- 1 came just after the audit's list was cleared, so it names no sound.
How often: in the 18 s with Viv still and the entity walking up to her with **the drone away**, 4 rises (none of them right after a teleport). With **the drone back in** and the same spot, 28 s and **no rise** (the entity was walking away from her by then, from 1.7 to 6.6 u, so this is suggestive, not a clean comparison). They all came while the drone was away or still fading in.
This is Step 18's finding, reproduced, with one difference: Step 18 saw it from its breathing and idle taps (`pat_tap`) while it stood; here it came almost all from its steps while it walked, and its taps did not cause one this time. Same cause: in the quietest house its near sounds rise more than 18 dB in one go. **Not fixed**: it is yours to decide (see section 9). One teleport-free way to hear it: Sound Audition, M until the read-out says "no drone", stand still on Viv's starting spot and let it walk up to her.
For your ears: whether a claw step a metre away in a silent house feels like a scare or like the near sound the design wants.

**5. Does any house sound play while the entity is alert or near?**
Measured: no. The audit counted **0 house sounds while gated** over the whole session, and `HouseVoice.violations` stayed **0**. What `HouseVoice.gate()` said at each moment: before, settling (the next effect 108 s away); heard, "it is alert (heard)"; hunting, "it is alert (hunting)"; searching, "it is alert (searching)"; after the stand-down, "it is near (ring 3)" then "(ring 2)" as it walked off; once safe, "it only just became safe" for a few seconds. `test_house_voice` and `test_jump_scare_audit` check every gate in the suites.


---

## 8. Checks

One full run of all 30 suites (`python3 testing/run_checks.py`), 19 November 2026, on `a7254b0` plus this step's docs. The word PASS/FAIL the runner prints is not meaningful (every suite prints harmless "resources still in use" lines); the counts are.

| Suite | Count | Expected |
|---|---|---|
| Menu flow | 34/34 | 34/34 |
| Kiosk | 324/325 | 324/325 (known) |
| Tutorial | 123/123 | 123/123 |
| Doors and rooms | 23/23 | 23/23 |
| Breath events | 36/36 | 36/36 |
| Breath feedback | 49/49 | 49/49 |
| Throw feedback | 70/70 | 70/70 |
| Prayer feedback | 73/73 | 73/73 |
| Sprint feedback | 62/63 | 62/63 (known) |
| Footstep audio | 83/83 | 83/83 |
| Player actions | 56/56 | 56/56 |
| Player motion | 133/133 | 132–134 (varies) |
| Player pose | 24/24 | 24/24 |
| Phantom camera | 166/170 | 166/170 (known) |
| Level | 11/11 | 11/11 |
| Test Lab | 120/121 | 120/121 (known) |
| Audio mix | 56/56 | 56/56 |
| Entity audio | 45/45 | 45/45 |
| Awareness | 76/76 | 76/76 |
| Idle voice | 33/34, then 34/34 alone | 34/34 (known flake) |
| Threat | 64/64 | 64/64 |
| Acoustics | 48/48 | 48/48 |
| Rings | 68/68 | 68/68 |
| Body audio | 100/100 | 100/100 |
| House voice | 96/96 | 96/96 |
| Sparse music | 34/34 | 34/34 |
| Jump-scare audit | 64/64 | 64/64 |
| Heart | 34/34 | 34/34 |
| Prayer audio | 48/48 | 48/48 |
| Entity knock | 57/57 | 57/57 |

**Known failures** (they predate the audio work or sit outside it; unchanged):
- Kiosk: "The last shot brings out the entity".
- Sprint feedback: "Every sprint source, movement, effect and interruption scenario completes" (a script error in the test itself: `test_sprint_feedback.gd` line 253 reads `position` on a Dictionary).
- Phantom camera (4): "Camera settles within the existing 1.15-second reveal", "Attack reaches its original blackout timing", "Camera experiment preserves attack completion", "Attack releases the camera to exploration".
- Test Lab: "Real high-exertion holding shows strain and its readable studio status".

**Flakes in this run**: Idle voice, "Inside a run the sniffs come at one steady pace" (the known "sniff pace" flake): it failed once in the full run and passed 34/34 when the suite was run alone. No other suite was below its count. **Nothing new failed.**

**Clean log.** The tutorial (bedroom, about a minute: walking, holding her breath, sprinting) and the Test Lab (Sound Audition, about eight minutes: walking, holding, the two encounters) ran with **no errors and no warnings** in the game's log. The only lines of note are the audit's own `[JumpAudit] … UNEXPLAINED` reports (question 4 above), which are development output of the Test Lab, not faults. The editor's console holds 35 older error lines, all 3½ hours or more older than these runs, from earlier sessions' half-written scripts (parse errors such as "Identifier not found: HouseVoice" while that file was being written); none appeared during these runs.


---

## 9. Known issues and things left for you

**For your ears or your decision (audio):**

- **Claw taps and breathing next to her (fairness, open).** With the music drone away (the house at its quietest), an unaware entity standing right next to Viv (ring 3) can rise more than 18 dB out of the quiet with its idle claw taps (`entity/pat_tap`) and its breathing; the audit logs these as UNEXPLAINED. You said of the pat_tap rise "Leave it for now". Measured again for this report: see section 7, question 4.
- **The heard-you cue is loud by design.** It rises about 20–25 dB to about −1 dB peak. It is the learnable warning itself, so the audit counts it as explained; listen whether it is too much.
- **Eli's praying** in the tutorial (`tutorial/assets/audio/prayer.wav`) was left alone: is it a "voice saying words"?
- **The answering knock** gets nearer, not louder, because its file is already quieter than every limit (Step 17).
- **The scream** has three files but two of them sound nearly the same: a third distinct take needs a recording.
- **Single-take sets** cannot avoid repeating (section 4).
- **`prepare_sounds.py`** would level raw footstep files to −28 LUFS (breath level) and does not cut takes that hold several steps (Step 13). Drop finished one-step files straight into the folders instead.
- **`SOUND_SETS.md`** will bring back the old panting wording the next time the tool runs, unless the line in your raw-folder README changes (section 3).
- **The door check** of Step 17 calls a private part of Acoustics (`Acoustics._wall_between`) from `house_voice.gd`. It works; it is a tidy-up for later, not a fault.

**For the entity plan (behaviour, not audio; nothing was changed):**

- **The entity can never knock in the house today**: none of its six patrol stops is within 1.5 u of a door (the nearest is about 4 u). It needs a patrol stop by a door, or a larger `entity_knock_door_u`, and files in `entity/knock`.
- **It hunts on the noise of a door it opened itself**: it reacts to its own door noise and goes straight into a hunt.
- **The Sound Audition starts Viv on patrol stop 5**, so the patrolling entity walks into her and gets stuck pressing against her.

**New in this final check:**

- **The fairness rise is wider than thought** (question 4): with the drone away, its own claw steps as it walks beside or up to her rise +18 to +21 dB (to about −5 to −8 dB peak) and are logged UNEXPLAINED, about one every few seconds while it is within 2 u. Before, this was known for its breathing and idle taps while standing. Possible directions, for you to choose (nothing was changed): a slightly lower level for its sounds in ring 3 (`position_full_u`, or `set_gain_db` for `entity/claws_walk`), the house never fully silent while it is near (a quiet bed under the drone's absence), or accept it as the intended "it is right here" and teach the audit that a near entity explains it.
- **Driving the tutorial's first message through the Godot connection**: a simulated E did not dismiss Eli's opening line; calling the tutorial's own `advance_dialogue` did. A tool limit, not a game fault.

---

## 10. File by file

The list comes from `git diff --stat e850ec0..HEAD`: `e850ec0` is the commit just before Step 1 (`f6e52b7`), so this is everything Steps 1–18, the breathing fix and this report changed. `.uid` files are Godot's own id files that come with each new script; they are not listed.

### New sound files
- **`assets/audio/entity/<set>/`, `assets/audio/viv/<set>/`** (181 sound files, 169 for the entity and 12 for Viv, with their import files): the processed sounds of Step 1. Before: none; the entity breathed one NonCommercial file and Viv's breath used two generic clips.
- **`assets/audio/house/settle/`, `house/effects/`, `house/prayer_tone/`, `entity/knock/`, `viv/steps_wood/`, `viv/steps_forest/`** (`.gitkeep` only): the empty folders of section 4, ready for files.
- **`tutorial/assets/audio/new_audio/`**: your raw picks, committed untouched in Step 1 so the script can be re-run.
- **`assets/audio/366137__dcsfx__monster-breathing.wav`** (deleted, with its import file and its line in `tutorial/credits_data.gd`): NonCommercial licence. It was the entity's breathing.
- **`assets/audio/SOUND_SETS.md`** (new): the table of every set (files, lengths, loudness, loops, notes), written by the script.

### New systems (`audio/`)
- **`audio/sound_settings.gd`** + **`audio/sound_settings.tres`** (new): every number of the system, one comment each. Before: numbers were scattered through scripts.
- **`audio/audio_bus.gd`** (new): the bus names in one place.
- **`audio/mix_director.gd`** (new, autoload MixDirector): the only script that changes the mix (ducks, muffles, threat). Before: three scripts touched buses directly.
- **`audio/sound_library.gd`** (new): turns a folder into a set; picks without repeating; warns once on a missing set.
- **`audio/dread.gd`** (new, autoload Dread): what the entity knows (awareness), threat, presence.
- **`audio/acoustics.gd`**, **`audio/acoustic_reading.gd`** (new, autoload Acoustics): how far its sound really travels, ring, clarity, the doorway.
- **`audio/house_voice.gd`** (new, autoload HouseVoice): the house's own sounds, gates, answers, escalation, the door found ajar. Before: a smaller "unease" logic inside `tutorial/tutorial.gd`.

### The entity
- **`entities/entity_audio.gd`** (new): every sound of the entity, both channels, the rings, the doorway, the idle voice, the knock.
- **`entities/entity.tscn`**: EntityAudio added; the NonCommercial breathing, the hunt stinger and the search riser taken out. Before: those three files were assigned there.
- **`entities/entity_ai.gd`**: its old players moved to the Entity bus and kept silent while EntityAudio exists. Before: it played its own clip arrays on SFX.
- **`tutorial/entity.gd`**: two signals added (`listen_started`, `stood_down`) so the sound knows the moment. No timing changed.

### Viv
- **`player/body_audio.gd`** (new): her breathing loops, listening, self-masking, and the parent of her heart and prayer.
- **`player/heart_audio.gd`** (new): her one heart. Before: two heartbeats, one in the music, one in the strain.
- **`player/prayer_audio.gd`** (new): prayer as a state (low-pass, slower breath, heart, optional tone).
- **`player/ears.gd`** (new): her ears, so sound is heard from where she stands. Before: from the camera's centre.
- **`player/player.tscn`**: her own breath sets on HoldBreath (3 breaths in, 2 breaths out, 1 late gasp, 3 forced gasps); the ears and BodyAudio added. Before: `hold_breath.wav` for the breath in and the forced gasp, `exertion.wav` for the gasp, no breath out. When the editor saved the scene it also wrote the ids of two light textures and dropped two `shadow_filter = 0` lines (0 is the default: the look is unchanged).
- **`player/hold_breath.gd`**: plays on Body, no take twice running; the exertion warning number (65 %) declared here once. Noise radii unchanged.
- **`player/breath_strain_audio.gd`**: its low-pass goes through MixDirector; its heartbeat removed (the tone stays). Before: it set the filter itself and had its own heart.
- **`player/footstep_audio.gd`**: steps by surface, falling back to concrete. Before: concrete only.
- **`player/flashlight.gd`**, **`player/throw.gd`**: on Body / World, no take twice running.

### The house, the music and the tutorial
- **`autoloads/music_director.gd`**: follows what the entity knows (silence when it hears, hunt with the scream, thin tone searching, slow return), a fade time per transition, the drone's own clock. Its threat heartbeat removed. Before: it followed the raw entity state with one 1.4 s crossfade and had a heartbeat.
- **`autoloads/game_over_ui.gd`**: no death stinger. Before: it played `jump_scare_02`.
- **`autoloads/preferences.gd`**: the SFX slider moves World, Body, Entity and EntityFar too.
- **`default_bus_layout.tres`**: the eight buses and their effects. Before: Music, Ambience, SFX, UI.
- **`project.godot`**: the four new autoloads and the bus layout entry (your MCP lines are separate and untouched).
- **`altar/altar.tscn`**: the whispering file removed. **`altar/body_altar.gd`**: plays on World, no take twice running.
- **`level/door/door.gd`**, **`tutorial/chest.gd`**: on World. Nothing else in the door changed.
- **`tutorial/tutorial.gd`**: story sounds on World and through the house voice; the surface per zone; the entity's hidden breathing off in every zone; the house's doors handed to the house voice. Before: its own unease logic, story sounds on SFX, a drag sound on the catch.
- **`tutorial/vital_meters.gd`**: reads the one exertion warning from HoldBreath. Before: its own copy of 65 %.
- **`export_presets.cfg`**: the raw picks are left out of builds.

### Tools
- **`tools/audio/prepare_sounds.py`**, **`tools/audio/prepared_sounds.json`** (new): the sound preparation script and its list of what it made. **`tools/.gdignore`** (new): Godot does not import the tools folder.

### Development only (`testing/`, not in builds)
- **`testing/experiments/sound_audition.gd/.tscn`** (new): the Sound Audition. **`testing/test_lab.gd`**: its button, and F3 mentions the audio read-out. **`testing/experiments/prayer_studio.gd`**: no voice, a prayer status line.
- **`testing/tools/noise_debug.gd`**: the F3 audio read-out. **`testing/tools/jump_scare_audit.gd`** (new): the audit.
- **Tests** — new suites (each a `.gd` + `.tscn`): `test_audio_mix`, `test_entity_audio`, `test_awareness`, `test_idle_voice`, `test_dread`, `test_acoustics`, `test_rings`, `test_body_audio`, `test_house_voice`, `test_sparse_music`, `test_jump_scare_audit`, `test_heart`, `test_prayer_audio`, `test_entity_knock`. Extended: `test_footstep_audio` (surfaces), `test_tutorial` (surfaces, longer wait for two house sounds), `test_test_lab` (the audition, the prayer studio). `testing/run_checks.py`: the new suites registered.

### Docs
- **`assets/audio/AUDIO_REPORT.md`** (new): this report.
- **`testing/README.md`**: how to use the audition, the read-out, the audit, and what each suite checks.
- **`docs/AUDIO_ASSET_CHECKLIST.md`**, **`docs/AUDIO_SPOTTING.md`** (this step): the passages that still described two heartbeats, the stingers, the monster breathing and the altar's clip now say what the game does (one heart, prayer without voices, no stingers). The rest is as you wrote it.
- **`docs/AUDIO_TEST_PLAN.md`** (this step): the list of audio suites added at the end. Nothing else changed.
