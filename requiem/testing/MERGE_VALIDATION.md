# GitHub alpha merge validation — 2026-10-15

GitHub `origin/alpha` at `508a412` was fast-forwarded into local `main` from `ce8574c`. Both existing local commits remain in history. Existing unfinished art, door-cue work, and the whitespace edit in `tutorial/world.gd` were preserved outside this change.

## Integration fixes

- Use explicit resource paths for the main menu and pause/loading autoloads so a fresh checkout starts reliably.
- Preserve pause-menu visibility through rapid close/reopen, clear it on scene exit, and retain the volume chosen in the main menu.
- Restore the eight synchronized footstep impacts while retaining incoming flashlight, breathing, ambience, and alarm audio.
- Share the torch turn-rate budget between arm movement and wrist correction.
- Clear death and entity audio on reset/exit. Allow the test audio mixer to release stopped playback before quitting.
- Add a real main-menu → threaded load → movement → pause/resume regression and update production-entry checks.

## Validation

Godot 4.7.2 on macOS, Metal Forward+. All 15 suites passed across the final complete run and reruns of the four affected teardown suites. The original complete run reported shutdown resource errors in three suites despite passing their gameplay assertions; their final reruns exited cleanly after the teardown fix.

- [Menu flow tests] 13/13 passed
- [Tutorial tests] 46/46 passed
- [Breath event tests] 36/36 passed
- [Breath feedback tests] 42/42 passed
- [Throw feedback tests] 94/94 passed
- [Prayer feedback tests] 100/100 passed
- [Sprint feedback tests] 87/87 passed
- [Footstep audio tests] 56/56 passed
- [Player action tests] 56/56 passed
- [Player motion tests] 343/343 passed
- [Player pose tests] 48/48 passed
- [Phantom Camera tests] 170/170 passed
- [Level tests] 11/11 passed
- [Test Lab checks] 90/90 passed
- [Light response] 19/19 passed

A fresh temporary copy imported without errors using an empty Godot cache. Manual rendered checks confirmed the main menu, Play transition, bedroom presentation, movement, hold breath, pause and resume. The tutorial regression reaches the ending and checks pickups, stealth failure/retry, the window throw, door unlock, dialogue, attack and return route.

The action test intentionally uses an unpainted template and emits its existing navigation warning. The tested playable content is the introductory tutorial; the nine-night campaign, disk saves and complete gamepad support remain unfinished as documented in the repository README. No export package was produced.

## Reproduce

```sh
python3 testing/run_checks.py --godot /Applications/Godot.app/Contents/MacOS/Godot --rendered
```

Detailed local logs are under `.local-development/final-merge-checks/` and `.local-development/audio-teardown-checks/`.
