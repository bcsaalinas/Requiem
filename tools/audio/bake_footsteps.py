#!/usr/bin/env python3
"""Extract eight dry one-shots from the project's existing recording. Requires ffmpeg."""
from array import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'requiem/assets/audio/freesound_community-concrete-footsteps-1-6265.mp3'
OUTPUT = ROOT / 'requiem/assets/audio/footsteps'
RATE = 24000
# Separate impacts, with enough context to find the attack without its silence.
WINDOWS = [(0.27, 0.55), (1.61, 1.91), (2.59, 2.89), (3.16, 3.46),
           (3.65, 3.95), (4.11, 4.41), (4.54, 4.84), (6.06, 6.36)]


def bake():
    decoded = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(SOURCE),
        '-af', 'highpass=f=85,lowpass=f=6500', '-ac', '1', '-ar', str(RATE), '-f', 'f32le', '-'])
    samples = array('f'); samples.frombytes(decoded)
    if sys.byteorder != 'little': samples.byteswap()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    entries = []
    for index, (start, end) in enumerate(WINDOWS, 1):
        segment = list(samples[round(start * RATE):round(end * RATE)])
        threshold = max(abs(x) for x in segment) * 0.08
        attack = next(i for i, x in enumerate(segment) if abs(x) >= threshold)
        first = max(0, attack - round(0.001 * RATE))
        segment = segment[first:first + round(0.26 * RATE)]
        rms = math.sqrt(sum(x*x for x in segment[:round(.12*RATE)]) / min(len(segment), round(.12*RATE)))
        gain = min(10**(-23/20) / max(rms, 1e-8), 10**(-3/20) / max(abs(x) for x in segment), 10**(18/20))
        for i in range(len(segment)):
            envelope = min(1.0, i / max(1, round(.00075*RATE)),
                           (len(segment)-1-i) / max(1, round(.055*RATE)))
            segment[i] *= gain * max(0, envelope)
        pcm = array('h', [round(max(-1, min(1, x))*32767) for x in segment])
        if sys.byteorder != 'little': pcm.byteswap()
        path = OUTPUT / f'concrete_step_{index:02}.wav'
        with wave.open(str(path), 'wb') as wav:
            wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(RATE)
            wav.writeframes(pcm.tobytes())
        entries.append(dict(file=str(path.relative_to(ROOT)), source_start=round(start+first/RATE,6),
            duration=len(segment)/RATE, gain_db=round(20*math.log10(gain),3),
            peak_db=round(20*math.log10(max(abs(x) for x in segment)),3),
            sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    manifest = dict(source=str(SOURCE.relative_to(ROOT)),
        source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        source_reference='https://pixabay.com/sound-effects/concrete-footsteps-1-6265/',
        format='24000 Hz mono 16-bit PCM; no loops',
        processing='85 Hz high-pass; 6.5 kHz low-pass; trimmed attack; bounded gain; 0.75 ms fade-in, 55 ms tail fade',
        clips=entries)
    (Path(__file__).parent / 'footsteps_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    bake()
