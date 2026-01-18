import SwiftUI

/// Main preferences window view with tabbed sections
struct PreferencesView: View {
    @ObservedObject private var configManager = ConfigManager.shared

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PathsSettingsView()
                .tabItem {
                    Label("Paths", systemImage: "folder")
                }

            CompaniesSettingsView()
                .tabItem {
                    Label("Companies", systemImage: "building.2")
                }

            ProcessingSettingsView()
                .tabItem {
                    Label("Processing", systemImage: "cpu")
                }
        }
        .frame(width: 600, height: 450)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @State private var launchAtLogin: Bool = false
    @State private var debounceInterval: Double = 3.0

    var body: some View {
        Form {
            Section {
                if #available(macOS 13.0, *) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            updateLaunchAtLogin(newValue)
                        }
                }

                HStack {
                    Text("Debounce Interval:")
                    Slider(value: $debounceInterval, in: 0.5...10, step: 0.5)
                    Text("\(debounceInterval, specifier: "%.1f")s")
                        .frame(width: 40)
                }
                .onChange(of: debounceInterval) { newValue in
                    updateDebounceInterval(newValue)
                }
            } header: {
                Text("Startup")
            }

            Section {
                HStack {
                    Text("Log Location:")
                    Text(configManager.config.logLocation.path)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.selectFile(
                            configManager.config.logLocation.path,
                            inFileViewerRootedAtPath: ""
                        )
                    }
                }

                Toggle("Log Extracted Text (Privacy)", isOn: Binding(
                    get: { configManager.config.logExtractedText },
                    set: { updateLogExtractedText($0) }
                ))
            } header: {
                Text("Logging")
            }

            Section {
                HStack {
                    Text("Config File:")
                    Text(configManager.configFileURL.path)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(
                            configManager.configFileURL.path,
                            inFileViewerRootedAtPath: ""
                        )
                    }
                }
                Text("Back up this file to preserve your settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Advanced")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadValues()
        }
    }

    private func loadValues() {
        launchAtLogin = configManager.config.launchAtLogin
        debounceInterval = configManager.config.debounceInterval
    }

    private func updateLaunchAtLogin(_ value: Bool) {
        try? configManager.updateConfig { config in
            config.launchAtLogin = value
        }
        if #available(macOS 13.0, *) {
            LaunchAtLoginManager.shared.sync(with: value)
        }
    }

    private func updateDebounceInterval(_ value: Double) {
        try? configManager.updateConfig { config in
            config.debounceInterval = value
        }
    }

    private func updateLogExtractedText(_ value: Bool) {
        try? configManager.updateConfig { config in
            config.logExtractedText = value
        }
    }
}

// MARK: - Paths Settings

struct PathsSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @State private var monitoredPaths: [MonitoredPath] = []
    @State private var destinationRoot: URL?
    @State private var supportedExtensions: String = ""
    @State private var exclusionPatterns: String = ""
    @State private var selectedPath: MonitoredPath?

    var body: some View {
        Form {
            Section {
                List(monitoredPaths, id: \.self, selection: $selectedPath) { path in
                    HStack {
                        Image(systemName: path.recursive ? "folder.fill.badge.gearshape" : "folder")
                        VStack(alignment: .leading) {
                            Text(path.path.lastPathComponent)
                                .fontWeight(.medium)
                            Text(path.path.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if path.recursive {
                            Text("Recursive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 120)

                HStack {
                    Button("Add...") {
                        addMonitoredPath()
                    }
                    Button("Remove") {
                        if let path = selectedPath {
                            removeMonitoredPath(path)
                        }
                    }
                    .disabled(selectedPath == nil)
                }
            } header: {
                Text("Monitored Directories")
            }

            Section {
                HStack {
                    Text("Destination Root:")
                    Text(destinationRoot?.path ?? "Same as source")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose...") {
                        chooseDestinationRoot()
                    }
                    if destinationRoot != nil {
                        Button("Clear") {
                            clearDestinationRoot()
                        }
                    }
                }
            } header: {
                Text("Destination")
            }

            Section {
                TextField("Extensions (comma-separated):", text: $supportedExtensions)
                    .onSubmit {
                        updateSupportedExtensions()
                    }
                Text("e.g., pdf, png, jpg, jpeg, heic")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Supported File Types")
            }

            Section {
                TextField("Exclusion Patterns (comma-separated):", text: $exclusionPatterns)
                    .onSubmit {
                        updateExclusionPatterns()
                    }
                Text("e.g., .*, *.tmp, *.download")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Exclusions")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadValues()
        }
    }

    private func loadValues() {
        monitoredPaths = configManager.config.monitoredPaths
        destinationRoot = configManager.config.destinationRoot
        supportedExtensions = configManager.config.supportedExtensions.sorted().joined(separator: ", ")
        exclusionPatterns = configManager.config.exclusionPatterns.joined(separator: ", ")
    }

    private func addMonitoredPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory to monitor for invoices"

        if panel.runModal() == .OK, let url = panel.url {
            let newPath = MonitoredPath(path: url, recursive: false)
            try? configManager.addMonitoredPath(newPath)
            monitoredPaths = configManager.config.monitoredPaths
        }
    }

    private func removeMonitoredPath(_ path: MonitoredPath) {
        try? configManager.removeMonitoredPath(at: path.path)
        monitoredPaths = configManager.config.monitoredPaths
        selectedPath = nil
    }

    private func chooseDestinationRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the root directory for organized invoices"

        if panel.runModal() == .OK, let url = panel.url {
            try? configManager.updateConfig { config in
                config.destinationRoot = url
            }
            destinationRoot = url
        }
    }

    private func clearDestinationRoot() {
        try? configManager.updateConfig { config in
            config.destinationRoot = nil
        }
        destinationRoot = nil
    }

    private func updateSupportedExtensions() {
        let extensions = Set(supportedExtensions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })

        try? configManager.updateConfig { config in
            config.supportedExtensions = extensions
        }
    }

    private func updateExclusionPatterns() {
        let patterns = exclusionPatterns
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        try? configManager.updateConfig { config in
            config.exclusionPatterns = patterns
        }
    }
}

// MARK: - Companies Settings

struct CompaniesSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared
    @State private var companies: [CompanyConfig] = []
    @State private var selectedCompany: CompanyConfig?
    @State private var showingAddSheet = false
    @State private var showingEditSheet = false

    var body: some View {
        VStack(spacing: 0) {
            List(companies, id: \.self, selection: $selectedCompany) { company in
                VStack(alignment: .leading, spacing: 4) {
                    Text(company.name)
                        .fontWeight(.medium)

                    HStack(spacing: 12) {
                        if !company.aliases.isEmpty {
                            Label("\(company.aliases.count) aliases", systemImage: "text.badge.plus")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if !company.taxIds.isEmpty {
                            Label("\(company.taxIds.count) tax IDs", systemImage: "number")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if !company.domains.isEmpty {
                            Label("\(company.domains.count) domains", systemImage: "globe")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
                Button(action: { showingEditSheet = true }) {
                    Image(systemName: "pencil")
                }
                .disabled(selectedCompany == nil)
                Button(action: removeSelectedCompany) {
                    Image(systemName: "minus")
                }
                .disabled(selectedCompany == nil)
                Spacer()
                Text("\(companies.count) companies")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
        .onAppear {
            companies = configManager.config.companies
        }
        .sheet(isPresented: $showingAddSheet) {
            CompanyEditorView(company: nil) { newCompany in
                try? configManager.addCompany(newCompany)
                companies = configManager.config.companies
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let company = selectedCompany {
                CompanyEditorView(company: company) { updatedCompany in
                    try? configManager.updateCompany(updatedCompany)
                    companies = configManager.config.companies
                    selectedCompany = updatedCompany
                }
            }
        }
    }

    private func removeSelectedCompany() {
        guard let company = selectedCompany else { return }
        try? configManager.removeCompany(named: company.name)
        companies = configManager.config.companies
        selectedCompany = nil
    }
}

// MARK: - Company Editor Sheet

struct CompanyEditorView: View {
    let company: CompanyConfig?
    let onSave: (CompanyConfig) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var aliases: String = ""
    @State private var taxIds: String = ""
    @State private var domains: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(company == nil ? "Add Company" : "Edit Company")
                .font(.headline)

            Form {
                TextField("Company Name:", text: $name)

                Section {
                    TextField("Aliases (comma-separated):", text: $aliases)
                    Text("Alternative names or spellings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    TextField("Tax IDs (comma-separated):", text: $taxIds)
                    Text("EIN, VAT, or other tax identifiers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    TextField("Domains (comma-separated):", text: $domains)
                    Text("Email domains like example.com")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveCompany()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
        .onAppear {
            if let company = company {
                name = company.name
                aliases = company.aliases.joined(separator: ", ")
                taxIds = company.taxIds.joined(separator: ", ")
                domains = company.domains.joined(separator: ", ")
            }
        }
    }

    private func saveCompany() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let parsedAliases = aliases
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let parsedTaxIds = taxIds
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let parsedDomains = domains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        let newCompany = CompanyConfig(
            name: trimmedName,
            aliases: parsedAliases,
            taxIds: parsedTaxIds,
            domains: parsedDomains
        )

        onSave(newCompany)
        dismiss()
    }
}

// MARK: - Processing Settings

struct ProcessingSettingsView: View {
    @ObservedObject private var configManager = ConfigManager.shared

    @State private var ocrLanguages: String = ""
    @State private var invoiceConfidence: Float = 0.7
    @State private var companyMatchThreshold: Float = 0.8
    @State private var maxOCRPages: Int = 3
    @State private var enableFilenameHint: Bool = true
    @State private var dateSource: DateSource = .extractedInvoiceDate

    var body: some View {
        Form {
            Section {
                Picker("Date Source:", selection: $dateSource) {
                    Text("Extracted Invoice Date").tag(DateSource.extractedInvoiceDate)
                    Text("File Creation Date").tag(DateSource.fileCreationDate)
                    Text("File Modification Date").tag(DateSource.fileModificationDate)
                    Text("Current Date").tag(DateSource.currentDate)
                }
                .onChange(of: dateSource) { newValue in
                    updateDateSource(newValue)
                }

                Toggle("Use Filename as Matching Hint", isOn: $enableFilenameHint)
                    .onChange(of: enableFilenameHint) { newValue in
                        updateEnableFilenameHint(newValue)
                    }
            } header: {
                Text("Classification")
            }

            Section {
                TextField("OCR Languages (comma-separated):", text: $ocrLanguages)
                    .onSubmit {
                        updateOCRLanguages()
                    }
                Text("Language codes like en-US, de-DE, fr-FR")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Stepper("Max OCR Pages: \(maxOCRPages)", value: $maxOCRPages, in: 1...20)
                    .onChange(of: maxOCRPages) { newValue in
                        updateMaxOCRPages(newValue)
                    }
            } header: {
                Text("OCR")
            }

            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Invoice Confidence:")
                        Slider(value: $invoiceConfidence, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(invoiceConfidence * 100))%")
                            .frame(width: 40)
                    }
                    .onChange(of: invoiceConfidence) { newValue in
                        updateInvoiceConfidence(newValue)
                    }
                    Text("Minimum confidence to classify a document as an invoice")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Company Match:")
                        Slider(value: $companyMatchThreshold, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(companyMatchThreshold * 100))%")
                            .frame(width: 40)
                    }
                    .onChange(of: companyMatchThreshold) { newValue in
                        updateCompanyMatchThreshold(newValue)
                    }
                    Text("Minimum confidence for company name matching")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Confidence Thresholds")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadValues()
        }
    }

    private func loadValues() {
        let config = configManager.config
        ocrLanguages = config.ocrLanguages.joined(separator: ", ")
        invoiceConfidence = config.invoiceConfidenceThreshold
        companyMatchThreshold = config.companyMatchThreshold
        maxOCRPages = config.maxOCRPages
        enableFilenameHint = config.enableFilenameHint
        dateSource = config.dateSource
    }

    private func updateOCRLanguages() {
        let languages = ocrLanguages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        try? configManager.updateConfig { config in
            config.ocrLanguages = languages
        }
    }

    private func updateInvoiceConfidence(_ value: Float) {
        try? configManager.updateConfig { config in
            config.invoiceConfidenceThreshold = value
        }
    }

    private func updateCompanyMatchThreshold(_ value: Float) {
        try? configManager.updateConfig { config in
            config.companyMatchThreshold = value
        }
    }

    private func updateMaxOCRPages(_ value: Int) {
        try? configManager.updateConfig { config in
            config.maxOCRPages = value
        }
    }

    private func updateEnableFilenameHint(_ value: Bool) {
        try? configManager.updateConfig { config in
            config.enableFilenameHint = value
        }
    }

    private func updateDateSource(_ value: DateSource) {
        try? configManager.updateConfig { config in
            config.dateSource = value
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
#endif
