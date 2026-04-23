import Foundation

// MARK: - BuildingBlock

/// A reusable HCL snippet for a Packer provisioner block.
/// Building blocks are app-managed and stored in AppDatabase — they are
/// not standalone Packer files and cannot be built on their own.
struct BuildingBlock: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var blockDescription: String
    var provisioner: ProvisionerType
    var hclContent: String
    var isBase: Bool          // true = seeded by Oven, read-only
    var createdAt: Date
    /// OS compatibility filter. Empty string = compatible with any OS / version.
    var osName: String        // MacOSRelease.Name.rawValue or ""
    var osVersion: String     // e.g. "15.6", "" = any version

    enum ProvisionerType: String, Codable, CaseIterable {
        case shell       = "shell"
        case shellLocal  = "shell-local"
        case file        = "file"
        case breakpoint  = "breakpoint"
        case custom      = "custom"

        var label: String {
            switch self {
            case .shell:      return "Shell"
            case .shellLocal: return "Shell (local)"
            case .file:       return "File"
            case .breakpoint: return "Breakpoint"
            case .custom:     return "Custom"
            }
        }

        var systemImage: String {
            switch self {
            case .shell, .shellLocal: return "terminal"
            case .file:               return "doc.badge.arrow.up"
            case .breakpoint:         return "pause.circle"
            case .custom:             return "puzzlepiece"
            }
        }
    }

    init(id: UUID = UUID(), displayName: String, blockDescription: String,
         provisioner: ProvisionerType, hclContent: String,
         isBase: Bool = false, createdAt: Date = Date(),
         osName: String = "", osVersion: String = "") {
        self.id = id
        self.displayName = displayName
        self.blockDescription = blockDescription
        self.provisioner = provisioner
        self.hclContent = hclContent
        self.isBase = isBase
        self.createdAt = createdAt
        self.osName = osName
        self.osVersion = osVersion
    }
}

// MARK: - BootCommandBlock

/// A reusable boot_command sequence for the Tart source block.
/// Encodes the key-presses that automate the macOS Setup Assistant.
/// Like BuildingBlock, base entries are seeded by Oven; users can fork
/// and customise them to handle OS-specific Setup Assistant variations.
struct BootCommandBlock: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var blockDescription: String
    /// Raw HCL lines that appear inside boot_command = [ ... ].
    /// Each string is one entry in the array, already quoted and escaped
    /// for HCL — the generator joins them with ",\n" and wraps the block.
    var commandLines: [String]
    var isBase: Bool
    var createdAt: Date
    /// OS compatibility. Empty = any OS / version.
    var osName: String
    var osVersion: String

    init(id: UUID = UUID(), displayName: String, blockDescription: String,
         commandLines: [String], isBase: Bool = false, createdAt: Date = Date(),
         osName: String = "", osVersion: String = "") {
        self.id = id
        self.displayName = displayName
        self.blockDescription = blockDescription
        self.commandLines = commandLines
        self.isBase = isBase
        self.createdAt = createdAt
        self.osName = osName
        self.osVersion = osVersion
    }
}

// MARK: - Seeded base building blocks

extension BuildingBlock {
    static let baseBlocks: [BuildingBlock] = [
        BuildingBlock(
            displayName: "Passwordless Sudo",
            blockDescription: "Grants the VM account full sudo access without a password prompt. Run this early so subsequent provisioners can use sudo freely.",
            provisioner: .shell,
            hclContent: """
  provisioner "shell" {
    inline = [
      "echo ${var.account_password} | sudo -S sh -c \\"mkdir -p /etc/sudoers.d/; echo '${var.account_userName} ALL=(ALL) NOPASSWD: ALL' | EDITOR=tee visudo /etc/sudoers.d/${var.account_userName}-nopasswd\\""
    ]
  }
""",
            isBase: true
        ),
        BuildingBlock(
            displayName: "Auto Login",
            blockDescription: "Configures the VM to log in automatically as the build account on boot. Uses kcpassword encoding for macOS compatibility.",
            provisioner: .shell,
            hclContent: """
  provisioner "shell" {
    inline = [
      "curl -fsSL https://raw.githubusercontent.com/karthikeyan-mac/Virtualization_macOS/refs/heads/main/kcpasswordgen.sh -o /tmp/kcpasswordgen.sh",
      "encoded_value=\\"$(bash /tmp/kcpasswordgen.sh ${var.account_password})\\"",
      "echo \\"$encoded_value\\" | sudo xxd -r - /etc/kcpassword",
      "sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser ${var.account_userName}"
    ]
  }
""",
            isBase: true
        ),
        BuildingBlock(
            displayName: "Homebrew Install",
            blockDescription: "Installs Homebrew package manager at /opt/homebrew. Required before using brew in subsequent provisioners.",
            provisioner: .shell,
            hclContent: """
  provisioner "shell" {
    inline = [
      "/bin/bash -c \\"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\\"",
      "echo 'eval \\"$(/opt/homebrew/bin/brew shellenv)\\"' >> ~/.zprofile",
      "eval \\"$(/opt/homebrew/bin/brew shellenv)\\""
    ]
  }
""",
            isBase: true
        ),
        BuildingBlock(
            displayName: "Xcode Command Line Tools",
            blockDescription: "Installs Xcode Command Line Tools and accepts the license. Required for compiling software and using git.",
            provisioner: .shell,
            hclContent: """
  provisioner "shell" {
    inline = [
      "xcode-select --install || true",
      "while ! xcode-select -p &>/dev/null; do sleep 5; done",
      "sudo xcodebuild -license accept"
    ]
  }
""",
            isBase: true
        ),
        BuildingBlock(
            displayName: "Enable SSH Daemon",
            blockDescription: "Enables Remote Login (SSH) via systemsetup. Useful when SSH is not already active inside the VM.",
            provisioner: .shell,
            hclContent: """
  provisioner "shell" {
    inline = [
      "sudo systemsetup -setremotelogin on"
    ]
  }
""",
            isBase: true
        ),
        BuildingBlock(
            displayName: "Disable Spotlight Indexing",
            blockDescription: "Turns off Spotlight indexing on all volumes. Reduces CPU and disk activity in CI/build VMs.",
            provisioner: .shell,
            hclContent: """
  provisioner "shell" {
    inline = [
      "sudo mdutil -a -i off"
    ]
  }
""",
            isBase: true
        ),
        BuildingBlock(
            displayName: "Disable Screen Lock",
            blockDescription: "Disables the screen lock so headless VMs don't lock during long builds.",
            provisioner: .shell,
            hclContent: """
  provisioner "shell" {
    inline = [
      "sysadminctl -screenLock off -password ${var.account_password}"
    ]
  }
""",
            isBase: true
        ),
        BuildingBlock(
            displayName: "Safari Automation",
            blockDescription: "Enables Safari WebDriver for UI automation and testing. Launches Safari once to initialize, then enables safaridriver.",
            provisioner: .shell,
            hclContent: """
  provisioner "shell" {
    inline = [
      "/Applications/Safari.app/Contents/MacOS/Safari &",
      "SAFARI_PID=$!",
      "disown",
      "sleep 30",
      "kill -9 $SAFARI_PID || true",
      "sudo safaridriver --enable"
    ]
  }
""",
            isBase: true
        ),
        BuildingBlock(
            displayName: "Random Computer Name",
            blockDescription: "Sets a unique random hostname, LocalHostName, and ComputerName. Prevents name collisions when cloning multiple VMs.",
            provisioner: .shell,
            hclContent: """
  provisioner "shell" {
    inline = [
      "computerName=\\"VM-TART-$(jot -r 1 1000 9999)\\"",
      "sudo scutil --set HostName $computerName",
      "sudo scutil --set LocalHostName $computerName",
      "sudo scutil --set ComputerName $computerName"
    ]
  }
""",
            isBase: true
        ),
        BuildingBlock(
            displayName: "File Upload",
            blockDescription: "Uploads a local file or directory into the VM at a specified destination path. Edit source and destination before using.",
            provisioner: .file,
            hclContent: """
  provisioner "file" {
    source      = "path/to/local/file"
    destination = "/tmp/uploaded-file"
  }
""",
            isBase: true
        ),
    ]
}
