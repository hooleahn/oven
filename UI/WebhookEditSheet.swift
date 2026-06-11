import SwiftUI

// MARK: - WebhookEditSheet

struct WebhookEditSheet: View {
    let existing: WebhookNotification?
    let onSave: (WebhookNotification) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var webhook: WebhookNotification
    @State private var secretValue: String = ""
    @State private var secretIsAlreadySaved = false
    @State private var copiedToken: String? = nil

    private var isNew: Bool { existing == nil }

    private static let tokens = ["%%VMNAME%%", "%%EVENTTYPE%%", "%%TIMESTAMP%%", "%%DATETIME%%"]

    init(existing: WebhookNotification?, onSave: @escaping (WebhookNotification) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _webhook = State(initialValue: existing ?? WebhookNotification())
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                authSection
                headersSection
                payloadSection
                datetimeSection
                eventsSection
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "Add Webhook" : "Edit Webhook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isFormValid)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 620)
        .onAppear { loadSecret() }
        .onChange(of: webhook.authType) { _, _ in
            secretValue = ""
            loadSecret()
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        Section("Identity") {
            LabeledContent("Name") {
                TextField("My Webhook", text: $webhook.displayName)
            }
            LabeledContent("URL") {
                TextField("https://example.com/webhook", text: $webhook.url)
            }
            Toggle("Enabled", isOn: $webhook.isEnabled)
        }
    }

    // MARK: - Authentication

    private var authSection: some View {
        Section("Authentication") {
            Picker("Type", selection: $webhook.authType) {
                ForEach(WebhookAuthType.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .pickerStyle(.segmented)

            if webhook.authType == .basic {
                LabeledContent("Username") {
                    TextField("", text: $webhook.basicAuthUsername)
                }
                LabeledContent("Password") {
                    HStack(spacing: 6) {
                        if secretIsAlreadySaved && secretValue.isEmpty {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.green)
                                .help("Saved in Keychain")
                        }
                        SecureField(secretIsAlreadySaved ? "Leave blank to keep" : "Required",
                                    text: $secretValue)
                    }
                }
            }

            if webhook.authType == .custom {
                LabeledContent("Header Name") {
                    TextField("X-API-Key", text: $webhook.customAuthHeaderName)
                }
                LabeledContent("Header Value") {
                    HStack(spacing: 6) {
                        if secretIsAlreadySaved && secretValue.isEmpty {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.green)
                                .help("Saved in Keychain")
                        }
                        SecureField(secretIsAlreadySaved ? "Leave blank to keep" : "Required",
                                    text: $secretValue)
                    }
                }
            }
        }
    }

    // MARK: - Additional Headers

    private var headersSection: some View {
        Section {
            TextEditor(text: $webhook.additionalHeaders)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 60, maxHeight: 100)
        } header: {
            Text("Additional Headers")
        } footer: {
            Text("One per line: Header-Name: Value")
        }
    }

    // MARK: - Payload

    private var payloadSection: some View {
        Section {
            tokenBar
            TextEditor(text: $webhook.jsonPayload)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 130)
        } header: {
            Text("JSON Payload")
        } footer: {
            payloadFooter
        }
    }

    private var tokenBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                Text("Insert:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Self.tokens, id: \.self) { token in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(token, forType: .string)
                        copiedToken = token
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if copiedToken == token { copiedToken = nil }
                        }
                    } label: {
                        Text(copiedToken == token ? "Copied!" : token)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Copy to clipboard, then paste into the payload")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var payloadFooter: some View {
        if !webhook.jsonPayload.isEmpty {
            if isValidJSON {
                Label("Valid JSON", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Label("Template tokens are substituted before sending — JSON validity is checked with placeholder values", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    // MARK: - Datetime Format

    private var datetimeSection: some View {
        Section {
            LabeledContent("Format") {
                TextField("%Y-%m-%d %H:%M:%S", text: $webhook.datetimeFormat)
                    .font(.system(.body, design: .monospaced))
            }
        } header: {
            Text("Datetime Format")
        } footer: {
            Text("Formats %%DATETIME%%. Leave empty for ISO 8601. Supports macOS date(1) specifiers: %Y year, %m month, %d day, %H hour (24h), %M minute, %S second, %Z timezone.")
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        Section("Events") {
            DisclosureGroup("Trigger on…") {
                ForEach(NotificationEvent.allCases) { event in
                    Toggle(isOn: eventBinding(event)) {
                        Label(event.label, systemImage: event.systemImage)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        !webhook.displayName.isEmpty && !webhook.url.isEmpty && URL(string: webhook.url) != nil
    }

    private var isValidJSON: Bool {
        let dummy = webhook.jsonPayload
            .replacingOccurrences(of: "%%VMNAME%%", with: "TestVM")
            .replacingOccurrences(of: "%%EVENTTYPE%%", with: "test")
            .replacingOccurrences(of: "%%TIMESTAMP%%", with: "1234567890")
            .replacingOccurrences(of: "%%DATETIME%%", with: "2024-01-01T00:00:00Z")
        guard let data = dummy.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private func eventBinding(_ event: NotificationEvent) -> Binding<Bool> {
        Binding(
            get: { webhook.enabledEvents.contains(event.rawValue) },
            set: { enabled in
                if enabled {
                    if !webhook.enabledEvents.contains(event.rawValue) {
                        webhook.enabledEvents.append(event.rawValue)
                    }
                } else {
                    webhook.enabledEvents.removeAll { $0 == event.rawValue }
                }
            }
        )
    }

    private func loadSecret() {
        guard let id = existing?.id else {
            secretIsAlreadySaved = false
            return
        }
        switch webhook.authType {
        case .none:
            secretIsAlreadySaved = false
        case .basic:
            secretIsAlreadySaved = NotificationService.shared.webhookPassword(for: id)?.isEmpty == false
        case .custom:
            secretIsAlreadySaved = NotificationService.shared.webhookCustomHeaderValue(for: id)?.isEmpty == false
        }
    }

    private func save() {
        switch webhook.authType {
        case .none:
            NotificationService.shared.setWebhookPassword(nil, for: webhook.id)
            NotificationService.shared.setWebhookCustomHeaderValue(nil, for: webhook.id)
        case .basic:
            if !secretValue.isEmpty {
                NotificationService.shared.setWebhookPassword(secretValue, for: webhook.id)
            }
            NotificationService.shared.setWebhookCustomHeaderValue(nil, for: webhook.id)
        case .custom:
            if !secretValue.isEmpty {
                NotificationService.shared.setWebhookCustomHeaderValue(secretValue, for: webhook.id)
            }
            NotificationService.shared.setWebhookPassword(nil, for: webhook.id)
        }
        onSave(webhook)
        dismiss()
    }
}
