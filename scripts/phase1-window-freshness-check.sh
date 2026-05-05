#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WIDTH=1024
HEIGHT=600
FPS=15
BITRATE_MBPS=2
DURATION=12
OUTPUT_DIR="/tmp/android-monitor-phase1-window-freshness"
EXTRA_ARGS=()

usage() {
    cat <<'EOF'
phase1-window-freshness-check.sh

Runs a Phase 1 visual-freshness gate with a normal TextEdit window on the
virtual display. The script streams to Android, then decodes the captured H.264
locally and verifies sampled frames are visible and changing.

Requires ffmpeg and Python Pillow for the local H.264 frame check.

Options:
  --output-dir <path>   Default: /tmp/android-monitor-phase1-window-freshness
  --help                Show this message.

Any other arguments are passed through to phase0-stream-test.sh after the
defaults, so width, height, fps, bitrate, duration, thresholds, and port can be
overridden there.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            OUTPUT_DIR="${2:?--output-dir requires a value}"
            EXTRA_ARGS+=("$1" "$2")
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            EXTRA_ARGS+=("$1")
            ;;
    esac
    shift
done

"$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale

"$ROOT_DIR/scripts/phase0-stream-test.sh" \
    --width "$WIDTH" \
    --height "$HEIGHT" \
    --fps "$FPS" \
    --bitrate-mbps "$BITRATE_MBPS" \
    --duration "$DURATION" \
    --output-dir "$OUTPUT_DIR" \
    --external-textedit-window \
    --pre-capture-delay 3 \
    --require-real-capture \
    --min-decoded-frames 30 \
    --min-input-fps 10 \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

"$ROOT_DIR/scripts/verify-h264-freshness.py" \
    "$OUTPUT_DIR/stream.h264" \
    --keep-frames "$OUTPUT_DIR/decoded-frames"

cat <<EOF
[OK] Phase 1 window freshness check passed.

Artifacts:
  Output dir:      $OUTPUT_DIR
  Decoded frames:  $OUTPUT_DIR/decoded-frames
EOF
