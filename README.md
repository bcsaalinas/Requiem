# Requiem

Godot 4.7 project. Open `requiem/project.godot` and allow the initial asset import to finish.

## Play and test

- **F5 — playable build:** `requiem/tutorial/main_menu.tscn` → Play → The First Breath.
- **F6 — development:** open `requiem/testing/test_lab.tscn`. This is the single entry for manual feature checks, camera comparison and the mechanics sandbox.
- **Automated checks:** `python3 requiem/testing/run_checks.py`. Add `--rendered` for GPU lighting checks with an available display. Use `--godot /path/to/godot` if needed.

The [Test Lab guide](requiem/testing/README.md) covers controls, captures and adding experiments. Gameplay is not switched to a test scene for a handoff. The export preset excludes `testing/*`.

## Main menu

Play loads the tutorial with Retry / Back to Menu on failure. Settings groups Audio,
Controls (reference only) and Display (fullscreen/windowed); audio and display preferences
are saved in `user://preferences.cfg` and shared with gameplay. Credits opens a cinematic automatic roll in `requiem/tutorial/credits.tscn`: team,
verified audio author handles, and engine/tool acknowledgements. Back/Esc exits at any
time, and the roll returns to the menu when finished. Licenses pauses the roll to read
complete notices. Team/resource text remains editable on the main menu script; established
credits live in `credits_data.gd`. Quit asks for confirmation, with Cancel focused first.
Escape returns one page, or opens Quit from the main menu. F11 toggles and saves fullscreen.
There is no Continue option or persistent gameplay save.

## Show-floor build

- Boots to the main menu in fullscreen at a 1280×720 canvas presented at 1080p (the window cannot be resized).
- R / controller Select returns a run straight to the title screen (`autoloads/kiosk.gd`).
- After 60 seconds without input the build hands the screen to attract mode (`tutorial/attract_mode.tscn`); any input returns to the title. Loading is excluded, and only the production scenes are watched.
- Instructions, dialogue and vital captions keep a 2 m legibility floor (`UIPalette.MIN_TEXT_SIZE`). Confirm on the actual monitor.
- Safety killzones (`tutorial/safety_killzones.gd`) keep the player from leaving the playable area.

`test_kiosk` covers fast reset, the idle timer, attract mode, the killzones, the 1080p lock and the text floor.

## Project layout

| Location | Purpose |
| --- | --- |
| `requiem/tutorial/` | Playable introductory route, authored world, story, HUD and presentation |
| `requiem/player/` | Shared movement, actions, aiming, breathing, throwing and character presentation |
| `requiem/level/` | Reusable level template, wall/prop TileSets and navigation |
| `requiem/entities/`, `altar/`, `autoloads/` | Shared gameplay and state |
| `requiem/testing/` | All manual experiments, regressions, capture tools and debug visualization |

Generated logs, captures, editor caches, machine-local settings and export binaries are not versioned. Historical tutorial images/video remain attached in Notion and recoverable from Git history before this cleanup. 

## Living GDD

- [Requiem Main Hub](https://app.notion.com/p/af438646982282099deb012d81b8eeaf)
- [Introduction/Tutorial: route and teaching beats](https://app.notion.com/p/b4f38646982282efbe37817e28908f31)
- [Player Movement Feedback: current character behavior](https://app.notion.com/p/3f13864698228139be99c9c9ff668526)
- [Debug Tools: testing and validation](https://app.notion.com/p/795386469822820baa2e01707ca07b7c)
- [Bugs](https://app.notion.com/p/213386469822828bb22b01024b0efe9a)
- [Version Control: team handoff](https://app.notion.com/p/bcc38646982283ba8d68016edabd40c5)

Record level-specific behavior in its level page, shared behavior in Mechanics/Systems, numeric tuning in Metrics, narrative in Narrative Design and defects in Bugs. Mark prototypes and unimplemented design explicitly.

## Current limits

The tutorial is playable; the nine-night campaign, disk saves, complete gamepad support, full vision-cone gameplay and dedicated breath/gasp/throw/prayer/death clips are unfinished. Phantom Camera remains an experiment. Existing open tutorial issues: partially filled rock inventory can exceed its intended cap (TUT-01); the final interaction does not require Hold Breath (TUT-02).
