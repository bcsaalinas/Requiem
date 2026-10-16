"""Bake a brisk, planted sprint from the original overhead character cutouts.

Only sprint-specific exports are written. The eight-pose cycle covers 0.60 s
at 172.8 world pixels/s; boot contact anchors and arm poses share that clock.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math

from PIL import Image, ImageDraw, ImageFont
import bake_rig as rig
import export_action_layers as action
import gait_rig as gait
import grip_rig as grip
import throw_rig as throw

ROOT = Path(__file__).resolve().parent
OUTPUT = action.OUTPUT
CYCLE_SECONDS = .60
SPEED = 172.8
STRIDE_DISTANCE = SPEED * CYCLE_SECONDS
STANCE = .375
FRAMES_PER_MODE = 8
MODES = [(False, 0)] + [(True, step) for step in action.AIM_STEPS]
FREE_UPPER_LENGTH = 18.0
FREE_FORE_LENGTH = 18.0
MAX_LATERAL_EXCURSION = 7.0
PIVOT = (128, 128)


def foot_sample(phase):
    """Constant planted speed and a smooth, distinctly folded return step."""
    stroke = STRIDE_DISTANCE * STANCE / gait.WORLD_SCALE
    if phase < STANCE:
        return stroke * (.5 - phase / STANCE), 0.0, True, 0.0
    progress = (phase - STANCE) / (1 - STANCE)
    lift = math.sin(math.pi * progress)
    displacement = stroke * (-.5 + progress * progress * (3 - 2 * progress))
    # A lifted boot draws toward the back while the knee comes through. This
    # is foreshortening in the overhead view, never a foot crossing its lane.
    return displacement - 7.0 * lift * lift, lift, False, progress


def _knee(hip, ankle, sign, lift):
    dx, dy = ankle[0] - hip[0], ankle[1] - hip[1]
    distance = max(math.hypot(dx, dy), .001)
    # Equal, bounded projected bone lengths give a clearly folded recovery.
    segment = min(32.0, max(15.0, distance * .5 + 5 + lift * 3.0))
    height = math.sqrt(max(0.0, segment * segment - distance * distance * .25))
    perpendicular = (-dy / distance, dx / distance)
    if perpendicular[0] * sign < 0:
        perpendicular = (-perpendicular[0], -perpendicular[1])
    return ((hip[0] + ankle[0]) * .5 + perpendicular[0] * height,
            (hip[1] + ankle[1]) * .5 + perpendicular[1] * height)


def render_lower(frame=0, direction="s", side=None):
    if side not in (None, "left", "right"):
        raise ValueError("side must be None, left, or right")
    direction = direction if direction in rig.FACING else "s"
    frame = int(frame) % 8
    phase = (frame / 8.0 - 1 / 16.0) % 1.0
    travel_angle = math.radians(-rig.FACING[direction])
    travel = (-math.sin(travel_angle), math.cos(travel_angle))
    half_stroke = STRIDE_DISTANCE * STANCE / gait.WORLD_SCALE / 2
    legs, supports = {}, []
    for name, sign, part in gait._SIDES:
        side_phase = (phase + (0 if name == "left" else .5)) % 1.0
        displacement, lift, contact, progress = foot_sample(side_phase)
        lateral = travel[0] * displacement * min(1, MAX_LATERAL_EXCURSION / half_stroke)
        lateral = max(-7, min(7, lateral + sign * lift * 4))
        boot = (128 + sign * 15 + lateral,
                136 + travel[1] * displacement
                + sign * lift * abs(travel[0]) * 8 * abs(displacement) / half_stroke)
        hip = (128 + sign * 12, 129)
        toe = math.pi / 2 - math.radians(sign * 3)
        ankle = (boot[0] - math.cos(toe) * 7, boot[1] - math.sin(toe) * 7)
        legs[name] = dict(hip=hip, knee=_knee(hip, ankle, sign, lift), ankle=ankle,
                          boot=boot, toe_angle=toe, contact=contact, lift=lift,
                          swing_progress=progress)
        if contact:
            supports.append((abs(side_phase - STANCE / 2), name))
    canvas = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
    for name, sign, part in gait._SIDES:
        if side is not None and side != name:
            continue
        leg = legs[name]
        # Register cloth to the true bones; this helper's registration=1 uses
        # the corrected Pillow convention without editing any older bakes.
        throw.left_segment(canvas, "thigh_" + part, leg["hip"], leg["knee"], 22, 7, 1)
        throw.left_segment(canvas, "shin_" + part, leg["knee"], leg["ankle"], 18, 6, 1)
    for name, sign, part in gait._SIDES:
        if side is not None and side != name:
            continue
        leg = legs[name]
        rig.put(canvas, "boot_" + part, leg["boot"], *gait.BOOT_SIZE, sign * 3)
    return action.finish(canvas), {
        "state": "sprint", "frame": frame, "direction": direction,
        "phase": phase, "pelvis_angle": 0.0,
        "support": min(supports)[1] if supports else "",
        "passing": frame in gait.PASSING_FRAMES, **legs,
    }


def render_upper(frame=0, aim_step=0, equipped=False):
    frame = int(frame) % 8
    phase = frame / 8.0
    wave = math.cos(phase * math.tau)
    # Two light rises per cycle imply running impact without moving the root
    # or unplanting the feet. The entire source torso and head stay rigid.
    rise = 1.8 * math.cos(phase * math.tau * 2)
    sway = 1.5 * math.sin(phase * math.tau)
    aim = math.radians(aim_step * 22.5) if equipped else 0.0
    torso_turn = aim * .4 + math.radians(2.4 * math.sin(phase * math.tau))
    canvas = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
    joints, arms = {}, []
    for part, sign in (("l", 1), ("r", -1)):
        shoulder = action.rotate((128 + sign * 32 + sway, 150 + rise), torso_turn)
        if part == "r" and equipped:
            lateral = (math.cos(torso_turn), math.sin(torso_turn))
            shoulder = (shoulder[0] - 2 * lateral[0], shoulder[1] - 2 * lateral[1])
            elbow = throw.extend(shoulder, 16, aim + math.radians(12))
            hand = throw.extend(elbow, 16, aim)
            grip.render_equipped_upper_arm(canvas, shoulder, elbow)
        else:
            drive = wave * (-1 if part == "l" else 1)
            # The elbow drives behind the shoulder while the hand folds
            # inward beside the coat. Avoid a broad sideways "chicken wing"
            # sweep: the hand travels forward/back, close to its own side.
            upper_angle = math.radians(sign * (-60 + 50 * drive)) + torso_turn
            fore_angle = math.radians(sign * (37.5 - 17.5 * drive)) + torso_turn
            elbow = throw.extend(shoulder, FREE_UPPER_LENGTH, upper_angle)
            hand = throw.extend(elbow, FREE_FORE_LENGTH, fore_angle)
            throw.left_segment(canvas, "upper_" + part, shoulder, elbow, 20, 8, 1)
        joints[part] = {"shoulder": shoulder, "elbow": elbow, "wrist": hand}
        arms.append((part, elbow, hand))
    torso = action.rotate((128 + sway, 137 + rise), torso_turn)
    rig.put(canvas, "torso", torso, 79, 52, 180 - math.degrees(torso_turn))
    for part, elbow, hand in arms:
        if part == "r" and equipped:
            grip.render_equipped_forearm(canvas, elbow, hand)
        else:
            throw.left_segment(canvas, "fore_" + part, elbow, hand, 15, 5, 1)
    head = action.rotate((128 + sway * .45, 162 + rise * .7), torso_turn)
    rig.put(canvas, "head", head, 44, 57, -math.degrees(torso_turn) - math.sin(phase * math.tau))
    right_hand = joints["r"]["wrist"]
    flashlight_angle = math.pi / 2 + aim
    muzzle = (right_hand[0] + math.cos(flashlight_angle) * grip.MUZZLE_DISTANCE,
              right_hand[1] + math.sin(flashlight_angle) * grip.MUZZLE_DISTANCE)
    return action.finish(canvas), dict(right_hand=right_hand, muzzle=muzzle,
        flashlight_angle=flashlight_angle, joints=joints, torso=torso, head=head)


def combined(frame=0, direction="s", aim_step=0, equipped=True, old=False):
    if old:
        return action.combined("sprint", frame, direction, aim_step, equipped)
    canvas, _ = render_lower(frame, direction)
    upper, anchors = render_upper(frame, aim_step, equipped)
    canvas.alpha_composite(upper)
    if equipped:
        attachment = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
        grip.draw_grip(attachment, anchors["right_hand"], anchors["flashlight_angle"] - math.pi / 2)
        canvas.alpha_composite(action.finish(attachment))
    return canvas


def validate():
    minimum_boot_gap = float("inf")
    maximum_reach = 0.0
    for direction in action.DIRECTIONS:
        for frame in range(8):
            image, meta = render_lower(frame, direction)
            assert image.tobytes() == render_lower(frame + 8, direction)[0].tobytes()
            left, right = meta["left"], meta["right"]
            minimum_boot_gap = min(minimum_boot_gap, math.dist(left["boot"], right["boot"]))
            assert left["boot"][0] >= 136 and right["boot"][0] <= 120
            for side, sign in (("left", 1), ("right", -1)):
                leg = meta[side]
                assert abs(leg["boot"][0] - (128 + sign * 15)) <= 7.00001
                reach = math.dist(leg["hip"], leg["ankle"])
                maximum_reach = max(maximum_reach, reach)
                assert reach <= gait.MAX_HIP_ANKLE_REACH
                assert math.dist(leg["hip"], leg["knee"]) <= 32.00001
                assert math.dist(leg["knee"], leg["ankle"]) <= 32.00001
                assert abs(leg["toe_angle"] - (math.pi / 2 - math.radians(sign * 3))) < 1e-9
    for equipped, step in MODES:
        for frame in range(8):
            image, anchors = render_upper(frame, step, equipped)
            assert image.tobytes() == render_upper(frame + 8, step, equipped)[0].tobytes()
            for side in ("l", "r"):
                joints = anchors["joints"][side]
                first = math.dist(joints["shoulder"], joints["elbow"])
                second = math.dist(joints["elbow"], joints["wrist"])
                expected = 16.0 if side == "r" and equipped else 18.0
                assert abs(first - expected) < 1e-9 and abs(second - expected) < 1e-9
                if side == "r" and equipped:
                    a = [joints["elbow"][i] - joints["shoulder"][i] for i in (0, 1)]
                    b = [joints["wrist"][i] - joints["elbow"][i] for i in (0, 1)]
                    angle = math.degrees(math.acos(sum(a[i] * b[i] for i in (0, 1)) / (first * second)))
                    assert abs(angle - 12) < 1e-9
            assert abs(math.dist(anchors["right_hand"], anchors["muzzle"]) - 15) < 1e-9
    # Contact stride matches the requested speed; no extra root motion exists.
    for phase in (.02, .10, .20, .30):
        displacement = foot_sample(phase)[0] - foot_sample(phase + .01)[0]
        assert abs(displacement * .5 / (.01 * CYCLE_SECONDS) - SPEED) < 1e-8
    return dict(upper_frames=48, lower_frames=64, cycle_seconds=CYCLE_SECONDS,
        stride_distance=STRIDE_DISTANCE, minimum_boot_center_gap=minimum_boot_gap,
        maximum_hip_ankle_reach=maximum_reach, max_lateral_excursion=7,
        equipped_elbow_degrees=12, rigid_boot_size=list(gait.BOOT_SIZE),
        fixed_upper_limb_lengths=True, cyclic_frame_wrapping=True,
        contact_velocity_matches_gameplay=True, passing_frames=list(gait.PASSING_FRAMES))


def reviews(directory, validation):
    directory.mkdir(parents=True, exist_ok=True)
    (directory / ".gdignore").touch()
    rig.contact_sheet([combined(frame, equipped=equipped) for equipped in (False, True) for frame in range(8)],
        [f"{'Torch' if equipped else 'Free arms'} {frame + 1}/8" for equipped in (False, True) for frame in range(8)],
        directory / "sprint_sequence_contacts.png", cols=8, cell=224)
    rig.contact_sheet([combined(frame, direction) for direction in action.DIRECTIONS for frame in (0, 2, 4, 6)],
        [f"Relative {direction} / {frame + 1}" for direction in action.DIRECTIONS for frame in (0, 2, 4, 6)],
        directory / "sprint_relative_feet_contacts.png", cols=4, cell=224)
    rig.contact_sheet([combined(frame, aim_step=step) for step in action.AIM_STEPS for frame in (0, 2, 4, 6)],
        [f"Aim {step * 22.5:+g} / {frame + 1}" for step in action.AIM_STEPS for frame in (0, 2, 4, 6)],
        directory / "sprint_aim_contacts.png", cols=4, cell=224)
    rig.contact_sheet([combined(frame).rotate(angle, Image.Resampling.BICUBIC) for angle in range(0, 360, 45) for frame in (0, 2, 4, 6)],
        [f"World {angle} / {frame + 1}" for angle in range(0, 360, 45) for frame in (0, 2, 4, 6)],
        directory / "sprint_world_facings.png", cols=4, cell=224)
    # Here each full source canvas is precisely the 128px in-game size, with
    # no zoom: this comparison reveals whether the new silhouette reads.
    rig.contact_sheet([combined(frame, old=old) for old in (True, False) for frame in range(8)],
        [f"{'Old' if old else 'New'} {frame + 1}/8" for old in (True, False) for frame in range(8)],
        directory / "sprint_gameplay_size_comparison.png", cols=8, cell=128)
    (directory / "sprint_validation.json").write_text(json.dumps(validation, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review-dir", type=Path)
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    validation = validate()
    if args.validate_only:
        print(json.dumps(validation))
        return
    upper, frames, left, right, lower_frames = [], [], [], [], []
    for equipped, step in MODES:
        for frame in range(8):
            image, anchors = render_upper(frame, step, equipped)
            upper.append(image)
            frames.append(dict(frame=frame, equipped=equipped, aim_step=step, **anchors))
    for direction in action.DIRECTIONS:
        for frame in range(8):
            image, anchors = render_lower(frame, direction, "left")
            left.append(image)
            right.append(render_lower(frame, direction, "right")[0])
            lower_frames.append(anchors)
    action.export_atlas(upper, OUTPUT / "sprint_upper_layers.png")
    action.export_atlas(left, OUTPUT / "sprint_left_leg_layers.png")
    action.export_atlas(right, OUTPUT / "sprint_right_leg_layers.png")
    lines = ["extends RefCounted", "## Generated by tools/character_rig/sprint_rig.py; source canvas pixels.",
             "const FRAMES_PER_MODE := 8", "const CYCLE_SECONDS := 0.60",
             "const STRIDE_DISTANCE := %.9f" % STRIDE_DISTANCE,
             "const FRAMES: Array[Dictionary] = ["]
    for entry in frames:
        lines.append("\t" + action.gd_literal({key: entry[key] for key in ("right_hand", "muzzle", "flashlight_angle")}) + ",")
    lines += ["]", "const LOWER_FRAMES: Array[Dictionary] = ["]
    lines.extend("\t" + action.gd_literal(entry) + "," for entry in lower_frames)
    lines.append("]")
    (OUTPUT / "sprint_layer_anchors.gd").write_text("\n".join(lines) + "\n")
    manifest = dict(source_sha256=hashlib.sha256(rig.SOURCE.read_bytes()).hexdigest(),
        recipe="sprint_rig.py with existing cutouts and read-only action/grip/throw helpers",
        frame_size=[256, 256], atlas_columns=8, pivot=[128, 128], world_scale=.5,
        cycle_seconds=CYCLE_SECONDS, speed=SPEED, stride_distance=STRIDE_DISTANCE,
        stance_fraction=STANCE, mode_count=6, frames_per_mode=8,
        directions=action.DIRECTIONS, upper_packing="mode * 8 + frame; neutral then equipped -2,-1,0,1,2",
        lower_packing="direction_index * 8 + frame; anatomical left/right sheets",
        notes=["Stronger forward lean, two-beat head/shoulder rhythm, and alternating bent free arms make sprint distinct from walking.",
               "Every upper limb has a constant projected length. The equipped elbow remains 12 degrees with one rigid hand/torch attachment.",
               "The 0.60 second stride matches 172.8px/s and uses the existing contact, swing_progress and passing-frame support solver.",
               "Rigid boots stay in separate anatomical lanes, retaining the original three-degree toe splay at every angle.",
               "Projected knees fold on recovery; trousers register to their actual bones using the corrected source-part transform.",
               "Original source, locomotion, breath, throw and prayer exports are never rewritten."],
        validation=validation, upper_frames=frames, lower_frames=lower_frames)
    (ROOT / "sprint_layers_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.review_dir:
        reviews(args.review_dir, validation)
    print(json.dumps(validation))


if __name__ == "__main__":
    main()
