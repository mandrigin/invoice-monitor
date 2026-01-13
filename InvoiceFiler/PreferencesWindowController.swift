import Cocoa
import SwiftUI

/// Controller for the preferences window
final class PreferencesWindowController: NSObject {

    // MARK: - Singleton

    static let shared = PreferencesWindowController()

    // MARK: - Properties

    private var window: NSWindow?

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Show the preferences window, creating it if necessary
    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let preferencesView = PreferencesView()
        let hostingController = NSHostingController(rootView: preferencesView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Invoice Filer Preferences"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.setContentSize(NSSize(width: 600, height: 450))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the preferences window if open
    func closeWindow() {
        window?.close()
    }
}

// MARK: - NSWindowDelegate

extension PreferencesWindowController: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        // Notify that config may have changed
        NotificationCenter.default.post(name: .configDidChange, object: nil)
    }
}
