"""Bake a restrained free-left-arm throw using the original character cutouts.

python throw_rig.py --review-dir ../../requiem/testing/captures/throw_review

The existing 0.5 second gameplay windup owns anticipation and release. The
release pose is shared with the 0.32 second follow-through, which settles to
the exact existing idle. All poses retain the normal lower-body registration.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math

from PIL import Image, ImageDraw
import bake_rig as rig
import export_action_layers as action
import grip_rig as grip

ROOT = Path(__file__).resolve().parent
OUTPUT = action.OUTPUT
LEFT_UPPER_LENGTH = math.hypot(4, 10)
LEFT_FORE_LENGTH = math.hypot(-3, 14)
# The original left cutout is 116 x 341. This landmark sits in the visible
# palm, inside the thumb/index curl, rather than at a nominal bone endpoint.
LEFT_PALM_SOURCE = (56.0, 274.0)
LEFT_WRIST_SOURCE = (55.0, 204.0)
NEUTRAL = dict(upper_degrees=-math.degrees(math.atan2(4, 10)),
               fore_degrees=math.degrees(math.atan2(3, 14)),
               shoulder_x=0.0, shoulder_y=0.0, chest_x=0.0, chest_y=0.0,
               head_y=0.0, head_angle=0.0, registration=0.0)


def pose(**changes):
    return {**NEUTRAL, **changes}


POSES = {
    "gather": pose(upper_degrees=-65, fore_degrees=-85, shoulder_x=.8,
                   shoulder_y=-.8, chest_x=-.4, chest_y=-.5, head_y=-.6,
                   head_angle=-.5, registration=1.0),
    "anticipation": pose(upper_degrees=-104, fore_degrees=-155,
                         shoulder_x=1.5, shoulder_y=-1.2, chest_x=-.8,
                         chest_y=-1.0, head_y=-1.3, head_angle=-1.0,
                         registration=1.0),
    "loaded": pose(upper_degrees=-99, fore_degrees=-150,
                   shoulder_x=1.3, shoulder_y=-1.0, chest_x=-.7,
                   chest_y=-.8, head_y=-1.1, head_angle=-.8,
                   registration=1.0),
    "release": pose(upper_degrees=-4, fore_degrees=8, shoulder_x=-.6,
                    shoulder_y=1.5, chest_x=.6, chest_y=1.2,
                    head_y=1.7, head_angle=.6, registration=1.0),
    "follow": pose(upper_degrees=4, fore_degrees=12, shoulder_x=.5,
                   shoulder_y=2.0, chest_x=.7, chest_y=1.6,
                   head_y=2.1, head_angle=.9, registration=1.0),
    "settle": pose(upper_degrees=-8, fore_degrees=19, shoulder_x=-.2,
                   shoulder_y=.4, chest_x=.1, chest_y=.3,
                   head_y=.5, head_angle=.2, registration=.65),
}


def blend(a, b, weight):
    return {key: a[key] + (b[key] - a[key]) * weight for key in a}


def smooth_track(keys, count):
    frames = []
    for index in range(count):
        phase = index / (count - 1)
        for (start, a), (end, b) in zip(keys, keys[1:]):
            if phase <= end:
                weight = min(1.0, max(0.0, (phase - start) / (end - start)))
                frames.append(blend(a, b, weight * weight * (3 - 2 * weight)))
                break
    return frames


TRACKS = {
    "windup": smooth_track([(0, NEUTRAL), (.25, POSES["gather"]),
                             (.58, POSES["anticipation"]), (.74, POSES["loaded"]),
                             (1, POSES["release"])], 12),
    "follow_through": smooth_track([(0, POSES["release"]), (.25, POSES["follow"]),
                                     (.60, POSES["settle"]), (1, NEUTRAL)], 10),
}
TRACK_DURATIONS = {"windup": .5, "follow_through": .32}
FRAMES_PER_MODE = sum(len(sequence) for sequence in TRACKS.values())
MODES = [(False, 0)] + [(True, step) for step in action.AIM_STEPS]


def extend(start, length, angle):
    return (start[0] - math.sin(angle) * length,
            start[1] + math.cos(angle) * length)


def transform_landmark(name, point, center, width, height, pillow_angle):
    # rig.put rounds the resized source dimensions before rotation. Match
    # those dimensions so the held prop is registered to the visible pixels.
    source = rig.parts[name]
    dx = (point[0] / source.width - .5) * round(width * rig.SS) / rig.SS
    dy = (point[1] / source.height - .5) * round(height * rig.SS) / rig.SS
    angle = math.radians(pillow_angle)
    return (center[0] + dx * math.cos(angle) + dy * math.sin(angle),
            center[1] - dx * math.sin(angle) + dy * math.cos(angle))


def left_segment(canvas, name, start, end, width, overlap, registration):
    dx, dy = end[0] - start[0], end[1] - start[1]
    length = math.hypot(dx, dy) + overlap
    center = ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2)
    # Legacy free-arm idle uses the opposite Pillow rotation convention.
    # Preserve its pixels at entry/exit, then register the same source part
    # to the articulated bone during the throw, without any pixel crossfade.
    angle = math.degrees(math.atan2(dx, dy)) * (2 * registration - 1)
    rig.put(canvas, name, center, width, length, angle)
    return {"center": center, "width": width, "height": length,
            "pillow_angle_degrees": angle}


def render(values, aim_step=0, equipped=False):
    canvas = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
    aim = math.radians(aim_step * 22.5) if equipped else 0.0
    torso_turn = aim * .4
    shoulder = action.rotate((160 + values["shoulder_x"],
                              137 + values["shoulder_y"]), torso_turn)
    arm_aim = aim * (.4 + .6 * values["registration"])
    elbow = extend(shoulder, LEFT_UPPER_LENGTH,
                   math.radians(values["upper_degrees"]) + arm_aim)
    hand = extend(elbow, LEFT_FORE_LENGTH,
                  math.radians(values["fore_degrees"]) + arm_aim)
    left_upper = left_segment(canvas, "upper_l", shoulder, elbow, 20, 8,
                              values["registration"])
    joints = {"l": {"shoulder": shoulder, "elbow": elbow, "wrist": hand}}
    right_shoulder = action.rotate((96, 137), torso_turn)
    if equipped:
        lateral = (math.cos(torso_turn), math.sin(torso_turn))
        right_shoulder = (right_shoulder[0] - lateral[0] * 2,
                          right_shoulder[1] - lateral[1] * 2)
        right_elbow = extend(right_shoulder, 16, aim + math.radians(12))
        right_hand = extend(right_elbow, 16, aim)
        grip.render_equipped_upper_arm(canvas, right_shoulder, right_elbow)
    else:
        right_elbow = action.rotate((92, 147), torso_turn)
        right_hand = action.rotate((95, 161), torso_turn)
        rig.segment(canvas, "upper_r", right_shoulder, right_elbow, 20, 8)
    joints["r"] = {"shoulder": right_shoulder, "elbow": right_elbow, "wrist": right_hand}
    torso = action.rotate((128 + values["chest_x"], 124 + values["chest_y"]), torso_turn)
    rig.put(canvas, "torso", torso, 79, 52, 180 - math.degrees(torso_turn))
    left_fore = left_segment(canvas, "fore_l", elbow, hand, 15, 5,
                             values["registration"])
    if equipped:
        grip.render_equipped_forearm(canvas, right_elbow, right_hand)
    else:
        rig.segment(canvas, "fore_r", right_elbow, right_hand, 15, 5)
    head = action.rotate((128, 144 + values["head_y"]), torso_turn)
    rig.put(canvas, "head", head, 44, 57, values["head_angle"] - math.degrees(torso_turn))
    throw_hand = transform_landmark("fore_l", LEFT_PALM_SOURCE, left_fore["center"],
                                    left_fore["width"], left_fore["height"],
                                    left_fore["pillow_angle_degrees"])
    drawn_wrist = transform_landmark("fore_l", LEFT_WRIST_SOURCE, left_fore["center"],
                                     left_fore["width"], left_fore["height"],
                                     left_fore["pillow_angle_degrees"])
    flashlight_angle = math.pi / 2 + aim
    muzzle = (right_hand[0] + math.cos(flashlight_angle) * grip.MUZZLE_DISTANCE,
              right_hand[1] + math.sin(flashlight_angle) * grip.MUZZLE_DISTANCE)
    return action.finish(canvas), {
        "right_hand": right_hand, "muzzle": muzzle,
        "flashlight_angle": flashlight_angle, "throw_hand": throw_hand,
        "joints": joints, "drawn_left_wrist": drawn_wrist,
        "left_part_transforms": {"upper": left_upper, "forearm": left_fore},
    }


def combined(values, aim_step=0, equipped=True, socket=False):
    canvas = action.render_lower()
    upper, anchors = render(values, aim_step, equipped)
    canvas.alpha_composite(upper)
    if equipped:
        attachment = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
        grip.draw_grip(attachment, anchors["right_hand"], anchors["flashlight_angle"] - math.pi / 2)
        canvas.alpha_composite(action.finish(attachment))
    if socket:
        x, y = anchors["throw_hand"]
        ImageDraw.Draw(canvas).ellipse((x - 2, y - 2, x + 2, y + 2), fill="#edba67")
    return canvas


def validate():
    checked = 0
    for equipped, step in MODES:
        idle, _ = action.render_upper(aim_step=step, equipped=equipped)
        for values in (TRACKS["windup"][0], TRACKS["follow_through"][-1]):
            image, _ = render(values, step, equipped)
            assert idle.tobytes() == image.tobytes(), (equipped, step, "idle seam")
        release, release_anchors = render(TRACKS["windup"][-1], step, equipped)
        follow, follow_anchors = render(TRACKS["follow_through"][0], step, equipped)
        assert release.tobytes() == follow.tobytes() and release_anchors == follow_anchors
        for sequence in TRACKS.values():
            for values in sequence:
                _, anchors = render(values, step, equipped)
                left, right = anchors["joints"]["l"], anchors["joints"]["r"]
                assert abs(math.dist(left["shoulder"], left["elbow"]) - LEFT_UPPER_LENGTH) < 1e-9
                assert abs(math.dist(left["elbow"], left["wrist"]) - LEFT_FORE_LENGTH) < 1e-9
                if equipped:
                    upper = math.dist(right["shoulder"], right["elbow"])
                    fore = math.dist(right["elbow"], right["wrist"])
                    assert abs(upper - 16) < 1e-9 and abs(fore - 16) < 1e-9
                    a = tuple(right["elbow"][i] - right["shoulder"][i] for i in (0, 1))
                    b = tuple(right["wrist"][i] - right["elbow"][i] for i in (0, 1))
                    cosine = sum(a[i] * b[i] for i in (0, 1)) / (upper * fore)
                    assert abs(math.degrees(math.acos(cosine)) - 12) < 1e-9
                assert abs(math.dist(anchors["right_hand"], anchors["muzzle"]) - grip.MUZZLE_DISTANCE) < 1e-9
                part = anchors["left_part_transforms"]["forearm"]
                socket = transform_landmark("fore_l", LEFT_PALM_SOURCE, part["center"],
                                             part["width"], part["height"], part["pillow_angle_degrees"])
                assert math.dist(socket, anchors["throw_hand"]) < 1e-9
                checked += 1
    return {"validated_frames": checked, "exact_idle_endpoints": len(MODES) * 2,
            "continuous_release_seams": len(MODES), "constant_limb_lengths": True,
            "registered_palm_sockets": True, "equipped_elbow_degrees": 12}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review-dir", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    validation = validate()
    if args.validate_only:
        print(json.dumps(validation))
        return
    images, frames = [], []
    for equipped, aim_step in MODES:
        for track, sequence in TRACKS.items():
            for frame, values in enumerate(sequence):
                image, anchors = render(values, aim_step, equipped)
                images.append(image)
                frames.append(dict(track=track, frame=frame, equipped=equipped,
                                   aim_step=aim_step, **anchors))
    action.export_atlas(images, OUTPUT / "throw_upper_layers.png")
    track_indices, offset = {}, 0
    for track, sequence in TRACKS.items():
        track_indices[track] = {"offset": offset, "count": len(sequence), "duration": TRACK_DURATIONS[track]}
        offset += len(sequence)
    lines = ["extends RefCounted", "## Generated by tools/character_rig/throw_rig.py; source canvas pixels.",
             "const FRAMES_PER_MODE := " + str(FRAMES_PER_MODE),
             "const TRACKS := " + action.gd_literal(track_indices),
             "const FRAMES: Array[Dictionary] = ["]
    for frame in frames:
        fields = [json.dumps(key) + ": " + action.gd_literal(frame[key], "right_hand" if key == "throw_hand" else key)
                  for key in ("right_hand", "muzzle", "flashlight_angle", "throw_hand")]
        lines.append("\t{" + ", ".join(fields) + "},")
    lines.append("]")
    (OUTPUT / "throw_layer_anchors.gd").write_text("\n".join(lines) + "\n")
    manifest = {
        "source_sha256": hashlib.sha256(rig.SOURCE.read_bytes()).hexdigest(),
        "recipe": "throw_rig.py; original cutouts, grip_rig.py and export_action_layers.py helpers",
        "frame_size": [256, 256], "atlas_columns": 8, "pivot": [128, 128], "world_scale": .5,
        "tracks": track_indices, "authored_pose_transforms": POSES, "neutral_pose": NEUTRAL,
        "mode_count": len(MODES), "frames_per_mode": FRAMES_PER_MODE,
        "packing": "mode * 22 + track.offset + frame; modes = neutral, equipped -45, -22.5, 0, +22.5, +45 degrees",
        "left_palm_source": LEFT_PALM_SOURCE, "left_wrist_source": LEFT_WRIST_SOURCE,
        "left_bone_lengths": [LEFT_UPPER_LENGTH, LEFT_FORE_LENGTH],
        "notes": [
            "The anatomical LEFT/free hand throws in every mode; flashlight remains attached to the right hand.",
            "Gameplay owns the unchanged windup duration, projectile release, inventory and cancellation.",
            "Windup phase 1 and follow_through phase 0 share the exact release sprite and socket.",
            "Follow-through lasts 0.32 seconds; entering and leaving the action returns exact legacy idle pixels.",
            "All limb interpolation changes individual source transforms; there are no alpha crossfades.",
            "The free-arm cutout eases from legacy idle rotation into articulated bone registration during the throw.",
            "throw_hand is the visible palm landmark transformed with the exact forearm cutout, not a guessed offset.",
            "Full equipped aim offsets guide the release arm; torso rotation retains the existing 0.4 multiplier.",
            "Equipped right shoulder, 12-degree elbow, bone lengths and rigid flashlight attachment remain unchanged.",
            "Lower body, locomotion exports, source artwork, foot contacts and lighting remain unchanged.",
        ],
        "validation": validation, "frames": frames,
    }
    (ROOT / "throw_layers_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.review_dir:
        args.review_dir.mkdir(parents=True, exist_ok=True)
        values = [values for sequence in TRACKS.values() for values in sequence]
        labels = [f"{track} {i + 1}/{len(sequence)}" for track, sequence in TRACKS.items()
                  for i in range(len(sequence))]
        rig.contact_sheet([combined(value) for value in values], labels,
                          args.review_dir / "throw_sequence_contacts.png", cols=6, cell=256)
        rig.contact_sheet([combined(value, equipped=False) for value in values], labels,
                          args.review_dir / "throw_neutral_contacts.png", cols=6, cell=256)
        rig.contact_sheet([combined(value, step, socket=True).crop((48, 64, 208, 224))
                           for value in POSES.values() for step in action.AIM_STEPS],
                          [f"{name} {step * 22.5:+g} deg" for name in POSES for step in action.AIM_STEPS],
                          args.review_dir / "throw_aim_contacts.png", cols=5, cell=256)
        (args.review_dir / "throw_validation.json").write_text(json.dumps(validation, indent=2) + "\n")
    print(json.dumps({"upper_frames": len(images), "tracks": track_indices,
                      "output": str(OUTPUT / "throw_upper_layers.png"), **validation}))


if __name__ == "__main__":
    main()
