#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    cat <<'EOF'
phase0-real-capture-check.sh

Runs the strict post-restart Phase 0 real-capture gate. This refuses to create
another virtual display if stale Android Monitor virtual displays are already
online, then runs phase0-stream-test.sh with host-owned animated test content
and synthetic fallback disabled as an acceptable result.

Any extra arguments are passed through to phase0-stream-test.sh after the
strict defaults, so they can override width, height, fps, bitrate, duration,
port, or output directory.

Default delegated command:
  scripts/phase0-stream-test.sh --width 1024 --height 600 --fps 15 --bitrate-mbps 2 --duration 10 --test-content-window --require-real-capture

Options:
  --help    Show this message.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

"$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale

"$ROOT_DIR/scripts/phase0-stream-test.sh" \
    --width 1024 \
    --height 600 \
    --fps 15 \
    --bitrate-mbps 2 \
    --duration 10 \
    --test-content-window \
    --require-real-capture \
    --min-decoded-frames 30 \
    --min-input-fps 10 \
    "$@"
