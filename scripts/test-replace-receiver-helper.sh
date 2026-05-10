#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/android-monitor-replace-test.XXXXXX")"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_expect_status() {
    local name="$1"
    local expected_status="$2"
    shift 2

    set +e
    output="$("$@" 2>&1)"
    status=$?
    set -e

    if [[ "$status" -ne "$expected_status" ]]; then
        printf '[FAIL] %s expected status %s, got %s\n%s\n' "$name" "$expected_status" "$status" "$output" >&2
        exit 1
    fi
    printf '[OK] %s\n' "$name"
}

assert_contains() {
    local name="$1"
    local needle="$2"
    local haystack="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf '[FAIL] %s expected output to contain: %s\n%s\n' "$name" "$needle" "$haystack" >&2
        exit 1
    fi
}

assert_log_equals() {
    local name="$1"
    local expected="$2"
    local log_path="$3"
    local actual=""

    if [[ -f "$log_path" ]]; then
        actual="$(cat "$log_path")"
    fi

    if [[ "$actual" != "$expected" ]]; then
        printf '[FAIL] %s expected call log:\n%s\nactual:\n%s\n' "$name" "$expected" "$actual" >&2
        exit 1
    fi
    printf '[OK] %s\n' "$name"
}

write_fake_helpers() {
    cat >"$TMP_DIR/audit" <<'EOF'
#!/usr/bin/env bash
printf 'audit:%s\n' "$*" >>"$CALL_LOG"
exit "$AUDIT_STATUS"
EOF
    chmod +x "$TMP_DIR/audit"

    cat >"$TMP_DIR/gradlew" <<'EOF'
#!/usr/bin/env bash
printf 'gradle:%s\n' "$*" >>"$CALL_LOG"
exit 0
EOF
    chmod +x "$TMP_DIR/gradlew"

    cat >"$TMP_DIR/verify" <<'EOF'
#!/usr/bin/env bash
printf 'verify:%s\n' "$*" >>"$CALL_LOG"
exit 0
EOF
    chmod +x "$TMP_DIR/verify"
}

run_replace_with_fakes() {
    local name="$1"
    local expected_status="$2"
    local audit_status="$3"
    local expected_log="$4"
    shift 4

    local call_log="$TMP_DIR/$name.calls"

    run_expect_status "$name" "$expected_status" env \
        AUDIT_RECEIVER_SIGNATURE_SCRIPT="$TMP_DIR/audit" \
        GRADLEW="$TMP_DIR/gradlew" \
        VERIFY_DEVICE_RUNTIME_SCRIPT="$TMP_DIR/verify" \
        CALL_LOG="$call_log" \
        AUDIT_STATUS="$audit_status" \
        scripts/replace-android-receiver.sh "$@"

    assert_log_equals "$name call order" "$expected_log" "$call_log"
}

write_fake_helpers

run_expect_status "replace refuses without confirmation" 2 scripts/replace-android-receiver.sh
run_expect_status "replace dry-run is non-destructive" 0 env \
    AUDIT_RECEIVER_SIGNATURE_SCRIPT="$TMP_DIR/audit" \
    GRADLEW="$TMP_DIR/gradlew" \
    VERIFY_DEVICE_RUNTIME_SCRIPT="$TMP_DIR/verify" \
    scripts/replace-android-receiver.sh --confirm-uninstall --dry-run
assert_contains "replace dry-run shows resolved audit command" "$TMP_DIR/audit --fail-on-mismatch" "$output"

run_replace_with_fakes "replace refuses when signatures match" 6 0 \
    $'audit:--fail-on-mismatch' \
    --confirm-uninstall

run_replace_with_fakes "replace skips uninstall when receiver absent" 0 3 \
    $'audit:--fail-on-mismatch\nverify:' \
    --confirm-uninstall

run_replace_with_fakes "replace uninstalls only after mismatch" 0 5 \
    $'audit:--fail-on-mismatch\ngradle:uninstallReceiverDebug --console=plain\nverify:' \
    --confirm-uninstall

run_replace_with_fakes "replace refuses unexpected audit failure" 9 9 \
    $'audit:--fail-on-mismatch' \
    --confirm-uninstall

echo "[OK] Replace receiver helper tests passed."
