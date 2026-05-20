import SwiftUI

// MARK: - AppTheme
// Controls "Fun Mode" — replaces technical labels with baking/tart terminology.
// Inject into the environment once at the root; all views read from it.

@MainActor
final class AppTheme: ObservableObject {

    @AppStorage("funModeEnabled") var funModeEnabled: Bool = false

    // MARK: - Label resolution

    /// Primary section names (sidebar, nav titles)
    var virtualMachines: String  { funModeEnabled ? "Tarts"        : "Virtual Machines" }
    var baseVMs: String          { funModeEnabled ? "Recipes"       : "Base VMs" }
    var installers: String       { funModeEnabled ? "Ingredients"   : "macOS Installers" }
    var registry: String         { funModeEnabled ? "Pantry"        : "Image Registry" }
    var mdmEnrollment: String    { funModeEnabled ? "MDM Enroll"    : "MDM Enrollment" }
    var mdmServers: String       { funModeEnabled ? "MDM Servers"   : "MDM Servers" }
    var recipes: String          { funModeEnabled ? "Recipe Book"   : "Packer Templates" }
    var logs: String             { funModeEnabled ? "Oven Log"      : "Activity Log" }

    /// Action verbs
    var build: String            { funModeEnabled ? "Bake"          : "Build" }
    var building: String         { funModeEnabled ? "Baking"        : "Building" }
    var built: String            { funModeEnabled ? "Baked"         : "Built" }
    var clone: String            { funModeEnabled ? "Slice"         : "Clone" }
    var newVM: String            { funModeEnabled ? "New Tart"      : "New VM" }
    var newBaseVM: String        { funModeEnabled ? "New Recipe"    : "New Base VM" }

    /// SF Symbols (same in both modes — the icon stays recognisable)
    var vmIcon: String           { "desktopcomputer" }
    var baseVMIcon: String       { funModeEnabled ? "oven"          : "shippingbox" }
    var installerIcon: String    { funModeEnabled ? "carrot"        : "arrow.down.circle" }
    var registryIcon: String     { funModeEnabled ? "cabinet"       : "externaldrive.connected.to.line.below" }
    var buildIcon: String        { funModeEnabled ? "flame"         : "hammer.fill" }

    // Debug mode: logs full commands and file paths to Activity Log before builds
    @AppStorage("debugModeEnabled") var debugModeEnabled: Bool = false

    // Input lock settings
    @AppStorage("showUnlockHintOverlay") var showUnlockHintOverlay: Bool = true
    @AppStorage("buildCompletionAction")   var buildCompletionAction: String = "nothing"  // "nothing" | "lock" | "shutdown"
    @AppStorage("buildTimeoutMinutes")    var buildTimeoutMinutes: Int = 180   // 3 hours
    @AppStorage("buildHeartbeatMinutes")  var buildHeartbeatMinutes: Int = 10  // warn if silent
    @AppStorage("batteryThresholdPct")    var batteryThresholdPct: Double = 80.0

    // Notification settings — master toggles
    @AppStorage("systemNotificationsEnabled") var systemNotificationsEnabled: Bool = false
    @AppStorage("pushoverEnabled")            var pushoverEnabled: Bool = false
    @AppStorage("slackEnabled")               var slackEnabled: Bool = false
    @AppStorage("teamsEnabled")               var teamsEnabled: Bool = false

    // System notification — delivery style (banner vs alert handled by OS; we track sound preference)
    @AppStorage("notif.system.soundEnabled")  var systemNotifSoundEnabled: Bool = true

    // Per-event toggles — System
    @AppStorage("notif.system.baseVMBuildSucceeded") var systemNotifBaseVMBuildSucceeded: Bool = true
    @AppStorage("notif.system.baseVMBuildFailed")    var systemNotifBaseVMBuildFailed: Bool = true
    @AppStorage("notif.system.ipswDownloaded")       var systemNotifIPSWDownloaded: Bool = true
    @AppStorage("notif.system.imagePullCompleted")   var systemNotifImagePullCompleted: Bool = true
    @AppStorage("notif.system.imagePushCompleted")   var systemNotifImagePushCompleted: Bool = false
    @AppStorage("notif.system.vmStopped")            var systemNotifVMStopped: Bool = false
    @AppStorage("notif.system.vmStarted")            var systemNotifVMStarted: Bool = true
    @AppStorage("notif.system.vmStartFailed")        var systemNotifVMStartFailed: Bool = true

    // Per-event toggles — Pushover
    @AppStorage("notif.pushover.baseVMBuildSucceeded") var pushoverNotifBaseVMBuildSucceeded: Bool = true
    @AppStorage("notif.pushover.baseVMBuildFailed")    var pushoverNotifBaseVMBuildFailed: Bool = true
    @AppStorage("notif.pushover.ipswDownloaded")       var pushoverNotifIPSWDownloaded: Bool = true
    @AppStorage("notif.pushover.imagePullCompleted")   var pushoverNotifImagePullCompleted: Bool = true
    @AppStorage("notif.pushover.imagePushCompleted")   var pushoverNotifImagePushCompleted: Bool = false
    @AppStorage("notif.pushover.vmStopped")            var pushoverNotifVMStopped: Bool = false
    @AppStorage("notif.pushover.vmStarted")            var pushoverNotifVMStarted: Bool = true
    @AppStorage("notif.pushover.vmStartFailed")        var pushoverNotifVMStartFailed: Bool = true

    // Per-event toggles — Slack
    @AppStorage("notif.slack.baseVMBuildSucceeded") var slackNotifBaseVMBuildSucceeded: Bool = true
    @AppStorage("notif.slack.baseVMBuildFailed")    var slackNotifBaseVMBuildFailed: Bool = true
    @AppStorage("notif.slack.ipswDownloaded")       var slackNotifIPSWDownloaded: Bool = true
    @AppStorage("notif.slack.imagePullCompleted")   var slackNotifImagePullCompleted: Bool = true
    @AppStorage("notif.slack.imagePushCompleted")   var slackNotifImagePushCompleted: Bool = false
    @AppStorage("notif.slack.vmStopped")            var slackNotifVMStopped: Bool = false
    @AppStorage("notif.slack.vmStarted")            var slackNotifVMStarted: Bool = false
    @AppStorage("notif.slack.vmStartFailed")        var slackNotifVMStartFailed: Bool = true

    // Per-event toggles — Teams
    @AppStorage("notif.teams.baseVMBuildSucceeded") var teamsNotifBaseVMBuildSucceeded: Bool = true
    @AppStorage("notif.teams.baseVMBuildFailed")    var teamsNotifBaseVMBuildFailed: Bool = true
    @AppStorage("notif.teams.ipswDownloaded")       var teamsNotifIPSWDownloaded: Bool = true
    @AppStorage("notif.teams.imagePullCompleted")   var teamsNotifImagePullCompleted: Bool = true
    @AppStorage("notif.teams.imagePushCompleted")   var teamsNotifImagePushCompleted: Bool = false
    @AppStorage("notif.teams.vmStopped")            var teamsNotifVMStopped: Bool = false
    @AppStorage("notif.teams.vmStarted")            var teamsNotifVMStarted: Bool = false
    @AppStorage("notif.teams.vmStartFailed")        var teamsNotifVMStartFailed: Bool = true

    // Menu bar
    @AppStorage("menuBarItemEnabled") var menuBarItemEnabled: Bool = true

    // MDM features
    @AppStorage("mdmEnabled") var mdmEnabled: Bool = true

    // Build settings
    @AppStorage("preventSleepDuringBuild") var preventSleepDuringBuild: Bool = true
    @AppStorage("showGraphicsDuringBuild") var showGraphicsDuringBuild: Bool = false
    @AppStorage("lockInputDuringBuild")    var lockInputDuringBuild: Bool = false
}
