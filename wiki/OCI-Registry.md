# OCI Registry

Oven integrates with OCI-compatible container registries to share base VM images across machines and teams. You can push a locally built base image to a registry and pull it on any other Mac running Oven and Tart.

This is supported through Tart's own function for pulling and pushing images from/to registries.

---

## Supported Registries

Oven works with any OCI-compliant registry:

- **GitHub Container Registry (GHCR)** — `ghcr.io`
- **Docker Hub** — `registry-1.docker.io`
- **Private registries** — any URL that implements the OCI Distribution Spec

---

## Setting Up Registry Credentials

Before pushing or pulling private images, store your credentials:

1. Go to [Preferences → Integrations](Preferences#integrations).
2. Under **Registry Credentials**, click **+**.
3. Enter:
   - **Registry URL** — e.g., `ghcr.io`
   - **Username**
   - **Password / Token** — stored in the macOS Keychain
4. Click **Save**.

You can add multiple sets of credentials for different registries.

### GHCR Authentication

For GitHub Container Registry, use a **Personal Access Token (PAT)** with `read:packages` and `write:packages` scopes as the password.

---

## Pushing a Base VM to a Registry

After a successful base image build:

1. Select the Base VM in the **Base VMs** list.
2. Click **Push to Registry** in the detail pane (or the **...** menu).
3. In the **Push** sheet:
   - **Registry** — select a saved credential or enter a new one
   - **Image Reference** — the full image path, e.g., `ghcr.io/myorg/macos-sequoia:latest`
   - **Tag** — optionally override the default `latest` tag
4. Click **Push**.

Oven runs `tart push <name> <image-ref>` in the background. Progress is shown in the Activity Log and a notification fires on completion.

---

## Pulling an Image from a Registry

### Pull to a New Base VM

1. In the **Base VMs** section, click **+**.
2. Choose **Pull from Registry**.
3. Enter the full image reference (e.g., `ghcr.io/myorg/macos-sequoia:latest`).
4. Give the local Base VM a name.
5. Click **Pull**.

### Clone a Registry Image into a VM

1. In the **Virtual Machines** section, click **+**.
2. Choose **Clone from Registry**.
3. Enter the image reference.
4. Give the new VM a display name and Tart name.
5. Click **Clone**.

Oven runs `tart clone <image-ref> <name>`. The VM will appear in the list once the pull completes.

---

## Browsing GHCR

Oven can browse the public catalog on `ghcr.io`:

1. In the **Registry** section (or **Pantry** in Fun Mode), click **Browse GHCR**.
2. Search for public macOS images by organization or image name.
3. Select an image and click **Pull** or **Clone**.

---

## Image Reference Format

OCI image references follow the standard format:

```
<registry>/<namespace>/<image>:<tag>
```

Examples:
- `ghcr.io/myorg/macos-sonoma:14.5`
- `ghcr.io/cirruslabs/macos-sonoma-vanilla:latest`
- `registry.internal.example.com/ci/macos-runner:v3`

---

## Registry Section (Pantry)

The **Registry** section in the sidebar shows:
- Saved registry credentials
- Previously pulled or pushed images (local cache of references)
- Quick-action buttons for pulling or re-pushing

---

## Workflow Example: Shared CI Base Image

1. **Build once locally** on a developer Mac using a Packer template.
2. **Push** to `ghcr.io/myorg/macos-sequoia-ci:latest`.
3. **Pull** on CI machines or other developer Macs — they skip the multi-hour Packer build.
4. **Rebuild and re-push** when you need to update the image (e.g., new Xcode version).

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `unauthorized` error | Check credentials in Preferences → Integrations; verify token scopes |
| Push fails with `no space left` | Free disk space — Tart stages the image locally during push |
| Pull is slow | Expected for large images (10–20 GB); use a wired connection if possible |
| Image not found after push | Check the exact image reference — tags are case-sensitive |
