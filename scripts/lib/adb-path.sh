#!/usr/bin/env bash

resolve_adb_bin() {
    local sdk_root
    for sdk_root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk"; do
        if [[ -n "$sdk_root" && -x "$sdk_root/platform-tools/adb" ]]; then
            printf '%s\n' "$sdk_root/platform-tools/adb"
            return 0
        fi
    done

    command -v adb || true
}

require_single_authorized_adb_device() {
    local adb_bin="$1"
    local devices

    if ! devices="$("$adb_bin" devices -l 2>&1 | tr -d '\r')"; then
        printf '%s\n' "$devices"
        echo "[FAIL] adb devices failed. Try: adb kill-server; adb start-server" >&2
        exit 1
    fi

    printf '%s\n' "$devices"

    if [[ -n "${ANDROID_SERIAL:-}" ]]; then
        local selected_state
        selected_state="$(printf '%s\n' "$devices" | awk -v serial="$ANDROID_SERIAL" 'NR > 1 && $1 == serial { print $2; found = 1 } END { if (!found) exit 1 }')" || {
            cat >&2 <<EOF
[FAIL] ANDROID_SERIAL=$ANDROID_SERIAL is set, but adb does not list that serial.
       Run scripts/adb-usb-diagnose.sh, or unset ANDROID_SERIAL and rerun.
EOF
            exit 4
        }

        if [[ "$selected_state" != "device" ]]; then
            cat >&2 <<EOF
[FAIL] ANDROID_SERIAL=$ANDROID_SERIAL is visible, but its adb state is '$selected_state'.
       Unlock the phone, approve USB debugging, or reconnect USB before rerunning.
EOF
            exit 4
        fi
        return
    fi

    local authorized_count unauthorized_count offline_count
    authorized_count="$(printf '%s\n' "$devices" | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')"
    unauthorized_count="$(printf '%s\n' "$devices" | awk 'NR > 1 && $2 == "unauthorized" { count++ } END { print count + 0 }')"
    offline_count="$(printf '%s\n' "$devices" | awk 'NR > 1 && $2 == "offline" { count++ } END { print count + 0 }')"

    if [[ "$authorized_count" -eq 0 ]]; then
        if [[ "$unauthorized_count" -gt 0 ]]; then
            echo "[FAIL] A phone is connected but USB debugging is not authorized. Unlock the phone and approve the USB debugging prompt." >&2
        elif [[ "$offline_count" -gt 0 ]]; then
            echo "[FAIL] A phone is visible to ADB but is offline. Reconnect USB, then run adb kill-server and adb start-server if needed." >&2
        else
            echo "[FAIL] No authorized adb device found." >&2
        fi
        exit 3
    fi

    if [[ "$authorized_count" -gt 1 ]]; then
        cat >&2 <<EOF
[FAIL] Multiple authorized Android devices are connected.
       Set ANDROID_SERIAL=<serial> before rerunning, or disconnect extra devices.
EOF
        printf '%s\n' "$devices" | awk 'NR > 1 && $2 == "device" { print "       " $1 }' >&2
        exit 4
    fi
}
