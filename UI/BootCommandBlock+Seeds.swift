import Foundation

// MARK: - Seeded base boot command blocks
//
// One entry per macOS major version. Each commandLines array maps directly
// to entries in the Tart source block's boot_command = [ ... ] stanza.
// These are best-effort baselines — Apple changes Setup Assistant screens
// across minor versions. Users should fork a base block and pin osVersion
// to a specific minor release if they need to handle a regression.
//
// Sequence source: cirruslabs/macos-image-templates vanilla templates,
// cross-referenced with the boot_command in PackerService.writeTemplate().

extension BootCommandBlock {

    static let baseBlocks: [BootCommandBlock] = [
        goldengate,
        tahoe,
        sequoia,
        sonoma,
        ventura,
        monterey,
    ]
    
    // MARK: - macOS 27 Golden Gate

    static let goldengate = BootCommandBlock(
        // Stable ID — never change once shipped; used as foreign key in ManualBuildConfig
        id: UUID(uuidString: "B1A2C3D4-E5F6-7890-ABCD-EF1234567890")!,
        displayName: "Setup Assistant — Golden Gate",
        blockDescription: "Automates the macOS 27 Golden Gate Setup Assistant. Selects English, skips Apple ID, sets UTC timezone, enables SSH and Screen Sharing, and disables Gatekeeper.",
        commandLines: [
            // Wait for VM to boot to language selection
            #""<wait60s><spacebar>""#,
            // Switch to Italiano then back to English to reliably select English (US)
            #""<wait30s>italiano<esc>english<enter>""#,
            // Select Your Country or Region
            #""<wait30s><click 'Select Your Country or Region'><wait5s>united states<leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Transfer Your Data to This Mac
            #""<wait10s><tab><tab><tab><spacebar><tab><tab><spacebar>""#,
            // Written and Spoken Languages
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Accessibility
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Data & Privacy
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Create a Mac Account
            #""<wait10s><tab><tab><tab><tab><tab><tab>${var.account_userName}<tab>${var.account_userName}<tab>${var.account_password}<tab>${var.account_password}<tab><tab><spacebar><tab><tab><spacebar>""#,
            // Enable Voice Over
            #""<wait120s><leftAltOn><f5><leftAltOff>""#,
            // Sign In with Your Apple ID
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Are you sure you want to skip signing in with an Apple ID?
            #""<wait10s><tab><spacebar>""#,
            // Terms and Conditions
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // I have read and agree to the macOS Software License Agreement
            #""<wait10s><tab><spacebar>""#,
            // Enable Location Services
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Are you sure you don't want to use Location Services?
            #""<wait10s><tab><spacebar>""#,
            // Select Your Time Zone
            #""<wait10s><tab><tab><tab>UTC<enter><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Analytics
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Screen Time
            #""<wait10s><tab><tab><spacebar>""#,
            // Siri
            #""<wait10s><tab><spacebar><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // FileVault
            #""<wait10s><leftShiftOn><tab><tab><leftShiftOff><spacebar>""#,
            // Mac Data Will Not Be Securely Encrypted
            #""<wait10s><tab><spacebar>""#,
            // Choose Your Look
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Update Mac Automatically
            #""<wait10s><tab><tab><spacebar>""#,
            // Welcome to Mac
            #""<wait30s><spacebar>""#,
            // Disable Voice Over
            #""<wait10s><leftAltOn><f5><leftAltOff>""#,
            // Enable Keyboard navigation and open Terminal
            #""<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<wait10s><enter>""#,
            #""<wait10s>defaults write NSGlobalDomain AppleKeyboardUIMode -int 3<enter>""#,
            // Open System Settings > Sharing — enable Screen Sharing and Remote Login
            #""<wait10s>open '/System/Applications/System Settings.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Sharing<enter>""#,
            #""<wait10s><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
            // Disable Gatekeeper
            #""<wait10s>sudo spctl --global-disable<enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            // Confirm Gatekeeper off in Privacy & Security
            #""<wait10s>open '/System/Applications/System Settings.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Privacy & Security<enter>""#,
            #""<wait10s><leftShiftOn><tab><tab><tab><tab><tab><tab><leftShiftOff>""#,
            #""<wait10s><down><wait1s><down><wait1s><enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><wait1s><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
        ],
        isBase: true,
        osName: "macOS 27 Golden Gate",
        osVersion: ""
    )
    
    // MARK: - macOS 26 Tahoe

    static let tahoe = BootCommandBlock(
        // Stable ID — never change once shipped; used as foreign key in ManualBuildConfig
        id: UUID(uuidString: "B1A2C3D4-E5F6-7890-ABCD-EF1234567890")!,
        displayName: "Setup Assistant — Tahoe",
        blockDescription: "Automates the macOS 26 Tahoe Setup Assistant. Selects English, skips Apple ID, sets UTC timezone, enables SSH and Screen Sharing, and disables Gatekeeper.",
        commandLines: [
            // Wait for VM to boot to language selection
            #""<wait60s><spacebar>""#,
            // Switch to Italiano then back to English to reliably select English (US)
            #""<wait30s>italiano<esc>english<enter>""#,
            // Select Your Country or Region
            #""<wait30s><click 'Select Your Country or Region'><wait5s>united states<leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Transfer Your Data to This Mac
            #""<wait10s><tab><tab><tab><spacebar><tab><tab><spacebar>""#,
            // Written and Spoken Languages
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Accessibility
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Data & Privacy
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Create a Mac Account
            #""<wait10s><tab><tab><tab><tab><tab><tab>${var.account_userName}<tab>${var.account_userName}<tab>${var.account_password}<tab>${var.account_password}<tab><tab><spacebar><tab><tab><spacebar>""#,
            // Enable Voice Over
            #""<wait120s><leftAltOn><f5><leftAltOff>""#,
            // Sign In with Your Apple ID
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Are you sure you want to skip signing in with an Apple ID?
            #""<wait10s><tab><spacebar>""#,
            // Terms and Conditions
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // I have read and agree to the macOS Software License Agreement
            #""<wait10s><tab><spacebar>""#,
            // Enable Location Services
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Are you sure you don't want to use Location Services?
            #""<wait10s><tab><spacebar>""#,
            // Select Your Time Zone
            #""<wait10s><tab><tab><tab>UTC<enter><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Analytics
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Screen Time
            #""<wait10s><tab><tab><spacebar>""#,
            // Siri
            #""<wait10s><tab><spacebar><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // FileVault
            #""<wait10s><leftShiftOn><tab><tab><leftShiftOff><spacebar>""#,
            // Mac Data Will Not Be Securely Encrypted
            #""<wait10s><tab><spacebar>""#,
            // Choose Your Look
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Update Mac Automatically
            #""<wait10s><tab><tab><spacebar>""#,
            // Welcome to Mac
            #""<wait30s><spacebar>""#,
            // Disable Voice Over
            #""<wait10s><leftAltOn><f5><leftAltOff>""#,
            // Enable Keyboard navigation and open Terminal
            #""<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<wait10s><enter>""#,
            #""<wait10s>defaults write NSGlobalDomain AppleKeyboardUIMode -int 3<enter>""#,
            // Open System Settings > Sharing — enable Screen Sharing and Remote Login
            #""<wait10s>open '/System/Applications/System Settings.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Sharing<enter>""#,
            #""<wait10s><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
            // Disable Gatekeeper
            #""<wait10s>sudo spctl --global-disable<enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            // Confirm Gatekeeper off in Privacy & Security
            #""<wait10s>open '/System/Applications/System Settings.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Privacy & Security<enter>""#,
            #""<wait10s><leftShiftOn><tab><tab><tab><tab><tab><tab><leftShiftOff>""#,
            #""<wait10s><down><wait1s><down><wait1s><enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><wait1s><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
        ],
        isBase: true,
        osName: "macOS 26 Tahoe",
        osVersion: ""
    )

    // MARK: - macOS 15 Sequoia

    static let sequoia = BootCommandBlock(
        id: UUID(uuidString: "A2B3C4D5-E6F7-8901-BCDE-F12345678901")!,
        displayName: "Setup Assistant — Sequoia",
        blockDescription: "Automates the macOS 15 Sequoia Setup Assistant. Selects English, skips Apple ID, sets UTC timezone, enables SSH and Screen Sharing, and disables Gatekeeper.",
        commandLines: [
            #""<wait60s><spacebar>""#,
            #""<wait30s>italiano<esc>english<enter>""#,
            #""<wait30s><click 'Select Your Country or Region'><wait5s>united states<leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><tab><tab><spacebar><tab><tab><spacebar>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><tab><tab><tab><tab><tab>${var.account_userName}<tab>${var.account_userName}<tab>${var.account_password}<tab>${var.account_password}<tab><tab><spacebar><tab><tab><spacebar>""#,
            #""<wait120s><leftAltOn><f5><leftAltOff>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            #""<wait10s><tab><tab><tab>UTC<enter><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><tab><spacebar>""#,
            #""<wait10s><tab><spacebar><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><leftShiftOn><tab><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><tab><spacebar>""#,
            #""<wait30s><spacebar>""#,
            #""<wait10s><leftAltOn><f5><leftAltOff>""#,
            #""<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<wait10s><enter>""#,
            #""<wait10s>defaults write NSGlobalDomain AppleKeyboardUIMode -int 3<enter>""#,
            #""<wait10s>open '/System/Applications/System Settings.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Sharing<enter>""#,
            #""<wait10s><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
            #""<wait10s>sudo spctl --global-disable<enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            #""<wait10s>open '/System/Applications/System Settings.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Privacy & Security<enter>""#,
            #""<wait10s><leftShiftOn><tab><tab><tab><tab><tab><tab><leftShiftOff>""#,
            #""<wait10s><down><wait1s><down><wait1s><enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><wait1s><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
        ],
        isBase: true,
        osName: "macOS 15 Sequoia",
        osVersion: ""
    )

    // MARK: - macOS 14 Sonoma
    // Sonoma's Setup Assistant is structurally similar to Sequoia but has
    // fewer screens (no "Update Mac Automatically" step at the end).

    static let sonoma = BootCommandBlock(
        id: UUID(uuidString: "C3D4E5F6-A7B8-9012-CDEF-123456789012")!,
        displayName: "Setup Assistant — Sonoma",
        blockDescription: "Automates the macOS 14 Sonoma Setup Assistant. Selects English, skips Apple ID, sets UTC timezone, enables SSH and Screen Sharing, and disables Gatekeeper.",
        commandLines: [
            #""<wait60s><spacebar>""#,
            #""<wait30s>italiano<esc>english<enter>""#,
            #""<wait30s><click 'Select Your Country or Region'><wait5s>united states<leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Migration Assistant
            #""<wait10s><tab><tab><tab><spacebar><tab><tab><spacebar>""#,
            // Accessibility
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Data & Privacy
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Create a Mac Account
            #""<wait10s><tab><tab><tab><tab><tab><tab>${var.account_userName}<tab>${var.account_userName}<tab>${var.account_password}<tab>${var.account_password}<tab><tab><spacebar><tab><tab><spacebar>""#,
            // Enable Voice Over
            #""<wait120s><leftAltOn><f5><leftAltOff>""#,
            // Apple ID
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Terms
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Location Services
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Time Zone
            #""<wait10s><tab><tab><tab>UTC<enter><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Analytics
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Screen Time
            #""<wait10s><tab><tab><spacebar>""#,
            // Siri
            #""<wait10s><tab><spacebar><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // FileVault
            #""<wait10s><leftShiftOn><tab><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Choose Your Look
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Welcome
            #""<wait30s><spacebar>""#,
            #""<wait10s><leftAltOn><f5><leftAltOff>""#,
            #""<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<wait10s><enter>""#,
            #""<wait10s>defaults write NSGlobalDomain AppleKeyboardUIMode -int 3<enter>""#,
            #""<wait10s>open '/System/Applications/System Settings.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Sharing<enter>""#,
            #""<wait10s><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
            #""<wait10s>sudo spctl --global-disable<enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            #""<wait10s>open '/System/Applications/System Settings.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Privacy & Security<enter>""#,
            #""<wait10s><leftShiftOn><tab><tab><tab><tab><tab><tab><leftShiftOff>""#,
            #""<wait10s><down><wait1s><down><wait1s><enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            #""<wait10s><leftShiftOn><tab><leftShiftOff><wait1s><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
        ],
        isBase: true,
        osName: "macOS 14 Sonoma",
        osVersion: ""
    )

    // MARK: - macOS 13 Ventura
    // Ventura uses System Preferences (not System Settings) for Sharing,
    // and spctl syntax differs slightly. The Setup Assistant screen order
    // is similar to Sonoma but keyboard navigation paths differ.

    static let ventura = BootCommandBlock(
        id: UUID(uuidString: "D4E5F6A7-B8C9-0123-DEF0-234567890123")!,
        displayName: "Setup Assistant — Ventura",
        blockDescription: "Automates the macOS 13 Ventura Setup Assistant. Selects English, skips Apple ID, sets UTC timezone, enables SSH and Screen Sharing, and disables Gatekeeper. Uses System Preferences (not System Settings).",
        commandLines: [
            #""<wait60s><spacebar>""#,
            #""<wait30s>italiano<esc>english<enter>""#,
            #""<wait30s><click 'Select Your Country or Region'><wait5s>united states<leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Migration Assistant
            #""<wait10s><tab><tab><tab><spacebar><tab><tab><spacebar>""#,
            // Accessibility
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Data & Privacy
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Create a Mac Account
            #""<wait10s><tab><tab><tab><tab><tab><tab>${var.account_userName}<tab>${var.account_userName}<tab>${var.account_password}<tab>${var.account_password}<tab><tab><spacebar><tab><tab><spacebar>""#,
            #""<wait120s><leftAltOn><f5><leftAltOff>""#,
            // Apple ID
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Terms
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Location Services
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Time Zone
            #""<wait10s><tab><tab><tab>UTC<enter><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Analytics
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Screen Time
            #""<wait10s><tab><tab><spacebar>""#,
            // Siri
            #""<wait10s><tab><spacebar><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // FileVault
            #""<wait10s><leftShiftOn><tab><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Choose Your Look
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Welcome
            #""<wait30s><spacebar>""#,
            #""<wait10s><leftAltOn><f5><leftAltOff>""#,
            #""<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<wait10s><enter>""#,
            #""<wait10s>defaults write NSGlobalDomain AppleKeyboardUIMode -int 3<enter>""#,
            // Ventura: System Preferences > Sharing
            #""<wait10s>open '/System/Applications/System Preferences.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Sharing<enter>""#,
            #""<wait10s><tab><tab><spacebar>""#,
            #""<wait10s><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
            // Ventura: spctl --master-disable (deprecated flag, still works)
            #""<wait10s>sudo spctl --master-disable<enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
        ],
        isBase: true,
        osName: "macOS 13 Ventura",
        osVersion: ""
    )

    // MARK: - macOS 12 Monterey
    // Monterey has a shorter Setup Assistant and uses System Preferences.
    // No "Choose Your Look" screen. spctl --master-disable used.

    static let monterey = BootCommandBlock(
        id: UUID(uuidString: "E5F6A7B8-C9D0-1234-EF01-345678901234")!,
        displayName: "Setup Assistant — Monterey",
        blockDescription: "Automates the macOS 12 Monterey Setup Assistant. Shorter flow than later versions — no 'Choose Your Look' screen. Uses System Preferences and spctl --master-disable.",
        commandLines: [
            #""<wait60s><spacebar>""#,
            #""<wait30s>italiano<esc>english<enter>""#,
            #""<wait30s><click 'Select Your Country or Region'><wait5s>united states<leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Migration Assistant
            #""<wait10s><tab><tab><tab><spacebar><tab><tab><spacebar>""#,
            // Accessibility
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Data & Privacy
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Create a Mac Account
            #""<wait10s><tab><tab><tab><tab><tab><tab>${var.account_userName}<tab>${var.account_userName}<tab>${var.account_password}<tab>${var.account_password}<tab><tab><spacebar><tab><tab><spacebar>""#,
            #""<wait120s><leftAltOn><f5><leftAltOff>""#,
            // Apple ID
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Terms
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Location Services
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            #""<wait10s><tab><spacebar>""#,
            // Time Zone
            #""<wait10s><tab><tab><tab>UTC<enter><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Analytics
            #""<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // Screen Time
            #""<wait10s><tab><tab><spacebar>""#,
            // Siri
            #""<wait10s><tab><spacebar><leftShiftOn><tab><leftShiftOff><spacebar>""#,
            // FileVault — Monterey skips the confirmation dialog
            #""<wait10s><leftShiftOn><tab><tab><leftShiftOff><spacebar>""#,
            // Welcome (no Choose Your Look in Monterey)
            #""<wait30s><spacebar>""#,
            #""<wait10s><leftAltOn><f5><leftAltOff>""#,
            #""<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<wait10s><enter>""#,
            #""<wait10s>defaults write NSGlobalDomain AppleKeyboardUIMode -int 3<enter>""#,
            // Monterey: System Preferences > Sharing
            #""<wait10s>open '/System/Applications/System Preferences.app'<enter>""#,
            #""<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Sharing<enter>""#,
            #""<wait10s><tab><tab><spacebar>""#,
            #""<wait10s><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><spacebar>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
            #""<wait10s>sudo spctl --master-disable<enter>""#,
            #""<wait10s>${var.account_password}<enter>""#,
            #""<wait10s><leftAltOn>q<leftAltOff>""#,
        ],
        isBase: true,
        osName: "macOS 12 Monterey",
        osVersion: ""
    )
}
