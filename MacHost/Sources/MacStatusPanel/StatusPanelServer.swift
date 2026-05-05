import Foundation
import Network

final class StatusPanelServer {
    private let port: UInt16
    private let queue = DispatchQueue(label: "android-monitor.status-panel")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw StatusPanelError.invalidPort(port)
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 30
            tcp.keepaliveInterval = 10
            tcp.keepaliveCount = 3
        }

        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] newConnection in
            self?.accept(newConnection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[OK] Status panel server listening on 127.0.0.1:\(self.port)")
                print("     USB setup: adb reverse tcp:\(self.port) tcp:\(self.port)")
                ADBReverseStatusPanel(port: self.port).setup()
            case .failed(let error):
                print("[WARN] Status panel listener failed: \(error)")
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.sendSnapshot()
        }
        timer.resume()
        self.timer = timer
    }

    private func accept(_ newConnection: NWConnection) {
        connection?.cancel()
        connection = newConnection
        newConnection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[OK] Status panel client connected")
            case .failed(let error):
                print("[WARN] Status panel client failed: \(error)")
            case .cancelled:
                print("[INFO] Status panel client disconnected")
            default:
                break
            }
        }
        newConnection.start(queue: queue)
    }

    private func sendSnapshot() {
        guard let connection else {
            return
        }

        let snapshot = StatusSnapshot.current()
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot.json, options: []),
              var line = String(data: data, encoding: .utf8)?.data(using: .utf8) else {
            return
        }
        line.append(0x0A)
        connection.send(content: line, completion: .contentProcessed { error in
            if let error {
                print("[WARN] Status snapshot send failed: \(error)")
            }
        })
    }
}

private enum StatusPanelError: Error {
    case invalidPort(UInt16)
}

private struct StatusSnapshot {
    let json: [String: Any]

    static func current() -> StatusSnapshot {
        let hostName = Host.current().localizedName ?? Host.current().name ?? "Mac"
        let uptime = ProcessInfo.processInfo.systemUptime
        let logTail = firstNonEmpty([
            tail("/tmp/android-monitor-menubar.log", lines: 8),
            tail("/tmp/android-monitor-phase1-window-freshness/mac-host.log", lines: 8),
            tail("/tmp/android-monitor-phase2-stability-smoke/mac-host.log", lines: 8)
        ])
        let repoRoot = findRepoRoot()

        return StatusSnapshot(json: [
            "type": "status_snapshot",
            "host": hostName,
            "repo_root": repoRoot,
            "timestamp": isoTimestamp(),
            "uptime": compact(run("/usr/bin/uptime", [])),
            "uptime_seconds": Int(uptime),
            "cpu": compact(run("/bin/sh", ["-lc", "ps -A -o %cpu= -o comm= -r | head -n 8"])),
            "memory": compact(run("/usr/bin/vm_stat", [])),
            "disk": compact(run("/bin/df", ["-h", "/"])),
            "network": compact(run("/sbin/ifconfig", ["en0"])),
            "command_output": compact(run("/bin/sh", ["-lc", "date; uptime; df -h / | tail -n +2"])),
            "build_status": buildStatus(repoRoot: repoRoot),
            "log_tail": logTail
        ])
    }

    private static func isoTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date())
    }

    private static func buildStatus(repoRoot: String) -> String {
        let fileManager = FileManager.default
        let checks = [
            ("Mac debug host", "\(repoRoot)/MacHost/.build/debug/phase0-spike"),
            ("Mac status server", "\(repoRoot)/MacHost/.build/debug/status-panel-server"),
            ("Mac app bundle", "\(repoRoot)/MacHost/build/Android Monitor Host.app/Contents/MacOS/Android Monitor Host"),
            ("Android APK", "\(repoRoot)/AndroidReceiver/app/build/outputs/apk/debug/android-receiver-debug.apk")
        ]
        let artifactStatus = checks
            .map { label, path in
                fileManager.fileExists(atPath: path) ? "\(label): present" : "\(label): missing"
            }
        return (artifactStatus + [androidUnitTestStatus(repoRoot: repoRoot)])
            .joined(separator: "\n")
    }

    private static func androidUnitTestStatus(repoRoot: String) -> String {
        let resultDir = "\(repoRoot)/AndroidReceiver/app/build/test-results/testDebugUnitTest"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: resultDir) else {
            return "Android unit tests: missing"
        }

        let resultFiles = files
            .filter { $0.hasPrefix("TEST-") && $0.hasSuffix(".xml") }
            .map { "\(resultDir)/\($0)" }
            .sorted()
        guard !resultFiles.isEmpty else {
            return "Android unit tests: missing"
        }

        let summaries = resultFiles.compactMap { AndroidTestSuiteSummary.parse(path: $0) }
        guard !summaries.isEmpty else {
            return "Android unit tests: unreadable"
        }

        let tests = summaries.reduce(0) { $0 + $1.tests }
        let failures = summaries.reduce(0) { $0 + $1.failures }
        let errors = summaries.reduce(0) { $0 + $1.errors }
        let skipped = summaries.reduce(0) { $0 + $1.skipped }
        let status = failures == 0 && errors == 0 ? "pass" : "fail"
        return "Android unit tests: \(status) (\(tests) tests, \(failures) failures, \(errors) errors, \(skipped) skipped, \(summaries.count) suites)"
    }

    private static func findRepoRoot() -> String {
        let fileManager = FileManager.default
        var starts = [fileManager.currentDirectoryPath]
        if let executable = Bundle.main.executablePath {
            starts.append((executable as NSString).deletingLastPathComponent)
        }

        for start in starts {
            var candidate = URL(fileURLWithPath: start).standardizedFileURL.path
            for _ in 0..<10 {
                if looksLikeRepoRoot(candidate) {
                    return candidate
                }
                let parent = (candidate as NSString).deletingLastPathComponent
                if parent == candidate {
                    break
                }
                candidate = parent
            }
        }
        return fileManager.currentDirectoryPath
    }

    private static func looksLikeRepoRoot(_ path: String) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: "\(path)/PLAN.md")
            && fileManager.fileExists(atPath: "\(path)/MacHost")
            && fileManager.fileExists(atPath: "\(path)/AndroidReceiver")
    }

    private static func tail(_ path: String, lines: Int) -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            return ""
        }
        return run("/usr/bin/tail", ["-n", "\(lines)", path])
    }

    private static func firstNonEmpty(_ values: [String]) -> String {
        values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
    }

    private static func compact(_ text: String, maxCharacters: Int = 2200) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else {
            return trimmed
        }
        return String(trimmed.prefix(maxCharacters)) + "\n..."
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String {
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
            return error.localizedDescription
        }

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return stdout.isEmpty ? stderr : stdout
    }
}

private struct ADBReverseStatusPanel {
    let port: UInt16

    func setup() {
        guard let adbPath = findADB() else {
            print("[WARN] adb not found; status panel USB reverse was not configured")
            return
        }

        let endpoint = "tcp:\(port)"
        _ = run(adbPath, ["reverse", "--remove", endpoint])
        let reverse = run(adbPath, ["reverse", endpoint, endpoint])
        if reverse.exitCode == 0 {
            print("[OK] adb reverse configured for status panel: \(endpoint) -> \(endpoint)")
        } else {
            print("[WARN] adb reverse failed for status panel: \(reverse.output)")
        }
    }

    private func findADB() -> String? {
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
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(exitCode: -1, output: error.localizedDescription)
        }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandResult(exitCode: process.terminationStatus, output: output)
    }
}

private struct CommandResult {
    let exitCode: Int32
    let output: String
}

private final class AndroidTestSuiteSummary: NSObject, XMLParserDelegate {
    private(set) var tests = 0
    private(set) var failures = 0
    private(set) var errors = 0
    private(set) var skipped = 0
    private var foundSuite = false

    static func parse(path: String) -> AndroidTestSuiteSummary? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        let summary = AndroidTestSuiteSummary()
        let parser = XMLParser(data: data)
        parser.delegate = summary
        guard parser.parse(), summary.foundSuite else {
            return nil
        }
        return summary
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "testsuite", !foundSuite else {
            return
        }
        foundSuite = true
        tests = intAttribute(attributeDict["tests"])
        failures = intAttribute(attributeDict["failures"])
        errors = intAttribute(attributeDict["errors"])
        skipped = intAttribute(attributeDict["skipped"])
    }

    private func intAttribute(_ value: String?) -> Int {
        guard let value, let parsed = Int(value) else {
            return 0
        }
        return parsed
    }
}
