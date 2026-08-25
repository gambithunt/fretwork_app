#!/bin/bash
#
# Writes a synthetic SampleMasters directory — synthesised tones plus a
# matching manifest.json, in the exact shape the in-app capture mode
# produces — so scripts/build-sample-library.sh can be exercised end to end
# without a real recording session. See
# docs/workstreams/active/002-sample-capture-and-library.md, Phase 4.
#
# This is a test-fixture generator only. It never runs as part of a real
# build and its output is never committed.
#
#   ./scripts/generate-synthetic-masters.sh <output-dir> [options]
#
set -euo pipefail

# Mirrors the same two constants in build-sample-library.sh, which mirror
# SampleLibrary.swift / Tuning.swift in turn — see that script's header for
# why these are duplicated rather than shared.
STRING_COUNT=6
HIGHEST_FRET=22
OPEN_MIDI=(40 45 50 55 59 64)

DEFAULT_SECONDS=2.0
DEFAULT_RATE=48000
DEFAULT_BREAK="none"

usage() {
  cat <<USAGE
Usage: $(basename "$0") <output-dir> [options]

Options:
  --seconds N   Per-take duration in seconds. Real masters run ~6s; this
                defaults much shorter since a synthetic fixture only needs to
                exercise the build script's trim/fade/convert path, not
                reproduce real timing. Default: $DEFAULT_SECONDS
  --rate N      Sample rate in Hz. Default: $DEFAULT_RATE
  --break MODE  Introduce exactly one deliberate defect, to exercise one
                validation failure path in build-sample-library.sh. MODE is
                one of:
                  none            (default) a fully valid 138-position library
                  missing-position  one position has neither a manifest row
                                    nor an audio file
                  missing-audio     one manifest row's audio file is absent
                  orphaned-file     one audio file exists with no manifest row
                                    (also short one manifest row, since those
                                    are the same underlying defect — see
                                    SampleLibrary.write's crash-consistency
                                    note)
                  midi-mismatch     one manifest row's targetMIDI disagrees
                                    with its (correctly-named) audio file
  -h, --help    Show this help.

One position is always marked peakFlagged=true, regardless of --break, so a
clean run also demonstrates build-sample-library.sh's report-but-don't-fail
path for flagged takes.
USAGE
}

OUTPUT_DIR=""
SECONDS_PER_TAKE="$DEFAULT_SECONDS"
RATE="$DEFAULT_RATE"
BREAK="$DEFAULT_BREAK"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --seconds) SECONDS_PER_TAKE="$2"; shift 2 ;;
    --rate) RATE="$2"; shift 2 ;;
    --break) BREAK="$2"; shift 2 ;;
    -*) echo "error: unknown option $1" >&2; usage >&2; exit 1 ;;
    *)
      if [ -n "$OUTPUT_DIR" ]; then
        echo "error: unexpected argument: $1" >&2
        exit 1
      fi
      OUTPUT_DIR="$1"
      shift
      ;;
  esac
done

if [ -z "$OUTPUT_DIR" ]; then
  echo "error: output directory is required" >&2
  usage >&2
  exit 1
fi

case "$BREAK" in
  none|missing-position|missing-audio|orphaned-file|midi-mismatch) ;;
  *) echo "error: unknown --break mode: $BREAK" >&2; usage >&2; exit 1 ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found" >&2; exit 1; }

# A synthetic fixture starts clean every time — this is scaffolding for a
# test run, not state anyone builds on incrementally.
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

python3 - "$OUTPUT_DIR" "$SECONDS_PER_TAKE" "$RATE" "$BREAK" "$STRING_COUNT" "$HIGHEST_FRET" "${OPEN_MIDI[@]}" <<'PY'
import json
import math
import sys
import time
import wave
from pathlib import Path

(out_dir, seconds, rate, break_mode, strings, highest_fret, *open_midi) = sys.argv[1:]

out_dir = Path(out_dir)
seconds = float(seconds)
rate = int(rate)
strings = int(strings)
highest_fret = int(highest_fret)
open_midi = [int(x) for x in open_midi]

AMPLITUDE = 0.5
ATTACK_MS = 5.0
MAX_VAL = 2 ** 23 - 1


def midi_to_freq(midi):
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def synth_wav(path, freq, seconds, rate):
    n = int(round(seconds * rate))
    attack_frames = max(1, int(round(rate * ATTACK_MS / 1000.0)))
    frames = bytearray()
    for i in range(n):
        env = min(1.0, (i + 1) / attack_frames)
        sample = AMPLITUDE * env * math.sin(2 * math.pi * freq * i / rate)
        value = int(round(sample * MAX_VAL))
        frames += value.to_bytes(3, byteorder="little", signed=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(3)
        w.setframerate(rate)
        w.writeframes(bytes(frames))
    return n


all_positions = [(s, f) for s in range(strings) for f in range(highest_fret + 1)]

# Deterministic so re-running the same --break mode always disturbs the same
# position, which is what makes the "prove it fails" transcripts reproducible.
FLAGGED_POSITION = (strings - 1, highest_fret)

skip_audio = set()
skip_manifest = set()
corrupt_midi_position = None

if break_mode == "missing-position":
    skip_audio.add((strings // 2, highest_fret // 2))
    skip_manifest.add((strings // 2, highest_fret // 2))
elif break_mode == "missing-audio":
    skip_audio.add((2, 5))
elif break_mode == "orphaned-file":
    # The file is written normally below; only its manifest row is withheld.
    # This is deliberately the same shape SampleLibrary.write's own docstring
    # describes as the surviving crash-consistency failure mode: audio placed
    # before the manifest is updated, so a crash in between leaves a file
    # nothing tracks.
    skip_manifest.add((3, 8))
elif break_mode == "midi-mismatch":
    corrupt_midi_position = (4, 12)

manifest = []
for (s, f) in all_positions:
    midi = open_midi[s] + f
    name = f"s{s}-f{f:02d}-m{midi:03d}.wav"

    if (s, f) not in skip_audio:
        frame_count = synth_wav(out_dir / name, midi_to_freq(midi), seconds, rate)
    else:
        frame_count = int(round(seconds * rate))

    if (s, f) in skip_manifest:
        continue

    target_midi = midi
    if corrupt_midi_position is not None and (s, f) == corrupt_midi_position:
        target_midi = midi + 7  # deliberately wrong; the file itself stays correctly named

    manifest.append({
        "string": s,
        "fret": f,
        "targetMIDI": target_midi,
        "detectedFrequency": midi_to_freq(midi),
        "centsDeviation": 0.0,
        "peak": AMPLITUDE,
        "frameCount": frame_count,
        "sampleRate": rate,
        "recordedAt": time.time(),
        "peakFlagged": (s, f) == FLAGGED_POSITION,
    })

(out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))

written = len(all_positions) - len(skip_audio)
print(f"Wrote {written} audio file(s) and {len(manifest)} manifest row(s) to {out_dir} (--break {break_mode})")
PY
