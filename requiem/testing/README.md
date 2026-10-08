# Test Lab

Open `res://testing/test_lab.tscn` and run the current scene (F6). F5 always starts the normal tutorial.

## Manual stations

| Station | What it checks |
| --- | --- |
| Play tutorial | Full story, equipment pickup, stealth crossings, rocks/window/latch, retry and ending |
| Character and camera | Same playable tutorial with C for native/Phantom camera, V for locomotion feedback, and 1–5 for area jumps |
| Mechanics sandbox | Painted level template, shared player, active hearing-driven entity and altar; tests shared throwing/prayer outside tutorial scripting |
| Breath animation and effects | Safe production hallway/bedroom; real hold/release, movement and aim; low-air/high-exertion presets, equipment and screen-effects comparisons |
| Throw animation | Safe production hallway/bedroom; real finite-rock windup, hand release and follow-through; flashlight absent/off/on, movement, breath and reset |
| Prayer animation | Safe production bedroom with the real altar; kneeling entry, sustained loop, early release, eight headings, flashlight absent/off/on, low-air interruption and full completion |
| Sprint animation and dust | Safe production bedroom, hallway and forest; real walk/run transitions, direction changes, rearward aim, equipment absent/off/on, dust/audio toggles and resource reset |

F1 returns to the launcher, including while paused. Restart test reloads the selected station. F3 toggles emitted-noise visualization within the lab. A ring proves an event was emitted, not that a listener detected it. Scenario switches clear pause, pending input and shared state. Noise controls are absent from the normal game.

Movement: WASD/arrows; Shift sprint; Space hold breath; cursor aim; F flashlight; Q throw. In the tutorial, E interacts, B changes battery, R retries, Escape/H pauses and F11 changes fullscreen. The shared mechanics sandbox uses E to pray near the altar and Tab to select pebble/alarm; R retries after death. Its map is a test fixture, not a campaign level.

## Automated checks

From the repository root:

```sh
python3 requiem/testing/run_checks.py
python3 requiem/testing/run_checks.py --rendered
python3 requiem/testing/run_checks.py --suite test_player_pose
```

Python uses only the standard library. Set `--godot` or the `GODOT` environment variable for a custom executable. Each suite starts a separate Godot process. Nonzero exit, script errors, missing success summary and timeout fail the run. Logs default to ignored `requiem/.local-development/test-results/`; `--output` changes that location. On Linux the runner isolates Godot user data under that output directory.

The core run covers tutorial progression, player actions, motion, dense pose sweeps, camera, level authoring and lab lifecycle. Lighting requires a rendered viewport; headless checks cannot validate its pixels. The launcher is for manual checks; automated suites remain separate processes because their scripts intentionally quit when complete.

Breath coverage includes accepted action events, noise/resource parity, rearming after a forced gasp, authored upper-body playback, pause/dialogue/death interruptions and frame-matched hand/beam alignment. The 1,106 sampled breath poses cover all headings with equipment absent, off and on. Screen effects add no gameplay noise. The original lower-body sheets and footstep timing remain unchanged.

In Breath Studio, presets set actual starting resources. Hold Space to play the real mechanic, release above 20% for a controlled exhale, or hold through depletion to see forced recovery. After a forced gasp, release Space before starting another hold. R resets the studio. Effects on/off compares the paired strokes and edge shade; character animation and vital signs remain active. No story listener or enemy interrupts this station.

Throw Studio starts with three rocks. Q uses the actual 0.5-second windup and one-second cooldown; R clears pending/released rocks and refills the finite inventory. The character releases from her animated left palm and settles during the first 0.32 seconds of cooldown. Cursor aim commits when the throw begins, including before flashlight pickup. Equipment cycles through absent, off and on; area selection swaps between the real hallway and bedroom. The existing movement, hold-breath and pause controls remain active. Impacts produce their normal noise but cannot trigger story progression in this station. Use the mechanics sandbox to review the shared pebble/alarm inventory.

`test_throw_feedback` covers accepted/denied starts, exact release/socket timing, committed target and item, inventory/cooldown/noise parity, priority interruptions, pause/reset, moving/held throws, unarmed rearward throws and transformed parents. Its 1,936 authored pose samples check all headings and aim modes with flashlight absent/off/on, fixed boots, beam placement and the bounded wrist. A blocked hand socket falls back to the center trajectory without changing the committed landing.

Prayer Studio uses the real altar: hold E for 12 consecutive seconds, or release E to reset progress and play the short rise. R resets the ritual and resources. The low-air preset sets 25% lung; hold E and Space to review forced gasp taking visual priority while prayer continues. Equipment cycles absent/off/on, and the facing selector places the character around the altar in all eight headings. The character turns toward the accepted altar through the existing aiming and foot-pivot response. Normal release unlocks movement immediately; the 0.38-second rise adds no action lock. The tutorial still reserves prayer for its scripted friend demonstration.

`test_prayer_feedback` checks accepted altar ownership, real elapsed time, matched partial release/re-entry, hearing/completion parity, breath/throw priority, pause, death, disabled input, source deletion, reset and teleport. Its 2,112 pose samples check all authored modes, folded feet behind the body, standing endpoints, lens registration and the wrist limit. Prayer uses its own lower-body sheets and returns to the shared locomotion foot solver.

Sprint Studio starts in the lit bedroom. WASD/arrows and Shift drive the real movement; move the cursor through opposite and sideways headings to review independent foot placement. Area selection also offers the hallway and forest. Equipment cycles absent/off/on, the dust toggle isolates the new ground effect, and R resets position, resources and feedback. The new run completes a cycle per 103.68 pixels travelled (0.60 seconds at 5.4 u/s), preserving phase when switching to/from walking. Dust follows visible foot plants; speed, exertion and the existing 0.45-second gameplay footstep/noise cadence are unchanged.

`test_sprint_feedback` covers authored sprint geometry, every gait transition phase, full-aim movement/reversal sweeps, actual-distance playback, planted-foot/toe stability, fixed hand/beam registration, world-space dust and lifecycle cleanup. It also checks real throw, breath and prayer overlaps and compares movement, exertion and hearing with sprint presentation enabled/disabled.

## Captures

`captures/` contains overview, lighting, readability, aspect-ratio/pause, walkthrough and movement capture scenes. Run a selected scene with a rendered viewport. `regression/test_phantom_camera_capture.tscn` adds camera comparison frames. Images use `user://test-results/` via `tools/capture_output.gd`, which creates directories automatically. In Godot, use **Project → Open User Data Folder** to find them. Video output can use Godot Movie Maker with an output path outside tracked source.

`captures/breath_feedback_capture.tscn` records a repeatable real-input breath sequence and saves ten stills under `user://test-results/breath/`. Its internal 1280 × 720 viewport keeps review framing consistent even when a tiling desktop resizes the window. It does not change production window settings.

`captures/throw_feedback_capture.tscn` records real equipped, unarmed and moving breath-held throws and saves eleven stills under `user://test-results/throw/`. Release stills wait for the actual release event. For Movie Maker, pass `--resolution 1280x720 --fixed-fps 60 --write-movie` with a path in `.local-development/throw-review/`. Generated source contact sheets live in the ignored `testing/captures/throw_review/` folder.

`captures/prayer_feedback_capture.tscn` records actual E/Space input, early release, absent/off/on equipment, gasp continuation and a full twelve-second ritual. Eleven stills and a state-evidence JSON go to ignored `.local-development/prayer-review/`; `-- --capture-dir=/absolute/path` selects another destination. Source contact sheets live under ignored `testing/captures/prayer_review/`.

`captures/sprint_feedback_capture.tscn` records real walk/run input, diagonal/rearward movement, direction reversals, equipment states, dust and wall blocking. Stills and evidence go to ignored `.local-development/sprint-review/`; the internal viewport is 1280 × 720. Source contact sheets live under ignored `testing/captures/sprint_review/`.

Capture images are temporary evidence. Attach useful results to the matching GDD page and label the tested build; do not commit repeated screenshots or recordings into runtime folders. Older Notion videos predate the current directional rig.

## Adding a feature

1. Reuse an existing manual station where possible; put isolated experiments in `experiments/` and expose them through the launcher.
2. Add meaningful regression coverage under `regression/` and register its scene in `run_checks.py`.
3. Keep production scripts independent of `res://testing/`. Test scenes may reference production scenes, never the reverse.
4. After playtest acceptance, integrate only the completed runtime components into the appropriate gameplay scene. Preserve the lab fixture for regression.
5. Update the existing GDD location, Metrics and Bugs; run the affected checks and the core suite before a team handoff.

The export preset excludes `testing/*`. Character source artwork and bake tools live outside the Godot project in `tools/character_rig/`. Addon licenses and imported runtime art remain versioned.

## Footstep audio synchronization

Sprint Studio also provides Steps on/off. Eight short mono WAV impacts are triggered by visible foot plants for walking, sprinting and held breath. Sprint uses +2.5 dB and held breath -8 dB relative to walking, with subtle nonrepeating variation. Hearing remains on the existing independent 0.45/0.70-second gameplay cadence. Stop lets the last short tail finish; wall pushing, idle pivots, prayer and forced recovery produce no new steps. Death, reset, disabled input and teleport clear voices.

`test_footstep_audio` checks contact/frame agreement, actual audible cadence, sample variation, world-space playback, lifecycle silence and unchanged hearing/movement/exertion with audio muted. `captures/footstep_audio_capture.tscn` records an explicitly labeled reenactment of the old long-file restart followed by actual synchronized walking, sprinting, held movement, turns, stops and walls. MovieMaker records the engine audio, with ambience muted only for this comparison. Output goes to `.local-development/footstep-review/`. Regeneration and source provenance: `tools/audio/README.md` at repository root.
