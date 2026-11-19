#!/usr/bin/env python3
"""Turn the raw sound picks into game-ready assets.

Reads   tutorial/assets/audio/new_audio/<entity|viv>/<set>/   (never changed)
Writes  assets/audio/<entity|viv>/<set>/*.wav | *.ogg          (rebuilt on every run)
        assets/audio/SOUND_SETS.md                             (what was made, measured)

The folder name is the set name. A new folder is a new set: unless it is listed in
SETS below it is treated as plain one-shots at the default loudness of its owner.

    python3 tools/audio/prepare_sounds.py                 # everything
    python3 tools/audio/prepare_sounds.py --only claws    # sets whose name contains "claws"
    python3 tools/audio/prepare_sounds.py --debug         # also print what was detected

Needs ffmpeg on PATH. No Python packages. Run it from anywhere.
"""
from __future__ import annotations

import argparse
import array
import collections
import itertools
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
RAW_ROOT = PROJECT / "tutorial/assets/audio/new_audio"
OUT_ROOT = PROJECT / "assets/audio"
REPORT = OUT_ROOT / "SOUND_SETS.md"
MANIFEST = Path(__file__).with_name("prepared_sounds.json")
OWNERS = ("entity", "viv")
RAW_TYPES = {".mp3", ".wav", ".ogg", ".flac", ".m4a", ".aif", ".aiff"}

RATE = 48000
CEILING_DB = -1.0        # true peak ceiling of every file
MAX_LIMITING_DB = 6.0    # most a peak may be pushed down to reach a loudness target
RUMBLE_HZ = 25           # everything below is inaudible rumble that only eats headroom
BLOCK_S = 0.4            # the loudness standard listens in blocks this long

LOOP, SLICE, STROKE, BURST, SCREAM, PHRASE, WHOLE = "loop", "slice", "stroke", "burst", "scream", "phrase", "whole"
KIND_TEXT = {
    LOOP: "loop (OGG, crossfaded ends, loop on in the import settings)",
    SLICE: "sliced one-shots (one hit per file)",
    STROKE: "sliced one-shots (one scrape stroke per file)",
    BURST: "sliced one-shots (one sniff per file, cut at the pauses between them)",
    SCREAM: "scream (loudest second first, 1.6 s at most)",
    PHRASE: "idle talking (long takes split at pauses)",
    WHOLE: "one-shot, kept whole",
}

# set -> (kind, target integrated loudness in LUFS)
SETS = {
    "entity/mumble": (PHRASE, -24.0),
    "entity/breath_calm": (LOOP, -24.0),
    "entity/breath_hunt": (LOOP, -24.0),
    "entity/drag": (LOOP, -24.0),
    "entity/scream": (SCREAM, -12.0),
    "entity/inhale": (WHOLE, -16.0),
    "entity/foot_slam": (WHOLE, -16.0),
    "entity/catch_grab": (WHOLE, -16.0),
    "entity/claws_walk": (SLICE, -20.0),
    "entity/claws_run": (SLICE, -20.0),
    "entity/claws_scuttle": (SLICE, -20.0),
    "entity/pat_tap": (SLICE, -20.0),
    "entity/claw_scrape": (STROKE, -20.0),
    "entity/heard_voice": (WHOLE, -20.0),
    "entity/neck_click": (WHOLE, -20.0),
    "entity/lost": (WHOLE, -20.0),
    "entity/sniff": (BURST, -20.0),
    "entity/cloth_fall": (WHOLE, -20.0),
    "entity/sob_stops": (WHOLE, -20.0),
    "entity/exhale": (WHOLE, -20.0),
    "entity/knock": (WHOLE, -20.0),          # its knock on a door: kept whole, as loud as its taps
    "viv/hold_in": (WHOLE, -28.0),
    "viv/exhale": (WHOLE, -28.0),
    "viv/gasp": (WHOLE, -28.0),
    "viv/forced_gasp": (WHOLE, -24.0),
    "viv/panic": (LOOP, -24.0),
    "viv/calm": (LOOP, -32.0),
    "viv/nervous": (LOOP, -32.0),
}
DEFAULT = {"entity": (WHOLE, -20.0), "viv": (WHOLE, -28.0)}
# Sets built from another set's takes: slowed (lower and longer), then cut to length.
DERIVED = {
    "entity/stand_down": {"source": "entity/exhale", "speed": 0.85, "min_s": 2.5, "max_s": 3.0, "lufs": -20.0,
                          "unlike": "entity/lost"},      # the report shows how the two differ
}

SLICE_MIN_S, SLICE_MAX_S = 0.15, 0.8
SAME_HIT_S = 0.18        # clicks closer than this belong to one footfall
STROKE_MIN_S = 0.35
SCREAM_BODY_S, SCREAM_MAX_S, SCREAM_FADE_S = 1.0, 1.6, 0.3
PHRASE_SPLIT_OVER_S = 6.0
PHRASE_MIN_S = 0.8

DEBUG = False
BACKGROUND = {"level": -120.0}   # level between the hits of the file being sliced, in dBFS


# ------------------------------------------------------------------ ffmpeg ---

def ffmpeg(args: list, data: bytes | None = None) -> subprocess.CompletedProcess:
    result = subprocess.run(["ffmpeg", "-hide_banner", "-nostdin", *map(str, args)], input=data, capture_output=True)
    if result.returncode != 0:
        sys.exit("ffmpeg failed: %s\n%s" % (" ".join(map(str, args)), result.stderr.decode(errors="replace")[-600:]))
    return result


def as_samples(raw: bytes) -> array.array:
    samples = array.array("f")
    samples.frombytes(raw[: len(raw) // 4 * 4])
    return samples


def decode(path: Path, speed: float = 1.0, clean: bool = True) -> array.array:
    """Any audio file -> mono 48 kHz floats, with the rumble under RUMBLE_HZ filtered out.
    speed < 1 plays it slower and lower, like tape."""
    filters = ["highpass=f=%d:p=2" % RUMBLE_HZ] * 2 if clean else []
    if speed != 1.0:
        filters += ["aresample=%d" % RATE, "asetrate=%d" % round(RATE * speed)]
    args = ["-v", "error", "-i", path, "-map", "0:a:0", "-ac", "1"]
    if filters:
        args += ["-af", ",".join(filters)]
    return as_samples(ffmpeg(args + ["-ar", RATE, "-f", "f32le", "-"]).stdout)


def encode(samples: array.array, path: Path) -> None:
    codec = ["-c:a", "libvorbis", "-q:a", "6"] if path.suffix == ".ogg" else ["-c:a", "pcm_s16le"]
    ffmpeg(["-v", "error", "-y", "-f", "f32le", "-ar", RATE, "-ac", "1", "-i", "-", *codec,
            "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", path], samples.tobytes())


def measure(samples: array.array, loops: bool = False) -> tuple[float, float]:
    """Integrated loudness (LUFS, ITU-R BS.1770) and true peak (dBTP). A one-shot is measured
    as it is heard: played once, with silence around it. A loop is measured going round."""
    if len(samples) == 0:
        return -99.0, -99.0
    if loops:
        samples = samples * max(1, math.ceil(3.0 * RATE / len(samples)))
    else:
        silence = array.array("f", bytes(4 * frames(BLOCK_S)))
        samples = silence + samples + silence
    log = ffmpeg(["-f", "f32le", "-ar", RATE, "-ac", "1", "-i", "-", "-af", "ebur128=peak=true:framelog=verbose",
                  "-f", "null", "-"], samples.tobytes()).stderr.decode(errors="replace")
    summary = log[log.rfind("Summary:"):]
    loud = re.search(r"\bI:\s+(-?[\d.]+) LUFS", summary)
    peak = re.search(r"\bPeak:\s+(-?[\d.]+) dBFS", summary)
    return (float(loud.group(1)) if loud else -99.0), (float(peak.group(1)) if peak else -99.0)


# ---------------------------------------------------------------- analysis ---

def frames(seconds: float) -> int:
    return int(round(seconds * RATE))


def envelope(x: array.array, win_ms: float, hop_ms: float) -> list[float]:
    """RMS level in dBFS of windows win_ms long, one every hop_ms."""
    win, hop = max(1, frames(win_ms / 1000)), max(1, frames(hop_ms / 1000))
    total = [0.0]
    total.extend(itertools.accumulate(v * v for v in x))
    return [10.0 * math.log10((total[i + win] - total[i]) / win + 1e-12) for i in range(0, max(1, len(x) - win + 1), hop)]


def percentile(values: list[float], percent: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * percent / 100.0))]


def peak_db(x: array.array) -> float:
    return 20.0 * math.log10(max(max(x, default=0.0), -min(x, default=0.0), 1e-9))


def sound_bounds(x: array.array, tail_db: float = -55.0) -> tuple[int, int]:
    """First and last sample that is not silence. The start is where the sound comes within
    40 dB of its loudest moment; if a hard attack follows within 60 ms, the start moves up to
    it, so a slam lands on its animation frame. The end keeps the decay down to tail_db."""
    env = envelope(x, 2.0, 1.0)
    top = max(env)
    start_level, end_level = max(top - 40.0, -70.0), max(top + tail_db, -75.0)
    first = next((i for i, v in enumerate(env) if v > start_level), 0)
    attack = next((i for i, v in enumerate(env) if v > top - 20.0), first)
    if 5 < attack - first <= 60:
        first = attack - 5
    last = len(env) - 1 - next((i for i, v in enumerate(reversed(env)) if v > end_level), 0)
    return frames(first / 1000), min(len(x), frames((last + 2) / 1000))


def local_minima(env: list[float], spacing: int) -> list[int]:
    found = []
    for i in range(1, len(env) - 1):
        lo, hi = max(0, i - spacing), min(len(env), i + spacing + 1)
        if env[i] == min(env[lo:hi]) and (not found or i - found[-1] >= spacing):
            found.append(i)
    return found


# ----------------------------------------------------------------- editing ---

def faded(x: array.array, fade_in_s: float, fade_out_s: float) -> array.array:
    """Copy with raised-cosine fades, so no cut ever starts or ends on a click."""
    y = array.array("f", x)
    n_in, n_out = min(frames(fade_in_s), len(y) // 2), min(frames(fade_out_s), len(y) // 2)
    for i in range(n_in):
        y[i] *= 0.5 - 0.5 * math.cos(math.pi * i / n_in)
    for i in range(n_out):
        y[len(y) - 1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / n_out)
    return y


def limit(x: array.array, ceiling_db: float) -> tuple[array.array, float]:
    """Look-ahead peak limiter (3 ms look-ahead, 100 ms release). Returns the limited copy
    and the deepest gain reduction in dB."""
    ceiling = 10.0 ** (ceiling_db / 20.0)
    need = [ceiling / abs(v) if abs(v) > ceiling else 1.0 for v in x]
    deepest = min(need, default=1.0)
    if deepest >= 1.0:
        return x, 0.0
    ahead, n = frames(0.003), len(x)
    window: collections.deque = collections.deque()
    lowest = [1.0] * n                       # the smallest gain needed in the next 3 ms
    for i in range(n + ahead):
        if i < n:
            while window and need[window[-1]] >= need[i]:
                window.pop()
            window.append(i)
        start = i - ahead
        if start >= 0:
            while window[0] < start:
                window.popleft()
            lowest[start] = need[window[0]]
    recover, gain = 1.0 - math.exp(-1.0 / (0.100 * RATE)), 1.0
    for i in range(n):                       # hold, then let go slowly
        gain = min(lowest[i], gain + (1.0 - gain) * recover)
        lowest[i] = gain
    y, running = array.array("f", x), 0.0
    for i in range(n):                       # ramp into each reduction over the look-ahead
        running += lowest[i] - (lowest[i - ahead] if i >= ahead else 1.0)
        y[i] = x[i] * min(need[i], running / ahead + 1.0)
    return y, -20.0 * math.log10(deepest)


def normalise(x: array.array, target: float, path: Path) -> dict:
    """Bring x to the target loudness under the true-peak ceiling and write it to path. Peaks
    are limited by MAX_LIMITING_DB at most: a sound that is one sharp click stays under target."""
    loops = path.suffix == ".ogg"
    start_loud, _ = measure(x, loops)
    if start_loud < -70.0:
        encode(x, path)
        return {"lufs": start_loud, "peak": peak_db(x), "limited": 0.0, "gain": 0.0, "silent": True}
    margin, source_peak = 0.3, peak_db(x)
    gain = target - start_loud
    for _ in range(8):
        most = CEILING_DB - margin - source_peak + MAX_LIMITING_DB
        gain = min(gain, most)
        y = array.array("f", (v * 10.0 ** (gain / 20.0) for v in x))
        y, limited = limit(y, CEILING_DB - margin)
        encode(y, path)
        heard = decode(path, clean=False) if loops else y
        loud, peak = measure(heard, loops)
        if peak > CEILING_DB + 0.005:
            margin += peak - CEILING_DB + 0.1
        elif abs(target - loud) <= 0.15 or (target > loud and gain >= most - 0.01):
            break
        else:
            gain += target - loud
    return {"lufs": loud, "peak": peak, "limited": limited, "gain": gain, "silent": False}


# ------------------------------------------------------------------- kinds ---

def cut_whole(x: array.array, notes: list[str]) -> list[array.array]:
    start, end = sound_bounds(x)
    start = max(0, start - frames(0.002))
    env = envelope(x, 5.0, 5.0)
    top = max(env)
    if start == 0 and env[0] > top - 20.0:
        notes.append("!source starts abruptly (no lead-in)")
    if end >= len(x) - frames(0.02) and env[-1] > top - 25.0:
        notes.append("!source ends abruptly (faded over 30 ms)")
    return [faded(x[start:end], 0.002, 0.03)]


def faintest_kept(strength: list[float]) -> float:
    """The level of the faintest hit that still belongs to its take. Everything under the
    first 6 dB drop in strength is a ghost note, once three hits (and a quarter of them) are
    above that drop. Raising ghost notes to full level would raise the take's hiss with them."""
    ordered = sorted(strength, reverse=True)
    for k in range(max(3, math.ceil(len(ordered) / 4)), len(ordered)):
        if ordered[k - 1] - ordered[k] >= 6.0:
            return ordered[k - 1]
    return min(ordered, default=0.0)


def find_hits(x: array.array, notes: list[str]) -> list[tuple[int, int, float]]:
    """(start, end, fade_out_s) of every hit, in samples. A hit starts on a click: the level
    jumps 12 dB or more over what it was 10-30 ms earlier, and stands 18 dB clear of what came
    just before (so a tick in the tail of a hit is not a hit). Clicks within SAME_HIT_S of the
    first belong to that hit. Hits much fainter than the rest of the take are left out."""
    fast, slow = envelope(x, 3.0, 1.0), envelope(x, 10.0, 1.0)     # one value per ms
    floor, top = percentile(fast, 20), max(fast)
    gate = max(floor + 20.0, top - 32.0)
    clicks: list[int] = []
    for t in range(80, len(fast)):
        if fast[t] < gate or (clicks and t - clicks[-1] <= 15) or fast[t] - max(fast[t - 30:t - 10]) < 12.0:
            continue
        in_a_hit = bool(clicks) and t - clicks[-1] < SAME_HIT_S * 1000
        if in_a_hit or max(fast[t:t + 4]) - percentile(fast[t - 80:t - 20], 50) >= 18.0:
            clicks.append(t)
    groups: list[list[int]] = []
    for t in clicks:
        if groups and t - groups[-1][0] < SAME_HIT_S * 1000:
            groups[-1].append(t)
        else:
            groups.append([t])
    strength = [max(fast[group[0]:group[-1] + 30]) for group in groups]
    faintest = faintest_kept(strength)
    faint = sum(1 for level in strength if level < faintest)
    groups = [group for group, level in zip(groups, strength) if level >= faintest]
    hits, doubles, cut_tails, between = [], 0, 0, list(fast)
    for index, group in enumerate(groups):
        start = group[0]
        while start > max(0, group[0] - 10) and fast[start - 1] > floor + 6.0 and fast[start - 1] < fast[start]:
            start -= 1                                    # back to the foot of a soft attack
        click = next(t for t in range(start, group[0] + 30) if fast[t] >= max(fast[group[0]:group[0] + 30]) - 12.0)
        start = max(0, start - 2, click - 6)              # the click lands within 6 ms of the cut
        limit_ms = min(start + SLICE_MAX_S * 1000, len(slow) - 1)
        if index + 1 < len(groups):
            limit_ms = min(limit_ms, groups[index + 1][0] - 14)
        strongest = max(fast[start:int(min(limit_ms, group[-1] + 30)) + 1])
        quiet = max(floor + 8.0, strongest - 40.0)
        end = next((t for t in range(group[-1] + 20, int(limit_ms)) if slow[t] < quiet), None)
        natural = end is not None
        end = min(end + 10, limit_ms) if natural else limit_ms
        if end - start < SLICE_MIN_S * 1000:          # a very short tap keeps its quiet tail
            end = min(max(end, start + SLICE_MIN_S * 1000), limit_ms)
        left = slow[min(int(end), len(slow) - 1)] - strongest
        if index + 1 == len(groups) and not natural and end >= len(slow) - 2 and left > -20.0:
            notes.append("!last hit is cut off by the end of the source (left out)")
            continue
        if not natural and left > -18.0:
            cut_tails += 1
        doubles += bursts(slow[start:int(end)], 9.0, 6.0, 40) > 1
        length = (end - start) / 1000
        between[start:int(end)] = [None] * (int(end) - start)
        hits.append((frames(start / 1000), frames(end / 1000), 0.015 if natural else min(0.06, 0.3 * length)))
        if DEBUG:
            print("    hit %2d  %6.3f-%6.3f s  %.3f s  peak %5.1f dB  clicks %d  %s" % (
                len(hits), start / 1000, end / 1000, length, strongest, len(group),
                "decays out" if natural else "tail cut at %.0f dB" % left))
    BACKGROUND["level"] = percentile([v for v in between if v is not None] or [-120.0], 50)
    if faint:
        notes.append("!%d faint hit%s left out (6 dB or more under the rest of the take)" % (faint, "" if faint == 1 else "s"))
    if doubles:
        notes.append("%d of %d hits land in two parts (claws touching down under %.2f s apart), kept as one hit" % (doubles, len(hits), SAME_HIT_S))
    if cut_tails:
        notes.append("!%d hits run into the next one before they have died away (tail faded early)" % cut_tails)
    return hits


def find_strokes(x: array.array, notes: list[str]) -> list[tuple[int, int, float, float]]:
    """(start, end, fade_in_s, fade_out_s) of scrape strokes. A drag has no clicks to cut on, so
    each stretch of scraping is cut at its quietest moments into pieces under SLICE_MAX_S."""
    hop = 0.005
    env = envelope(x, 20.0, hop * 1000)
    body = percentile(env, 95)
    gate = max(body - 15.0, percentile(env, 20) + 8.0)
    stretches, begin, gap = [], None, 0
    for i, level in enumerate(env + [-200.0] * 40):
        if level > gate:
            begin, gap = (i if begin is None else begin), 0
        elif begin is not None:
            gap += 1
            if gap * hop >= 0.1:
                if (i - gap + 1 - begin) * hop >= STROKE_MIN_S:
                    stretches.append((begin, i - gap + 1))
                begin = None
    strokes = []
    low, high = round(STROKE_MIN_S / hop), round(SLICE_MAX_S / hop)
    for begin, end in stretches:
        size = end - begin
        cuts = [0, size]
        if size > high:
            middle = percentile(env[begin:end], 50)
            best = {0: (0.0, None)}                        # cut position -> (cost so far, previous cut)
            for i in range(1, size + 1):
                options = [(best[j][0] + (0.0 if i == size else env[begin + i] - middle + 8.0), j)
                           for j in range(max(0, i - high), i - low + 1) if j in best]
                if i == size and not options:               # allow a short last piece
                    options = [(best[j][0] + 6.0, j) for j in range(max(0, i - high), i) if j in best]
                if options:
                    best[i] = min(options)
            cuts, at = [], size
            while at is not None:
                cuts.append(at)
                at = best[at][1]
            cuts.reverse()
        for a, b in zip(cuts, cuts[1:]):
            first, last = a == 0, b == size
            start = frames((begin + a) * hop) - (frames(0.002) if first else 0)
            strokes.append((max(0, start), min(len(x), frames((begin + b) * hop + (0.03 if last else 0.0))),
                            0.003 if first else 0.015, 0.03 if last else 0.07))
            if DEBUG:
                print("    stroke %2d  %6.3f-%6.3f s  %.3f s  %s" % (len(strokes), (begin + a) * hop, (begin + b) * hop,
                      (b - a) * hop, "whole scrape" if first and last else "piece of a %.1f s scrape" % (size * hop)))
    outside = [v for i, v in enumerate(env) if not any(begin <= i < end for begin, end in stretches)]
    BACKGROUND["level"] = percentile(outside or [-120.0], 50)
    longest = max(((end - begin) * hop for begin, end in stretches), default=0.0)
    if longest > SLICE_MAX_S:
        notes.append("!the source holds %d continuous drags (up to %.1f s), not separate scrapes: each is cut at its quietest moments into strokes under %.1f s, with soft fades" % (len(stretches), longest, SLICE_MAX_S))
    return strokes


def cut_bursts(x: array.array, notes: list[str]) -> list[array.array]:
    """One file per sniff. Sniffs have no click to cut on: the take is cut at the pauses
    between them (every dip 12 dB or more under the sound on both sides of it)."""
    hop = 0.005
    env = envelope(x, 20.0, hop * 1000)
    start, end = sound_bounds(x, -40.0)
    first, last = int(start / RATE / hop), min(len(env) - 1, int(end / RATE / hop))
    wide = round(0.6 / hop)
    edges = [first] + [i for i in local_minima(env, round(0.1 / hop)) if first < i < last
                       and min(max(env[max(0, i - wide):i + 1]), max(env[i:i + wide + 1])) - env[i] >= 12.0] + [last]
    changed = True
    while changed and len(edges) > 2:                       # a sliver joins its neighbour across the shallower dip
        changed = False
        for i in range(len(edges) - 1):
            if (edges[i + 1] - edges[i]) * hop < SLICE_MIN_S:
                del edges[i + 1 if i + 2 < len(edges) and (i == 0 or env[edges[i + 1]] > env[edges[i]]) else i]
                changed = True
                break
    pieces = list(zip(edges, edges[1:]))
    strength = [max(env[a:b + 1]) for a, b in pieces]
    faintest = faintest_kept(strength)
    clips = []
    for (a, b), level in zip(pieces, strength):
        if level < faintest:
            continue
        piece = x[frames(a * hop):frames(b * hop)]
        p_start, p_end = sound_bounds(piece, -35.0)
        clips.append(faded(piece[max(0, p_start - frames(0.002)):p_end], 0.004, 0.025))
        if DEBUG:
            print("    sniff %2d  %6.3f-%6.3f s  %.3f s  peak %5.1f dB" % (len(clips), a * hop, b * hop, len(clips[-1]) / RATE, level))
    if len(pieces) > len(clips):
        faint = len(pieces) - len(clips)
        notes.append("!%d faint sniff%s left out (6 dB or more under the rest of the take)" % (faint, "" if faint == 1 else "s"))
    BACKGROUND["level"] = -120.0
    return clips


def cut_scream(x: array.array, notes: list[str]) -> list[array.array]:
    """Starts on the attack of the scream, chosen so the second that follows is the loudest
    second there is; SCREAM_MAX_S long at most, ending in a fade."""
    env = envelope(x, 10.0, 1.0)
    span = int(SCREAM_BODY_S * 1000)
    total = [0.0]
    total.extend(itertools.accumulate(10.0 ** (v / 10.0) for v in env))
    energy = [total[min(i + span, len(env))] - total[i] for i in range(len(env))]
    top = max(env)
    attacks = [i for i, level in enumerate(env) if level <= top - 18.0]
    start = max(attacks, key=lambda i: energy[i]) if attacks else 0
    _, sound_end = sound_bounds(x)
    end = min(frames(start / 1000 + SCREAM_MAX_S), sound_end)
    cut = end < sound_end
    notes.append("starts on the attack, %.2f s into the source%s" % (
        start / 1000, "; ends in a %.1f s fade" % SCREAM_FADE_S if cut else ""))
    short = 10.0 * math.log10(max(energy) / energy[start])
    if short > 3.0:
        notes.append("!its first second is %.1f dB under the loudest second of the take (slow build-up)" % short)
    return [faded(x[frames(start / 1000):end], 0.005, SCREAM_FADE_S if cut else 0.03)]


def cut_phrases(x: array.array, notes: list[str]) -> list[array.array]:
    """Takes longer than PHRASE_SPLIT_OVER_S are split where the voice pauses."""
    start, end = sound_bounds(x)
    if (end - start) / RATE <= PHRASE_SPLIT_OVER_S:
        return [faded(x[max(0, start - frames(0.002)):end], 0.003, 0.04)]
    hop = 0.005
    env = envelope(x, 30.0, hop * 1000)
    voice = percentile(env[int(start / RATE / hop):int(end / RATE / hop)], 95)
    first, last = int(start / RATE / hop), min(len(env) - 1, int(end / RATE / hop))

    def pauses(depth: float, shortest: float) -> list[tuple[float, int]]:
        """(how deep, where) for every dip below voice - depth lasting at least `shortest`."""
        found, begin = [], None
        for i in range(first, last + 1):
            if env[i] < voice - depth and i < last:
                begin = i if begin is None else begin
            elif begin is not None:
                if (i - begin) * hop >= shortest:
                    lowest = min(range(begin, i), key=lambda k: env[k])
                    found.append((voice - env[lowest], lowest))
                begin = None
        return found

    pieces = sorted([first, last] + [at for _, at in pauses(14.0, 0.2)])
    dips = sorted(pauses(12.0, 0.06), reverse=True)
    while True:     # a piece that is still too long is cut at its deepest short dip, if it has one
        a, b = max(zip(pieces, pieces[1:]), key=lambda piece: piece[1] - piece[0])
        inside = [at for _, at in dips if a + PHRASE_MIN_S / hop < at < b - PHRASE_MIN_S / hop]
        if (b - a) * hop <= PHRASE_SPLIT_OVER_S or not inside:
            break
        pieces = sorted(pieces + [inside[0]])
    changed = True
    while changed and len(pieces) > 2:                      # no fragment shorter than PHRASE_MIN_S
        changed = False
        for i in range(len(pieces) - 1):
            if (pieces[i + 1] - pieces[i]) * hop < PHRASE_MIN_S:
                del pieces[i + 1 if i + 2 < len(pieces) and (i == 0 or env[pieces[i + 1]] > env[pieces[i]]) else i]
                changed = True
                break
    phrases = []
    for a, b in zip(pieces, pieces[1:]):
        inner_start, inner_end = a != first, b != last
        piece = x[frames(a * hop):frames(b * hop)]
        if inner_start or inner_end:                        # drop the silence left around a pause
            p_start, p_end = sound_bounds(piece, -45.0)
            piece = piece[max(0, p_start - frames(0.002)):p_end]
        phrases.append(faded(piece, 0.004 if inner_start else 0.003, 0.06 if inner_end else 0.04))
        if DEBUG:
            print("    phrase %d  %6.2f-%6.2f s  %.2f s" % (len(phrases), a * hop, b * hop, len(piece) / RATE))
    longest = max(len(p) for p in phrases) / RATE
    if len(phrases) == 1:
        notes.append("!%.1f s without a pause to cut at: kept as one phrase" % longest)
    elif longest > PHRASE_SPLIT_OVER_S:
        notes.append("!longest phrase is %.1f s (no pause inside it)" % longest)
    return phrases


def cut_loop(x: array.array, notes: list[str]) -> list[array.array]:
    """A sound with pauses in it (breaths, strokes) loops from one pause to another over a short
    crossfade: the pair of pauses that is far apart, keeps the level steady across the seam and
    leaves no hole there. A sound without pauses loops between two moments that sound alike,
    over a long crossfade."""
    hop = 0.005
    env = envelope(x, 40.0, hop * 1000)
    start, end = sound_bounds(x, -40.0)
    first, last = int(start / RATE / hop), min(len(env) - 1, int(end / RATE / hop))
    wide, near = round(1.5 / hop), round(0.25 / hop)
    power = [0.0]
    power.extend(itertools.accumulate(10.0 ** (v / 10.0) for v in env))

    def average(i: int, j: int) -> float:                   # mean level of env[i:j] in dB
        i, j = max(0, min(i, len(env))), max(0, min(j, len(env)))
        return 10.0 * math.log10((power[j] - power[i]) / (j - i) + 1e-12) if j > i else -90.0

    def level(i: int) -> float:
        return env[i] if 0 <= i < len(env) else -90.0

    dips = [i for i in local_minima(env, round(0.15 / hop)) if first <= i <= last]
    # A pause is a dip 12 dB or more under the sound on both sides of it; so are the two ends.
    pauses = [i for i in dips if min(max(env[max(0, i - wide):i + 1]), max(env[i:i + wide + 1])) - env[i] >= 12.0]
    edge = round(0.1 / hop)
    pauses = sorted(set(pauses + [max(0, first - edge), min(len(env) - 1, last + edge)]))
    shortest = max(2.5, 0.4 * (last - first) * hop)
    best = None
    if len(pauses) >= 3:
        for a in pauses:
            for b in pauses:
                if (b - a) * hop >= shortest:
                    step = average(a, a + wide) - average(b - wide, b)      # heard across the seam
                    usual, half = average(a, b), round(0.5 / hop)
                    hole = max(0.0, usual - average(a, a + half) - 10.0) + max(0.0, usual - average(b - half, b) - 10.0)
                    score = 2.0 * max(0.0, abs(step) - 2.0) + hole - (b - a) * hop
                    if best is None or score < best[0]:
                        best = (score, a, b, step)
        blend, where = 0.05, "inside a pause"
    else:
        for a in dips:
            for b in dips:
                if (b - a) * hop >= shortest:
                    unlike = sum(abs(level(a + k) - level(b + k)) for k in range(-near, near + 1)) / (2 * near + 1)
                    step = average(a, a + wide) - average(b - wide, b)
                    score = unlike + abs(step) - 1.5 * (b - a) * hop
                    if best is None or score < best[0]:
                        best = (score, a, b, step)
        blend, where = 0.5, "over the sound"
    if best is None:
        notes.append("!too short to loop: kept whole")
        return [faded(x[start:end], 0.01, 0.01)]
    _, a, b, step = best
    a_s, b_s = frames(a * hop), frames(b * hop)
    n = max(0, min(frames(min(blend, (b - a) * hop / 8.0)), len(x) - b_s))
    loop = array.array("f", x[a_s:b_s])
    for i in range(n):                                      # the end of the loop already leads into x[b:]
        angle = 0.5 * math.pi * i / n
        loop[i] = x[a_s + i] * math.sin(angle) + x[b_s + i] * math.cos(angle)
    notes.append("loops %.2f-%.2f s of the source, %.0f ms crossfade %s" % (a * hop, b * hop, n / RATE * 1000, where))
    if abs(step) > 3.0:
        notes.append("!the level steps %s by %.1f dB where the loop restarts" % ("up" if step > 0 else "down", abs(step)))
    return [loop]


def cut_derived(path: Path, rule: dict, notes: list[str]) -> list[array.array]:
    x = decode(path, rule["speed"])
    start, end = sound_bounds(x)
    start = max(0, start - frames(0.002))
    length = (end - start) / RATE
    notes.append("%s played %d%% slower" % (path.name, round((1.0 - rule["speed"]) * 100)))
    if length > rule["max_s"]:
        end = start + frames(rule["max_s"])
        notes.append("cut from %.1f s to %.1f s with a 0.8 s fade" % (length, rule["max_s"]))
        return [faded(x[start:end], 0.003, 0.8)]
    if length < rule["min_s"]:
        notes.append("!only %.1f s long (wanted %.1f s or more)" % (length, rule["min_s"]))
    return [faded(x[start:end], 0.003, 0.05)]


# -------------------------------------------------------------------- sets ---

def source_notes(x: array.array) -> list[str]:
    notes = []
    clipped = sum(1 for v in x if abs(v) >= 0.999)
    if clipped > 4:
        notes.append("!source clips (%d samples at full scale)" % clipped)
    if peak_db(x) < -50.0:
        notes.append("!source is silent")
    return notes


def lead_ms(x: array.array) -> float:
    """Milliseconds before the sound comes within 40 dB of its loudest moment."""
    env = envelope(x, 2.0, 1.0)
    top = max(env)
    return float(next((i for i, v in enumerate(env) if v > max(top - 40.0, -70.0)), 0))


def centre_hz(x: array.array) -> float:
    """Where the energy of a sound sits, as one frequency: a few hundred Hz for a voice,
    thousands for breath and hiss. (From how fast the wave moves compared with how big it is.)"""
    moving = sum((b - a) ** 2 for a, b in zip(x, x[1:]))
    size = sum(v * v for v in x) or 1e-12
    return RATE / math.pi * math.asin(min(1.0, 0.5 * math.sqrt(moving / size)))


def bursts(env: list[float], within_db: float, dip_db: float, apart: int) -> int:
    """Separate bursts of sound in an envelope: each within `within_db` of the loudest, with a
    dip of `dip_db` or more before it, and `apart` envelope steps or more after the last one."""
    top, count, last_loud, dipped = max(env, default=0.0), 0, None, True
    for i, level in enumerate(env):
        if level > top - within_db:
            if dipped and (last_loud is None or i - last_loud >= apart):
                count, dipped = count + 1, False
            last_loud = i
        elif last_loud is not None and level < env[last_loud] - dip_db:
            dipped = True
    return count


def hits_inside(x: array.array) -> int:
    """Independent check of a finished clip: bursts within 12 dB of the loudest, split by a dip
    of 10 dB or more and SAME_HIT_S or more apart."""
    return bursts(envelope(x, 20.0, 5.0), 12.0, 10.0, round(SAME_HIT_S / 0.005))


def build(set_id: str, kind: str, target: float, sources: list[Path], rule: dict | None, staging: Path) -> list[dict]:
    """Cuts, levels and writes every clip of a set. Notes starting with "!" are worth a listen."""
    owner, name = set_id.split("/")
    rows = []
    for source in sources:
        notes: list[str] = []
        if rule is not None:
            clips, stem = cut_derived(source, rule, notes), source.stem.replace(rule["source"].split("/")[1], name)
        else:
            x = decode(source)
            notes += source_notes(decode(source, clean=False))
            stem = source.stem
            if DEBUG:
                print("  %s (%.2f s)" % (source.name, len(x) / RATE))
            if kind == SLICE:
                clips = [faded(x[a:b], 0.001, fade_out) for a, b, fade_out in find_hits(x, notes)]
            elif kind == STROKE:
                clips = [faded(x[a:b], fade_in, fade_out) for a, b, fade_in, fade_out in find_strokes(x, notes)]
            elif kind == BURST:
                clips = cut_bursts(x, notes)
            elif kind == SCREAM:
                clips = cut_scream(x, notes)
            elif kind == PHRASE:
                clips = cut_phrases(x, notes)
            elif kind == LOOP:
                clips = cut_loop(x, notes)
            else:
                clips = cut_whole(x, notes)
        numbered = kind in (SLICE, STROKE, BURST) or len(clips) > 1
        for index, clip in enumerate(clips, 1):
            for _ in range(3):                             # every one-shot starts within 10 ms
                if kind == LOOP or lead_ms(clip) < 10.0:
                    break
                clip = faded(clip[frames((lead_ms(clip) - 2.0) / 1000):], 0.003, 0.0)
            extension = ".ogg" if kind == LOOP else ".wav"
            file_name = "%s_%02d%s" % (stem, index, extension) if numbered else stem + extension
            path = staging / owner / name / file_name
            path.parent.mkdir(parents=True, exist_ok=True)
            result = normalise(clip, target, path)
            if DEBUG:
                print("    -> %-34s %5.2f s  %+5.1f dB gain  %5.1f LUFS  peak %5.1f  limited %.1f dB" % (
                    file_name, len(clip) / RATE, result["gain"], result["lufs"], result["peak"], result["limited"]))
            found: list[tuple[str, float, str]] = []        # (what, how much, text)
            length, lead = len(clip) / RATE, lead_ms(clip)
            if result["silent"]:
                found.append(("silent", 0.0, "SILENT"))
            elif abs(result["lufs"] - target) > 0.5:
                off = result["lufs"] - target
                found.append(("off", abs(off), "%.1f LU %s target (peaks already limited by %.0f dB)" % (abs(off), "under" if off < 0 else "over", result["limited"])))
            elif result["limited"] >= 3.0:
                found.append(("limited", result["limited"], "peaks limited by %.1f dB" % result["limited"]))
            if kind in (SLICE, STROKE) and BACKGROUND["level"] + result["gain"] > -36.0:
                raised = BACKGROUND["level"] + result["gain"]
                found.append(("background", raised, "quiet source: its background comes up to %.0f dB" % raised))
            elif kind not in (SLICE, STROKE) and result["gain"] > 30.0:
                found.append(("quiet", result["gain"], "very quiet source (raised %.0f dB)" % result["gain"]))
            if kind != LOOP and lead >= 10.0:
                found.append(("lead", lead, "%.0f ms before the sound starts" % lead))
            if kind in (SLICE, BURST) and hits_inside(clip) > 1:
                found.append(("two", 0.0, "may hold two hits"))
            if kind in (SLICE, STROKE, BURST) and not SLICE_MIN_S - 0.005 <= length <= SLICE_MAX_S + 0.035:
                found.append(("length", length, "length outside %.2f-%.1f s" % (SLICE_MIN_S, SLICE_MAX_S)))
            if kind == WHOLE and rule is None and hits_inside(clip) >= 8:
                found.append(("many", hits_inside(clip), "%d separate sounds in a row, kept whole as one file" % hits_inside(clip)))
            rows.append({"set": set_id, "file": file_name, "seconds": length, "lufs": result["lufs"], "pitch": centre_hz(clip),
                         "peak": result["peak"], "loop": kind == LOOP, "source": source.name, "found": found,
                         "source_notes": notes if index == 1 else [], "of": len(clips)})
    return rows


def find_sets() -> dict[str, list[Path]]:
    found = {}
    for owner in OWNERS:
        for folder in sorted(p for p in (RAW_ROOT / owner).glob("*") if p.is_dir()):
            files = sorted(f for f in folder.iterdir() if f.suffix.lower() in RAW_TYPES)
            if files:
                found["%s/%s" % (owner, folder.name)] = files
    return found


def read_me() -> dict[str, str]:
    """"When it plays" per set, from the README next to the raw files."""
    plays, owner = {}, ""
    readme = RAW_ROOT / "README.md"
    for line in readme.read_text().splitlines() if readme.exists() else []:
        heading = re.match(r"##\s+(\w+)/", line)
        row = re.match(r"\|\s*`(\w+)`\s*\|\s*(.+?)\s*\|\s*$", line)
        if heading:
            owner = heading.group(1)
        elif row and owner:
            plays["%s/%s" % (owner, row.group(1))] = row.group(2)
    return plays


def publish(staging: Path, rows: list[dict], partial: bool) -> tuple[int, int]:
    """Copy changed files into the project and remove outputs this script made earlier but no
    longer makes. Files it never made are left alone."""
    written = removed = 0
    made = sorted("%s/%s" % (row["set"], row["file"]) for row in rows)
    for relative in made:
        new, old = staging / relative, OUT_ROOT / relative
        old.parent.mkdir(parents=True, exist_ok=True)
        if not old.exists() or old.read_bytes() != new.read_bytes():
            shutil.copyfile(new, old)
            written += 1
        if old.suffix == ".ogg":
            set_loop_import(old)
    if partial:
        return written, removed
    before = json.loads(MANIFEST.read_text())["files"] if MANIFEST.exists() else []
    for relative in before:
        if relative not in made:
            for stale in (OUT_ROOT / relative, OUT_ROOT / (relative + ".import")):
                if stale.exists():
                    stale.unlink()
                    removed += 1
    MANIFEST.write_text(json.dumps({"files": made}, indent=1) + "\n")
    return written, removed


def set_loop_import(ogg: Path) -> None:
    """Loop enabled in Godot's import settings. Godot fills in the rest (uid, paths) on import."""
    settings = ogg.with_name(ogg.name + ".import")
    if not settings.exists():
        settings.write_text('[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n'
                            "[params]\n\nloop=true\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4\n")
    elif "loop=false" in settings.read_text():
        settings.write_text(settings.read_text().replace("loop=false", "loop=true"))


WORTH = {   # several files of one take with the same remark are reported once
    "off": "%d of %d files are under the loudness target, by up to %.1f LU (sharp clicks: their peaks are already limited)",
    "limited": "%d of %d files had their peaks limited by up to %.1f dB",
    "background": "%d of %d files: quiet source, so its background comes up with it (to %.0f dB at worst)",
}


def worth_a_listen(by_set: dict[str, list[dict]], empty: list[str]) -> list[str]:
    lines = []
    for set_id, rows in by_set.items():
        for source in dict.fromkeys(row["source"] for row in rows):
            takes = [row for row in rows if row["source"] == source]
            for note in takes[0]["source_notes"]:
                if note.startswith("!"):
                    lines.append("`%s` (from `%s`): %s" % (set_id, source, note[1:]))
            for what in dict.fromkeys(what for row in takes for what, _, _ in row["found"]):
                hits = [(row, amount, text) for row in takes for key, amount, text in row["found"] if key == what]
                worst = max(amount for _, amount, _ in hits)
                if len(hits) == 1 or what not in WORTH:
                    lines += ["`%s/%s`: %s" % (set_id, row["file"], text) for row, _, text in hits]
                else:
                    lines.append("`%s` (from `%s`): " % (set_id, source) + WORTH[what] % (len(hits), len(takes), worst))
    lines += ["`%s`: the folder has no audio files" % set_id for set_id in empty]
    return lines


def write_report(rows: list[dict], kinds: dict[str, tuple[str, float]], empty: list[str]) -> int:
    plays = read_me()
    by_set: dict[str, list[dict]] = {}
    for row in rows:
        by_set.setdefault(row["set"], []).append(row)
    out = ["# Sound sets", "",
           "Written by `tools/audio/prepare_sounds.py`. Do not edit: run the script again instead.",
           "Raw picks: `tutorial/assets/audio/new_audio/`. Game files: this folder.", "",
           "Every file is mono, 48 kHz, with a true peak of %.0f dB or lower. One-shots are WAV and start" % CEILING_DB,
           "within 10 ms; loops are OGG with loop enabled in their import settings.", "",
           "**Loudness** is integrated loudness (ITU-R BS.1770) of the mono file: a one-shot is measured played",
           "once with silence around it, a loop is measured going round. **Peak** is the true peak.",
           "Rumble under %d Hz is filtered out first: nobody hears it, and it eats the headroom the" % RUMBLE_HZ,
           "audible part needs. To reach a target, peaks are limited by %.0f dB at most; a sound that is one" % MAX_LIMITING_DB,
           "sharp click or thud stays under its target instead.", "",
           "**Make-up** is what a set still lacks on average, in dB. It is not squeezed out of the files:",
           "the game adds it at playback (`set_gain_db` in `audio/sound_settings.tres`).", "",
           "## Overview", "", "| Set | Files | Kind | Target | Measured | Make-up | Lengths |", "|---|---|---|---|---|---|---|"]
    for set_id, set_rows in by_set.items():
        louds = [row["lufs"] for row in set_rows]
        lengths = [row["seconds"] for row in set_rows]
        lacking = round(2.0 * (kinds[set_id][1] - sum(louds) / len(louds))) / 2.0
        out.append("| `%s` | %d | %s | %.0f | %s | %s | %s |" % (
            set_id, len(set_rows), kinds[set_id][0], kinds[set_id][1],
            "%.1f" % louds[0] if max(louds) - min(louds) < 0.05 else "%.1f to %.1f" % (min(louds), max(louds)),
            "+%.1f" % lacking if lacking >= 0.5 else "",
            "%.2f s" % lengths[0] if len(lengths) == 1 else "%.2f-%.2f s" % (min(lengths), max(lengths))))
    worth = worth_a_listen(by_set, empty)
    out += ["", "## Worth a listen", ""]
    out += ["- " + line for line in worth] or ["Nothing was flagged."]
    for set_id, set_rows in by_set.items():
        kind, target = kinds[set_id]
        out += ["", "## %s" % set_id, ""]
        if set_id in plays:
            out.append("Plays: %s  " % plays[set_id])
        if set_id in DERIVED:
            out.append("Built from `%s`.  " % DERIVED[set_id]["source"])
            other = DERIVED[set_id].get("unlike")
            if other in by_set:
                def describe(name: str) -> str:
                    clips = by_set[name]
                    lengths = sorted(row["seconds"] for row in clips)
                    centre = sum(row["pitch"] for row in clips) / len(clips)
                    return "`%s` is %s of %s (its energy sits around %d Hz)" % (
                        name, "%.1f s" % lengths[0] if len(clips) == 1 else "%.1f-%.1f s" % (lengths[0], lengths[-1]),
                        "breath noise" if centre > 1500 else "voiced sound", round(centre, -1))
                out.append("How it differs from `%s`: %s; %s.  " % (other, describe(set_id), describe(other)))
        out += ["Kind: %s. Target: %.0f LUFS." % (KIND_TEXT[kind], target), "",
                "| File | Length (s) | Loudness (LUFS) | Peak (dB) | Loop | From | Notes |", "|---|---|---|---|---|---|---|"]
        for row in set_rows:
            remarks = [note.lstrip("!") for note in row["source_notes"]] + [text for _, _, text in row["found"]]
            out.append("| `%s` | %.2f | %.1f | %.1f | %s | `%s` | %s |" % (
                row["file"], row["seconds"], row["lufs"], row["peak"], "yes" if row["loop"] else "no",
                row["source"], "; ".join(remarks)))
    REPORT.write_text("\n".join(out) + "\n")
    return len(worth)


def main() -> int:
    global DEBUG
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", help="only sets whose name contains this text (the report is not rewritten)")
    parser.add_argument("--debug", action="store_true", help="print what was detected in each file")
    args = parser.parse_args()
    DEBUG = args.debug
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg is not installed (brew install ffmpeg)")
    sets = find_sets()
    empty = sorted("%s/%s" % (owner, p.name) for owner in OWNERS for p in (RAW_ROOT / owner).glob("*")
                   if p.is_dir() and "%s/%s" % (owner, p.name) not in sets)
    jobs = []                                              # (set, kind, target, sources, derive rule)
    for set_id, files in sets.items():
        kind, target = SETS.get(set_id, DEFAULT[set_id.split("/")[0]])
        if set_id not in SETS:
            print("note: %s is not listed in SETS: treated as one-shots at %.0f LUFS" % (set_id, target))
        jobs.append((set_id, kind, target, files, None))
    for set_id, rule in DERIVED.items():
        if rule["source"] in sets and set_id not in sets:
            jobs.append((set_id, WHOLE, rule["lufs"], sets[rule["source"]], rule))
    if args.only:
        jobs = [job for job in jobs if args.only in job[0]]
    rows, kinds = [], {}
    with tempfile.TemporaryDirectory() as temporary:
        for set_id, kind, target, files, rule in jobs:
            print("%-22s %-7s %d raw file%s" % (set_id, kind, len(files), "" if len(files) == 1 else "s"), flush=True)
            kinds[set_id] = (kind, target)
            rows += build(set_id, kind, target, files, rule, Path(temporary))
        written, removed = publish(Path(temporary), rows, bool(args.only))
    print("%d files in %d sets (%d written, %d stale removed)" % (len(rows), len(kinds), written, removed))
    if not args.only:
        print("%d things worth a listen: see %s" % (write_report(rows, kinds, empty), REPORT.relative_to(PROJECT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
