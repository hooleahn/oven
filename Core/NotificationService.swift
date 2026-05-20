import Foundation
import UserNotifications

// MARK: - NotificationService
// Sends build status notifications to Pushover and/or Slack.
// Credentials stored in Keychain; only URLs/keys are in UserDefaults.

@MainActor
final class NotificationService {

    static let shared = NotificationService()

    private init() {
        // Register fallback defaults for scheduled VM event toggles.
        // UserDefaults.standard.bool(forKey:) returns false for any key that has
        // never been written — the @AppStorage default in AppTheme only applies
        // when the property wrapper reads the value. Registering here ensures
        // these events fire on a fresh install without needing a prefs visit.
        UserDefaults.standard.register(defaults: [
            "notif.system.vmStarted":      true,
            "notif.system.vmStartFailed":  true,
            "notif.pushover.vmStarted":    true,
            "notif.pushover.vmStartFailed": true,
        ])
    }

    // MARK: - Keychain keys

    private let pushoverTokenKey        = "notification.pushover.appToken"
    private let pushoverUserKeychainKey = "notification.pushover.userKey"
    private let slackWebhookKey         = "notification.slack.webhookURL"
    private let teamsWebhookKey         = "notification.teams.webhookURL"

    // MARK: - Credential storage (Keychain)

    var pushoverAppToken: String? {
        get { KeychainService.retrieve(key: pushoverTokenKey) }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainService.store(key: pushoverTokenKey, value: v)
            } else {
                KeychainService.delete(key: pushoverTokenKey)
            }
        }
    }

    var pushoverUserKey: String? {
        get { KeychainService.retrieve(key: pushoverUserKeychainKey) }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainService.store(key: pushoverUserKeychainKey, value: v)
            } else {
                KeychainService.delete(key: pushoverUserKeychainKey)
            }
        }
    }

    var slackWebhookURL: String? {
        get { KeychainService.retrieve(key: slackWebhookKey) }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainService.store(key: slackWebhookKey, value: v)
            } else {
                KeychainService.delete(key: slackWebhookKey)
            }
        }
    }

    var teamsWebhookURL: String? {
        get { KeychainService.retrieve(key: teamsWebhookKey) }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainService.store(key: teamsWebhookKey, value: v)
            } else {
                KeychainService.delete(key: teamsWebhookKey)
            }
        }
    }

    // MARK: - OS authorization state

    /// Returns the current UNAuthorizationStatus without prompting.
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Returns all granular UNNotificationSetting values for display in prefs.
    func currentNotificationSettings() async -> UNNotificationSettings {
        await UNUserNotificationCenter.current().notificationSettings()
    }

    // MARK: - Send build notification

    func notifyBuildComplete(vmName: String, success: Bool, detail: String? = nil) async {
        let pushEnabled   = UserDefaults.standard.bool(forKey: "pushoverEnabled")
        let slackEnabled  = UserDefaults.standard.bool(forKey: "slackEnabled")
        let teamsEnabled  = UserDefaults.standard.bool(forKey: "teamsEnabled")
        let systemEnabled = UserDefaults.standard.bool(forKey: "systemNotificationsEnabled")
        let webhookEvent = success ? "baseVMBuildSucceeded" : "baseVMBuildFailed"
        await sendWebhooks(eventType: webhookEvent, vmName: vmName)
        guard pushEnabled || slackEnabled || teamsEnabled || systemEnabled else { return }

        let title   = success ? "✅ Oven: Build Complete" : "❌ Oven: Build Failed"
        let message = success
            ? "Base VM '\(vmName)' was built successfully."
            : "Base VM '\(vmName)' failed to build.\(detail.map { " \($0)" } ?? "")"

        let eventKey = success ? "notif.%@.baseVMBuildSucceeded" : "notif.%@.baseVMBuildFailed"

        await withTaskGroup(of: Void.self) { group in
            if pushEnabled && UserDefaults.standard.bool(forKey: String(format: eventKey, "pushover")) {
                group.addTask { await self.sendPushover(title: title, message: message) }
            }
            if slackEnabled && UserDefaults.standard.bool(forKey: String(format: eventKey, "slack")) {
                group.addTask { await self.sendSlack(title: title, message: message, success: success) }
            }
            if teamsEnabled && UserDefaults.standard.bool(forKey: String(format: eventKey, "teams")) {
                group.addTask { await self.sendTeams(title: title, message: message, success: success) }
            }
            if systemEnabled && UserDefaults.standard.bool(forKey: String(format: eventKey, "system")) {
                group.addTask { await self.sendSystemNotification(title: title, message: message, success: success) }
            }
        }
    }

    func notifyVMStopped(vmName: String) async {
        AppLogger.shared.log("VM stopped: \(vmName)", source: "NotificationService")

        let pushEnabled   = UserDefaults.standard.bool(forKey: "pushoverEnabled")
        let slackEnabled  = UserDefaults.standard.bool(forKey: "slackEnabled")
        let teamsEnabled  = UserDefaults.standard.bool(forKey: "teamsEnabled")
        let systemEnabled = UserDefaults.standard.bool(forKey: "systemNotificationsEnabled")
        await sendWebhooks(eventType: "vmStopped", vmName: vmName)
        guard pushEnabled || slackEnabled || teamsEnabled || systemEnabled else { return }

        let title   = "🛑 Oven: VM Stopped"
        let message = "VM '\(vmName)' has stopped."
        let eventKey = "notif.%@.vmStopped"

        await withTaskGroup(of: Void.self) { group in
            if pushEnabled   && UserDefaults.standard.bool(forKey: String(format: eventKey, "pushover")) {
                group.addTask { await self.sendPushover(title: title, message: message) }
            }
            if slackEnabled  && UserDefaults.standard.bool(forKey: String(format: eventKey, "slack")) {
                group.addTask { await self.sendSlack(title: title, message: message, success: nil) }
            }
            if teamsEnabled  && UserDefaults.standard.bool(forKey: String(format: eventKey, "teams")) {
                group.addTask { await self.sendTeams(title: title, message: message, success: nil) }
            }
            if systemEnabled && UserDefaults.standard.bool(forKey: String(format: eventKey, "system")) {
                group.addTask { await self.sendSystemNotification(title: title, message: message, success: nil) }
            }
        }
    }

    func notifyVMStarted(vmName: String) async {
        AppLogger.shared.success("VM started on schedule: \(vmName)", source: "NotificationService")

        let pushEnabled   = UserDefaults.standard.bool(forKey: "pushoverEnabled")
        let slackEnabled  = UserDefaults.standard.bool(forKey: "slackEnabled")
        let teamsEnabled  = UserDefaults.standard.bool(forKey: "teamsEnabled")
        let systemEnabled = UserDefaults.standard.bool(forKey: "systemNotificationsEnabled")
        await sendWebhooks(eventType: "vmStarted", vmName: vmName)
        guard pushEnabled || slackEnabled || teamsEnabled || systemEnabled else { return }

        let title   = "▶️ Oven: VM Started"
        let message = "VM '\(vmName)' started on schedule."
        let eventKey = "notif.%@.vmStarted"

        await withTaskGroup(of: Void.self) { group in
            if pushEnabled   && UserDefaults.standard.bool(forKey: String(format: eventKey, "pushover")) {
                group.addTask { await self.sendPushover(title: title, message: message) }
            }
            if slackEnabled  && UserDefaults.standard.bool(forKey: String(format: eventKey, "slack")) {
                group.addTask { await self.sendSlack(title: title, message: message, success: true) }
            }
            if teamsEnabled  && UserDefaults.standard.bool(forKey: String(format: eventKey, "teams")) {
                group.addTask { await self.sendTeams(title: title, message: message, success: true) }
            }
            if systemEnabled && UserDefaults.standard.bool(forKey: String(format: eventKey, "system")) {
                group.addTask { await self.sendSystemNotification(title: title, message: message, success: true) }
            }
        }
    }

    func notifyVMStartFailed(vmName: String, reason: String) async {
        AppLogger.shared.warning("VM start failed (scheduled): \(vmName) — \(reason)", source: "NotificationService")

        let pushEnabled   = UserDefaults.standard.bool(forKey: "pushoverEnabled")
        let slackEnabled  = UserDefaults.standard.bool(forKey: "slackEnabled")
        let teamsEnabled  = UserDefaults.standard.bool(forKey: "teamsEnabled")
        let systemEnabled = UserDefaults.standard.bool(forKey: "systemNotificationsEnabled")
        await sendWebhooks(eventType: "vmStartFailed", vmName: vmName)
        guard pushEnabled || slackEnabled || teamsEnabled || systemEnabled else { return }

        let title   = "⚠️ Oven: VM Start Failed"
        let message = "VM '\(vmName)' failed to start. \(reason)"
        let eventKey = "notif.%@.vmStartFailed"

        await withTaskGroup(of: Void.self) { group in
            if pushEnabled   && UserDefaults.standard.bool(forKey: String(format: eventKey, "pushover")) {
                group.addTask { await self.sendPushover(title: title, message: message) }
            }
            if slackEnabled  && UserDefaults.standard.bool(forKey: String(format: eventKey, "slack")) {
                group.addTask { await self.sendSlack(title: title, message: message, success: false) }
            }
            if teamsEnabled  && UserDefaults.standard.bool(forKey: String(format: eventKey, "teams")) {
                group.addTask { await self.sendTeams(title: title, message: message, success: false) }
            }
            if systemEnabled && UserDefaults.standard.bool(forKey: String(format: eventKey, "system")) {
                group.addTask { await self.sendSystemNotification(title: title, message: message, success: false) }
            }
        }
    }

    func notifyBuildStarted(vmName: String) async {
        let pushEnabled   = UserDefaults.standard.bool(forKey: "pushoverEnabled")
        let slackEnabled  = UserDefaults.standard.bool(forKey: "slackEnabled")
        let teamsEnabled  = UserDefaults.standard.bool(forKey: "teamsEnabled")
        let systemEnabled = UserDefaults.standard.bool(forKey: "systemNotificationsEnabled")
        await sendWebhooks(eventType: "baseVMBuildStarted", vmName: vmName)
        guard pushEnabled || slackEnabled || teamsEnabled || systemEnabled else { return }

        let title   = "🔨 Oven: Build Started"
        let message = "Building base VM '\(vmName)'…"

        await withTaskGroup(of: Void.self) { group in
            if pushEnabled  { group.addTask { await self.sendPushover(title: title, message: message) } }
            if slackEnabled { group.addTask { await self.sendSlack(title: title, message: message, success: nil) } }
            if teamsEnabled { group.addTask { await self.sendTeams(title: title, message: message, success: nil) } }
            if systemEnabled { group.addTask { await self.sendSystemNotification(title: title, message: message, success: nil) } }
        }
    }

    // MARK: - Pushover

    private func sendPushover(title: String, message: String) async {
        guard let token = pushoverAppToken, !token.isEmpty,
              let user  = pushoverUserKey,  !user.isEmpty else {
            AppLogger.shared.warning("Pushover enabled but token/user key not configured", source: "NotificationService")
            return
        }

        let body: [String: String] = [
            "token":   token,
            "user":    user,
            "title":   title,
            "message": message,
            "sound":   "none",
        ]

        do {
            var request = URLRequest(url: URL(string: "https://api.pushover.net/1/messages.json")!)
            request.httpMethod  = "POST"
            request.httpBody    = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                AppLogger.shared.success("Pushover notification sent", source: "NotificationService")
            } else {
                AppLogger.shared.warning("Pushover returned HTTP \(status)", source: "NotificationService")
            }
        } catch {
            AppLogger.shared.error("Pushover failed: \(error.localizedDescription)", source: "NotificationService")
        }
    }

    // MARK: - Slack

    private func sendSlack(title: String, message: String, success: Bool?) async {
        guard let webhookURLString = slackWebhookURL, !webhookURLString.isEmpty,
              let webhookURL = URL(string: webhookURLString) else {
            AppLogger.shared.warning("Slack enabled but webhook URL not configured", source: "NotificationService")
            return
        }

        let color: String
        switch success {
        case true:  color = "#36a64f"
        case false: color = "#d32f2f"
        case nil:   color = "#f0a500"
        }

        let payload: [String: Any] = [
            "attachments": [[
                "color": color,
                "title": title,
                "text":  message,
                "footer": "Oven · macOS VM Manager",
                "ts":     Int(Date().timeIntervalSince1970),
            ]]
        ]

        do {
            var request = URLRequest(url: webhookURL)
            request.httpMethod = "POST"
            request.httpBody   = try JSONSerialization.data(withJSONObject: payload)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                AppLogger.shared.success("Slack notification sent", source: "NotificationService")
            } else {
                AppLogger.shared.warning("Slack returned HTTP \(status)", source: "NotificationService")
            }
        } catch {
            AppLogger.shared.error("Slack failed: \(error.localizedDescription)", source: "NotificationService")
        }
    }

    private func sendSystemNotification(title: String, message: String, success: Bool?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = message
        let soundEnabled = UserDefaults.standard.bool(forKey: "notif.system.soundEnabled")
        content.sound = soundEnabled ? .default : nil

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard (settings.authorizationStatus == .authorized) ||
                (settings.authorizationStatus == .provisional) else {
            do {
                let _ = try await requestAuthorizationForSystemNotifications()
            } catch {
                AppLogger.shared.error("System Notifications are disabled for Oven", source: "NotificationService")
            }
            return
        }

        if settings.alertSetting == .enabled {
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
                AppLogger.shared.success("System Notification sent", source: "NotificationService")
            } catch {
                AppLogger.shared.error("System Notification failed: \(error.localizedDescription)", source: "NotificationService")
            }
        } else {
            AppLogger.shared.error("System Notification failed — alerts disabled in System Settings", source: "NotificationService")
        }
    }

    func requestAuthorizationForSystemNotifications() async throws -> Bool {
        let notificationCenter = UNUserNotificationCenter.current()
        let authorizationOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
        do {
            let authorizationGranted = try await notificationCenter.requestAuthorization(options: authorizationOptions)
            return authorizationGranted
        } catch {
            throw error
        }
    }

    func checkCurrentAuthorizationSetting() async {
        let notificationCenter = UNUserNotificationCenter.current()
        let currentSettings = await notificationCenter.notificationSettings()
        switch currentSettings.authorizationStatus {
        case .authorized:
            AppLogger.shared.success("System notifications are enabled", source: "NotificationService")
        case .denied:
            AppLogger.shared.error("System notifications are disabled", source: "NotificationService")
        case .ephemeral:
            AppLogger.shared.warning("System notifications are enabled but temporary", source: "NotificationService")
        case .notDetermined:
            AppLogger.shared.log("System notifications are not determined", source: "NotificationService")
        case .provisional:
            AppLogger.shared.warning("System notifications are provisional", source: "NotificationService")
        @unknown default:
            AppLogger.shared.log("System notifications are not determined", source: "NotificationService")
        }
    }

    // MARK: - Webhook Keychain helpers

    func webhookPassword(for id: UUID) -> String? {
        KeychainService.retrieve(key: "webhook.\(id.uuidString).basicPassword")
    }

    func setWebhookPassword(_ value: String?, for id: UUID) {
        let key = "webhook.\(id.uuidString).basicPassword"
        if let v = value, !v.isEmpty { KeychainService.store(key: key, value: v) }
        else { KeychainService.delete(key: key) }
    }

    func webhookCustomHeaderValue(for id: UUID) -> String? {
        KeychainService.retrieve(key: "webhook.\(id.uuidString).customHeaderValue")
    }

    func setWebhookCustomHeaderValue(_ value: String?, for id: UUID) {
        let key = "webhook.\(id.uuidString).customHeaderValue"
        if let v = value, !v.isEmpty { KeychainService.store(key: key, value: v) }
        else { KeychainService.delete(key: key) }
    }

    func deleteWebhookSecrets(for id: UUID) {
        KeychainService.delete(key: "webhook.\(id.uuidString).basicPassword")
        KeychainService.delete(key: "webhook.\(id.uuidString).customHeaderValue")
    }

    // MARK: - Webhooks

    private func sendWebhooks(eventType: String, vmName: String) async {
        let all: [WebhookNotification] = AppDatabase.shared.readOrDefault(.webhookNotifications, default: [])
        let matching = all.filter { $0.isEnabled && $0.enabledEvents.contains(eventType) }
        guard !matching.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for wh in matching {
                group.addTask { await self.sendWebhook(wh, eventType: eventType, vmName: vmName) }
            }
        }
    }

    @discardableResult
    private func sendWebhook(_ webhook: WebhookNotification, eventType: String, vmName: String) async -> Result<Void, NotificationError> {
        guard !webhook.url.isEmpty, let url = URL(string: webhook.url) else {
            AppLogger.shared.warning("Webhook '\(webhook.displayName)' has invalid URL", source: "NotificationService")
            return .failure(.notConfigured("Invalid URL"))
        }

        let now = Date()
        let body = applyWebhookTemplate(webhook.jsonPayload, vmName: vmName, eventType: eventType, timestamp: now, datetimeFormat: webhook.datetimeFormat)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        switch webhook.authType {
        case .none:
            break
        case .basic:
            let password = webhookPassword(for: webhook.id) ?? ""
            let encoded = Data("\(webhook.basicAuthUsername):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        case .custom:
            if !webhook.customAuthHeaderName.isEmpty,
               let value = webhookCustomHeaderValue(for: webhook.id), !value.isEmpty {
                request.setValue(value, forHTTPHeaderField: webhook.customAuthHeaderName)
            }
        }

        for line in webhook.additionalHeaders.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let range = trimmed.range(of: ": ") else { continue }
            let name  = String(trimmed[trimmed.startIndex..<range.lowerBound])
            let value = String(trimmed[range.upperBound...])
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                AppLogger.shared.success("Webhook '\(webhook.displayName)' delivered (HTTP \(status))", source: "NotificationService")
                return .success(())
            } else {
                AppLogger.shared.warning("Webhook '\(webhook.displayName)' returned HTTP \(status)", source: "NotificationService")
                return .failure(.httpError(status))
            }
        } catch {
            AppLogger.shared.error("Webhook '\(webhook.displayName)' failed: \(error.localizedDescription)", source: "NotificationService")
            return .failure(.network(error.localizedDescription))
        }
    }

    func testWebhook(_ webhook: WebhookNotification) async -> Result<Void, NotificationError> {
        await sendWebhook(webhook, eventType: "test", vmName: "TestVM")
    }

    // MARK: - Template helpers

    private func applyWebhookTemplate(_ template: String, vmName: String, eventType: String, timestamp: Date, datetimeFormat: String) -> String {
        let unix = String(Int(timestamp.timeIntervalSince1970))
        let eventLabel = NotificationEvent(rawValue: eventType)?.label ?? eventType
        let datetime = formatWebhookDatetime(timestamp, format: datetimeFormat)
        return template
            .replacingOccurrences(of: "%%VMNAME%%", with: vmName)
            .replacingOccurrences(of: "%%EVENTTYPE%%", with: eventLabel)
            .replacingOccurrences(of: "%%TIMESTAMP%%", with: unix)
            .replacingOccurrences(of: "%%DATETIME%%", with: datetime)
    }

    private func formatWebhookDatetime(_ date: Date, format: String) -> String {
        guard !format.isEmpty else {
            return ISO8601DateFormatter().string(from: date)
        }
        let df = DateFormatter()
        df.dateFormat = strftimeToDFFormat(format)
        return df.string(from: date)
    }

    private func strftimeToDFFormat(_ fmt: String) -> String {
        var result = fmt
        let replacements: [(String, String)] = [
            ("%Y", "yyyy"), ("%y", "yy"),
            ("%m", "MM"),   ("%d", "dd"),
            ("%H", "HH"),   ("%I", "hh"),
            ("%M", "mm"),   ("%S", "ss"),
            ("%A", "EEEE"), ("%a", "EEE"),
            ("%B", "MMMM"), ("%b", "MMM"),
            ("%Z", "zzz"),  ("%z", "Z"),
            ("%p", "a"),    ("%e", "d"),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    // MARK: - Test

    func testSystemNotifications() async -> Result<Void, NotificationError> {

        let content = UNMutableNotificationContent()
        content.title = "Oven: Test notification"
        content.body = "System notifications are configured correctly 🎉"

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard (settings.authorizationStatus == .authorized) ||
              (settings.authorizationStatus == .provisional) else {
            AppLogger.shared.error("System Notifications are disabled for Oven", source:"NotificationService")
            do {
                let _ = try await requestAuthorizationForSystemNotifications()
            } catch {
                print(error.localizedDescription)
                return .failure(.notAuthorized("System Notifications are disabled for Oven"))
            }
            return .failure(.notConfigured("System Notifications are disabled")) }

        if settings.alertSetting == .enabled {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print(error)
            }
            AppLogger.shared.success("Test System Notification sent", source:"NotificationService")
            return .success(())
        } else {
            return .failure(.notConfigured("Notifications are disabled"))
        }
    }

    func testPushover() async -> Result<Void, NotificationError> {
        guard let token = pushoverAppToken, !token.isEmpty,
              let user  = pushoverUserKey,  !user.isEmpty
        else { return .failure(.notConfigured("Token and user key are required")) }

        let body: [String: String] = [
            "token": token, "user": user,
            "title": "Oven: Test notification",
            "message": "Pushover is configured correctly 🎉",
            "sound": "none",
        ]
        do {
            var req = URLRequest(url: URL(string: "https://api.pushover.net/1/messages.json")!)
            req.httpMethod = "POST"
            req.httpBody   = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 ? .success(()) : .failure(.httpError(status))
        } catch { return .failure(.network(error.localizedDescription)) }
    }

    func testSlack() async -> Result<Void, NotificationError> {
        guard let urlStr = slackWebhookURL, !urlStr.isEmpty,
              let url = URL(string: urlStr)
        else { return .failure(.notConfigured("Webhook URL is required")) }

        let payload: [String: Any] = ["text": "Oven: Test notification — Slack is configured correctly 🎉"]
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody   = try JSONSerialization.data(withJSONObject: payload)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 ? .success(()) : .failure(.httpError(status))
        } catch { return .failure(.network(error.localizedDescription)) }
    }

    // MARK: - Teams

    private func sendTeams(title: String, message: String, success: Bool?) async {
        guard let webhookURLString = teamsWebhookURL, !webhookURLString.isEmpty,
              let webhookURL = URL(string: webhookURLString) else {
            AppLogger.shared.warning("Teams enabled but webhook URL not configured", source: "NotificationService")
            return
        }

        let themeColor: String
        switch success {
        case true:  themeColor = "36a64f"
        case false: themeColor = "d32f2f"
        case nil:   themeColor = "f0a500"
        }

        let payload: [String: Any] = [
            "type": "message",
            "attachments": [[
                "contentType": "application/vnd.microsoft.card.adaptive",
                "contentUrl": NSNull(),
                "content": [
                    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                    "type": "AdaptiveCard",
                    "version": "1.2",
                    "msteams": ["width": "Full"],
                    "body": [
                        [
                            "type": "TextBlock",
                            "text": title,
                            "weight": "Bolder",
                            "size": "Medium",
                            "color": success == false ? "Attention" : (success == true ? "Good" : "Warning")
                        ],
                        [
                            "type": "TextBlock",
                            "text": message,
                            "wrap": true
                        ],
                        [
                            "type": "TextBlock",
                            "text": "Oven · macOS VM Manager",
                            "isSubtle": true,
                            "size": "Small"
                        ]
                    ]
                ]
            ]]
        ]

        do {
            var request = URLRequest(url: webhookURL)
            request.httpMethod = "POST"
            request.httpBody   = try JSONSerialization.data(withJSONObject: payload)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 || status == 202 {
                AppLogger.shared.success("Teams notification sent", source: "NotificationService")
            } else {
                AppLogger.shared.warning("Teams returned HTTP \(status)", source: "NotificationService")
            }
        } catch {
            AppLogger.shared.error("Teams failed: \(error.localizedDescription)", source: "NotificationService")
        }
    }

    func testTeams() async -> Result<Void, NotificationError> {
        guard let urlStr = teamsWebhookURL, !urlStr.isEmpty,
              let url = URL(string: urlStr)
        else { return .failure(.notConfigured("Webhook URL is required")) }

        let payload: [String: Any] = [
            "type": "message",
            "attachments": [[
                "contentType": "application/vnd.microsoft.card.adaptive",
                "contentUrl": NSNull(),
                "content": [
                    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                    "type": "AdaptiveCard",
                    "version": "1.2",
                    "body": [[
                        "type": "TextBlock",
                        "text": "Oven: Test notification — Teams is configured correctly 🎉",
                        "wrap": true
                    ]]
                ]
            ]]
        ]
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody   = try JSONSerialization.data(withJSONObject: payload)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (status == 200 || status == 202) ? .success(()) : .failure(.httpError(status))
        } catch { return .failure(.network(error.localizedDescription)) }
    }
}

// MARK: - NotificationError

enum NotificationError: Error, LocalizedError {
    case notAuthorized(String)
    case notConfigured(String)
    case httpError(Int)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let msg): return msg
        case .notConfigured(let msg): return msg
        case .httpError(let code):    return "HTTP \(code)"
        case .network(let msg):       return msg
        }
    }
}
