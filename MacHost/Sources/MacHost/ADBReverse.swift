import Foundation

struct ADBReverse {
    let port: UInt16
    let adbPath: String

    init(port: UInt16) throws {
        self.port = port
        guard let adbPath = Self.findADB() else {
            throw SpikeError.capture("adb not found; install Android platform-tools or run with --no-adb-reverse")
        }
        self.adbPath = adbPath
    }

    func setup() {
        let endpoint = "tcp:\(port)"
        print("[INFO] Using adb at \(adbPath)")

        _ = runADB(["reverse", "--remove", endpoint], tolerateFailure: true)
        let reverse = runADB(["reverse", endpoint, endpoint], tolerateFailure: true)
        if reverse.exitCode != 0 {
            print("[WARN] adb reverse failed:")
            printIndented(reverse.combinedOutput)
            print("       If the device is unauthorized, unlock it and accept the USB debugging prompt.")
            return
        }

        let list = runADB(["reverse", "--list"], tolerateFailure: true)
        if list.exitCode == 0, list.combinedOutput.contains(endpoint) {
            print("[OK] adb reverse configured: \(endpoint) -> \(endpoint)")
        } else {
            print("[WARN] adb reverse command succeeded, but the mapping was not visible in adb reverse --list")
            printIndented(list.combinedOutput)
        }
    }

    private func runADB(_ arguments: [String], tolerateFailure: Bool) -> CommandResult {
        let result = Self.run(adbPath, arguments: arguments)
        if result.exitCode != 0 && !tolerateFailure {
            print("[WARN] adb \(arguments.joined(separator: " ")) failed with exit \(result.exitCode)")
            printIndented(result.combinedOutput)
        }
        return result
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

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ])

        let fileManager = FileManager.default
        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return nil
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
            return CommandResult(exitCode: -1, combinedOutput: error.localizedDescription)
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, combinedOutput: stdout + stderr)
    }

    private func printIndented(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("       <no adb output>")
            return
        }
        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            print("       \(line)")
        }
    }
}

private struct CommandResult {
    let exitCode: Int32
    let combinedOutput: String
}
