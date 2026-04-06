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
    var recipes: String          { funModeEnabled ? "Recipes"       : "Packer Templates" }
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

    // Notification settings
    @AppStorage("systemNotificationsEnabled")       var systemNotificationsEnabled: Bool = false
    @AppStorage("pushoverEnabled")    var pushoverEnabled: Bool = false
    @AppStorage("slackEnabled")       var slackEnabled: Bool = false

    // Build settings
    @AppStorage("preventSleepDuringBuild") var preventSleepDuringBuild: Bool = true
    @AppStorage("showGraphicsDuringBuild") var showGraphicsDuringBuild: Bool = false
    @AppStorage("lockInputDuringBuild")    var lockInputDuringBuild: Bool = false
}

