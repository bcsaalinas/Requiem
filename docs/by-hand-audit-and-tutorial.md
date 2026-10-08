# Requiem — What should be done by hand in Godot (audit + beginner tutorial)

> **Audit date:** 2026-10-08 · **Code state audited:** commit `78377b8` ("Add phantom camera organic tutorial prototype") · **Godot:** 4.7 (from `project.godot`)
>
> Line numbers below refer to that commit. If you edit files they will drift — search for the quoted code instead.

---

### TL;DR

- About **250 of the 3,391 gameplay lines**, **~35 hard-coded coordinates**, **154 duplicated materials** and **86 script-drawn props** are doing work the Godot editor should do (and would do better, because you could *see* it).
- The biggest offenders: `art.gd` (draws props, walls, candles), `world.gd` (paints floors), `tutorial.gd` (coordinates, raw keys, window/audio set-up), five scripts that build audio players and HUD bars with `.new()`, and two autoloads that build their UI in code.
- **Keep in code:** the entity AI, the breath/flashlight/throw/altar logic, the noise bus, the story flow, shaders, the nav-from-map automation, the tests, and the readability-shader system. Section 4 explains why.
- **The tile system** is well designed but has never been used on real content. Use tiles for walls, floors and identical scenery; keep pickups/doors (anything with a unique id) as placed scenes. Section 5.
- **Start with Lessons 1–3** (~1.5 hours). They are low-risk, and teach Project Settings, Input Map and the Inspector.

---

## 0. How to use this document

This file has two halves.

| Half | What it is | Read it when |
|---|---|---|
| **Part A — The audit** (sections 1–6) | The full description of the problem, a register of every thing that is done in code but belongs in the Godot editor, a list of what *must* stay in code, and a verdict on the tile system. | You want to understand *why* and *what*. |
| **Part B — The tutorial** (sections 7–9) | Click-by-click lessons, written for someone who has never used Godot. Each lesson fixes one group of problems from the register. | You are sitting in front of the editor and want to *do* it. |

You do **not** have to do everything. Lessons are ordered from easiest/most valuable to hardest. After each lesson the game still runs, so you can stop at any point.

### Contents

**Part A — The audit**
1. [The problem, in plain words](#1-the-problem-in-plain-words)
2. [The scorecard](#2-the-scorecard)
3. [The register — everything done in code that belongs in the editor](#3-the-register--everything-done-in-code-that-belongs-in-the-editor)
4. [What must stay in code (and why)](#4-what-must-stay-in-code-and-why)
5. [Does the tile system work? (and when to use tiles vs scenes)](#5-does-the-tile-system-work-and-when-to-use-tiles-vs-scenes)
6. [Recommended order](#6-recommended-order)

**Part B — The tutorial**
7. Godot in 20 minutes (only what this project needs)
8. The lessons — 1 Settings · 2 Input Map · 3 Audio · 4 Audio players + HUD bars · 5 Autoloads as scenes · 6 Shared materials · 7 Lights · 8 Markers, areas, triggers, groups · 9 Static props · 10 Candles · 11 Floors & trail · 12 Walls as tiles · 13 Scene tiles (trees) · 14 What remains in `art.gd`
9. Appendices — A Scale/Offset table · B Coordinates · C Names the code depends on · D Contact shadows · E Troubleshooting · F Glossary

### Two honesty notes (please read)

1. **I could not run Godot in the environment where I wrote this.** Everything here comes from reading the code and the scene files, plus a few scripts I used to count and compute numbers. The code snippets and numbers are carefully derived, but the *editor click paths* are written from my knowledge of Godot 4 — menu names can differ slightly in 4.7. Every lesson ends with a "Check it worked" step and a "If it breaks" step. If a step does not match what you see on screen, **stop and ask** instead of improvising.
2. **I did not run the project's test suite or the tile-system test.** When I say the tile system "works", I mean "the code reads correctly and its own test describes it working" — not "I watched it pass". Section 5 spells out exactly what that means.

### Words you will see a lot

| Word | Meaning in this project |
|---|---|
| **by hand / in the editor** | Created or edited with the Godot editor's windows (Scene dock, Inspector, 2D view, Project Settings), so it is *saved as data* in a `.tscn` / `.tres` / `project.godot` file. |
| **in code** | Created or computed by a `.gd` script while the game (or a `@tool` script in the editor) runs. |
| **redundant code** | Code whose job the editor can do for you, *and* where the editor version is easier to see, change and keep correct. |
| **magic number** | A bare number in code (like `Vector2(5870,692)`) that means "a place in the world" but cannot be seen or dragged. |

---

# PART A — The audit

## 1. The problem, in plain words

### 1.1 What is going on

Godot is built around the idea that **you build your game visually and use scripts only for behaviour**:

- *What things look like and where they are* → scenes, nodes, Inspector, tile maps. (Data.)
- *What things do when the player acts* → GDScript. (Behaviour.)

Requiem is mostly good at this already: `hud.tscn`, `player.tscn`, `altar.tscn`, `entity.tscn` and most of `world.tscn` are real scenes, and the player/entity scripts use `@export` so you can tune numbers in the Inspector. The newest work (`level/`, Phases 1–4 in the git log) even sets up a proper tile system.

But a large part of the **tutorial level** and a few **systems** were built the other way round: the script *draws*, *creates*, *positions* and *configures* things that the editor could simply store. That is the problem this document is about.

### 1.2 Why it matters (with real examples from this repo)

**(a) You cannot see it, so you cannot fix it by looking.**
`autoloads/game_over_ui.gd` builds its "you died" label like this:

```gdscript
label = Label.new()
label.set_anchors_preset(Control.PRESET_CENTER)
```

In the editor you would drop a `Label`, click *Layout → Center*, and *see* the result immediately. In code you only find out by dying in the game. Reading this code carefully, I believe the label's top-left corner is anchored to the screen centre with no offset, so the text probably starts at the centre and runs to the lower right instead of being centred. I could not run it to confirm — but that is exactly the kind of bug that cannot exist when you place the label by eye.

**(b) The same fact is stored twice, and the two copies can disagree.**
`world.tscn` already saves each prop's `light_mask`, `z_index`, `texture_filter` and shader material. Then `art.gd` runs `_ready()` and sets the *same* properties again from code (`art.gd` lines 37–40). Because `art.gd` is a `@tool` script it also runs inside the editor, so when you press Save the editor writes its freshly-created materials into the scene: **`world.tscn` contains 154 separate `ShaderMaterial` copies** — 95 with empty parameters (`shader_parameter/saturation = null`) and 59 holding the tree (50), rug (8) and floor (1) values. That is four distinct looks, stored 154 times. One shared `.tres` per look would replace all of them.

**(c) Magic numbers.**
`tutorial.gd` contains about 30 hard-coded world positions: `Vector2(5870,692)`, `Vector2(6030,330)`, `Rect2(2038,418,144,128)`, door x-values `1930.0` / `2310.0`, and so on. To move a sound or a trigger you must read the script, guess which number is which, edit it, run the game and walk there. In the editor each one would be a visible marker you drag.

**(d) The art is a spreadsheet instead of pictures.**
`art.gd` stores 16 + 8 hand-measured rectangles of the sprite atlases (`CELLS`, `DETAIL_REGIONS`) and a long `match` block of per-kind sizes and offsets. Godot has a tool for exactly this: `AtlasTexture` + the *Region editor*, where you crop with the mouse and see the sprite.

**(e) Duplicated, then hidden.**
`hold_breath.gd`, `flashlight.gd` and `throw.gd` each build their own HUD bars/labels in code. The tutorial then builds a *second*, properly designed HUD (`hud.tscn`) and **hides the first one in code** (`tutorial.gd` lines 76–77, 84). Code that creates something only to be hidden is the clearest sign of redundancy.

**(f) Tests become fragile.**
Hard-coded coordinates and node-name strings (`"candle_(985_0, 280_0)"`) are copied into tests. Moving anything in the editor can silently invalidate them.

### 1.3 How it got this way (my reading of the history)

- `world.tscn` has nodes named `@CollisionShape2D@252` (Godot's auto-name for nodes created by `add_child()` in code). That means it was originally **generated by a script** and later saved as a scene. The scene is real and editable now, but it carries the "generated" shape: one `StaticBody2D` + `CollisionShape2D` + `LightOccluder2D` + art node per prop, 99 times over.
- `art.gd` / `materials.gd` were the generator's drawing layer and never got replaced by real nodes.
- Phases 1–4 (`util/units.gd`, `walls_tileset.tres`, `props_tileset.tres`, `level_template.tscn`) introduced the *right* tools, but the tutorial level was never migrated to them. The two worlds co-exist.

### 1.4 What this costs you, concretely

| Cost | Example |
|---|---|
| Slow iteration | To nudge a branch-snap sound you edit a number, run, walk there. As a node you drag it. |
| Invisible layout | You can't see where the entity patrols, where triggers are, or where the room edges are. |
| Bloated, noisy scenes | `world.tscn` is 4,899 lines; much of it is duplicated materials, shapes and polygons. |
| Hard to learn from | You said you want to learn Godot by doing. Code that fights the editor teaches the wrong habits. |
| Fragile changes | The same value lives in a scene *and* a script (b), so edits are overwritten at runtime. |

---

## 2. The scorecard

Numbers are from the audited commit (non-addon GDScript only).

| Measure | Value |
|---|---|
| Gameplay GDScript (non-test, non-addon) | **3,391 lines** in 24 files |
| Test/capture GDScript | 962 lines in 10 files (**stays code**) |
| Lines that I judge *redundant* (could be deleted once the editor holds the data) | **≈ 250 lines (~7 %)** — my estimate, summing the ranges in the register |
| `art.gd` | ≈ 55 of 218 lines are redundant, but the real win is not line count: **86 of its 150 drawn nodes become plain `Sprite2D` nodes**, 24 hand-measured rectangles become editable resources, and the rest (≈ 160 lines) is the readability-shader system that genuinely needs code |
| `Art` nodes in `world.tscn` (nodes whose picture is drawn by `art.gd`) | **150** (50 trees, 32 walls, 15 lanterns, 8 rugs, 8 doors, 7 markers, 5 candles, 4 batteries, 3 desks, 3 chairs, 3 coats, 2 shelves, 2 rocks, 2 altars, 1 each of bed/phone/flashlight/window/friend/entity) |
| `StaticBody2D` / `LightOccluder2D` in `world.tscn` | 99 / 99 (one set per prop and wall) |
| Duplicated `ShaderMaterial` sub-resources in `world.tscn` | **154** (needed: 4) |
| Hard-coded world positions in `tutorial.gd` + `world.gd` + camera rig | roughly **30–40** (counted by hand from `Vector2(...)` / `Rect2(...)` lines) |
| Nodes created with `.new()` that could be real scene nodes | 5× `AudioStreamPlayer2D`, 3× `CanvasLayer`, 4× `ProgressBar`/`Label`, 1 autoload `Label`, 2 autoload `CanvasLayer` + `Label`, 1 projectile `Sprite2D`, 1 runtime `PointLight2D` |
| Keys hard-coded instead of Input Map actions | 6 keys (`E`, `B`, `R`, `H`, `Esc`, `F11`) + `F3` + `R` in the autoloads |

---

## 3. The register — everything done in code that belongs in the editor

How to read the tables:

- **Effort**: S = under 30 min · M = 1–2 h · L = a half day or more (for a beginner).
- **Risk**: how likely you are to break something that a test or the game depends on. Lessons tell you how to check.
- **Lesson**: where the click-by-click instructions are (section 8).

Within each group, items are listed roughly from most valuable to least.

### Group S — Settings the project already has a window for

| ID | Where | What the code does | Do this by hand instead | Effort | Risk | Lesson |
|---|---|---|---|---|---|---|
| **S1** | `tutorial.gd` L60–62, L67 | Sets the window's content size to 1280×720, scale mode, scale aspect, and the default clear (background) colour `0e161b` at startup. | **Project Settings → Display → Window** (viewport size, stretch mode/aspect — mode and aspect are *already* set in `project.godot`) and **Rendering → Environment → Default Clear Color**. | S | Low | 1 |
| **S2** | `tutorial.gd` `_input` (L226–250), `noise_debug.gd` L112–113, `game_over_ui.gd` L28–29 | Checks raw keys (`KEY_E`, `KEY_B`, `KEY_R`, `KEY_H`, `KEY_ESCAPE`, `KEY_F11`, `KEY_F3`). `player.gd` explicitly says *not* to do this (it uses Input Map actions so players can rebind). | **Project Settings → Input Map**: add actions `interact`, `use_battery`, `retry`, `pause`, `toggle_fullscreen`, `toggle_noise_debug`. | S | Low | 2 |
| **S3** | `tutorial.gd` L90–95, L151 | Assigns audio streams in code (`prayer_audio.stream = sound("prayer")`, `flashlight.click_clips.assign(...)`, `thrower.piedra_clips.assign(...)`, ambience by zone) and **re-plays ambient/prayer loops by connecting `finished` signals**. | Drop the `.wav` into the node's **Stream / Clips** field in the Inspector; set **Loop Mode = Forward** on the WAV in the **Import** dock so it loops by itself. | S | Low | 3 |
| **S4** | `tutorial.gd` L75, L79, L83; `prop_light.gd` L6–14 | Hides `player.Sprite2D` (already `visible = false` in `player.tscn`); `PropLight.attach()` re-sets light cull masks and shadow filters that `player.tscn` **already saves**, then creates the companion light in code. | Add a `PropLight` child (with the script) to `LocalLight` and `flashlight` inside `player.tscn`; delete the redundant lines. | S | Low | 7 |
| **S5** | `world.gd` L43–44, L85–92 | Hard-codes node names (`"parent_door_a"`, `"VestibuleLight"`…) while the scene **already carries metadata that says the same thing** (`occupied_door = true` on the two doors; `lighting_role = "story"` on the three story lights). | Use **Groups** (Node dock → Groups) and/or read the metadata that is already there. | S | Low | 8 |

### Group U — UI that is generated in code

| ID | Where | What the code does | Do this by hand instead | Effort | Risk | Lesson |
|---|---|---|---|---|---|---|
| **U1** | `autoloads/game_over_ui.gd` L11–19 | Creates a `Label`, sets font size 42, colour, anchors, alignment — all by code. | A `game_over_ui.tscn` scene (`CanvasLayer` + `Label`) used as the autoload. | S | Low | 5 |
| **U2** | `autoloads/noise_debug.gd` L26–33, L59–78 | Creates 2 `CanvasLayer`s, a `Node2D`, and a `Label`; font size and position by code. (The *drawing* of the noise circles is real code and stays.) | A `noise_debug.tscn` with those nodes; keep only the drawing/logic in the script. | M | Low | 5 |
| **U3** | `hold_breath.gd` L65–96, `flashlight.gd` L69–90, `throw.gd` L83–102 | Each mechanic builds its own `CanvasLayer` + `ProgressBar`s / `Label` at hard-coded pixel positions (20,20), (20,54), (20,88), (20,122). **The tutorial then hides all three** (`tutorial.gd` L76–77, L84) because `hud.tscn` replaces them. | Put the bars as real nodes in `player.tscn`; scripts just reference them. | M | Medium | 4 |
| **U4** | `hud.gd` L19–23 | Finds `Flashlight`/`Battery`/`Rocks` slots by `String(kind).capitalize()`. Works, but breaks silently if you rename a node. | Turn on **Access as Unique Name** (`%Name`) in the Scene dock and use `%` lookups. (Optional polish.) | S | Low | 4 (bonus) |

> `hud.tscn` itself is the **model of how it should be done**: every label, bar, style box and the pause menu is a real node with Inspector values. Use it as your reference.

### Group N — Nodes created with `.new()` that should just be nodes

| ID | Where | What the code does | Do this by hand instead | Effort | Risk | Lesson |
|---|---|---|---|---|---|---|
| **N1** | `footstep_noise.gd` L59–60, `hold_breath.gd` L72–73, `flashlight.gd` L75–76, `throw.gd` L91–92, `body_altar.gd` L63–64 | `AudioStreamPlayer2D.new()` + `add_child()`, five times, identical. | An `AudioStreamPlayer2D` child named `AudioPlayer` in each scene; `@onready var _audio_player = $AudioPlayer`. | S | Low | 4 |
| **N2** | `throw.gd` L195–206 | Builds the thrown object's `Sprite2D` and a `PlaceholderTexture2D` in code. | A small `projectile.tscn` scene and an `@export var projectile_scene: PackedScene`. Bonus: you can give it a real sprite later with no code change. | S | Low | 4 (bonus 4E) |
| **N3** | `world.gd` L58–70, `tutorial.gd` L431, L449–451, L523–525 | `world.lamp()` creates a `PointLight2D` (texture, scale, colour, energy, shadow filter) at runtime for the 1.15-second window "reveal", then frees it. | A hidden `RevealLight` node placed in `House` in `world.tscn`; code just `show()`s/`hide()`s it. | S | Low | 7 |
| **N4** | `world.gd` L48–56, `art.gd` L89–92 | `world.prop("shards","glass",…)` creates a node that draws 11 little lines for broken glass. | Either a hidden authored node, or a one-shot `CPUParticles2D` (you can preview it live in the editor). *Needs one test line updated* — see Lesson 7 note. | M | Medium | 7 (bonus) |
| **N5** | `nav_setup.gd` L51–59 | Builds a `NavigationPolygon` from the painted map. | **Keep in code.** This is deliberate automation (see section 4). | — | — | — |

### Group A — Art that is drawn by code

| ID | Where | What the code does | Do this by hand instead | Effort | Risk | Lesson |
|---|---|---|---|---|---|---|
| **A1** | `art.gd` L16–25, L99–131 | Static props (bed, desk, shelf, chair, altar, trees, lanterns, rugs, coats) are **drawn by `_draw()`** from hard-coded atlas rectangles and a per-kind `match` of sizes and foot offsets. 86 nodes use this (plus the duplicate `altar_pray`). | A `Sprite2D` with an `AtlasTexture` (crop in the Region editor). Exact **Scale** and **Offset** numbers for every prop are in Appendix A. | M–L | Medium | 9 |
| **A2** | `art.gd` L140–160, `world.gd` L90–92 | Candles: one atlas crop, with a second, shorter crop when `extinguished`, switched by code. | Two `Sprite2D` children (`Lit`, `Out`); a group `danger_candles`; one `visible` toggle. | S | Low | 10 |
| **A3** | `art.gd` L83–88, `materials.gd` L4–11 | Walls: `Art(kind="wall")` paints two textured strips and two lines. 32 of these, each next to a hand-made collision + occluder. | A **TileMapLayer** with a walls TileSet that has a physics layer and an occlusion layer — which the project **already has** (`level/walls_tileset.tres`). | L | High | 12 |
| **A4** | `art.gd` L94–97, L125–127 | Fake "contact shadows" under props: two black ellipses drawn with `draw_colored_polygon` (alpha 0.08 and 0.14). | A `Sprite2D` child using a radial `GradientTexture2D`. (Optional polish.) | S | Low | 9 (polish) |
| **A5** | `art.gd` L40–48, `materials.gd` L13–21, `world.gd` L24–25 | Creates a `ShaderMaterial` per node and sets saturation/contrast/gain/detail per *kind* in code — while the scene saves its own copy (154 of them: 95 default, 50 tree, 8 rug, 1 floor). | **4 shared material files** (`.tres`): default, tree, rug, floor. Assign them to many nodes at once with multi-select. | S–M | Low | 6 |
| **A6** | `world.gd` L72–83, `materials.gd` L4–11 | The floor of every room and the forest trail are **painted by `_draw()`** in nested loops over texture rectangles. | One `Sprite2D` per room with *Region + Texture Repeat* (or a TileMapLayer), and a `Line2D` for the trail. Needs the four material cells cropped into their own PNGs once. | M | Medium | 11 |
| **A7** | `art.gd` L9–25 | 24 hand-measured `Rect2` values are the only record of "where each sprite is on the atlas". | `AtlasTexture` resources (`.tres`) saved once per sprite and reused everywhere. | S (comes with A1) | Low | 9 |
| **A8** | `art.gd` L101, L141, L156–159, L129 | Behaviour baked into drawing: `if int(position.x) % 3 == 0 → spruce instead of tree` (15 of 50 trees); window uses a different crop when `broken`; candle crops when extinguished; the actor bobs by `sin(clock*2)`. | Explicit choices you make in the editor (this tree is a `spruce` — you *see* it); states as child nodes; bobbing as an `AnimationPlayer` track (optional). | M | Medium | 9–10 |
| **A9** | `art.gd` L69–72 | Calls `queue_redraw()` **every frame** on actor, friend, entity, candle, phone and altar (and on the two occupied doors), but only the actor (idle bob) and the occupied doors (shifting feet) actually change over time. | Disappears with A1/A2. | — | — | 9 |

### Group L — Layout and story data written as numbers (the "magic numbers")

| ID | Where | What the code does | Do this by hand instead | Effort | Risk | Lesson |
|---|---|---|---|---|---|---|
| **L1** | `world.gd` L6–12, `tutorial.gd` L142/L562, `phantom_tutorial.gd` L25/L30, tests | `REGIONS`: the rectangle of each room, used for camera limits and spawn origin. | One `ReferenceRect` named `Bounds` per room (you *see* its red outline and drag its corners). | S–M | Medium | 8 |
| **L2** | `tutorial.gd` L143, L335, L339, L350, L370, L555–556 | Spawn and return positions: `{"bedroom":Vector2(340,440), …}`, `Vector2(820,460)`, `Vector2(2450,340)`, `Vector2(4460,540)`, `Vector2(5737,620)`… | `Marker2D` nodes (`BedroomSpawn`, `BedroomFromHall`, …). Exact coordinates in Appendix B. | S | Low | 8 |
| **L3** | `tutorial.gd` L169–170 | The entity's 3-point patrol route after the attack. | 3 `Marker2D`s (or a `Path2D`). | S | Low | 8 |
| **L4** | `tutorial.gd` L197, L200, L216, L220, L428, L441, L457 | Positions + volumes of one-shot sounds: branch snap, dragging behind the wall, chair scrape, rustle, "presence", thud. | `AudioStreamPlayer2D` nodes placed in the world with the stream and volume set in the Inspector. | M | Low | 8 |
| **L5** | `tutorial.gd` L194, L198, L211–215, L222, L417 | Trigger areas expressed as math: `player.position.x > 3500`, `abs(x - door_x) < 190`, `Rect2(2038,418,144,128).has_point(...)`, `distance_to(Vector2(5870,692)) > 59`. | `Area2D` + `CollisionShape2D` you can see; a `body_entered` signal. | M | Medium | 8 |
| **L6** | `tutorial.gd` L422, L425, L431, L465 | Where the glass lands, where the "reveal" figure stands, where the friend falls. | `Marker2D`s (the reveal figure is already a node; its light becomes one in Lesson 7). | S | Low | 8 |
| **L7** | `tutorial.gd` L485, L495 | "Listener" and "parent ear" positions (6 vectors) for the environment and parent reactions. | `Marker2D`s in a group (`listeners_forest`, `listeners_loop`, `parent_ears`). | S | Low | 8 |
| **L8** | `world.gd` L90, `tutorial_camera_rig.gd` L128 | `"candle_(985_0, 280_0)"` — node names made from coordinates, and a camera `Vector2(_hallway_door, 276.0)`. | Groups and a marker. | S | Low | 8, 10 |
| **L9** | `tutorial_camera_rig.gd` L37–56 | Sets camera limits on every PhantomCamera in code. The addon you already installed has a **`limit_target`** property for this (accepts a `TileMapLayer` or `CollisionShape2D`). | Optional — set `Limit Target` in the Inspector of each PhantomCamera2D. | S | Medium | — (optional; note at the end of Lesson 14) |

### Bonus findings (worth knowing, not in the lessons)

- **`altar_pray` draws a second altar.** It is an `Art(kind="altar")` at exactly the same position as `altar` `(6240, 280)` with `dimensions = (1,1)`. `art.gd` ignores `dimensions` for altars (it uses a fixed 148×128), so both draw the same sprite on top of each other. Its interaction is also disabled in `tutorial.gd` L300. It looks like an interaction anchor that accidentally became a visible duplicate. *To verify:* open `world.tscn`, select `altar_pray` and hide it — if nothing changes visually, delete it or replace it with a `Marker2D`.
- **The base player depends on the tutorial.** `player/player.tscn` uses `res://tutorial/throw.gd` (which hides the ammo label and only lets you throw when `rocks > 0`), `res://tutorial/art.gd` (the `Appearance` node, `kind = "actor"`) and `res://tutorial/scenery.gdshader`. So the player in `level_template.tscn` is really the *tutorial* player. Not a bug today, but it means "tutorial" and "game" are not separable yet.
- **Dead code/data:** the `crate` entry in `art.gd` (no instance exists), the `@export var tint` on `art.gd` (declared, never used, but saved on the 15 lanterns), the `occupied_door` and `lighting_role` metadata (saved in the scene, never read).
- **Possible navigation bug (unverified).** `tutorial.gd` L411–413 re-bakes the House navigation region when the latch is released. The House region's `NavigationPolygon` uses `source_geometry_group_name = "tutorial_obstacles"`, and in `world.tscn` only **2 of the 99** bodies (`HouseChestCollision15`, `AltarChairCollision16`) are in that group. If the bake only reads group members, the re-baked house mesh would ignore walls and most furniture. I could not run it, so treat this as "worth checking": after releasing the latch, watch whether the entity walks into walls in the house. This is another thing the editor can show you directly (Node dock → Groups).

---

## 4. What must stay in code (and why)

Not everything should go into the editor. Moving *behaviour* out of code is as wrong as leaving *data* in it. This list is here so you do not waste time (or break the game).

### Keep — this is logic, not data

| File | Why it stays |
|---|---|
| `entities/entity_ai.gd`, `tutorial/entity.gd` | The state machine (patrol → investigate → search → hunt), hearing, memory, pathing. The editor cannot express this. (Its numbers are already `@export`ed — good.) |
| `player/player.gd`, `footstep_noise.gd`, `hold_breath.gd` (logic), `flashlight.gd` (logic), `throw.gd` (logic) | Movement rules, meter maths, flicker, trajectories, noise emission. |
| `altar/body_altar.gd` | The prayer ritual timers and noise pulse. |
| `autoloads/noise_manager.gd`, `game_state.gd` | The global signal bus and shared state — that is what autoloads are for. |
| `util/units.gd` | One source of truth for scale. It's a `class_name` with constants — exactly right. |
| `tutorial/tutorial.gd` (flow) | The story state machine: interactions, checkpoints, sequences, resets, dialogue queue. Only its *data* (positions, keys, streams) moves out. |
| `tutorial/world.gd` (indexing) | Builds the `interactables`/`props`/`landmarks` dictionaries from the scene — good use of code to *read* what you authored. |
| `tutorial/hud.gd` | `place_prompt()` follows a world position; `update_inventory()` shows/hides slots. Real logic. |
| `tutorial/prop_light.gd` (the `_sync` part) | Copies a light's state onto its companion light every frame so two light layers stay in step with flicker/aim/story changes. Dynamic, so it needs code. |
| `tutorial/cameras/tutorial_camera_rig.gd` | Shot selection, blending and effect timing. (Only the limit-setting is replaceable — L9.) |
| `autoloads/noise_debug.gd` (drawing) | Custom `_draw()` of circles/labels in world space is exactly what `_draw()` is for. |
| `*.gdshader` (4 files) | Shaders are code by nature. They are *assets* you keep; what changes is that their parameters are stored in `.tres` files instead of being set in scripts (A5). |
| `level/level.gd`, `level/nav_setup.gd` | Deliberate automation: they fit the floor/camera and bake navigation **from the painted map**, so a new level needs no hand-sizing. Their own comments say this is the point. |
| `tutorial/tests/*`, `level/tests/*` | Tests and screenshot captures are code by definition. |
| `addons/phantom_camera/*` | Third-party addon. Do not edit. |

### Gray zone — your call, my recommendation

| Thing | Recommendation |
|---|---|
| **The readability shader pipeline** (`focal_sprite.gdshader`, `readability_rim.gdshader`, the `paint_sprite()` part of `art.gd`, ~80 lines) | **Keep in code for now.** It creates two extra sprites per important prop and recomputes 10 shader parameters when focus/threat changes — that is dynamic behaviour. After lessons 9–10, `art.gd` is ≈ 160 lines: this system (~80 lines) plus the drawing of the ~26 nodes that depend on it. Applies to: actor, friend, entity, flashlight, battery, phone, rocks, marker, window, door (~26 nodes). |
| **Dialogue / subtitle text** (about 40 strings in `tutorial.gd`) | Data in code, but the Godot answer is a translation CSV, which only pays off when you want a second language. Leave until then. |
| **The actor's idle bob** (`sin(clock*2)*.6`) | Could be an `AnimationPlayer`, but the effect is 0.6 px. Not worth a lesson. |
| **`entity_ai.gd` setting `CatchArea` radius at runtime** | Fine: the radius is derived from an `@export` in *units*. |
| **Polling in `_process`** (`_tick_hallway`, `_find_interaction`) | Some of it becomes signals when you add `Area2D`s (L5), the rest is fine. |

---

## 5. Does the tile system work? (and when to use tiles vs scenes)

You asked whether items could be placed "with our tiling system (if it works properly)". Here is an honest answer.

### 5.1 What exists

- `level/walls_tileset.tres` — a 32×32 `TileSet` with 4 tiles from `assets/sprites/wall.png`, each with a **physics polygon** and an **occlusion polygon**. Occlusion light mask 1, physics layer 1.
- `level/props_tileset.tres` — a *scenes collection* that holds `altar.tscn` as a tile.
- `level/level_template.tscn` — `Level` root with `Floor` (ColorRect), `Map` (walls layer), `Props` (props layer), `NavigationRegion2D`, `Player`, `Entity`, `CanvasModulate`.
- `level/level.gd` — fits the floor and the player camera limits to the painted walls (+4 u margin) and warns if a layer's tile size isn't 32 px.
- `level/nav_setup.gd` — bakes navigation from the painted map and puts `Map` and `Props` into an obstacle group.
- `level/tests/test_level_template.gd` — paints a 24×16 house in code and checks: floor/camera fitting, walls and altars carved out of navigation, a 2-tile and a 1-tile doorway being walkable, the entity patrolling, and a prayed-at altar erasing its own tile.

### 5.2 Verdict

**For walls, floors, and "one scene = one prop" placement: yes, it is the right system and it reads as correct.** The design is clean (single scale source, no hard-coded sizes, tests that exercise the real nodes). I have **not** run that test, so I can't say it passes today — you can: open `level/tests/test_level_template.tscn` and press **F6**; the last Output line should read `[Level tests] N/N passed`.

**But it has never been used for real content.** `project.godot` runs `tutorial/tutorial.tscn`, which does not use `level_template.tscn` at all. The tile system has only been exercised by its own synthetic test. Three gaps will bite the first time you retrofit the tutorial:

1. **Scene tiles can't carry per-instance data.** Every instance of a scene tile is identical. The tutorial's interactables each need a unique `interaction_id` / `interaction_label` (20 of them) and unique names (`battery`, `forest_battery`, `porch_battery`, `house_battery` each track their own "collected" state). Those must stay **placed instances** (drag-and-drop a scene, set metadata in the Inspector), not tiles. Tiles suit things that are the same everywhere: walls, floor patches, trees, crates, chairs.
2. **The wall art doesn't match.** `wall.png` is a 64×64 flat placeholder. The tutorial's walls use a top surface + a darker 30 px "front face" painted from `materials_atlas.png`. And the tutorial's walls are **24 px thick**, while the grid is **32 px**. You'd re-lay walls on the grid and make new wall tile art.
3. **The tutorial's lighting uses two light layers** (walls/floor/characters on layer 1, raised props on layer 2, with a companion `PropLight` for each light). The walls TileSet's occlusion layer is on mask 1, which matches the tutorial's walls — but any prop scene you make must set **light mask 2** on its sprite and **occluder light mask 2** on its occluder (that's how the existing bed/trees are set up). Forgetting this makes props look unlit or shadowless.

Also note `altar.tscn` is still a 40×40 yellow placeholder square sitting in a 32 px cell, so it overlaps its neighbours slightly. That's a placeholder, not a bug.

### 5.3 Decision guide: tile, scene, or node?

| You want to place… | Use | Why |
|---|---|---|
| Floor of a room | `Sprite2D` (Region + Repeat) or a `TileMapLayer` | Large uniform surface. |
| Walls | `TileMapLayer` (`walls_tileset.tres`) | Collision + shadows come with the tile; you paint rooms in seconds. |
| Trees, crates, chairs, identical things | **Scene tile** on the `Props` layer, or a scene you drag in | Same everywhere; snaps to the grid when tiled. |
| Furniture that needs a unique footprint or art size (desk, bed, rugs) | **Scene instance** (drag from FileSystem) | Per-instance scale/size; no grid needed. |
| Pickups, doors, anything with an `interaction_id` | **Scene instance** + metadata | Needs unique per-instance data. |
| A "spot" (spawn, sound origin, event position) | `Marker2D` | Visible, draggable, named. |
| A region ("when the player is here") | `Area2D` + `CollisionShape2D` | Gives you a `body_entered` signal for free. |
| A rectangle used by code (room bounds) | `ReferenceRect` | Draws its outline in the editor. |

### 5.4 My recommendation

Don't retrofit *everything* in the tutorial just to use tiles. Instead:

1. Do the **cheap, high-value** lessons first (1–8). They remove most of the code and magic numbers without touching the level's geometry.
2. Use **floor sprites + prop sprites** (lessons 9–11) to remove `art.gd`'s drawing.
3. Treat **walls as tiles** (lesson 12) as the "new way" and use it **for the next room/level you build** on `level_template.tscn`. Retrofit the 32 existing tutorial walls only if you want to — they work and are already hand-authored nodes; the only code involved is `art.gd` drawing their surface.

---

## 6. Recommended order

| Tier | Lessons | Time | What you gain |
|---|---|---|---|
| **1 — Quick wins** (do these first) | 1 Settings · 2 Input Map · 3 Audio streams & loops | ~1.5 h | ~10 lines of code gone, no more hard-coded keys, loops by import setting. You learn: Project Settings, Input Map, Inspector, Import dock. |
| **2 — Real nodes instead of `.new()`** | 4 Audio players + HUD bars in scenes · 5 Autoloads as scenes · 6 Shared materials · 7 Lights | ~4 h | ~130 lines gone, 154 duplicate materials gone. You learn: scenes, child nodes, `@onready`, resources, `.tres`, multi-select, groups of nodes. |
| **3 — Places as nodes** | 8 Markers, areas, groups | ~3 h | All magic coordinates become visible, draggable nodes. You learn: `Marker2D`, `Area2D`, `ReferenceRect`, signals, groups. |
| **4 — Art** | 9 Static props · 10 Candles · 11 Floor & trail | ~6 h | 86 props stop being script-drawn; `art.gd` keeps only the readability system (≈ 160 lines). You learn: `Sprite2D`, `AtlasTexture`, Region editor, texture repeat, `Line2D`. |
| **5 — Tiles** | 12 Walls as tiles · 13 Scene tiles (trees) | ~half a day | The project's tile system finally used on real content. You learn: `TileSet`, physics/occlusion layers, `TileMapLayer`. |
| **6 — Clean-up** | 14 What remains in `art.gd` | ~30 min | Final check list. |

After **each** lesson: run the game (F5), run the test scene (see section 7.4), then commit.

---

# PART B — The tutorial

## 7. Godot in 20 minutes (only what this project needs)

If you already know Godot's basics, skip to section 8. If not, read this once; every lesson refers back to it.

### 7.1 Five ideas

| Idea | One-sentence explanation | Example from Requiem |
|---|---|---|
| **Node** | A building block with one job. | `Sprite2D` shows a picture; `StaticBody2D` is a solid thing; `Label` shows text; `AudioStreamPlayer2D` plays a sound from a position. |
| **Scene** | A *tree of nodes saved in one file* (`.tscn`). You can place ("instance") a scene inside another scene. | `player.tscn` is placed inside `tutorial.tscn`; `hud.tscn` is placed inside it too. |
| **Resource** | A saved *piece of data* (`.tres`, or an image/sound file) that many nodes can share. | `walls_tileset.tres`, the `.wav` files, and — after Lesson 6 — shared shader materials. |
| **Script** | A `.gd` file that gives a node behaviour. Variables marked `@export` appear in the Inspector. | `player.gd` has `@export var walk_speed_u`, which you can change in the Inspector. |
| **Signal** | A node announcing "something happened" (`body_entered`, `pressed`, `finished`…). | `NoiseManager.noise_emitted`; a button's `pressed`. |

Two script phrases you'll see in the lessons:

```gdscript
@onready var _audio_player: AudioStreamPlayer2D = $AudioPlayer
```
means: "when this node is ready, find my child node named `AudioPlayer` and remember it in `_audio_player`". `$Name` is shorthand for "the child called Name", and `$A/B` means "child B of child A". It only works if a node with exactly that name exists — so **node names matter**.

```gdscript
@export var room_ambience: AudioStream
```
means: "show a slot called *Room Ambience* in the Inspector where I can drop a sound file". That is how you move data *out* of code without losing control from code.

### 7.2 The editor screen

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Scene  Project  Debug  Editor  Help      [2D] [3D] [Script]      ▶ ⏸ ⏹ ▷ │  ← top bar. ▶ = Run project (F5)
├───────────────┬───────────────────────────────────────┬───────────────────┤      ▷ = Run current scene (F6)
│ SCENE dock    │                                       │ INSPECTOR         │
│ (the node     │         2D viewport                   │ (properties of    │
│  tree of the  │   (you see and drag the things here)  │  the selected     │
│  open scene)  │                                       │  node)            │
├───────────────┤                                       │  NODE tab: signals│
│ FILESYSTEM    │                                       │  and groups       │
│ dock (files)  ├───────────────────────────────────────┴───────────────────┤
│               │ BOTTOM PANEL tabs: Output · Debugger · Animation · TileSet… │
└───────────────┴─────────────────────────────────────────────────────────────┘
```

- **Scene dock** — the tree of the scene you have open. Select nodes here.
- **FileSystem dock** — every file in the project (`res://` means "the project folder"). Double-click a `.tscn` to open it. Drag files from here into slots in the Inspector or into the 2D viewport.
- **Inspector** — the properties of whatever is selected. If you are editing a *resource* (a texture, a material), the Inspector shows that.
- **Node dock** (a tab next to the Inspector) — has **Signals** and **Groups** tabs.
- **Output** (bottom) — `print()` messages and **errors in red**. Look here first when something is wrong.
- **Import dock** (a tab next to the Scene dock) — appears when you select an audio/image file in the FileSystem. Used for the loop setting in Lesson 3.

### 7.3 The twelve things you'll do constantly

| To… | Do this |
|---|---|
| Open a scene | Double-click the `.tscn` in the FileSystem dock |
| Save | **Ctrl/Cmd + S**. An unsaved scene has a `*` on its tab. |
| Add a child node | Select the parent in the Scene dock → **Ctrl/Cmd + A** (or right-click → *Add Child Node…*) → type the node type → *Create* |
| Add a scene as a child | **Ctrl/Cmd + Shift + A** (chain-link icon), or drag the `.tscn` from the FileSystem dock into the 2D viewport |
| Rename | Select → **F2** |
| Duplicate | Select → **Ctrl/Cmd + D** |
| Delete | Select → **Delete** |
| Select many nodes | Click one, then **Shift+click** another (range) or **Ctrl/Cmd+click** (individual) in the Scene dock. The Inspector then edits all of them together. |
| Find a node by name | Type in the *Filter nodes* box at the top of the Scene dock |
| Assign a file to a slot | Drag it from the FileSystem dock onto the slot, or click the slot's arrow → *Quick Load* |
| Run the game / the open scene | **F5** / **F6**. Stop with **F8**. |
| Move around the 2D view | Mouse wheel zooms; hold middle mouse (or Space) and drag to pan; press **F** to centre the view on the selected node |

### 7.4 Your safety net — git and tests

This repo is under git. **Before each lesson, commit.** If a lesson goes wrong you can throw it away and try again.

```bash
git status                      # what changed?
git add -A && git commit -m "before lesson N"
# ... do the lesson ...
git add -A && git commit -m "lesson N: <what you did>"
# if it went wrong and you want to undo EVERYTHING since the last commit:
git restore .                   # (careful: discards uncommitted work)
```

Any git app (GitHub Desktop, Fork, VS Code's Source Control panel) works as well.

**Running the tests from the editor.** The project has automated tests. They are ordinary scenes:

1. In the FileSystem dock, double-click the test scene.
2. Press **F6**.
3. Watch the **Output** panel. The last line is `[… tests] N/N passed`. Any failing check is printed in red.

| Test scene | What it covers | Run it after lessons |
|---|---|---|
| `res://tutorial/tests/test_tutorial.tscn` | The whole tutorial story flow (the most important one) | **every lesson** |
| `res://tutorial/tests/test_lighting_response.tscn` | Light companions and story lighting | 6, 7, 9, 10, 12 |
| `res://tutorial/tests/test_phantom_camera.tscn` | Camera rig and room bounds | 1, 8 |
| `res://level/tests/test_level_template.tscn` | The tile system | 4, 5, 12, 13 |

> **Do this once before Lesson 1:** run all four and write down the results ("test_tutorial N/N passed", and so on). If one already fails *before* you touch anything, you need to know that. I could not run them myself.

### 7.5 Seven rules for this migration

1. **One lesson at a time.** Commit before and after.
2. **Editor first, code second.** Build the editor version, then *comment out* (`#`) the old code, test, and only then delete it.
3. **Save the scene** (Ctrl+S) before you press F5. Forgetting is the #1 beginner mistake.
4. **Names matter.** Code finds nodes by name (`$AudioPlayer`, `get_node("Throw")`, `landmarks["EntryCollision"]`). Don't rename anything listed in **Appendix C** unless a lesson tells you to.
5. **`art.gd` and `world.gd` are `@tool` scripts**: they run *inside the editor* while you edit. If the 2D view looks wrong or things are missing, open **Output** — a script error in a `@tool` script shows up there.
6. **Resources are shared.** If ten nodes use one `.tres` and you edit it, all ten change. That's the point of Lesson 6. If you want a private copy, use *Make Unique* in the resource's dropdown.
7. **When stuck, look at `hud.tscn`.** It's the project's example of a well-built scene.

---

## 8. The lessons

Each lesson has the same shape: **what you'll learn → why → steps → code changes → check it worked → if it breaks**.

Difficulty: ★ easy · ★★ some thinking · ★★★ hard.

---

### Lesson 1 — Project Settings: window size and background colour
**Fixes S1** · ★ · ~15 min · Risk: low

**You'll learn:** where project-wide settings live (Project Settings), and that the code you're about to delete was only doing what a settings page does.

**Why:** `tutorial.gd` sets window scaling and the background colour every time the scene starts. These are *project* decisions, not tutorial decisions.

**Steps**

1. Menu **Project → Project Settings…** A window opens. In its top-right corner switch **Advanced Settings** *on* (so you can see everything).
2. In the left tree open **Display → Window**.
   - Under **Size**: set **Viewport Width = 1280** and **Viewport Height = 720**.
   - Under **Stretch**: check that **Mode = canvas_items** and **Aspect = expand**. (They are already set in `project.godot`; you're just confirming.)
3. In the left tree open **Rendering → Environment**. Find **Default Clear Color**. Click the colour swatch, and in the hex box type `0e161b`, press Enter.
4. Click **Close**. (Settings save automatically into `project.godot`.)

**Code changes** — in `res://tutorial/tutorial.gd`, function `_ready()`, delete (or first comment out) these four lines:

```gdscript
	get_window().content_scale_size = Vector2i(1280,720)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
```
and, a few lines lower:
```gdscript
	RenderingServer.set_default_clear_color(Color("0e161b"))
```
**Keep** the `get_window().mode = Window.MODE_FULLSCREEN` block: it depends on command-line flags and `test_mode`, which a settings page can't express.

**Check it worked:** press **F5**. The game should look identical (same framing, same dark blue-grey around the rooms). Run `test_tutorial.tscn` and `test_phantom_camera.tscn`.

**If it breaks:** background is black or grey → the clear colour didn't save; reopen Project Settings and re-enter `0e161b`. Framing differs → re-check Viewport Width/Height are 1280×720. Still wrong → restore the four lines (`git restore requiem/tutorial/tutorial.gd` from the repository root).

---

### Lesson 2 — Input Map: stop hard-coding keys
**Fixes S2** · ★ · ~25 min · Risk: low

**You'll learn:** the **Input Map** (named actions instead of raw keys), and how a script asks "was the *action* pressed?".

**Why:** `player.gd` already does this right (`Input.get_vector("move_left", …)`). `tutorial.gd`, `noise_debug.gd` and `game_over_ui.gd` check `KEY_E`, `KEY_R`, `KEY_H`… so those keys can't be rebound, don't work with a gamepad, and the same key is written in several files.

**Steps — create the actions**

1. **Project → Project Settings… → Input Map** tab.
2. In **Add New Action** type `interact`, press **Add**. The action appears in the list.
3. Click the **+** at the right end of the `interact` row. A dialog "Event Configuration" opens. Press the **E** key on your keyboard. The dialog shows "E (Physical)". Leave it as *Physical* (the other actions in this project, like `move_up`, are physical too). Click **OK**.
4. Repeat for every row of this table (for `pause`, click **+** twice: once for Esc, once for H):

| Action name | Key(s) | Replaces |
|---|---|---|
| `interact` | E | `KEY_E` in `tutorial.gd` |
| `use_battery` | B | `KEY_B` in `tutorial.gd` |
| `retry` | R | `KEY_R` in `tutorial.gd` and `game_over_ui.gd` |
| `pause` | Esc **and** H | `KEY_ESCAPE`, `KEY_H` |
| `toggle_fullscreen` | F11 | `KEY_F11` |
| `toggle_noise_debug` | F3 | `KEY_F3` in `noise_debug.gd` |

> The existing `pray` action is also **E**. That's fine: two actions can share a key. The altar listens to `pray`; the tutorial listens to `interact`.

**Code changes**

`tutorial.gd` — replace the whole `_input` function with:

```gdscript
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused: return
	if event.is_action_pressed("retry") and not resetting:
		request_reset("Back to the last safe place.")
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("use_battery") and dialogue.is_empty() and not resetting:
		insert_battery()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("interact"):
		if not dialogue.is_empty(): advance_dialogue()
		elif not resetting and sequence=="":
			_find_interaction()
			if nearest!="": interact(nearest)
		get_viewport().set_input_as_handled()
```

What changed: the first two lines of the old function (the "is it a pressed, non-echo key?" check and the `var key = …` line) are gone because `is_action_pressed()` already ignores key-repeat; every `key == KEY_X` became `event.is_action_pressed("x")`.

`autoloads/noise_debug.gd` — replace `_unhandled_input` with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_noise_debug"):
		enabled = not enabled
		_update_legend()
		_redraw()
```

`autoloads/game_over_ui.gd` — change the `if` line in `_unhandled_input` to:

```gdscript
	if GameState.is_dead and event.is_action_pressed("retry"):
```

Leave `phantom_tutorial.gd` alone: its `C` and `1–5` keys are debug shortcuts for a comparison scene, not gameplay.

**Check it worked:** F5, then: **E** talks to Eli / picks things up, **Esc** and **H** open the pause menu, **R** returns to the last safe place, **B** inserts a battery (once you have one), **F11** toggles fullscreen. Run `test_tutorial.tscn` — it presses `H` through `_input()` and checks that the game pauses, so this lesson is covered by an existing test.

**If it breaks:** a key does nothing → open Input Map and check the action name matches the code *exactly* (`use_battery`, not `use battery`). Esc/H pause does nothing → confirm `pause` has *two* events.

---

### Lesson 3 — Audio: streams in the Inspector, loops in the Import dock
**Fixes S3** · ★ · ~30 min · Risk: low

**You'll learn:** assigning a file to a slot in the Inspector, the **Import dock**, and `@export` for audio.

**Why:** `tutorial.gd` loads sounds by string name and, to loop ambience, connects each player's `finished` signal back to `play()`. Godot can loop a sound file by itself, and the Inspector can hold the sound file.

#### 3A — The prayer sound

1. Open `res://tutorial/tutorial.tscn`. In the Scene dock select **PrayerAudio**.
2. In the Inspector find **Stream** (under *AudioStreamPlayer2D*). Drag `res://tutorial/assets/audio/prayer.wav` from the FileSystem dock onto that slot.

#### 3B — Loop settings (the Import dock)

For each of `prayer.wav`, `forest.wav`, `room.wav` (all in `res://tutorial/assets/audio/`):

1. Click the file once in the FileSystem dock.
2. Click the **Import** tab (it appears next to the *Scene* tab, top-left).
3. Find **Edit → Loop Mode**. Change it from *Detect From WAV* to **Forward**.
4. Click **Reimport** (bottom of the Import dock).

#### 3C — The player's click and rock sounds

1. Open `res://player/player.tscn`. Select the **flashlight** node.
2. In the Inspector, under the script's **Audio** group, find **Click Clips**. Click it to expand, set **Size = 1**, then drag `res://tutorial/assets/audio/switch.wav` into **Element 0**.
3. Select the **Throw** node. Under **Audio** find **Piedra Clips**, set **Size = 1**, drag `res://tutorial/assets/audio/rock.wav` in.
4. Save (**Ctrl+S**).

#### 3D — Ambience by zone

The ambience changes between the forest and the rooms, so it can't be one Stream. Give `tutorial.gd` two **export slots** instead.

1. In `tutorial.gd`, next to the other `@export` lines near the top, add:

```gdscript
@export_group("Audio")
@export var room_ambience: AudioStream
@export var forest_ambience: AudioStream
```

   Put these three lines right *below* `@export var test_mode := false`. (An `@export_group` applies to everything under it until the next group, so putting them below keeps `test_mode` in the *Validation* group.)

2. Save the script, then open `tutorial.tscn`, select the root node **OrganicTutorial**. The Inspector now shows **Room Ambience** and **Forest Ambience**. Drag `room.wav` and `forest.wav` into them. Save.

**Code changes** in `tutorial.gd`

In `enter_zone()` replace
```gdscript
	ambience.stream=sound("forest" if zone=="forest" else "room")
```
with
```gdscript
	ambience.stream = forest_ambience if zone == "forest" else room_ambience
```

In `_ready()` delete these lines (they are now done by the Inspector and the import setting):

```gdscript
	ambience.finished.connect(func(): ambience.play())
	prayer_audio.stream=sound("prayer")
	prayer_audio.finished.connect(func():
		if zone=="house" and not attack_finished: prayer_audio.play())
	flashlight.click_clips.assign([sound("switch")])
	thrower.piedra_clips.assign([sound("rock")])
```

Keep the `if test_mode:` block just below them: it clears those arrays so tests stay silent.

**Check it worked:** F5 — the room hum plays and loops without gaps; the forest sound plays in the forest; the flashlight clicks (pick it up, press F); throwing a rock makes the rock sound; in the house you hear the prayer until Eli's attack, then it stops. Run `test_tutorial.tscn`.

**If it breaks:** silence → a Stream / Clips slot is empty (re-check 3A, 3C, 3D). Sound plays once and stops → the loop mode wasn't reimported (3B).

> **Note:** `play_sound("pickup", …)`, `play_sound("door", …)` etc. still load by name. Lesson 8 turns the *fixed-position* sounds into nodes; the "play at the player" ones can stay.

---

### Lesson 4 — Real nodes for audio players and HUD bars
**Fixes N1, U3, U4 (bonus)** · ★★ · ~1.5 h · Risk: medium

**You'll learn:** adding child nodes in a scene, setting Control layout in the Inspector, `@onready` and `$Path`, and why a script that *builds* UI is harder to work with than a scene that *contains* it.

**Why:** five scripts do `AudioStreamPlayer2D.new()` + `add_child()`. Three scripts build a `CanvasLayer` with `ProgressBar`/`Label` nodes at hard-coded pixel positions. The tutorial then hides those bars. Making them real nodes lets you *see and adjust* them, and removes about 80 lines.

#### 4A — Edit `player.tscn`

Open `res://player/player.tscn`. For each node below, **right-click it in the Scene dock → Add Child Node… → type the type → Create**, then **F2** to rename.

| Under this node | Add this child (type) | Name it exactly |
|---|---|---|
| `FootstepNoise` | `AudioStreamPlayer2D` | `AudioPlayer` |
| `HoldBreath` | `AudioStreamPlayer2D` | `AudioPlayer` |
| `HoldBreath` | `CanvasLayer` | `BarLayer` |
| `HoldBreath/BarLayer` | `ProgressBar` | `LungBar` |
| `HoldBreath/BarLayer` | `ProgressBar` | `ExertionBar` |
| `Throw` | `AudioStreamPlayer2D` | `AudioPlayer` |
| `Throw` | `CanvasLayer` | `BarLayer` |
| `Throw/BarLayer` | `Label` | `AmmoLabel` |
| `flashlight` | `AudioStreamPlayer2D` | `AudioPlayer` |
| `flashlight` | `CanvasLayer` | `BarLayer` |
| `flashlight/BarLayer` | `ProgressBar` | `BatteryBar` |

Now set the properties (select the node, edit in the Inspector). These are the exact values the old code used:

| Node | Property (where to find it) | Value |
|---|---|---|
| `LungBar` | *Layout → Transform → Position* / *Size* | Position `(20, 20)`, Size `(220, 24)` |
| | *ProgressBar → Show Percentage* | **off** |
| | *Range → Value* | `100` |
| | *CanvasItem → Visibility → Visible* | **off** |
| `ExertionBar` | Position / Size | `(20, 54)` / `(220, 24)` |
| | Show Percentage / Value / Visible | off / `0` / **off** |
| `BatteryBar` | Position / Size | `(20, 88)` / `(220, 24)` |
| | Show Percentage / Value / Visible | off / `100` / **off** |
| `AmmoLabel` | Position | `(20, 122)` |
| | *Theme Overrides → Font Sizes → Font Size* | `14` |

> **Tip:** build `LungBar` first, then select it and press **Ctrl+D** to duplicate it for `ExertionBar`, and just change Position and Value.
>
> **Why "Visible off"?** The scripts show a bar only when it's relevant (e.g. while holding your breath) and the old code created them hidden.

Save (**Ctrl+S**).

#### 4B — Edit `altar.tscn`

Open `res://altar/altar.tscn`. Right-click **BodyAltar → Add Child Node → AudioStreamPlayer2D**, rename it `AudioPlayer`. Save.

#### 4C — Change the five scripts

**`player/footstep_noise.gd`**

Replace
```gdscript
var footstep_timer: float = 0.0
var _audio_player: AudioStreamPlayer2D
```
with
```gdscript
var footstep_timer: float = 0.0
@onready var _audio_player: AudioStreamPlayer2D = $AudioPlayer
```
and **delete the whole `_ready()` function** (it only created the player).

**`player/hold_breath.gd`**

Delete these lines near the top: `var _audio_player: AudioStreamPlayer2D`, and the three bar variables `var _bar_layer: CanvasLayer`, `var _lung_bar: ProgressBar`, `var _exertion_bar: ProgressBar`. In their place put (after the `@onready var player` line):

```gdscript
@onready var _audio_player: AudioStreamPlayer2D = $AudioPlayer
# Las barras ahora son nodos reales de player.tscn.
@onready var _bar_layer: CanvasLayer = $BarLayer
@onready var _lung_bar: ProgressBar = $BarLayer/LungBar
@onready var _exertion_bar: ProgressBar = $BarLayer/ExertionBar
```
Then **delete the entire `_ready()` and the entire `_make_bar()` function.**

**`player/flashlight.gd`**

Delete `var _audio_player: AudioStreamPlayer2D`, `var _bar_layer: CanvasLayer`, `var _battery_bar: ProgressBar`. Add:

```gdscript
@onready var _audio_player: AudioStreamPlayer2D = $AudioPlayer
@onready var _bar_layer: CanvasLayer = $BarLayer
@onready var _battery_bar: ProgressBar = $BarLayer/BatteryBar
```
and shrink `_ready()` to just:

```gdscript
func _ready() -> void:
	_apply_beam_length()
	_full_cone_width = scale.y
	is_on = start_on and battery_percent > 0.0
	_refresh_light()
	_update_bar()
```

**`player/throw.gd`**

Delete `var _audio_player: AudioStreamPlayer2D`, `var _bar_layer: CanvasLayer`, `var _ammo_label: Label`. Add:

```gdscript
@onready var _audio_player: AudioStreamPlayer2D = $AudioPlayer
@onready var _bar_layer: CanvasLayer = $BarLayer
@onready var _ammo_label: Label = $BarLayer/AmmoLabel
```
and shrink `_ready()` to:

```gdscript
func _ready() -> void:
	alarms_left = alarm_charges
	_update_label()
```

**`altar/body_altar.gd`**

Replace `var _audio_player: AudioStreamPlayer2D` with `@onready var _audio_player: AudioStreamPlayer2D = $AudioPlayer`, and make `_ready()`:

```gdscript
func _ready() -> void:
	_color_base = sprite.modulate
```

> **Careful with order:** `@onready` variables are filled in just before `_ready()` runs, so `_ready()` can use them. A plain `var x = $Node` at the top of a script does *not* work (the node isn't there yet) — that's why we use `@onready`.

#### 4D — (Bonus, U4) Unique names in `hud.tscn`

`hud.gd` finds its slots by `String(kind).capitalize()`. If you ever rename a slot it breaks silently. To make it robust: open `hud.tscn`, right-click **Flashlight** (under `Screen/Inventory`) → **Access as Unique Name** (a `%` appears next to it). Do the same for **Battery**, **Rocks**. Then in `hud.gd`'s `_ready()` you could write `_slots[kind] = get_node("%" + String(kind).capitalize())`. This is optional polish; skip it if you're tired.

#### 4E — (Optional) The thrown object as a scene (N2)

`throw.gd` builds the flying rock's sprite in code (`PlaceholderTexture2D.new()` + `Sprite2D.new()`). As a scene you can later give it real art without touching code.

1. **Scene → New Scene → Other Node → Sprite2D**, rename `Projectile`. In the Inspector set **Texture → New PlaceholderTexture2D** and its **Size** to `(6, 6)`. Save as `res://player/projectile.tscn`.
2. In `throw.gd`, under the `@export_group("Visual")` lines, replace `@export var projectile_size: float = 6.0` with:

```gdscript
@export var projectile_scene: PackedScene
```
3. In `_release_object()` replace the block that creates `texture` and `sprite` with:

```gdscript
	var sprite: Sprite2D = projectile_scene.instantiate()
	sprite.modulate = _color_for(_pending_kind)
	sprite.global_position = player.global_position
	player.get_parent().add_child(sprite)
```
(the `_in_flight.append({...})` below it stays exactly as it is).
4. Open `player.tscn`, select **Throw**, and drag `projectile.tscn` into its new **Projectile Scene** slot. Save.

**Check:** in the tutorial, collect rocks and throw one (Q): a small pale square still flies to the cursor and makes noise where it lands. If you get `Invalid call. Nonexistent function 'instantiate' in base 'Nil'`, the slot in step 4 is empty.

**Check it worked**

- F5, play the tutorial: footsteps, breath sounds, the flashlight click, rocks and the altar sound all still play.
- The old on-screen bars are still hidden in the tutorial (the tutorial code hides `_bar_layer`, which is now a real node — same behaviour).
- To *see* your new bars: open `res://level/level_template.tscn`, press **F6**. Hold **Space**: the lung bar appears at top-left. Press **F** (flashlight): the battery bar appears under it.
- The ammo label can't be checked in-game: `player.tscn` uses `res://tutorial/throw.gd`, which hides the label and only lets you throw when `rocks > 0`. Check its position in the 2D viewport of `player.tscn` instead. (That the *base* player scene depends on a *tutorial* script is a coupling worth cleaning up one day — see "Bonus findings".)
- Run `test_tutorial.tscn` and `test_level_template.tscn`.

**If it breaks:** `Node not found: "AudioPlayer"` → the child's name is misspelled or it was added to the wrong parent (check the table in 4A). `Invalid access … null instance` on a bar → the path in `@onready` doesn't match (e.g. `BarLayer/LungBar`). Bars appear at the wrong place → check *Position* vs. *Size* weren't swapped.

> **Where this leads:** the tutorial now has *two* sets of bars (these hidden ones and `hud.tscn`). A cleaner end state is one shared HUD scene used by every level. That's a bigger design step and not needed now.

---

### Lesson 5 — Autoloads as scenes (GameOverUI and NoiseDebug)
**Fixes U1, U2** · ★★ · ~45 min (5A) + ~45 min (5B, optional) · Risk: low

**You'll learn:** that an **autoload** can be a *scene* (not just a script), anchors/alignment on a `Label`, and splitting "what it looks like" (scene) from "what it does" (script).

**Why:** `game_over_ui.gd` makes its whole UI with `.new()`. In a scene you will see the label while you design it.

#### 5A — GameOverUI

1. **Scene → New Scene.** In the Scene dock click **Other Node**, search `CanvasLayer`, **Create**. Rename the root to `GameOverUi`.
2. Select the root. In the Inspector set **Layer = 100**.
3. With the root selected press **Ctrl+A**, add a **Label**. Name it `Label`.
4. Select `Label` and set:
   - **Layout → Anchors Preset → Full Rect** (this stretches it over the whole screen — better than the old "Center" preset, which only anchors the top-left corner at the centre).
   - **Horizontal Alignment = Center**, **Vertical Alignment = Center**.
   - **Theme Overrides → Font Sizes → Font Size = 42**.
   - **Theme Overrides → Colors → Font Color =** `ff3333`.
   - **Text** = empty (leave blank).
5. **Right-click the root → Attach Script.** In the dialog click the **folder icon** next to *Path* and choose the *existing* `res://autoloads/game_over_ui.gd`. Confirm the dialog (its button says *Load* or *Attach*).
6. **Scene → Save Scene As…** → `res://autoloads/game_over_ui.tscn`.

Now edit `game_over_ui.gd` so it uses the scene's label instead of building one. Replace everything above `_on_player_died` with:

```gdscript
extends CanvasLayer

# GameOverUI (Autoload, escena)
#
# Muestra el texto de "moriste" cuando GameState avisa que el jugador murio,
# y permite reiniciar el nivel con la accion "retry" (R por defecto).
# El Label y su estilo viven en game_over_ui.tscn: aqui solo esta la logica.

@onready var label: Label = $Label


func _ready() -> void:
	GameState.player_died.connect(_on_player_died)
```
(Keep `_on_player_died` and `_unhandled_input` as they are — `_unhandled_input` was already updated in Lesson 2.)

**Swap the autoload:** **Project → Project Settings → Globals** tab (called *AutoLoad* in older versions).

1. Find the row **GameOverUi** (path `res://autoloads/game_over_ui.gd`) and delete it (trash icon).
2. In **Path** click the folder icon, choose `res://autoloads/game_over_ui.tscn`. **Node Name** `GameOverUi`. Click **Add**. Make sure **Enable** is ticked.
3. Autoloads load top to bottom, and this one needs `GameState` to exist first — so drag the new row so it sits *below* `GameState`.

**Check it worked:** open `game_over_ui.tscn`, type `TEST` in the Label's **Text** field, press **F6** — the text should be centred on the screen. Clear the text again and save. Then the real flow: open `res://level/level_template.tscn`, press **F6**, and let the roaming entity catch you — "MORISTE…" appears centred; press **R** and the level restarts. (The tutorial never kills the player — it resets to a checkpoint — so the template is the place to see this screen.)

#### 5B — NoiseDebug (optional, a good second exercise)

`noise_debug.gd` creates two `CanvasLayer`s, a `Label`, and an inner class `NoiseCanvas` that draws the circles. The drawing is real code and stays. The *scaffolding* becomes nodes.

1. New Scene, root **Node** named `NoiseDebug`. Attach the existing `res://autoloads/noise_debug.gd`.
2. Add child **CanvasLayer** `WorldLayer`: **Layer = 50**, and in *Follow Viewport* tick **Enabled**.
3. Under `WorldLayer` add a **Node2D** named `Canvas`.
4. Under `NoiseDebug` add a second **CanvasLayer** `LegendLayer`: **Layer = 90**.
5. Under `LegendLayer` add a **Label** `Legend`: **Position `(16, 16)`**, **Font Size 14**.
6. Create a new script file `res://autoloads/noise_canvas.gd`:

```gdscript
extends Node2D
## Dibuja los circulos de ruido. Los datos y la logica viven en noise_debug.gd
## (el nodo raiz de la escena), que es el `owner` de este nodo.

func _draw() -> void:
	owner._draw_noises(self)
```
   and attach it to the `Canvas` node.
7. Save the scene as `res://autoloads/noise_debug.tscn`.

In `noise_debug.gd`: **delete** the inner `class NoiseCanvas extends Node2D: …` block (lines ~26–33), replace the four variable declarations with

```gdscript
@onready var _canvas_layer: CanvasLayer = $WorldLayer
@onready var _canvas: Node2D = $WorldLayer/Canvas
@onready var _legend_layer: CanvasLayer = $LegendLayer
@onready var _legend: Label = $LegendLayer/Legend
```
and reduce `_ready()` to

```gdscript
func _ready() -> void:
	NoiseManager.noise_emitted.connect(_on_noise_emitted)
	_update_legend()
```

Swap the autoload entry (**Globals → NoiseDebug**) to `res://autoloads/noise_debug.tscn`, just like 5A. Keep the name `NoiseDebug` and keep it **below `NoiseManager`**.

**Check it worked:** in a level that doesn't disable it (open `level_template.tscn`, **F6**), walk: coloured circles appear around you; **F3** toggles them; the legend text shows top-left. (The tutorial turns this overlay off on purpose.)

**If it breaks:** circles don't draw → `Canvas` has no script attached, or `owner` is null because the script was attached to a node in the wrong scene. `Invalid access to '_legend_layer'` from `tutorial.gd` → the autoload still points at the old `.gd`.

---
### Lesson 6 — Shared materials: 154 copies become 4 files
**Fixes A5** · ★★ · ~1 h · Risk: low

**You'll learn:** what a **Resource** is, creating a `.tres` file, assigning one resource to many nodes at once (multi-select), and why `@tool` scripts can bloat a scene.

**Why:** `art.gd` runs `Materials.scenery_material()` for every node when the scene loads. Because the script is `@tool`, it also runs in the editor, so when you press Save the editor writes each brand-new material into `world.tscn` — **154 `ShaderMaterial` blocks** (95 with empty parameters, 50 with the tree values, 8 with the rug values, 1 with the floor values). They are all the same four looks. One file per look is easier to tune: change one number, the whole forest changes.

#### 6A — Create the four material files

1. FileSystem dock → right-click `res://tutorial/` → **Create New → Folder…** → `materials`.
2. Right-click that new folder → **Create New → Resource…** → type `ShaderMaterial` → **Create** → name it `scenery_default.tres` → **Create**.
3. Double-click `scenery_default.tres`. In the Inspector, drag `res://tutorial/scenery.gdshader` onto the **Shader** slot. Four **Shader Parameters** appear (Saturation, Contrast, Gain, Detail Radius). Leave them at their defaults. **Ctrl+S**.
4. Repeat steps 2–3 for the other three, setting the parameters like this:

| File | Saturation | Contrast | Gain | Detail Radius | Used by |
|---|---|---|---|---|---|
| `scenery_default.tres` | *(default 0.23)* | *(default 0.55)* | *(default 0.78)* | *(default 2.0)* | everything else |
| `scenery_tree.tres` | `0.12` | *(default)* | `0.70` | *(default)* | trees |
| `scenery_rug.tres` | `0.08` | `0.38` | `0.56` | `3.0` | the 8 rugs |
| `scenery_floor.tres` | `0.10` | `0.50` | `0.68` | `3.5` | floors |

These numbers are exactly what `art.gd` L41–48 and `materials.gd` L13–21 set in code.

#### 6B — Assign them with multi-select

1. Open `res://tutorial/world.tscn`.
2. Select the root node **TutorialWorld**. Inspector → **CanvasItem → Material → Material**: drag `scenery_floor.tres` into the slot.
3. **Trees:** in the Scene dock's *Filter nodes* box type `tree_`. The 50 nodes `tree_0 … tree_76` are listed (not the `TreeTrunk…` bodies). Click the first, **Shift+click** the last — all 50 are selected. In the Inspector set **Material** → drag `scenery_tree.tres`. Clear the filter box.
4. **Rugs:** filter by name and Ctrl+click: `bed_rug`, `room_hearth_mat`, `hall_runner`, `hall_refuge_mat`, `vestibule_rug`, `altar_rug`, `loop_rug`, `loop_refuge_mat`. Assign `scenery_rug.tres`.
5. Also open `player/player.tscn` (node `Appearance`) and `tutorial/tutorial_entity.tscn` (node `Appearance`): assign `scenery_default.tres` there too (they currently hold a private inline copy).
6. **Ctrl+S** on each scene.

> **Why it works:** when several nodes are selected the Inspector shows only the properties they share, and what you change is applied to all of them.

#### 6C — Stop the code from overwriting it

In `art.gd`:

- Add near the top (under the other `const` lines):
```gdscript
const DEFAULT_MATERIAL := preload("res://tutorial/materials/scenery_default.tres")
```
- In `_ready()` replace `material = Materials.scenery_material()` with
```gdscript
	if material == null:
		material = DEFAULT_MATERIAL
```
- Delete the two blocks that set parameters for `kind == "tree"` and `kind == "rug"` (they would now edit the *shared* file).

In `world.gd`, `_ready()`: delete `material = Materials.scenery_material(true)` and `texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST` (the scene already saves both on the root). In `materials.gd` delete `scenery_material()` once nothing calls it (search for it: `Ctrl+Shift+F`).

> **Why `if material == null`?** Nodes spawned at runtime (the glass `shards`) have no material; the fallback keeps them looking right. The remaining ~95 default-look nodes keep their individually-saved copies for now — Lesson 9 replaces most of them with `Sprite2D` nodes that you assign `scenery_default.tres` to in one multi-select.

**Check it worked:** F5 — looks identical. In `git`, `world.tscn` should have lost a lot of lines after the re-save (`git diff --stat`). Run `test_tutorial.tscn` and `test_lighting_response.tscn`.

**If it breaks:** everything looks washed out or too saturated → the wrong file was assigned to the trees/rugs (check the table). Floor looks different → `scenery_floor.tres` wasn't assigned to the root. A node suddenly has no shader (flat colours) → it has no material and isn't an `Art` node; assign `scenery_default.tres` by hand.

---

### Lesson 7 — Lights: stop configuring them in code
**Fixes S4, N3** · ★★ · ~45 min · Risk: low–medium

**You'll learn:** that a script can be attached to a child node you add yourself; why a property saved in a scene never needs to be set again in code.

**Background (important):** the game lights two *layers*: layer 1 for floors, walls and characters, layer 2 for raised props. Each light has a hidden twin, `PropLight`, that lights layer 2. `prop_light.gd` keeps the twin in step with the original every frame (it copies `energy`, `color`, `enabled`…). The twins of the **world lights are already saved** in `world.tscn`. Only the player's two lights get theirs *created in code* by `PropLight.attach()` — which also re-applies shadow settings that `player.tscn` already saves. We'll make the player's twins real nodes too.

#### 7A — Player lights

1. Open `res://player/player.tscn`.
2. Select **LocalLight** → **Ctrl+A** → add a **PointLight2D** → name it exactly `PropLight`.
3. With `PropLight` selected, drag `res://tutorial/prop_light.gd` from the FileSystem dock onto the node (or Inspector → Script → Load). Do not change anything else; the script sets its own masks and copies everything else from its parent.
4. Repeat for the **flashlight** node.
5. **Ctrl+S.**

In `tutorial.gd` `_ready()`, delete these two lines:
```gdscript
	preload("res://tutorial/prop_light.gd").attach(player.get_node("LocalLight"))
	preload("res://tutorial/prop_light.gd").attach(flashlight)
```
Also delete the line `player.get_node("Sprite2D").hide()` — `player.tscn` already has that sprite at `visible = false`.

#### 7B — The window "reveal" light

1. Open `world.tscn`. Select the **House** node → add a child **PointLight2D** named `RevealLight` and set:

| Property | Value |
|---|---|
| Position | `(5870, 642)` |
| Color | `a9b9a7` |
| Energy | `0.45` |
| Texture | drag `res://assets/Textures/light_texture.png` |
| Texture Scale | `0.8` |
| Shadow → Enabled | on |
| Shadow → Filter | `PCF5` · Filter Smooth `1.5` |
| Shadow → Item Cull Mask | layers **1 and 2** |
| *CanvasItem → Visibility → Visible* | **off** |

2. Add a child `PropLight` (PointLight2D + `prop_light.gd` script) under it, exactly as in 7A.
3. **Ctrl+S.**

In `tutorial.gd`:

- `_on_rock_landed`: replace
```gdscript
	world.lamp(Vector2(5870,642),Color("a9b9a7"),.8,.45).name="RevealLight"
```
with
```gdscript
	world.landmarks["RevealLight"].show()
```
- `_tick_sequence`: replace the two lines `var light:=world.get_node_or_null("RevealLight")` / `if light!=null: light.queue_free()` with
```gdscript
				world.landmarks["RevealLight"].hide()
```
- `request_reset`: replace `var reveal_light:=…` / `if reveal_light!=null: reveal_light.queue_free()` with
```gdscript
	world.landmarks["RevealLight"].hide()
```

Then delete `world.lamp()` from `world.gd` (L58–70) and the `static func attach(...)` block from `prop_light.gd` (L6–14, plus its comment) — search first (**Ctrl+Shift+F**) that nothing else calls `lamp(` or `attach(`.

> **The glass shards** (`world.prop("shards","glass",…)`, N4) can also become an authored hidden node or a one-shot `CPUParticles2D`. It's optional: if you do it, note that `test_tutorial.gd` checks `game.world.props.has("shards")` (L91), and `props` only contains nodes that use `art.gd`. You'd change that line to `game.world.landmarks.has("Shards")`.

**Check it worked:** F5 — the flashlight cone and your personal light behave as before; throw a rock through the window: a pale flash and the figure appear for about a second. Run `test_lighting_response.tscn` (it checks `flashlight.get_node("PropLight")` and that prop lights switch off with their source) and `test_tutorial.tscn`.

**If it breaks:** `Invalid access to property 'enabled'` from `prop_light.gd` → the twin isn't a *child of a PointLight2D*, or it isn't of type `PointLight2D`. Props look unlit near the flashlight → the twin's script wasn't attached.

---

### Lesson 8 — Make places visible: markers, rectangles, triggers, groups
**Fixes L1–L8, S5** · ★★★ · ~3 h · Risk: medium

This is the lesson that turns ~35 invisible numbers into things you can *see and drag*. Take it in slices; run the tests after each slice.

**You'll learn:** `Marker2D`, `ReferenceRect`, `Area2D` + signals, `AudioStreamPlayer2D` placed in the world, **Groups**, and how to give a script a small, stable way to ask the scene for those things.

#### 8.0 The five tools

| Tool | Node | Use it for | You'll see it in the editor as… |
|---|---|---|---|
| **Marker** | `Marker2D` | "a place": spawn points, event positions, route points | a small cross |
| **Rectangle** | `ReferenceRect` | "an area the code reads the rectangle of": room bounds | a red outline |
| **Trigger** | `Area2D` + `CollisionShape2D` | "tell me when the player walks in here" | a blue shape |
| **Sound** | `AudioStreamPlayer2D` | "a sound that comes from this spot" | the speaker icon |
| **Group** | (a tag on any node) | "all the nodes that are X" — lists of candles, lights, listeners | not drawn; set in **Node dock → Groups** |

How to create a node: select its parent in the Scene dock → **Ctrl+A** → type the type → *Create* → **F2** to name it. How to set a position: select it, Inspector → **Transform → Position**, type the X and Y from the tables. How to add a group: select the node → **Node** tab (next to Inspector) → **Groups** sub-tab → type the name → **Add**.

> **Where to put the new nodes:** as **direct children of a room node** (`Bedroom`, `Hallway`, `Forest`, `House`, `Loop`) in `world.tscn`. `world.gd` builds its `landmarks` dictionary from exactly those children, which is how the code will find them by name. Names must be **unique across all rooms**. None of the room nodes has a position of its own, so a marker's local position equals its world position.

#### 8.1 Give `world.gd` a small API

Add these to `world.gd` (next to the existing functions). You'll use them in every slice below.

```gdscript
signal trigger_entered(id: String)
## zone ("bedroom"…) -> rectangle of the room's "Bounds" node.
var regions: Dictionary = {}

## Posicion global de un Marker2D (u otro Node2D) colocado a mano.
func marker(id: String) -> Vector2:
	return (landmarks[id] as Node2D).global_position

## Posiciones de todos los nodos de un grupo, ordenados por nombre (EntityRoute1, 2, 3…).
func markers_in(group: String) -> Array[Vector2]:
	var nodes := get_tree().get_nodes_in_group(group)
	nodes.sort_custom(func(a, b): return String(a.name) < String(b.name))
	var result: Array[Vector2] = []
	for node in nodes:
		result.append((node as Node2D).global_position)
	return result

## Un sonido colocado en el mundo (AudioStreamPlayer2D).
func cue(id: String) -> AudioStreamPlayer2D:
	return landmarks[id] as AudioStreamPlayer2D

func _on_trigger_body_entered(body: Node2D, id: String) -> void:
	if body.is_in_group("player"):
		trigger_entered.emit(id)
```

And in `_ready()` of `world.gd`, **inside** the existing double loop (after `landmarks[String(child.name)] = child`), add:

```gdscript
			if not Engine.is_editor_hint() and child is Area2D and child.is_in_group("story_triggers"):
				(child as Area2D).body_entered.connect(_on_trigger_body_entered.bind(String(child.name)))
```
(Tabs matter in GDScript: these lines sit at the same indentation as `scene_nodes.append(child)`, i.e. inside both `for` loops.)
and, after the loops, fill `regions`:

```gdscript
	for room in get_children():
		var bounds := room.get_node_or_null("Bounds") as ReferenceRect
		if bounds != null:
			regions[String(room.name).to_lower()] = bounds.get_global_rect()
```

Also in `tutorial.gd` add two helpers next to `play_sound`:

```gdscript
func play_cue(id: String) -> void:
	if test_mode: return
	world.cue(id).play()
```

(The line that connects `world.trigger_entered` to a handler in `tutorial.gd` is added in slice 8.5, together with the handler itself, so nothing refers to a function that doesn't exist yet.)

#### 8.2 Slice 1 — Room bounds (L1)

1. In `world.tscn`, for each room add a child **ReferenceRect** named `Bounds`. Set **Position** and **Size** (Inspector → *Layout → Transform*):

| Room | Position | Size |
|---|---|---|
| Bedroom | `(0, 0)` | `(960, 640)` |
| Hallway | `(1600, 0)` | `(960, 640)` |
| Forest | `(3200, 0)` | `(1440, 800)` |
| House | `(5200, 0)` | `(1280, 960)` |
| Loop | `(7200, 0)` | `(960, 640)` |

   A red outline appears; you can drag its corners later to resize a room.

2. In `world.gd` delete the whole `const REGIONS := { … }` block. The floor `_draw()` loop still needs it until Lesson 11 — change `for zone in REGIONS:` to `for zone in regions:` and `var r: Rect2 = REGIONS[zone]` to `var r: Rect2 = regions[zone]`.
3. Replace every other use (search **Ctrl+Shift+F** for `REGIONS`):

| File | Old | New |
|---|---|---|
| `tutorial.gd` `_frame_camera` | `World.REGIONS[zone]` | `world.regions[zone]` |
| `phantom_tutorial.gd` (2 places) | `World.REGIONS[zone]` | `world.regions[zone]` |
| `tests/test_phantom_camera.gd` L26 | `game.World.REGIONS[game.zone]` | `game.world.regions[game.zone]` |
| `tests/presentation_capture.gd` L34 | `game.World.REGIONS.bedroom` | `game.world.regions["bedroom"]` |

**Check:** F5 plays as before; run `test_tutorial`, `test_phantom_camera`.

#### 8.3 Slice 2 — Spawn and return markers (L2, L3, L6)

Create these `Marker2D` nodes (names exact, parent = room shown, **Position** as shown). The spawn positions are the old `REGIONS[zone].position + starts[zone]`, already added up for you:

| Marker | Room | Position | Replaces |
|---|---|---|---|
| `BedroomSpawn` | Bedroom | `(340, 440)` | `starts["bedroom"]`, default checkpoint |
| `HallwaySpawn` | Hallway | `(1710, 340)` | `starts["hallway"]` |
| `ForestSpawn` | Forest | `(3350, 540)` | `starts["forest"]` |
| `HouseSpawn` | House | `(5730, 850)` | `starts["house"]` |
| `LoopSpawn` | Loop | `(7330, 330)` | `starts["loop"]` |
| `BedroomFromHall` | Bedroom | `(820, 460)` | `hall_back` return |
| `HallwayFromForest` | Hallway | `(2450, 340)` | `forest_back` return |
| `ForestFromHouse` | Forest | `(4460, 540)` | `house_back` return |
| `BedroomReset` | Bedroom | `(760, 425)` | retry after the parent catches you |
| `FrontDoorInside` | House | `(5737, 620)` | front-door teleport (in) |
| `FrontDoorOutside` | House | `(5737, 755)` | front-door teleport (out) |
| `GlassShards` | House | `(5870, 720)` | where the glass lands |
| `FriendFallen` | House | `(6240, 392)` | where Eli lies after the attack |

**Entity route:** three markers in **House**, each added to the group `entity_route` (Groups tab): `EntityRoute1` `(6030, 330)`, `EntityRoute2` `(6080, 360)`, `EntityRoute3` `(6080, 500)`.

**The reveal figure:** select the existing node `reveal` (House). Set its **Position** to `(5878, 640)` and **CanvasItem → Visibility → Modulate** to `(0.65, 0.65, 0.65, 0.65)` (RGBA). It stays hidden until the rock hits the glass.

Code changes in `tutorial.gd`:

```gdscript
# enter_zone(): delete the 'var origin' line and the 'var starts' line, and change the spawn line to:
	player.position = world.marker(zone.capitalize() + "Spawn") if spawn == Vector2.INF else spawn
```
```gdscript
# _configure_entity():
	if zone == "house" and attack_finished:
		var points: Array[Vector2] = world.markers_in("entity_route")
		entity.reset_encounter(points[0], points)
		entity.show()
		encounter_grace=5.0
```
```gdscript
# interact():
	"hall_back": enter_zone("bedroom", world.marker("BedroomFromHall"))
	"forest_back": enter_zone("hallway", world.marker("HallwayFromForest"))
	# in "house_back":   else: enter_zone("forest", world.marker("ForestFromHouse"))
	# in "front_door":   player.position = world.marker("FrontDoorInside") if player.position.y>680 else world.marker("FrontDoorOutside")
```
In `_on_rock_landed()`:

- `if at.distance_to(Vector2(5870,692))>59: return` becomes `if at.distance_to(world.props["window"].position)>59: return` (the window node already sits at `(5870, 692)`).
- `world.prop("shards","glass",Vector2(5870,720))` becomes `world.prop("shards","glass",world.marker("GlassShards"))`.
- Delete the two lines that set `world.props["reveal"].position` and `.modulate` (the node now carries both). Keep `world.props["reveal"].show()`.

```gdscript
# _tick_sequence() step 2:
	world.props["friend"].position = world.marker("FriendFallen")
# restore_checkpoint():
	if bedroom: enter_zone("bedroom", world.marker("BedroomReset"), false)
	else: enter_zone(checkpoint.get("zone","bedroom"), checkpoint.get("position", world.marker("BedroomSpawn")), false)
```

**Check:** F5; walk bedroom → hallway → back (you appear at the right spots); `test_tutorial` (it uses `interactables` positions and the front door teleport).

#### 8.4 Slice 3 — Sounds placed in the world (L4)

Each of these is an **AudioStreamPlayer2D**. For each: create it, drag the `.wav` (from `res://tutorial/assets/audio/`) into **Stream**, set **Volume Db**, set **Position**, and add it to the group `tutorial_audio` (so `_exit_tree` still silences it, exactly like the old runtime ones).

| Node (parent) | Stream | Volume Db | Position | Extra group | Replaces |
|---|---|---|---|---|---|
| `BranchSnap` (Forest) | `branch.wav` | −4 | `(3630, 215)` | | `play_sound("branch",Vector2(3630,215),-4)` |
| `BehindWall` (Loop) | `behind_wall.wav` | −5 | `(7675, 210)` | | `play_sound("behind_wall",Vector2(7675,210),-5)` |
| `ForestListenerA` (Forest) | `branch.wav` | −4 | `(3630, 285)` | `listeners_forest` | listener 1 |
| `ForestListenerB` (Forest) | `branch.wav` | −4 | `(4010, 285)` | `listeners_forest` | listener 2 |
| `LoopListenerA` (Loop) | `behind_wall.wav` | −4 | `(7640, 278)` | `listeners_loop` | listener 1 |
| `LoopListenerB` (Loop) | `behind_wall.wav` | −4 | `(7850, 278)` | `listeners_loop` | listener 2 |
| `PresenceReveal` (House) | `presence.wav` | −8 | `(5870, 640)` | | `play_sound("presence",Vector2(5870,640))` |
| `PresenceAltar` (House) | `presence.wav` | −8 | `(6230, 170)` | | `play_sound("presence",Vector2(6230,170))` |
| `Thud` (House) | `thud.wav` | −2 | `(6240, 365)` | | `play_sound("thud",Vector2(6240,365),-2)` |

The **parents' ears** need a little structure so each door has both of its sounds. In **Hallway** add two `Marker2D`s, `ParentEarA` at `(1930, 276)` and `ParentEarB` at `(2310, 276)`, both in the group `parent_ears`. Give each of them two `AudioStreamPlayer2D` children (leave their Position at `(0,0)`):

| Child | Stream | Volume Db | Group |
|---|---|---|---|
| `ChairScrape` | `chair_scrape.wav` | −3 | `tutorial_audio` |
| `Rustle` | `parent_rustle.wav` | −7 | `tutorial_audio` |

Code changes in `tutorial.gd`:

```gdscript
# _process(): (the forest/loop cues move to triggers in slice 4 — leave them for now) 

# _tick_hallway():
func _tick_hallway(delta: float) -> void:
	hall_audio_clock -= delta
	var x := player.position.x
	for index in range(2):
		var ear: Node2D = world.landmarks["ParentEarA" if index == 0 else "ParentEarB"]
		if absf(x-ear.global_position.x)<190 and not hall_door_cues.has(index):
			hall_door_cues[index]=true
			hall_cued=true
			say("[Chair scrapes behind the door]\nSPACE · Hold breath" if index==0 else "[Movement behind the door]",6)
			if not test_mode: ear.get_node("ChairScrape").play()
			hall_audio_clock=4.0
	if hall_audio_clock<=0:
		var ear: Node2D = world.landmarks["ParentEarA" if x<2110 else "ParentEarB"]
		if not test_mode: ear.get_node("Rustle").play()
		hall_audio_clock=6.5
	# (the refuge check moves to a trigger in slice 4)
```
```gdscript
# _on_rock_landed():   play_cue("PresenceReveal")
# _begin_attack():     play_cue("PresenceAltar")
# _tick_sequence():    play_cue("Thud")
#                      NoiseManager.emit_noise(world.cue("Thud").global_position,256,NoiseManager.SourceType.ENVIRONMENT)
```
```gdscript
func _on_noise(at: Vector2, radius: float, source: int, _duration: float) -> void:
	# The unseen passages answer audible player actions, without an invisible capture body.
	if zone in ["forest","loop"] and not resetting and ambient_reply_cooldown<=0:
		if source in [NoiseManager.SourceType.FOOTSTEP,NoiseManager.SourceType.SPRINT,NoiseManager.SourceType.BREATH,NoiseManager.SourceType.THROW]:
			var listeners := get_tree().get_nodes_in_group("listeners_forest" if zone=="forest" else "listeners_loop")
			for listener in listeners:
				if at.distance_to(listener.global_position)<=radius:
					if not test_mode: listener.play()
					say("[Branches shift nearby]" if zone=="forest" else "[The dragging stops]",4)
					ambient_reply_cooldown=6.0
					break
	if zone!="hallway" or resetting or not dialogue.is_empty(): return
	# Parent listens to player actions only; ambience never becomes a failure signal.
	if source not in [NoiseManager.SourceType.FOOTSTEP,NoiseManager.SourceType.SPRINT,NoiseManager.SourceType.CROUCH,NoiseManager.SourceType.BREATH,NoiseManager.SourceType.THROW]: return
	for ear in get_tree().get_nodes_in_group("parent_ears"):
		if at.distance_to(ear.global_position)<=radius:
			parent_failures+=1
			request_reset("PARENT: Back to your room. Now.",true)
			return
```

The sounds that play **where the player is** (`pickup`, `door`, `switch`, `parent`, `impossible`…) or where something *landed* (`glass`) are dynamic, so they stay as `play_sound(...)`.

**Check:** F5 — walk the hallway: scrape, then rustle every few seconds; do the forest branch and loop dragging still play? (those are slice 4). `test_tutorial` includes the "environmental answer" check at `Vector2(3580,350)` — the listener positions are identical to the old ones, so it must still pass.

#### 8.5 Slice 4 — Trigger areas (L5)

For each row create an `Area2D` (parent = room), add a child `CollisionShape2D`, in the Inspector choose **Shape → New RectangleShape2D** and set its **Size**; set the **Area2D's Position** to the centre. Then on the **Area2D**:

- Inspector → **Collision → Layer**: untick everything. **Mask**: tick only layer 1 (the player's layer).
- Node dock → Groups → add `story_triggers`.

| Area2D | Parent | Position (centre) | Rectangle Size | Replaces |
|---|---|---|---|---|
| `ForestBranchTrigger` | Forest | `(4070, 400)` | `(1140, 800)` | `player.position.x > 3500` |
| `LoopDragTrigger` | Loop | `(7810, 320)` | `(700, 640)` | `player.position.x > 7460` |
| `HallRefugeTrigger` | Hallway | `(2110, 482)` | `(144, 128)` | `Rect2(2038,418,144,128)` |

Code in `tutorial.gd`: delete the `forest_cued`, `loop_cued` blocks in `_process()` and the refuge block in `_tick_hallway()`. At the end of `_ready()` (after `NoiseManager.noise_emitted.connect(_on_noise)`) add `world.trigger_entered.connect(_on_trigger)`, and add this function:

```gdscript
func _on_trigger(id: String) -> void:
	if resetting or not dialogue.is_empty(): return
	match id:
		"ForestBranchTrigger":
			if forest_cued: return
			forest_cued=true
			say("[A branch snaps beyond the marked path. Nothing moves.]",5)
			play_cue("BranchSnap")
		"LoopDragTrigger":
			if loop_cued: return
			loop_cued=true
			play_cue("BehindWall")
			say("[Slow dragging on the other side of the wall.]",5)
		"HallRefugeTrigger":
			if hall_refuge_cued: return
			hall_refuge_cued=true
			say("Release your breath. Rest here.",6)
```

> **A real difference to know about:** the old code tested the player's *centre point*. An `Area2D` reacts when the player's *collision box* (24×24) touches it, i.e. about 12 px earlier. That's invisible in play.

**Check:** walk into the forest past the marked turn: the branch message and sound; reach the loop room's far side: dragging; stand on the hallway mat: "Release your breath".

#### 8.6 Slice 5 — Groups instead of name lists (S5, L8)

1. **Story lights:** in `world.tscn` select `VestibuleLight`, `AltarLeftLight`, `AltarRightLight` (the three that already carry `lighting_role = "story"`) and add them to the group `story_lights` (multi-select works).
2. **Danger candles:** select the three candles `candle_(985_0, 280_0)`, `candle_(1090_0, 280_0)`, `candle_(510_0, 618_0)` and add them to `danger_candles`. **Don't** add `candle_(300_0, 360_0)`: the code never extinguished that one, and I can't tell whether that was deliberate.
3. **Occupied doors:** nothing to do in the editor — `parent_door_a` and `parent_door_b` already carry `occupied_door = true`. In `world.gd` `_ready()` **delete** the lines
```gdscript
	for id in ["parent_door_a", "parent_door_b"]:
		props[id].listening = true
```
and **inside the double loop**, right after the line `props[String(child.name)] = child` (still inside the `if child.get_script() == Art:` block), add:
```gdscript
				if child.get_meta("occupied_door", false):
					child.listening = true
```
4. Replace `set_house_danger` with:

```gdscript
func set_house_danger(danger: bool) -> void:
	for node in get_tree().get_nodes_in_group("story_lights"):
		var light := node as PointLight2D
		light.energy = 0.12 if danger else float(light.get_meta("rest_energy"))
		light.color = Color("71889b") if danger else light.get_meta("rest_color")
	for candle in get_tree().get_nodes_in_group("danger_candles"):
		candle.extinguished = danger
		candle.queue_redraw()
```
(Lesson 10 changes the last two lines when the candles become sprites.)

**Check:** `test_tutorial` has two lighting assertions after the attack (`AltarLeftLight` dims, `HouseRecoveryLight` stays bright) — they exercise this function.

#### 8.7 Final check for Lesson 8

Search the project (**Ctrl+Shift+F**) for `Vector2(` in `tutorial.gd` and `world.gd`. What's left should be only: the `680` front-door threshold comparison, `Vector2.ZERO`/`INF` and similar. Run all four test scenes.

**If it breaks:** `Invalid get index 'BedroomSpawn' on base 'Dictionary'` → that marker doesn't exist, isn't a *direct child of a room*, or its name differs. A trigger never fires → the Area2D isn't in `story_triggers`, or its Mask doesn't include layer 1, or you put it under the wrong room. A sound is silent → its Stream is empty or it isn't in range of the player (AudioStreamPlayer2D attenuates with distance; raise **Max Distance** if you need to).

---

### Lesson 9 — Props: from `art.gd` drawing to `Sprite2D`
**Fixes A1, A4, A7, A8, A9** · ★★ · ~3 h (the bed in 30 min, the rest is repetition) · Risk: medium

**You'll learn:** `Sprite2D`, `AtlasTexture` and the **Region editor** (cropping part of a big image without cutting the image), scale vs offset, "Change Type", and multi-select editing.

**What changes and what doesn't.** `art.gd` draws every prop by itself. We will turn the **static** ones into plain `Sprite2D` nodes:

| Convert (86 nodes) | Keep as `Art` (they need the readability shader) |
|---|---|
| tree ×50 (35 trees + 15 spruce), lantern ×15, rug ×8, desk ×3, chair ×3, coats ×3, shelf ×2, altar ×1, bed ×1 | actor (player), friend, entity (and `reveal`), flashlight, battery ×4, phone, rocks ×2, marker ×7, window, door ×8 |

The 32 walls are Lesson 12; the 5 candles are Lesson 10. Everything you convert already has its **collision body and light occluder as separate sibling nodes** in `world.tscn` (that's how the scene was generated) — you don't touch those.

**Why a plain `Sprite2D` is better here:** you see the picture in the editor, you can nudge it with the mouse, and there's no `queue_redraw()` running every frame. The numbers in `art.gd` (`CELLS`, the `match` of sizes and offsets) are exactly what you will now type into the Inspector — once.

#### 9A — Make the AtlasTexture library (once, ~20 min)

An **AtlasTexture** is a resource that says "use *this rectangle* of *that image*". You don't edit the PNG at all.

1. FileSystem: create folder `res://tutorial/assets/art/atlas/`.
2. Right-click it → **Create New → Resource…** → `AtlasTexture` → name `bed.tres`.
3. Double-click `bed.tres`. In the Inspector:
   - **Atlas**: drag `res://tutorial/assets/art/props_atlas.png` into the slot.
   - **Region**: click to expand and type **X, Y, W, H** (below). Typing is more exact than dragging.
   - (Optional) click **Edit Region** to see the crop in the bottom panel and check it frames the right object.
4. **Ctrl+S**. Repeat for every row:

| File | Atlas | Region X, Y, W, H |
|---|---|---|
| `bed.tres` | `props_atlas.png` | 95, 0, 190, 317 |
| `desk.tres` | `props_atlas.png` | 366, 20, 250, 283 |
| `shelf.tres` | `props_atlas.png` | 694, 0, 205, 316 |
| `chair.tres` | `props_atlas.png` | 1005, 46, 207, 264 |
| `tree.tres` | `props_atlas.png` | 0, 322, 320, 318 |
| `spruce.tres` | `props_atlas.png` | 340, 322, 265, 318 |
| `altar.tres` | `props_atlas.png` | 666, 370, 282, 269 |
| `lantern.tres` | `props_atlas.png` | 446, 669, 91, 264 |
| `rug.tres` | `props_atlas.png` | 694, 641, 206, 306 |
| `coats.tres` | `props_atlas.png` | 1005, 674, 234, 254 |

These are the `CELLS` rectangles from `art.gd` L16–25, unchanged. (`door`, `actor`, `friend`, `fallen`, `entity` stay in code. `crate` has no instance in the world — it's dead data, so it has no row.)

#### 9B — Convert one prop completely: the bed

1. Open `world.tscn`. In the Scene dock, expand **Bedroom** and click the node **bed**.
2. Right-click → **Change Type…** → type `Sprite2D` → *Change*. The node's icon changes.
3. Right-click it again → **Detach Script** (in some versions called *Clear Script*). The `kind` and `dimensions` fields vanish from the Inspector — the picture will now come from the Sprite2D itself.
4. Inspector → **Texture**: drag `bed.tres` into the slot. The bed appears in the viewport.
5. Inspector → **Transform → Scale**: type **0.7368** (x) and **0.694** (y). Leave **Offset → Offset** at `(0, 0)` — for the bed the picture is centred on the node.
6. Under **CanvasItem** confirm the values that were already saved on the node: **Z Index = 1**, **Light → Mask = layer 2 only**, **Texture → Filter = Nearest**, **Material = `scenery_default.tres`** (drag it in if it still holds a private copy).
7. Optional: **Modulate** `(1.15, 1.12, 1.07)` — the old code brightened props by ~10 %. If the colour picker won't accept values above 1.0, skip it (open the picker and use its **Raw** mode if you want to type them).
8. **Ctrl+S** and run the game (F5): the bed should be where it was, the same size.

> **How the numbers were derived** (so you can do the same for new props): the old code drew the picture into a rectangle `size` wide and tall with its *bottom* edge `bottom` pixels below the node. **Scale = size ÷ crop size** (bed: 140÷190 = 0.7368, 220÷317 = 0.694). **Offset.y = (bottom − size.y/2) ÷ Scale.y**, because a `Sprite2D` is centred on its node by default. If you ever wonder why a prop sits too high or low, that's the number to check.

#### 9C — Convert the rest (the table)

Use **Appendix A** for exact Scale and Offset per prop. The efficient way, per group:

**Trees (50)**

1. Scene dock → *Filter nodes*: `tree_`. Click the first, Shift+click the last → 50 selected.
2. Right-click → **Change Type…** → `Sprite2D` (applies to all). Then **Detach Script** (works on a selection too).
3. Inspector (multi-edit): Texture = `tree.tres`, **Scale** `(0.4844, 0.5818)`, **Offset** `(0, -107.4)`, **Material** = `scenery_tree.tres`.
4. Now select **only the 15 spruce** — Ctrl+click each: `tree_14, tree_24, tree_25, tree_26, tree_28, tree_30, tree_37, tree_39, tree_40, tree_42, tree_58, tree_63, tree_70, tree_71, tree_72`. Set Texture = `spruce.tres` and **Scale** `(0.5849, 0.5818)`.

   > Those 15 are the trees where `int(position.x) % 3 == 0` — the rule `art.gd` L101 used to choose "spruce". Now it's an explicit, visible choice you can change per tree.

**Lanterns (15)** — filter `Lantern`, select all, Change Type + Detach Script, Texture `lantern.tres`, Scale `(0.2088, 0.2083)`, Offset `(0, -74.4)`, Material default. (They are children of the lights; they keep their position at the light's origin.)

**Everything else** — one at a time using Appendix A: the 8 rugs (each a different Scale, Offset `(0,0)`), 3 desks, 3 chairs, 3 coats, 2 shelves, and the altar. Delete the stray **`altar_pray`** *only after* checking it is a duplicate (see Bonus findings): select it, click the eye icon next to it in the Scene dock to hide it, look at the viewport, and if nothing changes remove it — or turn it into a `Marker2D` if you still need an interaction anchor.

**What you lose, and how to get it back.** The old code drew two faint black ellipses under props ("contact shadows"). A plain `Sprite2D` doesn't. If you miss them, **Appendix D** shows how to add one with a radial gradient. The characters, doors and pickups that remain in `art.gd` still get theirs.

**Check it worked:** compare with `requiem/docs/organic-tutorial/screenshots/01-bedroom.png` and `03-forest.png`. Run `test_tutorial.tscn`, `test_lighting_response.tscn`. In the Scene dock, 86 fewer nodes should carry the script icon (87 if you also removed `altar_pray`).

**If it breaks:**
- *Sprite is tiny/huge* → Scale typed into the wrong field, or into **Region** instead of **Transform**.
- *Sprite is too high/low* → Offset (see the derivation).
- *Prop looks unlit/black* → **Light → Mask** must be layer **2** for everything except rugs (layer 1).
- *Prop is drawn over the player* → **Z Index** must be 1 (rugs: 0).

---

### Lesson 10 — Candles: a prop with two states
**Fixes A2, A8, L8** · ★★ · ~45 min · Risk: low

**You'll learn:** saving a branch of nodes as a **scene** (`Save Branch as Scene`), instancing it, toggling states with `visible`, and using groups to talk to many nodes at once.

**Why:** a candle is "one picture when lit, a shorter picture when out". `art.gd` re-crops the atlas by 27 % in code; `world.gd` flips a flag on three nodes picked by *name strings made from coordinates*. Two child sprites and a group do the same, visibly.

1. Open `world.tscn`, select **bedroom_candle** (Bedroom). Right-click → **Detach Script** (it's already a `Node2D`, so no type change is needed). Its saved Light Mask / Z Index / Material now belong to an empty parent; you'll set them on the sprites in step 3.
2. Make two AtlasTextures in `res://tutorial/assets/art/atlas/` from **`details_atlas.png`** (not the props atlas):

| File | Region X, Y, W, H |
|---|---|
| `candle_lit.tres` | 1396.1, 479.0, 337.1, 328.2 |
| `candle_out.tres` | 1396.1, 567.6, 337.1, 239.6 |

3. Under `bedroom_candle` add two **Sprite2D** children:

| Name | Texture | Scale | Offset | Visible |
|---|---|---|---|---|
| `Lit` | `candle_lit.tres` | `(0.0742, 0.0823)` | `(0, -18.2)` | on |
| `Out` | `candle_out.tres` | `(0.0742, 0.0823)` | `(0, 26.1)` | **off** |

   On both children set: **Light → Mask** = layer 2, **Z Index** = 1, **Texture → Filter** = Nearest, **Material** = `scenery_default.tres`.
4. Right-click `bedroom_candle` → **Save Branch as Scene** → `res://tutorial/props/candle.tscn` (create the `props` folder in the dialog if needed). The node in the world now *is* an instance of that scene.
5. Replace the four candles in **House** the same way: for each of `candle_(985_0, 280_0)`, `candle_(1090_0, 280_0)`, `candle_(510_0, 618_0)`, `candle_(300_0, 360_0)`: note its **Position** (they're `(6185,280)`, `(6290,280)`, `(5710,618)`, `(5500,360)`), delete the node, drag `candle.tscn` into the House node, set the Position you noted, and rename it to something readable (e.g. `candle_altar_left`).
6. Select the three that used to be extinguished (**not** `(5500,360)`) → Node dock → Groups → `danger_candles` (you may already have added these in Lesson 8 slice 5; re-do it for the new instances).

**Code:** in `world.gd`'s `set_house_danger` replace the last two lines of the candle loop with:

```gdscript
	for candle in get_tree().get_nodes_in_group("danger_candles"):
		candle.get_node("Lit").visible = not danger
		candle.get_node("Out").visible = danger
```

In `art.gd` delete the `"candle"` entry in `DETAIL_REGIONS` and the `if kind == "candle" and extinguished:` block in `_draw_detail()`, and `"candle"` from the `queue_redraw()` list in `_process()`.

**Check it worked:** run `test_tutorial.tscn` (it checks the altar lights and recovery lamp after the attack). Play to the attack: the three altar-room candles go out.

---

### Lesson 11 — Floors and the forest trail
**Fixes A6** · ★★ · ~1.5 h · Risk: medium

**You'll learn:** `Sprite2D` **Region + Texture Repeat** (tiling a texture across a rectangle), `Line2D`, and draw order.

**Why:** `world.gd._draw()` loops over rectangles and calls `draw_texture_rect_region` for every 256 px of every room. One `Sprite2D` per room does the same job, and you can see and resize it.

#### 11A — Cut the material cells into their own PNGs (outside Godot, once)

`materials_atlas.png` is 1254×1254 = four 627×627 cells (0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right). Texture repeat needs each cell as **its own image**, resized to the 256 px size the old code drew them at.

*Using Python + Pillow* (run from the repository root):

```python
from PIL import Image
atlas = Image.open("requiem/tutorial/assets/art/materials_atlas.png")
cell = atlas.width // 2                      # 627
names = {0: "floor_room", 1: "floor_forest", 2: "wall_top", 3: "trail"}
import os; os.makedirs("requiem/tutorial/assets/art/materials", exist_ok=True)
for i, name in names.items():
    x, y = (i % 2) * cell, (i // 2) * cell
    atlas.crop((x, y, x + cell, y + cell)).resize((256, 256), Image.LANCZOS) \
         .save(f"requiem/tutorial/assets/art/materials/{name}.png")
```

*Without Python:* open the atlas in any image editor (GIMP, Krita, Photopea in the browser…), select each 627×627 quarter, copy it into a new image, resize to 256×256, export PNG with the names above. Godot imports them automatically.

#### 11B — One floor sprite per room

For each room in `world.tscn`:

1. Add a child **Sprite2D** named `Floor`. In the Scene dock, **drag it to the top** of that room's children (it must draw first). Check: Move Up repeatedly, or drag.
2. Inspector settings:

| Property | Value |
|---|---|
| Texture | `floor_room.png` (Forest: `floor_forest.png`) |
| Offset → Centered | **off** |
| Region → Enabled | **on** |
| Region → Rect | `(0, 0, W, H)` of the room (see below) |
| CanvasItem → Texture → **Repeat** | **Enabled** |
| CanvasItem → Visibility → Modulate | `(0.88, 0.88, 0.81)` |
| CanvasItem → Material | `scenery_floor.tres` |
| CanvasItem → Texture → Filter | Nearest |
| Transform → Position | room's top-left (below) |

| Room | Position | Region Rect W×H |
|---|---|---|
| Bedroom | `(0, 0)` | 960 × 640 |
| Hallway | `(1600, 0)` | 960 × 640 |
| Forest | `(3200, 0)` | 1440 × 800 |
| House | `(5200, 0)` | 1280 × 960 |
| Loop | `(7200, 0)` | 960 × 640 |

3. If the texture shows once and stops, **Repeat** wasn't set on this node (not on its parent).

#### 11C — The trail

In **Forest**, add five more `Sprite2D`s right after `Floor`, named `Trail1`…`Trail5`. All five: Texture `trail.png`, Centered **off**, Region Enabled, Texture **Repeat = Enabled**, Modulate `(0.85, 0.82, 0.72)`, Material `scenery_floor.tres`. Each rectangle is the old path segment grown by 47 px on every side:

| Node | Position | Region Rect (0, 0, W, H) |
|---|---|---|
| `Trail1` | `(3213, 493)` | `414 × 94` |
| `Trail2` | `(3533, 303)` | `94 × 284` |
| `Trail3` | `(3533, 303)` | `544 × 94` |
| `Trail4` | `(3983, 303)` | `94 × 284` |
| `Trail5` | `(3983, 493)` | `614 × 94` |

For the soft darker edge the old code drew along the path, add one **Line2D** named `TrailVerge` (before the trail sprites) with **Points** `(3260,540) (3580,540) (3580,350) (4030,350) (4030,540) (4550,540)`, **Width 108**, **Default Color** `(0.28, 0.28, 0.17, 0.35)`, **Antialiased** on.

> **Prefer real tiles?** A `TileMapLayer` also works for floors (you'd make a TileSet whose tile size is 256 and paint it). I chose `Sprite2D` here because the trail is only 94 px wide — narrower than one 256 px tile — and sprites can be any size.

#### 11D — Remove the drawing code

In `world.gd` delete: the `_draw()` function, the `queue_redraw()` call in `_ready()`, and the `@export_category("Floor")` / `@export var floor_details` lines (the trail path data now lives in the sprites; the leftover `floor_details` array saved on the root node simply disappears the next time you save the scene). In `materials.gd` delete the `paint()` function only if **Lesson 12** is done or you have no walls left as `Art` (`art.gd` still calls it for `kind == "wall"`).

**Check it worked:** compare room floors against `requiem/docs/organic-tutorial/screenshots/*.png`. Run `test_tutorial.tscn`.

**If it breaks:** a floor is covering the props → it isn't the first child of its room, or its Z Index isn't 0. A seam between repeats → turn **Texture → Filter** to Nearest.

---

### Lesson 12 — Walls as tiles (advanced; start with one room)
**Fixes A3** · ★★★ · ~half a day · Risk: high

**You'll learn:** `TileSet`, the **physics** and **occlusion** layers of a tile, `TileMapLayer`, painting tiles, and why navigation must be re-baked.

**First, decide.** Read section 5. The wall tiles in `level/walls_tileset.tres` are 32×32; the tutorial's walls are 24 px thick and look different. I recommend **practising on the Bedroom** (it's four plain walls: top, bottom, left, right — no doorway gaps; the exit is an interaction object), and using the tile system for the *next new room*, rather than retrofitting all 32 walls.

#### 12A — Wall art that fits the 32 px grid

`walls_tileset.tres` has one atlas source from `assets/sprites/wall.png` (64×64 = four 32×32 tiles at atlas coords (0,0), (1,0), (0,1), (1,1)), each with a full-tile **collision polygon** and **occluder polygon**. The easiest way to restyle walls without losing that setup is to **swap the picture, keeping the same 2×2 layout**.

1. Make a new **64×64** PNG `wall_tutorial.png` (e.g. in `assets/sprites/`) with four 32×32 tiles. Suggested content: top-left and bottom-left = wall top (cell 2, resized to 32 px); top-right and bottom-right = wall face (cell 0, resized to 32 px). Python:

```python
from PIL import Image
atlas = Image.open("requiem/tutorial/assets/art/materials_atlas.png")
c = atlas.width // 2
top  = atlas.crop((0, c, c, 2*c)).resize((32, 32), Image.LANCZOS)      # cell 2
face = atlas.crop((0, 0, c, c)).resize((32, 32), Image.LANCZOS)        # cell 0
sheet = Image.new("RGBA", (64, 64))
for (x, y, tile) in [(0, 0, top), (32, 0, face), (0, 32, top), (32, 32, face)]:
    sheet.paste(tile, (x, y))
sheet.save("requiem/assets/sprites/wall_tutorial.png")
```

2. Double-click `res://level/walls_tileset.tres`. The **TileSet** panel opens at the bottom. Click the atlas source (`Muro madera (wall.png)`). In the Inspector change **Texture** to `wall_tutorial.png`. (If Godot asks about tiles, keep the four existing ones — they already carry the collision and occluder shapes. The new image has the same 64×64 size, so nothing should need regenerating.)
3. To tint a tile like the old walls: in the TileSet panel choose the **Select** tab, click a tile, and in the Inspector set **Rendering → Modulate** (tops `(0.46, 0.47, 0.43)`, faces `(0.34, 0.31, 0.28)`).

> **Careful:** this edits the TileSet that `level_template.tscn` also uses. If you'd rather not change the template's look, **duplicate** the file (right-click → Duplicate) and use the copy for the tutorial.

#### 12B — Paint the Bedroom

1. In `world.tscn`, select **Bedroom**, add a child **TileMapLayer** named `Walls`. Inspector → **Tile Set** → drag `walls_tileset.tres`.
2. Set the layer's **Transform → Position** to `(0, 0)`, **Z Index** to `1` (the old `WallArt` nodes used 1) and **Material** to `scenery_default.tres`. The bedroom is 960×640 px = **30×20 tiles** of 32 px.
3. With `Walls` selected, the **TileMap** panel opens at the bottom. Pick a top tile, choose the **Rect** tool, and drag to fill row 0 (x 0→29). Do the bottom row (y 19), left column (x 0, y 0→19), right column (x 29, y 0→19). Use a face tile for the bottom edge of the horizontal walls if you want the "front face" look.
4. Delete the old wall nodes: `Wall01`, `Wall02`, `Wall03`, `Wall04` (each with its `CollisionShape2D`, `LightOccluder2D`, `WallArt`).
5. In the Scene dock check the room is still enclosed: F5 — walk against all four walls.

#### 12C — Re-bake navigation (don't skip)

The three `NavigationRegion2D`s in `world.tscn` were baked from the old collision bodies. The bedroom has **no** navigation region (the entity doesn't go there) so the Bedroom is safe; but **any** room whose walls you convert needs its region re-baked: select the `NavigationRegion2D` → click **Bake NavigationPolygon** in the toolbar, and make sure the new `Walls` layer is in the region's source group (the regions use the group `tutorial_obstacles`: select `Walls` → Node dock → Groups → add it). This is also where the possible issue in "Bonus findings" lives, so it's worth a look.

**Check it worked:** the bedroom looks like a room; the player can't leave; shadows from the flashlight fall on the walls. Run `test_tutorial.tscn` and `test_level_template.tscn` (which uses the same TileSet).

**If it breaks:** the player walks through walls → the TileSet's tiles lost their physics polygon (you pressed *Yes* on regenerate, or used the wrong atlas coords). No shadows → the occlusion polygon is missing, or the occluder's light mask doesn't match the light's *Shadow → Item Cull Mask*. Walls look unlit → the layer's **Light Mask** must be layer 1.

---

### Lesson 13 — Scene tiles: paint a forest
**Fixes A1 (trees, alternative)** · ★★★ · ~2 h · Risk: medium

**You'll learn:** building a prop *scene* with art + collision + shadow caster together, adding it to the project's `props_tileset.tres` **scenes collection**, and painting it.

**Why:** a tree today is **four nodes in two places** — `tree_N` (art), `TreeTrunkNN` (body), its `CollisionShape2D`, its `LightOccluder2D` — ×50 = 200 nodes and ~100 sub-resources. As a scene it is one thing you paint.

> Scene tiles snap to the 32 px grid and can't carry per-instance data (section 5). Trees are perfect for that. Don't use this for pickups or doors.

1. **Scene → New Scene → Other Node → StaticBody2D**, rename `Tree`.
2. Add child **Sprite2D** `Sprite`: Texture `tree.tres`, Scale `(0.4844, 0.5818)`, Offset `(0, -107.4)`, Material `scenery_tree.tres`, **Light → Mask = layer 2**, **Z Index 1**, Filter Nearest.
3. Add child **CollisionShape2D**: Shape → New RectangleShape2D, **Size `(20, 28)`**, **Position `(0, 9)`** (the old trunk body).
4. Add child **LightOccluder2D**: **Occluder → New OccluderPolygon2D**; with it selected, click the 2D viewport and draw a rounded rectangle roughly 20×28 around the trunk (centre `(0, 9)`). Set **Occluder Light Mask = 2**.
5. Save as `res://tutorial/props/tree.tscn`. Repeat (or duplicate and change the texture/scale) for `spruce.tscn`.
6. Open `res://level/props_tileset.tres`. In the TileSet panel select the **Escenas** (scenes collection) source and click **+** to add `tree.tscn` and `spruce.tscn`.
7. In `world.tscn`, under **Forest** add a **TileMapLayer** named `Trees` with Tile Set = `props_tileset.tres`. In the TileMap panel choose the scene tile and paint with the pencil, or the Line/Rect tools for rows.
8. Delete the old `tree_N` + `TreeTrunkNN` nodes (filter `tree_` and `TreeTrunk`, select all, Delete).
9. Re-bake the Forest navigation (as 12C; add `Trees` to the obstacle group).

**Check it worked:** the forest still blocks you at trunks, casts shadows, and the entity (if you test it) paths around them. Run `test_tutorial.tscn` and `test_level_template.tscn`.

---

### Lesson 14 — What remains in `art.gd` (the final checklist)
**Fixes A9** · ★ · ~30 min

After lessons 9–13, `art.gd` should only serve the nodes that use the **readability shader pipeline** (actor, friend, entity, flashlight, battery, phone, rocks, marker, window, door). Tick these off:

- [ ] `CELLS` contains only `door`, `actor`, `friend`, `fallen`, `entity`.
- [ ] `DETAIL_REGIONS` contains only `flashlight`, `battery`, `phone`, `rocks`, `window`, `broken`, `marker`.
- [ ] `_ready()`: the tree/rug material blocks are gone (Lesson 6); the `material == null` fallback remains for runtime nodes.
- [ ] `_draw()`: the `"wall"` and `"glass"` cases are gone, and `Materials.paint(...)` is no longer called.
- [ ] `_draw_sprite()`: only the `match` cases for `actor`, `friend`, `entity`, `door` remain; the `tree → spruce` rule and the `rug` check are gone.
- [ ] `_draw_detail()`: the candle branch is gone.
- [ ] `materials.gd` is empty or deleted (also remove `const Materials := preload(...)` from `art.gd` and `world.gd`).
- [ ] `world.gd` has no `_draw`, no `floor_details`, no `REGIONS`, no `lamp`, no `prop()` (unless shards stayed).
- [ ] `tutorial.gd` has no `Vector2(x, y)` literal left (the `680` front-door threshold is a plain number).
- [ ] All four test scenes pass; `git diff --stat` shows `world.tscn` much smaller.

**Optional extra (L9) — camera limits without code.** Your PhantomCamera addon has a **Limit → Limit Target** property that accepts a `TileMapLayer` or a `CollisionShape2D`. If you give each PhantomCamera2D a limit target, `tutorial_camera_rig.gd`'s `apply_region()` no longer needs to set four limits per shot in code. It needs care (the rig also computes a safe inset and minimum zoom for the camera-shake noise), so only try it once everything above is done and committed.

**Honest expectation:** `art.gd` will still be roughly **160 lines**: the readability system (~80 lines — the extra sprites and the ~10 shader parameters that change with focus/threat) plus the drawing of the ~26 nodes that use it. That is the right size for something that is real behaviour. If you want to go further, a later step is to split that system into its own small script (`prop_readability.gd`) and keep `art.gd` for nothing — but that is a design refactor, not a "do it by hand" job.

---

## 9. Appendices

### Appendix A — Exact Scale and Offset for every static prop

(All sprites: `Centered` on, `Offset.x = 0`. Region numbers are in Lesson 9A. The "Used by" column lists the node names in `world.tscn`.)

| Prop texture | Scale (x, y) | Offset (0, y) | Used by |
|---|---|---|---|
| `bed.tres` | (0.7368, 0.694) | 0 | bed |
| `desk.tres` | (0.88, 0.5597) | −65.6 | desk (bedroom) |
| `desk.tres` | (0.6, 0.3816) | −76.0 | porch_bench |
| `desk.tres` | (0.4, 0.318) | −39.3 | house_table |
| `shelf.tres` | (0.5366, 0.4747) | 0 | wardrobe |
| `shelf.tres` | (0.3512, 0.7595) | 0 | house_shelf |
| `chair.tres` | (0.3623, 0.3636) | −44.0 | room_chair, house_chair, altar_chair |
| `altar.tres` | (0.5248, 0.4758) | −54.6 | altar |
| `coats.tres` | (0.4957, 0.374) | −94.9 | hall_coats, porch_coats, loop_coats |
| `lantern.tres` | (0.2088, 0.2083) | −74.4 | the 15 `Lantern` nodes |
| `tree.tres` | (0.4844, 0.5818) | −107.4 | 35 trees (all `tree_N` except the 15 below) |
| `spruce.tres` | (0.5849, 0.5818) | −107.4 | tree_14, 24, 25, 26, 28, 30, 37, 39, 40, 42, 58, 63, 70, 71, 72 |
| `rug.tres` | (1.2621, 0.5882) | 0 | bed_rug |
| `rug.tres` | (1.1408, 0.3007) | 0 | room_hearth_mat |
| `rug.tres` | (3.8835, 0.2288) | 0 | hall_runner |
| `rug.tres` | (0.6117, 0.4183) | 0 | hall_refuge_mat |
| `rug.tres` | (1.068, 0.5229) | 0 | vestibule_rug |
| `rug.tres` | (1.4078, 0.7843) | 0 | altar_rug |
| `rug.tres` | (3.1553, 0.3595) | 0 | loop_rug |
| `rug.tres` | (0.6311, 0.5556) | 0 | loop_refuge_mat |

Light mask: **layer 2** for everything above **except the rugs (layer 1)**. Z Index: 1, except rugs (0). These are the values `world.tscn` already saves on those nodes — check, don't retype.

### Appendix B — All the coordinates in one place

| Kind | Name | Parent | Position / Rect | Notes |
|---|---|---|---|---|
| ReferenceRect | `Bounds` | Bedroom | pos (0,0) · size (960,640) | |
| ReferenceRect | `Bounds` | Hallway | pos (1600,0) · size (960,640) | |
| ReferenceRect | `Bounds` | Forest | pos (3200,0) · size (1440,800) | |
| ReferenceRect | `Bounds` | House | pos (5200,0) · size (1280,960) | |
| ReferenceRect | `Bounds` | Loop | pos (7200,0) · size (960,640) | |
| Marker2D | `BedroomSpawn` | Bedroom | (340,440) | |
| Marker2D | `HallwaySpawn` | Hallway | (1710,340) | |
| Marker2D | `ForestSpawn` | Forest | (3350,540) | |
| Marker2D | `HouseSpawn` | House | (5730,850) | |
| Marker2D | `LoopSpawn` | Loop | (7330,330) | |
| Marker2D | `BedroomFromHall` | Bedroom | (820,460) | |
| Marker2D | `HallwayFromForest` | Hallway | (2450,340) | |
| Marker2D | `ForestFromHouse` | Forest | (4460,540) | |
| Marker2D | `BedroomReset` | Bedroom | (760,425) | |
| Marker2D | `FrontDoorInside` | House | (5737,620) | |
| Marker2D | `FrontDoorOutside` | House | (5737,755) | |
| Marker2D | `GlassShards` | House | (5870,720) | |
| Marker2D | `FriendFallen` | House | (6240,392) | |
| Marker2D | `EntityRoute1/2/3` | House | (6030,330) · (6080,360) · (6080,500) | group `entity_route` |
| Marker2D | `ParentEarA` / `ParentEarB` | Hallway | (1930,276) / (2310,276) | group `parent_ears`; children `ChairScrape`, `Rustle` |
| AudioStreamPlayer2D | `BranchSnap` | Forest | (3630,215) | `branch.wav`, −4 dB |
| AudioStreamPlayer2D | `BehindWall` | Loop | (7675,210) | `behind_wall.wav`, −5 dB |
| AudioStreamPlayer2D | `ForestListenerA/B` | Forest | (3630,285) · (4010,285) | `branch.wav`, −4 dB, group `listeners_forest` |
| AudioStreamPlayer2D | `LoopListenerA/B` | Loop | (7640,278) · (7850,278) | `behind_wall.wav`, −4 dB, group `listeners_loop` |
| AudioStreamPlayer2D | `PresenceReveal` | House | (5870,640) | `presence.wav`, −8 dB |
| AudioStreamPlayer2D | `PresenceAltar` | House | (6230,170) | `presence.wav`, −8 dB |
| AudioStreamPlayer2D | `Thud` | House | (6240,365) | `thud.wav`, −2 dB |
| Area2D | `ForestBranchTrigger` | Forest | centre (4070,400) · size (1140,800) | group `story_triggers` |
| Area2D | `LoopDragTrigger` | Loop | centre (7810,320) · size (700,640) | group `story_triggers` |
| Area2D | `HallRefugeTrigger` | Hallway | centre (2110,482) · size (144,128) | group `story_triggers` |
| PointLight2D | `RevealLight` | House | (5870,642) | hidden; see Lesson 7B |
| Groups | `story_lights` | — | VestibuleLight, AltarLeftLight, AltarRightLight | |
| Groups | `danger_candles` | — | the three altar-room candles | |

### Appendix C — Names the code and tests depend on (don't rename or reorder)

- **Scene `tutorial.tscn`:** `TutorialWorld`, `Player`, `Entity`, `HUD`, `AmbientAudio`, `PrayerAudio`.
- **Scene `player.tscn`:** `Camera2D`, `FootstepNoise`, `HoldBreath`, `Throw`, `flashlight`, `LocalLight`, `Appearance`, `Sprite2D`; and, after Lesson 7, the `PropLight` children of `flashlight` and `LocalLight`.
- **`world.tscn` rooms:** `Bedroom`, `Hallway`, `Forest`, `House`, `Loop` (direct children of the root).
- **`world.props[...]` (nodes using `art.gd`):** `window`, `friend`, `reveal`, `battery`, `forest_rocks`, `parent_door_a`, `parent_door_b`, plus `shards` (runtime) and `entry_collision` (alias of `EntryCollision`).
- **`world.landmarks[...]`:** `EntryCollision`, `WindowCollision`, `ForestNavigation`, `HouseNavigation`, `LoopNavigation`, `AltarLeftLight`, `VestibuleLight`, `AltarRightLight`, `HouseRecoveryLight`, `BedroomDeskLight`, and every marker/cue you add.
- **Index-based lookup:** `world.window_body.get_child(1)` in `tutorial.gd` and tests is the `LightOccluder2D` of `WindowCollision` — **do not add or reorder children of `WindowCollision`.**
- **Order of `navigation_regions`:** `[Forest, House, Loop]`; `tutorial.gd` re-bakes `navigation_regions[1]` (House).
- **Every `PropLight` child name:** tests read `get_node("PropLight")`.
- **Interaction ids** (metadata on the nodes): `phone, flashlight, battery, bedroom_exit, hall_back, hall_exit, forest_back, forest_rocks, forest_battery, forest_exit, front_door, window, porch_rocks, porch_battery, house_back, altar_pray, friend, house_battery, loop_back, loop_end`.

### Appendix D — Optional: a soft contact shadow under a prop

1. Create `res://tutorial/assets/art/contact_shadow.tres`: **Create New → Resource → GradientTexture2D**. **Width 128, Height 128.** Under **Gradient** create a new Gradient with two points: offset `0` → black with alpha `0.25`; offset `1` → black with alpha `0`. **Fill = Radial**, **Fill From** `(0.5, 0.5)`, **Fill To** `(1.0, 0.5)`.
2. Add a `Sprite2D` named `Shadow` as a **sibling** of the prop (a child of the room, placed *before* it in the tree so it draws underneath), not a child — a child would inherit the prop's scale. Texture = `contact_shadow.tres`. **Position** = the prop's position + `(2, bottom − 3)`. **Scale** = `(prop_width × 0.68 ÷ 128, 16 ÷ 128)`. Z Index 0, Light Mask 1.
3. For a prop 140 px wide with its feet 110 px below its node centre: Scale `(0.744, 0.125)`, Position `(prop.x + 2, prop.y + 107)`.

### Appendix E — Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Editor shows red errors in the Output panel as soon as you open `world.tscn` | `art.gd` or `world.gd` (`@tool`) hit a missing node/variable you removed | Read the line number in the error; restore the thing it needs, or finish the lesson step that updates that line. |
| `Invalid access to property or key 'X' on a base object of type 'Dictionary'` | A name used in `landmarks[...]` / `props[...]` doesn't exist | Check spelling and that the node is a **direct child of a room**. |
| `Node not found: "AudioPlayer"` | The `@onready` path doesn't match the child's name | Rename the child, or fix the path. |
| A change I made in the Inspector vanished on run | The same property is set again in code | Search the project (Ctrl+Shift+F) for the property name; delete the code line. |
| Game runs but the whole scene is black | `CanvasModulate` is fine; a light is missing or `RevealLight`/`PropLight` is mis-parented | Check lights are children of the right nodes; compare with `HallEntryLight`'s hierarchy in `world.tscn`. |
| A test fails after a lesson | You changed something it checks | Open the failing line; the lesson tells you which test lines to update (8.2). |
| I broke everything | Happens. | `git restore .` (discard uncommitted work) and redo the lesson slowly. |

### Appendix F — A tiny glossary

- **Anchor / Layout (Control nodes):** how a UI node sticks to a corner or fills its parent.
- **Autoload:** a script or scene Godot loads once at startup and keeps alive for the whole game; reachable by name from anywhere (`GameState`).
- **CanvasLayer:** a node that draws its children on top of the world, fixed to the screen (HUD).
- **Instance:** a copy of a scene placed inside another scene.
- **Inspector:** the panel of properties for the selected node or resource.
- **Marker2D:** a node whose only job is to mark a position.
- **Occluder (`LightOccluder2D`):** a shape that blocks 2D light and casts a shadow.
- **Region (of a texture):** the rectangle of an image to draw.
- **Sub-resource:** a resource stored *inside* a `.tscn` instead of in its own file.
- **`@tool`:** a script annotation meaning "also run this inside the editor".
- **TileMapLayer / TileSet:** a grid you paint with tiles; the TileSet is the set of tiles (and their collision/shadow shapes).
