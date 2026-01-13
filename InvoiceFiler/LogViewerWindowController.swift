import Cocoa
import SwiftUI

/// Controller for the log viewer window
final class LogViewerWindowController: NSObject {

    // MARK: - Singleton

    static let shared = LogViewerWindowController()

    // MARK: - Properties

    private var window: NSWindow?

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Show the log viewer window, creating it if necessary
    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let logViewerView = LogViewerView()
        let hostingController = NSHostingController(rootView: logViewerView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Invoice Filer - Log Viewer"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 1000, height: 600))
        newWindow.minSize = NSSize(width: 800, height: 400)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Close the log viewer window if open
    func closeWindow() {
        window?.close()
    }
}

// MARK: - NSWindowDelegate

extension LogViewerWindowController: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        // Window is being closed, but we keep the reference for reuse
    }
}
