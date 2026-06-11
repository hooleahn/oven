# Getting Started

## Requirements

| Requirement | Minimum | Recommended |
|---|---|---|
| macOS | 14.0 (Ventura) | 15+ (Sequoia) |
| CPU | Any Apple Silicon | M2 or later |
| RAM | 8 GB | 16 GB or more |
| Disk | 50 GB free | 100 GB+ free |
| Xcode | 15.4 (build from source only) | Latest stable |


---

## Installation

### Pre-built Release

Download the latest `.pkg` from the [Releases](../../releases) page, run it, then look for **Oven.app** in your Applications folder.

### Build from Source

1. Clone the repository and open the project:

   ```bash
   git clone https://github.com/<your-org>/Oven.git
   cd Oven
   open Oven.xcodeproj
   ```

2. In Xcode, select your development team under **Signing & Capabilities**.
3. Build and run with **⌘R**.

---

## First Launch & Onboarding

On first launch Oven displays an **Onboarding** screen that walks you through initial setup:

### Step 1 — Choose a Storage Location

Oven stores VMs, IPSW firmware files, and Packer templates in directories on your Mac. You can accept the defaults or choose custom locations in the onboarding wizard (and change them later in [Preferences → Storage](Preferences#storage)).

Default locations:
- **VMs:** `~/.tart/` (managed by Tart)
- **IPSW files:** `~/Library/Application Support/Oven/ipsw/`
- **Packer templates:** `~/Library/Application Support/Oven/packer/`

### Step 2 — Dependency Check

Oven requires five command-line tools. By default it manages them itself:

| Tool | Purpose |
|---|---|
| `tart` | VM hypervisor |
| `packer` | Infrastructure-as-code provisioning |
| `mist-cli` | Alternative macOS firmware listing |
| `jq` | JSON parsing within build pipelines |
| `sshpass` | Password-based SSH to VMs |

Click **Download Tools** and Oven fetches the correct versions automatically. You can also point Oven at tools you already have installed — see [Preferences → Tools](Preferences#tools).

### Step 3 — Ready

Once all dependencies show a green checkmark, click **Get Started**. The main window opens.

---

## Main Window Layout

Oven uses a three-column layout:

```
┌─────────────┬──────────────────────┬────────────────────────────┐
│  Sidebar    │  List                │  Detail Pane               │
│             │                      │                            │
│  VMs        │  List of VMs or      │  Selected item's details,  │
│  Base VMs   │  Base VMs or         │  actions, and config       │
│  Installers │  Installers, etc.    │                            │
│  Registry   │                      │                            │
│  Log        │                      │                            │
└─────────────┴──────────────────────┴────────────────────────────┘
```

- **Sidebar** — switch between sections
- **List** — browse items in the selected section
- **Detail Pane** — view and edit the selected item; perform actions like start, stop, SSH, build

---

## Menu Bar Extra

Oven adds an icon to your macOS menu bar. Click it to:

- See which VMs are currently running
- Start or stop VMs without bringing the main window forward
- Open the main window

The menubar extra lists most-recently launched VMs, and you can additionally pin VMs to the menubar for quick access.

---

## OS Permissions

Oven needs the following permissions

- Disk Access – If VMs are stored in a different path than the default one.
- Local Network Access – Required for connecting via SSH to VMs.

Those are it off the top of my head. Holler if you see any other being requested.

---

## Next Steps

- [Build a base image](Building-Base-VMs)
- [Create your first VM](Virtual-Machines#creating-a-vm)
- [Set up notifications](Notifications)

---

## Reporting Issues and Feedback

You can create an issue in this repository or let's chat over at the #oven-beta channel in the MacAdmins Slack!
