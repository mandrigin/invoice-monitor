import Foundation

// MARK: - Company Configuration

/// Configuration for a company to match against invoice content
struct CompanyConfig: Codable, Equatable, Hashable {
    /// Primary company name
    let name: String

    /// Alternative names/spellings for the company
    var aliases: [String]

    /// Tax identification numbers (EIN, VAT, etc.)
    var taxIds: [String]

    /// Company email domains (e.g., "acme.com")
    var domains: [String]

    init(name: String, aliases: [String] = [], taxIds: [String] = [], domains: [String] = []) {
        self.name = name
        self.aliases = aliases
        self.taxIds = taxIds
        self.domains = domains
    }
}

// MARK: - Date Source

/// Source for determining the invoice folder date
enum DateSource: String, Codable, CaseIterable {
    /// Extract date from invoice content (primary), fallback to file creation date
    case extractedInvoiceDate

    /// Use file creation date
    case fileCreationDate

    /// Use file modification date
    case fileModificationDate

    /// Use current date when processing
    case currentDate
}

// MARK: - Monitored Path Configuration

/// Configuration for a single monitored directory
struct MonitoredPath: Codable, Equatable, Hashable {
    /// Path to the directory
    let path: URL

    /// Whether to watch subdirectories
    var recursive: Bool

    init(path: URL, recursive: Bool = false) {
        self.path = path
        self.recursive = recursive
    }
}

// MARK: - App Configuration

/// Main configuration for InvoiceFiler
struct AppConfig: Codable, Equatable {
    /// Configuration version for migration support
    var version: Int

    /// Directories to watch for new files
    var monitoredPaths: [MonitoredPath]

    /// Root directory for invoice folders; nil = use source file's directory
    var destinationRoot: URL?

    /// Companies to match against invoice content
    var companies: [CompanyConfig]

    /// File extensions to process
    var supportedExtensions: Set<String>

    /// Path to JSONL log file
    var logLocation: URL

    /// Whether to launch at login
    var launchAtLogin: Bool

    /// Glob patterns for files to skip
    var exclusionPatterns: [String]

    /// Seconds to wait after file event before processing
    var debounceInterval: TimeInterval

    /// Source for determining folder date
    var dateSource: DateSource

    /// Vision OCR language codes
    var ocrLanguages: [String]

    /// Minimum confidence to classify as invoice (0.0-1.0)
    var invoiceConfidenceThreshold: Float

    /// Minimum confidence for company match (0.0-1.0)
    var companyMatchThreshold: Float

    /// Maximum PDF pages to OCR
    var maxOCRPages: Int

    /// Use filename as supplementary matching signal
    var enableFilenameHint: Bool

    /// Include extracted text in log entries (privacy concern)
    var logExtractedText: Bool

    // MARK: - Default Values

    static let currentVersion = 2

    static var `default`: AppConfig {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("InvoiceFiler")

        return AppConfig(
            version: currentVersion,
            monitoredPaths: [],
            destinationRoot: nil,
            companies: [],
            supportedExtensions: ["pdf", "png", "jpg", "jpeg", "heic", "webp", "tiff"],
            logLocation: logsDir.appendingPathComponent("moves.jsonl"),
            launchAtLogin: true,
            exclusionPatterns: [".*", "*.tmp", "*.download", "*.crdownload", "*.part"],
            debounceInterval: 3.0,
            dateSource: .extractedInvoiceDate,
            ocrLanguages: ["en-US"],
            invoiceConfidenceThreshold: 0.7,
            companyMatchThreshold: 0.8,
            maxOCRPages: 3,
            enableFilenameHint: true,
            logExtractedText: false
        )
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case version
        case monitoredPaths
        case destinationRoot
        case companies
        case supportedExtensions
        case logLocation
        case launchAtLogin
        case exclusionPatterns
        case debounceInterval
        case dateSource
        case ocrLanguages
        case invoiceConfidenceThreshold
        case companyMatchThreshold
        case maxOCRPages
        case enableFilenameHint
        case logExtractedText
    }
}

// MARK: - Validation

extension AppConfig {
    /// Validation error types
    enum ValidationError: LocalizedError {
        case noMonitoredPaths
        case noCompanies
        case invalidConfidenceThreshold(String, Float)
        case invalidDebounceInterval(TimeInterval)
        case invalidMaxOCRPages(Int)
        case emptyCompanyName
        case duplicateCompanyName(String)
        case monitoredPathNotDirectory(URL)
        case monitoredPathNotAccessible(URL)

        var errorDescription: String? {
            switch self {
            case .noMonitoredPaths:
                return "At least one monitored path must be configured"
            case .noCompanies:
                return "At least one company must be configured"
            case .invalidConfidenceThreshold(let name, let value):
                return "\(name) must be between 0.0 and 1.0 (got \(value))"
            case .invalidDebounceInterval(let value):
                return "Debounce interval must be positive (got \(value))"
            case .invalidMaxOCRPages(let value):
                return "Max OCR pages must be at least 1 (got \(value))"
            case .emptyCompanyName:
                return "Company name cannot be empty"
            case .duplicateCompanyName(let name):
                return "Duplicate company name: \(name)"
            case .monitoredPathNotDirectory(let url):
                return "Monitored path is not a directory: \(url.path)"
            case .monitoredPathNotAccessible(let url):
                return "Monitored path is not accessible: \(url.path)"
            }
        }
    }

    /// Validate configuration and return all errors
    func validate() -> [ValidationError] {
        var errors: [ValidationError] = []

        // Check monitored paths
        if monitoredPaths.isEmpty {
            errors.append(.noMonitoredPaths)
        } else {
            let fileManager = FileManager.default
            for monitored in monitoredPaths {
                var isDirectory: ObjCBool = false
                if !fileManager.fileExists(atPath: monitored.path.path, isDirectory: &isDirectory) {
                    errors.append(.monitoredPathNotAccessible(monitored.path))
                } else if !isDirectory.boolValue {
                    errors.append(.monitoredPathNotDirectory(monitored.path))
                }
            }
        }

        // Check companies
        if companies.isEmpty {
            errors.append(.noCompanies)
        } else {
            var seenNames = Set<String>()
            for company in companies {
                let normalizedName = company.name.lowercased().trimmingCharacters(in: .whitespaces)
                if normalizedName.isEmpty {
                    errors.append(.emptyCompanyName)
                } else if seenNames.contains(normalizedName) {
                    errors.append(.duplicateCompanyName(company.name))
                } else {
                    seenNames.insert(normalizedName)
                }
            }
        }

        // Check confidence thresholds
        if invoiceConfidenceThreshold < 0.0 || invoiceConfidenceThreshold > 1.0 {
            errors.append(.invalidConfidenceThreshold("invoiceConfidenceThreshold", invoiceConfidenceThreshold))
        }
        if companyMatchThreshold < 0.0 || companyMatchThreshold > 1.0 {
            errors.append(.invalidConfidenceThreshold("companyMatchThreshold", companyMatchThreshold))
        }

        // Check other values
        if debounceInterval < 0 {
            errors.append(.invalidDebounceInterval(debounceInterval))
        }
        if maxOCRPages < 1 {
            errors.append(.invalidMaxOCRPages(maxOCRPages))
        }

        return errors
    }

    /// Returns true if configuration is valid for processing
    var isValid: Bool {
        validate().isEmpty
    }

    /// Returns true if configuration has minimum requirements to start processing
    var isReadyForProcessing: Bool {
        !monitoredPaths.isEmpty && !companies.isEmpty
    }
}
