# OS Installers

Oven manages macOS IPSW firmware files — the disk images that Tart uses to create VMs. This page explains where firmware comes from, how Oven downloads and stores it, and how to add custom installers.

---

## What Is an IPSW?

An IPSW (iPhone Software) file is the firmware package Apple ships for each macOS release. In the context of Apple Silicon VMs, it is the equivalent of an ISO — Tart uses an IPSW to provision a new VM's base system.

---

## Supported macOS Versions

| macOS Name | Major Version |
|---|---|
| Tahoe | 26 |
| Sequoia | 15 |
| Sonoma | 14 |
| Ventura | 13 |
| Monterey | 12 |

---

## Firmware Sources

Oven supports two sources for firmware discovery and download. Switch between them in [Preferences → Build](Preferences#build).

### ipsw.me (Default)

Oven queries the [ipsw.me API](https://ipsw.me) to discover available IPSW URLs for `VirtualMac2,1` (the Tart virtual hardware identifier). This source is fast, requires no extra tools, and covers all released versions.

### mist-cli (Alternative)

[mist-cli](https://github.com/ninxsoft/mist-cli) is a command-line tool that queries Apple's software catalog directly. Use it as a fallback if ipsw.me is unavailable, or when you need to see beta versions that ipsw.me doesn't index.

mist-cli is managed by Oven's dependency system — it is downloaded automatically if you switch to this mode and have not previously installed it.

---

## Browsing Available Installers

1. Click **Installers** (or **Ingredients** in Fun Mode) in the sidebar.
2. Oven shows a list of macOS versions available from your selected source.
3. Each entry displays the version number, build string, release date, and file size.
4. Click a version to see its details in the right pane.

---

## Downloading an IPSW

1. Select the macOS version you want.
2. Click **Download** in the detail pane.
3. Oven saves the IPSW to your configured storage root (default: `~/Library/Application Support/Oven/ipsw/`).

Downloads are resumable. If a download is interrupted, clicking **Download** again resumes from where it left off.

---

## Using a Downloaded IPSW in a Build

When you create a Base VM:
- If the required IPSW is already downloaded, Oven uses it automatically.
- If it is not downloaded yet, Oven will download it at the start of the build.

You can pre-download firmware in advance to avoid delays when a build starts.

---

## Custom Installers

You can register IPSW files you obtained outside of Oven — for example, beta builds, internal seeds, or files you downloaded manually.

### Adding a Custom Installer

1. In the **Installers** section, click **+ Add Custom Installer**.
2. Click **Browse** and select the `.ipsw` file on your Mac.
3. Enter a display name and the macOS version it represents.
4. Click **Save**.

The custom installer now appears alongside the standard entries and can be selected when creating a Base VM.

### Custom OS Entries

If you are building VMs from an OS that Oven does not recognize (for example, a private beta), you can define a **Custom OS Entry**:

1. Click **+ Add Custom OS**.
2. Provide a name, version number, and any identifying metadata.
3. Associate it with a downloaded IPSW or a custom installer.

Custom OS entries appear in the OS version picker in all build configuration UIs.

---

## Storage

IPSW files are large (typically 10–20 GB each). Oven stores them in a configurable root directory. To change it:

1. Go to [Preferences → Storage](Preferences#storage).
2. Update the **IPSW Storage Root** path.

Downloaded files are not moved automatically — if you change the path, move existing files manually.

---

## Disk Space Tips

- Keep only the IPSW versions you actively build against.
- A single macOS Sequoia IPSW is approximately 14 GB.
- Oven does not delete old IPSWs automatically — manage disk space manually.
- If you push base images to a registry, you can delete the local IPSW after the build completes since the OCI image can be pulled again later.
