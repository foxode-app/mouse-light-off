import AppKit
import IOKit.hid
import MouseLighting
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = MouseLightingController()
    private let worker = DispatchQueue(label: "com.foxode.mouselightoff.hid")
    private let monitor = ConnectionMonitor()
    private let autoOffKey = "turnOffAtLaunchAndReconnect"
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var statusView: NSTextView!
    private var autoOffButton: NSButton!
    private var commandButtons: [NSButton] = []
    private var commandMenuItems: [NSMenuItem] = []
    private let recoveryMonitor = RecoveryEventMonitor()
    private let logger = Logger(subsystem: "com.foxode.mouselightoff.app", category: "AutoOff")
    private lazy var recovery = AutoOffCoordinator(
        enabled: UserDefaults.standard.bool(forKey: autoOffKey)
    ) { [weak self] operation, token, completion in
        guard let self else { return }
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            completion(.failure(MouseLightingError.permissionRequired))
            return
        }
        self.worker.async {
            let result = Result {
                guard !token.isCancelled else { throw CancellationError() }
                switch operation {
                case .off:
                    return try self.controller.setLighting(.off, shouldContinue: { !token.isCancelled })
                case .white:
                    return try self.controller.setLighting(.white, shouldContinue: { !token.isCancelled })
                case .inspect:
                    return try self.controller.inspect(shouldContinue: { !token.isCancelled })
                }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.object(forKey: autoOffKey) == nil,
            let previous = UserDefaults.standard.persistentDomain(forName: "local.g403lightcontrol.app")?[
                autoOffKey] as? Bool
        {
            UserDefaults.standard.set(previous, forKey: autoOffKey)
        }
        setupMenu()
        setupWindow()
        showWindow()
        recovery.onStatus = { [weak self] text in self?.statusView.string = text }
        recovery.onDiagnostic = { [weak self] entry in
            self?.logger.info(
                "reason=\(entry.reason, privacy: .public) attempt=\(entry.attempt) result=\(entry.result, privacy: .public)"
            )
        }
        recoveryMonitor.onEvent = { [weak self] event in self?.recovery.handle(event) }
        recoveryMonitor.start()
        monitor.onChange = { [weak self] in self?.recovery.handle(.deviceChanged) }
        monitor.start()
        recovery.handle(.launch)
    }

    func applicationWillTerminate(_ notification: Notification) {
        recovery.stop()
        recoveryMonitor.stop()
        monitor.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMenu() {
        statusItem = MenuBarIcon.makeStatusItem()
        let menu = NSMenu()
        let title = NSMenuItem(title: "Mouse Light Off", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        addMenuItem("設定を開く…", action: #selector(showWindow), to: menu)
        menu.addItem(.separator())
        commandMenuItems = [
            addMenuItem("すべて消灯", action: #selector(turnOff), to: menu),
            addMenuItem("すべて点灯（白）", action: #selector(turnWhite), to: menu),
            addMenuItem("接続を確認", action: #selector(reconnect), to: menu),
        ]
        menu.addItem(.separator())
        addMenuItem("Mouse Light Offを終了", action: #selector(quit), to: menu, key: "q")
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    @discardableResult
    private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu, key: String = "")
        -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func setupWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 620),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        window.title = "Mouse Light Off"
        window.isReleasedWhenClosed = false
        window.center()
        guard let content = window.contentView else { return }

        let title = NSTextField(labelWithString: "Mouse Light Off")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = label("対応するロジクール製マウスのライトを、まとめて消灯。")
        subtitle.textColor = .secondaryLabelColor

        statusView = NSTextView()
        statusView.string = "接続を確認しています…"
        statusView.font = .systemFont(ofSize: 13)
        statusView.isEditable = false
        statusView.isSelectable = true
        statusView.drawsBackground = false
        statusView.isHorizontallyResizable = false
        statusView.isVerticallyResizable = true
        statusView.autoresizingMask = [.width]
        statusView.textContainer?.widthTracksTextView = true
        statusView.textContainerInset = NSSize(width: 6, height: 8)
        let statusScroll = NSScrollView()
        statusScroll.documentView = statusView
        statusScroll.hasVerticalScroller = true
        statusScroll.borderType = .bezelBorder
        statusScroll.heightAnchor.constraint(equalToConstant: 116).isActive = true

        commandButtons = [
            button("すべて消灯", action: #selector(turnOff)),
            button("すべて点灯（白）", action: #selector(turnWhite)),
            button("接続を確認", action: #selector(reconnect)),
        ]
        let commands = NSStackView(views: commandButtons)
        commands.orientation = .horizontal
        commands.spacing = 10

        autoOffButton = NSButton(
            checkboxWithTitle: "起動時・再接続・復帰時に自動消灯", target: self, action: #selector(toggleAutoOff)
        )
        autoOffButton.state = UserDefaults.standard.bool(forKey: autoOffKey) ? .on : .off
        let automaticNote = label("復帰・ロック解除後、間隔をあけて最大5回まで再適用します。")
        automaticNote.font = .systemFont(ofSize: 11)
        automaticNote.textColor = .secondaryLabelColor

        let permissionNote = label(
            "初回は入力監視を許可し、アプリを開き直してください。マウス操作やキー入力の記録は行いません。"
        )
        permissionNote.font = .systemFont(ofSize: 12)
        permissionNote.textColor = .secondaryLabelColor
        let permissionButtons = NSStackView(views: [
            button("アクセス許可を要求", action: #selector(requestPermission)),
            button("入力監視の設定を開く", action: #selector(openPermissionSettings)),
        ])
        permissionButtons.orientation = .horizontal
        permissionButtons.spacing = 10

        let caveat = label("手動で点灯すると再適用を中止します。次の復帰・再接続時は再び自動消灯します。")
        caveat.font = .systemFont(ofSize: 11)
        caveat.textColor = .secondaryLabelColor

        let supportedNote = label(
            "USB有線の8機種が対象です。G403 HEROは旧版で消灯確認済み、他の7機種は実験対応です。")
        supportedNote.font = .systemFont(ofSize: 11)
        supportedNote.textColor = .secondaryLabelColor
        let productButton = button("対応機種と使い方", action: #selector(openProductPage))
        let residentNote = label("設定画面を閉じてもメニューバーに常駐します。終了するには「アプリを終了」を押してください。")
        residentNote.font = .systemFont(ofSize: 11)
        residentNote.textColor = .secondaryLabelColor
        let footerButtons = NSStackView(views: [
            productButton, button("アプリを終了", action: #selector(quit)),
        ])
        footerButtons.orientation = .horizontal
        footerButtons.spacing = 10

        let stack = NSStackView(views: [
            title, subtitle, statusScroll, commands, autoOffButton, automaticNote,
            permissionNote, permissionButtons, caveat, supportedNote, residentNote, footerButtons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
        ])
        statusScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for text in [subtitle, automaticNote, permissionNote, caveat, supportedNote, residentNote] {
            text.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.isSelectable = true
        return label
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func turnOff() {
        recovery.performManual(.off)
    }

    @objc private func turnWhite() {
        recovery.performManual(.white)
    }

    @objc private func reconnect() {
        recovery.performManual(.inspect)
    }

    @objc private func toggleAutoOff() {
        let enabled = autoOffButton.state == .on
        UserDefaults.standard.set(enabled, forKey: autoOffKey)
        recovery.setEnabled(enabled)
    }

    @objc private func requestPermission() {
        let allowed = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        statusView.string =
            allowed
            ? "入力監視が許可されています。「接続を確認」を押してください。"
            : "入力監視の設定で Mouse Light Off を許可し、このアプリを再起動してください。"
    }

    @objc private func openPermissionSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openProductPage() {
        if let url = URL(string: "https://foxode.com/products/mouse-light-off/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

}
