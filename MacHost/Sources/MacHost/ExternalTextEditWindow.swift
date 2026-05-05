import CoreGraphics
import Foundation

final class ExternalTextEditWindow {
    private static let marker = "ANDROID MONITOR TEXTEDIT WINDOW TEST"
    private var process: Process?

    private let left: Int
    private let top: Int
    private let right: Int
    private let bottom: Int
    private let tickCount: Int

    init(displayID: CGDirectDisplayID, durationSeconds: TimeInterval) {
        let bounds = CGDisplayBounds(displayID)
        let width = max(320, min(Int(bounds.width) - 100, 900))
        let height = max(240, min(Int(bounds.height) - 140, 420))
        left = Int(bounds.minX) + 50
        top = Int(bounds.minY) + 70
        right = left + width
        bottom = top + height
        tickCount = max(6, Int(durationSeconds * 2))
    }

    func start() {
        let script = """
        set leftPos to \(left)
        set topPos to \(top)
        set rightPos to \(right)
        set bottomPos to \(bottom)
        set tickCount to \(tickCount)
        set markerText to "\(Self.marker)"

        tell application "TextEdit"
            activate
            set docRef to make new document with properties {text:markerText}
            set bounds of front window to {leftPos, topPos, rightPos, bottomPos}
        end tell

        repeat with i from 1 to tickCount
            tell application "TextEdit"
                try
                    set text of docRef to markerText & return & "frame " & i & return & (current date as text) & return & "Readable normal app window on the virtual display"
                    set bounds of front window to {leftPos, topPos, rightPos, bottomPos}
                end try
            end tell
            delay 0.5
        end repeat

        tell application "TextEdit"
            try
                if text of docRef begins with markerText then close docRef saving no
            end try
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            self.process = process
            print("[OK] External TextEdit test window launched at \(left),\(top) \(right - left)x\(bottom - top)")
        } catch {
            print("[WARN] Could not launch external TextEdit test window: \(error)")
        }
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        closeMarkedTextEditDocuments()
        process = nil
    }

    deinit {
        stop()
    }

    private func closeMarkedTextEditDocuments() {
        let script = """
        tell application "TextEdit"
            repeat with docRef in documents
                try
                    if text of docRef begins with "\(Self.marker)" then close docRef saving no
                end try
            end repeat
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }
}
