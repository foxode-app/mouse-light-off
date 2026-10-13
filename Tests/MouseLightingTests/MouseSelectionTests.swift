import XCTest

@testable import MouseLighting

final class MouseSelectionTests: XCTestCase {
    func testRegistryHasOnlyExplicitWiredModels() {
        XCTAssertEqual(SupportedMouse.devices.count, 8)
        XCTAssertEqual(Set(SupportedMouse.devices.map(\.productID)).count, 8)
        XCTAssertEqual(SupportedMouse.devices.filter(\.hardwareVerified).map(\.productID), [0xc08f])
        for model in SupportedMouse.devices {
            XCTAssertEqual(SupportedMouse.match(vendorID: 0x046d, productID: model.productID), model)
            XCTAssertNil(SupportedMouse.match(vendorID: 0x1234, productID: model.productID))
        }
        for unsupported in [0xc092, 0xc09d, 0xc095, 0xc539, 0xc52b, 0xc088, 0xffff] {
            XCTAssertNil(SupportedMouse.match(vendorID: 0x046d, productID: unsupported))
        }
    }

    func testInterfacesDeduplicatePerPhysicalDeviceWithoutDroppingIdenticalMice() {
        let candidates = [
            endpoint(physical: "usb:1", interface: 11, usage: 1),
            endpoint(physical: "usb:1", interface: 12),
            endpoint(physical: "usb:2", interface: 21),
            endpoint(physical: "usb:3", interface: 31, product: 0xc084),
        ]
        let groups = MouseInterface.groups(candidates)
        XCTAssertEqual(groups.count, 3)
        let shared = groups.first { $0[0].physicalID == "usb:1" }
        XCTAssertEqual(shared?.map(\.interfaceID), [12, 11])
        XCTAssertEqual(groups.flatMap { $0 }.count, 4)
    }

    func testUnknownWirelessAndShortReportInterfacesAreExcluded() {
        let candidates = [
            endpoint(), endpoint(vendor: 0xffff), endpoint(product: 0xc539),
            endpoint(transport: "Bluetooth"), endpoint(product: 0xc339, page: 1), endpoint(size: 7),
            endpoint(physical: ""),
        ]
        XCTAssertEqual(MouseInterface.groups(candidates), [[endpoint()]])
    }

    func testVerifiedG403CompositeKeyboardCollectionIsAccepted() {
        // The actual G403 HERO exposes HID++ through a keyboard primary collection.
        let commandInterface = endpoint(interface: 2, page: 1, usage: 6, size: 20)
        let ordinaryMouseInterface = endpoint(interface: 1, page: 1, usage: 2, size: 0)
        XCTAssertEqual(
            MouseInterface.groups([ordinaryMouseInterface, commandInterface]),
            [[commandInterface]])
    }

    func testBatchContinuesAfterFailureAndReportsEveryDevice() {
        var visited: [String] = []
        XCTAssertThrowsError(
            try MouseBatch.perform(["mouse1", "mouse2", "mouse3"], name: { $0 }) { device in
                visited.append(device)
                if device == "mouse2" { throw MouseLightingError.timeout }
                return "成功"
            }
        ) { error in
            XCTAssertTrue(error is MouseBatchError)
            XCTAssertTrue(error.localizedDescription.contains("mouse1: 成功"))
            XCTAssertTrue(error.localizedDescription.contains("mouse2: 失敗"))
            XCTAssertTrue(error.localizedDescription.contains("mouse3: 成功"))
        }
        XCTAssertEqual(visited, ["mouse1", "mouse2", "mouse3"])
    }

    func testNoDevicesThrowsAndAllSuccessIncludesEveryDevice() throws {
        XCTAssertThrowsError(try MouseBatch.perform([String](), name: { $0 }, operation: { $0 }))
        XCTAssertEqual(
            try MouseBatch.perform(["mouse1", "mouse2"], name: { $0 }, operation: { _ in "成功" }),
            "mouse1: 成功\nmouse2: 成功")
    }

    private func endpoint(
        physical: String = "usb:1", interface: UInt64 = 1, vendor: Int = 0x046d,
        product: Int = 0xc08f, transport: String = "USB", page: Int = 0xff00,
        usage: Int = 2, size: Int = 20
    ) -> MouseInterface {
        MouseInterface(
            vendorID: vendor, productID: product, transport: transport,
            usagePage: page, usage: usage, outputSize: size,
            physicalID: physical, interfaceID: interface)
    }
}
