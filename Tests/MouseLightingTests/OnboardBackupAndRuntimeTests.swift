import Foundation
import XCTest

@testable import MouseLighting

final class OnboardBackupAndRuntimeTests: XCTestCase {
    private func snapshot(off: Bool = false) -> OnboardLightingSnapshot {
        var directory = [UInt8](repeating: 0xff, count: 256)
        directory.replaceSubrange(0..<4, with: [0, 1, 1, 0])
        OnboardLightingSnapshot.updateCRC(&directory)
        var profile = [UInt8](repeating: 0xff, count: 256)
        profile[208] = off ? 0 : 3
        profile[219] = off ? 0 : 3
        OnboardLightingSnapshot.updateCRC(&profile)
        return OnboardLightingSnapshot(
            feature: 15, descriptor: [1, 2, 1, 1, 1, 6, 7, 1, 0, 10, 1, 0, 0, 0, 0, 0],
            mode: 1, sector: 1, directory: directory, profile: profile)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testBackupIsPrivateBoundToMouseAndRestorationDoesNotReplaceOriginal() throws {
        let directory = temporaryDirectory()
        let store = try OnboardBackupStore(deviceIdentity: "serial:first", directory: directory)
        XCTAssertThrowsError(try store.loadForRestoration())
        try store.save(snapshot(), forRestoration: true)
        try store.save(snapshot(off: true), forRestoration: false)
        XCTAssertEqual(try store.loadForRestoration(), snapshot())
        let other = try OnboardBackupStore(deviceIdentity: "serial:second", directory: directory)
        XCTAssertThrowsError(try other.loadForRestoration())
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 3)
        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testConcurrentWritersAreRejectedAndLeaseCanBeReleased() throws {
        let directory = temporaryDirectory()
        let first = try OnboardBackupStore(deviceIdentity: "same", directory: directory)
        let second = try OnboardBackupStore(deviceIdentity: "same", directory: directory)
        let lease = try first.acquireExclusiveAccess()
        XCTAssertThrowsError(try second.acquireExclusiveAccess())
        lease.release()
        let next = try second.acquireExclusiveAccess()
        next.release()
    }

    func testBackupWriteFailureAndCorruptBackupAreRejected() throws {
        let directory = temporaryDirectory()
        try Data([0]).write(to: directory)
        let store = try OnboardBackupStore(deviceIdentity: "same", directory: directory)
        XCTAssertThrowsError(try store.save(snapshot(), forRestoration: true))
        try FileManager.default.removeItem(at: directory)
        try store.save(snapshot(), forRestoration: true)
        try Data("invalid json".utf8).write(to: directory.appendingPathComponent("g403-hero-before-off.json"))
        XCTAssertThrowsError(try store.loadForRestoration())
    }

    func testDPIStateMustMatchExistingProfileTable() throws {
        let state = OnboardRuntimeCommands.DPIState(feature: 10, index: 1, current: 800, defaultValue: 800)
        var profile = [UInt8](repeating: 0, count: 256)
        profile[5] = 0x20
        profile[6] = 0x03
        try state.validate(profile: profile)
        profile[5] = 0
        XCTAssertThrowsError(try state.validate(profile: profile))
        XCTAssertThrowsError(try state.validate(profile: []))
    }

    func testUnchangedDPIIsOnlyReadAndNeverWritten() throws {
        let mouse = RuntimeMouse()
        let commands = OnboardRuntimeCommands(exchange: mouse.exchange)
        let before = try commands.readDPI(onboardFeature: 15)
        try commands.preserveDPI(before, onboardFeature: 15)
        XCTAssertTrue(mouse.writes.isEmpty)
    }

    func testDPIResetIsRestoredUsingOldIndexAndReadBack() throws {
        let mouse = RuntimeMouse()
        let commands = OnboardRuntimeCommands(exchange: mouse.exchange)
        let before = try commands.readDPI(onboardFeature: 15)
        mouse.index = 0
        mouse.dpi = 400
        try commands.preserveDPI(before, onboardFeature: 15)
        XCTAssertEqual(mouse.writes.map { Array($0[4..<7]) }, [[1, 0, 0]])
        XCTAssertTrue(mouse.writes.allSatisfy { $0[2] == 15 && $0[3] >> 4 == 12 })
        XCTAssertEqual(try commands.readDPI(onboardFeature: 15), before)
    }

    func testRejectedDPIRestorationIsNotRetried() throws {
        let mouse = RuntimeMouse()
        let commands = OnboardRuntimeCommands(exchange: mouse.exchange)
        let before = try commands.readDPI(onboardFeature: 15)
        mouse.index = 0
        mouse.dpi = 400
        mouse.ignoreWrites = true
        XCTAssertThrowsError(try commands.preserveDPI(before, onboardFeature: 15))
        XCTAssertEqual(mouse.writes.count, 1)
    }

    func testLightingReleaseDoesNotSwitchProfileOrMode() throws {
        var requests: [[UInt8]] = []
        let commands = OnboardRuntimeCommands { request in
            requests.append(request)
            return [0, 0, 0]
        }
        try commands.releaseLighting(feature: 14)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0], [0x10, 0xff, 14, 0x81, 0, 0, 0])
    }
}

private final class RuntimeMouse {
    var index: UInt8 = 1
    var dpi: UInt16 = 800
    var ignoreWrites = false
    var writes: [[UInt8]] = []

    func exchange(_ request: [UInt8]) throws -> [UInt8] {
        switch (request[2], request[3] >> 4) {
        case (0, 0): return [10, 0, 0]
        case (10, 0): return [1, 0, 0]
        case (15, 11): return [index, 0, 0]
        case (10, 2): return [0, UInt8(dpi >> 8), UInt8(dpi & 255), 3, 32] + Array(repeating: 0, count: 11)
        case (15, 12):
            writes.append(request)
            if !ignoreWrites { index = request[4]; dpi = 800 }
            return [index, 0, 0]
        default: throw MouseLightingError.unsupported("Unexpected test command")
        }
    }
}
