import AppKit
import Foundation

do {
    let options = try parseOptions(CommandLine.arguments)
    NSApplication.shared.setActivationPolicy(.accessory)

    if options.auditDisplays {
        let audit = DisplayAudit.current()
        audit.printReport()
        exit(options.failOnStaleDisplays && audit.staleAndroidMonitorDisplayCount > 0 ? 11 : 0)
    }

    if options.checkScreenCapturePermissionOnly {
        let granted = preflightScreenCapturePermission(
            requestIfMissing: options.requestScreenCapturePermission
        )
        exit(granted ? 0 : 4)
    }

    if options.checkAccessibilityPermissionOnly {
        let granted = preflightAccessibilityPermissionForInput(
            requestIfMissing: options.requestAccessibilityPermission
        )
        exit(granted ? 0 : 5)
    }

    print("========================================")
    print(" Android Monitor Phase 0 Mac Spike")
    print("========================================")
    print("Resolution: \(options.width)x\(options.height)")
    print("Encoding:   H.264 Baseline, \(options.fps) FPS, \(options.bitrateMbps) Mbps")
    print("Duration:   \(String(format: "%.1f", options.durationSeconds))s")
    print("Output:     \(options.outputPath)")
    print("")

    var display: VirtualDisplay?
    var testContentWindow: TestContentWindow?
    var externalTextEditWindow: ExternalTextEditWindow?
    var cursorTestWindow: CursorTestWindow?
    var cursorSweep: CursorSweep?
    var streamWidth = options.width
    var streamHeight = options.height

    if !options.syntheticOnly {
        _ = preflightScreenCapturePermission(
            requestIfMissing: options.requestScreenCapturePermission
        )
        print("")

        print("--- Creating CGVirtualDisplay ---")
        let createdDisplay = try VirtualDisplay(
            width: options.width,
            height: options.height,
            refreshRate: 60,
            name: "Android Monitor Phase 0"
        )
        display = createdDisplay
        print("[OK] Virtual display created with ID \(createdDisplay.displayID)")
        print("Waiting \(String(format: "%.1f", options.waitForDisplaySeconds))s for macOS to register it...")
        Thread.sleep(forTimeInterval: options.waitForDisplaySeconds)
        print(createdDisplay.isOnline() ? "[OK] Display is online" : "[WARN] Display was not found in the online display list")
        preflightAccessibilityPermissionForInput(
            requestIfMissing: options.requestAccessibilityPermission
        )

        let actualSize = createdDisplay.pixelSize()
        if actualSize.width > 0 && actualSize.height > 0 {
            streamWidth = actualSize.width
            streamHeight = actualSize.height
        }
        if streamWidth != options.width || streamHeight != options.height {
            print("[INFO] macOS registered the virtual display as \(streamWidth)x\(streamHeight)")
        }

        if options.testContentWindow {
            testContentWindow = TestContentWindow(displayID: createdDisplay.displayID)
            testContentWindow?.start()
        }

        if options.externalTextEditWindow {
            let testDuration = options.durationSeconds
                + options.waitForClientSeconds
                + options.preCaptureDelaySeconds
                + options.waitForDisplaySeconds
                + 5
            externalTextEditWindow = ExternalTextEditWindow(
                displayID: createdDisplay.displayID,
                durationSeconds: testDuration
            )
            externalTextEditWindow?.start()
        }

        if options.cursorTestWindow {
            cursorTestWindow = CursorTestWindow(displayID: createdDisplay.displayID)
            cursorTestWindow?.start()
            cursorSweep = CursorSweep(displayID: createdDisplay.displayID)
            cursorSweep?.start()
        }
    }

    var server: StreamServer?
    if options.startServer {
        let streamServer = StreamServer(
            width: streamWidth,
            height: streamHeight,
            fps: options.fps,
            bitrateMbps: options.bitrateMbps,
            port: options.port,
            inputDisplayID: display?.displayID,
            logInputEvents: options.logInputEvents
        )
        try streamServer.start()
        server = streamServer

        if options.setupAdbReverse {
            do {
                try ADBReverse(port: options.port).setup()
            } catch {
                print("[WARN] USB transport setup skipped: \(error)")
            }
        }

        if options.waitForClientSeconds > 0 {
            print("[INFO] Waiting up to \(String(format: "%.1f", options.waitForClientSeconds))s for Android client_hello before encoding")
            if streamServer.waitForClientHello(timeoutSeconds: options.waitForClientSeconds) {
                print("[OK] Android client is ready for the first keyframe")
            } else {
                print("[WARN] No Android client_hello before timeout; encoding will continue and late clients may miss the first keyframe")
            }
        }
    }

    if options.preCaptureDelaySeconds > 0 {
        print("[INFO] Waiting \(String(format: "%.1f", options.preCaptureDelaySeconds))s before capture")
        Thread.sleep(forTimeInterval: options.preCaptureDelaySeconds)
    }

    FileManager.default.createFile(atPath: options.outputPath, contents: nil)
    guard let output = FileHandle(forWritingAtPath: options.outputPath) else {
        throw SpikeError.file("could not open \(options.outputPath) for writing")
    }
    defer {
        cursorSweep?.stop()
        testContentWindow?.stop()
        cursorTestWindow?.stop()
        externalTextEditWindow?.stop()
        try? output.close()
        server?.stop()
        display?.destroy()
        display = nil
    }

    let encoder = try H264Encoder(
        width: streamWidth,
        height: streamHeight,
        fps: options.fps,
        bitrateMbps: options.bitrateMbps
    )

    if options.adaptiveBitrate {
        let adaptiveBitrate = AdaptiveBitrateController(
            fps: options.fps,
            initialBitrateMbps: options.bitrateMbps
        )
        server?.onStats = { [weak encoder] stats in
            guard let encoder else {
                return
            }
            adaptiveBitrate.handle(stats: stats, encoder: encoder)
        }
    }

    let frameQueue = DispatchQueue(label: "android-monitor.phase0.frames")
    var encodedFrames = 0
    var keyframes = 0
    var bytesWritten = 0

    encoder.onFrame = { frame in
        frameQueue.async {
            output.write(frame.data)
            encodedFrames += 1
            if frame.isKeyframe {
                keyframes += 1
            }
            bytesWritten += frame.data.count
            server?.send(frame)
        }
    }

    if options.syntheticOnly {
        print("--- Synthetic H.264 encode ---")
        let generatedFrames = try encodeSyntheticFrames(
            width: streamWidth,
            height: streamHeight,
            fps: options.fps,
            durationSeconds: options.durationSeconds,
            encoder: encoder
        )
        print("[OK] Submitted \(generatedFrames) synthetic frames")
    } else {
        guard let display else {
            throw SpikeError.virtualDisplay("display was not created")
        }

        print("--- Capturing virtual display ---")
        do {
            let capture = try captureDisplay(
                displayID: display.displayID,
                width: streamWidth,
                height: streamHeight,
                fps: options.fps,
                durationSeconds: options.durationSeconds,
                encoder: encoder
            )
            print("[OK] Capture finished: \(capture.frameCount) frames in \(String(format: "%.2f", capture.elapsedSeconds))s")

            if capture.frameCount == 0 {
                print("[WARN] No captured frames arrived; running synthetic encoder fallback for H.264 validation")
                let generatedFrames = try encodeSyntheticFrames(
                    width: streamWidth,
                    height: streamHeight,
                    fps: options.fps,
                    durationSeconds: min(3, options.durationSeconds),
                    encoder: encoder
                )
                print("[OK] Submitted \(generatedFrames) synthetic fallback frames")
            }
        } catch {
            print("[WARN] Capture failed: \(error)")
            print("[WARN] Running synthetic encoder fallback for H.264 validation")
            let generatedFrames = try encodeSyntheticFrames(
                width: streamWidth,
                height: streamHeight,
                fps: options.fps,
                durationSeconds: min(3, options.durationSeconds),
                encoder: encoder
            )
            print("[OK] Submitted \(generatedFrames) synthetic fallback frames")
        }

        _ = display
    }

    encoder.finish()
    frameQueue.sync {}

    print("")
    print("========================================")
    print(" Phase 0 Summary")
    print("========================================")
    print("Encoded frames: \(encodedFrames)")
    print("Keyframes:      \(keyframes)")
    print("Output bytes:   \(bytesWritten)")
    print("Output file:    \(options.outputPath)")
    print("Done.")
} catch {
    fputs("[FAIL] \(error)\n", stderr)
    exit(1)
}
