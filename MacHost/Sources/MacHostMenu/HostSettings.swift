import Foundation

struct HostSettings {
    var width: Int
    var height: Int
    var fps: Int
    var bitrateMbps: Int
    var port: Int
    var outputPath: String

    static let defaults = HostSettings(
        width: 1024,
        height: 600,
        fps: 15,
        bitrateMbps: 2,
        port: 38888,
        outputPath: "/tmp/android-monitor-menubar.h264"
    )

    var summary: String {
        "\(width)x\(height) @ \(fps) FPS, \(bitrateMbps) Mbps"
    }

    static func load(from defaults: UserDefaults = .standard) -> HostSettings {
        let fallback = Self.defaults
        let width = defaults.integer(forKey: Keys.width)
        let height = defaults.integer(forKey: Keys.height)
        let fps = defaults.integer(forKey: Keys.fps)
        let bitrate = defaults.integer(forKey: Keys.bitrateMbps)
        let port = defaults.integer(forKey: Keys.port)
        let outputPath = defaults.string(forKey: Keys.outputPath) ?? fallback.outputPath

        return HostSettings(
            width: width > 0 ? width : fallback.width,
            height: height > 0 ? height : fallback.height,
            fps: fps > 0 ? fps : fallback.fps,
            bitrateMbps: bitrate > 0 ? bitrate : fallback.bitrateMbps,
            port: port > 0 ? port : fallback.port,
            outputPath: outputPath.isEmpty ? fallback.outputPath : outputPath
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(width, forKey: Keys.width)
        defaults.set(height, forKey: Keys.height)
        defaults.set(fps, forKey: Keys.fps)
        defaults.set(bitrateMbps, forKey: Keys.bitrateMbps)
        defaults.set(port, forKey: Keys.port)
        defaults.set(outputPath, forKey: Keys.outputPath)
    }

    func validated() throws -> HostSettings {
        guard width > 0, height > 0 else {
            throw SettingsError.invalid("Width and height must be positive.")
        }
        guard fps > 0 && fps <= 60 else {
            throw SettingsError.invalid("FPS must be between 1 and 60.")
        }
        guard bitrateMbps > 0 else {
            throw SettingsError.invalid("Bitrate must be positive.")
        }
        guard port > 0 && port <= Int(UInt16.max) else {
            throw SettingsError.invalid("Port must be between 1 and \(UInt16.max).")
        }
        guard !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SettingsError.invalid("Output path is required.")
        }
        return self
    }

    enum SettingsError: LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let message):
                return message
            }
        }
    }

    private enum Keys {
        static let width = "host.width"
        static let height = "host.height"
        static let fps = "host.fps"
        static let bitrateMbps = "host.bitrateMbps"
        static let port = "host.port"
        static let outputPath = "host.outputPath"
    }
}
