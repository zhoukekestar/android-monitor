#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/scripts/lib/adb-path.sh"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/android-monitor-adb-helper-test.XXXXXX")"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

FAKE_ADB="$TMP_DIR/fake-adb"
cat >"$FAKE_ADB" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "devices" ]]; then
    echo "unexpected fake adb command: $*" >&2
    exit 99
fi
printf '%b\n' "${FAKE_ADB_DEVICES:-List of devices attached\n}"
EOF
chmod +x "$FAKE_ADB"

run_case() {
    local name="$1"
    local expected_status="$2"
    local devices="$3"
    local serial="${4:-}"

    set +e
    if [[ -n "$serial" ]]; then
        output="$(ANDROID_SERIAL="$serial" FAKE_ADB_DEVICES="$devices" bash -c '. scripts/lib/adb-path.sh; require_single_authorized_adb_device "$0"' "$FAKE_ADB" 2>&1)"
    else
        output="$(FAKE_ADB_DEVICES="$devices" bash -c '. scripts/lib/adb-path.sh; require_single_authorized_adb_device "$0"' "$FAKE_ADB" 2>&1)"
    fi
    status=$?
    set -e

    if [[ "$status" -ne "$expected_status" ]]; then
        printf '[FAIL] %s expected status %s, got %s\n%s\n' "$name" "$expected_status" "$status" "$output" >&2
        exit 1
    fi
    printf '[OK] %s\n' "$name"
}

run_case "single authorized device" 0 $'List of devices attached\nabc123 device model:Phone\n'
run_case "no devices" 3 $'List of devices attached\n'
run_case "unauthorized device" 3 $'List of devices attached\nabc123 unauthorized model:Phone\n'
run_case "offline device" 3 $'List of devices attached\nabc123 offline model:Phone\n'
run_case "multiple authorized devices require serial" 4 $'List of devices attached\nabc123 device model:One\nxyz789 device model:Two\n'
run_case "selected authorized serial" 0 $'List of devices attached\nabc123 device model:One\nxyz789 device model:Two\n' "xyz789"
run_case "selected missing serial" 4 $'List of devices attached\nabc123 device model:One\n' "missing"
run_case "selected unauthorized serial" 4 $'List of devices attached\nabc123 unauthorized model:One\n' "abc123"

echo "[OK] ADB device helper tests passed."
