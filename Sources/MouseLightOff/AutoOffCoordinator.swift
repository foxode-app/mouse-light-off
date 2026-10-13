import Foundation

/// Shared with the HID worker; cancellation is observed between complete HID++ requests.
final class LightingOperationToken {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

protocol RecoveryScheduledTask {
    func cancel()
}

private struct DispatchRecoveryTask: RecoveryScheduledTask {
    let item: DispatchWorkItem
    func cancel() { item.cancel() }
}

enum RecoveryEvent: String {
    case launch, deviceChanged, systemWake, screensWake, sessionActive, screenUnlocked, enabled
    case systemSleep, screensSleep, sessionInactive, screenLocked

    var suspendsRecovery: Bool {
        switch self {
        case .systemSleep, .screensSleep, .sessionInactive, .screenLocked: return true
        default: return false
        }
    }
}

enum LightingOperation: String {
    case off, white, inspect
    case inspectOnboard, saveOnboardOff, restoreOnboardLighting

    var writesOnboard: Bool {
        self == .saveOnboardOff || self == .restoreOnboardLighting
    }
}

struct RecoveryDiagnostic {
    let reason: String
    let attempt: Int
    let result: String
}

/// Main-thread state machine. A recovery window is finite, even when notifications repeat.
/// Successful attempts are repeated too: the mouse can reset after the first acknowledgement.
final class AutoOffCoordinator {
    typealias Completion = (Result<String, Error>) -> Void
    typealias Execute = (LightingOperation, LightingOperationToken, @escaping Completion) -> Void
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> RecoveryScheduledTask

    static let attemptOffsets: [TimeInterval] = [0.5, 2, 5, 10, 20]

    var onStatus: (String) -> Void = { _ in }
    var onDiagnostic: (RecoveryDiagnostic) -> Void = { _ in }
    var onOnboardWriteStateChanged: (Bool) -> Void = { _ in }
    private(set) var isEnabled: Bool
    var isBusy: Bool { active != nil }
    var isWritingOnboard: Bool { active?.operation.writesOnboard == true }

    private final class Request {
        let generation: UInt64
        let operation: LightingOperation
        let attempt: Int
        let reason: String
        let token = LightingOperationToken()

        init(generation: UInt64, operation: LightingOperation, attempt: Int, reason: String) {
            self.generation = generation
            self.operation = operation
            self.attempt = attempt
            self.reason = reason
        }
    }

    private let execute: Execute
    private let schedule: Schedule
    private var generation: UInt64 = 0
    private var tasks: [RecoveryScheduledTask] = []
    private var active: Request?
    private var pending: Request?
    private var windowReasons: Set<String> = []
    private var finalAttemptDue = false
    private var suspended = false
    private var terminated = false

    init(
        enabled: Bool, schedule: @escaping Schedule = AutoOffCoordinator.scheduleOnMain,
        execute: @escaping Execute
    ) {
        isEnabled = enabled
        self.schedule = schedule
        self.execute = execute
    }

    static func scheduleOnMain(after delay: TimeInterval, action: @escaping () -> Void)
        -> RecoveryScheduledTask
    {
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return DispatchRecoveryTask(item: item)
    }

    func handle(_ event: RecoveryEvent) {
        guard !terminated else { return }
        // A profile update must finish its write and readback before another operation runs.
        // Recovery always uses RAM-only .off; it must never retry a persistent write.
        if isWritingOnboard {
            if event.suspendsRecovery {
                suspended = true
            } else if event != .deviceChanged {
                suspended = false
            }
            return
        }
        if event.suspendsRecovery {
            suspended = true
            cancel(reason: event.rawValue)
            return
        }
        // USB changes alone must not reactivate recovery while the screen/session is asleep.
        if event != .deviceChanged { suspended = false }
        guard !suspended else { return }
        guard isEnabled else {
            if event == .launch || event == .deviceChanged { performManual(.inspect) }
            return
        }
        beginWindow(reason: event.rawValue)
    }

    func setEnabled(_ enabled: Bool) {
        guard !terminated, !isWritingOnboard, enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            handle(.enabled)
        } else {
            cancel(reason: "disabled")
            onStatus("自動消灯を停止しました。現在の照明は変更しません。")
        }
    }

    func performManual(_ operation: LightingOperation) {
        guard !terminated, !isWritingOnboard else { return }
        cancel(reason: "manual_\(operation.rawValue)")
        pending = Request(
            generation: generation, operation: operation, attempt: 0,
            reason: "manual_\(operation.rawValue)")
        drain()
    }

    func stop() {
        terminated = true
        cancel(reason: "terminated")
    }

    private func beginWindow(reason: String) {
        if !windowReasons.isEmpty {
            if windowReasons.insert(reason).inserted {
                onDiagnostic(.init(reason: reason, attempt: 0, result: "coalesced"))
            }
            return
        }
        cancel(reason: "new_window")
        windowReasons = [reason]
        finalAttemptDue = false
        let currentGeneration = generation
        onStatus("復帰後の自動消灯を準備しています（間隔をあけて最大5回）。")
        onDiagnostic(.init(reason: reason, attempt: 0, result: "scheduled"))
        for (index, offset) in Self.attemptOffsets.enumerated() {
            tasks.append(
                schedule(offset) { [weak self] in
                    guard let self, self.generation == currentGeneration, self.isEnabled,
                        !self.suspended, !self.terminated
                    else { return }
                    let attempt = index + 1
                    self.finalAttemptDue = attempt == Self.attemptOffsets.count
                    // If HID is busy, combine overdue attempts into one pending attempt.
                    self.pending?.token.cancel()
                    self.pending = Request(
                        generation: currentGeneration, operation: .off, attempt: attempt,
                        reason: self.windowReasons.sorted().joined(separator: ","))
                    self.drain()
                })
        }
    }

    private func cancel(reason: String) {
        generation &+= 1
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        pending?.token.cancel()
        pending = nil
        if !isWritingOnboard { active?.token.cancel() }
        windowReasons.removeAll()
        finalAttemptDue = false
        onDiagnostic(.init(reason: reason, attempt: 0, result: "cancelled"))
    }

    private func drain() {
        guard active == nil, let request = pending, !terminated else { return }
        pending = nil
        active = request
        if request.operation.writesOnboard { onOnboardWriteStateChanged(true) }
        let text: String
        switch request.operation {
        case .off: text = "消灯を要求しています…"
        case .white: text = "白色点灯を要求しています…"
        case .inspect: text = "接続を確認しています…"
        case .inspectOnboard: text = "本体の照明設定を確認しています…"
        case .saveOnboardOff: text = "本体に消灯を保存しています。完了までマウスを抜かないでください…"
        case .restoreOnboardLighting: text = "保存前の照明に戻しています。完了までマウスを抜かないでください…"
        }
        onStatus(text)
        onDiagnostic(.init(reason: request.reason, attempt: request.attempt, result: "started"))
        execute(request.operation, request.token) { [weak self, weak request] result in
            guard let self, let request, self.active === request else { return }
            self.active = nil
            if (self.generation == request.generation || request.operation.writesOnboard),
                !request.token.isCancelled
            {
                let message: String
                let outcome: String
                switch result {
                case .success(let value):
                    message = value
                    outcome = "success"
                case .failure(let error):
                    message = error.localizedDescription
                    outcome = "failure"
                }
                let waiting = request.attempt > 0 && (!self.finalAttemptDue || self.pending != nil)
                self.onStatus(message + (waiting ? "\n復帰後の再適用を待機中です（最大5回）。" : ""))
                self.onDiagnostic(.init(reason: request.reason, attempt: request.attempt, result: outcome))
                if request.attempt > 0, self.finalAttemptDue, self.pending == nil {
                    self.windowReasons.removeAll()
                    self.tasks.removeAll()
                }
            } else {
                self.onDiagnostic(
                    .init(reason: request.reason, attempt: request.attempt, result: "cancelled"))
            }
            self.drain()
            if request.operation.writesOnboard { self.onOnboardWriteStateChanged(false) }
        }
    }
}
