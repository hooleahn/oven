import SwiftUI

// MARK: - AppTheme
// Controls "Fun Mode" — replaces technical labels with baking/tart terminology.
// Inject into the environment once at the root; all views read from it.

@MainActor
@Observable
final class AppTheme {

    var funModeEnabled: Bool = UserDefaults.standard.bool(forKey: "funModeEnabled") {
        didSet { UserDefaults.standard.set(funModeEnabled, forKey: "funModeEnabled") }
    }

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
    var debugModeEnabled: Bool = UserDefaults.standard.bool(forKey: "debugModeEnabled") {
        didSet { UserDefaults.standard.set(debugModeEnabled, forKey: "debugModeEnabled") }
    }

    // Input lock settings
    var showUnlockHintOverlay: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "showUnlockHintOverlay") != nil ? ud.bool(forKey: "showUnlockHintOverlay") : true
    }() {
        didSet { UserDefaults.standard.set(showUnlockHintOverlay, forKey: "showUnlockHintOverlay") }
    }

    var buildCompletionAction: String = UserDefaults.standard.string(forKey: "buildCompletionAction") ?? "nothing" {
        didSet { UserDefaults.standard.set(buildCompletionAction, forKey: "buildCompletionAction") }
    }

    var buildTimeoutMinutes: Int = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "buildTimeoutMinutes") != nil ? ud.integer(forKey: "buildTimeoutMinutes") : 180
    }() {
        didSet { UserDefaults.standard.set(buildTimeoutMinutes, forKey: "buildTimeoutMinutes") }
    }

    var buildHeartbeatMinutes: Int = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "buildHeartbeatMinutes") != nil ? ud.integer(forKey: "buildHeartbeatMinutes") : 10
    }() {
        didSet { UserDefaults.standard.set(buildHeartbeatMinutes, forKey: "buildHeartbeatMinutes") }
    }

    var batteryThresholdPct: Double = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "batteryThresholdPct") != nil ? ud.double(forKey: "batteryThresholdPct") : 80.0
    }() {
        didSet { UserDefaults.standard.set(batteryThresholdPct, forKey: "batteryThresholdPct") }
    }

    // Notification settings — master toggles
    var systemNotificationsEnabled: Bool = UserDefaults.standard.bool(forKey: "systemNotificationsEnabled") {
        didSet { UserDefaults.standard.set(systemNotificationsEnabled, forKey: "systemNotificationsEnabled") }
    }

    var pushoverEnabled: Bool = UserDefaults.standard.bool(forKey: "pushoverEnabled") {
        didSet { UserDefaults.standard.set(pushoverEnabled, forKey: "pushoverEnabled") }
    }

    var slackEnabled: Bool = UserDefaults.standard.bool(forKey: "slackEnabled") {
        didSet { UserDefaults.standard.set(slackEnabled, forKey: "slackEnabled") }
    }

    var teamsEnabled: Bool = UserDefaults.standard.bool(forKey: "teamsEnabled") {
        didSet { UserDefaults.standard.set(teamsEnabled, forKey: "teamsEnabled") }
    }

    // System notification — delivery style (banner vs alert handled by OS; we track sound preference)
    var systemNotifSoundEnabled: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.system.soundEnabled") != nil ? ud.bool(forKey: "notif.system.soundEnabled") : true
    }() {
        didSet { UserDefaults.standard.set(systemNotifSoundEnabled, forKey: "notif.system.soundEnabled") }
    }

    // Per-event toggles — System
    var systemNotifBaseVMBuildSucceeded: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.system.baseVMBuildSucceeded") != nil ? ud.bool(forKey: "notif.system.baseVMBuildSucceeded") : true
    }() {
        didSet { UserDefaults.standard.set(systemNotifBaseVMBuildSucceeded, forKey: "notif.system.baseVMBuildSucceeded") }
    }

    var systemNotifBaseVMBuildFailed: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.system.baseVMBuildFailed") != nil ? ud.bool(forKey: "notif.system.baseVMBuildFailed") : true
    }() {
        didSet { UserDefaults.standard.set(systemNotifBaseVMBuildFailed, forKey: "notif.system.baseVMBuildFailed") }
    }

    var systemNotifIPSWDownloaded: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.system.ipswDownloaded") != nil ? ud.bool(forKey: "notif.system.ipswDownloaded") : true
    }() {
        didSet { UserDefaults.standard.set(systemNotifIPSWDownloaded, forKey: "notif.system.ipswDownloaded") }
    }

    var systemNotifImagePullCompleted: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.system.imagePullCompleted") != nil ? ud.bool(forKey: "notif.system.imagePullCompleted") : true
    }() {
        didSet { UserDefaults.standard.set(systemNotifImagePullCompleted, forKey: "notif.system.imagePullCompleted") }
    }

    var systemNotifImagePushCompleted: Bool = UserDefaults.standard.bool(forKey: "notif.system.imagePushCompleted") {
        didSet { UserDefaults.standard.set(systemNotifImagePushCompleted, forKey: "notif.system.imagePushCompleted") }
    }

    var systemNotifVMStopped: Bool = UserDefaults.standard.bool(forKey: "notif.system.vmStopped") {
        didSet { UserDefaults.standard.set(systemNotifVMStopped, forKey: "notif.system.vmStopped") }
    }

    var systemNotifVMStarted: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.system.vmStarted") != nil ? ud.bool(forKey: "notif.system.vmStarted") : true
    }() {
        didSet { UserDefaults.standard.set(systemNotifVMStarted, forKey: "notif.system.vmStarted") }
    }

    var systemNotifVMStartFailed: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.system.vmStartFailed") != nil ? ud.bool(forKey: "notif.system.vmStartFailed") : true
    }() {
        didSet { UserDefaults.standard.set(systemNotifVMStartFailed, forKey: "notif.system.vmStartFailed") }
    }

    // Per-event toggles — Pushover
    var pushoverNotifBaseVMBuildSucceeded: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.pushover.baseVMBuildSucceeded") != nil ? ud.bool(forKey: "notif.pushover.baseVMBuildSucceeded") : true
    }() {
        didSet { UserDefaults.standard.set(pushoverNotifBaseVMBuildSucceeded, forKey: "notif.pushover.baseVMBuildSucceeded") }
    }

    var pushoverNotifBaseVMBuildFailed: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.pushover.baseVMBuildFailed") != nil ? ud.bool(forKey: "notif.pushover.baseVMBuildFailed") : true
    }() {
        didSet { UserDefaults.standard.set(pushoverNotifBaseVMBuildFailed, forKey: "notif.pushover.baseVMBuildFailed") }
    }

    var pushoverNotifIPSWDownloaded: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.pushover.ipswDownloaded") != nil ? ud.bool(forKey: "notif.pushover.ipswDownloaded") : true
    }() {
        didSet { UserDefaults.standard.set(pushoverNotifIPSWDownloaded, forKey: "notif.pushover.ipswDownloaded") }
    }

    var pushoverNotifImagePullCompleted: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.pushover.imagePullCompleted") != nil ? ud.bool(forKey: "notif.pushover.imagePullCompleted") : true
    }() {
        didSet { UserDefaults.standard.set(pushoverNotifImagePullCompleted, forKey: "notif.pushover.imagePullCompleted") }
    }

    var pushoverNotifImagePushCompleted: Bool = UserDefaults.standard.bool(forKey: "notif.pushover.imagePushCompleted") {
        didSet { UserDefaults.standard.set(pushoverNotifImagePushCompleted, forKey: "notif.pushover.imagePushCompleted") }
    }

    var pushoverNotifVMStopped: Bool = UserDefaults.standard.bool(forKey: "notif.pushover.vmStopped") {
        didSet { UserDefaults.standard.set(pushoverNotifVMStopped, forKey: "notif.pushover.vmStopped") }
    }

    var pushoverNotifVMStarted: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.pushover.vmStarted") != nil ? ud.bool(forKey: "notif.pushover.vmStarted") : true
    }() {
        didSet { UserDefaults.standard.set(pushoverNotifVMStarted, forKey: "notif.pushover.vmStarted") }
    }

    var pushoverNotifVMStartFailed: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.pushover.vmStartFailed") != nil ? ud.bool(forKey: "notif.pushover.vmStartFailed") : true
    }() {
        didSet { UserDefaults.standard.set(pushoverNotifVMStartFailed, forKey: "notif.pushover.vmStartFailed") }
    }

    // Per-event toggles — Slack
    var slackNotifBaseVMBuildSucceeded: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.slack.baseVMBuildSucceeded") != nil ? ud.bool(forKey: "notif.slack.baseVMBuildSucceeded") : true
    }() {
        didSet { UserDefaults.standard.set(slackNotifBaseVMBuildSucceeded, forKey: "notif.slack.baseVMBuildSucceeded") }
    }

    var slackNotifBaseVMBuildFailed: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.slack.baseVMBuildFailed") != nil ? ud.bool(forKey: "notif.slack.baseVMBuildFailed") : true
    }() {
        didSet { UserDefaults.standard.set(slackNotifBaseVMBuildFailed, forKey: "notif.slack.baseVMBuildFailed") }
    }

    var slackNotifIPSWDownloaded: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.slack.ipswDownloaded") != nil ? ud.bool(forKey: "notif.slack.ipswDownloaded") : true
    }() {
        didSet { UserDefaults.standard.set(slackNotifIPSWDownloaded, forKey: "notif.slack.ipswDownloaded") }
    }

    var slackNotifImagePullCompleted: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.slack.imagePullCompleted") != nil ? ud.bool(forKey: "notif.slack.imagePullCompleted") : true
    }() {
        didSet { UserDefaults.standard.set(slackNotifImagePullCompleted, forKey: "notif.slack.imagePullCompleted") }
    }

    var slackNotifImagePushCompleted: Bool = UserDefaults.standard.bool(forKey: "notif.slack.imagePushCompleted") {
        didSet { UserDefaults.standard.set(slackNotifImagePushCompleted, forKey: "notif.slack.imagePushCompleted") }
    }

    var slackNotifVMStopped: Bool = UserDefaults.standard.bool(forKey: "notif.slack.vmStopped") {
        didSet { UserDefaults.standard.set(slackNotifVMStopped, forKey: "notif.slack.vmStopped") }
    }

    var slackNotifVMStarted: Bool = UserDefaults.standard.bool(forKey: "notif.slack.vmStarted") {
        didSet { UserDefaults.standard.set(slackNotifVMStarted, forKey: "notif.slack.vmStarted") }
    }

    var slackNotifVMStartFailed: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.slack.vmStartFailed") != nil ? ud.bool(forKey: "notif.slack.vmStartFailed") : true
    }() {
        didSet { UserDefaults.standard.set(slackNotifVMStartFailed, forKey: "notif.slack.vmStartFailed") }
    }

    // Per-event toggles — Teams
    var teamsNotifBaseVMBuildSucceeded: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.teams.baseVMBuildSucceeded") != nil ? ud.bool(forKey: "notif.teams.baseVMBuildSucceeded") : true
    }() {
        didSet { UserDefaults.standard.set(teamsNotifBaseVMBuildSucceeded, forKey: "notif.teams.baseVMBuildSucceeded") }
    }

    var teamsNotifBaseVMBuildFailed: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.teams.baseVMBuildFailed") != nil ? ud.bool(forKey: "notif.teams.baseVMBuildFailed") : true
    }() {
        didSet { UserDefaults.standard.set(teamsNotifBaseVMBuildFailed, forKey: "notif.teams.baseVMBuildFailed") }
    }

    var teamsNotifIPSWDownloaded: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.teams.ipswDownloaded") != nil ? ud.bool(forKey: "notif.teams.ipswDownloaded") : true
    }() {
        didSet { UserDefaults.standard.set(teamsNotifIPSWDownloaded, forKey: "notif.teams.ipswDownloaded") }
    }

    var teamsNotifImagePullCompleted: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.teams.imagePullCompleted") != nil ? ud.bool(forKey: "notif.teams.imagePullCompleted") : true
    }() {
        didSet { UserDefaults.standard.set(teamsNotifImagePullCompleted, forKey: "notif.teams.imagePullCompleted") }
    }

    var teamsNotifImagePushCompleted: Bool = UserDefaults.standard.bool(forKey: "notif.teams.imagePushCompleted") {
        didSet { UserDefaults.standard.set(teamsNotifImagePushCompleted, forKey: "notif.teams.imagePushCompleted") }
    }

    var teamsNotifVMStopped: Bool = UserDefaults.standard.bool(forKey: "notif.teams.vmStopped") {
        didSet { UserDefaults.standard.set(teamsNotifVMStopped, forKey: "notif.teams.vmStopped") }
    }

    var teamsNotifVMStarted: Bool = UserDefaults.standard.bool(forKey: "notif.teams.vmStarted") {
        didSet { UserDefaults.standard.set(teamsNotifVMStarted, forKey: "notif.teams.vmStarted") }
    }

    var teamsNotifVMStartFailed: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "notif.teams.vmStartFailed") != nil ? ud.bool(forKey: "notif.teams.vmStartFailed") : true
    }() {
        didSet { UserDefaults.standard.set(teamsNotifVMStartFailed, forKey: "notif.teams.vmStartFailed") }
    }

    // Menu bar
    var menuBarItemEnabled: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "menuBarItemEnabled") != nil ? ud.bool(forKey: "menuBarItemEnabled") : true
    }() {
        didSet { UserDefaults.standard.set(menuBarItemEnabled, forKey: "menuBarItemEnabled") }
    }

    // MDM features
    var mdmEnabled: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "mdmEnabled") != nil ? ud.bool(forKey: "mdmEnabled") : true
    }() {
        didSet { UserDefaults.standard.set(mdmEnabled, forKey: "mdmEnabled") }
    }

    // Build settings
    var preventSleepDuringBuild: Bool = {
        let ud = UserDefaults.standard
        return ud.object(forKey: "preventSleepDuringBuild") != nil ? ud.bool(forKey: "preventSleepDuringBuild") : true
    }() {
        didSet { UserDefaults.standard.set(preventSleepDuringBuild, forKey: "preventSleepDuringBuild") }
    }

    var showGraphicsDuringBuild: Bool = UserDefaults.standard.bool(forKey: "showGraphicsDuringBuild") {
        didSet { UserDefaults.standard.set(showGraphicsDuringBuild, forKey: "showGraphicsDuringBuild") }
    }

    var lockInputDuringBuild: Bool = UserDefaults.standard.bool(forKey: "lockInputDuringBuild") {
        didSet { UserDefaults.standard.set(lockInputDuringBuild, forKey: "lockInputDuringBuild") }
    }
}
