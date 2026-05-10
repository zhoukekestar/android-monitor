import Foundation

public enum MenuDeviceSelection {
    public static func resolvedSerial(selectedSerial: String?, authorizedSerials: [String]) -> String? {
        guard !authorizedSerials.isEmpty else {
            return nil
        }
        if let selectedSerial, authorizedSerials.contains(selectedSerial) {
            return selectedSerial
        }
        return authorizedSerials.first
    }
}
