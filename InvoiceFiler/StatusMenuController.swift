import Cocoa

/// Represents the current status of the Invoice Filer for badge display
enum StatusBadge {
    case idle           // Green - everything normal
    case processing     // Yellow - currently processing a file
    case error          // Red - recent error occurred

    var symbolName: String {
        switch self {
        case .idle:
            return "doc.text.magnifyingglass"
        case .processing:
            return "doc.text.magnifyingglass"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var badgeColor: NSColor? {
        switch self {
        case .idle:
            return .systemGreen
        case .processing:
            return .systemYellow
        case .error:
            return .systemRed
        }
    }
}

/// Represents the result of processing a file
struct ProcessedFileInfo {
    let filename: String
    let outcome: String
    let timestamp: Date
}

/// Represents processing statistics
struct ProcessingStats {
    var filesFiled: Int = 0
    var filesSkipped: Int = 0
    var lastReset: Date = Date()

    mutating func reset() {
        filesFiled = 0
        filesSkipped = 0
        lastReset = Date()
    }
}

/// Controller for the menu bar status item and menu
final class StatusMenuController {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var currentBadge: StatusBadge = .idle
    private var animationTimer: Timer?
    private var animationFrame: Int = 0

    private var stats = ProcessingStats()
    private var lastProcessedFile: ProcessedFileInfo?

    // Menu items that need dynamic updates
    private weak var statusMenuItem: NSMenuItem?
    private weak var statsMenuItem: NSMenuItem?
    private weak var lastFileMenuItem: NSMenuItem?

    // MARK: - Initialization

    init() {
        setupStatusItem()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            updateButtonImage(for: .idle)
            button.imagePosition = .imageOnly
        }

        statusItem?.menu = createMenu()
    }

    private func createMenu() -> NSMenu {
        let menu = NSMenu()

        // App title
        let titleItem = NSMenuItem(title: "Invoice Filer", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Status indicator
        let statusItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        self.statusMenuItem = statusItem
        menu.addItem(statusItem)

        // Stats (last 24 hours)
        let statsItem = NSMenuItem(title: "Last 24h: 0 filed, 0 skipped", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        self.statsMenuItem = statsItem
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        // Last processed file
        let lastFileItem = NSMenuItem(title: "No files processed yet", action: nil, keyEquivalent: "")
        lastFileItem.isEnabled = false
        self.lastFileMenuItem = lastFileItem
        menu.addItem(lastFileItem)

        menu.addItem(NSMenuItem.separator())

        // Invoicing
        let invoicingItem = NSMenuItem(title: "Invoice Management...", action: #selector(openInvoicingAction(_:)), keyEquivalent: "i")
        invoicingItem.target = self
        menu.addItem(invoicingItem)

        // View Log
        let viewLogItem = NSMenuItem(title: "View Log...", action: #selector(viewLogAction(_:)), keyEquivalent: "l")
        viewLogItem.target = self
        menu.addItem(viewLogItem)

        // Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferencesAction(_:)), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Invoice Filer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Public Interface

    /// Update the status badge (green/yellow/red)
    func setBadge(_ badge: StatusBadge) {
        currentBadge = badge
        updateButtonImage(for: badge)
        updateStatusMenuItem(for: badge)
    }

    /// Start the processing animation
    func startProcessingAnimation() {
        guard animationTimer == nil else { return }

        setBadge(.processing)
        animationFrame = 0

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateProcessingAnimation()
        }
    }

    /// Stop the processing animation
    func stopProcessingAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrame = 0
        setBadge(.idle)
    }

    /// Record a successful file operation
    func recordFileFiled(filename: String) {
        stats.filesFiled += 1
        lastProcessedFile = ProcessedFileInfo(
            filename: filename,
            outcome: "Filed",
            timestamp: Date()
        )
        updateStatsMenuItem()
        updateLastFileMenuItem()
    }

    /// Record a skipped file
    func recordFileSkipped(filename: String, reason: String) {
        stats.filesSkipped += 1
        lastProcessedFile = ProcessedFileInfo(
            filename: filename,
            outcome: "Skipped: \(reason)",
            timestamp: Date()
        )
        updateStatsMenuItem()
        updateLastFileMenuItem()
    }

    /// Record an error
    func recordError(filename: String, error: String) {
        lastProcessedFile = ProcessedFileInfo(
            filename: filename,
            outcome: "Error: \(error)",
            timestamp: Date()
        )
        setBadge(.error)
        updateLastFileMenuItem()

        // Auto-clear error badge after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.currentBadge == .error {
                self?.setBadge(.idle)
            }
        }
    }

    /// Reset 24-hour stats
    func resetStats() {
        stats.reset()
        updateStatsMenuItem()
    }

    // MARK: - Menu Actions

    @objc private func openInvoicingAction(_ sender: Any?) {
        InvoicingWindowController.shared.showWindow()
    }

    @objc private func viewLogAction(_ sender: Any?) {
        openLogInConsole()
    }

    @objc private func openPreferencesAction(_ sender: Any?) {
        openPreferences()
    }

    // MARK: - Private Methods

    private func updateButtonImage(for badge: StatusBadge) {
        guard let button = statusItem?.button else { return }

        let image = createBadgedImage(for: badge)
        button.image = image
    }

    private func createBadgedImage(for badge: StatusBadge) -> NSImage? {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        guard let baseImage = NSImage(systemSymbolName: badge.symbolName, accessibilityDescription: "Invoice Filer")?
            .withSymbolConfiguration(symbolConfig) else {
            return nil
        }

        // Create a composite image with badge dot
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw base icon
            baseImage.draw(in: NSRect(x: 2, y: 2, width: 18, height: 18))

            // Draw badge dot in corner
            if let color = badge.badgeColor {
                color.setFill()
                let badgeRect = NSRect(x: rect.width - 8, y: rect.height - 8, width: 6, height: 6)
                NSBezierPath(ovalIn: badgeRect).fill()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    private func updateProcessingAnimation() {
        animationFrame = (animationFrame + 1) % 4

        guard let button = statusItem?.button else { return }

        // Cycle through animation frames
        let symbols = [
            "doc.text.magnifyingglass",
            "doc.text",
            "doc.text.magnifyingglass",
            "doc.fill"
        ]

        let symbolName = symbols[animationFrame]
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Processing")?.withSymbolConfiguration(symbolConfig) {
            let badgedImage = createAnimatedProcessingImage(baseImage: image)
            button.image = badgedImage
        }
    }

    private func createAnimatedProcessingImage(baseImage: NSImage) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            baseImage.draw(in: NSRect(x: 2, y: 2, width: 18, height: 18))

            // Animated yellow badge (pulses)
            NSColor.systemYellow.setFill()
            let badgeSize: CGFloat = self.animationFrame % 2 == 0 ? 6 : 7
            let offset = (7 - badgeSize) / 2
            let badgeRect = NSRect(x: rect.width - 8 + offset, y: rect.height - 8 + offset, width: badgeSize, height: badgeSize)
            NSBezierPath(ovalIn: badgeRect).fill()

            return true
        }

        image.isTemplate = false
        return image
    }

    private func updateStatusMenuItem(for badge: StatusBadge) {
        let statusText: String
        switch badge {
        case .idle:
            statusText = "Status: Idle"
        case .processing:
            statusText = "Status: Processing..."
        case .error:
            statusText = "Status: Error"
        }
        statusMenuItem?.title = statusText
    }

    private func updateStatsMenuItem() {
        let text = "Last 24h: \(stats.filesFiled) filed, \(stats.filesSkipped) skipped"
        statsMenuItem?.title = text
    }

    private func updateLastFileMenuItem() {
        guard let info = lastProcessedFile else {
            lastFileMenuItem?.title = "No files processed yet"
            return
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: info.timestamp)

        // Truncate filename if too long
        let displayName = info.filename.count > 25
            ? String(info.filename.prefix(22)) + "..."
            : info.filename

        lastFileMenuItem?.title = "\(displayName) - \(info.outcome) (\(timeStr))"
    }

    private func openLogInConsole() {
        LogViewerWindowController.shared.showWindow()
    }

    private func openPreferences() {
        // Post notification for AppDelegate or PreferencesController to handle
        NotificationCenter.default.post(name: .openPreferences, object: nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openPreferences = Notification.Name("InvoiceFilerOpenPreferences")
}
