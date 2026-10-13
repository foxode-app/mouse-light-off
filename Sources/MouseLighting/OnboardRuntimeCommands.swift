import Foundation

/// Runtime DPI checks are separate from the raw-profile patch. No profile/mode switch is sent.
final class OnboardRuntimeCommands {
    struct DPIState: Equatable {
        let feature: UInt8
        let index: UInt8
        let current: UInt16
        let defaultValue: UInt16

        func validate(profile: [UInt8]) throws {
            let offset = 3 + Int(index) * 2
            guard profile.count == 256, index < 5,
                UInt16(profile[offset]) | (UInt16(profile[offset + 1]) << 8) == current
            else {
                throw MouseLightingError.unsupported("現在のDPIと本体のDPI設定が一致しないため、保存を中止しました。")
            }
        }
    }

    private let exchange: ([UInt8]) throws -> [UInt8]
    private var tag: UInt8 = 0

    init(exchange: @escaping ([UInt8]) throws -> [UInt8]) { self.exchange = exchange }

    private func query(_ feature: UInt8, _ function: UInt8, _ payload: [UInt8] = []) throws -> [UInt8] {
        tag = tag % 15 + 1
        return try exchange(HIDPP.request(feature: feature, function: function, tag: tag, payload: payload))
    }

    func readDPI(onboardFeature: UInt8) throws -> DPIState {
        let root = try query(0, 0, [0x22, 0x01, 0])
        guard let feature = root.first, feature != 0 else {
            throw MouseLightingError.unsupported("現在のDPIを確認できません。")
        }
        let count = try query(feature, 0)
        let index = try query(onboardFeature, 11)
        let dpi = try query(feature, 2, [0])
        guard count.first == 1, let dpiIndex = index.first, dpiIndex < 5,
            dpi.count >= 5, dpi[0] == 0
        else { throw MouseLightingError.unsupported("DPI情報の応答が不正です。") }
        let current = (UInt16(dpi[1]) << 8) | UInt16(dpi[2])
        guard current > 0 else { throw MouseLightingError.unsupported("現在のDPIが不正です。") }
        return DPIState(
            feature: feature, index: dpiIndex, current: current,
            defaultValue: (UInt16(dpi[3]) << 8) | UInt16(dpi[4]))
    }

    func preserveDPI(_ before: DPIState, onboardFeature: UInt8) throws {
        let after = try readDPI(onboardFeature: onboardFeature)
        guard before != after else { return }
        // Some firmware resets the runtime DPI when committing a profile. Restore its old index only.
        _ = try query(onboardFeature, 12, [before.index])
        guard try readDPI(onboardFeature: onboardFeature) == before else {
            throw MouseLightingError.unsupported("照明は保存しましたが、現在のDPIを元の値に確認できませんでした。")
        }
    }

    func releaseLighting(feature: UInt8) throws {
        _ = try query(feature, 8, [0, 0, 0])
    }
}
