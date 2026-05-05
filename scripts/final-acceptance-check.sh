#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_ROOT="/tmp/android-monitor-final-acceptance"
STABILITY_DURATION=3600
SKIP_INSTALL=0
SKIP_BUILD=0
SKIP_STATUS=0
SKIP_RUNTIME=0
SKIP_CURSOR=0
SKIP_TOUCH=0
REQUIRE_SCROLL=1
SCROLL_TIMEOUT=120

usage() {
    cat <<'EOF'
final-acceptance-check.sh

Runs the end-to-end PLAN acceptance sequence after logout/restart clears stale
Android Monitor virtual displays. The default run performs build/package checks,
Status Panel smokes, strict real-capture runtime gates including one-hour
stability, post-run cleanup audits, cursor-capture verification, and real
Android touch/scroll verification.

Options:
  --output-root <path>        Default: /tmp/android-monitor-final-acceptance
  --stability-duration <sec>  Default: 3600. Use 120 only for a short smoke.
  --skip-install             Do not install the debug APK in phone smokes.
  --skip-build               Skip phase0-check/package/status build checks.
  --skip-status              Skip Status Panel localhost and phone smokes.
  --skip-runtime             Skip post-restart real-capture runtime gates.
  --skip-cursor              Skip cursor-capture smoke.
  --skip-touch               Skip real-display touch smoke.
  --no-require-scroll        Do not require manual two-finger scroll in touch smoke.
  --scroll-timeout <sec>     Seconds to wait for manual scroll. Default: 120.
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
        --skip-install)
            SKIP_INSTALL=1
            ;;
        --skip-build)
            SKIP_BUILD=1
            ;;
        --skip-status)
            SKIP_STATUS=1
            ;;
        --skip-runtime)
            SKIP_RUNTIME=1
            ;;
        --skip-cursor)
            SKIP_CURSOR=1
            ;;
        --skip-touch)
            SKIP_TOUCH=1
            ;;
        --no-require-scroll)
            REQUIRE_SCROLL=0
            ;;
        --scroll-timeout)
            SCROLL_TIMEOUT="${2:?--scroll-timeout requires a value}"
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

if ! [[ "$STABILITY_DURATION" =~ ^[0-9]+$ ]] || [[ "$STABILITY_DURATION" -le 0 ]]; then
    echo "[FAIL] --stability-duration must be a positive integer: $STABILITY_DURATION" >&2
    exit 2
fi
if ! [[ "$SCROLL_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$SCROLL_TIMEOUT" -le 0 ]]; then
    echo "[FAIL] --scroll-timeout must be a positive integer: $SCROLL_TIMEOUT" >&2
    exit 2
fi

mkdir -p "$OUTPUT_ROOT"
SUMMARY="$OUTPUT_ROOT/final-acceptance-summary.txt"
MANIFEST="$OUTPUT_ROOT/final-acceptance-manifest.json"
rm -f "$SUMMARY" "$MANIFEST"

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

PHONE_SMOKE_INSTALL_ARGS=()
if [[ "$SKIP_INSTALL" -eq 1 ]]; then
    PHONE_SMOKE_INSTALL_ARGS+=(--skip-install)
fi

run_step "Initial stale-display audit" \
    "$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    PHASE0_ARGS=()
    if [[ "$SKIP_INSTALL" -eq 1 ]]; then
        PHASE0_ARGS+=(--skip-install)
    fi
    run_step "Phase 0 build/protocol/device setup" \
        "$ROOT_DIR/scripts/phase0-check.sh" "${PHASE0_ARGS[@]}"
    run_step "Package Mac host app" \
        "$ROOT_DIR/scripts/package-mac-host-app.sh"
fi

if [[ "$SKIP_STATUS" -eq 0 ]]; then
    run_step "Status Panel localhost smoke" \
        "$ROOT_DIR/scripts/status-panel-smoke.sh" \
        --port 38989
    run_step "Status Panel phone smoke" \
        "$ROOT_DIR/scripts/status-panel-phone-smoke.sh" \
        "${PHONE_SMOKE_INSTALL_ARGS[@]}" \
        --output-dir "$OUTPUT_ROOT/status-panel-phone"
fi

if [[ "$SKIP_RUNTIME" -eq 0 ]]; then
    run_step "Post-restart runtime gates" \
        "$ROOT_DIR/scripts/post-restart-runtime-gates.sh" \
        --stability-duration "$STABILITY_DURATION" \
        --output-root "$OUTPUT_ROOT/runtime-gates"
    run_step "Post-runtime cleanup audit" \
        "$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale
fi

if [[ "$SKIP_CURSOR" -eq 0 ]]; then
    run_step "Cursor capture smoke" \
        "$ROOT_DIR/scripts/cursor-capture-smoke.sh" \
        --output-dir "$OUTPUT_ROOT/cursor-capture"
    run_step "Post-cursor cleanup audit" \
        "$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale
fi

if [[ "$SKIP_TOUCH" -eq 0 ]]; then
    TOUCH_ARGS=("${PHONE_SMOKE_INSTALL_ARGS[@]}" --output-dir "$OUTPUT_ROOT/touch-real-display")
    if [[ "$REQUIRE_SCROLL" -eq 1 ]]; then
        TOUCH_ARGS+=(--require-scroll --scroll-timeout "$SCROLL_TIMEOUT")
    fi
    run_step "Real-display touch smoke" \
        "$ROOT_DIR/scripts/touch-real-display-phone-smoke.sh" \
        "${TOUCH_ARGS[@]}"
    run_step "Post-touch cleanup audit" \
        "$ROOT_DIR/scripts/display-audit.sh" --fail-on-stale
fi

python3 - "$MANIFEST" "$OUTPUT_ROOT" "$SUMMARY" "$STABILITY_DURATION" \
    "$SKIP_BUILD" "$SKIP_STATUS" "$SKIP_RUNTIME" "$SKIP_CURSOR" "$SKIP_TOUCH" "$REQUIRE_SCROLL" "$SCROLL_TIMEOUT" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
output_root = Path(sys.argv[2])
summary = Path(sys.argv[3])
stability_duration = int(sys.argv[4])
skip_build = sys.argv[5] == "1"
skip_status = sys.argv[6] == "1"
skip_runtime = sys.argv[7] == "1"
skip_cursor = sys.argv[8] == "1"
skip_touch = sys.argv[9] == "1"
require_scroll = sys.argv[10] == "1"
scroll_timeout = int(sys.argv[11])

def item(requirement, status, evidence):
    return {
        "requirement": requirement,
        "status": status,
        "evidence": [str(path) for path in evidence],
    }

runtime = output_root / "runtime-gates"
cursor = output_root / "cursor-capture"
touch = output_root / "touch-real-display"
status_phone = output_root / "status-panel-phone"

manifest = {
    "objective": "PLAN.md final acceptance for Android 5 phone as macOS extended display",
    "summary": str(summary),
    "output_root": str(output_root),
    "stability_duration_seconds": stability_duration,
    "scroll_required": require_scroll and not skip_touch,
    "scroll_timeout_seconds": scroll_timeout if require_scroll and not skip_touch else 0,
    "skips": {
        "build": skip_build,
        "status": skip_status,
        "runtime": skip_runtime,
        "cursor": skip_cursor,
        "touch": skip_touch,
    },
    "requirements": [
        item("Mac virtual display creation and real capture", "verified" if not skip_runtime else "skipped", [
            runtime / "phase0-real-capture" / "mac-host.log",
            runtime / "phase1-window-freshness" / "mac-host.log",
            runtime / "phase2-stability" / "mac-host.log",
        ]),
        item("H.264 Annex-B encode and Android 5 decode over USB", "verified" if not skip_runtime else "skipped", [
            runtime / "phase0-real-capture" / "stream.h264",
            runtime / "phase0-real-capture" / "android-logcat.log",
            runtime / "phase2-stability" / "stream.h264",
            runtime / "phase2-stability" / "android-logcat.log",
        ]),
        item("Reconnect without restarting MacHost", "verified" if not skip_runtime else "skipped", [
            runtime / "phase1-reconnect" / "mac-host.log",
            runtime / "phase1-reconnect" / "android-logcat.log",
        ]),
        item("One-hour stability and cleanup audits", "verified" if not skip_runtime else "skipped", [
            runtime / "runtime-gates-summary.txt",
            runtime / "phase2-stability" / "mac-host.log",
            summary,
        ]),
        item("Cursor visibility in captured stream", "verified" if not skip_cursor else "skipped", [
            cursor / "mac-host.log",
            cursor / "stream.h264",
            cursor / "decoded-frames",
        ]),
        item("Android tap, drag, and scroll input on real virtual display", "verified" if not skip_touch else "skipped", [
            touch / "mac-host.log",
            touch / "android-input-logcat.log",
            touch / "stream.h264",
        ]),
        item("Status Panel fallback", "verified" if not skip_status else "skipped", [
            Path("/tmp/android-monitor-status-panel-smoke/status-snapshot.json"),
            status_phone / "status-panel-server.log",
            status_phone / "android-status-logcat.log",
        ]),
        item("Build, tests, package, and stream protocol", "verified" if not skip_build else "skipped", [
            Path("MacHost/build/Android Monitor Host.app"),
            Path("AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk"),
            Path("/tmp/android-monitor-phase0-protocol.log"),
        ]),
    ],
}

manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

cat <<EOF | tee -a "$SUMMARY"

[OK] Final acceptance sequence completed.

Artifacts:
  Summary:       $SUMMARY
  Manifest JSON: $MANIFEST
  Output root:   $OUTPUT_ROOT

Use docs/completion-audit.md to record the final evidence before marking the
PLAN.md goal complete.
EOF
