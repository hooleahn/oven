import SwiftUI
import UserNotifications

// MARK: - NotificationEvent

/// All notification events the user can subscribe to per-service.
enum NotificationEvent: String, CaseIterable, Identifiable {
    case baseVMBuildSucceeded = "baseVMBuildSucceeded"
    case baseVMBuildFailed    = "baseVMBuildFailed"
    case baseVMBuildStarted   = "baseVMBuildStarted"
    case ipswDownloaded       = "ipswDownloaded"
    case imagePullCompleted   = "imagePullCompleted"
    case imagePushCompleted   = "imagePushCompleted"
    case vmStopped            = "vmStopped"
    case vmStarted            = "vmStarted"
    case vmStartFailed        = "vmStartFailed"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .baseVMBuildSucceeded: return "Base VM build succeeded"
        case .baseVMBuildFailed:    return "Base VM build failed"
        case .baseVMBuildStarted:   return "Base VM build started"
        case .ipswDownloaded:       return "IPSW downloaded"
        case .imagePullCompleted:   return "Registry pull completed"
        case .imagePushCompleted:   return "Registry push completed"
        case .vmStopped:            return "VM stopped"
        case .vmStarted:            return "VM started (scheduled)"
        case .vmStartFailed:        return "VM start failed (scheduled)"
        }
    }

    var systemImage: String {
        switch self {
        case .baseVMBuildSucceeded: return "checkmark.circle"
        case .baseVMBuildFailed:    return "xmark.circle"
        case .baseVMBuildStarted:   return "hammer"
        case .ipswDownloaded:       return "arrow.down.circle"
        case .imagePullCompleted:   return "arrow.down.to.line"
        case .imagePushCompleted:   return "arrow.up.to.line"
        case .vmStopped:            return "stop.circle"
        case .vmStarted:            return "play.circle"
        case .vmStartFailed:        return "exclamationmark.circle"
        }
    }

    /// Returns the AppStorage key for the given service prefix (system/pushover/slack/teams).
    func storageKey(for service: String) -> String {
        "notif.\(service).\(rawValue)"
    }
}

// MARK: - NotificationPrefsTab

struct NotificationPrefsTab: View {
    @Environment(AppTheme.self) private var theme

    // Credential input state
    @State private var pushoverToken  = ""
    @State private var pushoverUser   = ""
    @State private var slackWebhook   = ""
    @State private var teamsWebhook   = ""

    // Per-service test result
    @State private var systemTestResult:   TestResult? = nil
    @State private var pushoverTestResult: TestResult? = nil
    @State private var slackTestResult:    TestResult? = nil
    @State private var teamsTestResult:    TestResult? = nil

    @State private var isTestingSystem   = false
    @State private var isTestingPushover = false
    @State private var isTestingSlack    = false
    @State private var isTestingTeams    = false

    // Webhook state
    @State private var webhooks: [WebhookNotification] = []
    @State private var webhookSheetMode: WebhookSheetMode? = nil
    @State private var webhookTestResults: [UUID: TestResult] = [:]
    @State private var testingWebhookIDs: Set<UUID> = []

    // Live OS authorization state
    @State private var osAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var osAlertSetting: UNNotificationSetting = .notSupported
    @State private var osSoundSetting: UNNotificationSetting = .notSupported
    @State private var osBadgeSetting: UNNotificationSetting = .notSupported

    private var hasPushoverCredentials: Bool {
        NotificationService.shared.pushoverAppToken?.isEmpty == false &&
        NotificationService.shared.pushoverUserKey?.isEmpty  == false
    }
    private var hasSlackCredentials: Bool {
        NotificationService.shared.slackWebhookURL?.isEmpty == false
    }
    private var hasTeamsCredentials: Bool {
        NotificationService.shared.teamsWebhookURL?.isEmpty == false
    }

    var body: some View {
        @Bindable var theme = theme
        return Form {
            systemSection
            pushoverSection
            slackSection
            teamsSection
            webhooksSection
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .task {
            await refreshOSStatus()
            webhooks = AppDatabase.shared.readOrDefault(.webhookNotifications, default: [])
        }
        .sheet(item: $webhookSheetMode) { mode in
            switch mode {
            case .add:
                WebhookEditSheet(existing: nil) { saved in addOrUpdateWebhook(saved) }
            case .edit(let wh):
                WebhookEditSheet(existing: wh) { updated in addOrUpdateWebhook(updated) }
            }
        }
    }

    // MARK: - System section

    private var systemSection: some View {
        @Bindable var theme = theme
        return Section {
            Toggle(isOn: $theme.systemNotificationsEnabled) {
                Label("System notifications", systemImage: "bell.circle")
            }
            .help("Delivers macOS native banners and alerts for the events you select below. Requires notification permission in System Settings.")

            if theme.systemNotificationsEnabled {
                // OS authorization status row
                LabeledContent("Permission") {
                    HStack(spacing: 6) {
                        osAuthBadge
                        if osAuthStatus == .denied || osAuthStatus == .notDetermined {
                            Button("Open System Settings") { openNotificationSettings() }
                                .buttonStyle(.link).controlSize(.small)
                        }
                    }
                }

                // Granular delivery settings (read from OS)
                if osAuthStatus == .authorized || osAuthStatus == .provisional {
                    LabeledContent("Banners / Alerts") {
                        settingBadge(osAlertSetting)
                    }
                    LabeledContent("Sound") {
                        HStack(spacing: 8) {
                            settingBadge(osSoundSetting)
                            // User can suppress sound in Oven even if OS allows it
                            if osSoundSetting == .enabled {
                                Toggle("Play sound", isOn: $theme.systemNotifSoundEnabled)
                                    .toggleStyle(.checkbox).controlSize(.small)
                            }
                        }
                    }
                    LabeledContent("Badge") {
                        settingBadge(osBadgeSetting)
                    }
                }

                eventToggles(service: "system", bindings: systemEventBindings)

                HStack {
                    Button("Test") { Task { await testSystem() } }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(isTestingSystem || osAuthStatus == .denied)
                    if isTestingSystem { ProgressView().controlSize(.small) }
                }
                if let r = systemTestResult { testResultLabel(r) }
            }
        } header: {
            Text("System notifications")
        } footer: {
            if theme.systemNotificationsEnabled && (osAuthStatus == .denied) {
                Label("Notifications are denied. Enable them in System Settings → Notifications → Oven.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Pushover section

    private var pushoverSection: some View {
        @Bindable var theme = theme
        return Section {
            Toggle(isOn: $theme.pushoverEnabled) {
                Label("Pushover notifications", systemImage: "bell.badge")
            }
            .help("Send push notifications to your iPhone or Android device via the Pushover service. Requires a Pushover account and the Pushover app.")
            if theme.pushoverEnabled {
                credentialRow(label: "App token", text: $pushoverToken,
                              isSaved: hasPushoverCredentials,
                              prompt: hasPushoverCredentials ? "Saved" : "Required")
                credentialRow(label: "User key", text: $pushoverUser,
                              isSaved: hasPushoverCredentials,
                              prompt: hasPushoverCredentials ? "Saved" : "Required")

                eventToggles(service: "pushover", bindings: pushoverEventBindings)

                HStack {
                    Button(hasPushoverCredentials ? "Update credentials" : "Save credentials") {
                        savePushoverCredentials()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button("Test") { Task { await testPushover() } }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(isTestingPushover || !hasPushoverCredentials)
                    if isTestingPushover { ProgressView().controlSize(.small) }
                }
                if let r = pushoverTestResult { testResultLabel(r) }
            }
        } header: { Text("Pushover") }
    }

    // MARK: - Slack section

    private var slackSection: some View {
        @Bindable var theme = theme
        return Section {
            Toggle(isOn: $theme.slackEnabled) {
                Label("Slack notifications", systemImage: "message.badge")
            }
            .help("Post messages to a Slack channel via an Incoming Webhook URL. Create a webhook at api.slack.com/apps.")
            if theme.slackEnabled {
                credentialRow(label: "Webhook URL", text: $slackWebhook,
                              isSaved: hasSlackCredentials,
                              prompt: hasSlackCredentials ? "Saved" : "https://hooks.slack.com/services/…")

                eventToggles(service: "slack", bindings: slackEventBindings)

                HStack {
                    Button(hasSlackCredentials ? "Update webhook" : "Save webhook") {
                        saveSlackCredentials()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button("Test") { Task { await testSlack() } }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(isTestingSlack || !hasSlackCredentials)
                    if isTestingSlack { ProgressView().controlSize(.small) }
                }
                if let r = slackTestResult { testResultLabel(r) }
            }
        } header: { Text("Slack") }
    }

    // MARK: - Teams section

    private var teamsSection: some View {
        @Bindable var theme = theme
        return Section {
            Toggle(isOn: $theme.teamsEnabled) {
                Label("Microsoft Teams notifications", systemImage: "person.3.sequence")
            }
            .help("Post messages to a Microsoft Teams channel via an Incoming Webhook URL. Create a webhook in Teams → Channel → Connectors.")
            if theme.teamsEnabled {
                credentialRow(label: "Webhook URL", text: $teamsWebhook,
                              isSaved: hasTeamsCredentials,
                              prompt: hasTeamsCredentials ? "Saved" : "https://…webhook.office.com/…")

                eventToggles(service: "teams", bindings: teamsEventBindings)

                HStack {
                    Button(hasTeamsCredentials ? "Update webhook" : "Save webhook") {
                        saveTeamsCredentials()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    Button("Test") { Task { await testTeams() } }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(isTestingTeams || !hasTeamsCredentials)
                    if isTestingTeams { ProgressView().controlSize(.small) }
                }
                if let r = teamsTestResult { testResultLabel(r) }
            }
        } header: { Text("Microsoft Teams") }
          footer: { Text("Credentials are stored securely in Keychain.") }
    }

    // MARK: - Custom Webhooks section

    private var webhooksSection: some View {
        Section {
            if webhooks.isEmpty {
                Text("No webhooks configured")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(webhooks) { wh in
                    webhookRow(wh)
                }
            }
            Button {
                webhookSheetMode = .add
            } label: {
                Label("Add Webhook", systemImage: "plus")
            }
        } header: {
            Text("Custom Webhooks")
        } footer: {
            Text("POST requests to custom endpoints on VM events. Auth credentials are stored in Keychain.")
        }
    }

    @ViewBuilder
    private func webhookRow(_ wh: WebhookNotification) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(wh.displayName.isEmpty ? "Unnamed" : wh.displayName)
                    .fontWeight(.medium)
                Text(wh.url.isEmpty ? "No URL configured" : wh.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let result = webhookTestResults[wh.id] {
                testResultLabel(result)
            }
            if testingWebhookIDs.contains(wh.id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Test") {
                    Task { await testWebhookFromUI(wh) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(wh.url.isEmpty)
            }
            Toggle("", isOn: Binding(
                get: { wh.isEnabled },
                set: { enabled in toggleWebhook(wh.id, enabled: enabled) }
            ))
            .labelsHidden()
        }
        .contextMenu {
            Button("Edit…") { webhookSheetMode = .edit(wh) }
            Divider()
            Button("Delete", role: .destructive) { deleteWebhook(wh) }
        }
    }

    private func addOrUpdateWebhook(_ webhook: WebhookNotification) {
        if let idx = webhooks.firstIndex(where: { $0.id == webhook.id }) {
            webhooks[idx] = webhook
        } else {
            webhooks.append(webhook)
        }
        AppDatabase.shared.writeSilently(webhooks, to: .webhookNotifications)
    }

    private func deleteWebhook(_ webhook: WebhookNotification) {
        webhooks.removeAll { $0.id == webhook.id }
        AppDatabase.shared.writeSilently(webhooks, to: .webhookNotifications)
        NotificationService.shared.deleteWebhookSecrets(for: webhook.id)
        webhookTestResults.removeValue(forKey: webhook.id)
    }

    private func toggleWebhook(_ id: UUID, enabled: Bool) {
        guard let idx = webhooks.firstIndex(where: { $0.id == id }) else { return }
        webhooks[idx].isEnabled = enabled
        AppDatabase.shared.writeSilently(webhooks, to: .webhookNotifications)
    }

    private func testWebhookFromUI(_ webhook: WebhookNotification) async {
        testingWebhookIDs.insert(webhook.id)
        webhookTestResults.removeValue(forKey: webhook.id)
        let result = await NotificationService.shared.testWebhook(webhook)
        switch result {
        case .success:        webhookTestResults[webhook.id] = .success("Webhook sent")
        case .failure(let e): webhookTestResults[webhook.id] = .failure(e.localizedDescription)
        }
        testingWebhookIDs.remove(webhook.id)
    }

    // MARK: - Shared sub-views

    @ViewBuilder
    private func credentialRow(label: String, text: Binding<String>, isSaved: Bool, prompt: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                if isSaved {
                    Image(systemName: "lock.fill").foregroundStyle(.green).help("Saved in Keychain")
                } else {
                    Image(systemName: "lock.slash").foregroundStyle(.orange).help("Not yet saved")
                }
                SecureField("", text: text, prompt: Text(prompt).foregroundStyle(.secondary))
            }
        }
    }

    @ViewBuilder
    private func eventToggles(service: String, bindings: [(NotificationEvent, Binding<Bool>)]) -> some View {
        DisclosureGroup("Events") {
            ForEach(bindings, id: \.0.id) { event, binding in
                Toggle(isOn: binding) {
                    Label(event.label, systemImage: event.systemImage)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    @ViewBuilder
    private func testResultLabel(_ result: TestResult) -> some View {
        Label(result.message, systemImage: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(result.isSuccess ? .green : .red)
            .font(.callout)
    }

    // MARK: - OS status badge helpers

    @ViewBuilder
    private var osAuthBadge: some View {
        switch osAuthStatus {
        case .authorized:
            Label("Authorized", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        case .provisional:
            Label("Provisional", systemImage: "seal").foregroundStyle(.yellow)
        case .denied:
            Label("Denied", systemImage: "xmark.seal.fill").foregroundStyle(.red)
        case .notDetermined:
            Label("Not determined", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        case .ephemeral:
            Label("Ephemeral", systemImage: "clock").foregroundStyle(.orange)
        @unknown default:
            Label("Unknown", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func settingBadge(_ setting: UNNotificationSetting) -> some View {
        switch setting {
        case .enabled:
            Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .disabled:
            Label("Disabled", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .notSupported:
            Label("Not supported", systemImage: "minus.circle").foregroundStyle(.secondary)
        @unknown default:
            Label("Unknown", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    // MARK: - Per-service event bindings

    private var systemEventBindings: [(NotificationEvent, Binding<Bool>)] {
        @Bindable var theme = theme
        return [
            (.baseVMBuildSucceeded, $theme.systemNotifBaseVMBuildSucceeded),
            (.baseVMBuildFailed,    $theme.systemNotifBaseVMBuildFailed),
            (.ipswDownloaded,       $theme.systemNotifIPSWDownloaded),
            (.imagePullCompleted,   $theme.systemNotifImagePullCompleted),
            (.imagePushCompleted,   $theme.systemNotifImagePushCompleted),
            (.vmStopped,            $theme.systemNotifVMStopped),
            (.vmStarted,            $theme.systemNotifVMStarted),
            (.vmStartFailed,        $theme.systemNotifVMStartFailed),
        ]
    }

    private var pushoverEventBindings: [(NotificationEvent, Binding<Bool>)] {
        @Bindable var theme = theme
        return [
            (.baseVMBuildSucceeded, $theme.pushoverNotifBaseVMBuildSucceeded),
            (.baseVMBuildFailed,    $theme.pushoverNotifBaseVMBuildFailed),
            (.ipswDownloaded,       $theme.pushoverNotifIPSWDownloaded),
            (.imagePullCompleted,   $theme.pushoverNotifImagePullCompleted),
            (.imagePushCompleted,   $theme.pushoverNotifImagePushCompleted),
            (.vmStopped,            $theme.pushoverNotifVMStopped),
            (.vmStarted,            $theme.pushoverNotifVMStarted),
            (.vmStartFailed,        $theme.pushoverNotifVMStartFailed),
        ]
    }

    private var slackEventBindings: [(NotificationEvent, Binding<Bool>)] {
        @Bindable var theme = theme
        return [
            (.baseVMBuildSucceeded, $theme.slackNotifBaseVMBuildSucceeded),
            (.baseVMBuildFailed,    $theme.slackNotifBaseVMBuildFailed),
            (.ipswDownloaded,       $theme.slackNotifIPSWDownloaded),
            (.imagePullCompleted,   $theme.slackNotifImagePullCompleted),
            (.imagePushCompleted,   $theme.slackNotifImagePushCompleted),
            (.vmStopped,            $theme.slackNotifVMStopped),
            (.vmStarted,            $theme.slackNotifVMStarted),
            (.vmStartFailed,        $theme.slackNotifVMStartFailed),
        ]
    }

    private var teamsEventBindings: [(NotificationEvent, Binding<Bool>)] {
        @Bindable var theme = theme
        return [
            (.baseVMBuildSucceeded, $theme.teamsNotifBaseVMBuildSucceeded),
            (.baseVMBuildFailed,    $theme.teamsNotifBaseVMBuildFailed),
            (.ipswDownloaded,       $theme.teamsNotifIPSWDownloaded),
            (.imagePullCompleted,   $theme.teamsNotifImagePullCompleted),
            (.imagePushCompleted,   $theme.teamsNotifImagePushCompleted),
            (.vmStopped,            $theme.teamsNotifVMStopped),
            (.vmStarted,            $theme.teamsNotifVMStarted),
            (.vmStartFailed,        $theme.teamsNotifVMStartFailed),
        ]
    }

    // MARK: - OS status refresh

    private func refreshOSStatus() async {
        let settings = await NotificationService.shared.currentNotificationSettings()
        osAuthStatus   = settings.authorizationStatus
        osAlertSetting = settings.alertSetting
        osSoundSetting = settings.soundSetting
        osBadgeSetting = settings.badgeSetting
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Save credentials

    private func savePushoverCredentials() {
        if !pushoverToken.isEmpty { NotificationService.shared.pushoverAppToken = pushoverToken }
        if !pushoverUser.isEmpty  { NotificationService.shared.pushoverUserKey  = pushoverUser }
        pushoverToken = ""; pushoverUser = ""
    }
    private func saveSlackCredentials() {
        if !slackWebhook.isEmpty { NotificationService.shared.slackWebhookURL = slackWebhook }
        slackWebhook = ""
    }
    private func saveTeamsCredentials() {
        if !teamsWebhook.isEmpty { NotificationService.shared.teamsWebhookURL = teamsWebhook }
        teamsWebhook = ""
    }

    // MARK: - Test actions

    private func testSystem() async {
        isTestingSystem = true; systemTestResult = nil
        await refreshOSStatus()
        let result = await NotificationService.shared.testSystemNotifications()
        switch result {
        case .success:        systemTestResult = .success("System notification sent")
        case .failure(let e): systemTestResult = .failure(e.localizedDescription)
        }
        isTestingSystem = false
    }
    private func testPushover() async {
        isTestingPushover = true; pushoverTestResult = nil
        let result = await NotificationService.shared.testPushover()
        switch result {
        case .success:        pushoverTestResult = .success("Pushover notification sent")
        case .failure(let e): pushoverTestResult = .failure(e.localizedDescription)
        }
        isTestingPushover = false
    }
    private func testSlack() async {
        isTestingSlack = true; slackTestResult = nil
        let result = await NotificationService.shared.testSlack()
        switch result {
        case .success:        slackTestResult = .success("Slack notification sent")
        case .failure(let e): slackTestResult = .failure(e.localizedDescription)
        }
        isTestingSlack = false
    }
    private func testTeams() async {
        isTestingTeams = true; teamsTestResult = nil
        let result = await NotificationService.shared.testTeams()
        switch result {
        case .success:        teamsTestResult = .success("Teams notification sent")
        case .failure(let e): teamsTestResult = .failure(e.localizedDescription)
        }
        isTestingTeams = false
    }
}

// MARK: - WebhookSheetMode

private enum WebhookSheetMode: Identifiable {
    case add
    case edit(WebhookNotification)

    var id: String {
        switch self {
        case .add:           return "add"
        case .edit(let wh):  return wh.id.uuidString
        }
    }
}

// MARK: - TestResult

private enum TestResult {
    case success(String)
    case failure(String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    var message: String {
        switch self {
        case .success(let m): return "✓ \(m)"
        case .failure(let m): return "✗ \(m)"
        }
    }
}
