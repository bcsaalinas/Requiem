# Entity redesign: it listens before it hunts

This page goes with the branch `claude/cool-cannon-oiy4h5` (cut from `beta`). It says what
was researched, what was built from the Notion plan "Entity redesign plan — it listens before
it hunts" (decided 19 Nov), what was left out on purpose, and how to tune and test it.

The Notion plan stays the design source. Where this page and the plan differ, the difference
is listed under "Differences from the Notion plan".

## The problem

The entity felt dull, for reasons that are all in the code:

| What we saw | Why |
| --- | --- |
| Every noise it heard was a hunt | Listening was a delay, not a decision: 0.7–1.2 s, then always the scream. INVESTIGATE existed and nothing reached it. |
| It was nearly deaf | Heard only within radius × 1.25 in a straight line. A walking step reached 3.75 u; the screen is about 24 u wide. |
| Walls and doors meant nothing | Straight-line distance only. |
| It hunted its own doors | A door it pushed open sent a DOOR noise from the doorway it stood in. |
| It gave up fast | A hunt dropped to a search 5 s after the last noise, even before it arrived. The search was 3 points within 4 u, 5 s. |
| Its patrol route wore away | A "revisit" overwrote a patrol marker for good, so after a few noises it only walked between old noise spots. |
| It could get stuck | The path runs through a locked door; the body does not. |
| **In the Hacienda it walked into walls** | Found while testing this branch. The Hacienda's walls are built by script at load, and its navigation mesh was never baked: the scene still held one rectangle over the whole floor. Every path was a straight line through the walls, so the entity ground against the first wall between it and its target. For the same reason sound measured "through the doorways" passed straight through walls there. |

## What the research says

Sources are at the end. Darkwood's enemy rules are documented only by players (guides and
wikis); Acid Wizard has published their thinking on vision and sound, not on enemy AI. Those
points are marked "(player guide)".

### Darkwood

- The developers' pillars are the limited field of view, light and sound. What scares is
  hearing or half-seeing something move without knowing what moved it.
- Enemies announce themselves before they attack, by sound. A Chomper that notices you stops
  and roars for a few seconds, then runs. Dogs bark and growl as a warning, and walking away
  usually avoids the fight. (player guide)
- The Banshee's approach is a ladder of sounds: crows, the music drops to a drone, a shriek,
  then slow heavy footsteps. (player guide)
- Night events are often nothing: knocks, furniture that shifts, a door that opens by itself.
  They share a vocabulary with real threats, so no sound can be fully trusted. (player guide)

What we take: the stop-and-voice beat before every attack; one sound per level of danger;
the house's own knocks staying separate from the entity's (already true in `HouseVoice`).

### Alien: Isolation

- A sound never authorises a kill. Sounds send the creature to a place to investigate; it
  attacks only on sight or contact.
- Sounds have strengths (crouched, walking and running movement; louder events react faster).
- Its search circles the target, visits points in a deliberately bad order so it backtracks,
  and the circle tightens on later passes.
- A director knows where the player is and only ever gives the creature a general area. A
  menace gauge rises while it is close; at the top the director sends it away.
- When it approaches, the environment is turned down and its own sounds are turned up.

What we take: faint noise means "come and look", not "attack"; the search order and the
tightening passes; the director that only hints, with its pressure and back-off.

### Other games with an alert ladder

- **Thief**: awareness rises through a delay (the player's forgiveness window) and falls
  slowly through every step. Fast up, slow down.
- **The Dark Mod**: grace periods of 2–3 s in which new alerts are ignored, so one burst of
  noise counts once.
- **The Last of Us**: sound events have designer radii and are blocked by walls; infected
  that lose you stop to "canvass" and drift back to wandering.
- **Splinter Cell: Blacklist**: sound distance is measured along the path through
  doorways, not through walls.
- **Lethal Company, Eyeless Dog**: the closest relative, a blind sound hunter. It
  investigates on low suspicion and lunges at the last heard position on high suspicion.
  (fan sources, which disagree on the exact model)

### Why a warning makes it scarier, not easier

- An enemy reads as intelligent when the player can tell what it is thinking. A "bark"
  exists to say that the state changed; a give-up bark matters as much as an alert one.
- A reaction delay reads as fairness on the way up. A slow fall reads as lingering suspicion.
- Fear that lasts comes from self-blame: the player knows which of their own noises did it.
- Near misses come from a searcher that goes to the place, never to the player.

## The design, in five lines

1. It is blind. It never knows where Viv is. It knows where a sound was, and how sure it is.
2. **Barely heard**: it clicks, does not scream, and comes to check roughly where the sound was.
3. **Clearly heard**: it clicks, screams, and hunts the exact spot.
4. Once something has its attention, barely heard counts as clearly heard. The second noise
   is the one that gets you.
5. It never reacts to itself.

The rule the player learns: **click = it heard something. Scream = it knows where. Click and
no scream = it is coming to look: stop, then leave quietly.**

## The behaviour cycle

```
PATROL ──hears a noise (click)──▶ LISTEN ──barely heard, nothing more──▶ CHECK ──arrived──▶ short SEARCH ──▶ PATROL
                                     │                                     │
                                     └─clearly heard, or a second noise────┴─any noise it hears──▶ LISTEN ─▶ scream ─▶ HUNT
HUNT ──on the spot, 3 s of silence (groan)──▶ SEARCH ──gives up (exhale)──▶ PATROL
```

CHECK is `State.INVESTIGATE` in code.

| State | What it does | What the player should do |
| --- | --- | --- |
| PATROL | Walks its markers at 1 u/s, pauses, sometimes stops mid-way, sometimes detours to a place it heard something. In the Hacienda the Director picks the markers. | Move, carefully. |
| LISTEN | Freezes, head cocked to the sound. Its breath and steps cut off, then the neck click. | Freeze within about a second. |
| CHECK | Creeps at 2.2 u/s to a point up to 2.5 u off the sound. Stops once on the way to listen. | Leave the spot holding your breath (2.5 u/s is just faster), or stand still out of its way. |
| Hunt start | Stands still for the inhale and the scream (1.3 s). | Leave the spot. |
| HUNT | Runs at 3.9 u/s to the exact spot. New noises move the target with no new scream. | Stop feeding it sounds. |
| SEARCH | Checks points around the spot, nearest first and then out of order, feels the floor at each, steps through one nearby door. 12–18 s after a hunt, 5–8 s after a check. | Stay silent until the exhale. |

### Listening is the decision

For a barely-heard noise:

| Time | What happens |
| --- | --- |
| 0.0 s | It freezes. |
| 0.25 s | Neck click and voice. |
| 0 – 0.9 s | Grace. More faint noises only turn its head. A clear noise still means a hunt. |
| 0.9 s – end | It strains to hear. Any noise it hears means the scream. |
| End (1.4 – 2.2 s) | No second noise: it creeps toward the area. |

A clearly-heard noise keeps today's 0.7–1.2 s and always ends in the scream.

## Hearing

Every noise has a radius (how loud it is). The entity multiplies it twice:

- within radius × `clear_gain`: clearly heard
- within radius × `faint_gain`: barely heard

Distance is the acoustic distance Viv's own ears already use (`Acoustics.measure_between`):
the straight line when no wall is in the way, otherwise 30% straight line and 70% walking
path through the doorways. Each closed door on the way adds `door_muffle_u` (3 u, two doors
at most). So closing a door behind you makes you quieter, and every door it pushes open
stays open and makes the house louder for you.

Starting values, to tune by playtest. Each cell is clear / faint:

| Noise | Radius | Before (calm) | First house ×1.5 / ×2.5 | Hacienda ×2.0 / ×3.5 |
| --- | --- | --- | --- | --- |
| Held-breath step, quiet exhale, eased door | 1 u | 1.25 u | 1.5 / 2.5 u | 2 / 3.5 u |
| Flashlight click, door | 2.5 u | 3.1 u | 3.75 / 6.25 u | 5 / 8.75 u |
| Walking step, chest | 3 u | 3.75 u | 4.5 / 7.5 u | 6 / 10.5 u |
| Gasp | 5 u | 6.25 u | 7.5 / 12.5 u | 10 / 17.5 u |
| Sprint step, prayer | 6 u | 7.5 u | 9 / 15 u | 12 / 21 u |
| Forced gasp | 7 u | 8.75 u | 10.5 / 17.5 u | 14 / 24.5 u |
| Pebble, alarm clock | 8 u | 10 u | 12 / 20 u | 16 / 28 u |

The script's defaults are the Hacienda's. `tutorial.gd` sets the gentler pair for the first
house in `_configure_entity()` (`HOUSE_CLEAR_GAIN`, `HOUSE_FAINT_GAIN`).

## The Director (hint only)

`entities/entity_director.gd`, the child "Director" of the entity. It knows where Viv is.
The entity does not, and the Director never tells it. It does one thing: when the entity
asks which patrol marker to walk to next, the Director chooses.

- **Drift in.** It prefers markers whose walking distance to Viv is 8–16 u (the next room,
  not her room), with some randomness, never the same marker twice in a row.
- **No-go.** Never a marker within 5 u of her. It is never sent to her.
- **Pressure.** Rises while it sounds near to her (`Dread.presence`) or is alert
  (`Dread.threat`); 25 s on top of her fill it. Full: it backs off. For 20–35 s of patrol
  the markers 20 u or more from her are preferred, and the marker it was walking to is
  dropped at once. Then pressure starts again at 0.3. Time spent hunting or searching does
  not use the back-off up.
- **Quiet limit.** If it has not been within 18 u of her for 45–70 s, the next marker is
  the best one of the band, with no randomness.
- **Patrol life.** A small chance per second of walking (`patrol_stop_chance`, 0.05) to
  stop mid-way for 0.8–1.6 s: silence without a click.

It never changes what the entity hears, never touches where the entity thinks a sound
was, and never makes it listen, check or hunt. `test_entity_director` checks that, down to
the words its code may not contain.

The first house has the Director and the mid-way stops off (`_configure_entity()`); the
Hacienda has both on.

Four minutes of scripted patrol on the Hacienda's ground floor, Viv standing silent:

| | Director off | Director on |
| --- | --- | --- |
| Viv near three markers: mean distance to her | 22 u | 13–16 u |
| Viv in a corner with one marker beside her: mean distance | 28 u | 21 u |
| Same corner: longest stretch with it further than 18 u | 142 s | 49 s |
| Same corner: sent to the marker 3 u from her | once | never |
| Rhythm near her | none | about 115 s around her, 24 s away, back at pressure 0.3 |

## What is in this branch

| Plan step | What | Files |
| --- | --- | --- |
| 1 | It never hears itself. `NoiseManager.emit_noise()` takes an optional emitter; a door pushed open by a body makes its sound and sends no noise event. | `autoloads/noise_manager.gd`, `level/door/door.gd` |
| 2 | Two-certainty hearing through doorways and closed doors. Listening decides. The check (INVESTIGATE) with a fuzzed target, one stop on the way and a short look around. | `entities/entity_ai.gd`, `tutorial/entity.gd`, `tutorial/tutorial.gd`, `audio/acoustics.gd` (one public helper) |
| 3 | A hunt always reaches the spot (`hunt_linger`, `hunt_max_travel`). Longer search with tightening passes and a door as its last stop. Stuck watchdog. | `entities/entity_ai.gd`, `level/room/room_visibility.gd` |
| 4 | Sound hooks: a check counts as searching for the music and the house voice; its voice and sniffing while it checks; the click reaches as far as its faintest hearing (`heard_full_u` 16 → 32). Head scan while it checks. | `audio/dread.gd`, `entities/entity_audio.gd`, `audio/sound_settings.gd`, `tutorial/entity_sprite_rig.gd` |
| 5 | F3 overlay shows what it made of each noise. New suite `test_entity_behavior`. | `testing/tools/noise_debug.gd`, `testing/regression/*`, `testing/run_checks.py` |
| 6 | The Director and patrol life (above). The route no longer wears away: a revisit is a one-off detour. | `entities/entity_director.gd`, `tutorial/entity.gd`, `tutorial/tutorial_entity.tscn`, `tutorial/tutorial.gd` |
| not in the plan | The Hacienda's navigation mesh is baked at load, on both floors, right after the walls are built (about 10 ms). | `tutorial/zones/mansion_ground.gd`, `tutorial/zones/mansion_upper.gd` |

## Checked in the Hacienda

A scripted run on the ground floor (no player input, the real map, doors and patrol
markers), before and after the navigation bake:

| | Mesh not baked (as on `beta`) | Baked |
| --- | --- | --- |
| 90 s of patrol | 49 u walked, stuck against a wall 6 times | 85 u walked, never stuck, 6 doors pushed open |
| A barely-heard step 7–9 u away | Click, check, stuck on the way | Click, check lands about 1 u off the sound, short look, exhale: 12 s in all |
| A loud noise 32 u away, two closed doors on the way | Reached only when the straight line happened to be open | Heard as "wall in the way, 2 closed doors"; it arrives after 11 s, searches 12.5 s, exhales |

The one place it still stops is a patrol marker behind a locked door (the chapel): it
stands at the door for 1.5 s and moves on, which is the planned locked-door behaviour
without its rattle sound.

This changes how the Hacienda plays more than the hearing numbers do: it now gets to
where it is going. Expect it to feel clearly more dangerous there, and tune the two gains
after playing it, not before.

## What is not in this branch

Left for a follow-up, in the plan's own cut order:

- **Step 7, door behaviour**: waiting outside a closed door on patrol, slamming it in a
  hunt, rattling a locked one (`door_pushed`, `door_locked` sounds).
- **Step 8, learning inside a night.**
- **Step 9, claw taps.**
- The one teaching line for the tutorial, and the numbers going into Metrics.

## Differences from the Notion plan

- **Where the hearing lives.** The plan puts `hear()` in `tutorial/entity.gd`. It is in
  `entities/entity_ai.gd` instead, so the greybox entity of the level template follows the
  same rule (clear: hunt, faint: check). The listening pause stays in `tutorial/entity.gd`.
- **Noises are weighed at once when they arrive inside the physics step**, and on the next
  step otherwise. The plan queues all of them. Footsteps, doors and throws arrive inside the
  step, so nothing is a frame late and the existing suites still read the result at once.
- **The door a search ends at.** In a level with Rooms it is a door of the room the sound
  was in, as planned. The Hacienda has no Rooms yet, so there it is any unlocked door within
  `search_door_reach_u` (8 u) of the spot.
- **Check and search points stay in the same space as the sound** when one can be found
  (no wall between the two), so "about where the sound was" is never the room next door.
- **Pressure also counts hovering.** The plan fills the pressure from `Dread.presence`
  and `Dread.threat` only. Presence is how near it *sounds*, so circling her behind walls
  never filled it and it hovered in her part of the house for minutes. `near_pressure`
  (0.25) counts being within 18 u of her as a quarter of full closeness; 0 gives the plan's
  rule back. An empty house also drains the pressure (`pressure_fall_time`, 60 s), which
  the plan does not say.
- **A back-off only counts down on patrol**, and it redirects the patrol leg already under
  way. Otherwise a back-off that began during a hunt was over before it meant anything.
- **Mid-way stops are off in the first house**, with the Director.
- **Renamed exports**: `hunt_persistence` → `hunt_linger`, `search_duration` →
  `search_duration_range`. `calm_hearing_multiplier`, `alert_hearing_multiplier` and
  `hearing_multiplier()` are gone.

## Tuning

Everything is an `@export` on the entity, grouped in the Inspector:

| Group | Export | Default | What it changes |
| --- | --- | --- | --- |
| Hearing | `clear_gain` | 2.0 | How far a noise is a hunt. |
| Hearing | `faint_gain` | 3.5 | How far a noise is a check. Raise this to make it feel present; it costs the player nothing they are not warned about. |
| Hearing | `door_muffle_u` | 3.0 | What a closed door is worth. |
| Listening | `listen_time_range` | 0.7–1.2 s | Warning before a scream. |
| Listening | `faint_listen_time_range` | 1.4–2.2 s | How long it strains to hear after a faint noise. |
| Listening | `second_strike_grace` | 0.9 s | The player's window to stop. |
| Check | `investigate_speed_u` | 2.2 | Keep it under her held-breath speed (2.5). |
| Check | `investigate_error_u` | 2.5 | How far off a check can land. |
| Hunt | `hunt_linger` | 3 s | Stillness on the spot before the search. |
| Search | `search_duration_range` | 12–18 s | |
| Search | `search_radius_u`, `search_points` | 6 u, 5 | |
| Search | `search_door_reach_u` | 8 u | 0 turns the door stop off. |
| Stuck | `stuck_time` | 1.5 s | |
| Patrol route | `patrol_stop_chance` | 0.05 /s | Stops mid-way. 0 in the first house. |
| Director | `near_band_u` | 8–16 u | Where it likes to be: the next room. |
| Director | `no_go_u` | 5 u | Never sent closer than this. |
| Director | `jitter_u` | 4 u | Randomness of a choice. |
| Director | `pressure_fill_time` | 25 s | Closeness before it backs off. |
| Director | `near_pressure` | 0.25 | What hovering unheard counts for. Lower: it stays around longer. |
| Director | `back_off_range`, `far_u` | 20–35 s, 20 u | The breather. |
| Director | `quiet_limit_range`, `quiet_range_u` | 45–70 s, 18 u | No dead stretches. |

The Director's exports are on the "Director" node of `tutorial/tutorial_entity.tscn`.

**F3** (Test Lab, or any scene with the noise overlay): around each noise ring two thin
circles show how far the entity would hear that noise in open air (red: clearly, amber:
barely). Walls and closed doors make the real distance longer, so the read-out gains a last
line with the entity's own verdict on the last noise it weighed:

```
it hears (x2.0 / x3.5): INVESTIGATE · last noise FOOTSTEP 3.0 u: FAINT at 7.4 u (clear <= 6.0, faint <= 10.5) · wall in the way · 1 closed door
```

While it listens the line also says what the listening will end in (`listening -> HUNT` or
`listening -> INVESTIGATE`). In the Hacienda it ends with the Director: `director: pressure
0.42, last marker 4 (19 u from her by foot, drift in)`, or `backing off 22 s`. Tune the numbers in the Inspector while looking at this.

## Playtest matrix

| # | Do this | Expect |
| --- | --- | --- |
| 1 | Let it walk through a closed door | Door sound. No click, no scream. |
| 2 | Walk about 8 u from it (F3 on) | Click, no scream, it comes to about where you were. |
| 3 | After that click, keep walking | Scream within about 2 s. |
| 4 | After that click, stop inside 1 s and stay still | No scream. It checks and leaves with the exhale. |
| 5 | Walk within 5 u of it, same room | Click, scream, hunt. |
| 6 | Hold your breath and cross the room 4 u from it | Nothing. |
| 7 | Throw a pebble 10 u from it | Scream, hunt to the pebble, not to you. |
| 8 | Make a noise behind a closed door, then with the door open | Open is heard from further. |
| 9 | After a hunt, hide silently in the same room | It searches 12–18 s, tries a door, exhales. |
| 10 | Screen off, whole encounter | You can always say: heard / checking / hunting / gave up. |
| 11 | First house, first-time player | The encounter is still passable with the gentle values. |
| 12 | Hacienda: stay silent for 2 minutes | It comes through your part of the house, never straight at you. |
| 13 | Hacienda: let it hover near you for 2 minutes (F3 on) | Pressure fills, it leaves for about half a minute, and comes back. |

## Risks to watch in playtests

- **Alert ears are strict.** While it checks or searches, a walking step is a hunt out to
  10.5 u in the Hacienda. If that is too much, add a separate gain between the two.
- **Prayer.** Its noise repeats every 0.5 s, so within faint range it always ends in a hunt
  after about 2 s. That matches "prayer always draws the entity".
- **Many doors.** Small rooms and doors are where navigation breaks. The watchdog is the
  safety net; walk it through every door of a new map.
- **Patrol markers behind locked doors.** The Hacienda has at least one (the chapel). It
  costs 1.5 s each time; move the marker or leave it as a "something tried the door" beat.
- **Viv's ears changed in the Hacienda too.** The entity's own sounds are placed with the
  same path measurement, so behind a wall they now come from the doorway and from further
  away than before. That is how the first house already sounds.
- **Few markers.** The Hacienda has 8 patrol markers on a 70 × 56 u floor, so often no
  marker is inside the 8–16 u band and the Director takes the nearest one outside the
  no-go. More markers (two per big room, one per small) give it real choices.

## Merging `showcase/night-one-test`

Decided: where the two overlap, this branch wins. A trial merge conflicts in two files.

- `testing/run_checks.py`: keep every suite name from both sides.
- `tutorial/entity.gd`: keep this branch's file, then put the showcase's rest back on top
  of it, because the showcase's own code calls `entity.rest()` and `entity.is_resting()`:
  - the variables `_rest_left`, `_deaf_left`, `rest_hearing`, counted down at the top of
    `_physics_process()` and cleared in `reset_encounter()`;
  - `rest()` and `is_resting()` as they are, with `_hunt_travel = 0.0`, `_inbox.clear()`
    and `_detour = Vector2.INF` added to what `rest()` clears;
  - deaf: `_listens()` also returns false while `_deaf_left > 0.0`;
  - hears less: `hearing_multiplier()` is gone, so scale the noise instead, with
    `func _judge(at, radius, source): super._judge(at, radius * (rest_hearing if _rest_left > 0.0 else 1.0), source)`;
  - the catch guard `_rest_left <= 0.0` in `_on_catch_area_body_entered()`.

  `rest()` walks it to the route point furthest from Viv; that is the Director's back-off
  by another road, so the showcase could call it less once the Director is on.

## Sources

- Game Developer, "How Darkwood's visibility mechanics create a new kind of horror": https://gamedeveloper.com/design/how-i-darkwood-i-s-visibility-mechanics-create-a-new-kind-of-horror
- Push Square, interview with Acid Wizard: https://www.pushsquare.com/news/2019/05/interview_exploring_darkwood_ps4s_creepiest_upcoming_indie
- Darkwood enemy and night-event behaviour (player guides): https://steamcommunity.com/sharedfiles/filedetails/?id=1277428824 and https://steamah.com/darkwood-useful-tips-and-hidden-mechanics-guide/
- Game Developer, "The Perfect Organism: The AI of Alien: Isolation": https://www.gamedeveloper.com/design/the-perfect-organism-the-ai-of-alien-isolation
- Game Developer, "Revisiting the AI of Alien: Isolation": https://www.gamedeveloper.com/design/revisiting-the-ai-of-alien-isolation
- MCV, "Horror in the making: the Alien: Isolation gamble": https://mcvuk.com/development-news/horror-in-the-making-the-alien-isolation-gamble/
- Game Developer, "Building an AI sensory system: examining the design of Thief: The Dark Project": https://www.gamedeveloper.com/programming/building-an-ai-sensory-system-examining-the-design-of-i-thief-the-dark-project-i-
- The Dark Mod wiki, AI stats: https://wiki.thedarkmod.com/index.php/AI_stats
- Game Developer, "Endure and survive: the AI of The Last of Us": https://gamedeveloper.com/design/endure-and-survive-the-ai-of-the-last-of-us
- Game Developer, "Bringing balance to stealth AI in Splinter Cell: Blacklist": https://gamedeveloper.com/design/bringing-balance-to-stealth-ai-in-splinter-cell-blacklist
- Kotaku, "Why video game characters say such ridiculous things" (barks): https://kotaku.com/why-video-game-characters-say-such-ridiculous-things-5921878
- Lethal Company, Eyeless Dog (fan source): https://estnn.com/lethal-company-eyeless-dog-everything-you-need-to-know/
