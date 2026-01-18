import SwiftUI

/// Main view for invoice management - templates and drafts
struct InvoicingView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TemplatesListView()
                .tabItem {
                    Label("Templates", systemImage: "doc.text")
                }
                .tag(0)

            DraftsListView()
                .tabItem {
                    Label("Drafts", systemImage: "doc.badge.clock")
                }
                .tag(1)

            SchedulingSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)
        }
        .frame(width: 800, height: 600)
    }
}

// MARK: - Templates List

struct TemplatesListView: View {
    @ObservedObject private var scheduler = InvoiceScheduler.shared
    @State private var selectedTemplate: InvoiceTemplate?
    @State private var showingEditor = false
    @State private var showingAddTemplate = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Invoice Templates")
                    .font(.headline)

                Spacer()

                Button(action: { showingAddTemplate = true }) {
                    Label("New Template", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            // List
            if scheduler.templates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.below.ecg")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No templates yet")
                        .foregroundColor(.secondary)
                    Text("Create a template to start generating invoices automatically")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Create Template") {
                        showingAddTemplate = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(scheduler.templates, selection: $selectedTemplate) { template in
                    TemplateRow(template: template)
                        .tag(template)
                        .contextMenu {
                            Button("Edit") {
                                selectedTemplate = template
                                showingEditor = true
                            }
                            Button("Generate Invoice Now") {
                                generateInvoice(from: template)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                scheduler.deleteTemplate(template)
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showingAddTemplate) {
            InvoiceTemplateEditorView(template: nil, onSave: nil)
        }
        .sheet(isPresented: $showingEditor) {
            if let template = selectedTemplate {
                InvoiceTemplateEditorView(template: template, onSave: nil)
            }
        }
    }

    private func generateInvoice(from template: InvoiceTemplate) {
        _ = scheduler.generateDraft(from: template)
    }
}

struct TemplateRow: View {
    let template: InvoiceTemplate

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(template.name)
                        .fontWeight(.medium)
                    if !template.isActive {
                        Text("Inactive")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                Text(template.clientCompanyName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(template.currency.format(template.subtotal))
                    .fontWeight(.medium)
                Text("Day \(template.billingDayOfMonth) of month")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Scheduling Settings

struct SchedulingSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @ObservedObject private var scheduler = InvoiceScheduler.shared

    @State private var senderCountry: String = "US"
    @State private var schedulingEnabled: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Invoice Scheduling", isOn: $schedulingEnabled)
                    .onChange(of: schedulingEnabled) { newValue in
                        updateSchedulingEnabled(newValue)
                    }

                if schedulingEnabled {
                    Text("Invoices will be automatically generated based on template billing dates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Automatic Generation")
            }

            Section {
                Picker("Your Country", selection: $senderCountry) {
                    Text("United States").tag("US")
                    Text("United Kingdom").tag("GB")
                    Text("Germany").tag("DE")
                    Text("France").tag("FR")
                    Text("Canada").tag("CA")
                    Text("Australia").tag("AU")
                    Text("Netherlands").tag("NL")
                    Text("Switzerland").tag("CH")
                    Text("Japan").tag("JP")
                    Text("Singapore").tag("SG")
                }
                .onChange(of: senderCountry) { newValue in
                    updateSenderCountry(newValue)
                }

                Text("Used to calculate bank holidays when scheduling invoice generation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Bank Holidays")
            }

            Section {
                HStack {
                    Text("Active Templates")
                    Spacer()
                    Text("\(scheduler.activeTemplates.count)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Pending Drafts")
                    Spacer()
                    Text("\(scheduler.pendingDrafts.count)")
                        .foregroundColor(scheduler.pendingDrafts.isEmpty ? .secondary : .orange)
                }
            } header: {
                Text("Status")
            }

            Section {
                Button("Check for Due Invoices Now") {
                    scheduler.checkAndGenerateDrafts()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadValues()
        }
    }

    private func loadValues() {
        senderCountry = configManager.config.senderCountryCode
        schedulingEnabled = configManager.config.invoiceSchedulingEnabled
    }

    private func updateSenderCountry(_ value: String) {
        try? configManager.updateConfig { config in
            config.senderCountryCode = value
        }
    }

    private func updateSchedulingEnabled(_ value: Bool) {
        try? configManager.updateConfig { config in
            config.invoiceSchedulingEnabled = value
        }

        if value {
            scheduler.startScheduler()
        } else {
            scheduler.stopScheduler()
        }
    }
}

// MARK: - Window Controller

class InvoicingWindowController: NSObject {
    static let shared = InvoicingWindowController()

    private var window: NSWindow?

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = InvoicingView()

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Invoice Management"
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
