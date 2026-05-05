import AppKit
import CoreGraphics

final class TestContentWindow {
    private var window: NSWindow?
    private var view: AnimatedTestContentView?
    private var timer: Timer?

    init(displayID: CGDirectDisplayID) {
        let targetFrame: NSRect
        if let screen = Self.screen(for: displayID) {
            targetFrame = screen.visibleFrame.insetBy(dx: 40, dy: 40)
        } else {
            let appKitBounds = Self.appKitFrameFromCoreGraphicsBounds(displayID: displayID)
            guard appKitBounds.width > 0 && appKitBounds.height > 0 else {
                print("[WARN] Could not find display bounds for ID \(displayID); test content window disabled")
                return
            }
            print("[WARN] NSScreen did not publish display ID \(displayID); placing test window with converted CoreGraphics bounds")
            targetFrame = NSRect(
                x: appKitBounds.minX + 40,
                y: appKitBounds.minY + 40,
                width: appKitBounds.width - 80,
                height: appKitBounds.height - 80
            )
        }

        guard targetFrame.width > 0 && targetFrame.height > 0 else {
            print("[WARN] Test content target frame was empty; test content window disabled")
            return
        }

        let width = targetFrame.width
        let height = targetFrame.height
        let contentRect = NSRect(
            x: targetFrame.minX,
            y: targetFrame.minY,
            width: width,
            height: height
        )
        print("[INFO] Test content window frame: \(Int(contentRect.minX)),\(Int(contentRect.minY)) \(Int(contentRect.width))x\(Int(contentRect.height))")

        let view = AnimatedTestContentView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Android Monitor Capture Test"
        window.contentView = view
        window.level = .floating
        window.isReleasedWhenClosed = false

        self.window = window
        self.view = view
    }

    func start() {
        guard let window, let view else {
            return
        }

        window.makeKeyAndOrderFront(nil)
        view.needsDisplay = true
        view.displayIfNeeded()

        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak window, weak view] _ in
            guard let view else {
                return
            }
            view.tick += 1
            view.needsDisplay = true
            view.displayIfNeeded()
            window?.displayIfNeeded()
        }
        timer.tolerance = 0.002
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
        print("[OK] Animated test content window shown on virtual display")
    }

    func stop() {
        if let view {
            print("[INFO] Animated test content ticks: \(view.tick)")
        }
        timer?.invalidate()
        timer = nil
        window?.close()
        window = nil
        view = nil
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

private final class AnimatedTestContentView: NSView {
    var tick = 0

    override func draw(_ dirtyRect: NSRect) {
        let colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemPurple]
        colors[tick % colors.count].setFill()
        dirtyRect.fill()

        let text = "Android Monitor\nreal capture test\nframe \(tick)" as NSString
        text.draw(
            at: NSPoint(x: 24, y: max(24, bounds.height - 150)),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 34, weight: .bold),
                .foregroundColor: NSColor.white
            ]
        )

        NSColor.white.setStroke()
        let inset = bounds.insetBy(dx: 18, dy: 18)
        NSBezierPath(rect: inset).stroke()
    }
}
