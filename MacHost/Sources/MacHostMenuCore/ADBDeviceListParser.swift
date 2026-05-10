import Foundation

public struct ParsedADBDevice: Equatable {
    public enum Status: Equatable {
        case device
        case unauthorized
        case offline
        case other(String)
    }

    public let serial: String
    public let summary: String
    public let status: Status

    public var isAuthorized: Bool {
        status == .device
    }

    public init(serial: String, summary: String, status: Status) {
        self.serial = serial
        self.summary = summary
        self.status = status
    }
}

public enum ADBDeviceListParser {
    public static func parse(_ output: String) -> [ParsedADBDevice] {
        output.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("List of devices") else {
                return nil
            }

            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 2 else {
                return nil
            }

            let status: ParsedADBDevice.Status
            switch fields[1] {
            case "device":
                status = .device
            case "unauthorized":
                status = .unauthorized
            case "offline":
                status = .offline
            default:
                status = .other(fields[1])
            }

            return ParsedADBDevice(
                serial: fields[0],
                summary: summary(from: fields),
                status: status
            )
        }
    }

    private static func summary(from fields: [String]) -> String {
        let serial = fields.first ?? "device"
        let model = fields
            .first(where: { $0.hasPrefix("model:") })?
            .replacingOccurrences(of: "model:", with: "")
            .replacingOccurrences(of: "_", with: " ")
        return model.map { "\($0) (\(serial))" } ?? serial
    }
}
