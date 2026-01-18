import Foundation
import Combine
import UserNotifications

/// Manages invoice templates and scheduled draft generation
final class InvoiceScheduler: ObservableObject {

    // MARK: - Singleton

    static let shared = InvoiceScheduler()

    // MARK: - Published Properties

    @Published private(set) var templates: [InvoiceTemplate] = []
    @Published private(set) var draftInvoices: [DraftInvoice] = []
    @Published private(set) var pendingDrafts: [DraftInvoice] = []

    // MARK: - Properties

    private let workingDayCalculator = WorkingDayCalculator.shared
    private var schedulerTimer: Timer?
    private let fileManager = FileManager.default

    /// Directory for storing invoice data
    private var dataDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("InvoiceFiler").appendingPathComponent("Invoices")
    }

    private var templatesFileURL: URL {
        dataDirectory.appendingPathComponent("templates.json")
    }

    private var draftsFileURL: URL {
        dataDirectory.appendingPathComponent("drafts.json")
    }

    private var sequenceFileURL: URL {
        dataDirectory.appendingPathComponent("sequence.json")
    }

    // MARK: - Initialization

    private init() {
        ensureDataDirectoryExists()
        loadTemplates()
        loadDrafts()
        updatePendingDrafts()
    }

    // MARK: - Template Management

    /// Add a new invoice template
    func addTemplate(_ template: InvoiceTemplate) {
        var newTemplate = template
        newTemplate.createdAt = Date()
        newTemplate.updatedAt = Date()
        templates.append(newTemplate)
        saveTemplates()
    }

    /// Update an existing template
    func updateTemplate(_ template: InvoiceTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            var updated = template
            updated.updatedAt = Date()
            templates[index] = updated
            saveTemplates()
        }
    }

    /// Delete a template
    func deleteTemplate(_ template: InvoiceTemplate) {
        templates.removeAll { $0.id == template.id }
        saveTemplates()
    }

    /// Get templates for a specific client
    func templates(forClient clientName: String) -> [InvoiceTemplate] {
        templates.filter { $0.clientCompanyName.lowercased() == clientName.lowercased() }
    }

    /// Get active templates
    var activeTemplates: [InvoiceTemplate] {
        templates.filter { $0.isActive }
    }

    // MARK: - Draft Invoice Management

    /// Generate a draft invoice from a template
    /// Due date is calculated as: next billing day - 1 working day
    /// This ensures payment arrives before the billing day (e.g., for salary payments)
    func generateDraft(from template: InvoiceTemplate, forDate date: Date = Date()) -> DraftInvoice {
        let sequence = getNextSequence(for: date)
        let invoiceNumber = InvoiceNumberGenerator.generate(
            clientPrefix: String(template.clientCompanyName.prefix(4)),
            date: date,
            sequence: sequence
        )

        let calendar = Calendar.current

        // Calculate the next billing day (in the next month)
        var components = calendar.dateComponents([.year, .month], from: date)
        components.month! += 1
        components.day = template.billingDayOfMonth
        let nextBillingDay = calendar.date(from: components) ?? date

        // Subtract 1 working day from billing day to get due date
        // This ensures payment arrives BEFORE the billing day
        let dueDate = previousWorkingDay(before: nextBillingDay)

        // Calculate payment terms from the due date (due date - issue date)
        let daysBetween = calendar.dateComponents([.day], from: date, to: dueDate).day ?? template.paymentTerms.daysUntilDue
        var adjustedPaymentTerms = template.paymentTerms
        adjustedPaymentTerms.daysUntilDue = max(0, daysBetween)

        var draft = DraftInvoice.fromTemplate(
            template,
            invoiceNumber: invoiceNumber,
            issueDate: date,
            dueDate: dueDate
        )
        draft.paymentTerms = adjustedPaymentTerms

        draftInvoices.append(draft)
        saveDrafts()
        updatePendingDrafts()

        // Send notification
        if #available(macOS 10.14, *) {
            NotificationManager.shared.showDraftInvoiceReady(
                invoiceNumber: invoiceNumber,
                clientName: template.clientCompanyName
            )
        }

        return draft
    }

    /// Get the previous working day before a given date (subtracts 1 working day)
    /// Uses simple weekend detection; for holiday-aware calculation use WorkingDayCalculator
    private func previousWorkingDay(before date: Date) -> Date {
        let calendar = Calendar.current
        var result = calendar.date(byAdding: .day, value: -1, to: date) ?? date

        // Skip weekends (Saturday = 7, Sunday = 1)
        var weekday = calendar.component(.weekday, from: result)
        while weekday == 1 || weekday == 7 {
            result = calendar.date(byAdding: .day, value: -1, to: result) ?? result
            weekday = calendar.component(.weekday, from: result)
        }

        return result
    }

    /// Update a draft invoice
    func updateDraft(_ draft: DraftInvoice) {
        if let index = draftInvoices.firstIndex(where: { $0.id == draft.id }) {
            var updated = draft
            updated.updatedAt = Date()
            draftInvoices[index] = updated
            saveDrafts()
            updatePendingDrafts()
        }
    }

    /// Approve a draft invoice
    func approveDraft(_ draft: DraftInvoice) {
        if let index = draftInvoices.firstIndex(where: { $0.id == draft.id }) {
            var approved = draft
            approved.status = .approved
            approved.updatedAt = Date()
            draftInvoices[index] = approved
            saveDrafts()
            updatePendingDrafts()
        }
    }

    /// Mark a draft as sent
    func markDraftAsSent(_ draft: DraftInvoice) {
        if let index = draftInvoices.firstIndex(where: { $0.id == draft.id }) {
            var sent = draft
            sent.status = .sent
            sent.sentAt = Date()
            sent.updatedAt = Date()
            draftInvoices[index] = sent
            saveDrafts()
            updatePendingDrafts()
        }
    }

    /// Cancel a draft invoice
    func cancelDraft(_ draft: DraftInvoice) {
        if let index = draftInvoices.firstIndex(where: { $0.id == draft.id }) {
            var cancelled = draft
            cancelled.status = .cancelled
            cancelled.updatedAt = Date()
            draftInvoices[index] = cancelled
            saveDrafts()
            updatePendingDrafts()
        }
    }

    /// Delete a draft invoice
    func deleteDraft(_ draft: DraftInvoice) {
        draftInvoices.removeAll { $0.id == draft.id }
        saveDrafts()
        updatePendingDrafts()
    }

    /// Get drafts by status
    func drafts(withStatus status: DraftInvoiceStatus) -> [DraftInvoice] {
        draftInvoices.filter { $0.status == status }
    }

    // MARK: - Scheduling

    /// Start the scheduler to check for invoices that need to be generated
    func startScheduler() {
        stopScheduler()

        // Check every hour
        schedulerTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkAndGenerateDrafts()
        }

        // Also check immediately
        checkAndGenerateDrafts()
    }

    /// Stop the scheduler
    func stopScheduler() {
        schedulerTimer?.invalidate()
        schedulerTimer = nil
    }

    /// Check if any invoices need to be generated today
    func checkAndGenerateDrafts() {
        let today = Date()
        let calendar = Calendar.current
        let dayOfMonth = calendar.component(.day, from: today)

        for template in activeTemplates {
            // Check if today is the billing day
            guard template.billingDayOfMonth == dayOfMonth else { continue }

            // Check if we already generated a draft for this template this month
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            let existingDraft = draftInvoices.first { draft in
                draft.templateId == template.id &&
                draft.createdAt >= monthStart
            }

            if existingDraft == nil {
                // Generate new draft
                _ = generateDraft(from: template, forDate: today)
            }
        }
    }

    /// Calculate when an invoice should be generated based on due date and working days
    func calculateGenerationDate(
        dueDate: Date,
        paymentTerms: Int,
        senderCountry: String,
        recipientCountry: String,
        completion: @escaping (Result<Date, Error>) -> Void
    ) {
        workingDayCalculator.dateSubtractingWorkingDays(
            paymentTerms,
            from: dueDate,
            senderCountry: senderCountry,
            recipientCountry: recipientCountry,
            completion: completion
        )
    }

    // MARK: - Private Methods

    private func ensureDataDirectoryExists() {
        try? fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    }

    private func loadTemplates() {
        guard fileManager.fileExists(atPath: templatesFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: templatesFileURL)
            templates = try JSONDecoder().decode([InvoiceTemplate].self, from: data)
        } catch {
            print("Failed to load templates: \(error)")
        }
    }

    private func saveTemplates() {
        do {
            let data = try JSONEncoder().encode(templates)
            try data.write(to: templatesFileURL, options: .atomic)
        } catch {
            print("Failed to save templates: \(error)")
        }
    }

    private func loadDrafts() {
        guard fileManager.fileExists(atPath: draftsFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: draftsFileURL)
            draftInvoices = try JSONDecoder().decode([DraftInvoice].self, from: data)
        } catch {
            print("Failed to load drafts: \(error)")
        }
    }

    private func saveDrafts() {
        do {
            let data = try JSONEncoder().encode(draftInvoices)
            try data.write(to: draftsFileURL, options: .atomic)
        } catch {
            print("Failed to save drafts: \(error)")
        }
    }

    private func updatePendingDrafts() {
        pendingDrafts = draftInvoices.filter { $0.status == .pending }
    }

    private func getNextSequence(for date: Date) -> Int {
        var sequences: [String: Int] = [:]

        // Load existing sequences
        if fileManager.fileExists(atPath: sequenceFileURL.path),
           let data = try? Data(contentsOf: sequenceFileURL),
           let loaded = try? JSONDecoder().decode([String: Int].self, from: data) {
            sequences = loaded
        }

        // Get key for this month
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM"
        let key = formatter.string(from: date)

        // Increment sequence
        let sequence = (sequences[key] ?? 0) + 1
        sequences[key] = sequence

        // Save
        if let data = try? JSONEncoder().encode(sequences) {
            try? data.write(to: sequenceFileURL, options: .atomic)
        }

        return sequence
    }
}

// MARK: - NotificationManager Extension

@available(macOS 10.14, *)
extension NotificationManager {

    /// Show notification when a draft invoice is ready for review
    func showDraftInvoiceReady(invoiceNumber: String, clientName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Draft Invoice Ready"
        content.body = "\(invoiceNumber) for \(clientName) is ready for review"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Show notification when invoice generation is due
    func showInvoiceGenerationReminder(clientName: String, dueDate: Date) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let content = UNMutableNotificationContent()
        content.title = "Invoice Due Soon"
        content.body = "Invoice for \(clientName) is due \(formatter.string(from: dueDate))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
