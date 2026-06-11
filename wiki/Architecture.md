# Architecture

This page is for contributors and anyone who wants to understand how Oven is built.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 |
| UI framework | SwiftUI (native macOS) |
| Architecture | MVVM + `@Observable` |
| Persistence | JSON files via `AppDatabase` |
| Credentials | macOS Keychain |
| Concurrency | Swift Structured Concurrency (`async/await`, `AsyncStream`) |
| External processes | `Foundation.Process` wrapped in `ProcessRunner` |
| Dependencies | None (no SwiftPM or CocoaPods packages) |

Minimum deployment target: **macOS 14.0**

---

## Project Layout

```
Oven/
├── Core/        # Foundation services
├── Models/      # Data structures
├── Services/    # Business logic & external integrations
├── UI/          # SwiftUI views
└── Resources/   # Info.plist, entitlements, assets, wallpapers
```

---

## Core Layer (`/Core`)

Low-level services shared across the app.

| File | Role |
|---|---|
| `ProcessRunner.swift` | Async wrapper around `Foundation.Process`; yields `ProcessEvent` (.stdout, .stderr, .exit) via `AsyncStream` |
| `DependencyManager.swift` | Downloads, versions, and locates tool binaries (Tart, Packer, mist-cli, jq, sshpass) |
| `AppDatabase.swift` | Unified JSON persistence with versioned schema envelopes; reads/writes all model data to `~/Library/Application Support/Oven/` |
| `AppLogger.swift` | In-memory + persisted activity log; entries are timestamped and viewable in the Activity Log view |
| `AppTheme.swift` | Resolves display strings based on Fun Mode toggle |
| `KeychainService.swift` | Typed Keychain read/write for passwords, tokens, and registry credentials |
| `NotificationService.swift` | Routes notification events to enabled channels (system, Pushover, Slack, Teams) |
| `BuildMonitor.swift` | Tracks active build sessions; fires timeout events if no output is received |
| `BuildSessionManager.swift` | Coordinates multiple concurrent build sessions |
| `ProfileStore.swift` | Persists and activates workspace profiles |
| `TagStore.swift` | Color palette and tag definitions |
| `PreflightCheck.swift` | Validates dependencies before allowing a build to start |
| `StreamConsumer.swift` | Parses structured output from Packer and Tart |

---

## Models Layer (`/Models`)

Plain Swift structs that conform to `Codable`. Stored and loaded by `AppDatabase`.

| Model | Description |
|---|---|
| `VirtualMachine` | Central VM entity. Contains ~50 fields covering identity, hardware, OS metadata, build info, provisioning config, and registry origin. |
| `AppSettings` | Global settings: storage roots, dependency mode, binary paths, IPSW source |
| `OvenProfile` | Workspace profile: name + four storage roots (`TART_HOME`, IPSW root, templates root, metadata root) |
| `MDMProfile` | Enrollment profile: server ID, invitation ID, expiration, custom server URL |
| `MDMServer` | Jamf Pro connection: URL, auth type, credentials reference, last test result |
| `RegistryCredential` | Per-registry username; password is stored separately in Keychain, referenced by ID |
| `ManualBuildConfig` | Complete build configuration for the manual build path; serialized into HCL at build time |
| `CustomInstaller` | User-registered `.ipsw` file with name and version metadata |
| `CustomOSEntry` | User-defined OS entry for unrecognized macOS builds |

### MacOSRelease.Name

`VirtualMachine` embeds a `MacOSRelease.Name` enum covering Tahoe (26), Sequoia (15), Sonoma (14), Ventura (13), Monterey (12), plus `.custom`, `.any`, and `.unknown`. Each case carries a default version list used when the SOFA feed is unavailable.

### ProcessEvent

```swift
enum ProcessEvent {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}
```

`ProcessRunner` yields these via `AsyncStream<ProcessEvent>`. All services consume this stream.

---

## Services Layer (`/Services`)

One service per domain. Each service is instantiated once in `AppState` and injected into views via the environment.

| Service | Responsibilities |
|---|---|
| `VMStore` | VM metadata CRUD; syncs with `tart list` to detect externally created/deleted VMs |
| `BaseVMStore` | Base VM CRUD; orchestrates builds via `PackerService` |
| `TartService` | Wraps Tart CLI: `list`, `run`, `clone`, `push`, `pull`, `stop`, `suspend`, `ip`, `delete`, `login` |
| `PackerService` | Wraps Packer CLI: `init`, `validate`, `build`; streams output via `ProcessRunner` |
| `RegistryService` | Wraps `tart login` and `tart push`/`tart pull` for OCI operations |
| `IPSWService` | Queries ipsw.me API; caches results for 24 hours |
| `MistService` | Wraps `mist-cli list firmware --export`; parses JSON output |
| `SOFAService` | Fetches macadmins.io SOFA feed; falls back to hardcoded version list |
| `JamfService` | Jamf Pro API client: token auth, device lookup, enrollment check, delete |
| `PackerTemplateStore` | CRUD for Packer templates + sidecar metadata JSON (UUIDs, display names) |
| `BuildingBlockStore` | CRUD for building block snippets; seeds 10 defaults on first launch |
| `CirrusLabsTemplateStore` | Fetches template catalogue from cirruslabs GitHub repo |
| `ManualBuildHCLGenerator` | Generates `.pkr.hcl` from a `ManualBuildConfig` struct |
| `CustomOSStore` | CRUD for custom OS entries |
| `CustomInstallerStore` | CRUD for custom installer registrations |
| `PushManager` | Fan-out notification sender across all enabled channels |

---

## UI Layer (`/UI`)

74 SwiftUI files. Key structural files:

| File | Role |
|---|---|
| `OvenApp.swift` | `@main` entry point; `NSApplicationDelegate`; creates the main window scene and menu bar extra |
| `AppState.swift` | `@Observable` global state; owns all service instances; injected as `.environment(appState)` |
| `ContentView.swift` | Root three-column `NavigationSplitView` |

Views receive services through `@Environment(AppState.self)` and call service methods directly. There are no intermediate ViewModels — `AppState` serves that role for global state, while view-local state uses `@State`.

---

## Persistence

`AppDatabase` manages a single directory at `~/Library/Application Support/Oven/` (configurable per workspace). Each model type is stored in its own JSON file wrapped in a versioned envelope:

```json
{
  "version": 1,
  "data": [ ...array of model objects... ]
}
```

The version field allows `AppDatabase` to migrate data when the schema changes. Migrations run automatically on load.

Credentials (passwords, tokens, registry passwords) are never stored in JSON — only Keychain item identifiers are stored, and the actual secrets are read from Keychain at runtime.

---

## Dependency Management

`DependencyManager` tracks five binaries. In **Managed** mode:

1. On launch, it reads each binary's version by running `<tool> --version`.
2. It queries the GitHub Releases API for the latest version of each tool.
3. If an update is available, it sets the tool's status to `.updateAvailable`.
4. Downloads use `URLSession` with CryptoKit SHA256 verification of the downloaded archive before extraction.

In **Custom** mode, `DependencyManager` still verifies that each path resolves to a working binary, but does not download or update.

---

## Build Pipeline

For a template-based build:

```
User clicks Build
    │
    ▼
PreflightCheck (all tools present?)
    │
    ▼
PackerService.init(templatePath, varsPath?)
    │  → packer init -upgrade <dir>
    ▼
PackerService.validate(templatePath, varsPath?)
    │  → packer validate [-var-file=<vars>] <template>
    ▼
PackerService.build(templatePath, varsPath?)
    │  → packer build [-var-file=<vars>] <template>
    │  → streams ProcessEvent via AsyncStream
    │  → BuildMonitor watches for stall
    ▼
Build completes
    │
    ▼
BaseVMStore updates base VM metadata
PushManager fires completion notifications
BuildCompletionAction runs (if configured)
```

For a manual build, `ManualBuildHCLGenerator` writes a `.pkr.hcl` to a temp directory first, then the same pipeline runs against it.

---

## Concurrency Model

Oven uses Swift Structured Concurrency throughout:

- All service methods are `async`.
- Long-running operations (builds, downloads) run as `Task { ... }` attached to a view's lifetime via `.task {}` modifier or cancelled explicitly.
- `ProcessRunner` publishes output as `AsyncStream<ProcessEvent>`, consumed with `for await event in stream`.
- UI updates always happen on `MainActor` — service methods annotated with `@MainActor` where needed.

---

## Adding a New Tool Integration

To add a new CLI tool wrapper:

1. Add a `Dependency` entry to `DependencyManager` with the tool's name, GitHub release URL, and binary name.
2. Create a new `Service` file following the pattern of `TartService.swift` — instantiate `ProcessRunner`, call `run(arguments:)`, and consume the `AsyncStream`.
3. Add the service instance to `AppState`.
4. Inject it into views via the environment.
