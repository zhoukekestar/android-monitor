import Foundation

enum SpikeError: Error, CustomStringConvertible {
    case argument(String)
    case virtualDisplay(String)
    case encoder(String)
    case capture(String)
    case file(String)

    var description: String {
        switch self {
        case .argument(let message):
            return "Argument error: \(message)"
        case .virtualDisplay(let message):
            return "Virtual display error: \(message)"
        case .encoder(let message):
            return "Encoder error: \(message)"
        case .capture(let message):
            return "Capture error: \(message)"
        case .file(let message):
            return "File error: \(message)"
        }
    }
}
