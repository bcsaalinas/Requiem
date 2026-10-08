#!/usr/bin/env python3
"""Run isolated Godot suites; a crash, timeout, script error or missing summary fails."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[1]
SUITES = ("test_tutorial", "test_breath_events", "test_breath_feedback", "test_throw_feedback", "test_prayer_feedback", "test_sprint_feedback", "test_footstep_audio", "test_player_actions", "test_player_motion",
          "test_player_pose", "test_phantom_camera", "test_level_template", "test_test_lab")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--rendered", action="store_true", help="Also run GPU lighting checks (requires a display)")
    parser.add_argument("--suite", choices=(*SUITES, "test_lighting_response"))
    parser.add_argument("--output", type=Path, default=PROJECT / ".local-development/test-results")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    if sys.platform.startswith("linux"):
        # Keep test saves/captures isolated and writable in CI and sandboxed runs.
        environment["XDG_DATA_HOME"] = str((args.output / "runtime").resolve())
    selected = [args.suite] if args.suite else list(SUITES) + (["test_lighting_response"] if args.rendered else [])
    failures = []
    for suite in selected:
        rendered = suite == "test_lighting_response"
        command = [args.godot, "--path", str(PROJECT), "--audio-driver", "Dummy",
                   "--log-file", str((args.output / f"{suite}.engine.log").resolve())]
        command += ["--display-driver", "x11"] if rendered and sys.platform.startswith("linux") else ([] if rendered else ["--headless"])
        command += [f"res://testing/regression/{suite}.tscn", "--", "--windowed"]
        print(f"Running {suite}...", flush=True)
        try:
            result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180, env=environment)
            output = result.stdout.decode(errors="replace")
            summaries = re.findall(r"\[[^\n]+\][^\n]*\d+/\d+[^\n]*passed", output, re.IGNORECASE)
            failed = result.returncode != 0 or not summaries or "SCRIPT ERROR:" in output or "ERROR:" in output
        except subprocess.TimeoutExpired as exc:
            output = (exc.stdout or b"").decode(errors="replace") + "\nTIMEOUT after 180 seconds\n"
            summaries, failed = [], True
        (args.output / f"{suite}.log").write_text(output)
        print(("FAIL" if failed else "PASS") + " " + (summaries[-1] if summaries else suite), flush=True)
        if failed:
            failures.append(suite)
    print(f"{len(selected) - len(failures)}/{len(selected)} suites passed. Logs: {args.output.resolve()}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
