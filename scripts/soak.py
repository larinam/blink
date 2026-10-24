#!/usr/bin/env python3
"""Observe one unchanged Blink process for a live working-day stability trial.

Writes local technical measurements only; it never drives input or bypasses idle,
quiet, or sleep behavior. A completed run still needs human/agent review of the
measurements and a native responsiveness check.
"""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess
import time
from datetime import datetime, timezone

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--pid", type=int, required=True)
parser.add_argument("--binary", type=pathlib.Path, required=True)
parser.add_argument("--state", type=pathlib.Path, required=True)
parser.add_argument("--hours", type=float, default=8)
parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("qa-output/live-trial"))
args = parser.parse_args()
if args.hours <= 0:
    parser.error("--hours must be positive")
args.output.mkdir(parents=True, exist_ok=True)

def stamp():
    return datetime.now(timezone.utc).isoformat()

def digest():
    return hashlib.sha256(args.binary.read_bytes()).hexdigest()

def process():
    result = subprocess.run(["ps", "-p", str(args.pid), "-o", "pid=,%cpu=,rss=,lstart="], text=True, capture_output=True)
    if result.returncode or not result.stdout.strip():
        raise RuntimeError("The observed Blink process exited.")
    parts = result.stdout.strip().split(maxsplit=3)
    return int(parts[0]), float(parts[1]), int(parts[2]), parts[3]

baseline_hash = digest()
_, _, _, process_start = process()
started = time.monotonic()
samples = []
metadata = {"status": "running", "started_at": stamp(), "pid": args.pid, "process_start": process_start,
            "binary": str(args.binary.resolve()), "sha256": baseline_hash, "requested_hours": args.hours}
(args.output / "status.json").write_text(json.dumps(metadata, indent=2) + "\n")
print(json.dumps(metadata), flush=True)

try:
    with (args.output / "samples.jsonl").open("w") as log:
        while True:
            pid, cpu, rss, current_start = process()
            if current_start != process_start:
                raise RuntimeError("PID was reused by another process.")
            if digest() != baseline_hash:
                raise RuntimeError("App binary changed; this run cannot verify the new build.")
            elapsed = time.monotonic() - started
            state_stat = args.state.stat()
            sample = {"at": stamp(), "elapsed_seconds": round(elapsed, 2), "cpu_percent": cpu,
                      "rss_kib": rss, "state_bytes": state_stat.st_size,
                      "state_age_seconds": round(max(0, time.time() - state_stat.st_mtime), 2)}
            log.write(json.dumps(sample) + "\n")
            log.flush()
            samples.append(sample)
            if len(samples) % 5 == 1:
                print(json.dumps(sample), flush=True)
            metadata.update(last_sample=sample, samples=len(samples))
            (args.output / "status.json").write_text(json.dumps(metadata, indent=2) + "\n")
            if elapsed >= args.hours * 3600:
                break
            time.sleep(min(60, args.hours * 3600 - elapsed))
    warm = [s for s in samples if s["elapsed_seconds"] >= 1800] or samples
    first = warm[:min(30, len(warm))]
    last = warm[-min(30, len(warm)):]
    summary = {**metadata, "status": "measurement_complete", "finished_at": stamp(),
               "cpu_mean_percent": statistics.mean(s["cpu_percent"] for s in samples),
               "rss_peak_kib": max(s["rss_kib"] for s in samples),
               "rss_first_warm_median_kib": statistics.median(s["rss_kib"] for s in first),
               "rss_last_median_kib": statistics.median(s["rss_kib"] for s in last),
               "max_state_bytes": max(s["state_bytes"] for s in samples),
               "max_state_age_seconds": max(s["state_age_seconds"] for s in samples),
               "review_required": "Inspect resource trend, sleep gaps and heartbeat, then verify native responsiveness."}
    (args.output / "status.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary), flush=True)
except BaseException as error:
    metadata.update(status="interrupted", finished_at=stamp(), error=str(error))
    (args.output / "status.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata), flush=True)
    raise
