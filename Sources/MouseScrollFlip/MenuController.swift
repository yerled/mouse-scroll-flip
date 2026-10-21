import AppKit

/// Menu-bar menu: on/off, horizontal flip, login item, Accessibility, quit.
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let enabledItem = NSMenuItem()
    private let horizontalItem = NSMenuItem()
    private let loginItem = NSMenuItem()
    private let statusLine = NSMenuItem()
    private let permissionItem = NSMenuItem()
    private var didPromptThisLaunch = false
    private var displayedActive: Bool?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureMenu()
        ScrollEventTap.shared.setReverseHorizontal(SettingsStore.reverseHorizontal)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tapUnavailable),
            name: .scrollTapUnavailable,
            object: nil
        )
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(machineWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(machineWake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        syncTapToPermission()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.syncTapToPermission()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let title = NSMenuItem(title: "Mouse Scroll Flip", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let version = NSMenuItem(
            title: L10n.text("Version \(AppInfo.version)", "版本 \(AppInfo.version)"),
            action: nil,
            keyEquivalent: ""
        )
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())

        statusLine.isEnabled = false
        menu.addItem(statusLine)

        permissionItem.target = self
        permissionItem.action = #selector(openAccessibility)
        menu.addItem(permissionItem)
        menu.addItem(.separator())

        enabledItem.target = self
        enabledItem.action = #selector(toggleEnabled)
        menu.addItem(enabledItem)

        horizontalItem.target = self
        horizontalItem.action = #selector(toggleHorizontal)
        menu.addItem(horizontalItem)

        loginItem.target = self
        loginItem.action = #selector(toggleLogin)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: L10n.text("Quit", "退出"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        statusItem.menu = menu
        refreshItems()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshItems()
    }

    private func refreshItems() {
        let trusted = AccessibilityPermission.isTrusted
        let enabled = SettingsStore.enabled
        let running = ScrollEventTap.shared.isTapEnabled
        enabledItem.title = L10n.text("Reverse mouse wheel", "反转鼠标滚轮")
        enabledItem.state = enabled ? .on : .off

        horizontalItem.title = L10n.text("Also reverse horizontal", "同时反转水平滚动")
        horizontalItem.state = SettingsStore.reverseHorizontal ? .on : .off
        horizontalItem.isEnabled = enabled

        switch LoginItemController.status {
        case .enabled:
            loginItem.title = L10n.text("Launch at Login", "登录时启动")
            loginItem.state = .on
        case .requiresApproval:
            loginItem.title = L10n.text("Launch at Login (approval needed)", "登录时启动（需要允许）")
            loginItem.state = .mixed
        default:
            loginItem.title = L10n.text("Launch at Login", "登录时启动")
            loginItem.state = .off
        }

        permissionItem.title = L10n.text("Open Accessibility Settings…", "打开辅助功能设置…")
        let showPermission: Bool
        if !enabled {
            statusLine.title = L10n.text("Paused", "已暂停")
            showPermission = !trusted
        } else if running {
            statusLine.title = L10n.text("Mouse wheel reversed", "鼠标滚轮已反转")
            showPermission = false
        } else if !trusted {
            statusLine.title = L10n.text("Needs Accessibility permission", "需要辅助功能权限")
            showPermission = true
        } else {
            statusLine.title = L10n.text("Starting…", "正在启动…")
            showPermission = false
        }
        setPermissionItemVisible(showPermission)
        applyIcon(active: enabled && (running || trusted))
    }

    /// `NSMenuItem.isHidden` is macOS 14+. Insert and remove so macOS 13 works.
    private func setPermissionItemVisible(_ visible: Bool) {
        guard let menu = statusItem.menu else { return }
        let contains = menu.items.contains(permissionItem)
        if visible && !contains {
            let index = menu.index(of: statusLine)
            menu.insertItem(permissionItem, at: index + 1)
        } else if !visible && contains {
            menu.removeItem(permissionItem)
        }
    }

    private func applyIcon(active: Bool) {
        if displayedActive == active, statusItem.button?.image != nil {
            return
        }
        displayedActive = active
        let symbol = active ? "computermouse.fill" : "computermouse"
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Mouse Scroll Flip")?
            .withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: "Mouse Scroll Flip")
        if let image {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            statusItem.button?.title = "MSF"
        }
        statusItem.button?.appearsDisabled = !active
        statusItem.button?.toolTip = "Mouse Scroll Flip"
    }

    /// Polls Accessibility and the tap. Granting permission in System Settings
    /// is observed on the next tick: the tap is created then, with no relaunch.
    /// `AXIsProcessTrusted` can lag behind TCC, so a failed tap is retried
    /// until `tapCreate` succeeds.
    private func syncTapToPermission() {
        let trusted = AccessibilityPermission.isTrusted
        if SettingsStore.enabled && !trusted && !didPromptThisLaunch {
            didPromptThisLaunch = true
            AccessibilityPermission.prompt()
        }
        if SettingsStore.enabled {
            ScrollEventTap.shared.setReverseHorizontal(SettingsStore.reverseHorizontal)
            if !ScrollEventTap.shared.isTapEnabled {
                ScrollEventTap.shared.revive()
            }
        } else {
            ScrollEventTap.shared.stop()
        }
        refreshItems()
    }

    @objc private func toggleEnabled() {
        SettingsStore.enabled.toggle()
        ScrollEventTap.shared.setReverseHorizontal(SettingsStore.reverseHorizontal)
        syncTapToPermission()
    }

    @objc private func toggleHorizontal() {
        SettingsStore.reverseHorizontal.toggle()
        ScrollEventTap.shared.setReverseHorizontal(SettingsStore.reverseHorizontal)
        refreshItems()
    }

    @objc private func toggleLogin() {
        switch LoginItemController.status {
        case .requiresApproval:
            LoginItemController.openLoginItemsSettings()
        case .enabled:
            if let message = LoginItemController.setEnabled(false) {
                present(message)
            }
        default:
            if let message = LoginItemController.setEnabled(true) {
                present(message)
            } else if LoginItemController.status == .requiresApproval {
                present(L10n.text(
                    "macOS needs you to allow Mouse Scroll Flip under System Settings → General → Login Items & Extensions.",
                    "请在“系统设置 → 通用 → 登录项与扩展”中允许 Mouse Scroll Flip 登录时打开。"
                ))
                LoginItemController.openLoginItemsSettings()
            }
        }
        refreshItems()
    }

    @objc private func openAccessibility() {
        AccessibilityPermission.prompt()
        AccessibilityPermission.openSettings()
    }

    @objc private func tapUnavailable() {
        refreshItems()
    }

    @objc private func machineWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.syncTapToPermission()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.syncTapToPermission()
        }
    }

    private func present(_ message: String) {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        let alert = NSAlert()
        alert.messageText = "Mouse Scroll Flip"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("OK", "好"))
        alert.runModal()
    }
}
