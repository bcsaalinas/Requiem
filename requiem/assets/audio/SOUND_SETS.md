# Sound sets

Written by `tools/audio/prepare_sounds.py`. Do not edit: run the script again instead.
Raw picks: `tutorial/assets/audio/new_audio/`. Game files: this folder.

Every file is mono, 48 kHz, with a true peak of -1 dB or lower. One-shots are WAV and start
within 10 ms; loops are OGG with loop enabled in their import settings.

**Loudness** is integrated loudness (ITU-R BS.1770) of the mono file: a one-shot is measured played
once with silence around it, a loop is measured going round. **Peak** is the true peak.
Rumble under 25 Hz is filtered out first: nobody hears it, and it eats the headroom the
audible part needs. To reach a target, peaks are limited by 6 dB at most; a sound that is one
sharp click or thud stays under its target instead.

## Overview

| Set | Files | Kind | Target | Measured | Lengths |
|---|---|---|---|---|---|
| `entity/breath_calm` | 1 | loop | -24 | -24.0 | 7.72 s |
| `entity/breath_hunt` | 2 | loop | -24 | -24.0 | 5.73-7.67 s |
| `entity/catch_grab` | 1 | whole | -16 | -17.4 | 1.72 s |
| `entity/claw_scrape` | 21 | stroke | -20 | -24.5 to -20.0 | 0.35-0.83 s |
| `entity/claws_run` | 36 | slice | -20 | -22.8 to -20.0 | 0.15-0.25 s |
| `entity/claws_scuttle` | 13 | slice | -20 | -20.8 to -20.0 | 0.16-0.28 s |
| `entity/claws_walk` | 13 | slice | -20 | -20.3 to -20.0 | 0.18-0.36 s |
| `entity/cloth_fall` | 1 | whole | -20 | -28.3 | 3.65 s |
| `entity/drag` | 1 | loop | -24 | -24.0 | 6.15 s |
| `entity/exhale` | 1 | whole | -20 | -20.0 | 3.92 s |
| `entity/foot_slam` | 2 | whole | -16 | -22.9 to -18.6 | 1.10-1.17 s |
| `entity/heard_voice` | 3 | whole | -20 | -20.0 | 1.73-2.00 s |
| `entity/inhale` | 1 | whole | -16 | -16.0 | 1.90 s |
| `entity/lost` | 2 | whole | -20 | -20.1 to -20.0 | 4.81-5.90 s |
| `entity/mumble` | 20 | phrase | -24 | -24.1 to -24.0 | 1.21-7.78 s |
| `entity/neck_click` | 2 | whole | -20 | -27.4 to -24.7 | 0.34-0.43 s |
| `entity/pat_tap` | 7 | slice | -20 | -31.5 to -22.5 | 0.15-0.18 s |
| `entity/scream` | 3 | scream | -12 | -12.1 | 1.60-1.60 s |
| `entity/sniff` | 2 | whole | -20 | -20.1 to -20.0 | 4.99-8.39 s |
| `entity/sob_stops` | 1 | whole | -20 | -20.1 | 2.62 s |
| `viv/calm` | 1 | loop | -32 | -32.0 | 6.91 s |
| `viv/exhale` | 2 | whole | -28 | -28.0 | 1.66-2.79 s |
| `viv/forced_gasp` | 3 | whole | -24 | -24.0 | 1.86-4.85 s |
| `viv/gasp` | 1 | whole | -28 | -28.0 | 1.43 s |
| `viv/hold_in` | 3 | whole | -28 | -28.0 | 0.43-0.98 s |
| `viv/nervous` | 1 | loop | -32 | -32.0 | 7.83 s |
| `viv/panic` | 1 | loop | -24 | -24.0 | 7.17 s |
| `entity/stand_down` | 1 | whole | -20 | -20.0 | 3.00 s |

## Worth a listen

- `entity/catch_grab` (from `entity_catch_grab_01.mp3`): source clips (46 samples at full scale)
- `entity/catch_grab/entity_catch_grab_01.wav`: 1.4 LU under target (peaks already limited by 6 dB)
- `entity/claw_scrape` (from `entity_claw_scrape_01.mp3`): the source holds 4 continuous drags (up to 3.5 s), not separate scrapes: each is cut at its quietest moments into strokes under 0.8 s, with soft fades
- `entity/claw_scrape` (from `entity_claw_scrape_01.mp3`): 3 of 13 files: quiet source, so its background comes up with it (to -33 dB at worst)
- `entity/claw_scrape/entity_claw_scrape_01_08.wav`: 4.5 LU under target (peaks already limited by 6 dB)
- `entity/claw_scrape` (from `entity_claw_scrape_02.mp3`): the source holds 3 continuous drags (up to 2.8 s), not separate scrapes: each is cut at its quietest moments into strokes under 0.8 s, with soft fades
- `entity/claw_scrape/entity_claw_scrape_02_08.wav`: peaks limited by 6.0 dB
- `entity/claws_run` (from `entity_claws_run_01.mp3`): 9 of 36 files are under the loudness target, by up to 2.8 LU (sharp clicks: their peaks are already limited)
- `entity/claws_run` (from `entity_claws_run_01.mp3`): 7 of 36 files: quiet source, so its background comes up with it (to -30 dB at worst)
- `entity/claws_run` (from `entity_claws_run_01.mp3`): 7 of 36 files had their peaks limited by up to 6.0 dB
- `entity/claws_scuttle` (from `entity_claws_scuttle_01.mp3`): 1 faint hit left out (6 dB or more under the rest of the take)
- `entity/claws_scuttle` (from `entity_claws_scuttle_01.mp3`): 3 of 13 files are under the loudness target, by up to 0.8 LU (sharp clicks: their peaks are already limited)
- `entity/claws_scuttle` (from `entity_claws_scuttle_01.mp3`): 2 of 13 files had their peaks limited by up to 6.0 dB
- `entity/claws_walk` (from `entity_claws_walk_01.mp3`): 1 faint hit left out (6 dB or more under the rest of the take)
- `entity/claws_walk` (from `entity_claws_walk_01.mp3`): 2 of 13 files had their peaks limited by up to 6.0 dB
- `entity/cloth_fall/entity_cloth_fall_01.wav`: 8.3 LU under target (peaks already limited by 6 dB)
- `entity/foot_slam` (from `entity_foot_slam_01.mp3`): source clips (9 samples at full scale)
- `entity/foot_slam/entity_foot_slam_01.wav`: 2.6 LU under target (peaks already limited by 6 dB)
- `entity/foot_slam` (from `entity_foot_slam_deep_01.mp3`): source clips (9 samples at full scale)
- `entity/foot_slam/entity_foot_slam_deep_01.wav`: 6.9 LU under target (peaks already limited by 6 dB)
- `entity/mumble` (from `entity_mumble_lullaby_01.mp3`): 7.8 s without a pause to cut at: kept as one phrase
- `entity/neck_click/entity_neck_click_01.wav`: 4.7 LU under target (peaks already limited by 6 dB)
- `entity/neck_click/entity_neck_click_02.wav`: 7.4 LU under target (peaks already limited by 6 dB)
- `entity/pat_tap` (from `entity_pat_tap_01.mp3`): 5 faint hits left out (6 dB or more under the rest of the take)
- `entity/pat_tap` (from `entity_pat_tap_01.mp3`): 4 of 4 files are under the loudness target, by up to 7.1 LU (sharp clicks: their peaks are already limited)
- `entity/pat_tap/entity_pat_tap_01_01.wav`: quiet source: its background comes up to -32 dB
- `entity/pat_tap` (from `entity_pat_tap_02.mp3`): 2 faint hits left out (6 dB or more under the rest of the take)
- `entity/pat_tap` (from `entity_pat_tap_02.mp3`): 3 of 3 files are under the loudness target, by up to 11.5 LU (sharp clicks: their peaks are already limited)
- `entity/scream/entity_scream_full_01.wav`: peaks limited by 5.8 dB
- `entity/sniff/entity_sniff_steady_01.wav`: 20 separate sounds in a row, kept whole as one file
- `entity/sniff` (from `entity_sniff_voice_01.mp3`): source clips (191 samples at full scale)
- `entity/sob_stops/entity_sob_stops_01.wav`: peaks limited by 3.6 dB

## entity/breath_calm

Plays: Breathing loop while calm  
Kind: loop (OGG, crossfaded ends, loop on in the import settings). Target: -24 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_breath_calm_01.ogg` | 7.72 | -24.0 | -2.0 | yes | `entity_breath_calm_01.mp3` | loops 0.95-8.67 s of the source, 50 ms crossfade inside a pause |

## entity/breath_hunt

Plays: Breathing loop while hunting  
Kind: loop (OGG, crossfaded ends, loop on in the import settings). Target: -24 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_breath_hunt_01.ogg` | 5.73 | -24.0 | -2.7 | yes | `entity_breath_hunt_01.mp3` | loops 3.84-9.57 s of the source, 50 ms crossfade inside a pause |
| `entity_breath_hunt_02.ogg` | 7.67 | -24.0 | -2.9 | yes | `entity_breath_hunt_02.mp3` | loops 0.29-7.96 s of the source, 40 ms crossfade inside a pause |

## entity/catch_grab

Plays: The grab when it catches Viv  
Kind: one-shot, kept whole. Target: -16 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_catch_grab_01.wav` | 1.72 | -17.4 | -1.2 | no | `entity_catch_grab_01.mp3` | source clips (46 samples at full scale); 1.4 LU under target (peaks already limited by 6 dB) |

## entity/claw_scrape

Plays: Claws dragged on the floor (listening, feeling the floor)  
Kind: sliced one-shots (one scrape stroke per file). Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_claw_scrape_01_01.wav` | 0.77 | -20.0 | -1.3 | no | `entity_claw_scrape_01.mp3` | the source holds 4 continuous drags (up to 3.5 s), not separate scrapes: each is cut at its quietest moments into strokes under 0.8 s, with soft fades |
| `entity_claw_scrape_01_02.wav` | 0.63 | -20.0 | -5.7 | no | `entity_claw_scrape_01.mp3` |  |
| `entity_claw_scrape_01_03.wav` | 0.54 | -20.1 | -1.2 | no | `entity_claw_scrape_01.mp3` | quiet source: its background comes up to -35 dB |
| `entity_claw_scrape_01_04.wav` | 0.65 | -20.0 | -3.4 | no | `entity_claw_scrape_01.mp3` |  |
| `entity_claw_scrape_01_05.wav` | 0.36 | -20.0 | -4.4 | no | `entity_claw_scrape_01.mp3` | quiet source: its background comes up to -33 dB |
| `entity_claw_scrape_01_06.wav` | 0.36 | -20.0 | -2.6 | no | `entity_claw_scrape_01.mp3` | quiet source: its background comes up to -36 dB |
| `entity_claw_scrape_01_07.wav` | 0.35 | -20.0 | -2.3 | no | `entity_claw_scrape_01.mp3` |  |
| `entity_claw_scrape_01_08.wav` | 0.40 | -24.5 | -1.3 | no | `entity_claw_scrape_01.mp3` | 4.5 LU under target (peaks already limited by 6 dB) |
| `entity_claw_scrape_01_09.wav` | 0.54 | -20.0 | -2.5 | no | `entity_claw_scrape_01.mp3` |  |
| `entity_claw_scrape_01_10.wav` | 0.71 | -20.0 | -1.3 | no | `entity_claw_scrape_01.mp3` |  |
| `entity_claw_scrape_01_11.wav` | 0.83 | -20.0 | -3.5 | no | `entity_claw_scrape_01.mp3` |  |
| `entity_claw_scrape_01_12.wav` | 0.53 | -20.0 | -4.1 | no | `entity_claw_scrape_01.mp3` |  |
| `entity_claw_scrape_01_13.wav` | 0.47 | -20.0 | -5.1 | no | `entity_claw_scrape_01.mp3` |  |
| `entity_claw_scrape_02_01.wav` | 0.77 | -20.0 | -1.8 | no | `entity_claw_scrape_02.mp3` | the source holds 3 continuous drags (up to 2.8 s), not separate scrapes: each is cut at its quietest moments into strokes under 0.8 s, with soft fades |
| `entity_claw_scrape_02_02.wav` | 0.69 | -20.0 | -1.7 | no | `entity_claw_scrape_02.mp3` |  |
| `entity_claw_scrape_02_03.wav` | 0.63 | -20.0 | -6.0 | no | `entity_claw_scrape_02.mp3` |  |
| `entity_claw_scrape_02_04.wav` | 0.71 | -20.0 | -6.7 | no | `entity_claw_scrape_02.mp3` |  |
| `entity_claw_scrape_02_05.wav` | 0.68 | -20.0 | -5.5 | no | `entity_claw_scrape_02.mp3` |  |
| `entity_claw_scrape_02_06.wav` | 0.39 | -20.0 | -3.1 | no | `entity_claw_scrape_02.mp3` |  |
| `entity_claw_scrape_02_07.wav` | 0.75 | -20.0 | -5.5 | no | `entity_claw_scrape_02.mp3` |  |
| `entity_claw_scrape_02_08.wav` | 0.79 | -20.1 | -1.3 | no | `entity_claw_scrape_02.mp3` | peaks limited by 6.0 dB |

## entity/claws_run

Kind: sliced one-shots (one hit per file). Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_claws_run_01_01.wav` | 0.18 | -20.1 | -1.3 | no | `entity_claws_run_01.mp3` | 4 of 36 hits land in two parts (claws touching down under 0.18 s apart), kept as one hit |
| `entity_claws_run_01_02.wav` | 0.19 | -20.1 | -1.3 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_03.wav` | 0.18 | -20.9 | -1.3 | no | `entity_claws_run_01.mp3` | 0.9 LU under target (peaks already limited by 6 dB); quiet source: its background comes up to -34 dB |
| `entity_claws_run_01_04.wav` | 0.19 | -20.1 | -1.3 | no | `entity_claws_run_01.mp3` | peaks limited by 4.5 dB; quiet source: its background comes up to -34 dB |
| `entity_claws_run_01_05.wav` | 0.19 | -20.0 | -1.9 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_06.wav` | 0.15 | -20.2 | -1.3 | no | `entity_claws_run_01.mp3` | peaks limited by 4.1 dB |
| `entity_claws_run_01_07.wav` | 0.20 | -20.1 | -1.3 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_08.wav` | 0.17 | -21.1 | -1.3 | no | `entity_claws_run_01.mp3` | 1.1 LU under target (peaks already limited by 6 dB); quiet source: its background comes up to -35 dB |
| `entity_claws_run_01_09.wav` | 0.17 | -20.0 | -2.2 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_10.wav` | 0.19 | -20.1 | -1.3 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_11.wav` | 0.17 | -20.0 | -1.3 | no | `entity_claws_run_01.mp3` | peaks limited by 5.1 dB; quiet source: its background comes up to -30 dB |
| `entity_claws_run_01_12.wav` | 0.20 | -22.8 | -1.3 | no | `entity_claws_run_01.mp3` | 2.8 LU under target (peaks already limited by 6 dB) |
| `entity_claws_run_01_13.wav` | 0.20 | -20.0 | -1.6 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_14.wav` | 0.15 | -20.1 | -1.3 | no | `entity_claws_run_01.mp3` | peaks limited by 3.1 dB |
| `entity_claws_run_01_15.wav` | 0.20 | -20.0 | -2.7 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_16.wav` | 0.21 | -20.0 | -1.6 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_17.wav` | 0.21 | -20.0 | -1.3 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_18.wav` | 0.23 | -20.3 | -1.3 | no | `entity_claws_run_01.mp3` | peaks limited by 5.8 dB |
| `entity_claws_run_01_19.wav` | 0.17 | -20.0 | -1.5 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_20.wav` | 0.18 | -22.2 | -1.3 | no | `entity_claws_run_01.mp3` | 2.2 LU under target (peaks already limited by 6 dB) |
| `entity_claws_run_01_21.wav` | 0.17 | -20.0 | -2.2 | no | `entity_claws_run_01.mp3` | quiet source: its background comes up to -36 dB |
| `entity_claws_run_01_22.wav` | 0.15 | -20.0 | -2.4 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_23.wav` | 0.16 | -20.5 | -1.3 | no | `entity_claws_run_01.mp3` | peaks limited by 6.0 dB; quiet source: its background comes up to -32 dB |
| `entity_claws_run_01_24.wav` | 0.18 | -20.9 | -1.3 | no | `entity_claws_run_01.mp3` | 0.9 LU under target (peaks already limited by 6 dB) |
| `entity_claws_run_01_25.wav` | 0.16 | -20.0 | -2.7 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_26.wav` | 0.19 | -22.0 | -1.3 | no | `entity_claws_run_01.mp3` | 2.0 LU under target (peaks already limited by 6 dB) |
| `entity_claws_run_01_27.wav` | 0.16 | -20.1 | -1.3 | no | `entity_claws_run_01.mp3` | quiet source: its background comes up to -35 dB |
| `entity_claws_run_01_28.wav` | 0.19 | -20.0 | -1.3 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_29.wav` | 0.21 | -20.0 | -2.0 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_30.wav` | 0.25 | -21.1 | -1.3 | no | `entity_claws_run_01.mp3` | 1.1 LU under target (peaks already limited by 6 dB) |
| `entity_claws_run_01_31.wav` | 0.20 | -20.0 | -1.3 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_32.wav` | 0.20 | -20.1 | -1.3 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_33.wav` | 0.15 | -20.1 | -1.3 | no | `entity_claws_run_01.mp3` | peaks limited by 3.8 dB |
| `entity_claws_run_01_34.wav` | 0.19 | -22.2 | -1.3 | no | `entity_claws_run_01.mp3` | 2.2 LU under target (peaks already limited by 6 dB) |
| `entity_claws_run_01_35.wav` | 0.16 | -20.0 | -3.4 | no | `entity_claws_run_01.mp3` |  |
| `entity_claws_run_01_36.wav` | 0.15 | -22.5 | -1.3 | no | `entity_claws_run_01.mp3` | 2.5 LU under target (peaks already limited by 6 dB) |

## entity/claws_scuttle

Plays: Crawling steps while it searches (cut into single steps)  
Kind: sliced one-shots (one hit per file). Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_claws_scuttle_01_01.wav` | 0.23 | -20.1 | -1.3 | no | `entity_claws_scuttle_01.mp3` | 1 faint hit left out (6 dB or more under the rest of the take) |
| `entity_claws_scuttle_01_02.wav` | 0.17 | -20.7 | -1.3 | no | `entity_claws_scuttle_01.mp3` | 0.7 LU under target (peaks already limited by 6 dB) |
| `entity_claws_scuttle_01_03.wav` | 0.16 | -20.8 | -1.3 | no | `entity_claws_scuttle_01.mp3` | 0.8 LU under target (peaks already limited by 6 dB) |
| `entity_claws_scuttle_01_04.wav` | 0.17 | -20.1 | -1.3 | no | `entity_claws_scuttle_01.mp3` |  |
| `entity_claws_scuttle_01_05.wav` | 0.19 | -20.0 | -1.8 | no | `entity_claws_scuttle_01.mp3` |  |
| `entity_claws_scuttle_01_06.wav` | 0.20 | -20.2 | -1.3 | no | `entity_claws_scuttle_01.mp3` | peaks limited by 3.5 dB |
| `entity_claws_scuttle_01_07.wav` | 0.20 | -20.0 | -1.8 | no | `entity_claws_scuttle_01.mp3` |  |
| `entity_claws_scuttle_01_08.wav` | 0.19 | -20.1 | -1.3 | no | `entity_claws_scuttle_01.mp3` |  |
| `entity_claws_scuttle_01_09.wav` | 0.21 | -20.7 | -1.3 | no | `entity_claws_scuttle_01.mp3` | 0.7 LU under target (peaks already limited by 6 dB) |
| `entity_claws_scuttle_01_10.wav` | 0.18 | -20.1 | -1.3 | no | `entity_claws_scuttle_01.mp3` |  |
| `entity_claws_scuttle_01_11.wav` | 0.20 | -20.2 | -1.3 | no | `entity_claws_scuttle_01.mp3` | peaks limited by 6.0 dB |
| `entity_claws_scuttle_01_12.wav` | 0.17 | -20.1 | -1.3 | no | `entity_claws_scuttle_01.mp3` |  |
| `entity_claws_scuttle_01_13.wav` | 0.28 | -20.0 | -2.3 | no | `entity_claws_scuttle_01.mp3` |  |

## entity/claws_walk

Plays: Walking steps (several steps per file: cut into single steps)  
Kind: sliced one-shots (one hit per file). Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_claws_walk_01_01.wav` | 0.24 | -20.0 | -2.8 | no | `entity_claws_walk_01.mp3` | 1 faint hit left out (6 dB or more under the rest of the take); 5 of 13 hits land in two parts (claws touching down under 0.18 s apart), kept as one hit |
| `entity_claws_walk_01_02.wav` | 0.36 | -20.1 | -1.3 | no | `entity_claws_walk_01.mp3` |  |
| `entity_claws_walk_01_03.wav` | 0.23 | -20.3 | -1.3 | no | `entity_claws_walk_01.mp3` | peaks limited by 6.0 dB |
| `entity_claws_walk_01_04.wav` | 0.30 | -20.1 | -1.3 | no | `entity_claws_walk_01.mp3` | peaks limited by 5.4 dB |
| `entity_claws_walk_01_05.wav` | 0.24 | -20.1 | -1.3 | no | `entity_claws_walk_01.mp3` |  |
| `entity_claws_walk_01_06.wav` | 0.32 | -20.0 | -3.9 | no | `entity_claws_walk_01.mp3` |  |
| `entity_claws_walk_01_07.wav` | 0.18 | -20.0 | -2.1 | no | `entity_claws_walk_01.mp3` |  |
| `entity_claws_walk_01_08.wav` | 0.29 | -20.0 | -1.3 | no | `entity_claws_walk_01.mp3` |  |
| `entity_claws_walk_01_09.wav` | 0.28 | -20.0 | -1.3 | no | `entity_claws_walk_01.mp3` |  |
| `entity_claws_walk_01_10.wav` | 0.33 | -20.1 | -1.3 | no | `entity_claws_walk_01.mp3` |  |
| `entity_claws_walk_01_11.wav` | 0.31 | -20.0 | -1.5 | no | `entity_claws_walk_01.mp3` |  |
| `entity_claws_walk_01_12.wav` | 0.24 | -20.1 | -1.3 | no | `entity_claws_walk_01.mp3` |  |
| `entity_claws_walk_01_13.wav` | 0.30 | -20.0 | -2.7 | no | `entity_claws_walk_01.mp3` |  |

## entity/cloth_fall

Kind: one-shot, kept whole. Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_cloth_fall_01.wav` | 3.65 | -28.3 | -1.3 | no | `entity_cloth_fall_01.mp3` | 8.3 LU under target (peaks already limited by 6 dB) |

## entity/drag

Kind: loop (OGG, crossfaded ends, loop on in the import settings). Target: -24 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_drag_01.ogg` | 6.15 | -24.0 | -5.2 | yes | `entity_drag_01.mp3` | loops 3.33-9.48 s of the source, 50 ms crossfade inside a pause |

## entity/exhale

Plays: It relaxes / gives up  
Kind: one-shot, kept whole. Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_exhale_01.wav` | 3.92 | -20.0 | -5.1 | no | `entity_exhale_01.mp3` |  |

## entity/foot_slam

Plays: The stomp with the scream  
Kind: one-shot, kept whole. Target: -16 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_foot_slam_01.wav` | 1.17 | -18.6 | -1.2 | no | `entity_foot_slam_01.mp3` | source clips (9 samples at full scale); 2.6 LU under target (peaks already limited by 6 dB) |
| `entity_foot_slam_deep_01.wav` | 1.10 | -22.9 | -1.3 | no | `entity_foot_slam_deep_01.mp3` | source clips (9 samples at full scale); 6.9 LU under target (peaks already limited by 6 dB) |

## entity/heard_voice

Plays: It heard something (the one sound players must learn)  
Kind: one-shot, kept whole. Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_heard_voice_01.wav` | 2.00 | -20.0 | -1.7 | no | `entity_heard_voice_01.mp3` |  |
| `entity_heard_voice_02.wav` | 1.73 | -20.0 | -2.1 | no | `entity_heard_voice_02.mp3` |  |
| `entity_heard_voice_03.wav` | 1.89 | -20.0 | -1.3 | no | `entity_heard_voice_03.mp3` |  |

## entity/inhale

Plays: The breath before the scream  
Kind: one-shot, kept whole. Target: -16 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_inhale_01.wav` | 1.90 | -16.0 | -3.6 | no | `entity_inhale_01.mp3` |  |

## entity/lost

Plays: It lost you (hunt ends)  
Kind: one-shot, kept whole. Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_lost_groan_01.wav` | 4.81 | -20.0 | -5.9 | no | `entity_lost_groan_01.mp3` |  |
| `entity_lost_groan_02.wav` | 5.90 | -20.1 | -7.2 | no | `entity_lost_groan_02.mp3` |  |

## entity/mumble

Plays: Idle talking while it roams and has not heard you (random, every few seconds)  
Kind: idle talking (long takes split at pauses). Target: -24 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_mumble_chant_01_01.wav` | 3.26 | -24.0 | -9.0 | no | `entity_mumble_chant_01.mp3` |  |
| `entity_mumble_chant_01_02.wav` | 2.29 | -24.0 | -8.9 | no | `entity_mumble_chant_01.mp3` |  |
| `entity_mumble_chant_01_03.wav` | 3.65 | -24.0 | -10.0 | no | `entity_mumble_chant_01.mp3` |  |
| `entity_mumble_chant_01_04.wav` | 1.78 | -24.0 | -9.9 | no | `entity_mumble_chant_01.mp3` |  |
| `entity_mumble_chant_01_05.wav` | 3.24 | -24.0 | -9.1 | no | `entity_mumble_chant_01.mp3` |  |
| `entity_mumble_chant_02_01.wav` | 2.28 | -24.0 | -9.0 | no | `entity_mumble_chant_02.mp3` |  |
| `entity_mumble_chant_02_02.wav` | 3.23 | -24.0 | -8.6 | no | `entity_mumble_chant_02.mp3` |  |
| `entity_mumble_chant_02_03.wav` | 5.29 | -24.0 | -7.9 | no | `entity_mumble_chant_02.mp3` |  |
| `entity_mumble_chuckle_01.wav` | 3.46 | -24.0 | -3.9 | no | `entity_mumble_chuckle_01.mp3` |  |
| `entity_mumble_chuckle_02.wav` | 3.27 | -24.1 | -1.3 | no | `entity_mumble_chuckle_02.mp3` |  |
| `entity_mumble_chuckle_03.wav` | 3.24 | -24.0 | -8.1 | no | `entity_mumble_chuckle_03.mp3` |  |
| `entity_mumble_lullaby_01.wav` | 7.78 | -24.0 | -13.8 | no | `entity_mumble_lullaby_01.mp3` | 7.8 s without a pause to cut at: kept as one phrase |
| `entity_mumble_lullaby_02_01.wav` | 1.21 | -24.0 | -11.0 | no | `entity_mumble_lullaby_02.mp3` |  |
| `entity_mumble_lullaby_02_02.wav` | 2.81 | -24.0 | -9.3 | no | `entity_mumble_lullaby_02.mp3` |  |
| `entity_mumble_lullaby_02_03.wav` | 3.54 | -24.0 | -16.6 | no | `entity_mumble_lullaby_02.mp3` |  |
| `entity_mumble_question_01.wav` | 3.23 | -24.0 | -7.9 | no | `entity_mumble_question_01.mp3` |  |
| `entity_mumble_question_02.wav` | 3.56 | -24.0 | -7.3 | no | `entity_mumble_question_02.mp3` |  |
| `entity_mumble_talk_01.wav` | 4.69 | -24.0 | -7.0 | no | `entity_mumble_talk_01.mp3` |  |
| `entity_mumble_talk_02_01.wav` | 5.47 | -24.0 | -7.4 | no | `entity_mumble_talk_02.mp3` |  |
| `entity_mumble_talk_02_02.wav` | 1.75 | -24.0 | -5.8 | no | `entity_mumble_talk_02.mp3` |  |

## entity/neck_click

Plays: The head snap at that same moment  
Kind: one-shot, kept whole. Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_neck_click_01.wav` | 0.43 | -24.7 | -1.1 | no | `entity_neck_click_01.mp3` | 4.7 LU under target (peaks already limited by 6 dB) |
| `entity_neck_click_02.wav` | 0.34 | -27.4 | -1.1 | no | `entity_neck_click_02.mp3` | 7.4 LU under target (peaks already limited by 6 dB) |

## entity/pat_tap

Plays: Claws tapping the floor while it searches  
Kind: sliced one-shots (one hit per file). Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_pat_tap_01_01.wav` | 0.15 | -24.2 | -1.2 | no | `entity_pat_tap_01.mp3` | 5 faint hits left out (6 dB or more under the rest of the take); 4.2 LU under target (peaks already limited by 6 dB); quiet source: its background comes up to -32 dB |
| `entity_pat_tap_01_02.wav` | 0.15 | -25.1 | -1.2 | no | `entity_pat_tap_01.mp3` | 5.1 LU under target (peaks already limited by 6 dB) |
| `entity_pat_tap_01_03.wav` | 0.15 | -27.1 | -1.3 | no | `entity_pat_tap_01.mp3` | 7.1 LU under target (peaks already limited by 6 dB) |
| `entity_pat_tap_01_04.wav` | 0.15 | -26.3 | -1.2 | no | `entity_pat_tap_01.mp3` | 6.3 LU under target (peaks already limited by 6 dB) |
| `entity_pat_tap_02_01.wav` | 0.15 | -22.9 | -1.2 | no | `entity_pat_tap_02.mp3` | 2 faint hits left out (6 dB or more under the rest of the take); 2.9 LU under target (peaks already limited by 6 dB) |
| `entity_pat_tap_02_02.wav` | 0.18 | -22.5 | -1.2 | no | `entity_pat_tap_02.mp3` | 2.5 LU under target (peaks already limited by 6 dB) |
| `entity_pat_tap_02_03.wav` | 0.15 | -31.5 | -1.3 | no | `entity_pat_tap_02.mp3` | 11.5 LU under target (peaks already limited by 6 dB) |

## entity/scream

Plays: Hunt starts  
Kind: scream (loudest second first, 1.6 s at most). Target: -12 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_scream_erupts_01.wav` | 1.60 | -12.1 | -1.3 | no | `entity_scream_erupts_01.mp3` | starts on the attack, 1.02 s into the source; ends in a 0.3 s fade |
| `entity_scream_erupts_02.wav` | 1.60 | -12.1 | -1.3 | no | `entity_scream_erupts_02.mp3` | starts on the attack, 2.31 s into the source; ends in a 0.3 s fade |
| `entity_scream_full_01.wav` | 1.60 | -12.1 | -1.2 | no | `entity_scream_full_01.mp3` | starts on the attack, 0.41 s into the source; ends in a 0.3 s fade; peaks limited by 5.8 dB |

## entity/sniff

Plays: While it searches  
Kind: one-shot, kept whole. Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_sniff_steady_01.wav` | 8.39 | -20.1 | -1.3 | no | `entity_sniff_steady_01.mp3` | 20 separate sounds in a row, kept whole as one file |
| `entity_sniff_voice_01.wav` | 4.99 | -20.0 | -2.7 | no | `entity_sniff_voice_01.mp3` | source clips (191 samples at full scale) |

## entity/sob_stops

Kind: one-shot, kept whole. Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_sob_stops_01.wav` | 2.62 | -20.1 | -1.3 | no | `entity_sob_stops_01.mp3` | peaks limited by 3.6 dB |

## viv/calm

Plays: Breathing loop, calm  
Kind: loop (OGG, crossfaded ends, loop on in the import settings). Target: -32 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `viv_calm_01.ogg` | 6.91 | -32.0 | -13.1 | yes | `viv_calm_01.mp3` | loops 0.17-7.08 s of the source, 50 ms crossfade inside a pause |

## viv/exhale

Plays: She lets go early (quiet)  
Kind: one-shot, kept whole. Target: -28 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `viv_exhale_lips_01.wav` | 1.66 | -28.0 | -14.0 | no | `viv_exhale_lips_01.mp3` |  |
| `viv_exhale_nose_01.wav` | 2.79 | -28.0 | -13.8 | no | `viv_exhale_nose_01.mp3` |  |

## viv/forced_gasp

Plays: She ran out of air (the entity hears this)  
Kind: one-shot, kept whole. Target: -24 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `viv_forced_gasp_01.wav` | 4.85 | -24.0 | -2.0 | no | `viv_forced_gasp_01.mp3` |  |
| `viv_forced_gasp_02.wav` | 1.86 | -24.0 | -8.4 | no | `viv_forced_gasp_02.mp3` |  |
| `viv_forced_gasp_huff_01.wav` | 1.93 | -24.0 | -6.2 | no | `viv_forced_gasp_huff_01.mp3` |  |

## viv/gasp

Plays: She lets go late (louder)  
Kind: one-shot, kept whole. Target: -28 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `viv_gasp_late_01.wav` | 1.43 | -28.0 | -12.3 | no | `viv_gasp_late_01.mp3` |  |

## viv/hold_in

Plays: She starts holding her breath (quick, quiet)  
Kind: one-shot, kept whole. Target: -28 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `viv_hold_in_01.wav` | 0.44 | -28.0 | -12.6 | no | `viv_hold_in_01.mp3` |  |
| `viv_hold_in_02.wav` | 0.98 | -28.0 | -12.9 | no | `viv_hold_in_02.mp3` |  |
| `viv_hold_in_03.wav` | 0.43 | -28.0 | -10.0 | no | `viv_hold_in_03.mp3` |  |

## viv/nervous

Plays: Breathing loop, the entity is alert  
Kind: loop (OGG, crossfaded ends, loop on in the import settings). Target: -32 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `viv_nervous_01.ogg` | 7.83 | -32.0 | -11.5 | yes | `viv_nervous_01.mp3` | loops 0.46-8.29 s of the source, 50 ms crossfade inside a pause |

## viv/panic

Plays: Breathing loop, hunted or sprinting  
Kind: loop (OGG, crossfaded ends, loop on in the import settings). Target: -24 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `viv_panic_01.ogg` | 7.17 | -24.0 | -4.0 | yes | `viv_panic_01.mp3` | loops 0.28-7.45 s of the source, 50 ms crossfade inside a pause |

## entity/stand_down

Built from `entity/exhale`.  
How it differs from `entity/lost`: `entity/stand_down` is 3.0 s of breath noise (its energy sits around 2360 Hz); `entity/lost` is 4.8-5.9 s of voiced sound (its energy sits around 480 Hz).  
Kind: one-shot, kept whole. Target: -20 LUFS.

| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |
|---|---|---|---|---|---|---|
| `entity_stand_down_01.wav` | 3.00 | -20.0 | -6.4 | no | `entity_exhale_01.mp3` | entity_exhale_01.mp3 played 15% slower; cut from 4.6 s to 3.0 s with a 0.8 s fade |
