import AppKit
import CoreGraphics
import Foundation
import CGVirtualDisplayBridge

final class VirtualDisplay {
    let displayID: CGDirectDisplayID
    private var display: CGVirtualDisplay?
    private var descriptor: CGVirtualDisplayDescriptor?
    private var settings: CGVirtualDisplaySettings?

    init(width: Int, height: Int, refreshRate: Double, name: String) throws {
        guard width > 0 && height > 0 else {
            throw SpikeError.virtualDisplay("invalid size \(width)x\(height)")
        }

        let displayDescriptor = CGVirtualDisplayDescriptor()
        displayDescriptor.name = name
        displayDescriptor.maxPixelsWide = UInt32(width)
        displayDescriptor.maxPixelsHigh = UInt32(height)
        displayDescriptor.vendorID = 0xEEEE
        let stableProductID = UInt32((width * 10_000 + height) & 0xFFFFFFFF)
        displayDescriptor.productID = stableProductID
        displayDescriptor.serialNum = 0x0001

        let millimetersPerPixel = 25.4 / 110.0
        displayDescriptor.sizeInMillimeters = CGSize(
            width: Double(width) * millimetersPerPixel,
            height: Double(height) * millimetersPerPixel
        )

        let createdDisplay: CGVirtualDisplay
        if let stableDisplay = CGVirtualDisplay(descriptor: displayDescriptor) {
            createdDisplay = stableDisplay
        } else {
            let processSalt = UInt32(ProcessInfo.processInfo.processIdentifier & 0xFFFF)
            displayDescriptor.productID = stableProductID ^ processSalt
            displayDescriptor.serialNum = processSalt
            guard let saltedDisplay = CGVirtualDisplay(descriptor: displayDescriptor) else {
                throw SpikeError.virtualDisplay("CGVirtualDisplay init returned nil")
            }
            print("[WARN] Stable virtual display identity was unavailable; using process-scoped identity")
            createdDisplay = saltedDisplay
        }

        let displaySettings = CGVirtualDisplaySettings()
        displaySettings.hiDPI = 0
        let modes = [
            CGVirtualDisplayMode(
                width: UInt32(width),
                height: UInt32(height),
                refreshRate: refreshRate
            )
        ]
        displaySettings.modes = modes

        guard createdDisplay.apply(displaySettings) else {
            throw SpikeError.virtualDisplay("applySettings failed")
        }

        display = createdDisplay
        descriptor = displayDescriptor
        settings = displaySettings
        displayID = CGDirectDisplayID(createdDisplay.displayID)
    }

    func destroy(waitSeconds: TimeInterval = 3) {
        guard display != nil else {
            return
        }

        display = nil
        descriptor = nil
        settings = nil

        let deadline = Date().addingTimeInterval(waitSeconds)
        while isOnline() && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        if isOnline() {
            print("[WARN] Virtual display ID \(displayID) is still online after release")
        } else {
            print("[OK] Virtual display ID \(displayID) released")
        }
    }

    deinit {
        destroy(waitSeconds: 0)
    }

    func isOnline() -> Bool {
        let maxDisplays: UInt32 = 32
        let displays = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(maxDisplays))
        defer { displays.deallocate() }

        var count: UInt32 = 0
        let result = CGGetOnlineDisplayList(maxDisplays, displays, &count)
        guard result == .success else {
            return false
        }

        for index in 0..<Int(count) where displays[index] == displayID {
            return true
        }
        return false
    }

    func pixelSize() -> (width: Int, height: Int) {
        (
            width: Int(CGDisplayPixelsWide(displayID)),
            height: Int(CGDisplayPixelsHigh(displayID))
        )
    }
}
