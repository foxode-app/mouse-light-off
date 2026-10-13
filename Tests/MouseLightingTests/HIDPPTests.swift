import XCTest

@testable import MouseLighting

final class HIDPPTests: XCTestCase {
    func testFeatureDiscoveryDoesNotHardcodeDeviceFeatureIndex() {
        XCTAssertEqual(HIDPP.featureQuery(0x8070, tag: 5), [0x10, 0xff, 0, 5, 0x80, 0x70, 0])
    }

    func testSoftwareControlTargetsDiscoveredFeature() {
        XCTAssertEqual(HIDPP.temporaryControl(feature: 0x0e, tag: 2), [0x10, 0xff, 0x0e, 0x82, 1, 1, 0])
    }

    func testLightingInfoUsesReadOnlyFunctionAndBoundsDynamicZones() throws {
        XCTAssertEqual(HIDPP.lightingInfo(feature: 4, tag: 7), [0x10, 0xff, 4, 7, 0, 0, 0])
        for count: UInt8 in 1...HIDPP.maximumZones {
            XCTAssertEqual(try HIDPP.zoneCount([count, 0, 0]), count)
        }
        for payload: [UInt8] in [[], [0], [9], [255]] {
            XCTAssertThrowsError(try HIDPP.zoneCount(payload))
        }
    }

    func testEveryLightingModeUsesVolatileStorage() {
        for mode: LightingMode in [.off, .white] {
            for zone: UInt8 in 0..<HIDPP.maximumZones {
                let packet = HIDPP.lighting(
                    feature: 4, zone: zone, effect: mode == .off ? 0 : 1, mode: mode, tag: 3)
                XCTAssertEqual(packet[16], 0, "Lighting commands must never persist to EEPROM.")
            }
        }
    }

    func testOffPacketCoversAllSupportedZones() {
        for zone: UInt8 in 0..<HIDPP.maximumZones {
            let packet = HIDPP.lighting(feature: 0x0e, zone: zone, effect: 0, mode: .off, tag: 3)
            XCTAssertEqual(Array(packet.prefix(6)), [0x11, 0xff, 0x0e, 0x33, zone, 0])
            XCTAssertEqual(packet.count, 20)
            XCTAssertTrue(packet.dropFirst(6).allSatisfy { $0 == 0 })
        }
    }

    func testWhiteUsesStaticEffect() {
        let packet = HIDPP.lighting(feature: 4, zone: 1, effect: 1, mode: .white, tag: 8)
        XCTAssertEqual(Array(packet.prefix(10)), [0x11, 0xff, 4, 0x38, 1, 1, 255, 255, 255, 2])
    }

    func testOnlyMatchingResponseAccepted() throws {
        let request = HIDPP.featureQuery(0x8070, tag: 5)
        XCTAssertEqual(try HIDPP.response([0x10, 0xff, 0, 5, 0x0e, 0, 0], to: request), [0x0e, 0, 0])
        for response: [UInt8] in [
            [], [0x10, 0xff], [0x10, 1, 0, 5, 0x0e, 0, 0],
            [0x10, 0xff, 1, 5, 0x0e, 0, 0], [0x10, 0xff, 0, 6, 0x0e, 0, 0],
            [0x11, 0xff, 0, 5, 0x0e, 0, 0], [1, 0xff, 0, 5, 0x0e, 0, 0],
        ] {
            XCTAssertNil(try HIDPP.response(response, to: request))
        }
    }

    func testDeviceRejectionIsNotReportedAsSuccess() {
        let request = HIDPP.temporaryControl(feature: 0x0e, tag: 2)
        XCTAssertThrowsError(try HIDPP.response([0x10, 0xff, 0x8f, 0x0e, 0x82, 3, 0], to: request))
        XCTAssertThrowsError(try HIDPP.response([0x10, 0xff, 0xff, 0x0e, 0x82, 2, 0], to: request))
    }
}
