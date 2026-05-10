import XCTest
@testable import MacHostMenuCore

final class ADBDeviceListParserTests: XCTestCase {
    func testParsesAuthorizedDeviceWithModelSummary() {
        let devices = ADBDeviceListParser.parse("""
        List of devices attached
        NZSOGMZL99999999       device usb:0-1.2 product:hennessy model:Redmi_Note_3 device:hennessy transport_id:2
        """)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].serial, "NZSOGMZL99999999")
        XCTAssertEqual(devices[0].summary, "Redmi Note 3 (NZSOGMZL99999999)")
        XCTAssertEqual(devices[0].status, .device)
        XCTAssertTrue(devices[0].isAuthorized)
    }

    func testParsesUnauthorizedAndOfflineDevices() {
        let devices = ADBDeviceListParser.parse("""
        List of devices attached
        phone-a unauthorized usb:1
        phone-b offline usb:2 model:Pixel_5
        """)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].status, .unauthorized)
        XCTAssertEqual(devices[1].status, .offline)
        XCTAssertEqual(devices[1].summary, "Pixel 5 (phone-b)")
    }

    func testIgnoresHeaderBlankAndMalformedLines() {
        let devices = ADBDeviceListParser.parse("""
        List of devices attached

        malformed
        phone-c device
        """)

        XCTAssertEqual(devices, [
            ParsedADBDevice(serial: "phone-c", summary: "phone-c", status: .device)
        ])
    }

    func testSupportsMultipleAuthorizedDevices() {
        let devices = ADBDeviceListParser.parse("""
        List of devices attached
        a device model:Phone_A
        b device model:Phone_B
        """)

        XCTAssertEqual(devices.map(\.serial), ["a", "b"])
        XCTAssertEqual(devices.filter(\.isAuthorized).count, 2)
    }
}
