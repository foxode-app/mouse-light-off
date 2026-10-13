import CryptoKit
import Darwin
import Foundation

/// Local, private raw-profile backups. Never include these files in release artifacts.
final class OnboardBackupStore {
    private struct Record: Codable {
        let schema: Int
        let productID: Int
        let deviceIdentity: String
        let snapshot: OnboardLightingSnapshot
    }

    let directory: URL
    private let lockDirectory: URL
    private let deviceIdentity: String
    private var restoreURL: URL { directory.appendingPathComponent("g403-hero-before-off.json") }

    init(deviceIdentity: String, directory: URL? = nil) throws {
        self.deviceIdentity = deviceIdentity
        let identityHash = SHA256.hash(data: Data(deviceIdentity.utf8)).map { String(format: "%02x", $0) }
            .joined()
        let baseDirectory =
            try directory
            ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("Mouse Light Off/Backups", isDirectory: true)
        self.directory = directory ?? baseDirectory.appendingPathComponent(identityHash, isDirectory: true)
        lockDirectory = baseDirectory
    }

    func acquireExclusiveAccess() throws -> OnboardWriteLease {
        try FileManager.default.createDirectory(
            at: lockDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return try OnboardWriteLease(url: lockDirectory.appendingPathComponent("write.lock"))
    }

    func save(_ snapshot: OnboardLightingSnapshot, forRestoration: Bool) throws {
        let manager = FileManager.default
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(
            Record(schema: 1, productID: 0xc08f, deviceIdentity: deviceIdentity, snapshot: snapshot))
        // Keep history even when a new successful request replaces the restoration baseline.
        try write(data, to: directory.appendingPathComponent(UUID().uuidString + ".json"))
        if forRestoration { try write(data, to: restoreURL) }
    }

    func loadForRestoration() throws -> OnboardLightingSnapshot {
        guard FileManager.default.fileExists(atPath: restoreURL.path) else {
            throw MouseLightingError.unsupported("保存前の照明バックアップがありません。")
        }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: restoreURL))
        guard record.schema == 1, record.productID == 0xc08f,
            record.deviceIdentity == deviceIdentity
        else {
            throw MouseLightingError.unsupported("照明バックアップがこのマウスと一致しません。個体識別情報のないマウスは同じ接続中のみ復元できます。")
        }
        return record.snapshot
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        guard try Data(contentsOf: url) == data else {
            throw MouseLightingError.unsupported("本体設定のバックアップを検証できませんでした。")
        }
    }
}

/// Serializes all app and CLI writers, including devices without stable serial numbers.
final class OnboardWriteLease {
    private var descriptor: Int32

    init(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else {
            throw MouseLightingError.unsupported("本体保存のロックファイルを開けません。")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            descriptor = -1
            throw MouseLightingError.unsupported("別のMouse Light Offが本体を保存しています。完了後に再操作してください。")
        }
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}
