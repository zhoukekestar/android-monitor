import Foundation

struct ADBDeviceState {
    enum Status {
        case unknown
        case adbMissing
        case noDevice
        case unauthorized
        case authorized(String)
    }

    let status: Status

    var canStartStream: Bool {
        if case .authorized = status {
            return true
        }
        return false
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
        case .authorized(let summary):
            return "Device: \(summary)"
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

final class ADBDeviceMonitor {
    var onUpdate: ((ADBDeviceState) -> Void)?

    private let queue = DispatchQueue(label: "android-monitor.menu.adb-device")
    private var timer: DispatchSourceTimer?

    func start() {
        refresh()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.refreshOnQueue()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        queue.async { [weak self] in
            self?.refreshOnQueue()
        }
    }

    private func refreshOnQueue() {
        let state = Self.readDeviceState()
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(state)
        }
    }

    private static func readDeviceState() -> ADBDeviceState {
        guard let adbPath = findADB() else {
            return ADBDeviceState(status: .adbMissing)
        }

        let result = run(adbPath, arguments: ["devices", "-l"])
        guard result.exitCode == 0 else {
            return ADBDeviceState(status: .noDevice)
        }

        var sawUnauthorized = false
        for rawLine in result.output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("List of devices") else {
                continue
            }

            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 2 else {
                continue
            }

            if fields[1] == "device" {
                return ADBDeviceState(status: .authorized(deviceSummary(from: fields)))
            }
            if fields[1] == "unauthorized" {
                sawUnauthorized = true
            }
        }

        return ADBDeviceState(status: sawUnauthorized ? .unauthorized : .noDevice)
    }

    private static func deviceSummary(from fields: [String]) -> String {
        let serial = fields.first ?? "device"
        let model = fields
            .first(where: { $0.hasPrefix("model:") })?
            .replacingOccurrences(of: "model:", with: "")
            .replacingOccurrences(of: "_", with: " ")
        return model.map { "\($0) (\(serial))" } ?? serial
    }

    private static func findADB() -> String? {
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

    private static func run(_ executable: String, arguments: [String]) -> CommandResult {
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
}

private struct CommandResult {
    let exitCode: Int32
    let output: String
}
