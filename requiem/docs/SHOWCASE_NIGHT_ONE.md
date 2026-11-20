# Showcase: night one at the booth

Local test branch `showcase/night-one-test`. It is not pushed and not merged into beta.

**Goal:** a visitor who has never played a game finishes night one in about 15 minutes. It stays scary without jump scares, in the spirit of Darkwood: the dread comes from sound, darkness and what the player does not know, not from being punished.

**Where the settings live:**
- All the numbers are in `tutorial/showcase.gd`.
- `Showcase.enabled = false` turns everything off and gives you the beta exactly as it was.
- The regression tests run with the showcase off. The one exception is `test_showcase`, which sets `force_showcase`.

## What changes, and why

| Problem for a first-time player | Change | Where |
|---|---|---|
| One catch means restarting, which feels unfair and wastes the 15 minutes | The first catch is a near miss. The creature grabs her, she tears free and is shoved away, and the creature is deaf for 6 s and then rests for 30 s. Only a second catch within 60 s kills her. | `tutorial.gd` `_near_miss`, `entity.gd` `rest()` |
| No time to breathe or read | After every hunt (30 s) and after every note (12 s), the creature walks to the far end of its patrol and rests. While resting it hears at half range and ignores contact. | `entity.gd`, `tutorial.gd` `give_breathing_room` |
| Seven altars plus keys is too long | Night one needs only 3 altars: the fountain, the chapel and the tapanco. Tía Rosa already lit the other four. The chapel opens after the fountain. The tapanco note carries Eli's confession, so the reveal still lands. | `mansion_story.gd` |
| "Where do I go?" | Offerings lie in fixed rooms. One objective line says the next step. Marigold petals on the floor lead there, the same petals the forest taught. | `guide_petals.gd`, `hud.gd` `set_objective` |
| The rules are invisible | Every sound she makes ripples on the floor as far as it carries. Her air shows as a ring around her. While the creature listens or hunts, a mark shows where a stone would land. | `showcase_overlay.gd` |
| Running out of breath is a hard fail | Her first forced gasp is soft (radius 2 u). Chests give stones, and she arrives with 3. | `hold_breath.gd`, `tutorial.gd` |
| Prayers are hard to finish under pressure | Prayers take 7 s. Interrupted progress drains slowly instead of resetting. | `mansion_altar.gd` `progress_drain` |
| A Spanish-speaking audience | All text is in Spanish (Mexican, tú). F9 switches between Spanish and English. | `showcase_locale.gd` |
| Checkpoints | Reading a note, taking an offering and placing an offering each save a checkpoint. | `mansion_story.gd` |

## Booth notes
- **F9:** switches between Spanish and English. Anything already on screen stays in its language until it is shown again.
- **Prayer audio:** the showcase altars are wordless (`prayer_spoken = false`), because the voiced prayer is English. A Spanish prayer still needs to be recorded.
- **Not done yet:**
  - controller prompts
  - flashlight auto-aim
  - HUD badges such as ON/OFF/CELL, which stay in English because they are sized for it
