import Foundation
import MacHostMenuCore

struct ADBDevice: Equatable {
    enum ConnectionStatus: Equatable {
        case device
        case unauthorized
        case offline
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
        case adbError(String)
        case noDevice
        case unauthorized
        case offline
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
        case .adbError:
            return "Device: adb error"
        case .noDevice:
            return "Device: Not connected"
        case .unauthorized:
            return "Device: Unauthorized"
        case .offline:
            return "Device: Offline"
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
        case .adbError:
            return "ADB Error"
        case .noDevice:
            return "No Device"
        case .unauthorized:
            return "Unauthorized"
        case .offline:
            return "Offline"
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
    enum Operation {
        case installReceiver
        case configureReverse
        case launchReceiver
        case displayAudit
    }

    static let receiverPackage = "com.androidmonitor.receiver"
    static let receiverActivity = "com.androidmonitor.receiver/.MainActivity"

    static func readDeviceState() -> ADBDeviceState {
        guard let adbPath = findADB() else {
            return ADBDeviceState(status: .adbMissing)
        }

        let result = run(adbPath, arguments: ["devices", "-l"])
        guard result.succeeded else {
            let message = ADBFailureGuidance.message(
                exitCode: result.exitCode,
                output: result.output,
                operation: .configureReverse
            )
            return ADBDeviceState(status: .adbError(message), adbPath: adbPath)
        }

        let devices = ADBDeviceListParser.parse(result.output).map(ADBDevice.init(parsed:))
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
        if devices.contains(where: {
            if case .offline = $0.status {
                return true
            }
            return false
        }) {
            return ADBDeviceState(status: .offline, devices: devices, adbPath: adbPath)
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

    static func userGuidance(for result: CommandResult, operation: Operation) -> String {
        let coreOperation: ADBFailureOperation
        switch operation {
        case .installReceiver:
            coreOperation = .installReceiver
        case .configureReverse:
            coreOperation = .configureReverse
        case .launchReceiver:
            coreOperation = .launchReceiver
        case .displayAudit:
            coreOperation = .displayAudit
        }
        return ADBFailureGuidance.message(
            exitCode: result.exitCode,
            output: result.output,
            operation: coreOperation
        )
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

    static func run(_ executable: String, arguments: [String], timeoutSeconds: TimeInterval = 8) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                terminateTimedOutProcess(process)
                let partialOutput: String
                if process.isRunning {
                    partialOutput = ""
                } else {
                    let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    partialOutput = stdout + stderr
                }
                let partialSuffix = partialOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? ""
                    : "\n\nPartial output:\n\(partialOutput.trimmingCharacters(in: .whitespacesAndNewlines))"
                return CommandResult(
                    exitCode: -2,
                    output: "Command timed out after \(Int(timeoutSeconds))s: \(executable) \(arguments.joined(separator: " "))"
                        + partialSuffix
                )
            }
        } catch {
            return CommandResult(exitCode: -1, output: error.localizedDescription)
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: stdout + stderr)
    }

    private static func terminateTimedOutProcess(_ process: Process) {
        process.terminate()
        waitBrieflyForExit(process, timeoutSeconds: 0.4)
        guard process.isRunning else {
            return
        }

        process.interrupt()
        waitBrieflyForExit(process, timeoutSeconds: 0.2)
        guard process.isRunning else {
            return
        }

        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/bin/kill")
        kill.arguments = ["-KILL", "\(process.processIdentifier)"]
        try? kill.run()
        kill.waitUntilExit()
        waitBrieflyForExit(process, timeoutSeconds: 0.4)
    }

    private static func waitBrieflyForExit(_ process: Process, timeoutSeconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if !process.isRunning {
            process.waitUntilExit()
        }
    }
}

private extension ADBDevice {
    init(parsed: ParsedADBDevice) {
        let status: ConnectionStatus
        switch parsed.status {
        case .device:
            status = .device
        case .unauthorized:
            status = .unauthorized
        case .offline:
            status = .offline
        case .other(let raw):
            status = .other(raw)
        }

        self.init(serial: parsed.serial, summary: parsed.summary, status: status)
    }
}
