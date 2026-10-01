#!/bin/bash
# Builds the offline replay harness against the *real* shared source files, so
# it exercises the production detection path rather than a copy.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
SRC="$ROOT/Fretlight"
OUT="${BUILD_DIR:-$ROOT/scripts/offline-replay/.build}/offline-replay"
mkdir -p "$(dirname "$OUT")"

swiftc -O \
  "$SRC/Theory/PitchClass.swift" \
  "$SRC/Pitch/NoteMapper.swift" \
  "$SRC/Models/PitchDisplayState.swift" \
  "$SRC/Audio/SensitivitySettings.swift" \
  "$SRC/Audio/NoteGate.swift" \
  "$SRC/Audio/RingBuffer.swift" \
  "$SRC/Pitch/PitchDetector.swift" \
  "$SRC/Audio/AudioAnalysisWorker.swift" \
  "$ROOT/scripts/offline-replay/main.swift" \
  -o "$OUT"

echo "built: $OUT"
