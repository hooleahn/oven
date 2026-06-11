# Building Base VMs

A **Base VM** is a fully provisioned macOS image that serves as the source for cloning. You build one once, then clone it into as many VMs as you need — each clone starts from a known-good state in seconds.

Oven uses [Packer](https://www.packer.io) with the [Tart Packer plugin](https://github.com/cirruslabs/packer-plugin-tart) to build base images.

---

## Overview of the Build Process

```
IPSW (macOS firmware)
        │
        ▼
  Packer template (.pkr.hcl)
  + optional variables (.pkrvars.hcl)
  + building blocks (provisioners)
        │
        ▼
  packer init → packer validate → packer build
        │
        ▼
  Base VM (local Tart image)
        │
        ▼
  (optional) Push to OCI registry
```

---

## Creating a Base VM

1. Navigate to **Base VMs** in the sidebar.
2. Click **+** to open the **New Base VM** sheet.
3. Choose a build path:

### Path A: From a Packer Template (Recommended)

Select an existing template from the [Template Library](Templates-and-Building-Blocks). Oven ships with vanilla templates from [CirrusLabs](https://github.com/cirruslabs/macos-image-templates) for:
- macOS Tahoe (26)
- macOS Sequoia (15)
- macOS Sonoma (14)
- macOS Ventura (13)
- macOS Monterey (12)

Configure:
- **Display Name** — human-readable name for this base image
- **Tart Name** — identifier on disk
- **macOS Version** — must match the template
- **Template Variables** — if the template has a `.pkrvars.hcl` companion, link it here
- **Building Blocks** — add reusable provisioner snippets (see below)

### Path B: Manual Build Configuration

For advanced users who want full HCL control:

1. Choose **Manual Build**.
2. Configure hardware (CPU, memory, disk), OS version, and IPSW source.
3. Toggle provisioning options individually (see [Provisioning Options](#provisioning-options) below).
4. Oven generates the HCL on the fly from your selections.

---

## Provisioning Options

These toggles are available in both template-based and manual builds:

| Option | What It Does |
|---|---|
| **Passwordless Sudo** | Configures the build user to run `sudo` without a password prompt |
| **Auto Login** | Sets the user account to log in automatically on boot |
| **Install Homebrew** | Installs the Homebrew package manager |
| **Install Xcode CLI Tools** | Runs `xcode-select --install` |
| **Enable SSH** | Enables the SSH server (Remote Login) in macOS |
| **Disable Screen Lock** | Turns off the screen lock / screensaver |
| **Disable Sleep** | Prevents the VM from sleeping |
| **Disable Spotlight** | Turns off Spotlight indexing |
| **Safari Automation** | Enables WebDriver support for Safari |
| **Install Tart Guest Agent** | Installs the Tart guest agent for host↔VM communication |
| **Install Rosetta** | Installs Rosetta 2 (Apple Silicon VMs only) |
| **Random Computer Name** | Sets a random hostname on each boot (useful for MDM enrollment) |

These correspond to **Building Blocks** in the template system and can be combined freely.

---

## Building Blocks

Building Blocks are reusable HCL provisioner snippets you can attach to any build. Oven ships 10 seeded blocks:

1. Passwordless Sudo
2. Auto Login
3. Homebrew
4. Xcode CLI Tools
5. SSH
6. Disable Spotlight
7. Screen Lock
8. Safari Automation
9. Random Computer Name
10. File Upload

You can also create custom building blocks. See [Templates & Building Blocks](Templates-and-Building-Blocks#building-blocks) for details.

---

## Boot Commands

Oven automates the macOS Setup Assistant by sending keystroke sequences via Packer's `boot_command`. You can customize these sequences in the **Boot Commands** editor within a base VM's configuration.

The default boot command block navigates through the Setup Assistant screens — language selection, network, Apple ID skip, license agreement, account creation — and is tuned for each macOS version.

---

## Running a Build

1. Open the base VM in the detail pane.
2. Click **Build**.
3. Oven runs `packer init`, `packer validate`, then `packer build` in sequence.
4. Live output streams into the **Build Log** panel in real time.
5. A notification fires when the build completes or fails (if [Notifications](Notifications) are configured).

### Build Completion Actions

In [Preferences → Build](Preferences#build), you can configure what happens after a successful build:
- **Do Nothing** (default)
- **Lock Screen**
- **Shut Down Mac**

---

## Validating a Template

Before running a full build, click **Validate** in the detail pane. Oven runs `packer validate` and shows any errors inline. This is faster than a full build for catching HCL syntax or variable issues. Only syntax is validated. Boot commands and building blocks can fail as `packer validate` doesn't catch these issues.

---

## Build History

Each base VM keeps a history of past builds. In the detail pane, open the **Build History** tab to see:
- Build date and time
- macOS version built
- Duration
- Success or failure

---

## After the Build

Once built, the base VM appears in the **Base VMs** list with a status badge. From there you can:
- **Clone** it into one or more VMs
- **Push** it to an OCI registry to share with teammates — see [OCI Registry](OCI-Registry)
- **Rebuild** it to pick up a newer macOS patch release

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| Build fails immediately | Missing dependency | Check [Preferences → Tools](Preferences#tools); try re-downloading tools |
| `packer validate` errors | HCL syntax issue | Open the template in the HCL editor and look for red markers |
| Build hangs at Setup Assistant | Boot command timing | Adjust boot command delays or use a newer template version |
| IPSW download fails | Network or ipsw.me outage | Try switching to mist-cli in [Preferences → Build](Preferences#build) |
| Packer plugin not found | Plugin not initialized | Run **Validate** first — it triggers `packer init` which downloads the plugin |
