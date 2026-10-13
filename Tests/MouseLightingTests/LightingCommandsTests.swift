import XCTest

@testable import MouseLighting

final class LightingCommandsTests: XCTestCase {
    func testDiscoveryIsReadOnlyAndUsesActualZoneCount() throws {
        for count in [1, 2, 3, 8] {
            let mouse = MockMouse(effects: Array(repeating: [0, 1], count: count))
            let capabilities = try mouse.commands.inspect()
            XCTAssertEqual(capabilities.zones.count, count)
            XCTAssertTrue(mouse.writes.isEmpty)
        }
    }

    func testOffUsesDiscoveredEffectIndexForEveryZone() throws {
        let mouse = MockMouse(effects: [[1, 3, 0], [3, 0, 1], [0, 1]])
        let commands = mouse.commands
        let capabilities = try commands.inspect()
        XCTAssertEqual(try commands.apply(.off, capabilities: capabilities), 3)
        XCTAssertEqual(mouse.writes.map { $0[3] >> 4 }, [8, 3, 3, 3])
        XCTAssertEqual(mouse.writes.dropFirst().map { $0[4] }, [0, 1, 2])
        XCTAssertEqual(mouse.writes.dropFirst().map { $0[5] }, [2, 1, 0])
        XCTAssertTrue(mouse.writes.dropFirst().allSatisfy { $0[16] == 0 })
        let firstWrite = try XCTUnwrap(mouse.requests.firstIndex { $0[3] >> 4 == 8 })
        XCTAssertTrue(mouse.requests[..<firstWrite].allSatisfy { $0[3] >> 4 <= 2 })
    }

    func testWhiteUsesDiscoveredStaticEffectIndex() throws {
        let mouse = MockMouse(effects: [[1, 3, 0]])
        let commands = mouse.commands
        let capabilities = try commands.inspect()
        _ = try commands.apply(.white, capabilities: capabilities)
        let packet = try XCTUnwrap(mouse.writes.last)
        XCTAssertEqual(packet[5], 0)
        XCTAssertEqual(Array(packet[6...9]), [255, 255, 255, 2])
        XCTAssertEqual(packet[16], 0)
    }

    func testMissingStaticInLaterZonePreventsAllWrites() throws {
        let mouse = MockMouse(effects: [[0, 1], [0, 3]])
        let commands = mouse.commands
        let capabilities = try commands.inspect()
        XCTAssertThrowsError(try commands.apply(.white, capabilities: capabilities))
        XCTAssertTrue(mouse.writes.isEmpty)
    }

    func testMissingOffOrUnboundedCapabilitiesPreventAllWrites() {
        for effects: [[UInt16]] in [
            [], Array(repeating: [0], count: 9), [[]], [[1, 3]], [Array(repeating: 3, count: 17)],
        ] {
            let mouse = MockMouse(effects: effects)
            XCTAssertThrowsError(try mouse.commands.inspect())
            XCTAssertTrue(mouse.writes.isEmpty)
        }
    }

    func testMissingFeatureAndMalformedCapabilityResponsesPreventWrites() {
        let replies: [[[UInt8]]] = [
            [[0, 0, 0]],
            [[7, 0, 0], []],
            [[7, 0, 0], [1, 0, 0], [0, 0, 0]],
            [[7, 0, 0], [1, 0, 0], [1, 0, 0, 1]],
            [[7, 0, 0], [1, 0, 0], [0, 0, 0, 1], [1, 0, 0, 0]],
            [[7, 0, 0], [1, 0, 0], [0, 0, 0, 1], [0, 1, 0, 0]],
        ]
        for var queue in replies {
            var requests: [[UInt8]] = []
            let commands = LightingCommands { request in
                requests.append(request)
                guard !queue.isEmpty else { throw MouseLightingError.timeout }
                return queue.removeFirst()
            }
            XCTAssertThrowsError(try commands.inspect())
            XCTAssertTrue(requests.allSatisfy { $0[3] >> 4 <= 2 })
        }
    }

    func testDeviceFailureStopsRemainingWritesAndDoesNotReportSuccess() throws {
        let mouse = MockMouse(effects: [[0, 1], [0, 1], [0, 1]])
        mouse.rejectZone = 1
        let commands = mouse.commands
        let capabilities = try commands.inspect()
        XCTAssertThrowsError(try commands.apply(.off, capabilities: capabilities))
        XCTAssertEqual(mouse.writes.dropFirst().map { $0[4] }, [0, 1])
    }

    func testCancellationBeforeSoftwareControlPreventsEveryWrite() throws {
        let mouse = MockMouse(effects: [[0, 1], [0, 1]])
        let commands = mouse.commands
        let capabilities = try commands.inspect()
        XCTAssertThrowsError(try commands.apply(.off, capabilities: capabilities, shouldContinue: { false }))
        {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertTrue(mouse.writes.isEmpty)
    }

    func testCancellationBetweenZoneCommandsStopsRemainingWrites() throws {
        let mouse = MockMouse(effects: [[0, 1], [0, 1], [0, 1]])
        let commands = mouse.commands
        let capabilities = try commands.inspect()
        // Complete software control and zone 0; cancellation blocks zone 1 and 2.
        XCTAssertThrowsError(
            try commands.apply(
                .off, capabilities: capabilities,
                shouldContinue: { mouse.writes.count < 2 })
        ) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(mouse.writes.map { $0[3] >> 4 }, [8, 3])
        XCTAssertEqual(mouse.writes.last?[4], 0)
    }

    func testCancellationDuringDiscoveryStopsFurtherQueriesWithoutWrites() {
        let mouse = MockMouse(effects: [[0, 1], [0, 1]])
        XCTAssertThrowsError(try mouse.commands.inspect(shouldContinue: { mouse.requests.count < 2 })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(mouse.requests.count, 2)
        XCTAssertTrue(mouse.writes.isEmpty)
    }

    func testG403OffCommandRetainsKnownWorkingPackets() throws {
        let mouse = MockMouse(effects: [[0, 1], [0, 1]])
        let commands = mouse.commands
        let capabilities = try commands.inspect()
        _ = try commands.apply(.off, capabilities: capabilities)
        XCTAssertEqual(mouse.writes[0][4...6], [1, 1, 0])
        for packet in mouse.writes.dropFirst() {
            XCTAssertEqual(packet[0], 0x11)
            XCTAssertEqual(packet[1], 0xff)
            XCTAssertEqual(packet[2], 7)
            XCTAssertEqual(packet[3] >> 4, 3)
            XCTAssertTrue(packet.dropFirst(5).allSatisfy { $0 == 0 })
        }
    }
}

private final class MockMouse {
    let effects: [[UInt16]]
    var requests: [[UInt8]] = []
    var rejectZone: UInt8?
    var commands: LightingCommands { LightingCommands(exchange: exchange) }
    var writes: [[UInt8]] { requests.filter { $0[3] >> 4 >= 3 } }

    init(effects: [[UInt16]]) { self.effects = effects }

    func exchange(_ request: [UInt8]) throws -> [UInt8] {
        requests.append(request)
        if request[2] == 0 { return [7, 0, 0] }
        switch request[3] >> 4 {
        case 0: return [UInt8(effects.count), 0, 0]
        case 1:
            let zone = Int(request[4])
            return [UInt8(zone), 0, 0, UInt8(effects[zone].count)]
        case 2:
            let effect = effects[Int(request[4])][Int(request[5])]
            return [request[4], request[5], UInt8(effect >> 8), UInt8(effect & 255)]
        case 3:
            if request[4] == rejectZone { throw MouseLightingError.deviceError(2) }
            return []
        case 8: return []
        default: throw MouseLightingError.deviceError(1)
        }
    }
}
