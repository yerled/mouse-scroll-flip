import AppKit
import ApplicationServices
import ServiceManagement

enum SettingsStore {
    private static let enabledKey = "enabled"
    private static let reverseHorizontalKey = "reverseHorizontal"

    /// Missing value means on, so the first launch flips the wheel as soon
    /// as Accessibility permission is granted.
    static var enabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var reverseHorizontal: Bool {
        get { UserDefaults.standard.bool(forKey: reverseHorizontalKey) }
        set { UserDefaults.standard.set(newValue, forKey: reverseHorizontalKey) }
    }
}

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt the first time. Later calls are a cheap check
    /// plus our own menu item, because macOS will not keep re-showing the dialog.
    static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

enum LoginItemController {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    /// Registers or removes this app as a login item via `SMAppService`.
    /// macOS 13 may leave the service in `.requiresApproval` until the user
    /// allows it under System Settings → General → Login Items.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func openLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.Users-Groups.extension"
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}

enum L10n {
    static var isChinese: Bool {
        guard let code = Locale.preferredLanguages.first else { return false }
        return code.hasPrefix("zh")
    }

    static func text(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.yerled.mousescrollflip"
    }
}
