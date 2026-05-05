#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="/tmp/android-monitor-runtime-gates"
STABILITY_DURATION=3600
SKIP_STABILITY=0
SKIP_PHASE0=0
SKIP_PHASE1=0
SKIP_RECONNECT=0

usage() {
    cat <<'EOF'
post-restart-runtime-gates.sh

Runs the capture-dependent acceptance gates after logout/restart clears stale
Android Monitor virtual displays. This script refuses to continue if stale
virtual displays are still online.

Default sequence:
  1. scripts/display-audit.sh --fail-on-stale
  2. scripts/phase0-real-capture-check.sh
  3. scripts/phase1-window-freshness-check.sh
  4. scripts/phase1-reconnect-check.sh
  5. scripts/phase2-stability-check.sh --duration 3600

Options:
  --output-root <path>        Default: /tmp/android-monitor-runtime-gates
  --stability-duration <sec>  Default: 3600. Use 120 for a smoke.
  --skip-stability           Skip the Phase 2 stability gate.
  --skip-phase0              Skip the Phase 0 strict real-capture gate.
  --skip-phase1              Skip the Phase 1 visual freshness gate.
  --skip-reconnect           Skip the Phase 1 reconnect gate.
  --help                     Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-root)
            OUTPUT_ROOT="${2:?--output-root requires a value}"
            shift
            ;;
        --stability-duration)
            STABILITY_DURATION="${2:?--stability-duration requires a value}"
            shift
            ;;
        --skip-stability)
            SKIP_STABILITY=1
            ;;
        --skip-phase0)
            SKIP_PHASE0=1
            ;;
        --skip-phase1)
            SKIP_PHASE1=1
            ;;
        --skip-reconnect)
            SKIP_RECONNECT=1
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

if ! [[ "$STABILITY_DURATION" =~ ^[0-9]+$ ]] || [[ "$STABILITY_DURATION" -le 0 ]]; then
    echo "[FAIL] --stability-duration must be a positive integer: $STABILITY_DURATION" >&2
    exit 2
fi

mkdir -p "$OUTPUT_ROOT"
SUMMARY="$OUTPUT_ROOT/runtime-gates-summary.txt"
rm -f "$SUMMARY"

log_step() {
    printf '\n==> %s\n' "$1" | tee -a "$SUMMARY"
}

run_step() {
    local name="$1"
    shift
    log_step "$name"
    {
        printf 'Command:'
        printf ' %q' "$@"
        printf '\n'
    } | tee -a "$SUMMARY"
    "$@"
    printf '[OK] %s\n' "$name" | tee -a "$SUMMARY"
}

run_step "Audit stale virtual displays" "$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale

if [[ "$SKIP_PHASE0" -eq 0 ]]; then
    run_step "Phase 0 strict real capture" \
        "$ROOT_DIR/scripts/phase0-real-capture-check.sh" \
        --output-dir "$OUTPUT_ROOT/phase0-real-capture"
fi

if [[ "$SKIP_PHASE1" -eq 0 ]]; then
    run_step "Phase 1 normal-window freshness" \
        "$ROOT_DIR/scripts/phase1-window-freshness-check.sh" \
        --output-dir "$OUTPUT_ROOT/phase1-window-freshness"
fi

if [[ "$SKIP_RECONNECT" -eq 0 ]]; then
    run_step "Phase 1 reconnect" \
        "$ROOT_DIR/scripts/phase1-reconnect-check.sh" \
        --output-dir "$OUTPUT_ROOT/phase1-reconnect"
fi

if [[ "$SKIP_STABILITY" -eq 0 ]]; then
    run_step "Phase 2 stability" \
        "$ROOT_DIR/scripts/phase2-stability-check.sh" \
        --duration "$STABILITY_DURATION" \
        --output-dir "$OUTPUT_ROOT/phase2-stability"
fi

cat <<EOF | tee -a "$SUMMARY"

[OK] Runtime gate sequence completed.

Artifacts:
  Summary:      $SUMMARY
  Output root:  $OUTPUT_ROOT

Manual follow-up still required:
  - Grant Accessibility to the launcher used for MacHost.
  - Run scripts/touch-real-display-phone-smoke.sh --skip-install --require-scroll.
  - Run scripts/cursor-capture-smoke.sh.
EOF
