# Workspaces

Oven supports multiple **Workspaces** (called *Profiles* internally) so you can maintain completely isolated environments on a single Mac. Each workspace has its own VMs, IPSW storage, Packer templates, and metadata.

---

## Why Use Multiple Workspaces?

Common use cases:

- **Separate teams** — one workspace for iOS CI and another for macOS QA
- **Separate environments** — a production image workspace and a development/experimental workspace
- **Different Tart homes** — keep VM disk images on separate drives or partitions
- **Clean slate testing** — spin up a blank workspace to test build configurations without touching existing VMs

---

## What Each Workspace Isolates

| Resource | Per Workspace |
|---|---|
| Tart VMs | Yes — each workspace points to its own `TART_HOME` |
| IPSW files | Yes — separate download directory |
| Packer templates | Yes — separate templates directory |
| VM metadata | Yes — separate metadata database |
| App settings (tools, notifications, integrations) | No — shared across all workspaces |

Registry credentials, Jamf servers, and notification settings are global and apply to all workspaces.

---

## Creating a Workspace

1. Click the workspace picker at the top of the sidebar (shows the current workspace name).
2. Click **New Workspace**.
3. Fill in:
   - **Name** — display name for this workspace
   - **TART_HOME** — directory where Tart will store VMs for this workspace (e.g., `~/.tart-ci/`)
   - **IPSW Storage Root** — where to download firmware for this workspace
   - **Packer Templates Root** — where to store Packer templates
4. Click **Create**.

Oven switches to the new workspace immediately.

---

## Switching Workspaces

Click the workspace picker in the sidebar and select a workspace from the list. The switch is instant — all lists (VMs, Base VMs, Installers) update to show the contents of the selected workspace.

---

## Default Workspace

The **Default** workspace is created automatically on first launch. It uses the default storage paths from your initial onboarding setup. It cannot be deleted.

---

## Editing a Workspace

1. Open the workspace picker.
2. Click the pencil icon next to the workspace you want to edit.
3. Update the name or storage paths.
4. Click **Save**.

> Changing storage paths does not move existing files. If you point a workspace to a new directory, it will appear empty until you populate it or adjust the path back.

---

## Deleting a Workspace

1. Open the workspace picker.
2. Click the trash icon next to the workspace.
3. Confirm the deletion.

Deleting a workspace removes the workspace configuration from Oven. **It does not delete files on disk** — VMs, IPSWs, and templates in the workspace's directories are untouched.

---

## Tips

- Use descriptive names like "macOS CI — Sequoia" or "QA — Sonoma" to quickly identify workspaces.
- Point different workspaces to different physical drives to spread large VM storage across disks.
- If you share a Mac with teammates (uncommon but possible), workspaces can segment each person's VMs cleanly.
