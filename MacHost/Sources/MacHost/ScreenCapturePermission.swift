import CoreGraphics
import Foundation

func preflightScreenCapturePermission(requestIfMissing: Bool) -> Bool {
    if CGPreflightScreenCaptureAccess() {
        print("[OK] Screen capture permission is granted")
        return true
    }

    print("[WARN] Screen capture permission is not granted")
    print("       Grant Screen/System Audio Recording to the terminal or app launching phase0-spike.")

    guard requestIfMissing else {
        print("       Re-run with --request-screen-capture-permission to ask macOS for access.")
        return false
    }

    print("[INFO] Requesting screen capture permission from macOS...")
    let granted = CGRequestScreenCaptureAccess()
    if granted {
        print("[OK] macOS reported screen capture permission granted")
    } else {
        print("[WARN] macOS did not grant permission yet")
        print("       If you changed the setting, quit and reopen the launching terminal before retrying.")
    }
    return granted
}
