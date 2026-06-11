# Preferences

Open Preferences with **⌘,** or from the **Oven** menu. There are six tabs.

---

## Build

Settings that affect how Packer builds run.

| Setting | Description |
|---|---|
| **IPSW Download Source** | Choose between `ipsw.me` (default) and `mist-cli` for firmware discovery and download |
| **Build Timeout** | Minutes of inactivity before Oven considers a build hung and fires a failure notification. Default: 30 |
| **Heartbeat Interval** | How often (seconds) Oven checks for build output to detect stalls |
| **Build Completion Action** | What to do after a successful build: **Do Nothing** (default), **Lock Screen**, or **Shut Down** |
| **Fun Mode** | Toggle baking-themed UI labels (Tarts, Recipes, Ingredients, Pantry) |
| **Debug Mode** | Log every shell command Oven runs to the Activity Log |

---

## Tools

Manage the command-line tools Oven depends on.

### Dependency Mode

| Mode | Description |
|---|---|
| **Managed** (default) | Oven downloads and maintains versioned binaries in its own directory |
| **Custom** | Oven uses tools you specify or tools found on your `$PATH` |

### Managed Mode

In managed mode, click the refresh icon next to any tool to check for a newer version. Click **Update** to upgrade.

Managed binaries are stored in the configured **Dependencies Root** (see Storage tab).

### Custom Mode

In custom mode, enter the full path to each binary or leave it blank to use the system `$PATH`.

| Tool | Default lookup |
|---|---|
| `tart` | `$(which tart)` |
| `packer` | `$(which packer)` |
| `mist-cli` | `$(which mist-cli)` |
| `jq` | `$(which jq)` |
| `sshpass` | `$(which sshpass)` |

### Tool Status

Each tool shows its current version and a status badge:
- **Up to date** — current version matches the latest known release
- **Update available** — a newer version exists
- **Not found** — the binary cannot be located at the configured path
- **Unknown** — version could not be determined

---

## Storage

Configure where Oven stores files.

| Setting | Description | Default |
|---|---|---|
| **VM Storage Root** (`TART_HOME`) | Where Tart stores VM disk images | `~/.tart/` |
| **IPSW Storage Root** | Where macOS firmware files are downloaded | `~/Library/Application Support/Oven/ipsw/` |
| **Packer Templates Root** | Where Packer `.pkr.hcl` and `.pkrvars.hcl` files are stored | `~/Library/Application Support/Oven/packer/` |
| **Dependencies Root** | Where managed tool binaries are downloaded | `~/Library/Application Support/Oven/deps/` |

Click **Browse** next to any path to pick a new directory with the Finder. Existing files are **not** moved automatically.

---

## Notifications

Configure notification channels and events. See the [Notifications](Notifications) page for full setup instructions.

| Setting | Description |
|---|---|
| **System Notifications** | Toggle macOS native notifications |
| **Pushover** | Enable + enter API token and user key |
| **Slack** | Enable + enter webhook URL |
| **Microsoft Teams** | Enable + enter webhook URL |
| Per-event toggles | Independently enable/disable notifications for: build success, build failure, IPSW download, registry push, registry pull, VM stopped |

---

## Integrations

Configure external service connections.

### Registry Credentials

Add username/password pairs for OCI registries. Passwords are stored in the Keychain. See [OCI Registry](OCI-Registry#setting-up-registry-credentials).

### Jamf Pro Servers

Add and test Jamf Pro connections. See [MDM Integration](MDM-Integration#connecting-to-jamf-pro).

---

## Acknowledgements

Lists open-source tools and libraries Oven depends on with their licenses:
- Tart (cirruslabs)
- Packer (HashiCorp)
- mist-cli (ninxsoft)
- jq (Stephen Dolan)
- sshpass

Also shows the current Oven version and build number.
