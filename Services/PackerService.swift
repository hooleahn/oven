import Foundation

actor PackerService {

    private let runner: ProcessRunner
    private let packerPath: String
    private let pluginDir: String
    private let templatesRoot: URL

    init(runner: ProcessRunner, packerPath: String, pluginDir: String, templatesRoot: URL) {
        self.runner = runner
        self.packerPath = packerPath
        self.pluginDir = pluginDir
        self.templatesRoot = templatesRoot
    }

    // MARK: - Build pipeline

    func buildWithInit(templateName: String, varsFileName: String,
                        username: String = "baker", password: String = "baker",
                        showGraphics: Bool = false) async -> AsyncStream<ProcessEvent> {
        AsyncStream { continuation in
            Task {
                let templateURL = templatesRoot.appendingPathComponent(templateName)
                let varsURL     = templatesRoot.appendingPathComponent(varsFileName)
                // Sanitised minimal env for packer/tart -- don't inherit the full Oven process env
                let depsDir = URL(fileURLWithPath: packerPath).deletingLastPathComponent().path
                let parentEnv = ProcessInfo.processInfo.environment
                let debug = UserDefaults.standard.bool(forKey: "debugModeEnabled")
                var env: [String: String] = [
                    "PACKER_PLUGIN_PATH": pluginDir,
                    "PATH":   "\(depsDir):/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME":   parentEnv["HOME"]   ?? NSHomeDirectory(),
                    "TMPDIR": parentEnv["TMPDIR"] ?? "/tmp",
                    "USER":   parentEnv["USER"]   ?? "unknown",
                    "SHELL":  "/bin/zsh",
                ]
                // Forward TART_HOME so tart stores VMs in the user-configured location
                let tartHome = AppSettings.load().resolvedTartHome.path
                env["TART_HOME"] = tartHome
                if debug { env["PACKER_LOG"] = "1" }

                // Write a temporary credentials pkrvars file — deleted after build.
                // Using a second -var-file is more reliable than env() in variable defaults.
                let credVarsURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("oven-creds-\(UUID().uuidString).pkrvars.hcl")
                var credContent = "account_userName = \"\(username)\"\naccount_password = \"\(password)\"\n"
                if debug && showGraphics {
                    credContent += "\nrun_extra_args = [\"--no-audio\", \"--graphics\"]\n"
                }
                do {
                    try credContent.write(to: credVarsURL, atomically: true, encoding: .utf8)
                } catch {
                    
                    continuation.yield(.exit(1)); continuation.finish(); return
                }
                defer { try? FileManager.default.removeItem(at: credVarsURL) }

                continuation.yield(.stdout("==> packer init \(templateURL.lastPathComponent)"))
                if debug {
                    continuation.yield(.stdout("[debug] Binary: \(packerPath)"))
                    continuation.yield(.stdout("[debug] Template: \(templateURL.path)"))
                    continuation.yield(.stdout("[debug] Plugin dir: \(pluginDir)"))
                    continuation.yield(.stdout("[debug] PATH prefix: \(depsDir)"))
                }
                do {
                    try await runner.run(packerPath, arguments: ["init", templateURL.path], environment: env)
                    continuation.yield(.stdout("==> Init complete"))
                } catch {
                    continuation.yield(.stderr("Init failed: \(error.localizedDescription)"))
                    continuation.yield(.exit(1))
                    continuation.finish()
                    return
                }

                continuation.yield(.stdout("==> packer build \(templateURL.lastPathComponent)"))
                // Always log the command so the user can verify which template is being used
                continuation.yield(.stdout("[cmd] \"\(packerPath)\" build -color=false -var-file=\"\(varsURL.path)\" -var-file=<creds> \"\(templateURL.path)\""))
                if debug {
                    continuation.yield(.stdout("[debug] Full vars file path: \(varsURL.path)"))
                    continuation.yield(.stdout("[debug] Vars file exists: \(FileManager.default.fileExists(atPath: varsURL.path))"))
                    continuation.yield(.stdout("[debug] Template exists: \(FileManager.default.fileExists(atPath: templateURL.path))"))
                    if let varsContent = try? String(contentsOf: varsURL, encoding: .utf8) {
                        // Redact password lines before logging
                        let redacted = varsContent.split(separator: "\n").map { line -> String in
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            if trimmed.hasPrefix("account_password") {
                                return "account_password = \"[REDACTED]\""
                            }
                            return String(line)
                        }.joined(separator: "\n")
                        continuation.yield(.stdout("[debug] Vars content:\n\(redacted)"))
                    }
                }
                if debug {
                    continuation.yield(.stdout("[debug] Creds file: \(credVarsURL.lastPathComponent) (temp, deleted after build)"))
                    continuation.yield(.stdout("[debug] PACKER_LOG=1 \(debug ? "enabled" : "disabled")"))
                }
                let stream = await runner.stream(
                    packerPath,
                    arguments: ["build", "-color=false",
                                "-var-file=\(varsURL.path)",
                                "-var-file=\(credVarsURL.path)",
                                templateURL.path],
                    environment: env
                )
                for await event in stream {
                    continuation.yield(event)
                    if case .exit = event { break }
                }
                continuation.finish()
            }
        }
    }

    /// Builds a template at an absolute URL (used by the manual build path).
    /// Like buildWithInit but accepts a pre-generated HCL file at any location.
    /// No vars file is used — all variable defaults are embedded in the generated HCL.
    func buildWithInitURL(templateURL: URL,
                          username: String, password: String,
                          showGraphics: Bool = false) async -> AsyncStream<ProcessEvent> {
        AsyncStream { continuation in
            Task {
                let depsDir = URL(fileURLWithPath: packerPath).deletingLastPathComponent().path
                let parentEnv = ProcessInfo.processInfo.environment
                let debug = UserDefaults.standard.bool(forKey: "debugModeEnabled")
                var env: [String: String] = [
                    "PACKER_PLUGIN_PATH": pluginDir,
                    "PATH":   "\(depsDir):/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME":   parentEnv["HOME"]   ?? NSHomeDirectory(),
                    "TMPDIR": parentEnv["TMPDIR"] ?? "/tmp",
                    "USER":   parentEnv["USER"]   ?? "unknown",
                    "SHELL":  "/bin/zsh",
                ]
                let tartHome = AppSettings.load().resolvedTartHome.path
                env["TART_HOME"] = tartHome
                if debug { env["PACKER_LOG"] = "1" }

                // Write temp credentials vars file
                let credVarsURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("oven-creds-\(UUID().uuidString).pkrvars.hcl")
                let credContent = "account_userName = \"\(username)\"\naccount_password = \"\(password)\"\n"
                do {
                    try credContent.write(to: credVarsURL, atomically: true, encoding: .utf8)
                } catch {
                    continuation.yield(.exit(1)); continuation.finish(); return
                }
                defer { try? FileManager.default.removeItem(at: credVarsURL) }

                continuation.yield(.stdout("==> packer init \(templateURL.lastPathComponent)"))
                if debug {
                    continuation.yield(.stdout("[debug] Binary: \(packerPath)"))
                    continuation.yield(.stdout("[debug] Template: \(templateURL.path)"))
                    continuation.yield(.stdout("[debug] Plugin dir: \(pluginDir)"))
                }
                do {
                    try await runner.run(packerPath, arguments: ["init", templateURL.path], environment: env)
                    continuation.yield(.stdout("==> Init complete"))
                } catch {
                    continuation.yield(.stderr("Init failed: \(error.localizedDescription)"))
                    continuation.yield(.exit(1))
                    continuation.finish()
                    return
                }

                continuation.yield(.stdout("==> packer build \(templateURL.lastPathComponent)"))
                continuation.yield(.stdout("[cmd] \"\(packerPath)\" build -color=false -var-file=<creds> \"\(templateURL.path)\""))

                let stream = await runner.stream(
                    packerPath,
                    arguments: ["build", "-color=false",
                                "-var-file=\(credVarsURL.path)",
                                templateURL.path],
                    environment: env
                )
                for await event in stream {
                    continuation.yield(event)
                    if case .exit = event { break }
                }
                continuation.finish()
            }
        }
    }

    /// Validates a full template standalone (no vars file — uses variable defaults).
    /// Runs packer init first, then packer validate. Yields status strings for UI display.
    func validateStandalone(at url: URL) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let depsDir = URL(fileURLWithPath: packerPath).deletingLastPathComponent().path
                let parentEnv = ProcessInfo.processInfo.environment
                let env: [String: String] = [
                    "PACKER_PLUGIN_PATH": pluginDir,
                    "PATH":   "\(depsDir):/usr/bin:/bin:/usr/sbin:/sbin",
                    "HOME":   parentEnv["HOME"]   ?? NSHomeDirectory(),
                    "TMPDIR": parentEnv["TMPDIR"] ?? "/tmp",
                    "USER":   parentEnv["USER"]   ?? "unknown",
                ]
                let debug = UserDefaults.standard.bool(forKey: "debugModeEnabled")
                // Capture output to parse errors
                let process = Process()
                process.executableURL = URL(fileURLWithPath: packerPath)
                process.arguments = ["validate", "-syntax-only", url.path]
                process.environment = env
                
                continuation.yield("> Running packer validate for template at \(url.path)...")
                if debug {
                    continuation.yield("[debug] Binary: \(packerPath)")
                    continuation.yield("[debug] Template: \(url.path)")
                    continuation.yield("[debug] Plugin dir: \(pluginDir)")
                    continuation.yield("[debug] PATH prefix: \(depsDir)")
                }
                
                // Capture output to parse errors
                let errorPipe = Pipe()
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        continuation.yield("✓ Template is valid")
                        continuation.finish()
                        return true
                    } else {
                        if debug {
                            continuation.yield("[debug] Exit Code: \(process.terminationStatus)")
                            continuation.yield("[debug] Command Arguments: \(process.arguments?.joined(separator: " ") ?? "")")
                        }
                        // Print stdio
                        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let standardOutput = String(data: stdoutData, encoding: .utf8)
                        continuation.yield("✗ Template validation failed (Exit code: \(process.terminationStatus))")
                        continuation.yield(standardOutput ?? "Unknown Error")
                        print("Validation failed (Exit code: \(process.terminationStatus)), Error Details: \( standardOutput ?? "Unknown Error")")
                        continuation.finish()
                        return false
                    }
                } catch {
                    print("Error running packer: \(error)")
                    continuation.finish()
                    return false
                }
            }
        }
    }

    func validate(templateName: String, varsFileName: String) async throws {
        let templateURL = templatesRoot.appendingPathComponent(templateName)
        let varsURL     = templatesRoot.appendingPathComponent(varsFileName)
        let depsDir = URL(fileURLWithPath: packerPath).deletingLastPathComponent().path
        let parentEnv2 = ProcessInfo.processInfo.environment
        try await runner.run(
            packerPath,
            arguments: ["validate", "-var-file=\(varsURL.path)", templateURL.path],
            environment: [
                "PACKER_PLUGIN_PATH": pluginDir,
                "PATH":   "\(depsDir):/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME":   parentEnv2["HOME"]   ?? NSHomeDirectory(),
                "TMPDIR": parentEnv2["TMPDIR"] ?? "/tmp",
                "USER":   parentEnv2["USER"]   ?? "unknown",
            ]
        )
    }

    // MARK: - Build config

    struct BuildConfig {
        let vmName: String
        let ipswURL: String
        let username: String
        let password: String
        let cpuCount: Int
        let memoryGB: Int
        let diskGB: Int
        let installRosetta: Bool
        let installHomebrew: Bool
        let enableSSHDaemon: Bool
        let enableAutoLogin: Bool
        let enablePasswordlessSudo: Bool
        let xcodeVersion: String?
        let jamfURL: String?
        let mdmInvitationID: String?
        let enrollmentType: String
        var showGraphics: Bool = false  // when true, headless = false (shows tart window)
    }

    // MARK: - Template generation
    // Matches motionbug apple-tart-tahoe.pkr.hcl exactly, including:
    //   - Full setup assistant boot_command
    //   - Shell provisioner with if/fi conditionals (not HCL dynamic blocks)
    //   - MDM provisioner writing .mobileconfig or .webloc
    //   - locals { uuid = uuidv4() }
    //   - recovery_partition = "keep"

    /// Finds all custom templates (in the root) matching a base VM name.
    /// Returns empty array if none -- caller should fall back to the default.
    func customTemplates(for vmName: String) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: templatesRoot.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: templatesRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "hcl"
                   && !$0.lastPathComponent.hasPrefix(".")
                   && $0.lastPathComponent.contains(vmName.components(separatedBy: "-").prefix(4).joined(separator: "-")) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Returns the template path to actually use for building:
    ///   1. Provided customTemplate URL (user picked from multiple)
    ///   2. Single custom template in root matching the vm name
    ///   3. Default template in defaults/ subdirectory
    /// Returns a path relative to templatesRoot.
    func resolveTemplate(vmName: String, customOverride: URL? = nil) throws -> String {
        // Explicit override (user selected from picker)
        if let custom = customOverride {
            return custom.lastPathComponent
        }
        // Auto-detect single custom template
        let customs = try customTemplates(for: vmName)
        if customs.count == 1 {
            return customs[0].lastPathComponent
        }
        // Fall back to default
        return "defaults/\(vmName).pkr.hcl"
    }

    /// Writes the default .pkr.hcl to `packer-templates/defaults/`
        /// Writes the default .pkr.hcl to `packer-templates/defaults/` (never overwrites user edits).
    /// The .pkrvars.hcl vars file is always written fresh to the templates root (it's config, not code).
    /// Returns (templateName, varsName) where templateName is relative to templatesRoot.
    func writeTemplate(config: BuildConfig) throws -> (template: String, vars: String) {
        // Default templates live in a subdirectory -- user templates stay in the root
        let defaultsDir = templatesRoot.appendingPathComponent("defaults", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: templatesRoot, withIntermediateDirectories: true)

        let baseName     = "\(config.vmName).pkr.hcl"
        let templateName = "defaults/\(baseName)"   // always write default here
        let varsName     = "\(config.vmName).pkrvars.hcl"  // vars always refreshed
        let cpu          = config.cpuCount
        let mem          = config.memoryGB
        let disk         = config.diskGB

        let template = """
packer {
  required_plugins {
    tart = {
      version = ">= 1.20.0"
      source  = "github.com/cirruslabs/tart"
    }
  }
}

# VM Configuration
variable "vm_name" {
  type        = string
  default     = "\(config.vmName)"
  description = "Name of the virtual machine to create"
}

variable "ipsw_url" {
  type        = string
  default     = "\(config.ipswURL)"
  description = "URL or path to the macOS IPSW file"
}

# Account Configuration
variable "account_userName" {
  type        = string
  default     = "\(config.username)"
  description = "Username for the macOS account"
}

variable "account_password" {
  type        = string
  default     = env("OVEN_VM_PASSWORD")
  sensitive   = true
  description = "Password for the macOS account (set via OVEN_VM_PASSWORD env var)"
}

# MDM Enrollment Configuration
variable "enrollment_type" {
  type        = string
  default     = "\(config.enrollmentType)"
  description = "Enrollment type: profile or link"
}

variable "jamf_url" {
  type        = string
  default     = "\(config.jamfURL ?? "")"
  description = "Jamf Cloud URL e.g. https://instance.jamfcloud.com"
}

variable "mdm_invitation_id" {
  type        = string
  default     = "\(config.mdmInvitationID ?? "")"
  description = "MDM enrollment invitation ID"
}

# Feature Toggles (use string "true" / "false")
variable "enable_passwordless_sudo" {
  type    = string
  default = "\(config.enablePasswordlessSudo ? "true" : "false")"
}

variable "enable_auto_login" {
  type    = string
  default = "\(config.enableAutoLogin ? "true" : "false")"
}

variable "enable_safari_automation" {
  type    = string
  default = "true"
}

variable "enable_screenlock_disable" {
  type    = string
  default = "true"
}

variable "enable_spotlight_disable" {
  type    = string
  default = "true"
}

variable "enable_clipboard_sharing" {
  type    = string
  default = "false"
}

locals {
  uuid = uuidv4()
}

# -------------------------
# Source Definition
# -------------------------

source "tart-cli" "tart" {
  from_ipsw    = var.ipsw_url
  vm_name      = var.vm_name
  cpu_count    = \(cpu)
  memory_gb    = \(mem)
  disk_size_gb = \(disk)
  ssh_username = "${var.account_userName}"
  ssh_password = "${var.account_password}"
  ssh_timeout  = "180s"

  boot_command = [
    # Wait for VM to boot to language selection
    "<wait60s><spacebar>",
    # Switch to Italiano then back to English to reliably select English (US)
    "<wait30s>italiano<esc>english<enter>",
    # Select Your Country or Region
    "<wait30s><click 'Select Your Country or Region'><wait5s>united states<leftShiftOn><tab><leftShiftOff><spacebar>",
    # Transfer Your Data to This Mac
    "<wait10s><tab><tab><tab><spacebar><tab><tab><spacebar>",
    # Written and Spoken Languages
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Accessibility
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Data & Privacy
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Create a Mac Account
    "<wait10s><tab><tab><tab><tab><tab><tab>${var.account_userName}<tab>${var.account_userName}<tab>${var.account_password}<tab>${var.account_password}<tab><tab><spacebar><tab><tab><spacebar>",
    # Enable Voice Over
    "<wait120s><leftAltOn><f5><leftAltOff>",
    # Sign In with Your Apple ID
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Are you sure you want to skip signing in with an Apple ID?
    "<wait10s><tab><spacebar>",
    # Terms and Conditions
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # I have read and agree to the macOS Software License Agreement
    "<wait10s><tab><spacebar>",
    # Enable Location Services
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Are you sure you don't want to use Location Services?
    "<wait10s><tab><spacebar>",
    # Select Your Time Zone
    "<wait10s><tab><tab><tab>UTC<enter><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Analytics
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Screen Time
    "<wait10s><tab><tab><spacebar>",
    # Siri
    "<wait10s><tab><spacebar><leftShiftOn><tab><leftShiftOff><spacebar>",
    # FileVault
    "<wait10s><leftShiftOn><tab><tab><leftShiftOff><spacebar>",
    # Mac Data Will Not Be Securely Encrypted
    "<wait10s><tab><spacebar>",
    # Choose Your Look
    "<wait10s><leftShiftOn><tab><leftShiftOff><spacebar>",
    # Update Mac Automatically
    "<wait10s><tab><tab><spacebar>",
    # Welcome to Mac
    "<wait30s><spacebar>",
    # Disable Voice Over
    "<wait10s><leftAltOn><f5><leftAltOff>",
    # Enable Keyboard navigation and open System Settings
    "<wait10s><leftAltOn><spacebar><leftAltOff>Terminal<wait10s><enter>",
    "<wait10s>defaults write NSGlobalDomain AppleKeyboardUIMode -int 3<enter>",
    # Open System Settings > Sharing
    "<wait10s>open '/System/Applications/System Settings.app'<enter>",
    "<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Sharing<enter>",
    # Enable Screen Sharing
    "<wait10s><tab><tab><tab><tab><tab><spacebar>",
    # Enable Remote Login (SSH)
    "<wait10s><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><tab><spacebar>",
    # Quit System Settings
    "<wait10s><leftAltOn>q<leftAltOff>",
    # Disable Gatekeeper
    "<wait10s>sudo spctl --global-disable<enter>",
    "<wait10s>${var.account_password}<enter>",
    # Open System Settings > Privacy & Security to confirm Gatekeeper off
    "<wait10s>open '/System/Applications/System Settings.app'<enter>",
    "<wait10s><leftCtrlOn><f2><leftCtrlOff><right><right><right><down>Privacy & Security<enter>",
    "<wait10s><leftShiftOn><tab><tab><tab><tab><tab><tab><leftShiftOff>",
    "<wait10s><down><wait1s><down><wait1s><enter>",
    "<wait10s>${var.account_password}<enter>",
    "<wait10s><leftShiftOn><tab><leftShiftOff><wait1s><spacebar>",
    "<wait10s><leftAltOn>q<leftAltOff>",
  ]

  headless = \(config.showGraphics ? "false" : "true")

  run_extra_args = [
    "--no-audio",
  ]

  create_grace_time = "30s"
  recovery_partition = "keep"
}

# -------------------------
# Build Section
# -------------------------
build {
  sources = ["source.tart-cli.tart"]

  provisioner "shell" {
    inline = [
      "set -euxo pipefail",

      # Passwordless sudo
      "if [ \\"${var.enable_passwordless_sudo}\\" = \\"true\\" ]; then",
      "  echo \\"Enabling passwordless sudo...\\"",
      "  echo ${var.account_password} | sudo -S sh -c \\"mkdir -p /etc/sudoers.d/; echo '${var.account_userName} ALL=(ALL) NOPASSWD: ALL' | EDITOR=tee visudo /etc/sudoers.d/${var.account_userName}-nopasswd\\"",
      "fi",

      # Auto-login
      "if [ \\"${var.enable_auto_login}\\" = \\"true\\" ]; then",
      "  curl https://raw.githubusercontent.com/karthikeyan-mac/Virtualization_macOS/refs/heads/main/kcpasswordgen.sh -o /tmp/kcpasswordgen.sh",
      "  encoded_value=\\"$(bash /tmp/kcpasswordgen.sh ${var.account_password})\\"",
      "  echo \\"$encoded_value\\" | sudo xxd -r - /etc/kcpassword",
      "  sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser ${var.account_userName}",
      "fi",

      # Screensaver disable
      "echo \\"Disabling screensaver...\\"",
      "sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime 0",
      "defaults -currentHost write com.apple.screensaver idleTime 0",

      # Prevent sleep
      "echo \\"Preventing system sleep...\\"",
      "sudo systemsetup -setsleep Off 2>/dev/null",

      # Safari automation
      "if [ \\"${var.enable_safari_automation}\\" = \\"true\\" ]; then",
      "  echo \\"Enabling Safari automation...\\"",
      "  /Applications/Safari.app/Contents/MacOS/Safari &",
      "  SAFARI_PID=$!",
      "  disown",
      "  sleep 30",
      "  kill -9 $SAFARI_PID",
      "  sudo safaridriver --enable",
      "fi",

      # Screen lock disable
      "if [ \\"${var.enable_screenlock_disable}\\" = \\"true\\" ]; then",
      "  echo \\"Disabling screen lock...\\"",
      "  sysadminctl -screenLock off -password ${var.account_password}",
      "fi",

      # Spotlight disable
      "if [ \\"${var.enable_spotlight_disable}\\" = \\"true\\" ]; then",
      "  echo \\"Disabling Spotlight indexing...\\"",
      "  sudo mdutil -a -i off",
      "fi",

      # Clipboard sharing via tart guest agent
      "if [ \\"${var.enable_clipboard_sharing}\\" = \\"true\\" ]; then",
      "  echo \\"Installing tart guest agent...\\"",
      "  /bin/bash -c \\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\"",
      "  /opt/homebrew/bin/brew install cirruslabs/cli/tart-guest-agent",
      "  curl https://raw.githubusercontent.com/cirruslabs/macos-image-templates/refs/heads/main/data/tart-guest-agent.plist -o tart-guest-agent.plist",
      "  sudo mv tart-guest-agent.plist /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist",
      "  sudo chown -R root:wheel /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist",
      "fi",

      # Set a random computer name
      "computerName=\\"VM-TART-$(jot -r 1 1000 9999)\\"",
      "sudo scutil --set HostName $computerName",
      "sudo scutil --set LocalHostName $computerName",
      "sudo scutil --set ComputerName $computerName",
    ]
  }

  provisioner "shell" {
    inline = [
      "set -euxo pipefail",
      "if [ \\"${var.enrollment_type}\\" = \\"profile\\" ]; then",
      "  cat << 'MCONFIG' > ~/Desktop/mdm_enroll.mobileconfig",
      "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>",
      "<!DOCTYPE plist PUBLIC \\"-//Apple//DTD PLIST 1.0//EN\\" \\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\\">",
      "<plist version=\\"1.0\\">",
      "    <dict>",
      "        <key>PayloadUUID</key>",
      "        <string>${local.uuid}</string>",
      "        <key>PayloadOrganization</key>",
      "        <string>JAMF Software</string>",
      "        <key>PayloadVersion</key>",
      "        <integer>1</integer>",
      "        <key>PayloadIdentifier</key>",
      "        <string>${local.uuid}</string>",
      "        <key>PayloadType</key>",
      "        <string>Profile Service</string>",
      "        <key>PayloadDisplayName</key>",
      "        <string>MDM Profile</string>",
      "        <key>PayloadContent</key>",
      "        <dict>",
      "            <key>Challenge</key>",
      "            <string>${var.mdm_invitation_id}</string>",
      "            <key>URL</key>",
      "            <string>${var.jamf_url}/enroll/profile</string>",
      "            <key>DeviceAttributes</key>",
      "            <array>",
      "                <string>UDID</string>",
      "                <string>SERIAL</string>",
      "                <string>VERSION</string>",
      "                <string>DEVICE_NAME</string>",
      "            </array>",
      "        </dict>",
      "    </dict>",
      "</plist>",
      "MCONFIG",
      "elif [ \\"${var.enrollment_type}\\" = \\"link\\" ]; then",
      "  cat << 'WLOC' > ~/Desktop/Enroll_Your_Mac.webloc",
      "<?xml version=\\"1.0\\" encoding=\\"UTF-8\\"?>",
      "<plist version=\\"1.0\\">",
      "<dict>",
      "    <key>URL</key>",
      "    <string>${var.jamf_url}/enroll?invitation=${var.mdm_invitation_id}</string>",
      "</dict>",
      "</plist>",
      "WLOC",
      "fi",
    ]
  }
}
"""

        let vars = """
# -------------------------
# Oven Variables File -- \(config.vmName)
# -------------------------
# Do NOT commit this file if it contains sensitive values.
# Add *.pkrvars.hcl to .gitignore

vm_name           = "\(config.vmName)"
ipsw_url          = "\(config.ipswURL)"
account_userName  = "\(config.username)"
# account_password is NOT set here -- it is read from the OVEN_VM_PASSWORD
# environment variable via the variable default in the .pkr.hcl template.
enrollment_type   = "\(config.enrollmentType)"
jamf_url          = "\(config.jamfURL ?? "")"
mdm_invitation_id = "\(config.mdmInvitationID ?? "")"

enable_passwordless_sudo  = "\(config.enablePasswordlessSudo ? "true" : "false")"
enable_auto_login         = "\(config.enableAutoLogin ? "true" : "false")"
enable_safari_automation  = "true"
enable_screenlock_disable = "true"
enable_spotlight_disable  = "true"
enable_clipboard_sharing  = "false"
"""

        // Write default template to defaults/ subdirectory
        try template.write(to: defaultsDir.appendingPathComponent(baseName),
                           atomically: true, encoding: .utf8)
        // Always refresh the vars file (it contains current config, not user-editable code)
        try vars.write(to: templatesRoot.appendingPathComponent(varsName),
                       atomically: true, encoding: .utf8)
        return (templateName, varsName)
    }
}
