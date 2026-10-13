import Foundation

/// USB models using HID++ 2.0 color LED effects (0x8070).
/// Protocol compatibility is checked again on each connected device before changing its LEDs.
public struct SupportedMouse: Equatable, Sendable {
    public let name: String
    public let productID: Int
    public let hardwareVerified: Bool
    public var vendorID: Int { 0x046d }

    // IDs and protocol families: OpenRGB's LogitechControllerDetect.cpp.
    // Exclude receivers and 0x8071 models such as G203 LIGHTSYNC.
    public static let devices: [SupportedMouse] = [
        .init(name: "G203 Prodigy", productID: 0xc084, hardwareVerified: false),
        .init(name: "G303 Daedalus Apex", productID: 0xc080, hardwareVerified: false),
        .init(name: "G403 Prodigy", productID: 0xc083, hardwareVerified: false),
        .init(name: "G403 HERO", productID: 0xc08f, hardwareVerified: true),
        .init(name: "G502 Proteus Spectrum", productID: 0xc332, hardwareVerified: false),
        .init(name: "G502 HERO", productID: 0xc08b, hardwareVerified: false),
        .init(name: "G PRO", productID: 0xc085, hardwareVerified: false),
        .init(name: "G PRO HERO", productID: 0xc08c, hardwareVerified: false),
    ]

    public static func match(vendorID: Int, productID: Int) -> SupportedMouse? {
        devices.first { $0.vendorID == vendorID && $0.productID == productID }
    }
}

/// A batch with any failure throws this error, including successful devices in its summary.
public struct MouseBatchError: LocalizedError {
    public let results: [String]
    public var errorDescription: String? { results.joined(separator: "\n") }
}

enum MouseBatch {
    static func perform<T>(
        _ devices: [T], name: (T) -> String, operation: (T) throws -> String
    ) throws -> String {
        guard !devices.isEmpty else { throw MouseLightingError.notConnected }
        var results: [String] = []
        var hadFailure = false
        for device in devices {
            do {
                results.append("\(name(device)): \(try operation(device))")
            } catch {
                hadFailure = true
                results.append("\(name(device)): 失敗 — \(error.localizedDescription)")
            }
        }
        if hadFailure { throw MouseBatchError(results: results) }
        return results.joined(separator: "\n")
    }
}
