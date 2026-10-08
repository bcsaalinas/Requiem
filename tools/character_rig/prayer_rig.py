"""Bake a kneeling prayer gesture from the original overhead character cutouts.

python prayer_rig.py --review-dir ../../requiem/testing/captures/prayer_review

The knees settle forward as the shins fold back and the boots emerge behind the
torso. The free left hand draws inward and the head bows. The equipped right
arm retains the shared 12-degree elbow and rigid hand/flashlight attachment.
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
import throw_rig as throw
import gait_rig as gait

ROOT = Path(__file__).resolve().parent
OUTPUT = action.OUTPUT
SOURCE_SHA256 = "281072703372ea992e80b5961d1301f7b5101bd49eaf022d221d5ce88d2f9cf3"
NEUTRAL = {**throw.NEUTRAL, "head_height": 57.0, "right_shoulder_x": 0.0,
           "right_shoulder_y": 0.0, "kneel_weight": 0.0}
HELD = {**NEUTRAL, "upper_degrees": -14.0, "fore_degrees": 40.0,
        "shoulder_x": -.8, "shoulder_y": 7.0,
        "chest_x": 0.0, "chest_y": 7.0, "head_y": 11.0,
        "head_angle": -.7, "head_height": 54.0, "registration": 1.0,
        "right_shoulder_x": .4, "right_shoulder_y": 6.6, "kneel_weight": 1.0}
FOCUSED_INHALE = {**HELD, "shoulder_y": 6.3, "chest_y": 6.5,
                  "head_y": 10.4, "head_angle": -.4,
                  "right_shoulder_y": 6.1, "fore_degrees": 39.3}
FOCUSED_EXHALE = {**HELD, "shoulder_y": 7.3, "chest_y": 7.4,
                  "head_y": 11.4, "head_angle": -.9,
                  "right_shoulder_y": 6.9, "fore_degrees": 40.4}
POSES = {"held": HELD, "focused_inhale": FOCUSED_INHALE,
         "focused_exhale": FOCUSED_EXHALE}

# A reversed entry permits the controller to unwind an interrupted entry at
# its exact pose instead of jumping to a fully bowed first exit frame.
ENTRY = throw.smooth_track([(0, NEUTRAL), (1, HELD)], 8)
ENTRY[0], ENTRY[-1] = NEUTRAL.copy(), HELD.copy()
LOOP = throw.smooth_track([(0, HELD), (.28, FOCUSED_INHALE),
                          (.72, FOCUSED_EXHALE), (1, HELD)], 8)
LOOP[0], LOOP[-1] = HELD.copy(), HELD.copy()
TRACKS = {"entry": ENTRY, "loop": LOOP, "exit": list(reversed(ENTRY))}
TRACK_DURATIONS = {"entry": .42, "loop": 2.0, "exit": .38}
FRAMES_PER_MODE = 24
MODES = [(False, 0)] + [(True, step) for step in action.AIM_STEPS]


def render(values, aim_step=0, equipped=False):
    canvas = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
    aim = math.radians(aim_step * 22.5) if equipped else 0.0
    torso_turn = aim * .4
    shoulder = action.rotate((160 + values["shoulder_x"],
                              137 + values["shoulder_y"]), torso_turn)
    # Prayer folds toward the actor's chest, independently of torch aim.
    elbow = throw.extend(shoulder, throw.LEFT_UPPER_LENGTH,
                         math.radians(values["upper_degrees"]) + torso_turn)
    hand = throw.extend(elbow, throw.LEFT_FORE_LENGTH,
                        math.radians(values["fore_degrees"]) + torso_turn)
    left_upper = throw.left_segment(canvas, "upper_l", shoulder, elbow, 20, 8,
                                    values["registration"])
    joints = {"l": {"shoulder": shoulder, "elbow": elbow, "wrist": hand}}
    right_shoulder = action.rotate((96 + values["right_shoulder_x"],
                                    137 + values["right_shoulder_y"]), torso_turn)
    if equipped:
        lateral = (math.cos(torso_turn), math.sin(torso_turn))
        right_shoulder = (right_shoulder[0] - lateral[0] * 2,
                          right_shoulder[1] - lateral[1] * 2)
        right_elbow = throw.extend(right_shoulder, 16, aim + math.radians(12))
        right_hand = throw.extend(right_elbow, 16, aim)
        grip.render_equipped_upper_arm(canvas, right_shoulder, right_elbow)
    else:
        right_elbow = action.rotate((92 + values["right_shoulder_x"],
                                     147 + values["right_shoulder_y"]), torso_turn)
        right_hand = action.rotate((95 + values["right_shoulder_x"],
                                    161 + values["right_shoulder_y"]), torso_turn)
        rig.segment(canvas, "upper_r", right_shoulder, right_elbow, 20, 8)
    joints["r"] = {"shoulder": right_shoulder, "elbow": right_elbow,
                    "wrist": right_hand}
    torso = action.rotate((128 + values["chest_x"], 124 + values["chest_y"]), torso_turn)
    rig.put(canvas, "torso", torso, 79, 52, 180 - math.degrees(torso_turn))
    left_fore = throw.left_segment(canvas, "fore_l", elbow, hand, 15, 5,
                                   values["registration"])
    if equipped:
        grip.render_equipped_forearm(canvas, right_elbow, right_hand)
    else:
        rig.segment(canvas, "fore_r", right_elbow, right_hand, 15, 5)
    head = action.rotate((128, 144 + values["head_y"]), torso_turn)
    head_angle = values["head_angle"] - math.degrees(torso_turn)
    rig.put(canvas, "head", head, 44, values["head_height"], head_angle)
    flashlight_angle = math.pi / 2 + aim
    muzzle = (right_hand[0] + math.cos(flashlight_angle) * grip.MUZZLE_DISTANCE,
              right_hand[1] + math.sin(flashlight_angle) * grip.MUZZLE_DISTANCE)
    left_palm = throw.transform_landmark("fore_l", throw.LEFT_PALM_SOURCE,
                                         left_fore["center"], left_fore["width"],
                                         left_fore["height"], left_fore["pillow_angle_degrees"])
    return action.finish(canvas), {
        "right_hand": right_hand, "muzzle": muzzle,
        "flashlight_angle": flashlight_angle, "joints": joints,
        "left_palm": left_palm,
        "part_transforms": {
            "left_upper": left_upper, "left_forearm": left_fore,
            "torso": {"center": torso, "width": 79, "height": 52,
                       "pillow_angle_degrees": 180 - math.degrees(torso_turn)},
            "head": {"center": head, "width": 44, "height": values["head_height"],
                      "pillow_angle_degrees": head_angle},
        },
    }


def render_lower(values, side=None):
    """Fold the original trouser/boot cutouts into a registered kneeling pose.

    Lower poses have one equipment-independent mode; the runtime rotates both
    plates with the locked body heading. Boots retain their source dimensions.
    """
    weight = values["kneel_weight"]
    _, idle = gait.render_lower()
    if weight == 0:
        image, metadata = gait.render_lower(side=side)
        return image, {**metadata, "kneel_weight": 0.0, "knee_contact": False}
    legs = {}
    for name, sign, _part in gait._SIDES:
        # Fold outward through the descent so two rigid boots never cross.
        # Their final toes face back, in two readable lanes behind the torso.
        boot = gait._mix(idle[name]["boot"], (128 + sign * 20, 94), weight)
        boot = (boot[0] + sign * math.sin(weight * math.pi) * 3, boot[1])
        toe = gait._toe_angle(sign) - sign * (math.pi - math.radians(6)) * weight
        ankle = (boot[0] - math.cos(toe) * 7, boot[1] - math.sin(toe) * 7)
        hip = gait._mix(idle[name]["hip"], (128 + sign * 12, 132), weight)
        knee = gait._mix(idle[name]["knee"], (128 + sign * 19, 144), weight)
        legs[name] = {"boot": list(boot), "hip": list(hip), "knee": list(knee),
                      "ankle": list(ankle), "contact": weight == 1.0,
                      "lift": math.sin(weight * math.pi), "toe_angle": toe,
                      "swing_progress": weight}
    metadata = {"state": "prayer", "frame": 0, "direction": "s",
                "phase": weight, "pelvis_angle": 0.0, "support": "knees" if weight >= .35 else "",
                "passing": False, "kneel_weight": weight, "knee_contact": weight >= .35, **legs}
    return gait._paint(legs, side), metadata


def combined(values, aim_step=0, equipped=True):
    canvas, _ = render_lower(values)
    upper, anchors = render(values, aim_step, equipped)
    canvas.alpha_composite(upper)
    if equipped:
        attachment = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
        grip.draw_grip(attachment, anchors["right_hand"], anchors["flashlight_angle"] - math.pi / 2)
        canvas.alpha_composite(action.finish(attachment))
    return canvas


def validate():
    assert hashlib.sha256(rig.SOURCE.read_bytes()).hexdigest() == SOURCE_SHA256
    assert FRAMES_PER_MODE == sum(len(sequence) for sequence in TRACKS.values())
    checked, exact_reversals = 0, 0
    for equipped, step in MODES:
        idle, idle_anchors = action.render_upper(aim_step=step, equipped=equipped)
        idle_whole = action.render_lower()
        idle_whole.alpha_composite(idle)
        if equipped:
            attachment = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
            grip.draw_grip(attachment, idle_anchors["right_hand"], idle_anchors["flashlight_angle"] - math.pi / 2.0)
            idle_whole.alpha_composite(action.finish(attachment))
        for values in (TRACKS["entry"][0], TRACKS["exit"][-1]):
            image, _ = render(values, step, equipped)
            assert idle.tobytes() == image.tobytes(), (equipped, step, "idle seam")
            assert idle_whole.tobytes() == combined(values, step, equipped).tobytes(), (equipped, step, "whole silhouette idle seam")
        held, held_anchors = render(HELD, step, equipped)
        held_lower, held_lower_anchors = render_lower(HELD)
        # A folded foot hidden entirely under the torso would not communicate
        # kneeling from overhead. Require visible rear boot pixels in all aims.
        for side in ("left", "right"):
            boot = held_lower_anchors[side]["boot"]
            visible = sum(held_lower.getpixel((x, y))[3] > 64 and held.getpixel((x, y))[3] < 64
                          for y in range(round(boot[1] - 12), min(100, round(boot[1] + 12)))
                          for x in range(round(boot[0] - 9), round(boot[0] + 9)))
            assert visible >= 30, (equipped, step, side, "rear boot silhouette", visible)
        for values in (TRACKS["entry"][-1], TRACKS["loop"][0],
                       TRACKS["loop"][-1], TRACKS["exit"][0]):
            image, anchors = render(values, step, equipped)
            assert held.tobytes() == image.tobytes() and held_anchors == anchors
        for entry, exit_values in zip(TRACKS["entry"], reversed(TRACKS["exit"])):
            entry_image, entry_anchors = render(entry, step, equipped)
            exit_image, exit_anchors = render(exit_values, step, equipped)
            assert entry_image.tobytes() == exit_image.tobytes() and entry_anchors == exit_anchors
            exact_reversals += 1
        for sequence in TRACKS.values():
            for values in sequence:
                _, anchors = render(values, step, equipped)
                left, right = anchors["joints"]["l"], anchors["joints"]["r"]
                assert abs(math.dist(left["shoulder"], left["elbow"]) - throw.LEFT_UPPER_LENGTH) < 1e-9
                assert abs(math.dist(left["elbow"], left["wrist"]) - throw.LEFT_FORE_LENGTH) < 1e-9
                if equipped:
                    upper = math.dist(right["shoulder"], right["elbow"])
                    fore = math.dist(right["elbow"], right["wrist"])
                    assert abs(upper - 16) < 1e-9 and abs(fore - 16) < 1e-9
                    a = tuple(right["elbow"][i] - right["shoulder"][i] for i in (0, 1))
                    b = tuple(right["wrist"][i] - right["elbow"][i] for i in (0, 1))
                    cosine = sum(a[i] * b[i] for i in (0, 1)) / (upper * fore)
                    assert abs(math.degrees(math.acos(cosine)) - 12) < 1e-9
                assert abs(math.dist(anchors["right_hand"], anchors["muzzle"]) - grip.MUZZLE_DISTANCE) < 1e-9
                checked += 1
    lower_checked, lower_reverse_pairs = 0, 0
    for side in ("left", "right"):
        idle, _ = gait.render_lower(side=side)
        for values in (TRACKS["entry"][0], TRACKS["exit"][-1]):
            image, _ = render_lower(values, side)
            assert idle.tobytes() == image.tobytes(), (side, "idle seam")
        held, held_anchors = render_lower(HELD, side)
        for values in (TRACKS["entry"][-1], *TRACKS["loop"], TRACKS["exit"][0]):
            image, anchors = render_lower(values, side)
            assert held.tobytes() == image.tobytes() and held_anchors == anchors
        for entry, exit_values in zip(TRACKS["entry"], reversed(TRACKS["exit"])):
            entry_image, entry_anchors = render_lower(entry, side)
            exit_image, exit_anchors = render_lower(exit_values, side)
            assert entry_image.tobytes() == exit_image.tobytes() and entry_anchors == exit_anchors
            lower_reverse_pairs += 1
        for sequence in TRACKS.values():
            for values in sequence:
                _, metadata = render_lower(values, side)
                left, right = metadata["left"], metadata["right"]
                assert left["boot"][0] - right["boot"][0] >= 30.0
                for leg in (left, right):
                    assert math.dist(leg["hip"], leg["knee"]) < 24.0
                    assert math.dist(leg["knee"], leg["ankle"]) < 46.0
                    assert abs(math.dist(leg["ankle"], leg["boot"]) - 7.0) < 1e-9
                if values["kneel_weight"] == 1.0:
                    assert left["boot"][1] < 100.0 and right["boot"][1] < 100.0
                    assert left["knee"][1] > left["hip"][1] and right["knee"][1] > right["hip"][1]
                    assert math.sin(left["toe_angle"]) < -.99 and math.sin(right["toe_angle"]) < -.99
                lower_checked += 1
    return {"validated_frames": checked, "exact_idle_endpoints": len(MODES) * 2,
            "continuous_track_seams": len(MODES) * 3,
            "exact_reversed_entry_exit_pairs": exact_reversals,
            "constant_limb_lengths": True, "equipped_elbow_degrees": 12,
            "source_sha256_verified": True, "validated_lower_frames": lower_checked,
            "exact_lower_idle_endpoints": 4, "exact_lower_reverse_pairs": lower_reverse_pairs,
            "fixed_kneeling_loop_feet": True, "rigid_boot_size": list(gait.BOOT_SIZE),
            "minimum_source_boot_spacing": 30.0, "kneeling_toes_face_back": True,
            "exact_whole_silhouette_idle_endpoints": 12, "visible_rear_boots_all_modes": True}


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
    action.export_atlas(images, OUTPUT / "prayer_upper_layers.png")
    lower_frames = []
    for side in ("left", "right"):
        lower_images = []
        for track, sequence in TRACKS.items():
            for frame, values in enumerate(sequence):
                image, metadata = render_lower(values, side)
                lower_images.append(image)
                if side == "left":
                    lower_frames.append({**metadata, "track": track, "frame": frame})
        action.export_atlas(lower_images, OUTPUT / f"prayer_{side}_leg_layers.png")
    track_indices, offset = {}, 0
    for track, sequence in TRACKS.items():
        track_indices[track] = {"offset": offset, "count": len(sequence), "duration": TRACK_DURATIONS[track]}
        offset += len(sequence)
    lines = ["extends RefCounted", "## Generated by tools/character_rig/prayer_rig.py; source canvas pixels.",
             "const FRAMES_PER_MODE := " + str(FRAMES_PER_MODE),
             "const TRACKS := " + action.gd_literal(track_indices),
             "const FRAMES: Array[Dictionary] = ["]
    for frame in frames:
        anchors = {key: frame[key] for key in ("right_hand", "muzzle", "flashlight_angle")}
        lines.append("\t" + action.gd_literal(anchors) + ",")
    lines.append("]")
    lines.append("const LOWER_FRAMES: Array[Dictionary] = [")
    for frame in lower_frames:
        lines.append("\t" + action.gd_literal(frame) + ",")
    lines.append("]")
    (OUTPUT / "prayer_layer_anchors.gd").write_text("\n".join(lines) + "\n")
    manifest = {
        "source_sha256": SOURCE_SHA256,
        "recipe": "prayer_rig.py; original cutouts, gait_rig.py, throw_rig.py, grip_rig.py and export_action_layers.py helpers",
        "frame_size": [256, 256], "atlas_columns": 8, "pivot": [128, 128], "world_scale": .5,
        "tracks": track_indices, "authored_pose_transforms": POSES, "neutral_pose": NEUTRAL,
        "mode_count": len(MODES), "frames_per_mode": FRAMES_PER_MODE,
        "packing": "mode * 24 + track.offset + frame; modes = neutral, equipped -45, -22.5, 0, +22.5, +45 degrees",
        "left_bone_lengths": [throw.LEFT_UPPER_LENGTH, throw.LEFT_FORE_LENGTH],
        "lower_frame_count": 24,
        "lower_packing": "track.offset + frame; shared by all equipment and aim modes; rotate with body heading",
        "notes": [
            "Knees settle forward while shins fold back; separate rear-facing boots remain visible behind the bowed torso.",
            "The free left hand draws inward; the right hand retains the flashlight during the kneel.",
            "Entry lasts 0.42 seconds, the quiet breathing loop lasts 2.0 seconds, exit lasts 0.38 seconds.",
            "Entry and exit are exact reverse frame sequences, allowing interrupted entry to unwind continuously.",
            "Entry begins at exact legacy idle; exit ends at exact legacy idle in every equipment and aim mode.",
            "Entry end, both loop endpoints and exit start share identical held pixels and anchors.",
            "Head displacement at the held pose is 5.5 world pixels, with 3.5 world-pixel torso settling.",
            "Lower entry/exit are exact reversals and join the original idle leg exports byte-for-byte.",
            "Kneeling legs stay fixed during the breathing loop; only the upper body and torch shoulder breathe.",
            "Free-arm folding follows the chest rather than the flashlight's aim offset.",
            "Equipped right arm retains 16-pixel bones, its 12-degree bend, and the single rigid hand/torch attachment.",
            "Interpolation changes original part transforms; no alpha crossfades, new artwork, emission or shadows.",
            "Original locomotion, throw and breath exports and source artwork remain unchanged.",
        ],
        "validation": validation, "frames": frames, "lower_frames": lower_frames,
    }
    (ROOT / "prayer_layers_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.review_dir:
        args.review_dir.mkdir(parents=True, exist_ok=True)
        values = [value for sequence in TRACKS.values() for value in sequence]
        labels = [f"{track} {i + 1}/{len(sequence)}" for track, sequence in TRACKS.items()
                  for i in range(len(sequence))]
        rig.contact_sheet([combined(value) for value in values], labels,
                          args.review_dir / "prayer_sequence_contacts.png", cols=8, cell=256)
        rig.contact_sheet([combined(value, equipped=False) for value in values], labels,
                          args.review_dir / "prayer_neutral_contacts.png", cols=8, cell=256)
        rig.contact_sheet([combined(value, step) for value in (NEUTRAL, HELD, FOCUSED_INHALE, FOCUSED_EXHALE)
                           for step in action.AIM_STEPS],
                          [f"{name} {step * 22.5:+g} deg" for name in ("neutral", "held", "inhale", "exhale")
                           for step in action.AIM_STEPS],
                          args.review_dir / "prayer_aim_contacts.png", cols=5, cell=256)
        rig.contact_sheet([combined(value).crop((64, 88, 192, 200)) for value in values], labels,
                          args.review_dir / "prayer_detail_contacts.png", cols=8, cell=256)
        rig.contact_sheet([combined(value).crop((64, 64, 192, 200)) for value in values], labels,
                          args.review_dir / "prayer_kneel_detail_contacts.png", cols=8, cell=256)
        rig.contact_sheet([combined(value).rotate(degrees, Image.Resampling.BICUBIC, center=(128, 128))
                           for value in (NEUTRAL, HELD) for degrees in rig.FACING.values()],
                          [f"{pose_name} {direction}" for pose_name in ("idle", "kneeling") for direction in rig.FACING],
                          args.review_dir / "prayer_kneel_heading_contacts.png", cols=8, cell=256)
    print(json.dumps({"upper_frames": len(images), "tracks": track_indices,
                      "validation": validation, "output": str(OUTPUT / "prayer_upper_layers.png")}))


if __name__ == "__main__":
    main()
