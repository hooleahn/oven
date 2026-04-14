import SwiftUI
import UserNotifications

// MARK: - NotificationEvent

/// All notification events the user can subscribe to per-service.
enum NotificationEvent: String, CaseIterable, Identifiable {
    case baseVMBuildSucceeded = "baseVMBuildSucceeded"
    case baseVMBuildFailed    = "baseVMBuildFailed"
    case ipswDownloaded       = "ipswDownloaded"
    case imagePullCompleted   = "imagePullCompleted"
    case imagePushCompleted   = "imagePushCompleted"
    case vmStopped            = "vmStopped"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .baseVMBuildSucceeded: return "Base VM build succeeded"
        case .baseVMBuildFailed:    return "Base VM build failed"
        case .ipswDownloaded:       return "IPSW downloaded"
        case .imagePullCompleted:   return "Registry pull completed"
        case .imagePushCompleted:   return "Registry push completed"
        case .vmStopped:            return "VM stopped"
        }
    }

    var systemImage: String {
        switch self {
        case .baseVMBuildSucceeded: return "checkmark.circle"
        case .baseVMBuildFailed:    return "xmark.circle"
        case .ipswDownloaded:       return "arrow.down.circle"
        case .imagePullCompleted:   return "arrow.down.to.line"
        case .imagePushCompleted:   return "arrow.up.to.line"
        case .vmStopped:            return "stop.circle"
        }
    }

    /// Returns the AppStorage key for the given service prefix (system/pushover/slack/teams).
    func storageKey(for service: String) -> String {
        "notif.\(service).\(rawValue)"
    }
}

// MARK: - NotificationPrefsTab

struct NotificationPrefsTab: View {
    @EnvironmentObject var theme: AppTheme

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
        Form {
            systemSection
            pushoverSection
            slackSection
            teamsSection
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
        .task { await refreshOSStatus() }
    }

    // MARK: - System section

    private var systemSection: some View {
        Section {
            Toggle(isOn: $theme.systemNotificationsEnabled) {
                Label("System notifications", systemImage: "bell.circle")
            }

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
        Section {
            Toggle(isOn: $theme.pushoverEnabled) {
                Label("Pushover notifications", systemImage: "bell.badge")
            }
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
        Section {
            Toggle(isOn: $theme.slackEnabled) {
                Label("Slack notifications", systemImage: "message.badge")
            }
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
        Section {
            Toggle(isOn: $theme.teamsEnabled) {
                Label("Microsoft Teams notifications", systemImage: "person.3.sequence")
            }
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
                SecureField("", text: text, prompt: Text(prompt).foregroundColor(.secondary))
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
        [
            (.baseVMBuildSucceeded, $theme.systemNotifBaseVMBuildSucceeded),
            (.baseVMBuildFailed,    $theme.systemNotifBaseVMBuildFailed),
            (.ipswDownloaded,       $theme.systemNotifIPSWDownloaded),
            (.imagePullCompleted,   $theme.systemNotifImagePullCompleted),
            (.imagePushCompleted,   $theme.systemNotifImagePushCompleted),
            (.vmStopped,            $theme.systemNotifVMStopped),
        ]
    }

    private var pushoverEventBindings: [(NotificationEvent, Binding<Bool>)] {
        [
            (.baseVMBuildSucceeded, $theme.pushoverNotifBaseVMBuildSucceeded),
            (.baseVMBuildFailed,    $theme.pushoverNotifBaseVMBuildFailed),
            (.ipswDownloaded,       $theme.pushoverNotifIPSWDownloaded),
            (.imagePullCompleted,   $theme.pushoverNotifImagePullCompleted),
            (.imagePushCompleted,   $theme.pushoverNotifImagePushCompleted),
            (.vmStopped,            $theme.pushoverNotifVMStopped),
        ]
    }

    private var slackEventBindings: [(NotificationEvent, Binding<Bool>)] {
        [
            (.baseVMBuildSucceeded, $theme.slackNotifBaseVMBuildSucceeded),
            (.baseVMBuildFailed,    $theme.slackNotifBaseVMBuildFailed),
            (.ipswDownloaded,       $theme.slackNotifIPSWDownloaded),
            (.imagePullCompleted,   $theme.slackNotifImagePullCompleted),
            (.imagePushCompleted,   $theme.slackNotifImagePushCompleted),
            (.vmStopped,            $theme.slackNotifVMStopped),
        ]
    }

    private var teamsEventBindings: [(NotificationEvent, Binding<Bool>)] {
        [
            (.baseVMBuildSucceeded, $theme.teamsNotifBaseVMBuildSucceeded),
            (.baseVMBuildFailed,    $theme.teamsNotifBaseVMBuildFailed),
            (.ipswDownloaded,       $theme.teamsNotifIPSWDownloaded),
            (.imagePullCompleted,   $theme.teamsNotifImagePullCompleted),
            (.imagePushCompleted,   $theme.teamsNotifImagePushCompleted),
            (.vmStopped,            $theme.teamsNotifVMStopped),
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
