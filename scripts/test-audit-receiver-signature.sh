#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/android-monitor-signature-test.XXXXXX")"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SDK_DIR="$TMP_DIR/sdk"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$SDK_DIR/platform-tools" "$BIN_DIR"

cat >"$SDK_DIR/platform-tools/adb" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    devices)
        printf 'List of devices attached\nabc123 device model:FakePhone\n'
        ;;
    shell)
        if [[ "${2:-}" == "pm" && "${3:-}" == "path" ]]; then
            printf 'package:/data/app/com.androidmonitor.receiver/base.apk\n'
        else
            echo "unexpected fake adb shell command: $*" >&2
            exit 99
        fi
        ;;
    pull)
        cp "$FAKE_INSTALLED_APK" "$3"
        printf '%s: 1 file pulled, 0 skipped.\n' "$2"
        ;;
    *)
        echo "unexpected fake adb command: $*" >&2
        exit 99
        ;;
esac
EOF
chmod +x "$SDK_DIR/platform-tools/adb"

cat >"$BIN_DIR/apksigner" <<'EOF'
#!/usr/bin/env bash
apk="${@: -1}"
marker="$(cat "$apk")"
case "$marker" in
    same)
        digest="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ;;
    current)
        digest="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        ;;
    installed)
        digest="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
        ;;
    *)
        digest="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
        ;;
esac
cat <<EOF2
V2 Signer: certificate DN: C=US, O=Android, CN=Android Debug
V2 Signer: certificate SHA-256 digest: $digest
V2 Signer: certificate SHA-1 digest: 0000000000000000000000000000000000000000
EOF2
EOF
chmod +x "$BIN_DIR/apksigner"

run_case() {
    local name="$1"
    local expected_status="$2"
    local current_marker="$3"
    local installed_marker="$4"
    shift 4

    local current_apk="$TMP_DIR/current-$name.apk"
    local installed_apk="$TMP_DIR/installed-$name.apk"
    printf '%s' "$current_marker" >"$current_apk"
    printf '%s' "$installed_marker" >"$installed_apk"

    set +e
    output="$(ANDROID_HOME="$SDK_DIR" PATH="$BIN_DIR:$PATH" FAKE_INSTALLED_APK="$installed_apk" scripts/audit-receiver-signature.sh --apk "$current_apk" "$@" 2>&1)"
    status=$?
    set -e

    if [[ "$status" -ne "$expected_status" ]]; then
        printf '[FAIL] %s expected status %s, got %s\n%s\n' "$name" "$expected_status" "$status" "$output" >&2
        exit 1
    fi
    printf '[OK] %s\n' "$name"
}

run_case "matching-certificates" 0 same same
run_case "mismatch-warns" 0 current installed
run_case "mismatch-strict-fails" 5 current installed --fail-on-mismatch

echo "[OK] Signature audit helper tests passed."
