#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAC_DIR="$ROOT_DIR/MacHost"
PORT="${STATUS_PANEL_PORT:-38889}"
OUTPUT_DIR="/tmp/android-monitor-status-panel-smoke"
LOG_FILE="$OUTPUT_DIR/status-panel-server.log"
SNAPSHOT_FILE="$OUTPUT_DIR/status-snapshot.json"

usage() {
    cat <<'EOF'
status-panel-smoke.sh

Builds and starts the Mac status-panel server without creating a virtual display,
then validates one localhost status_snapshot JSON line.

Options:
  --port <port>   Default: 38889, or STATUS_PANEL_PORT.
  --help          Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)
            PORT="${2:?--port requires a value}"
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

mkdir -p "$OUTPUT_DIR"
rm -f "$LOG_FILE" "$SNAPSHOT_FILE"

SERVER_PID=""
cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
        kill "$SERVER_PID" >/dev/null 2>&1 || true
        wait "$SERVER_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "==> Building status-panel server"
(cd "$MAC_DIR" && swift build --product status-panel-server)

echo "==> Starting status-panel server on localhost:$PORT"
(cd "$ROOT_DIR" && "$MAC_DIR/.build/debug/status-panel-server" "$PORT") >"$LOG_FILE" 2>&1 &
SERVER_PID=$!

python3 - "$PORT" "$SNAPSHOT_FILE" <<'PY'
import json
import socket
import sys
import time

port = int(sys.argv[1])
snapshot_path = sys.argv[2]
deadline = time.monotonic() + 10.0
last_error = None

while time.monotonic() < deadline:
    try:
        sock = socket.create_connection(("127.0.0.1", port), timeout=0.5)
        break
    except OSError as error:
        last_error = error
        time.sleep(0.1)
else:
    raise SystemExit(f"[FAIL] Could not connect to status panel: {last_error}")

with sock:
    sock.settimeout(5.0)
    data = bytearray()
    while True:
        chunk = sock.recv(1)
        if not chunk:
            raise SystemExit("[FAIL] Status panel closed before snapshot")
        if chunk == b"\n":
            break
        data.extend(chunk)

snapshot = json.loads(data.decode("utf-8"))
required = ["type", "host", "timestamp", "uptime_seconds", "command_output", "build_status", "log_tail"]
for key in required:
    if key not in snapshot:
        raise SystemExit(f"[FAIL] Missing status snapshot field: {key}")
if snapshot["type"] != "status_snapshot":
    raise SystemExit(f"[FAIL] Unexpected status snapshot type: {snapshot['type']!r}")

with open(snapshot_path, "w", encoding="utf-8") as out:
    json.dump(snapshot, out, indent=2, sort_keys=True)
    out.write("\n")

print(
    "[OK] Status snapshot: "
    f"host={snapshot.get('host')} "
    f"uptime_seconds={snapshot.get('uptime_seconds')} "
    f"build_status_bytes={len(snapshot.get('build_status', ''))}"
)
PY

echo "[OK] Snapshot written to $SNAPSHOT_FILE"
