import Foundation

struct Options {
    var width = 1024
    var height = 600
    var fps = 15
    var bitrateMbps = 4
    var durationSeconds: TimeInterval = 10
    var outputPath = "phase0.h264"
    var port: UInt16 = 38888
    var waitForClientSeconds: TimeInterval = 8
    var preCaptureDelaySeconds: TimeInterval = 0
    var syntheticOnly = false
    var startServer = true
    var setupAdbReverse = true
    var waitForDisplaySeconds: TimeInterval = 2
    var requestScreenCapturePermission = false
    var checkScreenCapturePermissionOnly = false
    var requestAccessibilityPermission = false
    var checkAccessibilityPermissionOnly = false
    var testContentWindow = false
    var externalTextEditWindow = false
    var cursorTestWindow = false
    var auditDisplays = false
    var failOnStaleDisplays = false
    var adaptiveBitrate = true
    var logInputEvents = false
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 1

    func requireValue(for flag: String) throws -> String {
        guard index + 1 < arguments.count else {
            throw SpikeError.argument("\(flag) requires a value")
        }
        index += 1
        return arguments[index]
    }

    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "--width":
            options.width = try Int(requireValue(for: arg)) ?? {
                throw SpikeError.argument("invalid width")
            }()
        case "--height":
            options.height = try Int(requireValue(for: arg)) ?? {
                throw SpikeError.argument("invalid height")
            }()
        case "--fps":
            options.fps = try Int(requireValue(for: arg)) ?? {
                throw SpikeError.argument("invalid fps")
            }()
        case "--bitrate-mbps":
            options.bitrateMbps = try Int(requireValue(for: arg)) ?? {
                throw SpikeError.argument("invalid bitrate")
            }()
        case "--duration":
            options.durationSeconds = try TimeInterval(requireValue(for: arg)) ?? {
                throw SpikeError.argument("invalid duration")
            }()
        case "--output":
            options.outputPath = try requireValue(for: arg)
        case "--port":
            let rawPort = try Int(requireValue(for: arg)) ?? {
                throw SpikeError.argument("invalid port")
            }()
            guard rawPort > 0 && rawPort <= UInt16.max else {
                throw SpikeError.argument("port must be 1...\(UInt16.max)")
            }
            options.port = UInt16(rawPort)
        case "--wait-for-client":
            options.waitForClientSeconds = try TimeInterval(requireValue(for: arg)) ?? {
                throw SpikeError.argument("invalid client wait")
            }()
        case "--pre-capture-delay":
            options.preCaptureDelaySeconds = try TimeInterval(requireValue(for: arg)) ?? {
                throw SpikeError.argument("invalid pre-capture delay")
            }()
        case "--synthetic-only":
            options.syntheticOnly = true
        case "--no-server":
            options.startServer = false
            options.setupAdbReverse = false
        case "--no-adb-reverse":
            options.setupAdbReverse = false
        case "--request-screen-capture-permission":
            options.requestScreenCapturePermission = true
        case "--check-screen-capture-permission":
            options.checkScreenCapturePermissionOnly = true
        case "--request-accessibility-permission":
            options.requestAccessibilityPermission = true
            options.checkAccessibilityPermissionOnly = true
        case "--check-accessibility-permission":
            options.checkAccessibilityPermissionOnly = true
        case "--test-content-window":
            options.testContentWindow = true
        case "--external-textedit-window":
            options.externalTextEditWindow = true
        case "--cursor-test-window":
            options.cursorTestWindow = true
        case "--audit-displays":
            options.auditDisplays = true
            options.startServer = false
            options.setupAdbReverse = false
        case "--fail-on-stale-displays":
            options.failOnStaleDisplays = true
        case "--no-adaptive-bitrate":
            options.adaptiveBitrate = false
        case "--log-input-events":
            options.logInputEvents = true
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw SpikeError.argument("unknown flag \(arg)")
        }
        index += 1
    }

    guard options.width > 0, options.height > 0 else {
        throw SpikeError.argument("width and height must be positive")
    }
    guard options.fps > 0 && options.fps <= 60 else {
        throw SpikeError.argument("fps must be 1...60")
    }
    guard options.bitrateMbps > 0 else {
        throw SpikeError.argument("bitrate must be positive")
    }
    guard options.durationSeconds > 0 else {
        throw SpikeError.argument("duration must be positive")
    }
    guard options.waitForClientSeconds >= 0 else {
        throw SpikeError.argument("client wait must be non-negative")
    }
    guard options.preCaptureDelaySeconds >= 0 else {
        throw SpikeError.argument("pre-capture delay must be non-negative")
    }

    return options
}

func printUsage() {
    print(
        """
        phase0-spike

        Creates a macOS virtual display, captures it with ScreenCaptureKit or CGDisplayStream,
        encodes H.264 Annex-B frames with VideoToolbox, and optionally serves them on localhost.

        Options:
          --width <px>          Default: 1024
          --height <px>         Default: 600
          --fps <n>             Default: 15
          --bitrate-mbps <n>    Default: 4
          --duration <seconds>  Default: 10
          --output <path>       Default: phase0.h264
          --port <port>         Default: 38888
          --wait-for-client <s> Default: 8. Wait for Android client_hello before encoding.
          --pre-capture-delay <s>
                                Wait after setup before capture. Useful for manual/window tests.
          --synthetic-only      Skip virtual display/capture and encode test frames.
          --no-server           Do not start the TCP stream server.
          --no-adb-reverse      Do not run adb reverse for the TCP stream port.
          --request-screen-capture-permission
                                Ask macOS for Screen/System Audio Recording access.
          --check-screen-capture-permission
                                Check capture permission and exit without creating a display.
          --request-accessibility-permission
                                Ask macOS for Accessibility access and exit without creating a display.
          --check-accessibility-permission
                                Check Accessibility permission and exit without creating a display.
          --test-content-window
                                Show animated test content on the virtual display during capture.
          --external-textedit-window
                                Show a normal animated TextEdit window on the virtual display.
          --cursor-test-window
                                Show a static cursor-capture target and sweep the macOS cursor.
          --audit-displays      Print read-only macOS display state and exit.
          --fail-on-stale-displays
                                With --audit-displays, exit 11 if stale Android Monitor displays exist.
          --no-adaptive-bitrate
                                Disable Android-stats-driven bitrate reduction.
          --log-input-events
                                Log Android touch/scroll control messages for diagnostics.
          --help                Show this message.
        """
    )
}
