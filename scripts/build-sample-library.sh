#!/bin/bash
#
# Converts verified note-sample masters into the compact library the app
# bundle ships from Fretlight/Resources/NoteSamples/. See
# docs/workstreams/active/002-sample-capture-and-library.md (Phase 4) for the
# full context, and Fretlight/Audio/SampleLibrary.swift for the masters
# format (WAV files + manifest.json) this script consumes.
#
#   ./scripts/build-sample-library.sh <masters-dir> [options]
#
# IMPORTANT: the output this script writes (audio files + index.json under
# Fretlight/Resources/NoteSamples/) IS committed to the repo, even though the
# masters it reads are not (they are git-ignored — see docs/releasing.md).
# The masters live only on the recording rig and its backup, so CI has no way
# to regenerate this directory; the converted library is therefore a build
# input like any other bundled asset, not a build artifact to gitignore.
#
# Requires afconvert and python3, both part of a standard macOS + Xcode
# command-line-tools install (the same toolchain xcodebuild already needs).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# The guitar has 6 strings and 22 frets past the nut; this is a physical fact,
# not a tunable — see SampleLibrary.stringCount/highestFret in
# Fretlight/Audio/SampleLibrary.swift, the source of truth this mirrors.
STRING_COUNT=6
HIGHEST_FRET=22

# Mirrors Tunings.standard.openMIDINotes in Fretlight/Theory/Tuning.swift
# (string 0 = low E). Duplicated here because this script has no Swift
# runtime to read it from directly; standard tuning cannot drift without the
# app itself changing, so keeping these six numbers in sync is a one-line fix
# if it ever does.
OPEN_MIDI=(40 45 50 55 59 64)

DEFAULT_OUTPUT_DIR="$REPO_ROOT/Fretlight/Resources/NoteSamples"
# AAC, chosen on measurement against the real masters rather than on the
# lossless-is-safer instinct. Decoded back to PCM and compared sample-for-
# sample against the ALAC build of the same takes: alignment is exact (best
# correlation at offset 0, so afconvert's priming introduces no attack-timing
# skew), and the codec's error RMS lands at -59 to -74 dBFS — 22 to 37 dB
# below the noise floor already present in each take's own pre-onset window.
# The error is buried under noise the recording carries anyway, and the
# library drops from 37.6 MB to 12.5 MB. Re-run with --format alac to rebuild
# losslessly if a future take is ever judged to suffer.
DEFAULT_FORMAT="aac"
# Masters are captured with a generous ~6s tail on purpose (workstream 002,
# Phase 0 recording parameters: "trim at build, not at record time"). This is
# the shared ceiling every bundled take is trimmed to, so a long-ringing low
# string cannot bloat the library. 4.0s matches the sizing estimate in that
# same Phase 0 note.
DEFAULT_TRIM_SECONDS=4.0
# Long enough that the release fade is not itself audible as an event, short
# enough not to perceptibly shorten the note's natural decay. Applied to the
# tail of every take unconditionally, whether or not the trim above actually
# cut anything off — a take that already decayed to silence before the cap
# can still end on a hard stop from the recorder's own decay-threshold cutoff.
DEFAULT_FADE_MS=60
# Where every take's attack is placed, measured from the start of the file.
# Matches TakeVerifier.preOnsetSeconds (0.015) — the margin the recorder aims
# for — so a take the recorder got right passes through this alignment
# unchanged, and only the ones it got wrong move.
ALIGN_MARGIN_MS=15
# Short enough not to soften a pluck, long enough to remove the step out of
# silence that every master starts on. See the fade block below.
HEAD_FADE_MS=2
# 192 kbps mono AAC is the figure workstream 002's Phase 0 sizing note used
# ("~13 MB as 192 kbps mono AAC"); kept as the default so --format aac's
# output size is comparable to that estimate.
AAC_BITRATE=192000

usage() {
  cat <<USAGE
Usage: $(basename "$0") <masters-dir> [options]

Converts a verified SampleMasters directory (WAV files + manifest.json,
produced by the in-app capture mode) into the compact library the app bundle
ships from Fretlight/Resources/NoteSamples/.

Options:
  --output DIR         Where to write the bundled library.
                        Default: ${DEFAULT_OUTPUT_DIR#$REPO_ROOT/}
  --format alac|aac     Bundle codec. Default: $DEFAULT_FORMAT
                        Measured against the real masters, not estimated: AAC
                        aligns exactly (no priming skew on the attack) and its
                        error sits 22-37 dB below each take's own recorded
                        noise floor, at a third of ALAC's size. See the
                        DEFAULT_FORMAT comment above and Phase 4 of
                        docs/workstreams/active/002-sample-capture-and-library.md.
                        ALAC remains available for a lossless rebuild.
  --trim-seconds N      Shared ceiling every take is trimmed to, in seconds.
                        Default: $DEFAULT_TRIM_SECONDS
  --fade-ms N           Release fade applied at the tail of every take, in
                        milliseconds, so no take ends on a discontinuity.
                        Default: $DEFAULT_FADE_MS
  -h, --help            Show this help.

Validation runs before any conversion and fails the whole run, naming the
offending position(s), if:
  - any of the $((STRING_COUNT * (HIGHEST_FRET + 1))) positions is missing from the manifest
  - a manifest row's audio file is missing from disk
  - a wav file on disk has no manifest row
  - a filename's encoded MIDI number disagrees with the string/fret it also
    encodes, or with the manifest's targetMIDI for that row

Rows with peakFlagged=true are reported, not failed — attack consistency
drifting over a long session needs a human decision, not an automatic reject.
USAGE
}

MASTERS_DIR=""
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
FORMAT="$DEFAULT_FORMAT"
TRIM_SECONDS="$DEFAULT_TRIM_SECONDS"
FADE_MS="$DEFAULT_FADE_MS"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --trim-seconds) TRIM_SECONDS="$2"; shift 2 ;;
    --fade-ms) FADE_MS="$2"; shift 2 ;;
    -*) echo "error: unknown option $1" >&2; usage >&2; exit 1 ;;
    *)
      if [ -n "$MASTERS_DIR" ]; then
        echo "error: unexpected argument: $1" >&2
        exit 1
      fi
      MASTERS_DIR="$1"
      shift
      ;;
  esac
done

if [ -z "$MASTERS_DIR" ]; then
  echo "error: masters directory is required" >&2
  usage >&2
  exit 1
fi
if [ ! -d "$MASTERS_DIR" ]; then
  echo "error: no such directory: $MASTERS_DIR" >&2
  exit 1
fi
case "$FORMAT" in
  alac|aac) ;;
  *) echo "error: --format must be alac or aac (got: $FORMAT)" >&2; exit 1 ;;
esac
if [ ! -f "$MASTERS_DIR/manifest.json" ]; then
  echo "error: no manifest.json in $MASTERS_DIR" >&2
  exit 1
fi

command -v afconvert >/dev/null 2>&1 || { echo "error: afconvert not found (expected as part of macOS)" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 not found (expected as part of the Xcode command-line tools)" >&2; exit 1; }

MASTERS_DIR="$(cd "$MASTERS_DIR" && pwd)"
# Resolved without being created. Creating it here to make `cd` work left an
# empty directory behind whenever validation failed, which reads as a library
# that exists but is empty — worse than no directory at all.
OUTPUT_DIR="$(python3 -c 'import os, sys; print(os.path.abspath(sys.argv[1]))' "$OUTPUT_DIR")"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/fretwork-sample-library.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
FINAL="$WORK/final"
mkdir -p "$FINAL"

echo "==> Validating masters in $MASTERS_DIR"

# Converts into $FINAL, a scratch directory, rather than $OUTPUT_DIR directly.
# $OUTPUT_DIR is a committed part of the repo (see header comment), so a run
# that fails validation partway through must not have already deleted a good
# previously-committed library — the swap into $OUTPUT_DIR below only happens
# once this has fully succeeded.
python3 - "$MASTERS_DIR" "$FINAL" "$WORK" "$FORMAT" "$TRIM_SECONDS" "$FADE_MS" "$AAC_BITRATE" \
  "$ALIGN_MARGIN_MS" "$HEAD_FADE_MS" "$STRING_COUNT" "$HIGHEST_FRET" "${OPEN_MIDI[@]}" <<'PY'
import json
import math
import re
import subprocess
import sys
import wave
from pathlib import Path

(masters_dir, output_dir, work_dir, fmt, trim_seconds, fade_ms, aac_bitrate,
 align_margin_ms, head_fade_ms, strings, highest_fret, *open_midi) = sys.argv[1:]

masters_dir = Path(masters_dir)
output_dir = Path(output_dir)
work_dir = Path(work_dir)
trim_seconds = float(trim_seconds)
fade_ms = float(fade_ms)
aac_bitrate = int(aac_bitrate)
ALIGN_MARGIN_MS = float(align_margin_ms)
HEAD_FADE_MS = float(head_fade_ms)

# What fraction of a take's own loudest opening block counts as the attack
# having started. 0.1 (-20 dB relative) sits above the recorded noise floor on
# every take measured, and below the shoulder of even the slowest wound-string
# attack, so it marks the transient rather than the noise or the peak.
ONSET_FRACTION = 0.1
strings = int(strings)
highest_fret = int(highest_fret)
open_midi = [int(x) for x in open_midi]

NAME_RE = re.compile(r"^s(\d+)-f(\d{2})-m(\d{3})\.wav$")


def expected_filename(string, fret):
    midi = open_midi[string] + fret
    return f"s{string}-f{fret:02d}-m{midi:03d}.wav"


manifest_path = masters_dir / "manifest.json"
try:
    manifest = json.loads(manifest_path.read_text())
except Exception as exc:  # noqa: BLE001 - reported to the operator, not re-raised
    print(f"error: could not parse {manifest_path}: {exc}", file=sys.stderr)
    sys.exit(1)

if not isinstance(manifest, list):
    print(f"error: {manifest_path} is not a JSON array", file=sys.stderr)
    sys.exit(1)

expected_positions = [(s, f) for s in range(strings) for f in range(highest_fret + 1)]
expected_set = set(expected_positions)

# Each error is (sort_key, message) so the report below can name positions in
# neck order rather than in whatever order the checks happened to run.
errors = []
by_position = {}
for row in manifest:
    try:
        s = int(row["string"])
        f = int(row["fret"])
    except (KeyError, TypeError, ValueError) as exc:
        errors.append(((99, 0, 0), f"manifest row is missing string/fret: {row!r} ({exc})"))
        continue
    if (s, f) not in expected_set:
        errors.append(((99, s, f), f"manifest row for an impossible position: string {s} fret {f}"))
        continue
    if (s, f) in by_position:
        errors.append(((3, s, f), f"duplicate manifest row for string {s} fret {f}"))
        continue
    by_position[(s, f)] = row

# 1. Positions missing from the manifest entirely.
for s, f in expected_positions:
    if (s, f) not in by_position:
        errors.append(((0, s, f), f"missing from manifest: string {s} fret {f} (expected {expected_filename(s, f)})"))

# 2. Manifest rows whose audio file is absent from disk.
for (s, f), row in by_position.items():
    name = expected_filename(s, f)
    if not (masters_dir / name).is_file():
        errors.append(((1, s, f), f"manifest row references missing audio file: string {s} fret {f} expects {name}"))

# 3 & 4. Every wav on disk: orphaned, or a filename/MIDI mismatch.
for path in sorted(masters_dir.glob("*.wav")):
    name = path.name
    m = NAME_RE.match(name)
    if not m:
        errors.append(((4, 99, 99), f"orphaned audio file: {name} does not match the s<string>-f<fret>-m<midi>.wav convention"))
        continue
    s, f, midi = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if (s, f) not in expected_set:
        errors.append(((4, s, f), f"orphaned audio file: {name} encodes an impossible position (string {s} fret {f})"))
        continue
    expected_midi = open_midi[s] + f
    if midi != expected_midi:
        errors.append((
            (2, s, f),
            f"filename/MIDI mismatch: {name} encodes MIDI {midi} but string {s} fret {f} implies MIDI {expected_midi}",
        ))
    row = by_position.get((s, f))
    if row is None:
        errors.append(((4, s, f), f"orphaned audio file: {name} has no manifest row for string {s} fret {f}"))
    elif row.get("targetMIDI") != midi:
        errors.append((
            (2, s, f),
            f"filename/MIDI mismatch: {name} encodes MIDI {midi} but the manifest row for string {s} fret {f} "
            f"has targetMIDI {row.get('targetMIDI')}",
        ))

if errors:
    errors.sort(key=lambda e: e[0])
    print(f"error: masters validation failed with {len(errors)} problem(s):", file=sys.stderr)
    for _, message in errors:
        print(f"  - {message}", file=sys.stderr)
    sys.exit(1)

flagged = sorted(pos for pos, row in by_position.items() if row.get("peakFlagged"))
if flagged:
    print(f"{len(flagged)} take(s) flagged for peak deviation (accepted, review before shipping):")
    for s, f in flagged:
        print(f"  - string {s} fret {f} ({expected_filename(s, f)})")

print(f"All {len(expected_positions)} positions present and verified.")

# ---- trim + fade every take into a scratch directory ----
trimmed_dir = work_dir / "trimmed"
trimmed_dir.mkdir(parents=True, exist_ok=True)

def measure_onset(samples, rate):
    """Frame index where the attack actually begins.

    The recorder already trimmed each master to a fixed margin ahead of the
    onset *it* detected, but its threshold is derived from the noise floor and
    fires late on a soft attack — measured across a real 138-take session, 93
    takes landed on the intended margin while 33 sat at 0-2ms (the rewind had
    landed mid-transient) and a dozen sat as late as 43ms. That is up to 15ms
    of jitter in where a note starts, which a sampled playback engine
    triggering on a grid renders as sloppy timing.

    Re-measuring here rather than trusting the recorder's mark: walk 1ms
    blocks and take the first one reaching a fixed fraction of the loudest
    block in the take's opening. Deliberately relative to the take's own level
    rather than to an absolute dBFS figure, because every take is normalised
    to the same peak but their attacks differ in slope by string and fret.
    """
    block = max(1, int(round(rate * 0.001)))
    blocks = []
    for start in range(0, min(len(samples), int(rate * 0.25)), block):
        seg = samples[start:start + block]
        if not seg:
            break
        blocks.append(math.sqrt(sum(v * v for v in seg) / len(seg)))
    if not blocks:
        return 0
    ceiling = max(blocks)
    if ceiling <= 0:
        return 0
    for i, v in enumerate(blocks):
        if v > ceiling * ONSET_FRACTION:
            return i * block
    return 0


positions = []
onset_reports = []
for s, f in expected_positions:
    row = by_position[(s, f)]
    src = masters_dir / expected_filename(s, f)
    with wave.open(str(src), "rb") as w:
        nch = w.getnchannels()
        sw = w.getsampwidth()
        rate = w.getframerate()
        nframes = w.getnframes()
        raw = w.readframes(nframes)

    if nch != 1 or sw != 3:
        print(
            f"error: {src.name} is not mono 24-bit PCM (got {nch} channel(s), {sw * 8}-bit)",
            file=sys.stderr,
        )
        sys.exit(1)

    full_scale = float(2 ** (8 * sw - 1))
    samples = [
        int.from_bytes(raw[i * sw:(i + 1) * sw], byteorder="little", signed=True) / full_scale
        for i in range(nframes)
    ]

    # Align every take so its attack begins the same distance into the file.
    # A take whose onset sits later than the common margin is cut down to it;
    # one that sits earlier is padded with silence. Padding cannot restore a
    # transient the recorder already trimmed away — that audio is not in the
    # master — but alignment is what playback needs, and a truncated attack
    # padded to the common margin is still in time with its neighbours.
    margin_frames = int(round(rate * ALIGN_MARGIN_MS / 1000.0))
    onset = measure_onset(samples, rate)
    shift = onset - margin_frames
    if shift > 0:
        samples = samples[shift:]
    elif shift < 0:
        samples = [0.0] * (-shift) + samples
    onset_reports.append((s, f, onset * 1000.0 / rate, shift * 1000.0 / rate))

    max_frames = int(round(rate * trim_seconds))
    trimmed_frames = min(len(samples), max_frames)
    samples = samples[:trimmed_frames]

    # Fade both ends. The tail fade is the long one, keeping a take from
    # ending on the discontinuity the trim above (or the recorder's own decay
    # cutoff) leaves behind. The head fade is short and exists for the
    # mirror-image reason: every master starts at a nonzero sample, and the
    # worst measured at +0.124 (-18 dBFS) — an instant step out of silence
    # that plays as a click. A couple of milliseconds removes the step without
    # perceptibly softening a plucked transient.
    head_frames = min(int(round(rate * HEAD_FADE_MS / 1000.0)), trimmed_frames)
    for i in range(head_frames):
        samples[i] *= (i + 1) / head_frames

    fade_frames = min(int(round(rate * fade_ms / 1000.0)), trimmed_frames)
    for i in range(fade_frames):
        idx = trimmed_frames - fade_frames + i
        samples[idx] *= 1.0 - (i + 1) / fade_frames

    max_val = 2 ** (8 * sw - 1) - 1
    min_val = -(2 ** (8 * sw - 1))
    data = bytearray(trimmed_frames * sw)
    for i, v in enumerate(samples):
        value = max(min_val, min(max_val, int(round(v * full_scale))))
        data[i * sw:(i + 1) * sw] = value.to_bytes(sw, byteorder="little", signed=True)

    basename = f"s{s}-f{f:02d}-m{row['targetMIDI']:03d}"
    dest = trimmed_dir / f"{basename}.wav"
    with wave.open(str(dest), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(sw)
        w.setframerate(rate)
        w.writeframes(bytes(data))

    positions.append({
        "string": s,
        "fret": f,
        "targetMIDI": row["targetMIDI"],
        "sampleRate": rate,
        "frameCount": trimmed_frames,
        "basename": basename,
    })

shifted = [r for r in onset_reports if abs(r[3]) >= 1.0]
print(
    f"Trimmed and faded {len(positions)} takes (max {trim_seconds:.1f}s, "
    f"{HEAD_FADE_MS:.0f}ms attack fade, {fade_ms:.0f}ms release fade)."
)
print(
    f"Aligned every attack to {ALIGN_MARGIN_MS:.0f}ms in; "
    f"{len(shifted)} take(s) needed a shift of 1ms or more "
    f"(largest {max((abs(r[3]) for r in onset_reports), default=0.0):.0f}ms)."
)

# ---- convert every trimmed take to the bundle format ----
print(f"==> Converting to {fmt} (.m4a)")
for entry in positions:
    src = trimmed_dir / f"{entry['basename']}.wav"
    dest = output_dir / f"{entry['basename']}.m4a"
    if fmt == "alac":
        cmd = ["afconvert", "-f", "m4af", "-d", "alac", str(src), str(dest)]
    else:
        cmd = ["afconvert", "-f", "m4af", "-d", "aac", "-b", str(aac_bitrate), "-q", "127", str(src), str(dest)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"error: afconvert failed for string {entry['string']} fret {entry['fret']} ({src.name}):", file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    entry["filename"] = dest.name

# index.json is written deterministically — sorted, no embedded generation
# timestamp — so re-running against unchanged masters produces no diff noise
# in a file this repo commits.
index = {
    "format": fmt,
    "positions": sorted(
        (
            {
                "string": e["string"],
                "fret": e["fret"],
                "targetMIDI": e["targetMIDI"],
                "filename": e["filename"],
                "sampleRate": e["sampleRate"],
                "frameCount": e["frameCount"],
            }
            for e in positions
        ),
        key=lambda e: (e["string"], e["fret"]),
    ),
}
(output_dir / "index.json").write_text(json.dumps(index, indent=2) + "\n")

total_bytes = sum((output_dir / e["filename"]).stat().st_size for e in positions)
total_bytes += (output_dir / "index.json").stat().st_size
total_mb = total_bytes / (1024 * 1024)
print(f"Converted {len(positions)} takes + index.json ({fmt}): {total_mb:.2f} MB ({total_bytes} bytes)")
PY

# Only now — after validation, trim/fade and every afconvert call has fully
# succeeded — replace what OUTPUT_DIR held. A partial or failed run above
# exits before this line runs, leaving a previously-good committed library
# untouched.
echo "==> Installing into $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.m4a "$OUTPUT_DIR/index.json"
mv "$FINAL"/*.m4a "$FINAL/index.json" "$OUTPUT_DIR"/

echo "==> Done"
echo "    $OUTPUT_DIR ($(du -sh "$OUTPUT_DIR" | cut -f1))"
