import AppKit

protocol DistributedRecoveryCenter: AnyObject {
    func addObserver(
        _ observer: Any, selector: Selector, name: Notification.Name?, object: String?,
        suspensionBehavior: DistributedNotificationCenter.SuspensionBehavior)
    func removeObserver(_ observer: Any)
}

extension DistributedNotificationCenter: DistributedRecoveryCenter {}

/// Workspace notifications cover system/display wake and user switching.
/// The distributed lock names are supplemental, undocumented macOS notifications;
/// correctness on normal wake must not depend on their delivery.
final class RecoveryEventMonitor: NSObject {
    static let workspaceEvents: [(Notification.Name, RecoveryEvent)] = [
        (NSWorkspace.didWakeNotification, .systemWake),
        (NSWorkspace.screensDidWakeNotification, .screensWake),
        (NSWorkspace.sessionDidBecomeActiveNotification, .sessionActive),
        (NSWorkspace.willSleepNotification, .systemSleep),
        (NSWorkspace.screensDidSleepNotification, .screensSleep),
        (NSWorkspace.sessionDidResignActiveNotification, .sessionInactive),
    ]
    static let distributedEvents: [(Notification.Name, RecoveryEvent)] = [
        (Notification.Name("com.apple.screenIsUnlocked"), .screenUnlocked),
        (Notification.Name("com.apple.screenIsLocked"), .screenLocked),
    ]

    var onEvent: (RecoveryEvent) -> Void = { _ in }
    private let workspaceCenter: NotificationCenter
    private let distributedCenter: DistributedRecoveryCenter
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        distributedCenter: DistributedRecoveryCenter = DistributedNotificationCenter.default()
    ) {
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
        super.init()
    }

    func start() {
        stop()
        isStarted = true
        for (name, event) in Self.workspaceEvents {
            let observer = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                guard let self, self.isStarted else { return }
                self.onEvent(event)
            }
            observers.append(observer)
        }
        for (name, _) in Self.distributedEvents {
            // AppKit suspends distributed notifications while an app is inactive.
            // A menu bar app must receive unlock even when its settings window is closed.
            distributedCenter.addObserver(
                self, selector: #selector(receiveDistributed(_:)), name: name,
                object: nil, suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func receiveDistributed(_ notification: Notification) {
        guard isStarted,
            let event = Self.distributedEvents.first(where: { $0.0 == notification.name })?.1
        else { return }
        onEvent(event)
    }

    func stop() {
        isStarted = false
        for observer in observers { workspaceCenter.removeObserver(observer) }
        observers.removeAll()
        distributedCenter.removeObserver(self)
    }

    deinit { stop() }
}
