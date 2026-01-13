import Cocoa
import Combine

/// Main application delegate that wires together all components
///
/// Implementation per spec section 5.1:
/// - Initializes all services on launch
/// - Coordinates FileWatcher → Debouncer → InvoiceProcessor pipeline
/// - Manages status menu updates
/// - Handles launch at login and permissions
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Core Components

    private var statusMenuController: StatusMenuController?
    private var fileWatcher: FileWatcher?
    private var debouncer: Debouncer?
    private var processingQueue: ProcessingQueue?
    private var invoiceProcessor: InvoiceProcessor?
    private var logger: Logger?

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup in order
        setupLogger()
        setupStatusMenu()
        setupNotifications()
        checkPermissions()
        setupLaunchAtLogin()
        setupProcessingPipeline()
        startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopMonitoring()
    }

    // MARK: - Setup Methods

    private func setupLogger() {
        let config = ConfigManager.shared.config
        logger = Logger(logPath: config.logLocation)
    }

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

        // Listen for config changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigChanged),
            name: .configDidChange,
            object: nil
        )
    }

    private func checkPermissions() {
        // Check and prompt for Full Disk Access on first launch
        PermissionManager.shared.promptForFullDiskAccessIfNeeded()

        // Validate monitored paths
        let config = ConfigManager.shared.config
        let monitoredURLs = config.monitoredPaths.map { $0.path }
        let inaccessiblePaths = PermissionManager.shared.validateMonitoredPaths(monitoredURLs)

        if !inaccessiblePaths.isEmpty {
            // Some paths are not accessible
            DispatchQueue.main.async { [weak self] in
                self?.showInaccessiblePathsWarning(inaccessiblePaths)
            }
        }
    }

    private func setupLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            let config = ConfigManager.shared.config
            LaunchAtLoginManager.shared.sync(with: config.launchAtLogin)
        }
    }

    private func setupProcessingPipeline() {
        let config = ConfigManager.shared.config

        // Create processing queue with OCR concurrency limit
        processingQueue = ProcessingQueue(maxConcurrent: 2)

        // Create invoice processor
        guard let logger = logger, let queue = processingQueue else { return }

        invoiceProcessor = InvoiceProcessor.fromConfig(logger: logger, processingQueue: queue)
        invoiceProcessor?.delegate = self

        // Create debouncer
        debouncer = Debouncer(debounceInterval: config.debounceInterval)
        debouncer?.configure(logger: logger)

        // Create file watcher
        fileWatcher = FileWatcher()
        fileWatcher?.configure(
            paths: config.monitoredPaths,
            supportedExtensions: config.supportedExtensions,
            exclusionPatterns: config.exclusionPatterns
        )

        // Wire up the pipeline: FileWatcher → Debouncer → InvoiceProcessor
        if let watcher = fileWatcher, let debouncerInstance = debouncer {
            // FileWatcher events → Debouncer
            watcher.events
                .sink { [weak debouncerInstance] event in
                    debouncerInstance?.process(event: event)
                }
                .store(in: &cancellables)

            // Debouncer ready files → InvoiceProcessor
            invoiceProcessor?.subscribe(to: debouncerInstance)
        }
    }

    private func startMonitoring() {
        let config = ConfigManager.shared.config

        // Only start if configuration is ready
        guard config.isReadyForProcessing else {
            showConfigurationRequiredAlert()
            return
        }

        do {
            try fileWatcher?.start()
            processingQueue?.start()
            invoiceProcessor?.start()
            statusMenuController?.setBadge(.idle)
        } catch {
            statusMenuController?.setBadge(.error)
            showStartupError(error)
        }
    }

    private func stopMonitoring() {
        fileWatcher?.stop()
        debouncer?.cancelAll()
        processingQueue?.stop()
        invoiceProcessor?.stop()
    }

    // MARK: - Public Access

    /// Provides access to the status menu controller for other components
    var statusMenu: StatusMenuController? {
        return statusMenuController
    }

    // MARK: - Notification Handlers

    @objc private func handleOpenPreferences() {
        // For now, show an alert indicating preferences are not yet implemented
        // TODO: Implement preferences window
        let alert = NSAlert()
        alert.messageText = "Preferences"
        alert.informativeText = "Preferences window is not yet implemented.\n\nYou can edit the configuration file directly at:\n\(ConfigManager.shared.configFileURL.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Show Config File")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.selectFile(
                ConfigManager.shared.configFileURL.path,
                inFileViewerRootedAtPath: ""
            )
        }
    }

    @objc private func handleConfigChanged() {
        // Restart monitoring with new configuration
        stopMonitoring()
        setupProcessingPipeline()
        startMonitoring()
    }

    // MARK: - Alert Helpers

    private func showInaccessiblePathsWarning(_ paths: [URL]) {
        let alert = NSAlert()
        alert.messageText = "Some Paths Not Accessible"

        let pathList = paths.map { "• \($0.path)" }.joined(separator: "\n")
        alert.informativeText = """
        The following monitored paths are not accessible:

        \(pathList)

        This may be because:
        - Full Disk Access has not been granted
        - The paths do not exist
        - You don't have permission to access them

        Files in these directories will not be monitored.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            PermissionManager.shared.openFullDiskAccessSettings()
        }
    }

    private func showConfigurationRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = "Configuration Required"
        alert.informativeText = """
        Invoice Filer needs to be configured before it can start monitoring for invoices.

        Please configure:
        1. At least one directory to monitor
        2. At least one company to match

        Click "Show Config File" to open the configuration file.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Show Config File")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            // Create default config file if it doesn't exist
            ConfigManager.shared.createDefaultConfigIfNeeded()

            NSWorkspace.shared.selectFile(
                ConfigManager.shared.configFileURL.path,
                inFileViewerRootedAtPath: ""
            )
        }
    }

    private func showStartupError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Startup Error"
        alert.informativeText = "Invoice Filer could not start monitoring:\n\n\(error.localizedDescription)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - InvoiceProcessorDelegate

extension AppDelegate: InvoiceProcessorDelegate {

    func processorDidStartProcessing(_ processor: InvoiceProcessor, file: URL) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMenuController?.startProcessingAnimation()
        }
    }

    func processorDidFinishProcessing(_ processor: InvoiceProcessor, result: ProcessingResultData) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMenuController?.stopProcessingAnimation()

            let filename = result.file.lastPathComponent

            switch result.outcome {
            case .success:
                self?.statusMenuController?.recordFileFiled(filename: filename)
            case .skippedNotInvoice:
                self?.statusMenuController?.recordFileSkipped(filename: filename, reason: "Not an invoice")
            case .skippedNoCompanyMatch:
                self?.statusMenuController?.recordFileSkipped(filename: filename, reason: "No company match")
            case .skippedAlreadyFiled:
                self?.statusMenuController?.recordFileSkipped(filename: filename, reason: "Already filed")
            case .skippedExtractionFailed:
                self?.statusMenuController?.recordFileSkipped(filename: filename, reason: "Extraction failed")
            case .skippedProtected:
                self?.statusMenuController?.recordFileSkipped(filename: filename, reason: "Password protected")
            case .skippedNoContent:
                self?.statusMenuController?.recordFileSkipped(filename: filename, reason: "No content")
            case .skippedDeleted:
                self?.statusMenuController?.recordFileSkipped(filename: filename, reason: "File deleted")
            case .failedMoveError(let error):
                self?.statusMenuController?.recordError(filename: filename, error: error.localizedDescription)
            case .failedLocked:
                self?.statusMenuController?.recordError(filename: filename, error: "File locked")
            }
        }
    }

    func processorDidEncounterError(_ processor: InvoiceProcessor, file: URL, error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMenuController?.stopProcessingAnimation()
            self?.statusMenuController?.recordError(filename: file.lastPathComponent, error: error.localizedDescription)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when configuration changes and monitoring should restart
    static let configDidChange = Notification.Name("InvoiceFilerConfigDidChange")
}
