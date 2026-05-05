#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WIDTH=1024
HEIGHT=600
FPS=15
BITRATE_MBPS=2
DURATION=3600
OUTPUT_DIR="/tmp/android-monitor-phase2-stability"
MIN_DECODED_FRAMES=""
MIN_INPUT_FPS=10
FRESHNESS_FPS=1

usage() {
    cat <<'EOF'
phase2-stability-check.sh

Runs the Phase 2 stability gate with a normal TextEdit window on the virtual
display. Defaults to the one-hour acceptance duration from PLAN.md and verifies
real capture, Android decoded-frame stats, Annex-B keyframes, and sampled H.264
visual freshness.

Options:
  --duration <seconds>        Default: 3600.
  --output-dir <path>         Default: /tmp/android-monitor-phase2-stability
  --min-decoded-frames <n>    Default: 60% of duration * fps.
  --min-input-fps <n>         Default: 10.
  --freshness-fps <n>         Default: 1. H.264 visual sample FPS.
  --help                      Show this message.
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
        --min-decoded-frames)
            MIN_DECODED_FRAMES="${2:?--min-decoded-frames requires a value}"
            shift
            ;;
        --min-input-fps)
            MIN_INPUT_FPS="${2:?--min-input-fps requires a value}"
            shift
            ;;
        --freshness-fps)
            FRESHNESS_FPS="${2:?--freshness-fps requires a value}"
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

if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -le 0 ]]; then
    echo "[FAIL] --duration must be a positive integer: $DURATION" >&2
    exit 2
fi
if ! awk -v value="$FRESHNESS_FPS" 'BEGIN { exit(value ~ /^[0-9]+([.][0-9]+)?$/ && value + 0 > 0 ? 0 : 1) }'; then
    echo "[FAIL] --freshness-fps must be a positive number: $FRESHNESS_FPS" >&2
    exit 2
fi
if [[ -z "$MIN_DECODED_FRAMES" ]]; then
    MIN_DECODED_FRAMES=$((DURATION * FPS * 60 / 100))
fi

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
    --min-decoded-frames "$MIN_DECODED_FRAMES" \
    --min-input-fps "$MIN_INPUT_FPS"

"$ROOT_DIR/scripts/verify-h264-freshness.py" \
    "$OUTPUT_DIR/stream.h264" \
    --fps "$FRESHNESS_FPS" \
    --min-frames 4 \
    --keep-frames "$OUTPUT_DIR/decoded-frames"

cat <<EOF
[OK] Phase 2 stability check passed.

Artifacts:
  Output dir:      $OUTPUT_DIR
  Mac log:         $OUTPUT_DIR/mac-host.log
  Android log:     $OUTPUT_DIR/android-logcat.log
  H.264 file:      $OUTPUT_DIR/stream.h264
  Decoded frames:  $OUTPUT_DIR/decoded-frames
EOF
