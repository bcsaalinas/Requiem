# Character footsteps

`python3 tools/audio/bake_footsteps.py` requires Python 3 and ffmpeg. It extracts eight mono PCM one-shots from the existing `requiem/assets/audio/freesound_community-concrete-footsteps-1-6265.mp3`; the original is preserved. No downloaded or generated audio is introduced. The original asset's source reference is https://pixabay.com/sound-effects/concrete-footsteps-1-6265/ (freesound_community); these edits retain the original asset's licensing, rather than assigning a new license.

`footsteps_manifest.json` records the original SHA-256, exact cut starts, duration, processing, gain and output hashes. Clips are 24 kHz / 16-bit / mono, 250–260 ms, with an immediate attack, mild low/high-pass filtering and a 55 ms tail fade. Normalization targets the first 120 ms at -23 dB RMS, with -3 dBFS peak and +18 dB gain caps. The same natural bank supports walking, sprinting and held-breath movement.

`FootstepNoise` retains gameplay cadence/radii and the inspector's clip/volume settings. `FootstepAudio` runs at physics priority 30, after `PlayerAim` resolves independent contacts. Only false-to-true contact changes during real displacement trigger sound at the planted boot. Three world-space voices preserve short tails and stop on cancellation/reset/teleport; a normal stop lets a released impact finish. Stationary pivots, wall pushing and pose settling do not trigger steps.

The player has eight walk-bank clips. Sprint falls back to that bank when no dedicated sprint bank is assigned. Playback excludes the previous clip where alternatives exist, varies pitch ±3.5% and gain ±0.7 dB with a private RNG, adds 2.5 dB for sprint, and subtracts 8 dB for held breath. These audio choices do not emit gameplay noise or alter global random state. Hearing remains at 0.45 s walk/sprint, 0.70 s held, with 3/6/1-unit radii.

Manual review: Test Lab → Sprint → Steps on/off. Real walk/run/held movement, direction changes, stopping and wall contact use the shared player. The current bank is one generic hard-surface set; material-specific footsteps are a separate future audio pass.
