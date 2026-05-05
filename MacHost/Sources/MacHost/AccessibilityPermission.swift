import ApplicationServices

@discardableResult
func preflightAccessibilityPermissionForInput(requestIfMissing: Bool = false) -> Bool {
    if isAccessibilityPermissionGranted() {
        print("[OK] Accessibility permission is granted for touch input")
        return true
    }

    if requestIfMissing {
        _ = requestAccessibilityPermission()
    }

    let granted = isAccessibilityPermissionGranted()
    if granted {
        print("[OK] Accessibility permission is granted for touch input")
    } else {
        print("[WARN] Accessibility permission is not granted; Android touch input may not control the Mac")
        print("       Grant Accessibility to the terminal or Android Monitor Host app in System Settings.")
    }
    return granted
}

func isAccessibilityPermissionGranted() -> Bool {
    AXIsProcessTrusted()
}

@discardableResult
func requestAccessibilityPermission() -> Bool {
    let options = [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}
