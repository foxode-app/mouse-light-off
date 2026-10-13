import AppKit
import IOKit.hid
import MouseLighting

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
    private var wakeObserver: NSObjectProtocol?
    private var refreshWorkItem: DispatchWorkItem?
    private var refreshPending = false
    private var isBusy = false

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
        monitor.onChange = { [weak self] in self?.scheduleRefresh() }
        monitor.start()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRefresh() }
        scheduleRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshWorkItem?.cancel()
        monitor.stop()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "computer.mouse", accessibilityDescription: "Mouse Light Off")
            button.toolTip = "Mouse Light Off"
        }
        let menu = NSMenu()
        addMenuItem("設定を開く…", action: #selector(showWindow), to: menu)
        menu.addItem(.separator())
        commandMenuItems = [
            addMenuItem("すべて消灯", action: #selector(turnOff), to: menu),
            addMenuItem("すべて点灯（白）", action: #selector(turnWhite), to: menu),
            addMenuItem("接続を確認", action: #selector(reconnect), to: menu),
        ]
        menu.addItem(.separator())
        addMenuItem("終了", action: #selector(quit), to: menu, key: "q")
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
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 590),
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
            checkboxWithTitle: "起動時・再接続時に消灯", target: self, action: #selector(toggleAutoOff)
        )
        autoOffButton.state = UserDefaults.standard.bool(forKey: autoOffKey) ? .on : .off
        let automaticNote = label("有効にすると、アプリ起動中はスリープ復帰時も消灯します。")
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

        let caveat = label("USB を抜くと照明が戻る場合があります。自動消灯はアプリ起動中に動作します。")
        caveat.font = .systemFont(ofSize: 11)
        caveat.textColor = .secondaryLabelColor

        let supportedNote = label(
            "USB有線の8機種が対象です。G403 HEROは旧版で消灯確認済み、他の7機種は実験対応です。")
        supportedNote.font = .systemFont(ofSize: 11)
        supportedNote.textColor = .secondaryLabelColor
        let productButton = button("対応機種と使い方", action: #selector(openProductPage))

        let stack = NSStackView(views: [
            title, subtitle, statusScroll, commands, autoOffButton, automaticNote,
            permissionNote, permissionButtons, caveat, supportedNote, productButton,
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
        for text in [subtitle, automaticNote, permissionNote, caveat, supportedNote] {
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
        perform("消灯を要求しています…") { try $0.setLighting(.off) }
    }

    @objc private func turnWhite() {
        perform("白色点灯を要求しています…") { try $0.setLighting(.white) }
    }

    @objc private func reconnect() {
        perform("接続を確認しています…") { try $0.inspect() }
    }

    @objc private func toggleAutoOff() {
        UserDefaults.standard.set(autoOffButton.state == .on, forKey: autoOffKey)
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

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isBusy {
                self.refreshPending = true
            } else if UserDefaults.standard.bool(forKey: self.autoOffKey) {
                self.turnOff()
            } else {
                self.reconnect()
            }
        }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func perform(_ message: String, operation: @escaping (MouseLightingController) throws -> String) {
        guard !isBusy else { return }
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            statusView.string = "入力監視の許可が必要です。下の「アクセス許可を要求」から許可してください。"
            return
        }
        isBusy = true
        setCommandsEnabled(false)
        statusView.string = message
        worker.async { [weak self] in
            guard let self else { return }
            let result = Result { try operation(self.controller) }
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    self.statusView.string = message
                case .failure(let error):
                    self.statusView.string = error.localizedDescription
                }
                self.isBusy = false
                self.setCommandsEnabled(true)
                if self.refreshPending {
                    self.refreshPending = false
                    self.scheduleRefresh()
                }
            }
        }
    }

    private func setCommandsEnabled(_ enabled: Bool) {
        commandButtons.forEach { $0.isEnabled = enabled }
        commandMenuItems.forEach { $0.isEnabled = enabled }
    }
}
