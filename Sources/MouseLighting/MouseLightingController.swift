import Foundation
import IOKit.hid

/// Each operation owns its HID connections. Invoke from a serial worker queue, not the UI thread.
public final class MouseLightingController {
    public init() {}

    public func inspect(shouldContinue: () -> Bool = { true }) throws -> String {
        try operate(shouldContinue: shouldContinue) { _, capabilities in
            String(
                format: "照明%dゾーンを確認しました（0x8070 / index 0x%02x）。",
                capabilities.zones.count, capabilities.feature)
        }
    }

    public func setLighting(_ mode: LightingMode, shouldContinue: () -> Bool = { true }) throws -> String {
        try operate(shouldContinue: shouldContinue) { commands, capabilities in
            let count = try commands.apply(mode, capabilities: capabilities, shouldContinue: shouldContinue)
            return mode == .off
                ? "照明\(count)ゾーンの消灯命令に応答がありました。"
                : "照明\(count)ゾーンの白色点灯命令に応答がありました。"
        }
    }

    private func operate(
        shouldContinue: () -> Bool = { true },
        _ operation: (LightingCommands, LightingCapabilities) throws -> String
    ) throws -> String {
        guard shouldContinue() else { throw CancellationError() }
        let devices = connectedMice()
        return try MouseBatch.perform(devices, name: { $0.name }) { mouse in
            guard shouldContinue() else { throw CancellationError() }
            // Alternate interfaces are tried using only read-only discovery requests.
            // Once lighting changes begin, failures never cause a retry on another interface.
            let (session, commands, capabilities) = try mouse.openLightingSession(
                shouldContinue: shouldContinue)
            return try withExtendedLifetime(session) { try operation(commands, capabilities) }
        }
    }
}

/// Isolates selection/deduplication from IOKit so filtering can be regression tested.
struct MouseInterface: Equatable {
    let vendorID: Int
    let productID: Int
    let transport: String
    let usagePage: Int
    let usage: Int
    let outputSize: Int
    let physicalID: String
    let interfaceID: UInt64

    var supportedMouse: SupportedMouse? {
        // IOKit may expose a composite keyboard primary collection (1:6) even when
        // this interface contains the HID++ reports; G403 HERO uses that layout.
        // Do not confuse PrimaryUsagePage with HIDAPI's individual report collection.
        guard transport == "USB", outputSize >= 20,
            !physicalID.isEmpty
        else { return nil }
        return SupportedMouse.match(vendorID: vendorID, productID: productID)
    }

    static func groups(_ interfaces: [MouseInterface]) -> [[MouseInterface]] {
        let supported = interfaces.filter { $0.supportedMouse != nil }
        let grouped = Dictionary(grouping: supported) {
            "\($0.vendorID):\($0.productID):\($0.physicalID)"
        }
        return grouped.keys.sorted().map { key in
            // Usage 2 is the long HID++ report interface in OpenRGB's detector.
            grouped[key]!.sorted {
                if ($0.usage == 2) != ($1.usage == 2) { return $0.usage == 2 }
                return $0.interfaceID < $1.interfaceID
            }
        }
    }
}

private struct ConnectedMouse {
    let name: String
    let interfaces: [IOHIDDevice]

    func openLightingSession(shouldContinue: () -> Bool) throws -> (
        HIDSession, LightingCommands, LightingCapabilities
    ) {
        var lastError: Error = MouseLightingError.notConnected
        for interface in interfaces {
            guard shouldContinue() else { throw CancellationError() }
            do {
                let session = try HIDSession(device: interface)
                let commands = LightingCommands(exchange: session.exchange)
                let capabilities = try commands.inspect(shouldContinue: shouldContinue)
                return (session, commands, capabilities)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

private func connectedMice() -> [ConnectedMouse] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching = SupportedMouse.devices.map {
        [kIOHIDVendorIDKey: $0.vendorID, kIOHIDProductIDKey: $0.productID]
    }
    IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
    let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    var handles: [UInt64: IOHIDDevice] = [:]
    let interfaces = devices.compactMap { device -> MouseInterface? in
        func number(_ key: String) -> Int {
            (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
        }
        let service = IOHIDDeviceGetService(device)
        var interfaceID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &interfaceID) == kIOReturnSuccess else {
            return nil
        }
        let location = number(kIOHIDLocationIDKey)
        let physicalID: String
        if let usbID = usbDeviceRegistryID(service) {
            physicalID = "usb:\(usbID)"
        } else if location != 0 {
            physicalID = "location:\(location)"
        } else {
            // An unidentified physical device cannot be safely deduplicated.
            return nil
        }
        handles[interfaceID] = device
        return MouseInterface(
            vendorID: number(kIOHIDVendorIDKey), productID: number(kIOHIDProductIDKey),
            transport: IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "",
            usagePage: number(kIOHIDPrimaryUsagePageKey), usage: number(kIOHIDPrimaryUsageKey),
            outputSize: number(kIOHIDMaxOutputReportSizeKey), physicalID: physicalID,
            interfaceID: interfaceID)
    }
    let groups = MouseInterface.groups(interfaces)
    var occurrences: [Int: Int] = [:]
    return groups.map { group in
        let model = group[0].supportedMouse!
        occurrences[model.productID, default: 0] += 1
        let hasDuplicates = groups.filter { $0[0].productID == model.productID }.count > 1
        let suffix = hasDuplicates ? " (\(occurrences[model.productID]!))" : ""
        return ConnectedMouse(
            name: model.name + suffix,
            interfaces: group.compactMap { handles[$0.interfaceID] })
    }
}

/// All HID collections for one USB mouse share the same parent USB device entry.
private func usbDeviceRegistryID(_ service: io_registry_entry_t) -> UInt64? {
    guard service != 0 else { return nil }
    IOObjectRetain(service)
    var current = service
    while true {
        if IOObjectConformsTo(current, "IOUSBHostDevice") != 0
            || IOObjectConformsTo(current, "IOUSBDevice") != 0
        {
            var identifier: UInt64 = 0
            let result = IORegistryEntryGetRegistryEntryID(current, &identifier)
            IOObjectRelease(current)
            return result == kIOReturnSuccess ? identifier : nil
        }
        var parent: io_registry_entry_t = 0
        let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
        IOObjectRelease(current)
        guard result == kIOReturnSuccess else { return nil }
        current = parent
    }
}

private final class HIDSession {
    private let device: IOHIDDevice
    private let runLoop: CFRunLoop
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize = 64
    private var incoming: [[UInt8]] = []

    init(device: IOHIDDevice) throws {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPermitted || result == kIOReturnNotPrivileged {
                throw MouseLightingError.permissionRequired
            }
            throw MouseLightingError.transport("USB接続", result)
        }
        self.device = device
        runLoop = CFRunLoopGetCurrent()
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, bufferSize,
            { context, result, _, _, reportID, report, length in
                guard let context, result == kIOReturnSuccess, reportID == 0x10 || reportID == 0x11,
                    length > 0, length <= 64
                else { return }
                let session = Unmanaged<HIDSession>.fromOpaque(context).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                // Ignore normal mouse and keyboard input; retain only HID++ replies.
                guard bytes.first == UInt8(reportID), bytes.count >= 7 else { return }
                if session.incoming.count < 64 { session.incoming.append(bytes) }
            }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deinitialize(count: bufferSize)
        buffer.deallocate()
    }

    func exchange(_ request: [UInt8]) throws -> [UInt8] {
        incoming.removeAll(keepingCapacity: true)
        let result = request.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(
                device, kIOHIDReportTypeOutput, CFIndex(request[0]), $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { throw MouseLightingError.transport("照明命令の送信", result) }
        let deadline = ProcessInfo.processInfo.systemUptime + 1.2
        repeat {
            while !incoming.isEmpty {
                if let response = try HIDPP.response(incoming.removeFirst(), to: request) { return response }
            }
            CFRunLoopRunInMode(.defaultMode, 0.02, true)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw MouseLightingError.timeout
    }
}
