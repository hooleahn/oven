# Templates & Building Blocks

Oven's template system separates *what to build* (the Packer HCL template) from *how to provision it* (building blocks). This page covers both.

---

## Packer Templates

A **Packer template** is an HCL file (`.pkr.hcl`) that defines a complete VM build: the OS source, boot commands, hardware configuration, and any provisioners.

### Template Library

Navigate to **Base VMs → Templates** (or **Recipes** in Fun Mode) in the sidebar to browse the template library.

Templates are organized into two categories:

| Category | Description |
|---|---|
| **CirrusLabs (vanilla)** | Pre-loaded, read-only vanilla templates from [cirruslabs/macos-image-templates](https://github.com/cirruslabs/macos-image-templates). Covers Tahoe, Sequoia, Sonoma, Ventura, and Monterey. |
| **Custom** | Templates you upload or create. These are editable. |

### CirrusLabs Templates

These are fetched from GitHub on demand and pinned to a specific upstream commit. They are the recommended starting point for new base images — they contain well-tested boot commands and sensible defaults.

To use one:
1. Click **Add from CirrusLabs** in the template list.
2. Browse the available templates.
3. Click **Import** — Oven downloads the `.pkr.hcl` and saves it to your templates directory.

### Custom Templates

To add your own template:
1. Click **+** in the template list.
2. Upload a `.pkr.hcl` file or paste HCL content directly.
3. Fill in the metadata: display name, description, target macOS version.

Custom templates can be edited directly in Oven's built-in HCL editor (see below).

### Template Variables (.pkrvars.hcl)

If your template uses `var.` references, you can provide a variables file:

1. In the template detail pane, click **Attach Variables File**.
2. Upload or create a `.pkrvars.hcl` file.
3. Oven passes it to Packer as `-var-file=<path>` at build time.

> **Security note:** Variable files may contain secrets (passwords, tokens). Oven flags this with a warning. Keep variable files out of version control.

### HCL Editor

Oven includes a built-in HCL editor with:
- Line numbers
- Syntax highlighting
- Error indicators from `packer validate`

Open any custom template and click **Edit** to enter the editor. Changes are saved to your templates directory. Read-only (CirrusLabs) templates must be **forked** before editing — click **Duplicate** to create an editable copy.

---

## Building Blocks

**Building Blocks** are reusable Packer provisioner snippets in HCL. Rather than duplicating provisioner code across many templates, you define a building block once and attach it to any build.

### Seeded Building Blocks

Oven ships with 10 built-in building blocks:

| Name | What It Provisions |
|---|---|
| **Passwordless Sudo** | `/etc/sudoers.d/` entry for the build user |
| **Auto Login** | macOS automatic login for the build user |
| **Homebrew** | Full Homebrew install via `curl` |
| **Xcode CLI Tools** | `xcode-select --install` with interactive bypass |
| **SSH** | Enables Remote Login (SSH server) |
| **Disable Spotlight** | `mdutil -a -i off` |
| **Screen Lock** | Disables screensaver and screen lock timeout |
| **Safari Automation** | Enables `safaridriver --enable` for WebDriver use |
| **Random Computer Name** | Generates and sets a random hostname |
| **File Upload** | Copies a file from the Packer host into the VM |

Seeded blocks are read-only. To customize one, click **Duplicate** to create your own editable copy.

### Creating Custom Building Blocks

1. Navigate to **Building Blocks** in the detail pane of any base VM.
2. Click **+ New Block**.
3. Fill in:
   - **Name** — shown in the UI
   - **Description** — optional, displayed in the detail pane
   - **Provisioner Type** — `shell`, `file`, or `shell-local`
   - **HCL Content** — the actual Packer provisioner block
   - **Target macOS version** (optional) — limits the block to specific OS versions in the picker
4. Click **Save**.

The block is now available to attach to any base VM build.

### Attaching Building Blocks to a Build

In the **New Base VM** sheet or the base VM's **Edit** sheet:

1. Open the **Building Blocks** section.
2. Click **Add Block**.
3. Browse the library and select the blocks you want.
4. Reorder them with drag-and-drop — provisioners run in the order listed.

### Building Block HCL Format

Each building block should contain a single Packer `provisioner` block. Example:

```hcl
provisioner "shell" {
  inline = [
    "echo 'Disabling Spotlight...'",
    "sudo mdutil -a -i off"
  ]
}
```

Oven injects each block's HCL into the `build {}` section of the parent template at build time.

---

## Template vs. Manual Build

| | Template-Based | Manual Build |
|---|---|---|
| HCL source | Stored `.pkr.hcl` file | Generated dynamically from UI settings |
| Editability | Yes (custom templates) | Configured via toggles in the UI |
| Building blocks | Attachable | Provisioning options are equivalent |
| Best for | Repeatable, versioned builds | Quick one-off builds or experimenting |

Both paths produce the same output: a named Tart VM image.
