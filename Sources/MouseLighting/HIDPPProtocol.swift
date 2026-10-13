import Foundation

public enum LightingMode: Sendable {
    case off
    case white
}

public enum MouseLightingError: LocalizedError {
    case notConnected
    case permissionRequired
    case transport(String, Int32)
    case timeout
    case deviceError(UInt8)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "対応するマウスが見つかりません。対応機種とUSB接続を確認してください。"
        case .permissionRequired:
            return "入力監視の許可が必要です。設定でMouse Light Offを許可し、アプリを終了して開き直してください。"
        case .transport(let operation, let code):
            return String(format: "%@に失敗しました（0x%08x）。", operation, code)
        case .timeout:
            return "マウスからの応答がありません。G HUBやOpenRGBが動作中なら終了し、再接続してください。"
        case .deviceError(let code):
            return String(format: "マウスが命令を拒否しました（HID++エラー0x%02x）。", code)
        case .unsupported(let detail):
            return "このマウスの照明機能を確認できませんでした。\(detail)"
        }
    }
}

// Protocol facts referenced in docs/PROTOCOL.md; implementation uses macOS IOKit directly.
enum HIDPP {
    static let address: UInt8 = 0xff
    static let maximumZones: UInt8 = 8
    static let maximumEffects: UInt8 = 16

    static func request(feature: UInt8, function: UInt8, tag: UInt8, payload: [UInt8]) -> [UInt8] {
        precondition(function < 16 && (1...15).contains(tag) && payload.count <= 16)
        var bytes = [UInt8](repeating: 0, count: payload.count > 3 ? 20 : 7)
        bytes[0] = bytes.count == 20 ? 0x11 : 0x10
        bytes[1] = address
        bytes[2] = feature
        bytes[3] = (function << 4) | tag
        bytes.replaceSubrange(4..<(4 + payload.count), with: payload)
        return bytes
    }

    static func featureQuery(_ id: UInt16, tag: UInt8) -> [UInt8] {
        request(feature: 0, function: 0, tag: tag, payload: [UInt8(id >> 8), UInt8(id & 255), 0])
    }

    static func lightingInfo(feature: UInt8, tag: UInt8) -> [UInt8] {
        request(feature: feature, function: 0, tag: tag, payload: [])
    }

    static func zoneCount(_ payload: [UInt8]) throws -> UInt8 {
        // 0x8070 GetInfo returns the zone count in its first parameter.
        guard let count = payload.first, (1...maximumZones).contains(count) else {
            throw MouseLightingError.unsupported("照明ゾーン数が対応範囲（1〜\(maximumZones)）外です。")
        }
        return count
    }

    static func zoneInfo(feature: UInt8, zone: UInt8, tag: UInt8) -> [UInt8] {
        request(feature: feature, function: 1, tag: tag, payload: [zone])
    }

    static func effectCount(_ payload: [UInt8], zone: UInt8) throws -> UInt8 {
        guard payload.count >= 4, payload[0] == zone,
            (1...maximumEffects).contains(payload[3])
        else { throw MouseLightingError.unsupported("ゾーン\(zone + 1)の照明効果を確認できません。") }
        return payload[3]
    }

    static func effectInfo(feature: UInt8, zone: UInt8, effect: UInt8, tag: UInt8) -> [UInt8] {
        request(feature: feature, function: 2, tag: tag, payload: [zone, effect])
    }

    static func effectID(_ payload: [UInt8], zone: UInt8, effect: UInt8) throws -> UInt16 {
        guard payload.count >= 4, payload[0] == zone, payload[1] == effect else {
            throw MouseLightingError.unsupported("ゾーン\(zone + 1)の照明効果の応答が不正です。")
        }
        return (UInt16(payload[2]) << 8) | UInt16(payload[3])
    }

    // 0x8070 function 8: software owns the LEDs; the second byte enables sync events.
    // This does not select storage persistence; function 3 does that separately.
    static func temporaryControl(feature: UInt8, tag: UInt8) -> [UInt8] {
        request(feature: feature, function: 8, tag: tag, payload: [1, 1, 0])
    }

    static func lighting(
        feature: UInt8, zone: UInt8, effect: UInt8, mode: LightingMode, tag: UInt8
    ) -> [UInt8] {
        precondition(zone < maximumZones && effect < maximumEffects)
        var payload = [UInt8](repeating: 0, count: 16)
        payload[0] = zone
        payload[1] = effect
        // Function 3 parameter 12 (report byte 16): 0 = RAM only, 1 = RAM + EEPROM.
        payload[12] = 0
        if case .white = mode {
            payload[2] = 255
            payload[3] = 255
            payload[4] = 255
            payload[5] = 2
        }
        return request(feature: feature, function: 3, tag: tag, payload: payload)
    }

    static func response(_ bytes: [UInt8], to request: [UInt8]) throws -> [UInt8]? {
        guard bytes.count >= 7, bytes[1] == address else { return nil }
        guard (bytes[0] == 0x10 && bytes.count == 7) || (bytes[0] == 0x11 && bytes.count == 20)
        else { return nil }
        if (bytes[2] == 0xff || bytes[2] == 0x8f), bytes[3] == request[2], bytes[4] == request[3] {
            throw MouseLightingError.deviceError(bytes[5])
        }
        guard bytes[2] == request[2], bytes[3] == request[3] else { return nil }
        return Array(bytes.dropFirst(4))
    }
}

struct LightingZone {
    let index: UInt8
    let offEffect: UInt8
    let whiteEffect: UInt8?
}

struct LightingCapabilities {
    let feature: UInt8
    let zones: [LightingZone]
}

/// The same command sequence is used by IOKit and deterministic transport tests.
final class LightingCommands {
    private let exchange: ([UInt8]) throws -> [UInt8]
    private var tag: UInt8 = 0

    init(exchange: @escaping ([UInt8]) throws -> [UInt8]) { self.exchange = exchange }

    private func nextTag() -> UInt8 {
        tag = (tag % 15) + 1
        return tag
    }

    func inspect() throws -> LightingCapabilities {
        let reply = try exchange(HIDPP.featureQuery(0x8070, tag: nextTag()))
        guard let feature = reply.first, feature != 0 else {
            throw MouseLightingError.unsupported("HID++ 0x8070がありません。")
        }
        let info = try exchange(HIDPP.lightingInfo(feature: feature, tag: nextTag()))
        let count = try HIDPP.zoneCount(info)
        var zones: [LightingZone] = []
        for zone in 0..<count {
            let zoneInfo = try exchange(HIDPP.zoneInfo(feature: feature, zone: zone, tag: nextTag()))
            let effects = try HIDPP.effectCount(zoneInfo, zone: zone)
            var off: UInt8?
            var white: UInt8?
            for effect in 0..<effects {
                let effectInfo = try exchange(
                    HIDPP.effectInfo(feature: feature, zone: zone, effect: effect, tag: nextTag()))
                switch try HIDPP.effectID(effectInfo, zone: zone, effect: effect) {
                case 0x0000: off = effect
                case 0x0001: white = effect
                default: break
                }
                if off != nil && white != nil { break }
            }
            guard let off else {
                throw MouseLightingError.unsupported("ゾーン\(zone + 1)に消灯効果がありません。")
            }
            zones.append(LightingZone(index: zone, offEffect: off, whiteEffect: white))
        }
        return LightingCapabilities(feature: feature, zones: zones)
    }

    func apply(_ mode: LightingMode, capabilities: LightingCapabilities) throws -> Int {
        // Validate every target zone before the first state-changing command.
        let effects = try capabilities.zones.map { zone -> UInt8 in
            if mode == .off { return zone.offEffect }
            guard let effect = zone.whiteEffect else {
                throw MouseLightingError.unsupported("ゾーン\(zone.index + 1)に白色点灯効果がありません。")
            }
            return effect
        }
        _ = try exchange(HIDPP.temporaryControl(feature: capabilities.feature, tag: nextTag()))
        for (zone, effect) in zip(capabilities.zones, effects) {
            _ = try exchange(
                HIDPP.lighting(
                    feature: capabilities.feature, zone: zone.index, effect: effect,
                    mode: mode, tag: nextTag()))
        }
        return effects.count
    }
}
