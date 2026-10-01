#!/bin/bash
# Deterministic screenshot capture for the iOS DEBUG snapshot harness.
#
# Usage:
#   scripts/ios-snapshots.sh <sim-udid> <output-dir> <scenario> [scenario ...]
#
# Each scenario is a `-IOSSnapshot*` launch argument. The script installs the
# already-built Fretwork.app, launches it with the argument, waits for the
# harness to settle, screenshots it, and terminates the app so the next
# scenario starts clean. Pass an existing app path in FRETWORK_APP to skip the
# default build-products location.
set -euo pipefail

UDID="${1:?simulator udid required}"
OUT="${2:?output dir required}"
shift 2
SCENARIOS=("$@")
if [ "${#SCENARIOS[@]}" -eq 0 ]; then
  echo "no scenarios given" >&2
  exit 1
fi

APP="${FRETWORK_APP:-/tmp/fw-ipad-dd/Build/Products/Debug-iphonesimulator/Fretwork.app}"
BUNDLE=org.fretwork.app.ios

mkdir -p "$OUT"
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant microphone "$BUNDLE" 2>/dev/null || true

for SCEN in "${SCENARIOS[@]}"; do
  NAME="${SCEN#-IOSSnapshot}"
  # A fresh launch per scenario: the harness reads its scenario from the
  # launch arguments, so a re-launch never carries a previous run's state.
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$SCEN" >/dev/null
  # The harness pops back / requests landscape at ~2s; give it 4 to settle.
  sleep 4
  xcrun simctl io "$UDID" screenshot "$OUT/${NAME}.png" >/dev/null
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "wrote ${#SCENARIOS[@]} screenshots to $OUT"
