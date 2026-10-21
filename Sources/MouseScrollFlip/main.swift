import AppKit

@main
enum MouseScrollFlipMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menu: MenuController?
    /// Held for the process lifetime. `beginActivity` ends if the token is released.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if quitIfAlreadyRunning() {
            return
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Keep the scroll event tap responsive"
        )
        menu = MenuController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScrollEventTap.shared.stop()
    }

    /// Two copies invert twice, which looks like the app does nothing.
    private func quitIfAlreadyRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }
        NSApp.terminate(nil)
        return true
    }
}
