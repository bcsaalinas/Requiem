# Monster vocal cues

Source: Monster Sound Effects Pack by Ogrebane
https://opengameart.org/content/monster-sound-effects-pack
Download: https://opengameart.org/sites/default/files/monster_sfx_pack.zip
License: CC0 1.0 — https://creativecommons.org/publicdomain/zero/1.0/
Retrieved: 2026-11-18.

Converted to mono 44.1 kHz WAV; loudness normalized (target -20 LUFS, -3 dBTP).
- hunt_scream.wav: monster-6.wav (played slower to match the scream hold).
- catch.wav: monster-8.wav.
- search_growl.wav: monster-1.wav.
- investigate.wav: monster-2.wav.

Existing breathing and movement recordings retain their existing sources/licenses.
The pre-existing DCSFX breathing is CC BY-NC 3.0:
https://freesound.org/people/DCSFX/sounds/366137/

## Devour cue

In the game this file is the sound set `entity/kill` (`assets/audio/entity/kill/devour.wav`),
played by `entities/entity_audio.gd`.

`devour.wav`: wet flesh Foley + slowed tearing + Ogrebane's lowered capture growl.
Mono 44.1 kHz WAV, 1.10 s, loudness target -13 LUFS, true-peak target -1.5 dBTP.
Starts on hide_player at 740 ms and finishes before the 1.9 s game-over transition.
The earlier crunchy-bite source is no longer used.

Sources (CC0 1.0), retrieved 2026-11-18:
- Sclolex, ZombieEatingFlesh.wav:
  https://freesound.org/people/Sclolex/sounds/236331/
  Public HQ preview: https://cdn.freesound.org/previews/236/236331_985466-hq.mp3
  Excerpt 0.35–1.35 s, lowered to 85% pitch/rate, high-pass at 80 Hz.
- aust_paul, rip_tear FLESH!.wav:
  https://freesound.org/people/aust_paul/sounds/30931/
  Public HQ preview: https://cdn.freesound.org/previews/30/30931_15696-hq.mp3
  Lowered to 80% pitch/rate, high-pass at 100 Hz.
- Ogrebane, catch.wav source above: lowered to 65% pitch/rate, low-pass at 1800 Hz.

Layers mixed, compressed, trimmed and faded at the tail; loudness normalized.
License: https://creativecommons.org/publicdomain/zero/1.0/
