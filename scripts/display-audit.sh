#!/usr/bin/env bash
set -euo pipefail

COUNT_ONLY=0
FAIL_ON_STALE=0

usage() {
    cat <<'EOF'
display-audit.sh

Collects read-only macOS display state for Phase 0 and counts stale Android
Monitor virtual displays. Android Monitor virtual displays use vendor ID
0xEEEE.

Options:
  --count          Print only the stale Android Monitor display count.
  --fail-on-stale Exit 11 if any stale Android Monitor displays are online.
  --help          Show this message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --count)
            COUNT_ONLY=1
            ;;
        --fail-on-stale)
            FAIL_ON_STALE=1
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

count_stale_displays() {
    swift -e 'import CoreGraphics; let maxDisplays: UInt32 = 64; let ids = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(maxDisplays)); var count: UInt32 = 0; CGGetOnlineDisplayList(maxDisplays, ids, &count); var stale = 0; for i in 0..<Int(count) { let id = ids[i]; if id != CGMainDisplayID() && CGDisplayVendorNumber(id) == 0xEEEE { stale += 1 } }; ids.deallocate(); print(stale)'
}

STALE_COUNT="$(count_stale_displays)"

if [[ "$COUNT_ONLY" -eq 1 ]]; then
    printf '%s\n' "$STALE_COUNT"
    exit 0
fi

echo "==> macOS online displays"
swift -e 'import CoreGraphics; let maxDisplays: UInt32 = 64; let ids = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(maxDisplays)); var count: UInt32 = 0; let err = CGGetOnlineDisplayList(maxDisplays, ids, &count); print("CGGetOnlineDisplayList status=\(err.rawValue) count=\(count)"); for i in 0..<Int(count) { let id = ids[i]; let bounds = CGDisplayBounds(id); let marker = id != CGMainDisplayID() && CGDisplayVendorNumber(id) == 0xEEEE ? "ANDROID_MONITOR" : ""; print("id=\(id) \(Int(bounds.origin.x)),\(Int(bounds.origin.y)) \(Int(bounds.width))x\(Int(bounds.height)) vendor=\(CGDisplayVendorNumber(id)) model=\(CGDisplayModelNumber(id)) serial=\(CGDisplaySerialNumber(id)) main=\(id == CGMainDisplayID()) \(marker)") }; ids.deallocate()'

if [[ "$STALE_COUNT" -gt 0 ]]; then
    echo "[WARN] Found $STALE_COUNT stale Android Monitor virtual display(s)."
    echo "       Log out or restart macOS before strict real-capture testing."
else
    echo "[OK] No stale Android Monitor virtual displays found."
fi

if [[ "$FAIL_ON_STALE" -eq 1 && "$STALE_COUNT" -gt 0 ]]; then
    exit 11
fi
