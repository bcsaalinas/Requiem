"""Bake independent locomotion, upper-body and held-prop layers of the v2 rig.

Run with Pillow: python export_action_layers.py [--review-dir DIRECTORY]
Only transforms the original modular source pixels; original exported assets
remain untouched. Body forward is +Y. Angles use Godot's screen convention:
positive angles turn +Y toward -X (clockwise on screen).
"""
from pathlib import Path
import argparse
import hashlib
import json
import math

from PIL import Image
import bake_rig as rig
import gait_rig as gait
import grip_rig as grip

ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT.parents[1] / "requiem/player/art/girl_rig_v2"
OUTPUT.mkdir(parents=True, exist_ok=True)
CELL = rig.SIZE
DIRECTIONS = list(rig.FACING)
STATES = ("idle", "walk", "sprint")
AIM_STEPS = (-2, -1, 0, 1, 2)
PIVOT = (128, 128)
TORCH_GRIP = grip.WRIST
TORCH_MUZZLE_DISTANCE = grip.MUZZLE_DISTANCE


def rotate(point, radians, pivot=PIVOT):
    dx, dy = point[0] - pivot[0], point[1] - pivot[1]
    return (pivot[0] + dx * math.cos(radians) - dy * math.sin(radians),
            pivot[1] + dx * math.sin(radians) + dy * math.cos(radians))


def finish(canvas):
    return canvas.resize((CELL, CELL), Image.Resampling.LANCZOS)


def render_lower(state="idle", frame=0, direction="s"):
    if state in ("turn_cw", "turn_ccw"):
        return gait.render_turn(1 if state == "turn_cw" else -1, frame)[0]
    return gait.render_lower(state, frame, direction)[0]


def render_upper(state="idle", frame=0, aim_step=0, equipped=False):
    canvas = Image.new("RGBA", (CELL * rig.SS, CELL * rig.SS))
    moving, sprint, phase = state != "idle", state == "sprint", frame / 8
    lean = 7 if sprint else 0
    sway = .9 * math.sin(phase * 2 * math.pi) if moving else 0
    aim = math.radians(aim_step * 22.5) if equipped else 0.0
    torso_turn = aim * .4
    shoulder_y = 137 + lean
    arms = []
    for side, sign in (("l", 1), ("r", -1)):
        wave = math.cos(phase * 2 * math.pi) * (1 if side == "r" else -1) if moving else 0
        amplitude = (19 if sprint else 9) * (.65 if side == "r" else 1)
        shoulder = rotate((128 + sign * 32 + sway, shoulder_y), torso_turn)
        if equipped and side == "r":
            # Keep one gently extended carrying posture at every aim angle.
            # The forearm follows the torch; a fixed 12-degree elbow bend
            # leaves a natural joint without the old opposing side offsets.
            forward = (-math.sin(aim), math.cos(aim))
            upper_angle = aim + math.radians(12)
            upper_forward = (-math.sin(upper_angle), math.cos(upper_angle))
            lateral = (math.cos(torso_turn), math.sin(torso_turn))
            shoulder = (shoulder[0] - lateral[0] * 2,
                        shoulder[1] - lateral[1] * 2)
            elbow = (shoulder[0] + upper_forward[0] * 16,
                     shoulder[1] + upper_forward[1] * 16)
            forearm_reach = 16 + (.5 * wave if moving else 0)
            hand = (elbow[0] + forward[0] * forearm_reach,
                    elbow[1] + forward[1] * forearm_reach)
        else:
            elbow = rotate((128 + sign * (39 if sprint else 36) + sway,
                            147 + lean + wave * amplitude * .6), torso_turn)
            hand = rotate((128 + sign * (31 if sprint else 33) + sway,
                           161 + wave * amplitude + lean), torso_turn)
        if equipped and side == "r":
            grip.render_equipped_upper_arm(canvas, shoulder, elbow)
        else:
            rig.segment(canvas, "upper_" + side, shoulder, elbow, 20, 8)
        arms.append((side, elbow, hand))
    torso = rotate((128 + sway, 124 + lean), torso_turn)
    rig.put(canvas, "torso", torso, 79, 52, 180 - math.degrees(torso_turn))
    for side, elbow, hand in arms:
        if equipped and side == "r":
            grip.render_equipped_forearm(canvas, elbow, hand)
        else:
            rig.segment(canvas, "fore_" + side, elbow, hand, 15, 5)
        if side == "r":
            right_hand = hand
    head = rotate((128 + sway * .45, 144 + lean * 1.35), torso_turn)
    head_sway = -1.2 * math.sin(phase * 2 * math.pi) if moving else 0
    rig.put(canvas, "head", head, 44, 57, head_sway - math.degrees(torso_turn))
    flashlight_angle = math.pi / 2 + aim
    muzzle = (right_hand[0] + math.cos(flashlight_angle) * TORCH_MUZZLE_DISTANCE,
              right_hand[1] + math.sin(flashlight_angle) * TORCH_MUZZLE_DISTANCE)
    return finish(canvas), {
        "right_hand": list(right_hand), "muzzle": list(muzzle),
        "flashlight_angle": flashlight_angle,
    }


def render_torch():
    return grip.render_grip()


def export_atlas(images, path):
    atlas = Image.new("RGBA", (CELL * 8, CELL * math.ceil(len(images) / 8)))
    for index, image in enumerate(images):
        bounds = image.getchannel("A").point(lambda value: 255 if value >= 32 else 0).getbbox()
        assert bounds and min(bounds[:2]) >= 8 and max(bounds[2:]) <= 248, (index, bounds)
        atlas.alpha_composite(image, (index % 8 * CELL, index // 8 * CELL))
    atlas.save(path, optimize=True)


def combined(state="idle", frame=0, direction="s", aim_step=0, equipped=True):
    canvas = render_lower(state, frame, direction)
    upper_state = state if state in STATES else "idle"
    upper, anchors = render_upper(upper_state, frame, aim_step, equipped)
    canvas.alpha_composite(upper)
    if equipped:
        torch = Image.new("RGBA", (CELL * rig.SS, CELL * rig.SS))
        angle = anchors["flashlight_angle"] - math.pi / 2
        hand = anchors["right_hand"]
        grip.draw_grip(torch, hand, angle)
        canvas.alpha_composite(finish(torch))
    return canvas


def gd_literal(value, key=""):
    """Encode metadata as export-safe GDScript constants with actual vectors."""
    if isinstance(value, dict):
        return "{" + ", ".join(json.dumps(name) + ": " + gd_literal(item, name)
                                for name, item in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        if key in ("boot", "hip", "knee", "ankle", "right_hand", "muzzle"):
            return "Vector2(%.9f, %.9f)" % (value[0], value[1])
        return "[" + ", ".join(gd_literal(item) for item in value) + "]"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return "%.12f" % value
    return json.dumps(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review-dir", type=Path)
    args = parser.parse_args()
    lower, left_legs, right_legs, lower_entries = [], [], [], []
    for state in STATES:
        for direction in (DIRECTIONS if state != "idle" else ["s"]):
            for frame in range(1 if state == "idle" else 8):
                image, anchors = gait.render_lower(state, frame, direction)
                lower.append(image)
                left_legs.append(gait.render_lower(state, frame, direction, "left")[0])
                right_legs.append(gait.render_lower(state, frame, direction, "right")[0])
                lower_entries.append(anchors)
    for sign, state in ((1, "turn_cw"), (-1, "turn_ccw")):
        for frame in range(gait.TURN_FRAME_COUNT):
            image, anchors = gait.render_turn(sign, frame)
            lower.append(image)
            left_legs.append(gait.render_turn(sign, frame, "left")[0])
            right_legs.append(gait.render_turn(sign, frame, "right")[0])
            lower_entries.append({**anchors, "state": state, "direction": "s"})
    upper, upper_entries = [], []
    for equipped, aim_step in [(False, 0)] + [(True, step) for step in AIM_STEPS]:
        for state in STATES:
            for frame in range(1 if state == "idle" else 8):
                image, anchors = render_upper(state, frame, aim_step, equipped)
                upper.append(image)
                upper_entries.append({"state": state, "frame": frame, "equipped": equipped,
                                      "aim_step": aim_step, **anchors})
    (ROOT / "previews").mkdir(exist_ok=True)
    export_atlas(lower, ROOT / "previews/lower_layers.png")
    export_atlas(left_legs, OUTPUT / "left_leg_layers.png")
    export_atlas(right_legs, OUTPUT / "right_leg_layers.png")
    export_atlas(upper, OUTPUT / "upper_layers.png")
    render_torch().save(OUTPUT / "flashlight_layer.png", optimize=True)
    manifest = {
        "source_sha256": hashlib.sha256(rig.SOURCE.read_bytes()).hexdigest(),
        "recipe": "export_action_layers.py with gait_rig.py and grip_rig.py; imports original bake_rig.py without editing it",
        "perspective": "Same strict overhead constructed source rig as original girl_atlas.png",
        "frame_size": [CELL, CELL], "atlas_columns": 8, "pivot": list(PIVOT), "world_scale": .5,
        "directions": DIRECTIONS, "aim_step_degrees": 22.5, "aim_steps": list(AIM_STEPS),
        "pose_counts": {"idle": 1, "walk": 8, "sprint": 8, "turn_cw": 4, "turn_ccw": 4}, "loop_seconds": .9,
        "lower_atlas_indices": {"idle": 0, "walk": 1, "sprint": 65, "turn_cw": 129, "turn_ccw": 133},
        "flashlight_size": list(grip.SIZE), "flashlight_grip": list(TORCH_GRIP),
        "flashlight_muzzle_distance": TORCH_MUZZLE_DISTANCE,
        "grip_attachment": grip.metadata(),
        "gait_limits": {"max_lateral_excursion": gait.MAX_LATERAL_EXCURSION,
                        "max_hip_ankle_reach": gait.MAX_HIP_ANKLE_REACH,
                        "passing_frames": list(gait.PASSING_FRAMES)},
        "angles": "Godot screen radians: south is PI/2; positive relative aim turns south toward west",
        "notes": [
            "Lower poses select travel relative to pelvis with bounded lateral correction steps and independent support-foot layers.",
            "Four authored turn poses per sign move the leading foot, then the trailing foot; boot/toe/contact anchors accompany every pose.",
            "Upper-body mode is neutral or one of five torch aim offsets; limb proportions and source artwork are shared.",
            "The equipped elbow retains a gentle 12-degree bend in every pose; the forearm points along the authored torch heading.",
            "The equipped forearm contains sleeve only. One rigid hand+torch attachment rotates continuously about the wrist; ownership controls whether it is drawn.",
            "All anchors use source canvas coordinates; subtract pivot and multiply by world_scale before body rotation.",
            "Exact wrist aim may rotate the prop within half an authored aim step; beam origin follows the resulting muzzle.",
            "No new AI generation, interpolated frames, shadows or baked light emission.",
        ],
        "lower_frames": lower_entries, "upper_frames": upper_entries,
    }
    (ROOT / "action_layers_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    # A script constant is a normal export dependency. Raw JSON would require
    # a project export include filter, so runtime sockets use this companion.
    anchor_lines = ["extends RefCounted", "## Generated by export_action_layers.py; source canvas coordinates.",
                    "const GRIP_WRIST := Vector2(%s, %s)" % grip.WRIST,
                    "const GRIP_MUZZLE := Vector2(%s, %s)" % grip.MUZZLE,
                    "const FRAMES: Array[Dictionary] = ["]
    for entry in upper_entries:
        hand, muzzle = entry["right_hand"], entry["muzzle"]
        anchor_lines.append(
            '\t{"right_hand": Vector2(%.9f, %.9f), "muzzle": Vector2(%.9f, %.9f), "flashlight_angle": %.12f},'
            % (hand[0], hand[1], muzzle[0], muzzle[1], entry["flashlight_angle"]))
    anchor_lines.append("]")
    anchor_lines.append("const LOWER_FRAMES: Array[Dictionary] = [")
    anchor_lines.extend("\t" + gd_literal(entry) + "," for entry in lower_entries)
    anchor_lines.append("]")
    (OUTPUT / "action_layer_anchors.gd").write_text("\n".join(anchor_lines) + "\n")
    if args.review_dir:
        args.review_dir.mkdir(parents=True, exist_ok=True)
        rig.contact_sheet(
            [combined(state, frame, direction, aim) for state, frame, direction, aim in
             [("idle", 0, "s", step) for step in AIM_STEPS] +
             [("walk", 0, direction, 0) for direction in DIRECTIONS] +
             [("sprint", frame, "s", 0) for frame in (0, 2, 4, 6)] +
             [("idle", 0, "s", 0)]],
            [f"Idle aim {step * 22.5:+g} deg" for step in AIM_STEPS] +
            [f"Walk travel {direction}" for direction in DIRECTIONS] +
            [f"Sprint pose {frame + 1}/8" for frame in (0, 2, 4, 6)] + ["Idle equipped"],
            args.review_dir / "action_layer_contacts.png", cols=5, cell=220)
        rig.contact_sheet([combined(equipped=False), combined(equipped=True)],
                          ["Before flashlight pickup", "After flashlight pickup"],
                          args.review_dir / "equipment_comparison.png", cols=2, cell=320)
        rig.contact_sheet([combined(state, frame) for state in ("turn_cw", "turn_ccw") for frame in range(4)],
                          [f"{state} {frame + 1}/4" for state in ("turn_cw", "turn_ccw") for frame in range(4)],
                          args.review_dir / "turn_pose_contacts.png", cols=4, cell=220)
    print(json.dumps({"lower_frames": len(lower), "upper_frames": len(upper), "output": str(ROOT)}))


if __name__ == "__main__":
    main()
