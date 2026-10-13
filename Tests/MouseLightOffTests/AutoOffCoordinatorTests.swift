import AppKit
import XCTest

@testable import MouseLightOff

final class AutoOffCoordinatorTests: XCTestCase {
    func testSuccessStillReappliesFiveTimesAtFiniteOffsets() {
        let fixture = Fixture()
        fixture.coordinator.handle(.systemWake)
        for (index, offset) in AutoOffCoordinator.attemptOffsets.enumerated() {
            fixture.clock.advance(to: offset)
            XCTAssertEqual(fixture.executor.calls.count, index + 1)
            XCTAssertEqual(fixture.executor.calls.last?.operation, .off)
            fixture.executor.completeLast(.success("off"))
        }
        fixture.clock.advance(to: 1000)
        XCTAssertEqual(fixture.executor.calls.count, 5)
        XCTAssertEqual(fixture.status.last, "off")
    }

    func testTemporaryAndPermanentFailuresAreBothBounded() {
        let fixture = Fixture()
        fixture.coordinator.handle(.screenUnlocked)
        for (index, offset) in AutoOffCoordinator.attemptOffsets.enumerated() {
            fixture.clock.advance(to: offset)
            fixture.executor.completeLast(index == 1 ? .success("off") : .failure(Failure.unavailable))
        }
        fixture.clock.advance(to: 1000)
        XCTAssertEqual(fixture.executor.calls.count, 5)
        XCTAssertEqual(fixture.diagnostics.filter { $0.result == "failure" }.count, 4)
        XCTAssertEqual(fixture.diagnostics.filter { $0.result == "success" }.count, 1)
        XCTAssertEqual(fixture.status.last, Failure.unavailable.localizedDescription)
    }

    func testDuplicateNotificationsDoNotExtendWindow() {
        let fixture = Fixture()
        fixture.coordinator.handle(.systemWake)
        fixture.coordinator.handle(.screensWake)
        fixture.coordinator.handle(.screenUnlocked)
        fixture.coordinator.handle(.systemWake)
        for offset in AutoOffCoordinator.attemptOffsets {
            fixture.clock.advance(to: offset)
            if offset == 10 { fixture.coordinator.handle(.deviceChanged) }
            fixture.executor.completeLast(.success("off"))
        }
        fixture.clock.advance(to: 100)
        XCTAssertEqual(fixture.executor.calls.count, 5)
        XCTAssertEqual(fixture.clock.createdCount, 5)
        XCTAssertEqual(fixture.diagnostics.filter { $0.result == "coalesced" }.count, 3)
    }

    func testNewEventAfterCompletedWindowStartsFreshWindow() {
        let fixture = Fixture()
        fixture.coordinator.handle(.launch)
        for offset in AutoOffCoordinator.attemptOffsets {
            fixture.clock.advance(to: offset)
            fixture.executor.completeLast(.success("off"))
        }
        fixture.clock.advance(to: 25)
        fixture.coordinator.handle(.deviceChanged)
        fixture.clock.advance(to: 25.5)
        XCTAssertEqual(fixture.executor.calls.count, 6)
    }

    func testBusyOperationsNeverOverlapAndOverdueAttemptsCoalesce() {
        let fixture = Fixture()
        fixture.coordinator.handle(.systemWake)
        fixture.clock.advance(to: 0.5)
        fixture.clock.advance(to: 20)
        XCTAssertEqual(fixture.executor.calls.count, 1)
        XCTAssertTrue(fixture.coordinator.isBusy)
        fixture.executor.completeLast(.success("off"))
        XCTAssertEqual(fixture.executor.calls.count, 2)
        fixture.executor.completeLast(.success("off"))
        XCTAssertFalse(fixture.coordinator.isBusy)
        XCTAssertEqual(fixture.diagnostics.filter { $0.result == "started" }.map(\.attempt), [1, 5])
        fixture.clock.advance(to: 100)
        XCTAssertEqual(fixture.executor.calls.count, 2)
    }

    func testSleepCancelsScheduledAndActiveWorkAndIgnoresStaleCompletion() {
        for event: RecoveryEvent in [.systemSleep, .screensSleep, .sessionInactive, .screenLocked] {
            let fixture = Fixture()
            fixture.coordinator.handle(.systemWake)
            fixture.clock.advance(to: 0.5)
            fixture.coordinator.handle(event)
            XCTAssertTrue(fixture.executor.calls[0].token.isCancelled)
            fixture.coordinator.handle(.deviceChanged)
            let statusBefore = fixture.status
            fixture.executor.completeLast(.success("stale"))
            fixture.clock.advance(to: 100)
            XCTAssertEqual(fixture.executor.calls.count, 1)
            XCTAssertEqual(fixture.status, statusBefore)
            fixture.coordinator.handle(.screenUnlocked)
            fixture.clock.advance(to: 100.5)
            XCTAssertEqual(fixture.executor.calls.count, 2)
        }
    }

    func testDisabledCancelsAndReenabledStartsFreshWindow() {
        let fixture = Fixture()
        fixture.coordinator.handle(.launch)
        fixture.clock.advance(to: 0.5)
        fixture.coordinator.setEnabled(false)
        XCTAssertTrue(fixture.executor.calls[0].token.isCancelled)
        fixture.executor.completeLast(.failure(Failure.unavailable))
        fixture.clock.advance(to: 50)
        XCTAssertEqual(fixture.executor.calls.count, 1)
        XCTAssertTrue(fixture.status.last?.contains("自動消灯を停止") == true)
        fixture.coordinator.setEnabled(true)
        fixture.clock.advance(to: 50.5)
        XCTAssertEqual(fixture.executor.calls.count, 2)
    }

    func testManualWhiteCancelsAutoAndWaitsForInFlightHID() {
        let fixture = Fixture()
        fixture.coordinator.handle(.systemWake)
        fixture.clock.advance(to: 0.5)
        fixture.coordinator.performManual(.white)
        XCTAssertTrue(fixture.executor.calls[0].token.isCancelled)
        XCTAssertEqual(fixture.executor.calls.count, 1)
        fixture.executor.completeLast(.success("stale off"))
        XCTAssertEqual(fixture.executor.calls.map(\.operation), [.off, .white])
        fixture.executor.completeLast(.success("white"))
        fixture.clock.advance(to: 100)
        XCTAssertEqual(fixture.executor.calls.count, 2)
        XCTAssertEqual(fixture.status.last, "white")
        XCTAssertFalse(fixture.status.contains("stale off"))
        fixture.coordinator.handle(.deviceChanged)
        fixture.clock.advance(to: 100.5)
        XCTAssertEqual(fixture.executor.calls.last?.operation, .off)
    }

    func testManualWhiteBeforeFirstAttemptPreventsAllReservedOffWrites() {
        let fixture = Fixture()
        fixture.coordinator.handle(.screensWake)
        fixture.coordinator.performManual(.white)
        fixture.executor.completeLast(.success("white"))
        fixture.clock.advance(to: 100)
        XCTAssertEqual(fixture.executor.calls.map(\.operation), [.white])
    }

    func testOnboardWritesRunOnceWithoutAutomaticPersistentRetries() {
        for operation: LightingOperation in [.saveOnboardOff, .restoreOnboardLighting] {
            for fails in [false, true] {
                let fixture = Fixture()
                fixture.coordinator.handle(.systemWake)
                fixture.coordinator.performManual(operation)
                XCTAssertTrue(fixture.coordinator.isWritingOnboard)
                fixture.executor.completeLast(fails ? .failure(Failure.unavailable) : .success("saved"))
                fixture.clock.advance(to: 1000)
                fixture.clock.fireCancelledTasks()
                XCTAssertEqual(fixture.executor.calls.map(\.operation), [operation])
                XCTAssertEqual(fixture.onboardWriteStates, [true, false])
                XCTAssertFalse(fixture.coordinator.isWritingOnboard)
                fixture.coordinator.handle(.screenUnlocked)
                fixture.clock.advance(to: 1000.5)
                XCTAssertEqual(fixture.executor.calls.map(\.operation), [operation, .off])
            }
        }
    }

    func testPendingOnboardWriteCanBeCancelledBeforeItStarts() {
        for operation: LightingOperation in [.saveOnboardOff, .restoreOnboardLighting] {
            let fixture = Fixture()
            fixture.coordinator.performManual(.inspect)
            fixture.coordinator.performManual(operation)
            XCTAssertTrue(fixture.executor.calls[0].token.isCancelled)
            XCTAssertFalse(fixture.coordinator.isWritingOnboard)
            fixture.coordinator.performManual(.white)
            fixture.executor.completeLast(.success("stale inspect"))
            XCTAssertEqual(fixture.executor.calls.map(\.operation), [.inspect, .white])
            fixture.executor.completeLast(.success("white"))
            fixture.clock.advance(to: 100)
            XCTAssertTrue(fixture.onboardWriteStates.isEmpty)
            XCTAssertEqual(fixture.status.last, "white")
        }
    }

    func testOnboardWriteWaitsForExistingHIDOperationBeforeProtectingItself() {
        let fixture = Fixture()
        fixture.coordinator.performManual(.off)
        fixture.coordinator.performManual(.saveOnboardOff)
        XCTAssertEqual(fixture.executor.calls.count, 1)
        XCTAssertTrue(fixture.onboardWriteStates.isEmpty)
        fixture.executor.completeLast(.success("stale off"))
        XCTAssertEqual(fixture.executor.calls.map(\.operation), [.off, .saveOnboardOff])
        XCTAssertEqual(fixture.onboardWriteStates, [true])
        fixture.executor.completeLast(.success("saved"))
        XCTAssertEqual(fixture.onboardWriteStates, [true, false])
        XCTAssertEqual(fixture.status.last, "saved")
    }

    func testActiveOnboardWriteIsNotInterruptedByRecoveryOrManualChanges() {
        for operation: LightingOperation in [.saveOnboardOff, .restoreOnboardLighting] {
            let fixture = Fixture()
            fixture.coordinator.performManual(operation)
            fixture.coordinator.handle(.screensSleep)
            fixture.coordinator.handle(.screenLocked)
            fixture.coordinator.handle(.screenUnlocked)
            fixture.coordinator.handle(.deviceChanged)
            fixture.coordinator.performManual(.white)
            fixture.coordinator.performManual(.saveOnboardOff)
            fixture.coordinator.setEnabled(false)
            fixture.clock.advance(to: 100)
            XCTAssertEqual(fixture.executor.calls.map(\.operation), [operation])
            XCTAssertFalse(fixture.executor.calls[0].token.isCancelled)
            XCTAssertTrue(fixture.coordinator.isEnabled)
            fixture.executor.completeLast(.success("saved"))
            XCTAssertEqual(fixture.onboardWriteStates, [true, false])
            XCTAssertEqual(fixture.status.last, "saved")
            fixture.clock.advance(to: 1000)
            XCTAssertEqual(fixture.executor.calls.count, 1)
        }
    }

    func testStopCancelsPendingOnboardWriteButLetsActiveWriteComplete() {
        let pending = Fixture()
        pending.coordinator.performManual(.inspect)
        pending.coordinator.performManual(.saveOnboardOff)
        pending.coordinator.stop()
        pending.executor.completeLast(.success("stale"))
        XCTAssertEqual(pending.executor.calls.map(\.operation), [.inspect])
        XCTAssertTrue(pending.onboardWriteStates.isEmpty)

        for operation: LightingOperation in [.saveOnboardOff, .restoreOnboardLighting] {
            let fixture = Fixture()
            fixture.coordinator.performManual(operation)
            fixture.coordinator.stop()
            XCTAssertFalse(fixture.executor.calls[0].token.isCancelled)
            XCTAssertTrue(fixture.coordinator.isWritingOnboard)
            fixture.executor.completeLast(.success("saved before termination"))
            XCTAssertEqual(fixture.onboardWriteStates, [true, false])
            XCTAssertFalse(fixture.coordinator.isBusy)
            XCTAssertEqual(fixture.status.last, "saved before termination")
            fixture.coordinator.handle(.systemWake)
            fixture.coordinator.performManual(.saveOnboardOff)
            fixture.clock.advance(to: 100)
            XCTAssertEqual(fixture.executor.calls.count, 1)
        }
    }

    func testOnboardInspectionRemainsCancellableReadOnlyWork() {
        let fixture = Fixture()
        fixture.coordinator.performManual(.inspectOnboard)
        XCTAssertFalse(fixture.coordinator.isWritingOnboard)
        fixture.coordinator.performManual(.white)
        XCTAssertTrue(fixture.executor.calls[0].token.isCancelled)
        fixture.executor.completeLast(.success("stale inspection"))
        XCTAssertEqual(fixture.executor.calls.map(\.operation), [.inspectOnboard, .white])
        fixture.executor.completeLast(.success("white"))
        XCTAssertTrue(fixture.onboardWriteStates.isEmpty)
        XCTAssertEqual(fixture.status.last, "white")
    }

    func testLateOldCompletionCannotOverwriteNewWindowOrStartOldAttempts() {
        let fixture = Fixture()
        fixture.coordinator.handle(.systemWake)
        fixture.clock.advance(to: 0.5)
        fixture.coordinator.handle(.systemSleep)
        fixture.coordinator.handle(.systemWake)
        fixture.clock.advance(to: 1)
        XCTAssertEqual(fixture.executor.calls.count, 1)
        fixture.executor.completeLast(.success("old"))
        XCTAssertEqual(fixture.executor.calls.count, 2)
        fixture.executor.completeLast(.success("new"))
        XCTAssertFalse(fixture.status.contains("old"))
        XCTAssertTrue(fixture.status.last?.hasPrefix("new") == true)
        // Even a callback already enqueued when cancelled must be harmless.
        fixture.clock.fireCancelledTasks()
        XCTAssertEqual(fixture.executor.calls.count, 2)
    }

    func testTerminateCancelsAndIgnoresAllFutureEventsAndManualRequests() {
        let fixture = Fixture()
        fixture.coordinator.handle(.systemWake)
        fixture.clock.advance(to: 0.5)
        fixture.coordinator.stop()
        XCTAssertTrue(fixture.executor.calls[0].token.isCancelled)
        fixture.executor.completeLast(.success("stale"))
        fixture.coordinator.handle(.systemWake)
        fixture.coordinator.performManual(.white)
        fixture.coordinator.setEnabled(true)
        fixture.clock.advance(to: 100)
        fixture.clock.fireCancelledTasks()
        XCTAssertEqual(fixture.executor.calls.count, 1)
        XCTAssertFalse(fixture.status.contains("stale"))
    }

    func testDisabledLaunchAndUSBOnlyInspectWithoutLightingChanges() {
        let fixture = Fixture(enabled: false)
        fixture.coordinator.handle(.launch)
        fixture.executor.completeLast(.success("found"))
        fixture.coordinator.handle(.systemWake)
        fixture.coordinator.handle(.screenUnlocked)
        fixture.clock.advance(to: 100)
        XCTAssertEqual(fixture.executor.calls.map(\.operation), [.inspect])
        fixture.coordinator.handle(.deviceChanged)
        XCTAssertEqual(fixture.executor.calls.map(\.operation), [.inspect, .inspect])
    }

    func testAllRecoveryEventsScheduleAutoOff() {
        for event: RecoveryEvent in [
            .launch, .deviceChanged, .systemWake, .screensWake,
            .sessionActive, .screenUnlocked, .enabled,
        ] {
            let fixture = Fixture()
            fixture.coordinator.handle(event)
            fixture.clock.advance(to: 0.5)
            XCTAssertEqual(fixture.executor.calls.map(\.operation), [.off], "\(event)")
        }
    }

    func testSynchronousPermissionFailureStillSchedulesFiniteRetries() {
        let clock = FakeClock()
        var attempts = 0
        var statuses: [String] = []
        let coordinator = AutoOffCoordinator(enabled: true, schedule: clock.schedule) { _, _, completion in
            attempts += 1
            completion(.failure(Failure.permission))
        }
        coordinator.onStatus = { statuses.append($0) }
        coordinator.handle(.systemWake)
        clock.advance(to: 100)
        XCTAssertEqual(attempts, 5)
        XCTAssertFalse(coordinator.isBusy)
        XCTAssertEqual(statuses.last, Failure.permission.localizedDescription)
    }

    func testNotificationMonitorUsesWorkspaceAndDistributedCentersAndStops() {
        let workspace = NotificationCenter()
        let distributed = FakeDistributedCenter()
        let monitor = RecoveryEventMonitor(workspaceCenter: workspace, distributedCenter: distributed)
        var observed: [RecoveryEvent] = []
        monitor.onEvent = { observed.append($0) }
        monitor.start()
        for (name, event) in RecoveryEventMonitor.workspaceEvents {
            workspace.post(name: name, object: nil)
            XCTAssertEqual(observed.last, event)
        }
        for (name, event) in RecoveryEventMonitor.distributedEvents {
            distributed.post(name: name, object: nil)
            XCTAssertEqual(observed.last, event)
        }
        XCTAssertEqual(observed.count, 8)
        XCTAssertEqual(distributed.behaviors.count, 2)
        XCTAssertTrue(distributed.behaviors.allSatisfy { $0 == .deliverImmediately })
        monitor.start()  // Repeated start must not duplicate observers.
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(observed.count, 9)
        monitor.stop()
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        distributed.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        XCTAssertEqual(observed.count, 9)
    }
}

private enum Failure: LocalizedError {
    case unavailable, permission
    var errorDescription: String? {
        self == .permission ? "permission required" : "mouse unavailable or partial failure"
    }
}

private final class Fixture {
    let clock = FakeClock()
    let executor = FakeExecutor()
    let coordinator: AutoOffCoordinator
    var status: [String] = []
    var diagnostics: [RecoveryDiagnostic] = []
    var onboardWriteStates: [Bool] = []

    init(enabled: Bool = true) {
        coordinator = AutoOffCoordinator(
            enabled: enabled, schedule: clock.schedule, execute: executor.execute)
        coordinator.onStatus = { [weak self] in self?.status.append($0) }
        coordinator.onDiagnostic = { [weak self] in self?.diagnostics.append($0) }
        coordinator.onOnboardWriteStateChanged = { [weak self] in self?.onboardWriteStates.append($0) }
    }
}

private final class FakeExecutor {
    struct Call {
        let operation: LightingOperation
        let token: LightingOperationToken
        let completion: AutoOffCoordinator.Completion
    }
    var calls: [Call] = []

    func execute(
        _ operation: LightingOperation, token: LightingOperationToken,
        completion: @escaping AutoOffCoordinator.Completion
    ) {
        calls.append(Call(operation: operation, token: token, completion: completion))
    }

    func completeLast(_ result: Result<String, Error>) { calls.last?.completion(result) }
}

private final class FakeClock {
    private final class Task: RecoveryScheduledTask {
        let deadline: TimeInterval
        let action: () -> Void
        var cancelled = false
        var fired = false
        init(deadline: TimeInterval, action: @escaping () -> Void) {
            self.deadline = deadline
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    private var tasks: [Task] = []
    private var now: TimeInterval = 0
    var createdCount: Int { tasks.count }

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) -> RecoveryScheduledTask {
        let task = Task(deadline: now + delay, action: action)
        tasks.append(task)
        return task
    }

    func advance(to target: TimeInterval) {
        while let task = tasks.filter({ !$0.fired && $0.deadline <= target })
            .min(by: { $0.deadline < $1.deadline })
        {
            now = task.deadline
            task.fired = true
            if !task.cancelled { task.action() }
        }
        now = target
    }

    func fireCancelledTasks() {
        for task in tasks where task.cancelled { task.action() }
    }
}

private final class FakeDistributedCenter: DistributedRecoveryCenter {
    private let center = NotificationCenter()
    var behaviors: [DistributedNotificationCenter.SuspensionBehavior] = []

    func addObserver(
        _ observer: Any, selector: Selector, name: Notification.Name?, object: String?,
        suspensionBehavior: DistributedNotificationCenter.SuspensionBehavior
    ) {
        behaviors.append(suspensionBehavior)
        center.addObserver(observer, selector: selector, name: name, object: object)
    }

    func removeObserver(_ observer: Any) { center.removeObserver(observer) }
    func post(name: Notification.Name, object: Any?) { center.post(name: name, object: object) }
}
