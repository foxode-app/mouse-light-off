import XCTest

@testable import MouseLighting

final class OnboardLightingTests: XCTestCase {
    func testCRCUsesKnownCCITTFalseVectorAndBigEndianSectorTrailer() throws {
        XCTAssertEqual(OnboardLightingSnapshot.crc16(Array("123456789".utf8)), 0x29b1)
        var bytes = [UInt8](repeating: 0, count: 256)
        OnboardLightingSnapshot.updateCRC(&bytes)
        XCTAssertEqual(bytes[254], 0x59)
        XCTAssertEqual(bytes[255], 0x2d)
        try OnboardLightingSnapshot.validateSector(bytes, label: "test")
        bytes[255] ^= 1
        XCTAssertThrowsError(try OnboardLightingSnapshot.validateSector(bytes, label: "test"))
    }

    func testDiscoveryOnlyReadsUserDirectoryAndCurrentProfile() throws {
        let mouse = OnboardMouse()
        let snapshot = try mouse.commands.inspect()
        XCTAssertEqual(snapshot.directory, mouse.directory)
        XCTAssertEqual(snapshot.profile, mouse.profile)
        XCTAssertEqual(snapshot.sector, 1)
        XCTAssertTrue(mouse.writes.isEmpty)
        XCTAssertTrue(mouse.requests.allSatisfy { [0, 2, 4, 5].contains($0[3] >> 4) })
        let reads = mouse.requests.filter { $0[3] >> 4 == 5 }
        XCTAssertEqual(Set(reads.map { ($0[4] << 4) | $0[5] }), [0, 1])
        XCTAssertTrue(reads.allSatisfy { $0[0] == 0x11 && $0[6] == 0 && $0[7] % 16 == 0 })
        XCTAssertTrue(mouse.requests.allSatisfy { (1...15).contains($0[3] & 0x0f) })
    }

    func testUnsupportedDescriptorLayoutsAreRejectedBeforeMemoryReads() {
        for (index, value): (Int, UInt8) in [
            (0, 2), (1, 1), (1, 3), (2, 2), (3, 0), (3, 2), (4, 2),
            (5, 0), (5, 17), (6, 1), (7, 0), (8, 1),
        ] {
            let mouse = OnboardMouse()
            mouse.descriptor[index] = value
            XCTAssertThrowsError(try mouse.commands.inspect())
            XCTAssertTrue(mouse.requests.allSatisfy { $0[3] >> 4 == 0 })
            XCTAssertTrue(mouse.writes.isEmpty)
        }
    }

    func testMissingFeatureMalformedRepliesAndWrongOperatingModeNeverWrite() {
        let variants: [(OnboardMouse) -> Void] = [
            { $0.feature = 0 },
            { $0.descriptor.removeLast() },
            { $0.mode = 2 },
            { $0.currentSector = 0x0101 },
            { $0.currentSector = 2 },
            { $0.truncateMemoryRead = true },
            { $0.changeModeAfterFirstRead = true },
        ]
        for mutate in variants {
            let mouse = OnboardMouse()
            mutate(mouse)
            XCTAssertThrowsError(try mouse.commands.inspect())
            XCTAssertTrue(mouse.writes.isEmpty)
        }
    }

    func testCorruptSectorsAndUnexpectedDirectoryEntriesPreventPlanning() {
        let mutations: [(OnboardMouse) -> Void] = [
            { $0.directory[10] ^= 1 },
            { $0.profile[10] ^= 1 },
            { mouse in
                mouse.directory[2] = 0
                OnboardLightingSnapshot.updateCRC(&mouse.directory)
            },
            { mouse in
                mouse.directory[1] = 2
                OnboardLightingSnapshot.updateCRC(&mouse.directory)
            },
            { mouse in
                mouse.directory[4] = 0
                mouse.directory[5] = 2
                OnboardLightingSnapshot.updateCRC(&mouse.directory)
            },
        ]
        for mutate in mutations {
            let mouse = OnboardMouse()
            mutate(mouse)
            XCTAssertThrowsError(try mouse.commands.inspect())
            XCTAssertTrue(mouse.writes.isEmpty)
        }
    }

    func testOffPatchPreservesAllOtherBytesIncludingUncertainTail() throws {
        let snapshot = try OnboardMouse().commands.inspect()
        let plan = try snapshot.planOff()
        XCTAssertTrue(plan.hasChanges)
        XCTAssertEqual(Array(plan.replacement[208..<230]), Array(repeating: 0, count: 22))
        for index in 0..<254 where !(208..<230).contains(index) {
            XCTAssertEqual(plan.replacement[index], snapshot.profile[index], "Changed byte \(index)")
        }
        XCTAssertEqual(Array(plan.replacement[230..<254]), Array(snapshot.profile[230..<254]))
        try OnboardLightingSnapshot.validateSector(plan.replacement, label: "patched")
    }

    func testAlreadyDisabledProfileDoesNotRewriteParametersOrFlash() throws {
        let mouse = OnboardMouse()
        // Nonzero unused parameters are not evidence that a disabled effect is enabled.
        mouse.profile[208] = 0
        mouse.profile[219] = 0
        OnboardLightingSnapshot.updateCRC(&mouse.profile)
        let commands = mouse.commands
        let snapshot = try commands.inspect()
        XCTAssertTrue(snapshot.lightingIsOff)
        let plan = try snapshot.planOff()
        XCTAssertFalse(plan.hasChanges)
        let changed = try commands.apply(plan) { _ in XCTFail("No backup needed for a no-op") }
        XCTAssertFalse(changed)
        XCTAssertEqual(mouse.profile, snapshot.profile)
        XCTAssertTrue(mouse.writes.isEmpty)
    }

    func testTransactionRequiresBackupWritesOneSectorAndVerifiesFullReadback() throws {
        let mouse = OnboardMouse()
        let commands = mouse.commands
        let original = try commands.inspect()
        let plan = try original.planOff()
        var saved: OnboardLightingSnapshot?
        mouse.beforeWrite = { XCTAssertNotNil(saved) }
        XCTAssertTrue(
            try commands.apply(plan) { snapshot in
                XCTAssertTrue(mouse.writes.isEmpty)
                saved = snapshot
            })
        XCTAssertEqual(saved, original)
        XCTAssertEqual(mouse.writes.map { $0[3] >> 4 }, [6] + Array(repeating: 7, count: 16) + [8])
        XCTAssertEqual(Array(mouse.writes[0][4..<10]), [0, 1, 0, 0, 1, 0])
        XCTAssertEqual(mouse.writes[0][0], 0x11)
        XCTAssertEqual(mouse.writes.last?[0], 0x10)
        let transmitted = mouse.writes.filter { $0[3] >> 4 == 7 }.flatMap { Array($0.dropFirst(4)) }
        XCTAssertEqual(transmitted, plan.replacement)
        XCTAssertEqual(mouse.profile, plan.replacement)
        XCTAssertEqual(mouse.directory, original.directory)
        XCTAssertTrue(mouse.readAfterCommit)
    }

    func testBackupFailurePreventsFirstFlashCommand() throws {
        let mouse = OnboardMouse()
        let commands = mouse.commands
        let plan = try commands.inspect().planOff()
        XCTAssertThrowsError(
            try commands.apply(plan) { _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertTrue(mouse.writes.isEmpty)
    }

    func testChangesBeforeOrDuringBackupPreventFirstFlashCommand() throws {
        for changeDuringBackup in [false, true] {
            let mouse = OnboardMouse()
            let commands = mouse.commands
            let plan = try commands.inspect().planOff()
            func changeDPI() {
                mouse.profile[3] ^= 1
                OnboardLightingSnapshot.updateCRC(&mouse.profile)
            }
            if !changeDuringBackup { changeDPI() }
            var backupCount = 0
            XCTAssertThrowsError(
                try commands.apply(plan) { _ in
                    backupCount += 1
                    if changeDuringBackup { changeDPI() }
                }
            ) { error in
                guard case OnboardLightingError.changedSinceRead = error else {
                    return XCTFail("Expected stale snapshot refusal")
                }
            }
            XCTAssertEqual(backupCount, changeDuringBackup ? 1 : 0)
            XCTAssertTrue(mouse.writes.isEmpty)
        }
    }

    func testWriteFailuresStopWithoutRetryCommitOrRollback() throws {
        for failureIndex in [0, 1, 8, 16, 17] {
            let mouse = OnboardMouse()
            let commands = mouse.commands
            let plan = try commands.inspect().planOff()
            mouse.rejectWriteIndex = failureIndex
            var backups = 0
            XCTAssertThrowsError(try commands.apply(plan) { _ in backups += 1 }) { error in
                guard case OnboardLightingError.writeOutcomeUnknown = error else {
                    return XCTFail("A partially transmitted transaction has an unknown outcome")
                }
            }
            XCTAssertEqual(backups, 1)
            XCTAssertEqual(mouse.writes.count, failureIndex + 1)
            XCTAssertEqual(mouse.writes.filter { $0[3] >> 4 == 6 }.count, 1)
            if failureIndex < 17 {
                XCTAssertFalse(mouse.writes.contains { $0[3] >> 4 == 8 })
            }
        }
    }

    func testMalformedWriteAcknowledgementDoesNotContinueTransaction() throws {
        let mouse = OnboardMouse()
        let commands = mouse.commands
        let plan = try commands.inspect().planOff()
        mouse.malformedWriteAcknowledgement = true
        XCTAssertThrowsError(try commands.apply(plan) { _ in })
        XCTAssertEqual(mouse.writes.count, 1)
    }

    func testFullReadbackMismatchIsNotReportedAsSuccessOrRetried() throws {
        for corruptDirectory in [false, true] {
            let mouse = OnboardMouse()
            let commands = mouse.commands
            let plan = try commands.inspect().planOff()
            mouse.afterCommit = {
                if corruptDirectory {
                    mouse.directory[20] ^= 1
                    OnboardLightingSnapshot.updateCRC(&mouse.directory)
                } else {
                    mouse.profile[80] ^= 1
                    OnboardLightingSnapshot.updateCRC(&mouse.profile)
                }
            }
            XCTAssertThrowsError(try commands.apply(plan) { _ in }) { error in
                guard case OnboardLightingError.writeOutcomeUnknown = error else {
                    return XCTFail("Readback mismatch must not claim success")
                }
            }
            XCTAssertEqual(mouse.writes.count, 18)
        }
    }

    func testRestoreChangesOnlyLightingAndRequiresIdenticalNonLightingContext() throws {
        let mouse = OnboardMouse()
        let commands = mouse.commands
        let original = try commands.inspect()
        mouse.profile = try original.planOff().replacement
        let disabled = try commands.inspect()
        let restore = try disabled.planRestoringLighting(from: original)
        XCTAssertEqual(restore.replacement, original.profile)
        XCTAssertTrue(try commands.apply(restore) { XCTAssertEqual($0, disabled) })
        XCTAssertEqual(mouse.profile, original.profile)

        mouse.profile[35] ^= 1
        OnboardLightingSnapshot.updateCRC(&mouse.profile)
        let changed = try commands.inspect()
        XCTAssertThrowsError(try changed.planRestoringLighting(from: original))
    }

    func testBackupRoundTripRetainsEveryByteAndRejectsCorruption() throws {
        let original = try OnboardMouse().commands.inspect()
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OnboardLightingSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, original)
        try decoded.validate()
        let invalid = OnboardLightingSnapshot(
            feature: original.feature, descriptor: original.descriptor, mode: original.mode,
            sector: original.sector, directory: original.directory,
            profile: Array(original.profile.dropLast()))
        XCTAssertThrowsError(try invalid.planOff())
        XCTAssertThrowsError(try original.planRestoringLighting(from: invalid))
    }
}

private final class OnboardMouse {
    var feature: UInt8 = 9
    var descriptor: [UInt8] = [1, 2, 1, 1, 1, 6, 7, 1, 0, 10, 1, 0, 0, 0, 0, 0]
    var mode: UInt8 = 1
    var currentSector: UInt16 = 1
    var directory = [UInt8](repeating: 0xff, count: 256)
    var profile = (0..<256).map { UInt8(($0 * 7 + 13) % 256) }
    var requests: [[UInt8]] = []
    var writes: [[UInt8]] = []
    var truncateMemoryRead = false
    var changeModeAfterFirstRead = false
    var rejectWriteIndex: Int?
    var malformedWriteAcknowledgement = false
    var beforeWrite: (() -> Void)?
    var afterCommit: (() -> Void)?
    var readAfterCommit = false
    private var modeReads = 0
    private var pending: [UInt8] = []
    private var committed = false

    var commands: OnboardLightingCommands { OnboardLightingCommands(exchange: exchange) }

    init() {
        directory.replaceSubrange(0..<8, with: [0, 1, 1, 0, 0xff, 0xff, 0, 0])
        OnboardLightingSnapshot.updateCRC(&directory)
        for offset in [208, 219] {
            profile.replaceSubrange(offset..<(offset + 11), with: [3, 0, 0, 0, 0, 0, 0x1f, 0x40, 0, 0, 0])
        }
        profile.replaceSubrange(230..<254, with: repeatElement(UInt8(0xff), count: 24))
        profile[230] = 0
        OnboardLightingSnapshot.updateCRC(&profile)
    }

    func exchange(_ request: [UInt8]) throws -> [UInt8] {
        requests.append(request)
        if request[2] == 0 {
            XCTAssertEqual(Array(request[4..<6]), [0x81, 0])
            return [feature, 0, 0]
        }
        let function = request[3] >> 4
        if function >= 6 {
            beforeWrite?()
            writes.append(request)
            if rejectWriteIndex == writes.count - 1 { throw MouseLightingError.timeout }
            if malformedWriteAcknowledgement { return [] }
        }
        switch function {
        case 0: return descriptor
        case 2:
            modeReads += 1
            return [changeModeAfterFirstRead && modeReads > 1 ? 2 : mode, 0, 0]
        case 4: return [UInt8(currentSector >> 8), UInt8(currentSector & 0xff), 0]
        case 5:
            let sector = (UInt16(request[4]) << 8) | UInt16(request[5])
            let offset = (Int(request[6]) << 8) | Int(request[7])
            guard [0, 1].contains(sector), offset <= 240 else {
                throw MouseLightingError.deviceError(2)
            }
            if committed { readAfterCommit = true }
            let bytes = sector == 0 ? directory : profile
            return Array(bytes[offset..<(offset + (truncateMemoryRead ? 15 : 16))])
        case 6:
            guard Array(request[4..<10]) == [0, 1, 0, 0, 1, 0] else {
                throw MouseLightingError.deviceError(2)
            }
            pending = []
        case 7: pending += Array(request.dropFirst(4))
        case 8:
            guard pending.count == 256 else { throw MouseLightingError.deviceError(2) }
            profile = pending
            committed = true
            afterCommit?()
        default: throw MouseLightingError.deviceError(1)
        }
        return [0, 0, 0]
    }
}
