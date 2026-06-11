# Virtual Machines

This page covers day-to-day VM management: creating, cloning, starting, stopping, connecting via SSH, and organizing with tags.

---

## VM States

| State | Meaning |
|---|---|
| **Stopped** | VM is not running |
| **Running** | VM is active and consuming CPU/RAM |

---

## Creating a VM

### New VM

1. Click the **+** button in the VM list toolbar.
2. Fill in the **New VM** sheet:
   - **Source** — Required. Choose a Base VM to create the VM from.
   - **Display Name** — Optional. The name shown in Oven (can be changed any time)
   - **Description** — Optional. What the VM is for, or whatever you want.
   - **Tags** — Optional. Simple way of categorizing VMs.
   - **SSH Credentials** — Optional. The credentials for using/accessing the VM. Since these are editable, they may not match what's actually in the VM. They are used for SSH and VNC connections. Stored in Keychain.
   - **CPU Cores**, **Memory (GB)**, **Disk (GB)** — hardware configuration. Oven will run a tart set command to change these in the new VM.
3. Click **Create**.

The VM appears in the list in a stopped state. Tart will automatically run a tart set [vm-name] --random-serial command to ensure the new VM has a different serial number from the Base VM.

### Clone from a Base VM

You can create a new VM from the Base VMs section:

1. Select a Base VM in the **Base VMs** section.
2. Click **Clone** in the detail pane.
3. Give the clone a display name and Tart name.
4. Click **Clone** — Tart copies the base image to a new named VM.

### Pull from a Registry

See [OCI Registry — Cloning from a Registry](OCI-Registry#cloning-from-a-registry).

---

## Starting & Stopping

| Action | How |
|---|---|
| **Start** | Select VM → click **Start** in the detail pane, or click the play icon in the VM card |
| **Stop** | Select a running VM → click **Stop** |
| **Resume** | Select a suspended VM → click **Start** |
| **Force Stop** | Use the menu bar extra or Tart CLI if the UI is unresponsive |

Oven opens a start mode selector when you start a VM from the Card view. It starts in Tart UI when started from the detail pane.

---

## SSH Access

Oven can SSH into running VMs directly.

### Setting Credentials

1. Select the VM.
2. In the detail pane, open the **SSH** section.
3. Enter the **username** and **password** for the VM's user account. Credentials are stored in the macOS Keychain — never in plain text.

### Connecting

Click **SSH** in the detail pane. Oven opens a Terminal window where you can input the VM password. The VM must be running and have its IP address resolved.

### IP Address

Oven polls `tart ip` after a VM starts and caches the result. If the IP field shows a spinner, the VM's network interface is still coming up — wait a few seconds and it will populate automatically.

---

## Shared Folders

You can mount host directories into a running VM:

1. Select the VM.
2. In the detail pane, open **Shared Folders**.
3. Click **+** and choose a directory.
4. The folder will be mounted inside the VM at `/Volumes/My Shared Files/<folder-name>` (Tart default mount path).

Shared folder mounts are applied each time the VM starts.

---

## Display Name & Tags

### Display Name

Every VM has a **Display Name** shown in the Oven UI, separate from its Tart identifier. Change it any time in the detail pane without affecting the underlying VM.

### Tags

Tags let you categorize VMs — for example, by team, purpose, or macOS version.

1. Open the VM detail pane.
2. Click **Add Tag**.
3. Type a tag name and choose a color from the palette.

Tags are shown as colored chips on VM cards in the list view. You can filter the list by tag using the search/filter bar.

---

## Executing Commands

In the VM detail pane, the **Run Command** field lets you send a shell command to the VM over SSH. This is useful for quick checks or automation without opening a full terminal session.

---

## Recovery Mode

For troubleshooting a VM that won't boot normally:

1. Select the stopped VM.
2. Click the start button (play icon)
3. Choose **Recovery (Native Only)**.

Tart starts the VM with the recovery partition active.

---

## Editing a VM

1. Select the VM.
2. Click the pencil icon.
3. You can edit multiple values for the VM.
  - Display Name
  - Description
  - Tags
  - Use as Base VM – Toggle this to treat this VM as a Base VM, it will be moved to the Base VM section. You can revert the change from there if needed.
  - OS Name and Version – This is usually inferred from the Base VM or the VM name, but you can manually set it here.
  - Beta OS – Toggle this to classify it as a Beta OS VM. Currently this toggle doesn't do anything.
  - Serial Number – Setting this value and tying the VM to an MDM server will allow Oven to query the VM enrollment status and to offer the option to remove it from the MDM server when deleted locally.
  - Default VM and SSH Credentials – You can change these if they are incorrect. Oven has no way of knowing which credentials this are, unless the Base VM was built in the app and the credentials haven't changed.
  - Tart Guest Agent – Toggle to enable the option of executing commands on a running VM using tart exec via the Tart Guest Agent. Oven has no way of knowing if the VM has the Tart Guest Agent installed.
  - Hardware – Changing this will run tart set on the VM and change its hardware settings. The CPU Cores and RAM size cannot be set larger than what the host hardware supports. Changing the disk size might require additional steps in Recovery Mode. See https://tart.run/faq/#disk-resizing for more info.
  - Shared Folders – You can set local folders to be automatically mounted when running a VM.



---

## Deleting a VM

1. Select the VM.
2. Click the **...** menu → **Delete**.
3. Confirm the prompt.

This removes the VM's disk image from your `TART_HOME`. This action is irreversible.

If a MDM server was set in the VM configuration you will have the option to remove it from the MDM server as well.

---

## VM Detail Pane Reference

| Section | Contents |
|---|---|
| Top Bar | Start in Tart native mode, Options to delete, push to registry, pin to menubar, search field |
| Header | Display name, Tart VM name, status indicator |
| Configuration | CPU, memory, disk, OS version, display size, serial number |
| Connectivity | IP address (auto-resolved), SSH URI, VNC URI (if available) |
| Credentials | VM Credentials |
| Properties | Tart VM Name, Creation Date, Last Start Date |
