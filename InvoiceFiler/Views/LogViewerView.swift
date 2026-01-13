import SwiftUI
import Combine

// MARK: - LogEntry Extensions

extension LogEntry: Identifiable {
    var id: String { eventId }
}

extension LogEntry: Hashable {
    static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        lhs.eventId == rhs.eventId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(eventId)
    }
}

// MARK: - Log Viewer View Model

/// View model for loading and managing log entries
final class LogViewerViewModel: ObservableObject {
    @Published var entries: [LogEntry] = []
    @Published var filteredEntries: [LogEntry] = []
    @Published var searchText: String = ""
    @Published var selectedOutcomeFilter: OutcomeFilter = .all
    @Published var startDate: Date?
    @Published var endDate: Date?
    @Published var isLoading: Bool = false
    @Published var selectedEntryID: String?

    private var cancellables = Set<AnyCancellable>()
    private let logPath: URL
    private var fileMonitor: DispatchSourceFileSystemObject?
    private let decoder = JSONDecoder()
    private let dateFormatter: ISO8601DateFormatter

    enum OutcomeFilter: String, CaseIterable {
        case all = "All"
        case success = "Success"
        case skipped = "Skipped"
        case failed = "Failed"
    }

    init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("InvoiceFiler")
        self.logPath = logsDir.appendingPathComponent("moves.jsonl")

        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        setupFilters()
        loadEntries()
        setupFileMonitor()
    }

    deinit {
        fileMonitor?.cancel()
    }

    private func setupFilters() {
        Publishers.CombineLatest4($entries, $searchText, $selectedOutcomeFilter, Publishers.CombineLatest($startDate, $endDate))
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] entries, search, outcomeFilter, dateRange in
                self?.applyFilters(entries: entries, search: search, outcomeFilter: outcomeFilter, startDate: dateRange.0, endDate: dateRange.1)
            }
            .store(in: &cancellables)
    }

    private func applyFilters(entries: [LogEntry], search: String, outcomeFilter: OutcomeFilter, startDate: Date?, endDate: Date?) {
        var filtered = entries

        // Filter by outcome
        if outcomeFilter != .all {
            filtered = filtered.filter { entry in
                switch outcomeFilter {
                case .success:
                    return entry.outcome == .success
                case .skipped:
                    return entry.outcome.rawValue.hasPrefix("skipped:")
                case .failed:
                    return entry.outcome.rawValue.hasPrefix("failed:")
                case .all:
                    return true
                }
            }
        }

        // Filter by search text
        if !search.isEmpty {
            let lowercasedSearch = search.lowercased()
            filtered = filtered.filter { entry in
                entry.filename.lowercased().contains(lowercasedSearch) ||
                entry.companyMatch?.company.lowercased().contains(lowercasedSearch) == true ||
                entry.sourcePath.lowercased().contains(lowercasedSearch) ||
                entry.destinationPath?.lowercased().contains(lowercasedSearch) == true
            }
        }

        // Filter by date range
        if let start = startDate {
            filtered = filtered.filter { entry in
                guard let entryDate = dateFormatter.date(from: entry.timestamp) else { return false }
                return entryDate >= start
            }
        }

        if let end = endDate {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
            filtered = filtered.filter { entry in
                guard let entryDate = dateFormatter.date(from: entry.timestamp) else { return false }
                return entryDate < endOfDay
            }
        }

        filteredEntries = filtered
    }

    func loadEntries() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var loadedEntries: [LogEntry] = []

            guard FileManager.default.fileExists(atPath: self.logPath.path),
                  let content = try? String(contentsOf: self.logPath, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self.entries = []
                    self.isLoading = false
                }
                return
            }

            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let entry = try? self.decoder.decode(LogEntry.self, from: data) else {
                    continue
                }
                loadedEntries.append(entry)
            }

            // Sort by timestamp descending (newest first)
            loadedEntries.sort { $0.timestamp > $1.timestamp }

            DispatchQueue.main.async {
                self.entries = loadedEntries
                self.isLoading = false
            }
        }
    }

    private func setupFileMonitor() {
        guard FileManager.default.fileExists(atPath: logPath.path) else { return }

        let fileDescriptor = open(logPath.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend],
            queue: DispatchQueue.main
        )

        fileMonitor?.setEventHandler { [weak self] in
            self?.loadEntries()
        }

        fileMonitor?.setCancelHandler {
            close(fileDescriptor)
        }

        fileMonitor?.resume()
    }

    func clearLog() {
        do {
            try "".write(to: logPath, atomically: true, encoding: .utf8)
            entries = []
        } catch {
            print("Failed to clear log: \(error)")
        }
    }

    func exportLog(to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(filteredEntries)
            try data.write(to: url)
        } catch {
            print("Failed to export log: \(error)")
        }
    }
}

// MARK: - Log Viewer View

/// Main log viewer window view
struct LogViewerView: View {
    @StateObject private var viewModel = LogViewerViewModel()
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbarView

            Divider()

            // Main content
            if viewModel.isLoading {
                ProgressView("Loading log entries...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredEntries.isEmpty {
                emptyStateView
            } else {
                logTableView
            }
        }
        .frame(minWidth: 900, minHeight: 500)
        .alert("Clear Log", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                viewModel.clearLog()
            }
        } message: {
            Text("Are you sure you want to clear all log entries? This cannot be undone.")
        }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search filename, company, path...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 300)

            // Outcome filter
            Picker("Outcome", selection: $viewModel.selectedOutcomeFilter) {
                ForEach(LogViewerViewModel.OutcomeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            // Date range
            HStack(spacing: 4) {
                DatePicker("From", selection: Binding(
                    get: { viewModel.startDate ?? Date.distantPast },
                    set: { viewModel.startDate = $0 }
                ), displayedComponents: .date)
                .labelsHidden()
                .frame(width: 100)

                Text("-")
                    .foregroundColor(.secondary)

                DatePicker("To", selection: Binding(
                    get: { viewModel.endDate ?? Date() },
                    set: { viewModel.endDate = $0 }
                ), displayedComponents: .date)
                .labelsHidden()
                .frame(width: 100)

                if viewModel.startDate != nil || viewModel.endDate != nil {
                    Button {
                        viewModel.startDate = nil
                        viewModel.endDate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Entry count
            Text("\(viewModel.filteredEntries.count) entries")
                .foregroundColor(.secondary)
                .font(.caption)

            // Export button
            Button {
                exportLog()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            // Clear button
            Button {
                showingClearConfirmation = true
            } label: {
                Label("Clear", systemImage: "trash")
            }

            // Refresh button
            Button {
                viewModel.loadEntries()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(12)
    }

    // MARK: - Log Table

    private var selectedEntry: LogEntry? {
        guard let id = viewModel.selectedEntryID else { return nil }
        return viewModel.filteredEntries.first { $0.eventId == id }
    }

    private var logTableView: some View {
        HSplitView {
            // Table
            Table(viewModel.filteredEntries, selection: $viewModel.selectedEntryID) {
                TableColumn("Time") { entry in
                    Text(formatTimestamp(entry.timestamp))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 80, ideal: 90, max: 100)

                TableColumn("Outcome") { entry in
                    outcomeLabel(for: entry.outcome)
                }
                .width(min: 100, ideal: 120, max: 150)

                TableColumn("Filename") { entry in
                    Text(entry.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 150, ideal: 200, max: 300)

                TableColumn("Company") { entry in
                    Text(entry.companyMatch?.company ?? "-")
                        .foregroundColor(entry.companyMatch == nil ? .secondary : .primary)
                }
                .width(min: 100, ideal: 150, max: 200)

                TableColumn("Action") { entry in
                    Text(entry.action)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 60, ideal: 70, max: 80)
            }
            .frame(minWidth: 500)

            // Detail pane
            if let entry = selectedEntry {
                LogEntryDetailView(entry: entry)
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
            } else {
                Text("Select an entry to view details")
                    .foregroundColor(.secondary)
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            if viewModel.entries.isEmpty {
                Text("No log entries yet")
                    .font(.headline)
                Text("Log entries will appear here as invoices are processed.")
                    .foregroundColor(.secondary)
            } else {
                Text("No matching entries")
                    .font(.headline)
                Text("Try adjusting your filters.")
                    .foregroundColor(.secondary)
                Button("Clear Filters") {
                    viewModel.searchText = ""
                    viewModel.selectedOutcomeFilter = .all
                    viewModel.startDate = nil
                    viewModel.endDate = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: timestamp) else {
            return timestamp
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "HH:mm:ss"
        return displayFormatter.string(from: date)
    }

    private func outcomeLabel(for outcome: LogOutcome) -> some View {
        let (text, color) = outcomeDisplay(outcome)
        return Text(text)
            .font(.system(.caption, design: .rounded).weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }

    private func outcomeDisplay(_ outcome: LogOutcome) -> (String, Color) {
        switch outcome {
        case .success:
            return ("Success", .green)
        case .skippedNotInvoice:
            return ("Not Invoice", .orange)
        case .skippedNoCompanyMatch:
            return ("No Company", .orange)
        case .skippedAlreadyFiled:
            return ("Already Filed", .orange)
        case .skippedLocked:
            return ("Locked", .orange)
        case .skippedUnstable:
            return ("Unstable", .orange)
        case .skippedExtractionFailed:
            return ("Extraction Failed", .orange)
        case .skippedProtected:
            return ("Protected", .orange)
        case .skippedNoContent:
            return ("No Content", .orange)
        case .skippedDeleted:
            return ("Deleted", .orange)
        case .failedMoveError:
            return ("Move Error", .red)
        case .failedLocked:
            return ("Failed: Locked", .red)
        }
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "invoice-log-export.json"

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.exportLog(to: url)
        }
    }
}

// MARK: - Log Entry Detail View

/// Detail view for a selected log entry
struct LogEntryDetailView: View {
    let entry: LogEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.filename)
                        .font(.headline)
                    Text(formatFullTimestamp(entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Basic info
                detailSection("Basic Info") {
                    detailRow("Event ID", entry.eventId)
                    detailRow("Action", entry.action)
                    detailRow("Outcome", entry.outcome.rawValue)
                    detailRow("File Size", formatFileSize(entry.fileSize))
                    detailRow("Processing Time", "\(entry.processingTimeMs) ms")
                }

                // Paths
                detailSection("Paths") {
                    detailRow("Source", entry.sourcePath)
                    if let dest = entry.destinationPath {
                        detailRow("Destination", dest)
                    }
                }

                // Company match
                if let company = entry.companyMatch {
                    detailSection("Company Match") {
                        detailRow("Company", company.company)
                        detailRow("Confidence", String(format: "%.0f%%", company.confidence * 100))
                        if !company.signals.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Signals:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(company.signals.indices, id: \.self) { i in
                                    let signal = company.signals[i]
                                    HStack {
                                        Text(signal.type.rawValue)
                                            .font(.caption.monospaced())
                                        if let matched = signal.matched {
                                            Text("(\(matched))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(String(format: "%.0f%%", signal.confidence * 100))
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }

                // Extraction details
                if let extraction = entry.extraction {
                    detailSection("Extraction") {
                        detailRow("Method", extraction.method.rawValue)
                        detailRow("Confidence", String(format: "%.0f%%", extraction.confidence * 100))
                        detailRow("Pages", "\(extraction.pageCount)")
                        detailRow("Text Length", "\(extraction.textLength) chars")
                        detailRow("Time", "\(extraction.extractionTimeMs) ms")
                    }
                }

                // Invoice classification
                if let classification = entry.invoiceClassification {
                    detailSection("Invoice Classification") {
                        detailRow("Is Invoice", classification.isInvoice ? "Yes" : "No")
                        detailRow("Confidence", String(format: "%.0f%%", classification.confidence * 100))
                        if !classification.keywordMatches.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Keywords:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(classification.keywordMatches.indices, id: \.self) { i in
                                    let kw = classification.keywordMatches[i]
                                    HStack {
                                        Text(kw.keyword)
                                            .font(.caption.monospaced())
                                        Text(kw.category)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(String(format: "%.1f", kw.weight))
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }

                // Date extraction
                if let dateInfo = entry.dateExtraction {
                    detailSection("Date Extraction") {
                        detailRow("Date", dateInfo.extractedDate)
                        detailRow("Source", dateInfo.source.rawValue)
                        if let pattern = dateInfo.pattern {
                            detailRow("Pattern", pattern)
                        }
                    }
                }

                // Error info
                if let errorCode = entry.errorCode {
                    detailSection("Error") {
                        detailRow("Code", errorCode)
                        if let errorMsg = entry.errorMessage {
                            detailRow("Message", errorMsg)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            content()
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func formatFullTimestamp(_ timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = formatter.date(from: timestamp) else {
            return timestamp
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .medium
        return displayFormatter.string(from: date)
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview

#if DEBUG
struct LogViewerView_Previews: PreviewProvider {
    static var previews: some View {
        LogViewerView()
    }
}
#endif
