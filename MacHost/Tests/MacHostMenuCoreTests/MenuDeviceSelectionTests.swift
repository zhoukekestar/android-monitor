import XCTest
@testable import MacHostMenuCore

final class MenuDeviceSelectionTests: XCTestCase {
    func testPreservesSelectedAuthorizedSerial() {
        XCTAssertEqual(
            MenuDeviceSelection.resolvedSerial(selectedSerial: "b", authorizedSerials: ["a", "b"]),
            "b"
        )
    }

    func testFallsBackToFirstAuthorizedSerialWhenSelectionMissing() {
        XCTAssertEqual(
            MenuDeviceSelection.resolvedSerial(selectedSerial: "missing", authorizedSerials: ["a", "b"]),
            "a"
        )
    }

    func testSelectsFirstAuthorizedSerialWhenSelectionIsNil() {
        XCTAssertEqual(
            MenuDeviceSelection.resolvedSerial(selectedSerial: nil, authorizedSerials: ["a", "b"]),
            "a"
        )
    }

    func testReturnsNilWhenNoAuthorizedDevicesExist() {
        XCTAssertNil(MenuDeviceSelection.resolvedSerial(selectedSerial: "a", authorizedSerials: []))
    }
}
