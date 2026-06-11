# Oven

**Oven** is a native macOS application for building and managing macOS virtual machines. It provides a polished GUI around industry-standard tools — [Tart](https://tart.run), [Packer](https://www.packer.io), and [mist-cli](https://github.com/ninxsoft/mist-cli) — so you can provision, clone, and operate macOS VMs without wrestling with the command line.

---

## What Oven Does

| Task | How Oven Helps |
|---|---|
| Run macOS VMs locally | Start, stop, suspend, and SSH into Tart VMs from a native UI |
| Build reproducible base images | Orchestrate Packer builds from a template library with live log streaming |
| Download macOS firmware | Fetch IPSW files from ipsw.me or mist-cli; manage local copies |
| Share images with your team | Push and pull OCI images to/from any container registry (GHCR, Docker Hub, private) |
| Enroll VMs into MDM | Connect to Jamf Pro, create enrollment profiles, and provision managed VMs |
| Get notified when builds finish | Send alerts via macOS notifications, Pushover, Slack, or Teams |
| Work across multiple environments | Switch between isolated workspaces (profiles) with separate storage roots |

---

## Requirements

- **macOS 14.0 (Ventura) or later** — Apple Silicon Mac strongly recommended
- **Xcode 15.4+** (when building from source)
- External tools (Tart, Packer, mist-cli, jq, sshpass) are downloaded and managed automatically by Oven on first launch

---

## Pages in This Wiki

- [Getting Started](Getting-Started) — install, first-run setup, and onboarding
- [Virtual Machines](Virtual-Machines) — create, clone, start, SSH, tags, shared folders
- [Building Base VMs](Building-Base-VMs) — Packer-based base image builds
- [Templates & Building Blocks](Templates-and-Building-Blocks) — template library and reusable provisioner snippets
- [OS Installers](OS-Installers) — IPSW management and download sources
- [OCI Registry](OCI-Registry) — push/pull images to container registries
- [MDM Integration](MDM-Integration) — Jamf Pro connection and VM enrollment
- [Notifications](Notifications) — Pushover, Slack, Teams, and system alerts
- [Workspaces](Workspaces) — multi-profile support
- [Preferences](Preferences) — all settings explained
- [Architecture](Architecture) — technical overview for contributors

---

## Fun Mode

Oven ships with a **Fun Mode** toggle in Preferences that swaps all UI labels into baking terminology:

| Standard | Fun Mode |
|---|---|
| Virtual Machines | Tarts |
| Base VMs / Recipes | Recipes |
| OS Installers | Ingredients |
| Registry | Pantry |

The data and behavior are identical — only the labels change.
