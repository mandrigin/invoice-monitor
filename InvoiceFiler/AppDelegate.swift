import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusMenuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusMenu()
        setupNotifications()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
    }

    // MARK: - Setup

    private func setupStatusMenu() {
        statusMenuController = StatusMenuController()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPreferences),
            name: .openPreferences,
            object: nil
        )
    }

    // MARK: - Public Access

    /// Provides access to the status menu controller for other components
    var statusMenu: StatusMenuController? {
        return statusMenuController
    }

    // MARK: - Notification Handlers

    @objc private func handleOpenPreferences() {
        // TODO: Show preferences window
        // For now, show an alert indicating preferences are not yet implemented
        let alert = NSAlert()
        alert.messageText = "Preferences"
        alert.informativeText = "Preferences window is not yet implemented."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
