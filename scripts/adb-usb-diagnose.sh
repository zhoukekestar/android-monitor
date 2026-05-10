#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
. "$ROOT_DIR/scripts/lib/adb-path.sh"

adb_bin="$(resolve_adb_bin)"

echo "==> ADB binary"
if [[ -z "$adb_bin" ]]; then
    echo "[FAIL] adb was not found from ANDROID_HOME, ANDROID_SDK_ROOT, PATH, or ~/Library/Android/sdk/platform-tools/adb."
    echo "       Install Android SDK Platform-Tools in Android Studio."
    exit 0
fi
echo "$adb_bin"
"$adb_bin" version | sed -n '1,3p'

echo "==> ADB devices"
set +e
adb_devices="$("$adb_bin" devices -l 2>&1 | tr -d '\r')"
adb_status=$?
set -e
printf '%s\n' "$adb_devices"

if [[ "$adb_status" -ne 0 ]]; then
    echo "[FAIL] adb devices failed. Try: adb kill-server; adb start-server"
    exit 0
fi

authorized_count="$(printf '%s\n' "$adb_devices" | awk 'NR > 1 && $2 == "device" { count++ } END { print count + 0 }')"
unauthorized_count="$(printf '%s\n' "$adb_devices" | awk 'NR > 1 && $2 == "unauthorized" { count++ } END { print count + 0 }')"
offline_count="$(printf '%s\n' "$adb_devices" | awk 'NR > 1 && $2 == "offline" { count++ } END { print count + 0 }')"
row_count="$(printf '%s\n' "$adb_devices" | awk 'NR > 1 && NF > 0 { count++ } END { print count + 0 }')"

if [[ -n "${ANDROID_SERIAL:-}" ]] && ! printf '%s\n' "$adb_devices" | awk -v serial="$ANDROID_SERIAL" 'NR > 1 && $1 == serial { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "[WARN] ANDROID_SERIAL=$ANDROID_SERIAL is set, but adb does not list that serial."
fi

if [[ "$authorized_count" -gt 0 ]]; then
    echo "[OK] At least one authorized ADB device is available."
elif [[ "$unauthorized_count" -gt 0 ]]; then
    echo "[ACTION] Unlock the phone and approve the USB debugging prompt."
    echo "         If no prompt appears, revoke USB debugging authorizations on the phone and reconnect USB."
elif [[ "$offline_count" -gt 0 ]]; then
    echo "[ACTION] The device is offline. Reconnect USB, then run: adb kill-server; adb start-server"
elif [[ "$row_count" -eq 0 ]]; then
    echo "[ACTION] adb sees no device rows."
fi

if [[ "$(uname -s)" != "Darwin" ]] || ! command -v ioreg >/dev/null 2>&1; then
    exit 0
fi

echo "==> macOS USB devices"
usb_summary="$(ioreg -p IOUSB -l -w 0 | awk -F'= ' '
    /"USB Product Name"/ {
        product = $2
        gsub(/^"/, "", product)
        gsub(/"$/, "", product)
    }
    /"USB Vendor Name"/ {
        vendor = $2
        gsub(/^"/, "", vendor)
        gsub(/"$/, "", vendor)
        if (product != "") {
            print vendor " - " product
            product = ""
        }
    }
')"

if [[ -z "$usb_summary" ]]; then
    echo "[INFO] No named USB devices were reported by ioreg."
    exit 0
fi

printf '%s\n' "$usb_summary"

if [[ "$authorized_count" -gt 0 ]]; then
    echo "[OK] ADB is already authorized; USB product-name matching is informational only."
elif printf '%s\n' "$usb_summary" | grep -Eiq 'Android|ADB|Samsung|Xiaomi|Redmi|Huawei|Honor|OPPO|OnePlus|vivo|Google|Pixel|Motorola|Lenovo|Sony|HTC|LG|ZTE|MediaTek|Qualcomm'; then
    if [[ "$authorized_count" -eq 0 ]]; then
        echo "[ACTION] macOS can see a phone-like USB device, but adb cannot use it."
        echo "         On the phone, switch USB mode to File Transfer, MIDI, or PTP, enable USB debugging, then approve the prompt."
    fi
else
    echo "[ACTION] macOS does not show an Android-like USB device."
    echo "         Use a data-capable USB cable, avoid unpowered hubs, unlock the phone, and change USB mode from charge-only to file transfer."
fi
