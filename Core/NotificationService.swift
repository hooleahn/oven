import Foundation
import UserNotifications

// MARK: - NotificationService
// Sends build status notifications to Pushover and/or Slack.
// Credentials stored in Keychain; only URLs/keys are in UserDefaults.

@MainActor
final class NotificationService {

    static let shared = NotificationService()
    private init() {}

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
        let pushEnabled   = UserDefaults.standard.bool(forKey: "pushoverEnabled")
        let slackEnabled  = UserDefaults.standard.bool(forKey: "slackEnabled")
        let teamsEnabled  = UserDefaults.standard.bool(forKey: "teamsEnabled")
        let systemEnabled = UserDefaults.standard.bool(forKey: "systemNotificationsEnabled")
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

    func notifyBuildStarted(vmName: String) async {
        let pushEnabled   = UserDefaults.standard.bool(forKey: "pushoverEnabled")
        let slackEnabled  = UserDefaults.standard.bool(forKey: "slackEnabled")
        let teamsEnabled  = UserDefaults.standard.bool(forKey: "teamsEnabled")
        let systemEnabled = UserDefaults.standard.bool(forKey: "systemNotificationsEnabled")
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

        // Use Block Kit for a clean Slack message
        let color: String
        switch success {
        case true:  color = "#36a64f"   // green
        case false: color = "#d32f2f"   // red
        case nil:   color = "#f0a500"   // amber (in progress)
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


        // Verify the authorization status.
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
        // 2. Get the shared instance of UNUserNotificationCenter
        let notificationCenter = UNUserNotificationCenter.current()
        // 3. Define the types of authorization you need
        let authorizationOptions: UNAuthorizationOptions = [.alert, .sound, .badge]

        do {
            // 4. Request authorization to the user
            let authorizationGranted = try await notificationCenter.requestAuthorization(options: authorizationOptions)
            // 5. Return the result of the authorization process
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

    // MARK: - Test
    
    func testSystemNotifications() async -> Result<Void, NotificationError> {
        
        let content = UNMutableNotificationContent()
        content.title = "Oven: Test notification"
        content.body = "System notifications are configured correctly 🎉"
        
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()


        // Verify the authorization status.
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

            // add our notification request
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

        // Adaptive Card (Teams Incoming Webhook format)
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
