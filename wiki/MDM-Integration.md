# MDM Integration

Oven integrates with **Jamf Pro** so you can enroll VMs into device management during provisioning. This page covers connecting Jamf, creating MDM profiles, and enrolling VMs.

---

## Overview

The MDM integration flow:

1. Add a Jamf Pro server connection in Preferences.
2. Create an **MDM Profile** in Oven (maps to an enrollment invitation in Jamf).
3. Attach the profile to a Base VM build configuration.
4. During the build, Oven places the enrollment profile into the VM.
5. You need to manually install the enrollment profile in the VM.

---

## Connecting to Jamf Pro

#### WARNING: Before using in a production workflow, connect to a sandbox or test instance of a Jamf Pro server to test Oven's functionality.
#### Stick to the least-privilege principle and don't grant the User account or API Client used in Oven more privileges than required.

### Add a Server

1. Go to [Preferences → Integrations](Preferences#integrations).
2. Under **Jamf Pro Servers**, click **+**.
3. Fill in:
   - **Friendly Name** — label for this server in the UI
   - **Server URL** — e.g., `https://yourorg.jamfcloud.com`
   - **Authentication Type** — choose between:
     - **API Token** (recommended) — uses Jamf's modern bearer token auth
     - **Basic Auth** — uses username/password with the Jamf Classic API
   - **Username / Password** — credentials for the account Oven will use
4. Click **Test Connection** to verify.
5. Click **Save**.

Credentials are stored in the macOS Keychain.

### Required Jamf Privileges

The account Oven uses needs the following Jamf privileges depending on which features you enable:

| Feature | Required Privilege |
|---|---|
| Check enrollment status | Read Computers |
| Delete device from Jamf | Delete Computers |
| Check invitation status | Read Computer Enrollment Invitations |

Oven displays the detected privileges after a successful connection test.

### Multiple Servers

You can add multiple Jamf Pro instances (e.g., production and staging). Select the active server per MDM Profile.

---

## MDM Profiles

An **MDM Profile** in Oven represents an enrollment invitation. It stores the information needed to enroll a VM with a specific Jamf server.

### Creating an MDM Profile

1. Navigate to the **MDM Profiles** section (accessible from the sidebar or from a Base VM's detail pane).
2. Click **+ New Profile**.
3. Configure:
   - **Display Name** — identifies this profile in the UI
   - **Jamf Server** — select from your saved servers
   - **Custom Server URL** (optional) — override the MDM server URL sent inside the enrollment payload, if your Jamf is behind a proxy or has a different externally-accessible hostname
   - **Invitation ID** — the enrollment invitation ID from Jamf (found in Jamf → Computers → Enrollment Invitations)
   - **Expiration Date** — optional; Oven will warn you if the invitation has expired
4. Click **Save**.

### Checking Invitation Status

Select a profile and click **Check Status**. Oven queries Jamf to verify:
- Whether the invitation is still valid
- Whether the expiration date has passed
- Whether any devices have enrolled using this invitation

---

## Enrolling a VM During a Build

1. Open a Base VM's edit sheet.
2. Scroll to the **MDM** section.
3. Toggle **Enroll in MDM** on.
4. Select the MDM Profile to use.
5. Build the VM as normal.

During the Packer provisioning phase, Oven places the MDM enrollment profile into the VM. You then have to install the profile manually by booting the VM.

---

## Post-Enrollment Actions

After a VM is enrolled, Oven can perform Jamf operations on it from the VM detail pane:

| Action | Description |
|---|---|
| **Check Enrollment** | Queries Jamf for the device record matching this VM |
| **Get Management Status** | Returns whether the device is enrolled, managed, and MDM-capable |
| **Delete from Jamf** | Removes the device record from Jamf when the VM is deleted |

These actions use the Jamf Pro API and require the associated MDM Server to be configured and tested.

---

## Automatic Random Serial Number

Each cloned VM gets a unique serial number. This prevents Jamf from treating multiple clones as the same device.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Connection test fails | Check the server URL (include `https://`), username, and password; verify network access from your Mac |
| `403 Forbidden` on enrollment check | The Jamf account lacks Read Computers privilege |
| VM does not appear in Jamf after build | Check the build log for MDM provisioner errors; verify the invitation ID is correct and not expired |
| Invitation expired | Create a new enrollment invitation in Jamf and update the MDM Profile in Oven |
| Multiple clones appear as one device | Add the Random Computer Name building block to the base image build |

---

## Other MDMs

At this time there are no plans to support other MDMs. PRs and contributions are welcome.
