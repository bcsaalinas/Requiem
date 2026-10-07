# Test Lab

Open `res://testing/test_lab.tscn` and run the current scene (F6). F5 always starts the normal tutorial.

## Manual stations

| Station | What it checks |
| --- | --- |
| Play tutorial | Full story, equipment pickup, stealth crossings, rocks/window/latch, retry and ending |
| Character and camera | Same playable tutorial with C for native/Phantom camera, V for locomotion feedback, and 1–5 for area jumps |
| Mechanics sandbox | Painted level template, shared player, active hearing-driven entity and altar; tests shared throwing/prayer outside tutorial scripting |

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

## Captures

`captures/` contains overview, lighting, readability, aspect-ratio/pause, walkthrough and movement capture scenes. Run a selected scene with a rendered viewport. `regression/test_phantom_camera_capture.tscn` adds camera comparison frames. Images use `user://test-results/` via `tools/capture_output.gd`, which creates directories automatically. In Godot, use **Project → Open User Data Folder** to find them. Video output can use Godot Movie Maker with an output path outside tracked source.

Capture images are temporary evidence. Attach useful results to the matching GDD page and label the tested build; do not commit repeated screenshots or recordings into runtime folders. Older Notion videos predate the current directional rig.

## Adding a feature

1. Reuse an existing manual station where possible; put isolated experiments in `experiments/` and expose them through the launcher.
2. Add meaningful regression coverage under `regression/` and register its scene in `run_checks.py`.
3. Keep production scripts independent of `res://testing/`. Test scenes may reference production scenes, never the reverse.
4. After playtest acceptance, integrate only the completed runtime components into the appropriate gameplay scene. Preserve the lab fixture for regression.
5. Update the existing GDD location, Metrics and Bugs; run the affected checks and the core suite before a team handoff.

The export preset excludes `testing/*`. Character source artwork and bake tools live outside the Godot project in `tools/character_rig/`. Addon licenses and imported runtime art remain versioned.
