import Foundation

// MARK: - ManualBuildHCLGenerator
//
// Produces a valid .pkr.hcl file from a ManualBuildConfig.
// The generator is a pure function — no I/O, no side effects.
// Call generate(config:bootCommand:) and write the result to disk.

struct ManualBuildHCLGenerator {

    // MARK: - Entry point

    /// Generates a complete .pkr.hcl string.
    ///
    /// - Parameters:
    ///   - config: The build configuration populated by the UI.
    ///   - bootCommand: The resolved BootCommandBlock, or nil if Setup
    ///     Assistant automation is disabled.
    ///   - resolvedIPSW: The IPSW URL string to embed. For IPSWSource.auto
    ///     the caller must resolve the URL before calling this method.
    ///   - jamfURL: Resolved Jamf / MDM server URL, or nil if no enrollment.
    ///   - mdmInvitationID: Resolved MDM invitation ID, or nil if no enrollment.
    static func generate(
        config: ManualBuildConfig,
        bootCommand: BootCommandBlock?,
        resolvedIPSW: String,
        jamfURL: String? = nil,
        mdmInvitationID: String? = nil
    ) -> String {
        var parts: [String] = []

        parts.append(pluginBlock())
        parts.append(variableBlock(config: config, ipswURL: resolvedIPSW,
                                   jamfURL: jamfURL, mdmInvitationID: mdmInvitationID))
        parts.append(localsBlock())
        parts.append(sourceBlock(config: config, bootCommand: bootCommand))
        parts.append(buildBlock(config: config, jamfURL: jamfURL, mdmInvitationID: mdmInvitationID))

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Plugin block

    private static func pluginBlock() -> String {
        """
        packer {
          required_plugins {
            tart = {
              version = ">= 1.20.0"
              source  = "github.com/cirruslabs/tart"
            }
          }
        }
        """
    }

    // MARK: - Variable declarations

    private static func variableBlock(config: ManualBuildConfig, ipswURL: String,
                                       jamfURL: String?, mdmInvitationID: String?) -> String {
        var lines = [
            "variable \"vm_name\" {",
            "  type    = string",
            "  default = \"\(config.tartName)\"",
            "}",
            "",
            "variable \"ipsw_url\" {",
            "  type    = string",
            "  default = \"\(ipswURL)\"",
            "}",
        ]

        if config.automateSetupAssistant {
            lines += [
                "",
                "variable \"account_userName\" {",
                "  type    = string",
                "  default = \"\(config.credentials.username)\"",
                "}",
                "",
                "variable \"account_password\" {",
                "  type      = string",
                "  default   = env(\"OVEN_VM_PASSWORD\")",
                "  sensitive = true",
                "}",
            ]

            if jamfURL != nil || mdmInvitationID != nil {
                let jamfURLValue = jamfURL ?? ""
                let invitationIDValue = mdmInvitationID ?? ""
                lines += [
                    "",
                    "variable \"jamf_url\" {",
                    "  type    = string",
                    "  default = \"\(jamfURLValue)\"",
                    "  description = \"MDM server URL\"",
                    "}",
                    "",
                    "variable \"mdm_invitation_id\" {",
                    "  type    = string",
                    "  default = \"\(invitationIDValue)\"",
                    "  description = \"MDM enrollment invitation ID\"",
                    "}",
                ]
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Locals

    private static func localsBlock() -> String {
        """
        locals {
          uuid = uuidv4()
        }
        """
    }

    // MARK: - Source block

    private static func sourceBlock(
        config: ManualBuildConfig,
        bootCommand: BootCommandBlock?
    ) -> String {
        var lines = [
            "source \"tart-cli\" \"tart\" {",
            "  from_ipsw    = var.ipsw_url",
            "  vm_name      = var.vm_name",
            "  cpu_count    = \(config.cpuCount)",
            "  memory_gb    = \(config.memoryGB)",
            "  disk_size_gb = \(config.diskGB)",
        ]

        if config.automateSetupAssistant {
            lines += [
                "  ssh_username = \"${var.account_userName}\"",
                "  ssh_password = \"${var.account_password}\"",
                "  ssh_timeout  = \"180s\"",
            ]
        }

        if let cmd = bootCommand, !cmd.commandLines.isEmpty {
            lines.append("")
            lines.append("  boot_command = [")
            for (i, line) in cmd.commandLines.enumerated() {
                let comma = i < cmd.commandLines.count - 1 ? "," : ""
                lines.append("    \(line)\(comma)")
            }
            lines.append("  ]")
        }

        lines += [
            "",
            "  headless = true",
            "  run_extra_args = [\"--no-audio\"]",
            "  create_grace_time = \"30s\"",
            "  recovery_partition = \"keep\"",
            "}",
        ]

        return lines.joined(separator: "\n")
    }

    // MARK: - Build block

    private static func buildBlock(config: ManualBuildConfig,
                                    jamfURL: String?, mdmInvitationID: String?) -> String {
        var lines = [
            "build {",
            "  sources = [\"source.tart-cli.tart\"]",
        ]

        if config.automateSetupAssistant {
            let provisioners = provisionerLines(config: config)
            if !provisioners.isEmpty {
                lines.append("")
                lines.append(contentsOf: provisioners)
            }

            let uploads = fileUploadLines(config: config)
            if !uploads.isEmpty {
                lines.append("")
                lines.append(contentsOf: uploads)
            }

            // MDM enrollment provisioner (last — after all other setup)
            if jamfURL != nil || mdmInvitationID != nil {
                lines.append("")
                lines.append(contentsOf: mdmProvisionerLines())
            }
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    // MARK: - MDM enrollment provisioner

    private static func mdmProvisionerLines() -> [String] {
        [
            "  # MDM enrollment",
            "  provisioner \"shell\" {",
            "    inline = [",
            "      \"cat << 'MCONFIG' > ~/Desktop/mdm_enroll.mobileconfig\",",
            "      \"<?xml version=\\\"1.0\\\" encoding=\\\"UTF-8\\\"?>\",",
            "      \"<!DOCTYPE plist PUBLIC \\\"-//Apple//DTD PLIST 1.0//EN\\\" \\\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\\\">\",",
            "      \"<plist version=\\\"1.0\\\">\",",
            "      \"  <dict>\",",
            "      \"    <key>PayloadContent</key>\",",
            "      \"    <dict>\",",
            "      \"      <key>Challenge</key>\",",
            "      \"      <string>${var.mdm_invitation_id}</string>\",",
            "      \"      <key>URL</key>\",",
            "      \"      <string>${var.jamf_url}/enroll/profile</string>\",",
            "      \"    </dict>\",",
            "      \"  </dict>\",",
            "      \"</plist>\",",
            "      \"MCONFIG\",",
            "      \"open ~/Desktop/mdm_enroll.mobileconfig\",",
            "      \"sleep 30\",",
            "    ]",
            "  }",
        ]
    }

    // MARK: - Provisioner lines (dependency-ordered)

    private static func provisionerLines(config: ManualBuildConfig) -> [String] {
        let p = config.provisioning
        var inline: [String] = []

        inline.append("  \"set -euo pipefail\",")

        // 1. Passwordless sudo — must be first so subsequent steps can use sudo freely
        if p.passwordlessSudo {
            inline.append(contentsOf: [
                "  # Passwordless sudo",
                "  \"echo ${var.account_password} | sudo -S sh -c \\\\\"mkdir -p /etc/sudoers.d/; echo '${var.account_userName} ALL=(ALL) NOPASSWD: ALL' | EDITOR=tee visudo /etc/sudoers.d/${var.account_userName}-nopasswd\\\\\"\",",
            ])
        }

        // 2. Auto-login
        if p.autoLogin {
            inline.append(contentsOf: [
                "  # Auto-login via kcpassword",
                "  \"curl -fsSL https://raw.githubusercontent.com/karthikeyan-mac/Virtualization_macOS/refs/heads/main/kcpasswordgen.sh -o /tmp/kcpasswordgen.sh\",",
                "  \"encoded_value=\\\\\"$(bash /tmp/kcpasswordgen.sh ${var.account_password})\\\\\"\",",
                "  \"echo \\\\\"$encoded_value\\\\\" | sudo xxd -r - /etc/kcpassword\",",
                "  \"sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser ${var.account_userName}\",",
            ])
        }

        // 3. Disable sleep / screensaver
        if p.disableSleep {
            inline.append(contentsOf: [
                "  # Disable sleep and screensaver",
                "  \"sudo defaults write /Library/Preferences/com.apple.screensaver loginWindowIdleTime 0\",",
                "  \"defaults -currentHost write com.apple.screensaver idleTime 0\",",
                "  \"sudo systemsetup -setsleep Off 2>/dev/null\",",
            ])
        }

        // 4. Disable screen lock
        if p.disableScreenLock {
            inline.append(contentsOf: [
                "  # Disable screen lock",
                "  \"sysadminctl -screenLock off -password ${var.account_password}\",",
            ])
        }

        // 5. Disable Spotlight
        if p.disableSpotlight {
            inline.append(contentsOf: [
                "  # Disable Spotlight indexing",
                "  \"sudo mdutil -a -i off\",",
            ])
        }

        // 6. CLI tools
        if p.installCLITools {
            inline.append(contentsOf: [
                "  # Xcode Command Line Tools",
                "  \"xcode-select --install || true\",",
                "  \"while ! xcode-select -p &>/dev/null; do sleep 5; done\",",
                "  \"sudo xcodebuild -license accept || true\",",
            ])
        }

        // 7. Homebrew (requires CLI tools)
        if p.installHomebrew {
            inline.append(contentsOf: [
                "  # Homebrew",
                "  \"/bin/bash -c \\\\\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\\\\"\",",
                "  \"echo 'eval \\\\\"$(/opt/homebrew/bin/brew shellenv)\\\\\"' >> ~/.zprofile\",",
                "  \"eval \\\\\"$(/opt/homebrew/bin/brew shellenv)\\\\\"\",",
            ])
        }

        // 8. Xcode (requires Homebrew)
        if p.installXcode {
            inline.append(contentsOf: [
                "  # Xcode (via Homebrew cask)",
                "  \"/opt/homebrew/bin/brew install --cask xcode\",",
                "  \"sudo xcodebuild -license accept\",",
                "  \"xcodebuild -runFirstLaunch || true\",",
            ])
        }

        // 9. Safari automation
        if p.safariAutomation {
            inline.append(contentsOf: [
                "  # Safari automation",
                "  \"/Applications/Safari.app/Contents/MacOS/Safari &\",",
                "  \"SAFARI_PID=$!\",",
                "  \"disown\",",
                "  \"sleep 30\",",
                "  \"kill -9 $SAFARI_PID || true\",",
                "  \"sudo safaridriver --enable\",",
            ])
        }

        // 10. Tart guest agent (requires Homebrew)
        if p.tartGuestAgent {
            inline.append(contentsOf: [
                "  # Tart guest agent",
                "  \"/opt/homebrew/bin/brew install cirruslabs/cli/tart-guest-agent\",",
                "  \"curl -fsSL https://raw.githubusercontent.com/cirruslabs/macos-image-templates/refs/heads/main/data/tart-guest-agent.plist -o tart-guest-agent.plist\",",
                "  \"sudo mv tart-guest-agent.plist /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist\",",
                "  \"sudo chown -R root:wheel /Library/LaunchAgents/org.cirruslabs.tart-guest-agent.plist\",",
            ])
        }

        guard !inline.isEmpty else { return [] }

        var block = [
            "  provisioner \"shell\" {",
            "    inline = [",
        ]
        block.append(contentsOf: inline.map { "      \($0)" })
        block += [
            "    ]",
            "  }",
        ]
        return block
    }

    // MARK: - File upload provisioners

    private static func fileUploadLines(config: ManualBuildConfig) -> [String] {
        config.provisioning.fileUploads.flatMap { upload -> [String] in
            guard !upload.sourcePath.isEmpty, !upload.destinationPath.isEmpty else { return [] }
            return [
                "  provisioner \"file\" {",
                "    source      = \"\(upload.sourcePath)\"",
                "    destination = \"\(upload.destinationPath)\"",
                "  }",
            ]
        }
    }
}
