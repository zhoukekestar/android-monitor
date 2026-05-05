import AppKit
import CoreGraphics

final class CursorTestWindow {
    private var window: NSWindow?

    init(displayID: CGDirectDisplayID) {
        let targetFrame: NSRect
        if let screen = Self.screen(for: displayID) {
            targetFrame = screen.visibleFrame.insetBy(dx: 60, dy: 60)
        } else {
            let appKitBounds = Self.appKitFrameFromCoreGraphicsBounds(displayID: displayID)
            guard appKitBounds.width > 0 && appKitBounds.height > 0 else {
                print("[WARN] Could not find display bounds for ID \(displayID); cursor test window disabled")
                return
            }
            targetFrame = NSRect(
                x: appKitBounds.minX + 60,
                y: appKitBounds.minY + 60,
                width: appKitBounds.width - 120,
                height: appKitBounds.height - 120
            )
        }

        guard targetFrame.width > 0 && targetFrame.height > 0 else {
            print("[WARN] Cursor test target frame was empty; cursor test window disabled")
            return
        }

        let view = CursorTestContentView(frame: NSRect(x: 0, y: 0, width: targetFrame.width, height: targetFrame.height))
        let window = NSWindow(
            contentRect: targetFrame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Android Monitor Cursor Capture Test"
        window.contentView = view
        window.level = .floating
        window.isReleasedWhenClosed = false

        self.window = window
        print("[INFO] Cursor test window frame: \(Int(targetFrame.minX)),\(Int(targetFrame.minY)) \(Int(targetFrame.width))x\(Int(targetFrame.height))")
    }

    func start() {
        guard let window else {
            return
        }

        window.makeKeyAndOrderFront(nil)
        window.contentView?.needsDisplay = true
        window.contentView?.displayIfNeeded()
        print("[OK] Cursor test window shown on virtual display")
    }

    func stop() {
        window?.close()
        window = nil
    }

    deinit {
        stop()
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        let deadline = Date().addingTimeInterval(3)
        while true {
            if let screen = NSScreen.screens.first(where: { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    return false
                }
                return number.uint32Value == displayID
            }) {
                return screen
            }

            if Date() >= deadline {
                return nil
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private static func appKitFrameFromCoreGraphicsBounds(displayID: CGDirectDisplayID) -> NSRect {
        let bounds = CGDisplayBounds(displayID)
        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        return NSRect(
            x: bounds.origin.x,
            y: mainBounds.height - bounds.origin.y - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }
}

private final class CursorTestContentView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.50, alpha: 1).setFill()
        dirtyRect.fill()

        NSColor(calibratedWhite: 0.35, alpha: 1).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: NSPoint(x: bounds.midX, y: 0))
        path.line(to: NSPoint(x: bounds.midX, y: bounds.height))
        path.move(to: NSPoint(x: 0, y: bounds.midY))
        path.line(to: NSPoint(x: bounds.width, y: bounds.midY))
        path.stroke()

        let text = "Cursor capture target" as NSString
        text.draw(
            at: NSPoint(x: 24, y: max(24, bounds.height - 70)),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 28, weight: .bold),
                .foregroundColor: NSColor.white
            ]
        )
    }
}

final class CursorSweep {
    private let points: [CGPoint]
    private var timer: Timer?
    private var index = 0
    private var originalPoint: CGPoint?

    init(displayID: CGDirectDisplayID) {
        let bounds = CGDisplayBounds(displayID).insetBy(dx: 140, dy: 110)
        if bounds.width <= 0 || bounds.height <= 0 {
            points = []
        } else {
            points = [
                CGPoint(x: bounds.minX + bounds.width * 0.25, y: bounds.minY + bounds.height * 0.25),
                CGPoint(x: bounds.minX + bounds.width * 0.75, y: bounds.minY + bounds.height * 0.25),
                CGPoint(x: bounds.minX + bounds.width * 0.75, y: bounds.minY + bounds.height * 0.75),
                CGPoint(x: bounds.minX + bounds.width * 0.25, y: bounds.minY + bounds.height * 0.75),
                CGPoint(x: bounds.midX, y: bounds.midY)
            ]
        }
    }

    func start() {
        guard !points.isEmpty else {
            print("[WARN] Cursor sweep disabled because display bounds were empty")
            return
        }

        originalPoint = CGEvent(source: nil)?.location
        moveCursor()

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.moveCursor()
        }
        timer.tolerance = 0.02
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
        print("[OK] Cursor sweep started on virtual display")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let originalPoint {
            _ = CGWarpMouseCursorPosition(originalPoint)
        }
    }

    deinit {
        stop()
    }

    private func moveCursor() {
        let point = points[index % points.count]
        index += 1
        let result = CGWarpMouseCursorPosition(point)
        if result != .success {
            print("[WARN] Cursor sweep warp failed: \(result.rawValue)")
        }
    }
}
