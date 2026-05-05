#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="/tmp/android-monitor-cursor-capture-smoke"
DURATION=20

usage() {
    cat <<'EOF'
cursor-capture-smoke.sh

Runs a strict real-capture cursor visibility smoke. The script creates a real
virtual display with a static cursor target, sweeps the macOS cursor across it,
streams to Android over USB, then decodes sampled H.264 frames locally. If the
cursor is not included in ScreenCaptureKit output, the static target should not
produce enough sampled-frame change and the freshness check fails.

Options:
  --duration <sec>   Default: 20.
  --output-dir <p>   Default: /tmp/android-monitor-cursor-capture-smoke.
  --help             Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration)
            DURATION="${2:?--duration requires a value}"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="${2:?--output-dir requires a value}"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "[FAIL] Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 10 ]]; then
    echo "[FAIL] --duration must be an integer >= 10: $DURATION" >&2
    exit 2
fi

"$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale

"$ROOT_DIR/scripts/phase0-stream-test.sh" \
    --width 1024 \
    --height 600 \
    --fps 15 \
    --bitrate-mbps 2 \
    --duration "$DURATION" \
    --output-dir "$OUTPUT_DIR" \
    --cursor-test-window \
    --pre-capture-delay 2 \
    --require-real-capture \
    --min-decoded-frames 60 \
    --min-input-fps 10

"$ROOT_DIR/scripts/verify-h264-freshness.py" \
    "$OUTPUT_DIR/stream.h264" \
    --fps 1 \
    --min-frames 4 \
    --min-diff 0.03 \
    --keep-frames "$OUTPUT_DIR/decoded-frames"

if ! grep -q "Cursor sweep started" "$OUTPUT_DIR/mac-host.log"; then
    echo "[FAIL] Cursor sweep did not start." >&2
    exit 1
fi
if ! grep -q "showsCursor = true" "$ROOT_DIR/MacHost/Sources/MacHost/DisplayCapture.swift"; then
    echo "[FAIL] ScreenCaptureKit cursor capture is not enabled in source." >&2
    exit 1
fi

cat <<EOF
[OK] Cursor capture smoke passed.

Artifacts:
  Output dir:      $OUTPUT_DIR
  Mac log:         $OUTPUT_DIR/mac-host.log
  Android log:     $OUTPUT_DIR/android-logcat.log
  H.264 file:      $OUTPUT_DIR/stream.h264
  Decoded frames:  $OUTPUT_DIR/decoded-frames
EOF
