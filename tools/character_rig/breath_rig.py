"""Author the upper-body Hold Your Breath track from the existing source cutouts.

python breath_rig.py --review-dir previews

Seven upper-body tracks share the locomotion rig's registered canvas, aim modes,
straight equipped elbow and single wrist/hand/torch attachment. No leg pixels,
light emission or shadows are baked into this sheet. The controller blends the
tracks without pixel crossfades and supplies timing from the actual mechanic.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math

from PIL import Image
import bake_rig as rig
import export_action_layers as action
import grip_rig as grip

ROOT = Path(__file__).resolve().parent
OUTPUT = action.OUTPUT
POSES = {
    # Changes are source pixels. At the live .5 actor scale these remain small,
    # grounded gestures; the gasp is deliberately larger than sustained strain.
    "inhale": dict(shoulder_spread=1.0, shoulder_y=-2.0, chest_y=-1.0,
                   chest_width=81, chest_height=54, head_y=-2.0,
                   head_angle=0.0, free_elbow_in=1.0, free_hand_in=2.0,
                   free_hand_y=-2.0),
    "hold": dict(shoulder_spread=-0.5, shoulder_y=-1.0, chest_y=0.0,
                 chest_width=79, chest_height=51, head_y=-1.0,
                 head_angle=0.0, free_elbow_in=2.0, free_hand_in=4.0,
                 free_hand_y=-3.0),
    "strain": dict(shoulder_spread=-1.5, shoulder_y=2.0, chest_y=1.0,
                   chest_width=77, chest_height=52, head_y=2.5,
                   head_angle=-1.0, free_elbow_in=3.0, free_hand_in=6.0,
                   free_hand_y=-4.0),
    "release": dict(shoulder_spread=0.5, shoulder_y=1.5, chest_y=0.5,
                    chest_width=80, chest_height=51, head_y=0.0,
                    head_angle=0.0, free_elbow_in=0.0, free_hand_in=0.0,
                    free_hand_y=1.5),
    "gasp": dict(shoulder_spread=-2.0, shoulder_y=5.0, chest_y=3.5,
                 chest_width=77, chest_height=54, head_y=7.0,
                 head_angle=-2.0, free_elbow_in=4.0, free_hand_in=10.0,
                 free_hand_y=-6.0),
    "recovery": dict(shoulder_spread=1.5, shoulder_y=-1.5, chest_y=-0.5,
                     chest_width=82, chest_height=54, head_y=-1.5,
                     head_angle=0.5, free_elbow_in=1.0, free_hand_in=3.0,
                     free_hand_y=-1.0),
}
NEUTRAL = dict(shoulder_spread=0.0, shoulder_y=0.0, chest_y=0.0,
               chest_width=79, chest_height=52, head_y=0.0,
               head_angle=0.0, free_elbow_in=0.0, free_hand_in=0.0,
               free_hand_y=0.0)


def blend(a, b, weight):
    return {key: a[key] + (b[key] - a[key]) * weight for key in a}


def smooth_track(keys, count):
    frames = []
    for frame in range(count):
        phase = frame / (count - 1) if count > 1 else 0.0
        for (start, a), (end, b) in zip(keys, keys[1:]):
            if phase <= end:
                weight = min(1.0, max(0.0, (phase - start) / (end - start)))
                frames.append(blend(a, b, weight * weight * (3 - 2 * weight)))
                break
    return frames


GASP_SETTLE = blend(POSES["gasp"], POSES["recovery"], .55)
TRACKS = {
    "inhale": smooth_track([(0, NEUTRAL), (.45, POSES["inhale"]), (1, POSES["hold"])], 6),
    "hold": [POSES["hold"]],
    "strain": [blend(POSES["hold"], POSES["strain"], weight) for weight in (.80, 1.0, .9, .80)],
    "release": smooth_track([(0, POSES["hold"]), (.40, POSES["release"]), (1, NEUTRAL)], 6),
    "gasp": smooth_track([(0, POSES["hold"]), (.35, POSES["gasp"]), (1, GASP_SETTLE)], 6),
    "recovery": smooth_track([(0, GASP_SETTLE), (.22, POSES["recovery"]),
                               (.42, blend(NEUTRAL, POSES["gasp"], .35)),
                               (.64, blend(NEUTRAL, POSES["recovery"], .60)),
                               (1, NEUTRAL)], 8),
    "release_loud": smooth_track([(0, POSES["hold"]), (.35, blend(NEUTRAL, POSES["gasp"], .55)),
                                   (.70, blend(NEUTRAL, POSES["recovery"], .35)), (1, NEUTRAL)], 6),
}
TRACK_DURATIONS = {"inhale": .20, "hold": 0.0, "strain": 0.0, "release": .46,
                   "gasp": .28, "recovery": 1.72, "release_loud": .55}
FRAMES_PER_MODE = sum(len(frames) for frames in TRACKS.values())
MODES = [(False, 0)] + [(True, step) for step in action.AIM_STEPS]


def _free_segment(canvas, name, start, end, width, overlap):
    # Match the existing source cutout construction exactly at neutral so
    # entering and leaving this track never changes the legacy idle pose.
    rig.segment(canvas, name, start, end, width, overlap)


def render(values, aim_step=0, equipped=False):
    canvas = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
    aim = math.radians(aim_step * 22.5) if equipped else 0.0
    torso_turn = aim * .4
    arms, joints = [], {}
    for side, sign in (("l", 1), ("r", -1)):
        shoulder = action.rotate((128 + sign * (32 + values["shoulder_spread"]),
                                  137 + values["shoulder_y"]), torso_turn)
        if equipped and side == "r":
            # The same 12-degree elbow, bone lengths and forearm direction as
            # the normal carry pose. Only the shoulder anchor breathes.
            lateral = (math.cos(torso_turn), math.sin(torso_turn))
            shoulder = (shoulder[0] - lateral[0] * 2, shoulder[1] - lateral[1] * 2)
            upper_angle = aim + math.radians(12)
            elbow = (shoulder[0] - math.sin(upper_angle) * 16,
                     shoulder[1] + math.cos(upper_angle) * 16)
            hand = (elbow[0] - math.sin(aim) * 16,
                    elbow[1] + math.cos(aim) * 16)
            grip.render_equipped_upper_arm(canvas, shoulder, elbow)
        else:
            elbow = action.rotate((128 + sign * (36 - values["free_elbow_in"]),
                                   147 + values["shoulder_y"] * .6), torso_turn)
            hand = action.rotate((128 + sign * (33 - values["free_hand_in"]),
                                  161 + values["free_hand_y"]), torso_turn)
            _free_segment(canvas, "upper_" + side, shoulder, elbow, 20, 8)
        arms.append((side, elbow, hand))
        joints[side] = {"shoulder": shoulder, "elbow": elbow, "wrist": hand}
    torso = action.rotate((128, 124 + values["chest_y"]), torso_turn)
    rig.put(canvas, "torso", torso, values["chest_width"], values["chest_height"],
            180 - math.degrees(torso_turn))
    for side, elbow, hand in arms:
        if equipped and side == "r":
            grip.render_equipped_forearm(canvas, elbow, hand)
        else:
            _free_segment(canvas, "fore_" + side, elbow, hand, 15, 5)
        if side == "r":
            right_hand = hand
    head = action.rotate((128, 144 + values["head_y"]), torso_turn)
    rig.put(canvas, "head", head, 44, 57, values["head_angle"] - math.degrees(torso_turn))
    flashlight_angle = math.pi / 2 + aim
    muzzle = (right_hand[0] + math.cos(flashlight_angle) * grip.MUZZLE_DISTANCE,
              right_hand[1] + math.sin(flashlight_angle) * grip.MUZZLE_DISTANCE)
    return action.finish(canvas), {
        "right_hand": right_hand, "muzzle": muzzle,
        "flashlight_angle": flashlight_angle, "joints": joints,
    }


def combined(values, aim_step=0, equipped=True):
    canvas = action.render_lower()
    upper, anchors = render(values, aim_step, equipped)
    canvas.alpha_composite(upper)
    if equipped:
        attachment = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
        grip.draw_grip(attachment, anchors["right_hand"], anchors["flashlight_angle"] - math.pi / 2)
        canvas.alpha_composite(action.finish(attachment))
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review-dir", type=Path)
    args = parser.parse_args()
    images, frames = [], []
    for equipped, aim_step in MODES:
        for track, sequence in TRACKS.items():
            for frame, values in enumerate(sequence):
                image, anchors = render(values, aim_step, equipped)
                images.append(image)
                frames.append(dict(track=track, frame=frame, equipped=equipped, aim_step=aim_step, **anchors))
    action.export_atlas(images, OUTPUT / "breath_upper_layers.png")
    track_indices, offset = {}, 0
    for track, sequence in TRACKS.items():
        track_indices[track] = {"offset": offset, "count": len(sequence), "duration": TRACK_DURATIONS[track]}
        offset += len(sequence)
    lines = ["extends RefCounted", "## Generated by tools/character_rig/breath_rig.py; source canvas pixels.",
             "const FRAMES_PER_MODE := " + str(FRAMES_PER_MODE),
             "const TRACKS := " + action.gd_literal(track_indices),
             "const FRAMES: Array[Dictionary] = ["]
    for frame in frames:
        anchors = {key: frame[key] for key in ("right_hand", "muzzle", "flashlight_angle")}
        lines.append("\t" + action.gd_literal(anchors) + ",")
    lines.append("]")
    (OUTPUT / "breath_layer_anchors.gd").write_text("\n".join(lines) + "\n")
    manifest = {
        "source_sha256": hashlib.sha256(rig.SOURCE.read_bytes()).hexdigest(),
        "recipe": "breath_rig.py; existing source cutouts, grip_rig.py and export_action_layers.py helpers",
        "frame_size": [256, 256], "atlas_columns": 8, "pivot": [128, 128], "world_scale": .5,
        "tracks": track_indices, "authored_pose_transforms": POSES, "mode_count": len(MODES),
        "frames_per_mode": FRAMES_PER_MODE,
        "packing": "mode * 37 + track.offset + frame; modes = neutral, equipped -45, -22.5, 0, +22.5, +45 degrees",
        "notes": [
            "Upper body only. Locomotion and planted-foot contacts are not modified.",
            "Part-space interpolation is baked frame by frame; do not alpha-crossfade different wrists or cuffs.",
            "Select a phase from 0 to 1 and use the returned wrist socket for the same frame. Only strain loops.",
            "Hold is indefinite. Strain has no fixed duration: its loop runs at 0.8 to 1.55 Hz from live lung/exertion pressure.",
            "Recovery duration is 1.72 seconds for the default two-second forced lock; runtime follows the actual remaining lock.",
            "Inhale starts at exact idle; release, release_loud and recovery end at exact idle.",
            "Breath poses restrain arm swing when walking; gameplay owns all resources, speed and timings.",
            "Equipped elbow keeps its 12-degree bend, rigid bone lengths and forearm aim heading in every pose.",
            "Existing hand/flashlight attachment is drawn once at the selected frame's wrist socket.",
            "No new AI generation, particles, emission, shadow or repeated relaxed equipped hand.",
        ],
        "frames": frames,
    }
    (ROOT / "breath_layers_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.review_dir:
        args.review_dir.mkdir(parents=True, exist_ok=True)
        rig.contact_sheet([combined(values) for values in POSES.values()], list(POSES),
                          args.review_dir / "breath_pose_contacts.png", cols=6, cell=256)
        rig.contact_sheet([combined(values, step) for values in POSES.values() for step in action.AIM_STEPS],
                          [f"{pose} {step * 22.5:+g} deg" for pose in POSES for step in action.AIM_STEPS],
                          args.review_dir / "breath_aim_contacts.png", cols=5, cell=220)
        rig.contact_sheet([combined(values, step).crop((48, 64, 208, 224))
                           for values in POSES.values() for step in action.AIM_STEPS],
                          [f"{pose} {step * 22.5:+g} deg" for pose in POSES for step in action.AIM_STEPS],
                          args.review_dir / "breath_equipped_detail_contacts.png", cols=5, cell=256)
        rig.contact_sheet([combined(values, equipped=False) for values in POSES.values()], list(POSES),
                          args.review_dir / "breath_neutral_contacts.png", cols=6, cell=256)
        rig.contact_sheet([combined(values) for sequence in TRACKS.values() for values in sequence],
                          [f"{track} {i + 1}/{len(sequence)}" for track, sequence in TRACKS.items()
                           for i in range(len(sequence))],
                          args.review_dir / "breath_sequence_contacts.png", cols=8, cell=220)
    print(json.dumps({"upper_frames": len(images), "tracks": track_indices,
                      "output": str(OUTPUT / "breath_upper_layers.png")}))


if __name__ == "__main__":
    main()
