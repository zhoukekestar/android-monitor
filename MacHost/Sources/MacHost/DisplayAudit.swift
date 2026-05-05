import CoreGraphics
import Foundation

struct DisplayAudit {
    static let androidMonitorVendorID: UInt32 = 0xEEEE

    let displays: [DisplayInfo]

    var staleAndroidMonitorDisplayCount: Int {
        displays.filter { $0.isAndroidMonitorVirtualDisplay }.count
    }

    static func current() -> DisplayAudit {
        let maxDisplays: UInt32 = 64
        let onlineDisplays = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: Int(maxDisplays))
        defer { onlineDisplays.deallocate() }

        var displayCount: UInt32 = 0
        let error = CGGetOnlineDisplayList(maxDisplays, onlineDisplays, &displayCount)
        guard error == .success else {
            return DisplayAudit(displays: [])
        }

        let mainDisplayID = CGMainDisplayID()
        let displays = (0..<Int(displayCount)).map { index in
            let displayID = onlineDisplays[index]
            let bounds = CGDisplayBounds(displayID)
            return DisplayInfo(
                id: displayID,
                x: Int(bounds.origin.x),
                y: Int(bounds.origin.y),
                width: Int(bounds.width),
                height: Int(bounds.height),
                vendorID: CGDisplayVendorNumber(displayID),
                modelID: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID),
                isMain: displayID == mainDisplayID
            )
        }
        return DisplayAudit(displays: displays)
    }

    func printReport() {
        print("==> macOS online displays")
        print("display_count=\(displays.count)")
        for display in displays {
            let marker = display.isAndroidMonitorVirtualDisplay ? " ANDROID_MONITOR" : ""
            print(
                "id=\(display.id) "
                    + "\(display.x),\(display.y) "
                    + "\(display.width)x\(display.height) "
                    + "vendor=\(display.vendorID) "
                    + "model=\(display.modelID) "
                    + "serial=\(display.serialNumber) "
                    + "main=\(display.isMain)"
                    + marker
            )
        }

        let staleCount = staleAndroidMonitorDisplayCount
        if staleCount > 0 {
            print("[WARN] Found \(staleCount) stale Android Monitor virtual display(s).")
            print("       Log out or restart macOS before strict real-capture testing.")
        } else {
            print("[OK] No stale Android Monitor virtual displays found.")
        }
    }
}

struct DisplayInfo {
    let id: CGDirectDisplayID
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let vendorID: UInt32
    let modelID: UInt32
    let serialNumber: UInt32
    let isMain: Bool

    var isAndroidMonitorVirtualDisplay: Bool {
        !isMain && vendorID == DisplayAudit.androidMonitorVendorID
    }
}
