# Character rig source

The runtime rig is `requiem/player/art/girl_rig_v2/`. This folder retains the original generated modular source, deterministic bake scripts and manifests. Runtime provenance is in `PROVENANCE.txt` beside the exported assets. No authoring dependency is required to play the game.

Use Python 3 and Pillow (the preview uses Pillow's sized default font). From this folder:

```sh
python export_assets.py
python export_action_layers.py --review-dir previews
```

`export_assets.py` builds directional idle/walk/sprint frames and the Godot SpriteFrames resource. `export_action_layers.py` builds equipped upper-body, separate leg and grip layers plus attachment anchors. Outputs go to the runtime rig folder; manifests remain here. The combined lower-body inspection sheet and optional previews go to ignored `previews/`.

Reimport in Godot after baking, then run player motion, actions, dense pose and rendered lighting checks. Preserve the source sheet and its hash; do not treat it as disposable test output. Dedicated breath, gasp, throw, prayer and death clips have not been authored.
