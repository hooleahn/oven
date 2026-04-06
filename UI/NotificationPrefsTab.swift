import SwiftUI
import UserNotifications

struct NotificationPrefsTab: View {
    @EnvironmentObject var theme: AppTheme
    @State private var pushoverToken = ""
    @State private var pushoverUser  = ""
    @State private var slackWebhook  = ""
    @State private var notifTestResult: String? = nil
    @State private var isTestingNotif = false

    private var hasPushoverCredentials: Bool {
        (NotificationService.shared.pushoverAppToken?.isEmpty == false) &&
        (NotificationService.shared.pushoverUserKey?.isEmpty  == false)
    }
    private var hasSlackCredentials: Bool {
        NotificationService.shared.slackWebhookURL?.isEmpty == false
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $theme.systemNotificationsEnabled) {
                    Label("System notifications", systemImage: "bell.circle")
                }
                if theme.systemNotificationsEnabled{
                    HStack {
                        Button("Test") { Task { await testSystemNotifications() } }
                            .buttonStyle(.bordered).controlSize(.small).disabled(isTestingNotif)
                    }

                }
            } header: { Text("System notifications") }
            Section {
                Toggle(isOn: $theme.pushoverEnabled) {
                    Label("Pushover notifications", systemImage: "bell.badge")
                }
                if theme.pushoverEnabled {
                    LabeledContent("App token") {
                        HStack(spacing: 6) {
                            if hasPushoverCredentials {
                                Image(systemName: "lock.fill").foregroundStyle(.green).help("Saved in Keychain")
                            }
                            SecureField("", text: $pushoverToken,
                                        prompt: Text(hasPushoverCredentials ? "Saved" : "Required").foregroundColor(.secondary))
                        }
                    }
                    LabeledContent("User key") {
                        HStack(spacing: 6) {
                            if hasPushoverCredentials {
                                Image(systemName: "lock.fill").foregroundStyle(.green).help("Saved in Keychain")
                            }
                            SecureField("", text: $pushoverUser,
                                        prompt: Text(hasPushoverCredentials ? "Saved" : "Required").foregroundColor(.secondary))
                        }
                    }
                    HStack {
                        Button(hasPushoverCredentials ? "Update credentials" : "Save credentials") { savePushoverCredentials() }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button("Test") { Task { await testPushover() } }
                            .buttonStyle(.bordered).controlSize(.small).disabled(isTestingNotif)
                    }
                }
            } header: { Text("Pushover") }

            Section {
                Toggle(isOn: $theme.slackEnabled) {
                    Label("Slack notifications", systemImage: "message.badge")
                }
                if theme.slackEnabled {
                    LabeledContent("Webhook URL") {
                        HStack(spacing: 6) {
                            if hasSlackCredentials {
                                Image(systemName: "lock.fill").foregroundStyle(.green).help("Saved in Keychain")
                            }
                            SecureField("", text: $slackWebhook,
                                        prompt: Text(hasSlackCredentials ? "Saved" : "https://hooks.slack.com/services/…").foregroundColor(.secondary))
                        }
                    }
                    HStack {
                        Button(hasSlackCredentials ? "Update webhook" : "Save webhook") { saveSlackCredentials() }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button("Test") { Task { await testSlack() } }
                            .buttonStyle(.bordered).controlSize(.small).disabled(isTestingNotif)
                    }
                }
            } header: { Text("Slack") }
              footer: { Text("Notifications are sent when a Base VM build starts, completes, or fails. Credentials are stored in Keychain.") }

            if let result = notifTestResult {
                Section {
                    Label(result, systemImage: result.hasPrefix("✓") ? "checkmark.circle" : "xmark.circle")
                        .foregroundStyle(result.hasPrefix("✓") ? .green : .red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
    }

    private func savePushoverCredentials() {
        if !pushoverToken.isEmpty { NotificationService.shared.pushoverAppToken = pushoverToken }
        if !pushoverUser.isEmpty  { NotificationService.shared.pushoverUserKey  = pushoverUser }
        pushoverToken = ""; pushoverUser = ""
    }
    private func saveSlackCredentials() {
        if !slackWebhook.isEmpty { NotificationService.shared.slackWebhookURL = slackWebhook }
        slackWebhook = ""
    }
    private func testSystemNotifications() async {
        isTestingNotif = true; notifTestResult = nil
        let result = await NotificationService.shared.testSystemNotifications()
        switch result {
        case .success:        notifTestResult = "✓ System notification sent"
        case .failure(let e): notifTestResult = "✗ \(e.localizedDescription)"
        }
        isTestingNotif = false
    }
    private func testPushover() async {
        isTestingNotif = true; notifTestResult = nil
        let result = await NotificationService.shared.testPushover()
        switch result {
        case .success:        notifTestResult = "✓ Pushover notification sent"
        case .failure(let e): notifTestResult = "✗ \(e.localizedDescription)"
        }
        isTestingNotif = false
    }
    private func testSlack() async {
        isTestingNotif = true; notifTestResult = nil
        let result = await NotificationService.shared.testSlack()
        switch result {
        case .success:        notifTestResult = "✓ Slack notification sent"
        case .failure(let e): notifTestResult = "✗ \(e.localizedDescription)"
        }
        isTestingNotif = false
    }
}
