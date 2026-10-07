"""A shared wrist attachment constructed from the original v2 source pixels.

The equipped right forearm contains jacket sleeve only. Its open hand is
replaced by a compact grip and flashlight in ONE rigid attachment. Rotate
that whole attachment around WRIST, so visible skin can never rotate away
from the torch or leave a second stationary hand in the upper-body atlas.

All landmarks are source-canvas pixels, before actor scaling. The attachment
points south (+Y); angles accepted by draw_grip are Godot relative radians.
Source artwork and the original neutral forearm are never modified.
"""
from pathlib import Path
import argparse
import json
import math

from PIL import Image, ImageChops, ImageDraw
import bake_rig as rig

SIZE = (32, 48)
WRIST = (16, 20)
GRIP = (16, 24)
MUZZLE = (16, 35)
MUZZLE_DISTANCE = 15.0

# Coordinates inside bake_rig.parts['fore_r'] (105 x 344). The sleeve's
# curved lower edge ends near y=200; y=190 is the last wholly jacket row.
# The relaxed fingertips below y=320 are omitted from the gripping hand.
SLEEVE_RECT = (0, 0, 105, 190)
CUFF_RECT = (35, 163, 83, 190)
CUFF_SIZE = (9, 6)
HAND_RECT = (20, 199, 89, 320)
HAND_SIZE = (12, 13)
HAND_TOP_LEFT = (9.5, 18.0)
HAND_SHEAR = .20


def _sleeve():
    return rig.parts["fore_r"].crop(SLEEVE_RECT)


def _hand():
    hand = rig.parts["fore_r"].crop(HAND_RECT)
    # Retain wrist, knuckle and curled thumb pixels. A rounded distal mask
    # prevents the rectangular crop from becoming a straight finger edge.
    mask = Image.new("L", hand.size)
    draw = ImageDraw.Draw(mask)
    draw.rectangle((0, 0, hand.width, 83), fill=255)
    draw.ellipse((0, 49, hand.width - 1, hand.height - 1), fill=255)
    hand.putalpha(ImageChops.multiply(hand.getchannel("A"), mask))
    return hand


def _grip_supersampled():
    canvas = Image.new("RGBA", (SIZE[0] * rig.SS, SIZE[1] * rig.SS))
    # Cylinder below the gripping hand. Its visible lens ends at MUZZLE.
    rig.put(canvas, "flashlight", (16, 24), 6.5, 22)
    hand = _hand().resize((round(HAND_SIZE[0] * rig.SS), round(HAND_SIZE[1] * rig.SS)),
                          Image.Resampling.LANCZOS)
    # Curl the palm slightly around the cylinder: the wrist is unchanged,
    # while the source thumb/index opening moves onto the torch's centerline.
    hand = hand.transform((hand.width + round(HAND_SHEAR * hand.height), hand.height),
                          Image.Transform.AFFINE, (1, -HAND_SHEAR, 0, 0, 1, 0),
                          Image.Resampling.BICUBIC)
    canvas.alpha_composite(hand, tuple(round(value * rig.SS) for value in HAND_TOP_LEFT))
    return canvas


def render_grip():
    """Return the 32 x 48 RGBA wrist/hand/flashlight attachment texture.

    Draw at Rect2(-16,-20,32,48), rotated around the wrist. WRIST is the
    forearm attachment; GRIP is the physical hand/cylinder overlap, while
    MUZZLE is the point from which the flashlight beam should emerge.
    """
    return _grip_supersampled().resize(SIZE, Image.Resampling.LANCZOS)


def render_equipped_upper_arm(canvas, shoulder, elbow, width=20, overlap=8):
    """Align the original right sleeve to the actual shoulder/elbow bones.

    Pillow rotates a south-pointing source toward +X with a positive angle.
    Keep this local to the equipped rig; legacy bakes remain untouched.
    """
    dx, dy = elbow[0] - shoulder[0], elbow[1] - shoulder[1]
    center = ((shoulder[0] + elbow[0]) / 2, (shoulder[1] + elbow[1]) / 2)
    angle = math.degrees(math.atan2(dx, dy))
    rig.put(canvas, "upper_r", center, width, math.hypot(dx, dy) + overlap, angle)


def render_equipped_forearm(canvas, elbow, wrist, width=15, overlap=6):
    """Composite sleeve-only forearm into a rig.SS supersampled canvas.

    Elbow and wrist are source coordinates. The jacket extends overlap/2
    pixels past the joint and the attachment's skin begins 2 pixels before
    it. That contact remains filled during continuous wrist articulation.
    """
    dx, dy = wrist[0] - elbow[0], wrist[1] - elbow[1]
    length = math.hypot(dx, dy) + overlap
    sleeve = _sleeve().resize((max(1, round(width * rig.SS)), max(1, round(length * rig.SS))),
                              Image.Resampling.LANCZOS)
    angle = math.degrees(math.atan2(dx, dy))
    sleeve = sleeve.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    center = ((elbow[0] + wrist[0]) / 2, (elbow[1] + wrist[1]) / 2)
    canvas.alpha_composite(sleeve, (round(center[0] * rig.SS - sleeve.width / 2),
                                    round(center[1] * rig.SS - sleeve.height / 2)))
    # The source cuff is curved and off-center, so midpoint placement alone
    # can leave its last opaque pixel short of an oblique wrist. Register a
    # short rounded cuff directly on the joint using those same jacket pixels.
    # It sits below the rigid hand and overlaps both sides of the sleeve seam.
    cuff = rig.parts["fore_r"].crop(CUFF_RECT).resize(
        (CUFF_SIZE[0] * rig.SS, CUFF_SIZE[1] * rig.SS), Image.Resampling.LANCZOS)
    mask = Image.new("L", cuff.size)
    ImageDraw.Draw(mask).ellipse((0, 0, cuff.width - 1, cuff.height - 1), fill=255)
    cuff.putalpha(ImageChops.multiply(cuff.getchannel("A"), mask))
    cuff = cuff.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    canvas.alpha_composite(cuff, (round(wrist[0] * rig.SS - cuff.width / 2),
                                  round(wrist[1] * rig.SS - cuff.height / 2)))


def draw_grip(canvas, wrist, relative_angle=0):
    """Composite the complete rigid attachment, rotated about its wrist.

    canvas is supersampled by rig.SS. relative_angle=0 points south, positive
    angles turn south toward west, matching the runtime Sprite2D transform.
    """
    attachment = Image.new("RGBA", canvas.size)
    attachment.alpha_composite(_grip_supersampled(),
                               (round((wrist[0] - WRIST[0]) * rig.SS),
                                round((wrist[1] - WRIST[1]) * rig.SS)))
    if relative_angle:
        attachment = attachment.rotate(-math.degrees(relative_angle), Image.Resampling.BICUBIC,
                                       center=(wrist[0] * rig.SS, wrist[1] * rig.SS))
    canvas.alpha_composite(attachment)


def metadata():
    return {
        "size": list(SIZE), "wrist": list(WRIST), "grip": list(GRIP),
        "muzzle": list(MUZZLE), "muzzle_distance": MUZZLE_DISTANCE,
        "sleeve_source_crop": list(SLEEVE_RECT), "hand_source_crop": list(HAND_RECT),
        "cuff_source_crop": list(CUFF_RECT), "cuff_size": list(CUFF_SIZE),
        "hand_size": list(HAND_SIZE), "hand_top_left": list(HAND_TOP_LEFT),
        "hand_shear": HAND_SHEAR,
        "skin_landmarks": {"wrist": [16, 20], "knuckle": [16, 25], "thumb": [12, 27]},
        "torch_landmarks": {"rear": [16, 15], "barrel": [17, 32], "lens": [16, 34]},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review-dir", type=Path, required=True)
    args = parser.parse_args()
    args.review_dir.mkdir(parents=True, exist_ok=True)
    render_grip().save(args.review_dir / "hand_flashlight_attachment.png")
    (args.review_dir / "grip_landmarks.json").write_text(json.dumps(metadata(), indent=2) + "\n")
    poses, labels = [], []
    # The wrist articulates while the forearm stays on its authored pose.
    # Eight world orientations expose any asymmetric source crop or seam.
    for body_degrees in range(0, 360, 45):
        for wrist_degrees in (-11.25, 0, 11.25):
            canvas = Image.new("RGBA", (128 * rig.SS, 128 * rig.SS))
            elbow, wrist = (64, 40), (64, 67)
            render_equipped_forearm(canvas, elbow, wrist)
            draw_grip(canvas, wrist, math.radians(wrist_degrees))
            if body_degrees:
                canvas = canvas.rotate(-body_degrees, Image.Resampling.BICUBIC,
                                       center=(64 * rig.SS, 64 * rig.SS))
            poses.append(canvas.resize((128, 128), Image.Resampling.LANCZOS))
            labels.append(f"Facing {body_degrees} / wrist {wrist_degrees:+g}")
    rig.contact_sheet(poses, labels, args.review_dir / "grip_rotation_contacts.png", cols=6, cell=220)
    closeup = Image.new("RGB", (320, 480), "#30332e")
    texture = render_grip().resize((320, 480), Image.Resampling.NEAREST)
    closeup.paste(texture, (0, 0), texture)
    closeup.save(args.review_dir / "grip_texture_closeup.png")
    print(json.dumps(metadata()))


if __name__ == "__main__":
    main()
