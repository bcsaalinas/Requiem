"""Grounded lower-body poses using the existing v2 source parts.

This module only renders in memory. Coordinates are source-canvas pixels and
angles follow Godot's screen convention: south is pi/2, positive turns west.
The gameplay footstep clock remains authoritative; there is no new gait timer.
"""

import math

from PIL import Image

import bake_rig as rig

PIVOT = (128.0, 128.0)
WORLD_SCALE = 0.5
PASSING_FRAMES = (2, 6)
TURN_FRAME_COUNT = 4
MAX_LATERAL_EXCURSION = 7.0
MAX_HIP_ANKLE_REACH = 60.0
BOOT_SIZE = (18.0, 24.0)
_SIDES = (("left", 1.0, "l"), ("right", -1.0, "r"))


def _rotate(point, angle, pivot=PIVOT):
    x, y = point[0] - pivot[0], point[1] - pivot[1]
    cosine, sine = math.cos(angle), math.sin(angle)
    return (pivot[0] + x * cosine - y * sine,
            pivot[1] + x * sine + y * cosine)


def _mix(start, end, amount):
    return (start[0] + (end[0] - start[0]) * amount,
            start[1] + (end[1] - start[1]) * amount)


def _idle_boot(sign):
    return (128.0 + sign * 15.0, 136.0)


def _idle_hip(sign):
    return (128.0 + sign * 12.0, 129.0)


def _toe_angle(sign, heading=0.0):
    # Preserve the original three-degree boot splay; the boot image is rigid.
    return math.pi / 2.0 + heading - math.radians(sign * 3.0)


def _knee(hip, ankle, sign, heading):
    """Bend two bounded projected segments instead of stretching a long strip.

    A steep overhead view foreshortens the legs near the pelvis. Projection may
    shorten a segment, but its length is bounded and its texture width is fixed.
    """
    dx, dy = ankle[0] - hip[0], ankle[1] - hip[1]
    distance = max(math.hypot(dx, dy), 0.001)
    upper = max(10.0, min(32.0, distance * 0.52 + 4.0))
    lower = max(10.0, min(32.0, distance * 0.48 + 4.0))
    along = (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
    height = math.sqrt(max(0.0, upper * upper - along * along))
    axis = (dx / distance, dy / distance)
    perpendicular = (-axis[1], axis[0])
    outward = (sign * math.cos(heading), sign * math.sin(heading))
    if perpendicular[0] * outward[0] + perpendicular[1] * outward[1] < 0.0:
        perpendicular = (-perpendicular[0], -perpendicular[1])
    return (hip[0] + axis[0] * along + perpendicular[0] * height,
            hip[1] + axis[1] * along + perpendicular[1] * height)


def _leg(hip, boot, sign, heading, toe_angle, contact, lift=0.0, swing_progress=0.0):
    # Ankle stays behind the boot's toe along its own heading, including turns.
    forward = (math.cos(toe_angle), math.sin(toe_angle))
    ankle = (boot[0] - forward[0] * 7.0, boot[1] - forward[1] * 7.0)
    reach = math.dist(hip, ankle)
    if reach > MAX_HIP_ANKLE_REACH:
        ratio = MAX_HIP_ANKLE_REACH / reach
        ankle = _mix(hip, ankle, ratio)
        boot = (ankle[0] + forward[0] * 7.0, ankle[1] + forward[1] * 7.0)
    knee = _knee(hip, ankle, sign, heading)
    return {
        "boot": list(boot), "hip": list(hip), "knee": list(knee),
        "ankle": list(ankle), "contact": bool(contact), "lift": float(lift),
        "toe_angle": float(toe_angle), "swing_progress": float(swing_progress),
    }


def _paint(legs, side=None):
    if side not in (None, "left", "right"):
        raise ValueError("side must be None, 'left', or 'right'")
    canvas = Image.new("RGBA", (rig.SIZE * rig.SS, rig.SIZE * rig.SS))
    # Both trousers precede both rigid boots, preserving readable foot roles.
    for name, _sign, part in _SIDES:
        if side is not None and name != side:
            continue
        leg = legs[name]
        rig.segment(canvas, "thigh_" + part, leg["hip"], leg["knee"], 22, 7)
        rig.segment(canvas, "shin_" + part, leg["knee"], leg["ankle"], 18, 6)
    for name, _sign, part in _SIDES:
        if side is not None and name != side:
            continue
        leg = legs[name]
        rotation = -math.degrees(leg["toe_angle"] - math.pi / 2.0)
        rig.put(canvas, "boot_" + part, leg["boot"], *BOOT_SIZE, rotation)
    return canvas.resize((rig.SIZE, rig.SIZE), Image.Resampling.LANCZOS)


def render_lower(state="idle", frame=0, direction="s", side=None):
    """Return (RGBA image, anchors) for one sparse lower-body pose.

    side may select "left" or "right" for independently anchored leg sheets;
    anchors always describe both anatomical legs.

    Forward/backward travel retains the original stride and loop rate. Lateral
    poses are small correction steps; the runtime should turn the pelvis toward
    travel rather than using these short poses for prolonged sideways sliding.
    """
    state = state if state in ("walk", "sprint") else "idle"
    direction = direction if direction in rig.FACING else "s"
    frame = int(frame) % 8 if state != "idle" else 0
    moving, sprint = state != "idle", state == "sprint"
    speed, stance = (172.8, 0.375) if sprint else (102.4, 0.625)
    phase = (frame / 8.0 + (-1.0 if sprint else 1.0) / 16.0) % 1.0 if moving else 0.0
    travel_angle = math.radians(-rig.FACING[direction])
    travel = (-math.sin(travel_angle), math.cos(travel_angle))
    half_stroke = speed * 0.9 * stance / WORLD_SCALE / 2.0
    legs = {}
    supports = []
    for name, sign, _part in _SIDES:
        side_phase = (phase + (0.0 if name == "left" else 0.5)) % 1.0
        displacement, lift, contact = rig.foot_sample(side_phase, speed, stance) if moving else (0.0, 0.0, True)
        lateral = travel[0] * displacement * min(1.0, MAX_LATERAL_EXCURSION / half_stroke)
        # Opposite feet retain their anatomical lanes. A slight swing clearance
        # makes the short correction leg pass its partner without a crossover.
        lateral += sign * lift * (3.0 if sprint else 2.0)
        lateral = max(-MAX_LATERAL_EXCURSION, min(MAX_LATERAL_EXCURSION, lateral))
        boot = (128.0 + sign * 15.0 + lateral,
                136.0 + travel[1] * displacement
                + sign * lift * abs(travel[0]) * 10.0 * abs(displacement) / half_stroke)
        swing_progress = (side_phase - stance) / (1.0 - stance) if moving and not contact else 0.0
        legs[name] = _leg(_idle_hip(sign), boot, sign, 0.0, _toe_angle(sign), contact, lift, swing_progress)
        if contact:
            supports.append((abs(side_phase - stance / 2.0), name))
    metadata = {
        "state": state, "frame": frame, "direction": direction,
        "phase": phase, "pelvis_angle": 0.0,
        "support": min(supports)[1] if supports else "",
        "passing": moving and frame in PASSING_FRAMES,
        **legs,
    }
    return _paint(legs, side), metadata


def render_turn(sign=1, frame=0, side=None):
    """Return one of four staged poses for a +/-45 degree idle pivot.

    The leading foot moves first; the other remains planted. Then the first
    foot supports the second step. Frame 3 is exactly the rotated idle stance.
    Coordinates include the turn: render the plate at the *starting* heading
    until completion, then advance that heading and return to ordinary idle.
    """
    sign = 1 if sign >= 0 else -1
    frame = max(0, min(TURN_FRAME_COUNT - 1, int(frame)))
    target_angle = sign * math.pi / 4.0
    pelvis_angle = target_angle * (frame + 1) / TURN_FRAME_COUNT
    leading = "right" if sign > 0 else "left"
    trailing = "left" if leading == "right" else "right"
    legs = {}
    for name, side_sign, _part in _SIDES:
        amount = (0.5 if frame == 0 else 1.0) if name == leading else (0.0 if frame < 2 else (0.5 if frame == 2 else 1.0))
        contact = not ((name == leading and frame == 0) or (name == trailing and frame == 2))
        start = _idle_boot(side_sign)
        destination = _rotate(start, target_angle)
        boot = _mix(start, destination, amount)
        hip = _rotate(_idle_hip(side_sign), pelvis_angle)
        toe = _toe_angle(side_sign, target_angle * amount)
        legs[name] = _leg(hip, boot, side_sign, pelvis_angle, toe, contact,
                          0.0 if contact else 1.0, 0.0 if contact else 0.5)
    metadata = {
        "state": "turn", "frame": frame, "sign": sign,
        "phase": (frame + 1) / TURN_FRAME_COUNT,
        "pelvis_angle": pelvis_angle, "support": trailing if frame == 0 else leading,
        "passing": False, "turn_complete": frame == TURN_FRAME_COUNT - 1,
        **legs,
    }
    return _paint(legs, side), metadata
