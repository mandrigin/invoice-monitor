import Foundation

// MARK: - Organization Result

/// Result of organizing a file's destination
struct OrganizationResult {
    /// The destination folder (e.g., /path/to/invoices-03-2024)
    let destinationFolder: URL

    /// The final destination path including filename
    let destinationPath: URL

    /// The date used to determine the folder
    let folderDate: Date

    /// Source of the date used
    let dateSource: DateExtractionSource
}

// MARK: - Organizer Error

/// Errors that can occur during organization
enum OrganizerError: LocalizedError {
    /// File is already in an invoice folder
    case alreadyInInvoiceFolder(URL)

    /// Cannot determine destination
    case cannotResolveDestination(URL)

    /// Parent directory doesn't exist and can't be created
    case cannotCreateDirectory(URL, Error)

    var errorDescription: String? {
        switch self {
        case .alreadyInInvoiceFolder(let url):
            return "File already in invoice folder: \(url.path)"
        case .cannotResolveDestination(let url):
            return "Cannot resolve destination for: \(url.path)"
        case .cannotCreateDirectory(let url, let error):
            return "Cannot create directory \(url.path): \(error.localizedDescription)"
        }
    }
}

// MARK: - Organizer

/// Resolves destination paths and folder structure for invoice filing
///
/// Responsibilities (per spec sections 3.6):
/// - Folder naming: invoices-MM-YYYY
/// - Destination resolution: configurable root or source directory
/// - Idempotency check: skip files already in invoice folders
final class Organizer {

    // MARK: - Constants

    /// Regex pattern for invoice folder naming
    private static let invoiceFolderPattern = #"^invoices-\d{2}-\d{4}$"#

    // MARK: - Properties

    private let config: AppConfig
    private let fileManager: FileManager

    // MARK: - Initialization

    init(config: AppConfig? = nil, fileManager: FileManager = .default) {
        self.config = config ?? ConfigManager.shared.config
        self.fileManager = fileManager
    }

    /// Create an organizer from the current app configuration
    static func fromConfig() -> Organizer {
        Organizer(config: ConfigManager.shared.config)
    }

    // MARK: - Public API

    /// Organize a file by determining its destination folder and path
    /// - Parameters:
    ///   - sourceFile: The source file URL
    ///   - extractedDate: Optional date extracted from invoice content
    /// - Returns: Organization result with destination paths
    func organize(sourceFile: URL, extractedDate: Date? = nil) throws -> OrganizationResult {
        // 1. Idempotency check - skip if already in invoice folder
        if isInInvoiceFolder(sourceFile) {
            throw OrganizerError.alreadyInInvoiceFolder(sourceFile)
        }

        // 2. Determine the folder date
        let (folderDate, dateSource) = determineFolderDate(
            for: sourceFile,
            extractedDate: extractedDate
        )

        // 3. Resolve destination folder
        let destinationFolder = resolveDestinationFolder(
            sourceFile: sourceFile,
            folderDate: folderDate
        )

        // 4. Ensure destination folder exists
        try ensureDirectoryExists(at: destinationFolder)

        // 5. Build final destination path (collision handling done by Mover)
        let destinationPath = destinationFolder.appendingPathComponent(sourceFile.lastPathComponent)

        return OrganizationResult(
            destinationFolder: destinationFolder,
            destinationPath: destinationPath,
            folderDate: folderDate,
            dateSource: dateSource
        )
    }

    /// Check if a file is already in an invoice folder
    /// - Parameter url: File URL to check
    /// - Returns: true if the file's parent folder matches the invoice folder pattern
    func isInInvoiceFolder(_ url: URL) -> Bool {
        let parentName = url.deletingLastPathComponent().lastPathComponent
        return parentName.range(of: Self.invoiceFolderPattern, options: .regularExpression) != nil
    }

    /// Generate the folder name for a given date
    /// - Parameter date: The date to use
    /// - Returns: Folder name in format "invoices-MM-YYYY"
    func invoiceFolderName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-yyyy"
        return "invoices-\(formatter.string(from: date))"
    }

    // MARK: - Private Methods

    /// Determine the date to use for the folder
    private func determineFolderDate(
        for file: URL,
        extractedDate: Date?
    ) -> (Date, DateExtractionSource) {
        // 1. Try extracted invoice date if enabled and available
        if config.dateSource == .extractedInvoiceDate {
            if let date = extractedDate, isDateReasonable(date) {
                return (date, .invoiceContent)
            }
        }

        // 2. Fall back based on config
        switch config.dateSource {
        case .extractedInvoiceDate, .fileCreationDate:
            if let date = fileCreationDate(for: file) {
                return (date, .fileCreationDate)
            }
            // Fall through to modification date
            if let date = fileModificationDate(for: file) {
                return (date, .fileModificationDate)
            }

        case .fileModificationDate:
            if let date = fileModificationDate(for: file) {
                return (date, .fileModificationDate)
            }

        case .currentDate:
            break
        }

        // 3. Ultimate fallback: current date
        return (Date(), .currentDate)
    }

    /// Resolve the destination folder path
    private func resolveDestinationFolder(sourceFile: URL, folderDate: Date) -> URL {
        // Use configured destination root, or source file's directory
        let root = config.destinationRoot ?? sourceFile.deletingLastPathComponent()
        let folderName = invoiceFolderName(for: folderDate)
        return root.appendingPathComponent(folderName)
    }

    /// Ensure a directory exists, creating it if necessary
    private func ensureDirectoryExists(at url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                // Exists but is not a directory - this is an error
                throw OrganizerError.cannotCreateDirectory(
                    url,
                    NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)
                )
            }
            // Directory already exists
            return
        }

        // Create directory with intermediate directories
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw OrganizerError.cannotCreateDirectory(url, error)
        }
    }

    /// Check if a date is reasonable (not in future, not more than 2 years old)
    private func isDateReasonable(_ date: Date) -> Bool {
        let now = Date()
        let twoYearsAgo = Calendar.current.date(byAdding: .year, value: -2, to: now) ?? now

        return date <= now && date >= twoYearsAgo
    }

    /// Get file creation date
    private func fileCreationDate(for url: URL) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.creationDate] as? Date
    }

    /// Get file modification date
    private func fileModificationDate(for url: URL) -> Date? {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }
}

// MARK: - OrganizationResult Extensions

extension OrganizationResult {
    /// Convert to DateExtractionDetails for logging
    func asDateExtractionDetails(pattern: String? = nil) -> DateExtractionDetails {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return DateExtractionDetails(
            extractedDate: formatter.string(from: folderDate),
            source: dateSource,
            pattern: pattern
        )
    }
}
