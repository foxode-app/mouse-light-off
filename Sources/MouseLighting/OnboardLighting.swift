import Foundation

enum OnboardLightingError: LocalizedError {
    case unsupported(String)
    case invalidData(String)
    case changedSinceRead
    case writeOutcomeUnknown(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let reason):
            return "このマウスの本体保存には対応していません。\(reason)"
        case .invalidData(let reason):
            return "本体設定の整合性を確認できません。書き込みを中止しました。\(reason)"
        case .changedSinceRead:
            return "読み取り後に本体設定が変わりました。書き込みを中止しました。再確認してください。"
        case .writeOutcomeUnknown(let reason):
            return "本体保存の完了を確認できません。自動再試行は行いません。バックアップを保持して接続を確認してください。\(reason)"
        }
    }
}

/// A byte-for-byte backup of the validated user directory and active profile.
/// The caller must bind this data to the physical mouse before offering restoration.
struct OnboardLightingSnapshot: Codable, Equatable {
    let feature: UInt8
    let descriptor: [UInt8]
    let mode: UInt8
    let sector: UInt16
    let directory: [UInt8]
    let profile: [UInt8]

    // The two established LED records for profile format 2. The following 24 bytes
    // are deliberately preserved: their interpretation is not established for G403 HERO.
    static let lightingRange = 208..<230
    static let sectorSize = 256

    var lightingIsOff: Bool {
        profile.count == Self.sectorSize && profile[208] == 0 && profile[219] == 0
    }

    func planOff() throws -> OnboardLightingPlan {
        try validate()
        var replacement = profile
        // Already-disabled LED records retain their otherwise unused parameters.
        // This avoids unnecessary flash writes for an existing disabled profile.
        for offset in [208, 219] where replacement[offset] != 0 {
            replacement.replaceSubrange(offset..<(offset + 11), with: repeatElement(UInt8(0), count: 11))
        }
        Self.updateCRC(&replacement)
        return OnboardLightingPlan(original: self, replacement: replacement)
    }

    func planRestoringLighting(from backup: Self) throws -> OnboardLightingPlan {
        try validate()
        try backup.validate()
        // Never restore DPI, bindings, profile names, directory entries, or unknown bytes.
        // Refuse even a lighting-only restore when the surrounding profile has changed.
        guard descriptor == backup.descriptor, mode == backup.mode, sector == backup.sector,
            directory == backup.directory,
            Self.nonLightingBytes(profile) == Self.nonLightingBytes(backup.profile)
        else { throw OnboardLightingError.changedSinceRead }
        var replacement = profile
        replacement.replaceSubrange(Self.lightingRange, with: backup.profile[Self.lightingRange])
        Self.updateCRC(&replacement)
        return OnboardLightingPlan(original: self, replacement: replacement)
    }

    func validate() throws {
        try Self.validateDescriptor(descriptor)
        guard feature != 0, mode == 1, sector == 1 else {
            throw OnboardLightingError.unsupported("本体モードの単一ユーザープロファイルのみ対応します。")
        }
        try Self.validateSector(directory, label: "プロファイル一覧")
        guard Array(directory.prefix(4)) == [0, 1, 1, 0],
            directory[4] == 0xff, directory[5] == 0xff
        else { throw OnboardLightingError.unsupported("有効な単一プロファイルの一覧ではありません。") }
        try Self.validateSector(profile, label: "プロファイル")
    }

    static func validateDescriptor(_ bytes: [UInt8]) throws {
        guard bytes.count == 16, bytes[0] == 1, bytes[1] == 2, bytes[2] == 1,
            bytes[3] == 1, bytes[4] == 1, (1...16).contains(bytes[5]), bytes[6] >= 2,
            bytes[7] == 1, bytes[8] == 0
        else { throw OnboardLightingError.unsupported("メモリ形式またはプロファイル構成が対応範囲外です。") }
    }

    static func validateSector(_ bytes: [UInt8], label: String) throws {
        guard bytes.count == sectorSize else {
            throw OnboardLightingError.invalidData("\(label)の長さが不正です。")
        }
        let expected = crc16(bytes.prefix(sectorSize - 2))
        let actual = (UInt16(bytes[254]) << 8) | UInt16(bytes[255])
        guard expected == actual else {
            throw OnboardLightingError.invalidData("\(label)のチェックサムが一致しません。")
        }
    }

    static func crc16<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0xffff
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) == 0 ? crc << 1 : (crc << 1) ^ 0x1021
            }
        }
        return crc
    }

    static func updateCRC(_ bytes: inout [UInt8]) {
        precondition(bytes.count == sectorSize)
        let crc = crc16(bytes.prefix(sectorSize - 2))
        bytes[254] = UInt8(crc >> 8)
        bytes[255] = UInt8(crc & 0xff)
    }

    static func nonLightingBytes(_ bytes: [UInt8]) -> [UInt8] {
        Array(bytes[..<lightingRange.lowerBound]) + Array(bytes[lightingRange.upperBound..<254])
    }
}

struct OnboardLightingPlan {
    let original: OnboardLightingSnapshot
    let replacement: [UInt8]

    var hasChanges: Bool { original.profile != replacement }

    fileprivate init(original: OnboardLightingSnapshot, replacement: [UInt8]) {
        self.original = original
        self.replacement = replacement
    }

    fileprivate func validate() throws {
        try original.validate()
        try OnboardLightingSnapshot.validateSector(replacement, label: "保存予定のプロファイル")
        guard
            OnboardLightingSnapshot.nonLightingBytes(original.profile)
                == OnboardLightingSnapshot.nonLightingBytes(replacement)
        else { throw OnboardLightingError.invalidData("照明以外の設定が変更されています。") }
    }
}

/// Uses only feature 0x8100 and writes exactly one validated user sector.
/// Execute on the same serial worker as temporary lighting commands. Never automatically
/// retry or cancel a sector transaction halfway through; an error has an unknown outcome.
final class OnboardLightingCommands {
    private let exchange: ([UInt8]) throws -> [UInt8]
    private var tag: UInt8 = 0

    init(exchange: @escaping ([UInt8]) throws -> [UInt8]) { self.exchange = exchange }

    func inspect() throws -> OnboardLightingSnapshot {
        let featureReply = try exchange(HIDPP.featureQuery(0x8100, tag: nextTag()))
        guard let feature = featureReply.first, feature != 0 else {
            throw OnboardLightingError.unsupported("HID++ 0x8100がありません。")
        }
        let descriptor = try query(feature: feature, function: 0)
        try OnboardLightingSnapshot.validateDescriptor(descriptor)
        let (mode, sector) = try currentProfile(feature: feature)
        guard mode == 1, sector == 1 else {
            throw OnboardLightingError.unsupported("本体モードの単一ユーザープロファイルのみ対応します。")
        }
        let directory = try readSector(0, feature: feature)
        let profile = try readSector(sector, feature: feature)
        let (finalMode, finalSector) = try currentProfile(feature: feature)
        guard mode == finalMode, sector == finalSector else {
            throw OnboardLightingError.changedSinceRead
        }
        let snapshot = OnboardLightingSnapshot(
            feature: feature, descriptor: descriptor, mode: mode, sector: sector,
            directory: directory, profile: profile)
        try snapshot.validate()
        return snapshot
    }

    /// `persistBackup` must durably save the original bytes or throw. It runs before
    /// any write request. The profile is read again afterwards to detect external changes.
    /// Returns false without any write or backup callback when the desired bytes already match.
    func apply(
        _ plan: OnboardLightingPlan,
        persistBackup: (OnboardLightingSnapshot) throws -> Void
    ) throws -> Bool {
        try plan.validate()
        guard try inspect() == plan.original else { throw OnboardLightingError.changedSinceRead }
        guard plan.hasChanges else { return false }
        try persistBackup(plan.original)
        guard try inspect() == plan.original else { throw OnboardLightingError.changedSinceRead }

        do {
            // 0x8100/6: sector (BE), offset (BE), count (BE). No directory, ROM,
            // profile-selection or onboard-mode write is ever sent here.
            try acknowledge(
                feature: plan.original.feature, function: 6,
                payload: [0, 1, 0, 0, 1, 0])
            for offset in stride(from: 0, to: OnboardLightingSnapshot.sectorSize, by: 16) {
                try acknowledge(
                    feature: plan.original.feature, function: 7,
                    payload: Array(plan.replacement[offset..<(offset + 16)]))
            }
            try acknowledge(feature: plan.original.feature, function: 8)
            let verified = try inspect()
            guard verified.descriptor == plan.original.descriptor,
                verified.mode == plan.original.mode, verified.sector == plan.original.sector,
                verified.directory == plan.original.directory, verified.profile == plan.replacement
            else { throw OnboardLightingError.invalidData("保存後の読み戻しが一致しません。") }
        } catch {
            throw OnboardLightingError.writeOutcomeUnknown(error.localizedDescription)
        }
        return true
    }

    private func nextTag() -> UInt8 {
        tag = (tag % 15) + 1
        return tag
    }

    private func query(feature: UInt8, function: UInt8, payload: [UInt8] = []) throws -> [UInt8] {
        try exchange(HIDPP.request(feature: feature, function: function, tag: nextTag(), payload: payload))
    }

    private func acknowledge(feature: UInt8, function: UInt8, payload: [UInt8] = []) throws {
        let response = try query(feature: feature, function: function, payload: payload)
        guard response.count == 3 || response.count == 16 else {
            throw OnboardLightingError.invalidData("保存命令への応答の長さが不正です。")
        }
    }

    private func currentProfile(feature: UInt8) throws -> (UInt8, UInt16) {
        let mode = try query(feature: feature, function: 2)
        let current = try query(feature: feature, function: 4)
        guard let modeByte = mode.first, current.count >= 2 else {
            throw OnboardLightingError.invalidData("現在のプロファイル応答が不正です。")
        }
        return (modeByte, (UInt16(current[0]) << 8) | UInt16(current[1]))
    }

    private func readSector(_ sector: UInt16, feature: UInt8) throws -> [UInt8] {
        var bytes: [UInt8] = []
        for offset in stride(from: 0, to: OnboardLightingSnapshot.sectorSize, by: 16) {
            let chunk = try query(
                feature: feature, function: 5,
                payload: [UInt8(sector >> 8), UInt8(sector & 0xff), UInt8(offset >> 8), UInt8(offset & 0xff)])
            guard chunk.count == 16 else {
                throw OnboardLightingError.invalidData("メモリ読み取りの長さが不正です。")
            }
            bytes += chunk
        }
        return bytes
    }
}
