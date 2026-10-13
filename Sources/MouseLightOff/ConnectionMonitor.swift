import Foundation
import IOKit.hid
import MouseLighting

/// Watches USB arrival/removal without opening or seizing input devices.
final class ConnectionMonitor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var onChange: (() -> Void)?

    func start() {
        let matching = SupportedMouse.devices.map { mouse in
            [kIOHIDVendorIDKey: mouse.vendorID, kIOHIDProductIDKey: mouse.productID]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<ConnectionMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.onChange?()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
    }
}
