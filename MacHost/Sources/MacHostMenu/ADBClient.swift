import Foundation

struct ADBDevice: Equatable {
    enum ConnectionStatus: Equatable {
        case device
        case unauthorized
        case other(String)
    }

    let serial: String
    let summary: String
    let status: ConnectionStatus

    var isAuthorized: Bool {
        status == .device
    }
}

struct ADBDeviceState {
    enum Status {
        case unknown
        case adbMissing
        case noDevice
        case unauthorized
        case authorized
    }

    let status: Status
    let devices: [ADBDevice]
    let adbPath: String?

    init(status: Status, devices: [ADBDevice] = [], adbPath: String? = nil) {
        self.status = status
        self.devices = devices
        self.adbPath = adbPath
    }

    var authorizedDevices: [ADBDevice] {
        devices.filter(\.isAuthorized)
    }

    var canStartStream: Bool {
        !authorizedDevices.isEmpty
    }

    var menuTitle: String {
        switch status {
        case .unknown:
            return "Device: Checking..."
        case .adbMissing:
            return "Device: adb not found"
        case .noDevice:
            return "Device: Not connected"
        case .unauthorized:
            return "Device: Unauthorized"
        case .authorized:
            if authorizedDevices.count == 1, let device = authorizedDevices.first {
                return "Device: \(device.summary)"
            }
            return "Device: \(authorizedDevices.count) devices"
        }
    }

    var shortStatus: String {
        switch status {
        case .unknown:
            return "Checking"
        case .adbMissing:
            return "No adb"
        case .noDevice:
            return "No Device"
        case .unauthorized:
            return "Unauthorized"
        case .authorized:
            return "Ready"
        }
    }
}

struct CommandResult {
    let exitCode: Int32
    let output: String

    var succeeded: Bool {
        exitCode == 0
    }
}

enum ADBClient {
    static let receiverPackage = "com.androidmonitor.receiver"
    static let receiverActivity = "com.androidmonitor.receiver/.MainActivity"

    static func readDeviceState() -> ADBDeviceState {
        guard let adbPath = findADB() else {
            return ADBDeviceState(status: .adbMissing)
        }

        let result = run(adbPath, arguments: ["devices", "-l"])
        guard result.succeeded else {
            return ADBDeviceState(status: .noDevice, adbPath: adbPath)
        }

        let devices = parseDevices(result.output)
        if devices.contains(where: \.isAuthorized) {
            return ADBDeviceState(status: .authorized, devices: devices, adbPath: adbPath)
        }
        if devices.contains(where: {
            if case .unauthorized = $0.status {
                return true
            }
            return false
        }) {
            return ADBDeviceState(status: .unauthorized, devices: devices, adbPath: adbPath)
        }
        return ADBDeviceState(status: .noDevice, devices: devices, adbPath: adbPath)
    }

    static func packageInstalled(on device: ADBDevice) -> Bool {
        guard let adbPath = findADB() else {
            return false
        }
        let result = run(adbPath, arguments: ["-s", device.serial, "shell", "pm", "path", receiverPackage])
        return result.succeeded && result.output.contains("package:")
    }

    static func installReceiver(apkURL: URL, on device: ADBDevice) -> CommandResult {
        guard let adbPath = findADB() else {
            return CommandResult(exitCode: -1, output: "adb not found")
        }
        return run(adbPath, arguments: ["-s", device.serial, "install", "-r", "-d", apkURL.path])
    }

    static func configureReverse(port: Int, on device: ADBDevice) -> CommandResult {
        guard let adbPath = findADB() else {
            return CommandResult(exitCode: -1, output: "adb not found")
        }
        let endpoint = "tcp:\(port)"
        _ = run(adbPath, arguments: ["-s", device.serial, "reverse", "--remove", endpoint])
        return run(adbPath, arguments: ["-s", device.serial, "reverse", endpoint, endpoint])
    }

    static func launchReceiver(on device: ADBDevice, statusMode: Bool = false) -> CommandResult {
        guard let adbPath = findADB() else {
            return CommandResult(exitCode: -1, output: "adb not found")
        }
        var arguments = ["-s", device.serial, "shell", "am", "start"]
        if statusMode {
            arguments += ["--ez", "status_mode", "true"]
        }
        arguments += ["-n", receiverActivity]
        return run(adbPath, arguments: arguments)
    }

    static func forceStopReceiver(on device: ADBDevice) {
        guard let adbPath = findADB() else {
            return
        }
        _ = run(adbPath, arguments: ["-s", device.serial, "shell", "am", "force-stop", receiverPackage])
    }

    static func findADB() -> String? {
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment

        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key], !root.isEmpty {
                candidates.append("\(root)/platform-tools/adb")
            }
        }
        if let home = environment["HOME"], !home.isEmpty {
            candidates.append("\(home)/Library/Android/sdk/platform-tools/adb")
        }
        if let path = environment["PATH"] {
            for dir in path.split(separator: ":") {
                candidates.append("\(dir)/adb")
            }
        }
        candidates.append(contentsOf: ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"])

        let fileManager = FileManager.default
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0) })
    }

    static func run(_ executable: String, arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(exitCode: -1, output: error.localizedDescription)
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: stdout + stderr)
    }

    private static func parseDevices(_ output: String) -> [ADBDevice] {
        output.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("List of devices") else {
                return nil
            }

            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 2 else {
                return nil
            }

            let serial = fields[0]
            let status: ADBDevice.ConnectionStatus
            switch fields[1] {
            case "device":
                status = .device
            case "unauthorized":
                status = .unauthorized
            default:
                status = .other(fields[1])
            }

            return ADBDevice(
                serial: serial,
                summary: deviceSummary(from: fields),
                status: status
            )
        }
    }

    private static func deviceSummary(from fields: [String]) -> String {
        let serial = fields.first ?? "device"
        let model = fields
            .first(where: { $0.hasPrefix("model:") })?
            .replacingOccurrences(of: "model:", with: "")
            .replacingOccurrences(of: "_", with: " ")
        return model.map { "\($0) (\(serial))" } ?? serial
    }
}
