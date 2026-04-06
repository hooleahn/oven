## 0.1.300
- Fix: PackerTemplateStore.update() now copies the element out, mutates the copy, then assigns back with templates[i] = copy. This matches exactly how Array mutation triggers @Observable's property observation — the subscript setter on templates fires, which triggers objectWillChange, which causes @EnvironmentObject subscribers to re-render list rows with the new displayName. Previously apply(&templates[i]) mutated in-place through an inout reference without triggering the setter.

## 0.1.299
- Fix: PackerTemplateStore.update(id:apply:) now mirrors BuildingBlockStore.update(id:apply:) exactly — mutates templates[i] directly via inout. RecipesViewModel.save() calls store.update() after writing to disk, same pattern as blockStore.update { $0 = updated }. RecipesViewModel.save() also calls store.saveContent() and store.saveMetadata() (renamed from the old save/updateMetadata to avoid ambiguity).

## 0.1.298
- Fix: Moved templatesList and varsFilesList back to computed properties directly on RecipesView (same pattern as the working blocksList), reading templateStore as a direct @EnvironmentObject property of RecipesView. When objectWillChange fires on templateStore, RecipesView.body re-evaluates, templatesList recomputes from fresh templateStore.customFullTemplates, and rows get updated data — identical to how blocksList works. Removed TemplateListView and VarsFileListView child structs.

## 0.1.297
- Removed redundant loadTemplateContent() call after save in RecipesViewModel — store.updateMetadata() already sets the correct state via full templates reassignment; calling loadContent again was triggering a second objectWillChange and re-reading file content unnecessarily. Detail pane fields now sync directly from store.template(id:) after save.

## 0.1.296
- Fix (definitive root cause): @Observable tracks property setters, not subscript mutations. templates[idx].displayName = x goes through Array's subscript, which @Observable does not intercept — so objectWillChange never fires and SwiftUI never re-renders the list rows. Fixed by replacing all subscript mutations with templates = templates.map { ... } — a full property reassignment that @Observable's synthesised setter definitely intercepts. Also removed the load() call from save(content:) which was rebuilding the array from disk with the stale pre-save displayName.

## 0.1.295
- Fix (actual root cause): BuildingBlockStore has dual @Observable + ObservableObject conformance — when blocks[i] mutates, @Observable fires AND objectWillChange fires, so @EnvironmentObject subscribers update. PackerTemplateStore had lost ObservableObject in 0.1.293, breaking the objectWillChange signal. Restored dual conformance to match BuildingBlockStore exactly. TemplateListView and VarsFileListView remain as proper View structs (not computed properties) for correct structural identity, but now receive templateStore via @EnvironmentObject so objectWillChange propagates on mutation.

## 0.1.294
- Fix (definitive): TemplateListView and VarsFileListView now use @Environment(PackerTemplateStore.self) to receive templateStore, and are placed directly in the sidebar switch — not wrapped in computed property vars. Previously: (1) passing `let templateStore` meant @Observable had no way to register property access as a dependency, (2) wrapping in computed vars meant SwiftUI evaluated them as part of RecipesView's body rather than as independent View identities with their own tracking. Now @Observable intercepts templateStore.templates access inside each struct's body directly, and invalidates only those structs when displayName changes.
- Removed dead templatesList/varsFilesList computed property wrappers and templateContextMenu method; context menus inlined into TemplateListView and VarsFileListView.

## 0.1.293
- Fix (root cause): PackerTemplateStore had dual @Observable + ObservableObject conformance but was injected via @EnvironmentObject everywhere. @EnvironmentObject uses the ObservableObject/willChange system — since `templates` is not @Published, mutations via @Observable's tracking were invisible to all subscribers. Removed ObservableObject conformance; migrated all 13 injection/reception sites to .environment()/@Environment(PackerTemplateStore.self). List rows now update immediately on save.

## 0.1.292
- Fix: templatesList and varsFilesList were computed properties returning `some View`, preventing SwiftUI from tracking templateStore.templates changes. Replaced with TemplateListView and VarsFileListView proper View structs that take templateStore as a direct `let` parameter — since PackerTemplateStore is @Observable, SwiftUI now correctly tracks access to .templates inside their body and invalidates the list rows immediately when displayName is saved.

## 0.1.291
- Fix: PackerTemplateStore.updateMetadata() now updates templates[] in-place immediately after writing the sidecar, so @Observable propagates to list rows without a full disk round-trip load() — display name updates instantly on Save
- UI: Template and vars file detail pane toolbars now show Display Name (falling back to filename) as the primary heading, with filename · modified date below
- Building blocks: custom blocks now support full inline editing — Display Name (TextField), Description (multiline TextField), and Provisioner Type (Menu picker in toolbar) — with Revert/Save/⌘S pattern matching templates. Edit sheet retained for creation flow only.

## 0.1.290
- Fix: RecipesViewModel.save() now calls loadTemplateContent() after a successful save, immediately re-syncing the detail pane's display name, description, and OS fields from the updated store — no tab switch required
- Fix: RecipesViewModel.validate() now uses `await packerService.validateStandalone(at:)` (actor requires double await at call site)
## 0.1.289
- Fixed damaged Oven.xcodeproj: rebuilt pbxproj from known-good 0.1.285 base using single-pass registration; root cause was repeated multi-session anchor substitutions creating malformed duplicate entries
- Removed orphaned NewTemplateSheet.swift (superseded by NewPackerObjectSheet in 0.1.288)
- Building Blocks: custom blocks now show an Edit button in the detail pane → opens BuildingBlockEditSheet; onSave updates the store
- BaseVMView: refresh button now records timestamp and shows "Synced · X min ago" age indicator in toolbar, matching InstallerView pattern
- RegistryView: same refresh age indicator ("Synced · X min ago") added to toolbar

## 0.1.288
### Packer Templates — full redesign

**Three object types, now distinct:**
- Full Templates (`.pkr.hcl`) — drive Base VM builds
- Template Variables (`.pkrvars.hcl`) — override template settings at build time; security banner warns against storing passwords
- Building Blocks — HCL provisioner snippets for copy-paste; not buildable standalone

**New infrastructure:**
- `PackerTemplateStore` (@Observable service) — loads all templates with sidecar `.pkr.meta.json` metadata; stable UUIDs across reloads by URL matching
- `PackerTemplateMetadata` — sidecar JSON + HCL comment header writer
- `BuildingBlock` + `BuildingBlockStore` — AppDatabase-backed snippet library (`.packerBlocks` schema v1)
- `PackerService.validateStandalone(at:)` — runs `packer init` + `packer validate` without a vars file; yields status strings for UI

**RecipesView rewrite:**
- Three-tab sidebar: Templates | Vars Files | Building Blocks
- Sections: Custom / Base Templates (read-only); Base Building Blocks
- Metadata detail pane: editable Display Name, Description, OS, Version for full templates
- Validate button with spinner → inline result banner (✓/✗)
- "Create Custom Copy" dialog for Base Templates (fork, then edit)
- Full template context menu: Rename / Duplicate / Delete (→ Trash)
- `.searchable()` across all three tabs

**10 seeded Base Building Blocks:**
Passwordless Sudo, Auto Login, Homebrew Install, Xcode CLT, Enable SSH Daemon, Disable Spotlight, Disable Screen Lock, Safari Automation, Random Computer Name, File Upload

**VirtualMachine schema v5:**
- `customTemplateID: UUID?` replaces `customTemplatePath: String?` (legacy field kept for migration)
- `customVarsFileID: UUID?` added

**NewBaseVMSheet + BaseVMEditSheet:**
- Packer Template section: None / From library (filtered by OS+version) / Custom path
- Template Variables section: None / From library picker; security note when a vars file is selected

**BaseVMStore.build() pipeline:**
- Resolves `customTemplateID` → URL via `PackerTemplateStore`
- Falls back to legacy `customTemplatePath` string for v4 data
- Resolves `customVarsFileID` → `resolvedVarsName` used throughout the build

**AppDatabase:** added `.packerBlocks` (schema v1)

## 0.1.288
### Packer Templates — full overhaul

**Three object types** (was one monolithic list):
- **Full Templates** (`.pkr.hcl`) — complete build definitions, Base Templates read-only
- **Template Variables** (`.pkrvars.hcl`) — variable override files; editor shows security banner warning against storing passwords (Keychain recommended)
- **Building Blocks** — HCL provisioner snippets, copy-paste library; not buildable standalone

**10 seeded Base Building Blocks:** Passwordless Sudo, Auto Login, Homebrew Install, Xcode CLI Tools, Enable SSH Daemon, Disable Spotlight, Disable Screen Lock, Safari Automation, Random Computer Name, File Upload

**New view structure:**
- Segmented control sidebar: Templates | Vars Files | Building Blocks
- Each tab shows Base / Custom sections
- Context menus: Rename, Duplicate, Delete
- `ContentUnavailableView.search` for empty search results

**Metadata system:**
- Sidecar `.pkr.meta.json` per HCL file — Display Name, Description, OS Name, OS Version, UUID
- HCL comment header block written on create (decorative, not parsed back)
- Stable UUIDs across reloads — selection never jumps after save/rename

**Full Template detail pane:**
- Editable metadata grid (Display Name, Description, Target OS + Version, file path)
- Validate button: runs `packer init` (spinner) then `packer validate`, result shown inline
- Base Templates show "Create Custom Copy" button instead of Save/Revert (fork confirmation dialog)
- ⌘S to save

**Template Variables detail pane:**
- Orange security banner at top of editor
- Display Name + Description editable

**Building Block detail pane:**
- Read-only HCLEditor with Copy to clipboard
- Custom blocks: editable via `BuildingBlockEditSheet`, deletable with confirmation

**New object creation:** `NewPackerObjectSheet` — type picker (Full Template / Template Variables / Building Block) → kind-specific creation form

**NewBaseVMSheet overhaul:**
- Template section: None (auto-generate) / From library (filtered by OS+version) / Custom file path
- New Template Variables section: picker showing all vars files by display name
- Warning shown when vars file selected (may override credentials)

**BaseVMEditSheet:** same two-section template/vars picker

**VirtualMachine schema v5:**
- `customTemplateID: UUID?` — stable reference to library template (replaces `customTemplatePath: String?`)
- `customVarsFileID: UUID?` — vars file reference
- `customTemplatePath` retained for legacy migration

**BaseVMStore.build():**
- Resolves `customTemplateID` → URL via `PackerTemplateStore`
- Falls back to legacy `customTemplatePath` for v4 VMs
- Resolves `customVarsFileID` → `resolvedVarsName` used throughout build pipeline

**New files:** `PackerTemplate.swift` (rewritten), `PackerTemplateMetadata.swift`, `PackerTemplateStore.swift`, `BuildingBlock.swift`, `BuildingBlockStore.swift`, `RecipesViewModel.swift`, `TemplateDetailPane.swift`, `VarsFileDetailPane.swift`, `BuildingBlockDetailPane.swift`, `NewPackerObjectSheet.swift` (+ `HCLEditor.swift`, `NewTemplateSheet.swift` from 0.1.287)

## 0.1.287
- RecipesView refactor: split 490-line monolith into PackerTemplate.swift, HCLEditor.swift, NewTemplateSheet.swift, RecipesView.swift
- Added delete with confirmationDialog (moves to Trash, not permanent)
- Added inline rename: click pencil in toolbar or right-click → Rename; TextField appears in the row
- Added context menu on each row: Rename / Duplicate / Delete
- Stable UUIDs across reloads: loadTemplates() now preserves existing IDs by URL match, so selection never jumps after save
- Default templates are now read-only: HCLEditor gains isEditable param; Save/Revert hidden for defaults; "read-only" pill in toolbar
- Added .searchable() with ContentUnavailableView.search for no-results state
- ⌘S shortcut for Save
- "Edited" pill replaces "— Edited" text; modified date now shows time (not just date)
- NewTemplateSheet surfaces file creation errors in the form footer instead of swallowing them silently
- Duplicate copy naming now avoids stacking "-copy-copy-…" by stripping existing -copy suffix before appending

## 0.1.286
- ForEach stable IDs: `vm.tags` displays now use `enumerated()` + `\.offset` as identity in VMCard, VMDetailPane, VMListView, TagChip (removable list and suggestions) — prevents SwiftUI misidentifying chips when tags share a name or are removed mid-render
- MDM delete confirmations: deleting an MDM Profile or MDM Server now shows a `confirmationDialog` before executing — matches the confirmation pattern used in VMListView and BaseVMView

# Changelog

All notable changes to Oven are documented here.
Format: `[version] — description`


































---

## [0.1.282] — Consistency: refresh buttons, search, credential indicator

### Refresh buttons
BaseVMView: added ↻ button that calls syncOCI() to re-discover base VMs
from tart. Consistent with VMListView and InstallerView.
RegistryView: added ↻ button that calls syncFromTart() to re-sync OCI
images. Placed before the Cirrus Labs button.

### Search
BaseVMView: search field in toolbar, filters localVMs and registryVMs
by name, display name, and macOS version.
InstallerView: moved from shared appState.searchQuery to local @State
searchText — prevents search in Installers from polluting VMListView.
RegistryView: same fix — local searchText instead of shared state.
All search fields show an ✕ clear button when text is entered.

### Credential indicator — BaseVMDetailPane
Username row is now copyable (monospaced + copy button on hover),
matching VMDetailPane behaviour. Password row already showed
"Stored in Keychain" / "Not set" indicator.


## [0.1.280] — Template source picker + IPSW source cleanup

### Packer template source — NewBaseVMSheet
Replaced the conditional "only show if multiple templates exist" approach
with an explicit picker:
  [ ] Template library — shows library templates (auto-select if none)
  [ ] Custom filepath — Browse… to any .pkr.hcl or .json on disk
When a file is chosen from outside the library, Oven auto-imports it
(copies to the Packer templates folder) and logs the action.

### Packer template source — BaseVMEditSheet
Same two-option picker added for error/notBuilt base VMs:
  [ ] Template library — shows all .hcl/.json in the templates folder
  [ ] Custom filepath — Browse… to any file on disk
Pre-selects the current template if it's already in the library.

### IPSW source cleanup — NewBaseVMSheet
Removed the "Use downloaded IPSW" option (redundant — the auto mode
already checks the cache and skips downloading if found).
Three options remain:
  [ ] Download automatically (via ipsw.me / mist-cli)
  [ ] Custom file path
  [ ] Download from URL


## [0.1.277] — Base VM UX improvements + build log error reporting

### Build log: validation errors now shown inline
Template validation failures are written to the build log before throwing:
  ==> ERROR: Template validation failed
  ==> Template: defaults/base-tahoe-26.4.pkr.hcl
  ==> <packer error message>
Users no longer need to check Activity Log to understand why a build failed.

### Clone as Working VM — row-level access
Each Base VM row in the list now has:
- Swipe left to reveal "Clone as Working VM" button (local ready VMs only)
- Right-click context menu with "Clone as Working VM" and "Show Details"

### Re-categorise Base VM → Working VM
BaseVMEditSheet now has a "Category" section with a toggle "Use as Base VM".
Turning it off moves the VM back to the Virtual Machines view on next sync.
OCI-sourced VMs show a locked label instead of the toggle.

### IPSW auto-download label is now dynamic
"Download automatically (via mist-cli)" now reads the actual download method
from AppSettings: "via ipsw.me" or "via mist-cli" depending on Preferences.


## [0.1.271] — Build fixes: status, mist-cli syntax, IPSW naming, Picker snap

### "Not built" base VM status
VMStore.mergeWithTart now sets buildStatus=.ready for base-* named VMs
discovered via tart list. A VM present in tart list is by definition built.

### mist-cli download syntax
mist download firmware now uses --search <version> instead of a positional
arg. The positional version string was causing "Download <search-string> is
missing or empty" errors in newer mist-cli versions.

### IPSW filename standardisation
All IPSW downloads now target "macOS <version>.ipsw" (e.g. "macOS 15.4.1.ipsw").
Matches the display format in the Installers view. Cache detection checks for
the standard name first, then falls back to version string matching for
existing files with other naming patterns.

### Picker invalid selection
NewBaseVMSheet .task now snaps osVersion to the first available version after
fetchLiveVersions completes. Previously, if the firmware list was cached
(fresh), onChange(of: liveFirmwares) never fired and osVersion stayed "" —
causing Xcode to warn about an invalid Picker selection and the build to
fail when looking up the version in ipsw.me.

### Improved build logging
Build pipeline now always logs: OS name+version, hardware config, username,
IPSW filename, template and vars paths. Debug mode adds: IPSW storage root,
Rosetta/Homebrew/SSH flags, MDM profile ID.
When ipsw.me can't find a version, logs the first 5 available versions to
help diagnose version string mismatches.


## [0.1.263] — Option B: BaseVMStore absorbed into VMStore

Single unified store for all tart VMs. BaseVM model retired.

### VirtualMachine model additions
Build-related fields from BaseVM merged in: osName, ipswLocalPath,
ipswRemoteURL, installRosetta/Homebrew/SSHDaemon/AutoLogin/PasswordlessSudo,
xcodeVersion, builtAt, buildLog, packerTemplateName/VarsName,
customTemplatePath, vmSource (VMSource enum), buildStatus (BuildStatus enum).
Static helpers autoName/uniqueAutoName moved here.

### BaseVMStore
No longer owns storage. baseVMs computed property filters vmStore.vms for
effectivelyBase VMs. add/update/delete/build all delegate to VMStore.
Build pipeline (Packer, IPSW download, mist-cli) unchanged.

### VMStore
Gains migrateLegacyBaseVMs() — on first launch reads the legacy .baseVMs
AppDatabase file, converts records to VirtualMachine, merges into vms,
saves, and logs the migration count.

### AppDatabase
vms schema bumped to v4. .baseVMs key kept for legacy reads only.

### BaseVM.swift deleted
MacOSRelease catalogue (Name enum, fallbackVersions, displayLabel)
kept in VirtualMachine.swift via the existing import.

### All UI files updated
BaseVMRow, BaseVMViewModel, BaseVMEditSheet, BaseVMDetailPane, BaseVMView,
BuildLogView, LiveBuildLogPanel, NewBaseVMSheet, NewVMSheet, RegistryView —
all operate on VirtualMachine directly.

### Re-categorisation now works end to end
Any VM marked isBaseVM=true appears in Base VMs view via baseVMStore.baseVMs
filter. Edit sheet available from that view. NewVMSheet source picker shows
all baseVMStore.baseVMs (including re-categorised working VMs).


## [0.1.260] — isBaseVM: user-editable VM categorisation

### VirtualMachine model
- Added `isBaseVM: Bool` (persisted, default false)
- Added `isOCIBased: Bool` computed — true when registryImageRef != nil
- Added `effectivelyBase: Bool` — true if isBaseVM || isOCIBased
- AppDatabase schema for vms bumped to v3

### Rules
- Base VM: cannot be started, can be cloned into a working VM
- Working VM: can be started and cloned
- OCI/registry VMs: always base, effectivelyBase locked to true, toggle disabled in edit sheet

### VMStore
- mergeWithTart: auto-sets isBaseVM=true for newly discovered base-* named VMs
- base-* VMs no longer excluded from VMStore — effectivelyBase drives which view shows them
- startVM guarded: base VMs silently return without starting

### VMListViewModel
- filteredVMs excludes effectivelyBase VMs — working VMs view only

### VMCard
- Base VMs show a "Base VM" badge where Start/Stop buttons would be
- No Start button for effectivelyBase VMs

### VMEditSheet
- New "Category" section with Toggle "Use as Base VM"
- Toggle disabled (shows locked label) for OCI-sourced VMs
- Footer explains the current mode and how to change it


## [0.1.257] — SSH credentials: BaseVMEditSheet + detail pane improvements

### BaseVMEditSheet
Added "SSH credentials" section with username and password fields.
Username saved to BaseVM.defaultUsername, password to Keychain.
Existing password loaded from Keychain on appear.

### VMDetailPane — identity section
Shows stored SSH username (copyable) and "stored in Keychain" indicator
when a password exists, so the user can see at a glance whether credentials
are configured without exposing the password.

### VMDetailPane — SSH button
When a password is stored in Keychain, clicking "Open SSH in Terminal"
now copies the password to the clipboard automatically before opening
Terminal. The button tooltip says "password copied to clipboard" so the
user knows to paste (⌘V) when prompted for the password.


## [0.1.256] — Per-VM SSH credentials in Keychain

### VirtualMachine model
Added keychainKey ("vm.<uuid>.password") and sshPassword computed property,
mirroring the existing BaseVM pattern. Passwords never serialised to disk.

### VMEditSheet
New "SSH credentials" section with username + password fields. Username
saved to VM metadata, password saved to Keychain. Existing password loaded
from Keychain on appear. Available for any VM including those created
outside the app.

### PullDestinationSheet
Added username + password fields. Credentials are captured when the user
chooses Base VM or VM, then threaded through to routePulledImage and
createVMFromImage where they are stored on the created VM record.

### NewVMSheet
Added "SSH credentials" section. Seeds username/password from Packer
defaults in Preferences. Password stored in Keychain on the newly created
VM after cloning.

### RegistryView
routePulledImage uses credentials from PullDestinationSheet (via
RegistryViewModel.pendingPullUsername/Password) rather than global defaults.
createVMFromImage stores credentials on the VM after successful clone.

### BuildPrefsTab
Removed the "Default registry VM credentials" section — registry VM
credentials are per-VM, set at pull time or via VMEditSheet, not globally.
Packer and hardware defaults remain.


## [0.1.255] — Default hardware + credentials in Preferences

### Preferences → Build: new sections

**Default hardware** — CPU cores, memory, disk size stored in UserDefaults
via @AppStorage. Applied as initial values when opening New Base VM and
New VM sheets. Can still be overridden per-VM in those sheets.
Keys: defaultCPUCount, defaultMemoryGB, defaultDiskGB.

**Default Packer credentials** — username in UserDefaults, password in
Keychain under "defaults.packer.password". Used for Base VMs built from
Packer templates. NewBaseVMSheet seeds username+password from these
defaults on appear.

**Default registry VM credentials** — username in UserDefaults, password
in Keychain under "defaults.registry.password". Used when creating VMs
from registry images (RegistryView.routePulledImage). NewVMSheet also
seeds hardware from defaults.

All passwords stored via KeychainService — never in UserDefaults or on disk.


## [0.1.254] — macOS VM limit guard + Stop All button

### macOS 2-VM limit guard
macOS limits simultaneous macOS VMs to 2. Previously tart would fail with
a cryptic exit code. Now startVM() checks the running count first and
shows a clear alert: "macOS allows at most 2 simultaneous VMs. Currently
running: vm-name-1, vm-name-2."

### Stop All Running VMs
A "Stop All" button (red, bordered) appears in the Virtual Machines toolbar
whenever ≥1 VM is running. It's hidden when all VMs are stopped to keep
the toolbar clean. Tapping it shows a confirmation dialog before stopping
all running and suspended VMs concurrently.


## [0.1.250] — Phase 5: @Observable migration

All ObservableObject classes migrated to the Observation framework (@Observable).
Requires macOS 14+ which matches the project's deployment target.

### Classes migrated
VMStore, BaseVMStore, AppState, AppLogger, AppTheme, BuildMonitor,
BuildSessionManager, DependencyManager, TagStore, MDMServerStore

### Changes per class
- `final class Foo: ObservableObject` → `@Observable final class Foo`
- All `@Published var` → plain `var` (@Observable tracks all stored properties)
- `@Published private(set) var` → `private(set) var`
- Stale @Published comments removed

### Changes in views
- `@StateObject var foo = Foo()` → `@State var foo = Foo()` (OvenApp)
- `@ObservedObject var foo: Foo` → plain `var foo: Foo`
- `@EnvironmentObject` left in place — @Observable classes work with it
  as a compatibility bridge; full migration to @Environment custom keys
  is a future step

### Why this matters
@Published fires objectWillChange for ANY property mutation, causing all
subscribers to re-render even if the changed property isn't used.
@Observable tracks property access granularly — a view only re-renders
when a property it actually reads changes.


## [0.1.247] — @ViewBuilder subview extractions

Reduced body complexity in three files by extracting logical sections
into named @ViewBuilder computed vars and functions.

### VMDetailPane.swift
- headerSection: avatar icon + display name + tart name + StatusPill
- actionsSection: Divider + full VStack of SSH/stop/start/push buttons
- body reduced from ~255 to ~157 lines

### NewBaseVMSheet.swift
- sheetToolbar: title + Cancel + Build buttons with padding/background
- body reduced from ~206 to ~198 lines (toolbar was 11 lines)

### TagsPrefsTab.swift
- tagListHeader: description text + New Tag button + Divider
- tagRow(_:): full edit/display mode row for a single tag
- body reduced from ~174 to ~165 lines; tag row logic now in one place


## [0.1.245] — Mist-cli firmware list caching (24h)

MistService now caches firmware listings the same way IPSWService does:
- In-memory cache: instant on subsequent calls within the same session
- Disk cache (mist-firmware-cache.json): survives app restarts, 24h TTL
- Cache written after each successful mist list firmware call
- loadDiskCache() reads the file modification date as the cache timestamp

InstallerView wires mist cache state into the "Cached · X ago" indicator
using isMistCacheFresh() and mistCacheDate() helpers that read the cache
file modification date directly. The refresh button clears both the
IPSWService cache and the mist disk cache before reloading.

Previously mist list firmware ran as a subprocess on every view appearance,
which is slow (typically 3-10 seconds). Now it only runs once per 24 hours.


## [0.1.244] — Perf: .onAppear + Task{} → .task{}

Converted async .onAppear { Task { await ... } } patterns to .task {}.
.task is lifecycle-aware: it auto-cancels when the view disappears,
preventing leaked tasks from running after the view is gone.

NewBaseVMSheet: loadMDMData/loadLocalIPSWs/loadCustomTemplates/fetchLiveVersions
  now run in a single .task{} — fetchLiveVersions no longer leaks if the sheet
  is dismissed before the network call completes.

RegistryView: rvm.load + syncFromTart now in .task{} — the OCI discovery
  call cancels cleanly if the user navigates away before tart responds.

Other .onAppear blocks that contain only synchronous work (form population,
scroll position, value clamping, credential loading) are left as .onAppear
since .task would be unnecessary overhead for sync work.


## [0.1.235] — VM card: wallpaper thumbnails + inline action buttons

### Wallpaper thumbnails
VM cards now show the macOS wallpaper for the VM's OS version instead of
a system icon. Five wallpapers added to Assets.xcassets:
- wallpaper-tahoe    (macOS 26 Tahoe)
- wallpaper-sequoia  (macOS 15 Sequoia)
- wallpaper-sonoma   (macOS 14 Sonoma)
- wallpaper-ventura  (macOS 13 Ventura)
- wallpaper-monterey (macOS 12 Monterey)
Unknown OS versions fall back to the plain color+icon style.
Running/suspended/building VMs get a color tint overlay on the wallpaper
to maintain the status visual cue.

### Inline action buttons
The ellipsis menu is replaced with three small icon buttons (pencil,
doc.on.doc, trash) sitting directly next to the Start/Stop button.
All three have .help() tooltips. Start/Stop still fills remaining width.


## [0.1.233] — Fix: tag persistence + tag autocomplete

### Bug: tags not saved after editing a VM
VMStore.update(id:) applied the mutation in memory but never called
saveToDisk(). Tags, display names, descriptions, and shared folders
edited in VMEditSheet were lost on relaunch. Fixed by adding saveToDisk()
at the end of update().

### Improvement: tag autocomplete includes all defined tags
allKnownTags in VMEditSheet previously only pulled tags from existing VMs.
Tags defined in Preferences → Tags but not yet applied to any VM were
invisible to the autocomplete. Now unions vmStore VM tags with
tagStore.managedTags so all defined tags appear as suggestions.
TagStore injected into VMEditSheet via @EnvironmentObject.


## [0.1.228] — OCI auto-discovery + PreferencesView split

### Auto-discover OCI images in Registry view
RegistryViewModel gains syncFromTart(tartPath:vmStore:baseVMStore:) which
calls tart list --source oci and auto-adds any OCI refs not already tracked.
SHA256 digest variants (@sha256:...) are skipped — only tag refs are added.
Newly discovered images are marked isPulled=true and reconciled against the
VM stores. Runs on every appearance of the Registry view.

### PreferencesView split (761 → 28 lines)
Each preferences tab extracted into its own file:
- GeneralPrefsTab.swift     (27 lines)
- BuildPrefsTab.swift       (89 lines)
- StoragePrefsTab.swift     (139 lines)
- NotificationPrefsTab.swift (114 lines)
- IntegrationsPrefsTab.swift (166 lines, includes RegistryCredentialSheet)
- TagsPrefsTab.swift        (208 lines)
All six registered in pbxproj. PreferencesView.swift is now just the
TabView shell.


## [0.1.221] — Registry: dynamic host filter buttons

The ghcr.io / docker.io filter buttons in Image Registry were hardcoded.
Now `registries` is a computed property that unions:
- The two defaults (ghcr.io, docker.io) always first
- Hosts from all tracked image refs
- Hosts from all saved credentials in Preferences

New custom registry hosts appear automatically as soon as an image is
added or credentials are saved. An onChange guard snaps selectedRegistry
back to the first available host if the current selection disappears.


## [0.1.219] — Fix: mist installer duplicates use signed field

Previous attempt used `compatible` to deduplicate mist results, but that
incorrectly excludes releases signed by Apple but not compatible with this
specific machine model (e.g. compatible with VirtualMac2,1 but not MacBook).

Now filters on `signed == true` matching the jq command:
  mist list firmware --output-type json --quiet | jq '.[] | select(.signed == true)'

Added `signed: Bool` to MistFirmwareInfo with decodeIfPresent fallback.


## [0.1.218] — Bug fixes: OCI/Local classification, delete guard, mist duplicates

### Bug: OCI VM showing in Local section
A Base VM built from an OCI image (name = "ghcr.io/...") was appearing
in the Local section because source=.local (it was built locally via Packer).
Fixed by classifying VMs with "/" in their name into Registry regardless
of the source field, since "/" is never valid in a local tart name.

### Bug: mist-cli lists installers twice
mist list firmware returns both signed (compatible) and unsigned versions
of each release. Added `&& fw.compatible` to the supported() filter so
only installers compatible with this machine are shown.

### Feature: Base VM delete guard during active build
The delete confirmation button now checks status != .building before
proceeding. If the VM is currently building, the confirmation is dismissed
without deleting. The Delete button in the detail pane is also disabled
with a tooltip while building.

### loadProfileName: already uses AppDatabase (Phase 3)
VMDetailPane.loadProfileName was noted as reading disk directly — it was
already migrated to AppDatabase.shared.readOrDefault(.mdmProfiles) in
Phase 3. No change needed.

### Tag rename propagation: already implemented
commitRename() in PreferencesView already propagates the rename to all
VMs via vmStore.update. This was confirmed working since Phase 3 gave
PreferencesView access to vmStore.


## [0.1.217] — Fix: background thread publishing warnings

StreamConsumer.buildLog's appendLine callback was called synchronously
from a background Task (the stream consumer loop), but the callback
mutated @MainActor-isolated stores (BaseVMStore.update), causing:
  "Publishing changes from background threads is not allowed"

Fixed by marking appendLine as @escaping @MainActor and wrapping
each call in Task { @MainActor in appendLine(line) }, ensuring all
@Published mutations happen on the main actor.

Also noted: the Image Registry view does not auto-discover OCI images
from tart list --source oci. It maintains its own tracked list saved
to registry-images.json. Auto-discovery from tart is a future feature.


## [0.1.211–0.1.216] — Phase 3 fixes + RegistryImage migration

### AppDatabase generic constraint fixes (0.1.211–0.1.212)
All four generic methods (read, readOrDefault, write, writeSilently) now
require T: Codable. Envelope requires both Encodable and Decodable,
so Decodable-only or Encodable-only constraints caused compiler errors.
Data.WritingOptions.atomic specified explicitly to resolve type inference.

### Migration cleanup (0.1.213)
Removed unused `root` and `url` variables left over from the raw
JSONEncoder/Decoder migration. Removed duplicate saveToDisk() in BaseVMStore.

### RegistryImage backward compatibility (0.1.214–0.1.215)
Old registry-images.json files lacked the `registry` field added later.
Added a custom init(from:) that uses decodeIfPresent for `registry`,
falling back to the host component of imageRef (e.g. "ghcr.io").
Also added an explicit memberwise init since custom Codable inits
suppress the synthesised one, breaking call sites like RegistryImage(...).

### AppDatabase resilient fallback (0.1.216)
If both the envelope decode and the raw decode fail (e.g. file saved
with an incompatible older schema), read() now returns nil instead of
throwing, so readOrDefault returns the default value and logs a warning
rather than propagating an error that wipes the in-memory state.


## [0.1.210] — Phase 3: AppDatabase persistence layer

### AppDatabase registered in Xcode project
AppDatabase.swift existed but was never registered in the pbxproj —
it was silently excluded from compilation. All stores that referenced
AppDatabase.shared would have failed to build. Registered with the
registration script.

### Full migration to AppDatabase
All model persistence now routes through AppDatabase.shared, which wraps
each file in a versioned envelope (schemaVersion) enabling future migrations.

Migrated from raw JSONEncoder/Decoder:
- MDMServersView — load/save MDM servers
- MDMProfileView — loadProfiles/saveProfiles
- NewVMSheet — load MDM profiles + servers on appear
- NewBaseVMSheet — load MDM profiles + servers on appear
- VMDetailPane — load MDM profiles for enrollment display
- PushToRegistrySheet — load registry credentials
- PreferencesView — save/delete registry credentials
- BaseVMStore — inline MDM profile/server reads during build

### Intentionally excluded
- LogView/RecipesView: write user-facing text files, not model data
- TartService, JamfService, RegistryService: decode API responses
- AppDatabase.swift itself: the implementation


## [0.1.208] — Phase 4: StreamConsumer

New `Core/StreamConsumer.swift` eliminates the repeated
`for await event in stream { switch event { ... } }` pattern.

### StreamConsumer
Three static methods cover all use cases:
- `consume(_:onStdout:onStderr:)` — generic, returns StreamResult
- `logged(_:source:onLine:)` — routes to AppLogger per line
- `buildLog(_:source:appendLine:)` — appends to build log + Logger + BuildMonitor heartbeat
- `silent(_:)` — discards output, returns StreamResult

StreamResult exposes: stdoutLines, stderrLines, exitCode, succeeded,
combinedOutput — making exit-code checks and error extraction one-liners.

### Wired into:
- VMListViewModel.startVM — was 10 lines, now 4
- BaseVMStore packer build — was 30 lines, now 10
- BaseVMStore mist download — was 10 lines, now 4
- RegistryView pullImage — was 35 lines, now 15
- RegistryView createVMFromImage clone — was 15 lines, now 6


## [0.1.207] — Fix: friendly error messages for registry pull failures

parseTartError() was failing to extract the message from tart's
UnexpectedHTTPStatusCode error format:
  Error: UnexpectedHTTPStatusCode(when: "pulling manifest", code: 400,
    details: "{"errors":[{"message":"invalid repository name"}]}")

The old parser only handled JSON-style {"message":"value"} at the top level.
The new parser tries four patterns in order:
1. message field inside double-escaped details JSON
2. message field in plain JSON
3. when: "description" field from Swift struct format
4. CamelCase exception type name split into readable words (fallback)

Result: "400 — Invalid repository name" instead of "UnexpectedHTTPStatusCode".


## [0.1.204] — Fix registry VM clone + command logging

### Fix: Clone VM from registry image
createVMFromImage() was calling VMStore.clone(source:newName:) which wraps
`tart clone <local-source> <dest>` — tart rejects OCI refs as source here.

Now calls TartService.clone(imageRef:to:) directly, which runs:
  tart clone ghcr.io/org/image:tag local-name
tart resolves OCI refs from its local cache in this form. Derives a friendly
local name from the repo slug + tag (e.g. "macos-monterey-base-latest").

### Command logging in Activity Log
ProcessRunner.stream() now logs every command it runs as:
  $ /path/to/tart clone ghcr.io/... local-name
visible in Activity Log. Makes debugging process failures much easier
without needing to attach a debugger.


## [0.1.202] — Fix: Create VM from registry image

createVMFromImage() was passing the full OCI imageRef
(e.g. "ghcr.io/cirruslabs/macos-sequoia-base:latest") as the tart clone
source, which tart rejects with exit code 64: "should be a local name".

For OCI-sourced images, localName is set to the imageRef (how tart tracks
them in its OCI cache). The fix derives the correct local tart name the same
way pullImage does: take the last path component and replace ":" with "-",
giving "macos-sequoia-base-latest". Also generates a unique VM name to avoid
collisions with existing VMs.


## [0.1.201] — Bug fixes: IPSW sheet, Registry credentials label

### NewBaseVMSheetPreloaded → full NewBaseVMSheet
When tapping "Create Base VM" next to a downloaded IPSW in macOS Installers,
the app now opens the full NewBaseVMSheet instead of the stripped-down
NewBaseVMSheetPreloaded. This adds the previously missing options:
default credentials, Xcode, MDM Enrollment, custom Packer template.

NewBaseVMSheet gains a `preselectedIPSWURL` parameter. On appear it calls
`detectOS(from:)` to parse the IPSW filename and pre-populate OS and version,
then sets the IPSW source to Local Library and selects the file.

### Registry View — "rvm.credentials" label fixed
The ViewModel rename pass replaced text inside string literals, turning
"No credentials configured" into "No rvm.credentials configured" and
"Add credentials" into "Add rvm.credentials". Both strings restored.


## [0.1.186–0.1.199] — Phase 2 ViewModels + Phase 1 fixes

### Phase 1 — File extraction (0.1.186–0.1.188)
Extracted 16 structs from VMListView, BaseVMView, and RegistryView into
individual files. VMListView: 1,333→521 lines. BaseVMView: 1,257→213 lines.
RegistryView: 703→460 lines. New registration script with validation.

### Phase 2 — ViewModels (0.1.190–0.1.199)
Three @Observable ViewModels extracted from the view layer:

**VMListViewModel** — filter/sort/selection/action state from VMListView.
VMTab and VMSortOrder enums moved here. ViewModel property named `model`
to avoid shadowing the `vm` ForEach loop variable.

**BaseVMViewModel** — selectedBaseVMID, isPresentingNewSheet,
createVMFromBase, confirmDelete. Body split into listColumn/detailColumn
@ViewBuilder vars to resolve Swift type-checker timeout.

**RegistryViewModel** — images, credentials, pendingPull state plus
load/save/reconcile/addCirrusImage/inferOSFromRef methods.

### Bug fixes during Phase 2
- RegistryImage initializer: provided all required fields (id, registry,
  imageRef, isPulled) instead of non-existent imageRef-only convenience init
- BaseVMStore.delete: corrected call from delete(baseVM:) to delete(id:)
- register_swift_file.py: fixed double-comma bug in Sources phase insertion
- pbxproj: fixed 7 BuildFile entries with wrong fileRef IDs, fixed trailing
  comma issues throughout, restored all missing file registrations


## [0.1.190] — Phase 2: ViewModels

Three @Observable ViewModels extracted from the view layer.
No behavior changes — pure structural improvement.

### VMListViewModel (UI/VMListViewModel.swift)
Owns all filter/sort/selection/action state previously scattered
across VMListView @State vars:
- selectedTab, selectedTagFilters, selectedOSFilters, sortOrder, isListView
- selectedVM, confirmDelete, confirmStop, cloneVM, pendingLaunchVM, editingVM
- filteredVMs(), allTags(), allOSMajors(), osVersions() — computed from store
- startVM() — async action delegating to VMStore + AppState

### BaseVMViewModel (UI/BaseVMViewModel.swift)
Owns: selectedBaseVMID, isPresentingNewSheet, createVMFromBase, confirmDelete
- selectedBaseVM() — lookup helper
- delete() — clears selection then delegates to BaseVMStore

### RegistryViewModel (UI/RegistryViewModel.swift)
Owns all registry state: images, credentials, pendingPull, selectedRegistry etc.
- load(), saveImages(), saveCredentials() — persistence
- reconcileIsPulled() — syncs pulled state against vmStore + baseVMStore
- addCirrusImage(), addManualImage(), removeImage() — image management
- inferOSFromRef() — OS detection from image ref string
- makeRegistryService() — factory for RegistryService

### Registration script fix
register_swift_file.py now strips trailing commas before appending
to the Sources build phase list, preventing double-comma corruption.


## [0.1.186] — Base VM improvements: display names, unique names, IPSW fixes

### Display names + descriptions for Base VMs
- `BaseVM` model gains `displayName` and `vmDescription` fields (persisted).
- `BaseVMRow` updated to 4-line layout:
  - Line 1: Display name (or inferred friendly name for registry VMs)
  - Line 2: Tart name (monospaced, tertiary)
  - Line 3: OS + hardware (local) or pull date (registry)
  - Line 4: Provisioning flags + build date (local only)
- Registry VMs infer a friendly name from the image ref
  (e.g. `macos-tahoe-base:latest` → "Tahoe Base").
- `BaseVMDetailPane` header shows display name, tart name, description, status.
- New "Edit…" button in detail pane opens `BaseVMEditSheet` to set display name
  and description. Tart name and hardware shown read-only for reference.

### Bug #2: Unique tart name generation
`BaseVM.uniqueAutoName` appends a counter suffix (-2, -3…) when the base name
already exists, preventing silent overwrites of existing base VMs.
Both the name preview and the actual create() call use the unique variant.

### Bug #1: IPSW local library filter fixed
`loadLocalIPSWs` now matches by major version number (e.g. "15") in addition
to OS name ("sequoia"), so files named `macOS-15.6.1.ipsw` (no OS name in
filename) correctly appear when Sequoia is selected.

### Bug #3: InstallerView IPSW sheet auto-detects OS/version
When opening "New Base VM" from a downloaded IPSW in macOS Installers,
the OS picker and version are now pre-populated by parsing the IPSW filename.


## [0.1.178] — Lift vmStore/baseVMStore to OvenApp scope

`vmStore` and `baseVMStore` were `@StateObject` on `AppRootView`, making them
inaccessible to the `Settings {}` scene which runs in a separate window.

**Changes:**
- Both stores moved to `@StateObject` on `OvenApp` via static factory methods
  (`makeVMStore()`, `makeBaseVMStore()`, `resolvedTartPath()`).
- Injected via `.environmentObject` into both `WindowGroup` and `Settings` scenes.
- `AppRootView` now declares them as `@EnvironmentObject` instead of `@StateObject`,
  and its `init()` is removed entirely.

**Now enabled in Preferences → Tags:**
- VM usage count per tag (e.g. "3 VMs") restored.
- Rename propagation restored — renaming a tag in Preferences updates all VMs
  that had the old tag name.


## [0.1.169] — Tag management with colors

### TagStore
New `Core/TagStore.swift` — `@MainActor ObservableObject` persisting a
`[String: String]` (tag → hex color) map to `tag-colors.json`.
Provides `color(for:)`, `setColor(_:for:)`, `rename(tag:to:)`, `removeColor(for:)`.
Falls back to the deterministic palette for tags without an explicit color,
so existing tags continue to work without any migration.
Color hex helpers added to `Color` via extension (`init?(hex:)`, `hexString`).

### TagChip — color-aware
Reads from `TagStore` via `@EnvironmentObject` instead of calling
`tagColor(for:)` directly. Falls back to deterministic color if no
explicit color is set. Fully backward compatible.

### TagPickerField — optional color on creation
When a new (unknown) tag is committed, an inline color picker row appears
with a pre-seeded deterministic color, a "Set color" button, and a "Skip"
button. Known tags (already in TagStore) are added immediately.

### Preferences → Tags tab
New tab showing all tags from VMs + TagStore. Each row shows:
- ColorPicker swatch (click to change color immediately)
- TagChip preview
- VM usage count
- Pencil rename button (inline rename with Save/Cancel)
- Minus remove-color button (removes color entry; tag remains on VMs)
Toolbar + button opens a "New Tag" sheet with name + color picker + preview.
Rename propagates to all VMs that had the old tag via `vmStore.update`.

### VM list — tag filter menu
A tag icon button appears in the VM list toolbar when any VM has tags.
Clicking it opens a Menu with checkboxes for each tag. Active filters show
a blue badge with the count. Filtering requires all selected tags to match
(AND logic). "Clear Filter" option at the top when filters are active.


## [0.1.164] — Delete IPSW, Base VM live config, tech debt cleanup

### Delete downloaded IPSW
IPSWFirmwareRow now shows a trash button next to the "Downloaded" label.
Tapping it removes the file from disk and updates the row back to "Download"
using the same filename-matching logic as the downloaded detection.

### Base VM detail pane — live config via tart get
BaseVMDetailPane now loads CPU, Memory, Disk, and Display from
`tart get --format json` on appear (same as VMDetailPane). Shows a ↻
refresh button. Falls back to stored values if tart get fails or isn't
available (e.g. for OCI-sourced VMs that aren't running yet).

### Tech debt — TartUtils.swift
Created `Core/TartUtils.swift` as the single home for shared tart helpers:
- `inferMacOSVersion(from:)` — removed from VMStore (was duplicated)
- `inferOSName(from:)` — removed from BaseVMStore (was duplicated)
- `parseTartError(_:)` — moved from RegistryView.swift (wrong location)
All three are now free functions accessible across the entire module.

## [0.1.158] — OCI VMs in New VM picker, actual disk size, VM rename

### NewVMSheet — OCI base VMs always visible
`syncOCI()` now runs as a `.task` in NewVMSheet so registry-sourced base VMs
appear in the picker even if the user hasn't visited the Base VMs view yet.

### Actual disk size from tart list
`TartVMInfo.size` (the `Size` field from `tart list --format json`) is now stored
as `VirtualMachine.actualDiskGB` and synced on every `mergeWithTart` pass.
The VM card and detail pane show actual disk usage from tart rather than the
configured disk size. The detail pane shows a "Used" row alongside "Disk"
when live data is available.

### VM rename via tart rename
The Edit sheet now has an editable Tart name field (monospaced, validated to
letters/numbers/hyphens). On save, if the name changed, `VMStore.rename()`
calls `tart rename <old> <new>` and updates all metadata. Runs before hardware
changes so both can happen in one save.

## [0.1.158] — OCI base VMs in New VM sheet, VM rename, disk usage, parseTartError moved

### New VM sheet — OCI base VMs now selectable
Picker groups base VMs into Local and Registry sections.
OCI-sourced base VMs (pulled from Cirrus Labs etc.) appear under Registry.
`generatedName` handles registry VMs by using the image short name
(e.g. `sequoia-base-nomdm-abc123`) instead of the OS name/version fields
which are empty for OCI sources. Empty state message updated to mention
pulling as an alternative to building.

### VM rename
Tart name field added to the Edit sheet Identity section. Validates in
real-time: lowercases, strips invalid chars, checks for conflicts.
On save, calls `tart rename` if the name changed. Hardware and metadata
changes still apply in the same save.

### Live disk usage
VM cards now show actual disk usage from `tart list`'s `Size` field
(e.g. "32 GB used") instead of the provisioned size. Falls back to the
provisioned size if the value isn't available yet.

## [0.1.149] — Live VM config, stop timeout, VNC, copy buttons, quit guard

### Item 1 & 4: Live VM config via `tart get`
VMDetailPane now loads live hardware config from `tart get --format json` on appear.
CPU, Memory, and Disk reflect tart's actual view of the VM, not just what Oven stored.
A refresh button (↻) reloads config on demand. Display resolution shown when available.

### Item 3: `tart stop --timeout 30`
Stop now tries `tart stop --timeout 30` first (graceful shutdown), falling back to
immediate `tart stop` if that fails. Prevents hangs on unresponsive VMs.

### Item 6: VNC URL + copy-to-clipboard
- **VNC row** appears in the Network section when the VM has an IP address,
  showing `vnc://<ip>` with a copy button and an "Open VNC…" button that launches
  the system VNC client.
- **Copy button** (doc.on.doc) added to Tart name, IP address, and VNC URL rows.
  Flips to a green checkmark for 1.5s after copying.

### Items 2 & 7: Quit guard for running VMs
`AppDelegate.applicationShouldTerminate` checks for running/suspended VMs before
allowing quit. If any are active, shows an NSAlert listing them with "Quit Anyway"
and "Cancel" options. AppDelegate receives vmStore via AppRootView.onAppear.

## [0.1.143] — Biometric Keychain, Log export, Recipe duplicate, VM quick-clone

### #1 Biometric Keychain for sensitive credentials
Registry credential passwords and MDM server passwords now use
`KeychainService.storeSensitive` / `retrieveSensitive` (kSecAccessControlUserPresence)
requiring Touch ID or device passcode on access. Falls back to the regular store
for credentials saved before this update.

### #12 Activity Log export
"Export…" button in the Activity Log toolbar opens a save panel to write a plain
text file with timestamped, source-tagged log entries.

### #10 Recipes duplicate template
A doc.on.doc button appears in the template list toolbar when a custom (non-default)
template is selected. Copies the file with a -copy suffix and selects it immediately.

### #8 VM quick-clone from card menu
"Clone…" is now in the ⋯ menu on every VM card. Opens CloneVMSheet which lets the
user set a display name, shows the generated tart name (lowercased + random suffix
for uniqueness), and runs tart clone. All metadata (description, tags, CPU/RAM/disk,
SSH username) is copied from the source VM.

## [0.1.134] — Rebuild Metadata in Preferences → General

### Settings → General → Maintenance
A "Rebuild Metadata…" button under a new Maintenance section deletes all saved
`metadata.json` files for VMs and Base VMs, then rebuilds from scratch:
- `VMStore.resetMetadata()` — clears vms[], deletes JSON, re-runs `tart list --source local`
- `BaseVMStore.resetMetadata()` — clears baseVMs[], deletes JSON, re-runs:
  - `tart list --source OCI` → registers OCI VMs as registry-sourced Base VMs
  - `tart list --source local` filtered to `base-*` → registers local Base VMs

A confirmation dialog warns that display names, tags, and descriptions will be lost.
A progress indicator and "Done ✓" feedback appear during and after the rebuild.

This makes the source-routing changes retroactive — existing users can run
Rebuild Metadata once to move OCI VMs into Base VMs and clear local VMs
from the Virtual Machines view.

## [0.1.133] — VM source routing: local-only VMs list, OCI VMs in Base VMs

### Virtual Machines view — local only
`VMStore.sync()` now calls `tart list --source local` via `TartService.listLocal()`.
OCI-sourced VMs (pulled from a registry) no longer appear here.
The OCI sha256 dedup block in `mergeWithTart` is removed since it's no longer needed.

### OCI VMs auto-appear in Base VMs
`BaseVMStore.syncOCI()` calls `tart list --source OCI`, deduplicates sha256 aliases,
and registers any new OCI VMs as `BaseVM` records with `source: .registry` and
`status: .ready`. Called on `BaseVMView.task` so it runs every time the view appears.
The row subtitle shows "From registry" for OCI-sourced VMs.

### Push to Registry in Base VMs detail pane
"Push to Registry…" button appears in `BaseVMDetailPane` when:
- `baseVM.source == .local` (locally built, not pulled from a registry)  
- `baseVM.status == .ready` (build completed)
OCI-sourced and not-yet-built VMs don't show the push button.
Uses the same `PushToRegistrySheet` and `parseTartError` as the VM detail pane.

### TartService new methods
- `listLocal()` — `tart list --source local`
- `listOCI()` — `tart list --source OCI`
- `listFiltered(source:)` — shared implementation

## [0.1.126] — Push to Registry UI

### VM detail pane — Push to Registry
When a VM is stopped, a "Push to Registry…" button appears below "Start VM" in
the detail pane action area.

Tapping it opens `PushToRegistrySheet` which shows:
- **Account picker** — dropdown of saved registry credentials (auto-selects the first)
- **Name** — pre-filled with the VM's tart name, editable
- **Tag** — defaults to `latest`
- **Full ref** preview — live-updating `registry/username/name:tag`

Confirming starts the push via `TartService.push` with credentials injected as
env vars (same pattern as pull — no `tart login` step). Progress streams to the
Activity Log line-by-line. The detail pane shows a progress bar during push and
an error label on failure.

`TartService.push` now passes `tartEnv` (includes TART_HOME + registry credentials)
so pushes respect a custom TART_HOME and authenticate without a separate login step.

## [0.1.125] — Cirrus catalogue as sheet, pull status fix

### Cirrus Labs catalogue moved to a toolbar button
The catalogue no longer clutters the ghcr.io tab. A "Cirrus Labs" button in the
toolbar opens a sheet showing all public images grouped by OS in a clean List.
Tapping Add closes the sheet and immediately opens the pull destination prompt.
The image list is back to a plain List showing only the user's tracked images.

### Pull status updates immediately after completion
Previously the row reverted to "Pull" after a successful pull until the user
navigated away and back. Fixed: `images[idx].isPulled = true` is set in-memory
immediately in the same @MainActor context as the UI, so the row switches to
"Create VM" as soon as the pull finishes without any navigation.

## [0.1.124] — Cirrus Labs public image catalogue

The Image Registry view (ghcr.io tab) now shows a collapsible catalogue of all
Cirrus Labs public macOS images above the user's tracked image list.

Images are grouped by OS (Tahoe → Sequoia → Sonoma → Ventura → Monterey),
each with three variants:
- **Vanilla** (apple.logo) — clean macOS, nothing extra
- **Base** (shippingbox.fill, orange) — Homebrew, Git, build tools
- **Xcode** (hammer.circle.fill, blue) — Base + latest Xcode

Tapping **Add** on a catalogue row:
1. Adds the imageRef to the tracked list
2. Immediately opens the pull destination sheet (Base VM or Virtual Machine)

Already-tracked images show a green "Added" checkmark instead of the Add button.
In-progress downloads show the progress bar.

The catalogue is hardcoded (no API call) — Cirrus Labs public images are stable
and well-known. The section collapses with animation to keep the view tidy when
not needed.

## [0.1.115] — parseTartError handles UnexpectedHTTPStatusCode format

The error from pulling an invalid ref is `UnexpectedHTTPStatusCode`, not `AuthFailed`.
Different field names: `code: 400` (integer) and `when: "..."` instead of `why: "..."`.

Parser now handles both formats:
- Looks for `code: <digits>` first (covers UnexpectedHTTPStatusCode)
- Falls back to extracting HTTP status from the `why:` string (covers AuthFailed)
- `details:` JSON extraction is identical for both — produces "400 — Invalid repository name"

## [0.1.114] — Drop tart login, fix error parsing

### tart login removed
Per https://github.com/cirruslabs/tart/issues/596, tart reads
`TART_REGISTRY_USERNAME` and `TART_REGISTRY_PASSWORD` env vars automatically
for pull/clone — no `tart login` step needed. `tart login --username` was also
failing (exit 64) because tart requires `--password-stdin` alongside `--username`
but we weren't piping the password via stdin.

Fix: credentials are injected directly into `TartService.tartEnv` when constructing
the service for a pull, so every tart subprocess in that call inherits them. No
separate login subprocess runs at all.

### parseTartError rewritten (third attempt)
The previous version correctly extracted `why` but the `detailMessage` path
was silently returning nil — the `replacingOccurrences` call used the wrong
escape level in Swift source (`"\\\""` instead of `"\\\""`).

Rewritten with explicit step-by-step string operations and clear comments on
what each escape level means. Now correctly produces "400 — Invalid repository name"
from the AuthFailed error.

## [0.1.113] — Fix partial line delivery in ProcessRunner

### Root cause of inconsistent error truncation
tart writes long lines (the full Error: AuthFailed(...) message is ~300 chars)
which arrive in multiple `readabilityHandler` callbacks. The previous code split
each chunk on `\r\n` and yielded immediately — so a line arriving as two chunks
was yielded as two partial lines. `parseTartError` found "Error:" in the first
chunk and parsed a truncated string, explaining the different truncation lengths
in each run (chunk boundaries are non-deterministic).

### Fix: line buffering in ProcessRunner.stream
Each pipe handler now carries a `buf` string across callbacks. Incoming data is
appended to the buffer and split on `\r\n`. All complete lines (all but the last
fragment) are yielded; the trailing partial is kept in `buf` until the next chunk
arrives. On termination, a synthetic `\n` flushes any remaining partial line.

This fixes error parsing for tart and also improves packer/mist-cli log accuracy
since those also produce long lines that could split across callbacks.

## [0.1.112] — Fix tart error parsing (rewrite parseTartError)

The previous implementation used `.regularExpression` range matching and nested
raw strings which produced fragile escaping. The errorType regex matched but the
why/details extractions silently failed, leaving only the fallback "AuthFailed".

Rewritten with plain `range(of:)` string search:
1. Find `why: "` → read to closing `", ` → HTTP status code extracted from the text
2. Find `details: "` → unescape `\\"` → `"` → decode JSON array → take `message`
3. Format as `"<status> — <message>"` e.g. "400 — Invalid repository name"
4. Falls back to the why string, then the error type, then the raw line

## [0.1.111] — Parse tart error messages into human-readable alerts

tart errors follow a structured format:
`Error: AuthFailed(why: "...", details: "{\"errors\":[{\"code\":\"...\",...}]}")`

`parseTartError()` extracts three layers and builds the friendliest available message:
1. `details` JSON → `message` field (e.g. "Invalid repository name")
2. `why` value (HTTP-level description) appended if it adds context
3. Error type (AuthFailed, NotFound, etc.) as final fallback

Examples:
- `NAME_INVALID` → "Invalid repository name — received unexpected HTTP status code 400…"
- `UNAUTHORIZED` → "Authentication required"
- Unknown format → last non-empty line of the raw output

The **full raw error** (all collected stderr/stdout lines) is always logged to the
Activity Log for debugging. The **parsed friendly version** appears in the alert.

## [0.1.110] — Fix tart login blocking, stdin, and credential passing

### Root cause: `tart login` blocking on stdin
`tart login <registry>` waits for stdin if it can't resolve credentials non-interactively.
When launched from Oven (which inherits a null/pipe stdin from Xcode/launchd),
the process blocked indefinitely — hence three stuck `tart login ghcr.io` processes
visible in `ps aux`.

Three fixes:

**1. `ProcessRunner` redirects stdin to `/dev/null`**
All subprocesses now have `process.standardInput = FileHandle.nullDevice`.
Interactive prompts can never block — tart login fails fast with an error instead
of hanging, and the error surfaces in the Activity Log.

**2. `TartService.login` passes `--username` explicitly**
`tart login --username <user> <registry>` is the non-interactive form.
With stdin closed and the username flag set, tart reads the password from
`TART_REGISTRY_PASSWORD` env var and completes immediately.
Also now includes `tartEnv` (TART_HOME) in the environment.

**3. `RegistryService.login` delegates to `TartService.login`**
Previously duplicated the runner.run call without `--username`. Now routes
through the single correct implementation in TartService.

## [0.1.109] — Registry pull: correct tart commands, CR progress, persistent state

### tart pull vs tart clone — correct commands per destination
- **Base VM** → `tart pull <imageRef>` — caches OCI layers to `$TART_HOME/cache`,
  image appears as an OCI source entry in `tart list`. No local name needed.
- **Virtual Machine** → `tart clone <imageRef> <localName>` — creates a named
  local copy that appears as a local VM in `tart list`.
Previously both paths used `tart clone` which is wrong for Base VMs.

### CR progress output from tart
tart writes pull progress using carriage return (`\r`) to overwrite the same
terminal line rather than newlines. `ProcessRunner` was splitting only on `\n`,
so progress updates were buffered and never yielded until the process ended.
Changed all splits to `CharacterSet(charactersIn: "\r\n")` so each progress
update arrives as a separate event and the progress bar animates correctly.

### Pull progress persists across navigation
`activeDownloads` was `@State` on `RegistryView` — it reset to empty every time
the user navigated away and back. Moved to `AppState.registryDownloads`
(`@Published`, app lifetime) so an in-progress pull survives sidebar navigation.

### RegistryService pull signature
`pull(imageRef:localName:asBase:credentials:)` — the `asBase` parameter selects
`tart pull` vs `tart clone` at the service layer.

## [0.1.108] — Registry: error surfacing, dedup feedback, row delete

### @MainActor on async registry functions
`pullImage`, `routePulledImage`, `createVMFromImage`, and `reconcileIsPulled`
are now explicitly `@MainActor`. Without this, Swift 6 can hop off the main
actor between `for await` iterations, making `@State` mutations (errorMessage,
images, activeDownloads) and `AppLogger.shared` calls silently drop or crash.
This was the root cause of errors not appearing in the Activity Log or alert.

### Dedup shows error alert
When Add is clicked with an imageRef already in the list, an error alert now
explains "X is already in your image list" instead of silently clearing the field.

### Remove from list
Each image row has an `⋯` menu with a "Remove from list" action so stale or
invalid entries (like the bare `ghcr.io/cirruslabs` entries) can be cleaned up.
Removing a row deletes it from the in-memory list and saves immediately.

## [0.1.107] — Registry: dedup, tart error from stdout, progress bar stuck

### Duplicate image refs prevented
Clicking Add with an imageRef already in the list is now a no-op — the field
clears and no duplicate entry is added. Images are keyed on imageRef.

### tart errors captured from stdout
tart writes "Error: AuthFailed..." and similar errors to stdout, not stderr.
The pull event loop now checks stdout lines for "Error:" prefix and collects
them alongside stderr lines for the failure alert.

### Progress bar stuck at 0%
Two causes:
1. `activeDownloads` was only cleaned up inside the `.exit` case. A `defer`
   block now guarantees cleanup regardless of how the pull loop exits.
2. When tart fails immediately (before any progress), it now correctly removes
   the progress entry and shows the error alert instead of staying at 0%.

## [0.1.106] — Registry UX: host picker, full URL input, tart error surfacing

### Add Registry credential sheet — host picker
The free-text "Host" field in Preferences → Integrations → Add Registry now shows
a dropdown: "GitHub Container Registry (ghcr.io)", "Docker Hub (docker.io)", or
"Other…" which reveals a custom host text field. Pre-populates correctly when
editing an existing credential.

### Image Registry view — full URL input restored
The addImageBar reverts to a single full-URL text field (`ghcr.io/org/image:tag`).
The host picker belongs in the credential sheet, not here.

### Pull errors — tart stderr surfaced in alert
Previously any pull failure showed "Pull failed for <ref>" with no detail.
stderr is now collected line-by-line during the pull stream. On non-zero exit,
the first line containing "Error:", "invalid", or "failed" is shown in the alert
so the user sees tart's actual message (e.g. "Error: AuthFailed…NAME_INVALID").
The full stderr is also logged to the Activity Log.

## [0.1.105] — Fix Add Credentials button and unreachable default

- `NSApp.sendAction(Selector("showSettingsWindow:"))` is deprecated — SwiftUI
  Settings scenes must be opened via `SettingsLink`. Replaced the button with
  `SettingsLink { Text("Add credentials") }` which opens the Settings window
  correctly on macOS 15
- Removed `default: break` from the `pullImage` switch — `ProcessEvent` has
  exactly three cases (.stdout, .stderr, .exit), all handled, so the default
  was unreachable and produced a compiler warning

## [0.1.104] — Fix .accentColor in RegistryView
`.foregroundStyle(.accentColor)` → `.foregroundStyle(Color.accentColor)` —
`ShapeStyle` has no static member `accentColor` on macOS 15.

## [0.1.103] — Registry view overhaul: pull flow, isPulled, nav fix, host picker

### Stuck-screen bug fixed (NavigationLink in NavigationSplitView)
`NavigationLink(destination: PreferencesView())` inside a detail column replaced
the entire split-view detail with Preferences, with no way back. Replaced with
`NSApp.sendAction(Selector(("showSettingsWindow:")))` which opens the Settings
window as a separate floating panel — the correct macOS pattern.

### Pull destination asked BEFORE pulling
Previously the destination sheet appeared after a pull completed (and was never
actually wired to fire). Now clicking Pull immediately shows "Use as Base VM or
Virtual Machine?" — the pull starts only after the user chooses. This avoids
pulling a 16GB image to the wrong place.

The chosen destination also affects the local tart name:
- Base VM: prefixed with `base-` so `VMStore.mergeWithTart` filters it out and
  `BaseVMStore` picks it up automatically
- Virtual Machine: uses the plain derived name

### isPulled reconciled against tart list
Replaced filename-guessing with `reconcileIsPulled()` which cross-references
saved `RegistryImage` records against `vmStore.vms` + `baseVMStore.baseVMs`
by both `registryImageRef` and expected local name. Called on load and after
every pull + sync so the pulled indicator is always accurate.

### Add image bar — host picker
The free-text "ghcr.io/org/image:tag" field is split into a `Picker` for the
registry host (ghcr.io / docker.io) and a text field for the path/tag. Prevents
typos in the host, keeps the field shorter, and makes the supported registries
explicit.

## [0.1.102] — Registry pull → Base VM wiring complete

### routePulledImage Base VM path fully implemented
Previously the "Use as Base VM" path only logged a message. Now:
1. Infers OS name from the image ref (tahoe/sequoia/sonoma/ventura)
2. Creates a `BaseVM` record with `status: .ready` and `builtAt: Date()` —
   skips the build step since the image is already on disk
3. Overrides the auto-generated `name` with the actual local tart VM name
   (e.g. `macos-tahoe-base-latest`) so it matches what `tart list` returns
4. Calls `baseVMStore.add()` so the VM appears immediately in the Base VMs
   view and is available as a clone source in New VM

### RegistryView gains baseVMStore
`@EnvironmentObject var baseVMStore: BaseVMStore` added — inherits from the
root `OvenApp` environment, no explicit injection needed.

## [0.1.101] — Registry + VM grid improvements

### 1. Uniform VM card height (tags)
Tag chips were making tagged VM cards taller than untagged ones. Fixed by always
rendering the tag row with a fixed height — using `Color.clear` as a placeholder
when no tags are set, same as the tart name row fix.

### 2. OCI sha256 dedup in tart list
`tart list` returns two entries for a pulled OCI image: one for `registry/image:tag`
and one for `registry/image@sha256:...` (the sha entry is a symlink on disk).
`mergeWithTart` now deduplicates these — sha256 entries are dropped when a
tag-named entry for the same image is present. Only one entry per OCI image
appears in the Virtual Machines view.

### 3. Tahoe + registry name in OS inference
`inferMacOSVersion` now handles:
- `macOS Tahoe` (major version 26) — added to `MacOSRelease.Name` enum
- OCI registry paths like `ghcr.io/cirruslabs/macos-tahoe-base:latest` —
  strips the registry prefix and tag suffix before matching
- Added Monterey to the synonym list

### 4. isPulled synced from vmStore on load
On launch, saved registry images now cross-reference `vmStore.vms` to check
whether the pulled VM is actually on disk. Fixes the "already pulled but shows
as not pulled" state after an app restart.

### 5. Pull destination sheet
After a successful pull, a sheet asks "Use as Base VM or Virtual Machine?":
- **Base VM** — registers the local VM in the Base VMs view as a source for cloning
- **Virtual Machine** — creates a new VM record directly in the Virtual Machines view

## [0.1.100] — Non-blocking IP polling, SSH button enabled sooner

### Non-blocking IP resolution (#7 from backlog)
`refreshIP(for:)` previously called `tart ip --wait 5` once and gave up.
Replaced with a polling loop that retries every 3 seconds for up to 90 seconds,
stopping as soon as an IP is returned or the VM stops running.

- `VirtualMachine.isResolvingIP: Bool` (transient, not persisted) tracks poll state
- The IP row in the detail pane shows a `ProgressView` spinner while resolving
  and disables the refresh button to prevent double-polls
- Polling starts automatically when the detail pane opens for a running VM
- `tart ip --wait 3` used per attempt — short enough to be responsive,
  long enough for tart to do one DHCP check

### SSH button behaviour
The "Open SSH in Terminal" button stays disabled until `ipAddress` is set.
Once the IP resolves (which now happens automatically within ~3–90s of the VM
starting), the button enables without any user action.

### Temp .command file cleanup
`oven-ssh-*.command` files written to `/tmp` for Terminal launch are now cleaned
up on next app launch so they don't accumulate across sessions.

## [0.1.099] — Fix SSH Terminal launch using .command file

`NSWorkspace.open([], withApplicationAt: Terminal.app, configuration:)` ignores
`config.arguments` — Terminal doesn't treat launch arguments as commands to run.

Fix: write a temp `~/tmp/oven-ssh-<id>.command` shell script containing the ssh
command, make it executable (`chmod 0755`), then open it with `NSWorkspace.shared.open(url)`.
macOS registers `.command` files as Terminal-executable scripts — Terminal opens a
new window, runs the script, and the ssh session starts automatically. No AppleScript,
no automation permission, no entitlement changes needed.

Also removed the `AppLogger.shared` call from the Sendable closure that caused
the two Swift 6 actor-isolation warnings.

## [0.1.098] — Fix Open SSH in Terminal using NSWorkspace

`NSAppleScript` requires the user to grant Automation permission to Oven in
System Settings → Privacy & Security → Automation, which was never prompted
and silently failed.

Replaced with `NSWorkspace.shared.open(_:withApplicationAt:configuration:)`
passing the ssh command as `config.arguments` — equivalent to running
`open -a Terminal "ssh user@ip"` in the shell. Terminal opens a new window
and immediately connects. No special entitlements or permission prompts needed,
works with distribution via GitHub (no App Store sandboxing concerns).

## [0.1.097] — Fix "Open SSH in Terminal" button + correct username

### SSH button was silently doing nothing
The button called `openSSH(vm:)` which guards on `vm.ipAddress`. When the IP
was present, the AppleScript ran correctly but used `"admin"` as the hardcoded
username — which is wrong for Oven-built VMs (default user is `"baker"`).

### sshUsername stored on VirtualMachine
- `VirtualMachine` gains `sshUsername: String = "baker"` (default)
- `VMStore.clone()` accepts and stores `sshUsername`
- `NewVMSheet.createVM()` passes `base.defaultUsername` so the correct username
  from the Base VM flows through to the cloned VM
- `openSSH(vm:)` now uses `vm.sshUsername` with a `"baker"` fallback
- `VirtualMachine.init(from:)` uses `decodeIfPresent` with `"baker"` default
  so existing saved VMs get the right fallback automatically

## [0.1.096] — Fix AppSettings custom Decodable init compiler errors

Adding `init(from:)` suppresses Swift's synthesised memberwise init, which broke
`AppSettings(vmStorageRoot:...)` in the `default` static var. Fixed by:
1. Adding an explicit memberwise `init(...)` to restore that call site
2. Adding `enum CodingKeys` (required by `decodeIfPresent`)
3. Removing the `AppLogger.shared.warning(...)` call from `load()` — 
   `AppSettings.load()` is called from a nonisolated synchronous context and
   `AppLogger.shared` is `@MainActor`-isolated, which is a Swift 6 error

## [0.1.095] — Phase 1: correctness & data safety

### #2 — AppSettings Codable migration safety
Added a custom `init(from:)` using `decodeIfPresent` for every field so adding
new settings in a future build doesn't wipe existing user preferences. Falls back
to the field's default value if the key is absent in the saved JSON. The `load()`
method now logs a warning if the top-level decode fails rather than silently
returning defaults.

### #3 — lastStartedAt inferred from disk.img modification time
`tart` doesn't expose a last-started timestamp in `tart list`. Instead, every time
a VM runs, tart writes to `$TART_HOME/vms/<name>/disk.img`. `mergeWithTart` now
reads the modification date of that file on each sync and updates `lastStartedAt`
if it's newer than the stored value — meaning VMs started externally (via Terminal
or another tool) are correctly reflected in the "Last started" sort order and detail
pane. The date is only trusted if it's after the VM's creation date (rules out the
initial disk image write during build).

### #4 — TART_HOME forwarded to all tart subprocesses
`TartService` now builds a `tartEnv` dictionary from `AppSettings.load().resolvedTartHome`
and passes it as `environment:` to every `runner.run` and `runner.stream` call —
`list`, `run`, `stop`, `suspend`, `clone`, `delete`, `ip`, and `set`. Previously
only the packer subprocess received `TART_HOME`; `tart run` and `tart clone` would
use the system default `~/.tart` regardless of the configured path, breaking shared
folders and VM discovery when TART_HOME pointed to an external drive.

### #1 — Partial build cleanup (tart handles automatically)
Confirmed: tart automatically removes the partial VM on build failure. No Oven-side
cleanup needed.

## [0.1.094] — Fix RegistryCredential missing id: argument

`RegistryCredential` uses a synthesised memberwise init that requires `id: UUID`.
The `RegistryCredentialSheet` was calling `RegistryCredential(registry:username:)`
without the `id:` argument. Fixed to `RegistryCredential(id: UUID(), registry:username:)`.

## [0.1.093] — Fix three errors in tabbed PreferencesView

- `testPushover()` / `testSlack()` return `Result<Void, NotificationError>`,
  not `Bool` — replaced ternary with `switch result { case .success/failure }`
- `RegistryCredentialSheet` was missing from the rewritten file — added back

## [0.1.092] — Preferences redesigned as tabbed Settings window

Replaced the single long scrolling Form with five icon tabs matching the
macOS Settings pattern (Contacts, Tailscale style):

| Tab | Icon | Contents |
|---|---|---|
| General | gearshape | Appearance: Fun Mode, Debug Mode |
| Build | hammer | Safeguards (timeout/heartbeat/battery), Behaviour (sleep/lock/window), Completion action, IPSW download method |
| Storage | externaldrive | TART_HOME, IPSWs, Packer templates, Dependencies — each with Open in Finder |
| Notifications | bell.badge | Pushover + Slack with saved-credential indicators |
| Integrations | puzzlepiece.extension | Registry credentials |

Each tab is a private struct with its own state — no shared @State clutter.
The Settings sheet now opens to a compact per-tab view rather than a long
scroll. All logic (copy TART_HOME, fileImporter, test notifications, credential
save/delete) is preserved within the appropriate tab.

## [0.1.092] — Tabbed Preferences window (General / Build / Notifications / Registry)

Replaced the single long-scroll Form with a four-tab layout matching the macOS
HIG pattern used by Contacts, Tailscale, and System Settings:

- **General** — Appearance (Fun Mode, Debug Mode) + Storage locations (TART_HOME,
  IPSWs, Packer templates, Dependencies) with Open in Finder and Change buttons
- **Build** — Safeguards (timeout, heartbeat, battery), Behaviour (sleep, VM window,
  input lock), Input lock extras (overlay hint, after-build action), IPSW download
  method (ipsw.me vs mist-cli)
- **Notifications** — Pushover (token, user key, save/update, test) and Slack
  (webhook URL, save/update, test) with Keychain saved-state indicators
- **Registry** — Registry credential list with add/edit/delete and Keychain lock icons

Each tab is a separate private `View` struct so state is scoped correctly and the
file stays readable. The tab bar uses SF Symbols with filled variants for the active
tab and accent colour highlight, consistent with macOS conventions.

## [0.1.091] — Credential saved state in Pushover and Slack settings

When credentials are already stored in Keychain:

- **Green lock icon** (`lock.fill`) appears next to each field with tooltip
  "Saved in Keychain" — visible at a glance without revealing the value
- **Field prompt** changes from "Required" to "Saved" (Pushover) or from the
  URL placeholder to "Saved" (Slack) — distinguishes "nothing stored" from
  "something is stored"
- **Button label** changes from "Save credentials" → "Update credentials" and
  "Save webhook" → "Update webhook" — communicates that an action replaces
  existing data rather than creating it for the first time

All checks use `NotificationService.shared.pushoverAppToken` /
`pushoverUserKey` / `slackWebhookURL` which read directly from Keychain,
so the indicators are accurate immediately on view appear.

## [0.1.090] — Cache age label drops seconds

`Text(_:style: .relative)` auto-formats with seconds precision ("5 min, 15 sec ago").
Replaced with a `coarseAge(of:)` helper that rounds to the coarsest meaningful unit:
- < 2 min → "just now"
- < 1 hr  → "X min ago"
- < 1 day → "X hr ago"
- ≥ 1 day → "Xd ago"

## [0.1.089] — IPSW match: strip extension before version boundary check

Root cause of the persistent mismatch:

`macOS-15.6.1.ipsw` — after "15.6.1" comes "." (the file extension separator).
Our rule rejected "." because it could indicate another version component
(e.g. "15.6" → "15.6.1"). But that "." is the extension, not a version dot.

Fix: operate on the filename **stem** (extension stripped) for the boundary check:
- `macOS-15.6.1` → after "15.6.1" comes `nil` → match ✓  
- `macOS-15.6.1` → after "15.6" comes `.1` → `.` → reject ✓
- `UniversalMac_15.6.1_24G90_Restore` → after "15.6.1" comes `_` → match ✓
- `UniversalMac_15.6.1_24G90_Restore` → after "15.6" comes `.` → reject ✓

The exact-filename and buildid checks (paths 1 and 2) are unchanged.

## [0.1.088] — IPSW match fix (dot boundary), cache label, uniform card height

### IPSW downloaded indicator — dot boundary fix
Previous fix checked `!nextChar.isNumber` but `.` is not a number, so "15.6"
still matched "15.6.1" (next char is `.`). The correct rule: the character after
the version string must be `nil`, `-`, or `_` — anything else (including `.`)
indicates more version components follow. "15.6" in "macOS-15.6.ipsw" is followed
by "." then non-digit, so this also needs care: we check the stem only.
Final rule: next char must be nil, `-`, or `_`.

### Installer toolbar — last refreshed label
- `"Loaded N firmwares from cache"` vs `"…from ipsw.me"` / `"…from mist-cli"`
  logged to Activity Log so you can verify the 24h cache is working
- Toolbar shows `"Cached · X min ago"` or `"Refreshed · X min ago"` using
  SwiftUI's relative time `Text(_:style:)` which auto-updates
- `IPSWService.lastFetchDate` changed to `private(set)` so InstallerView can read it

### VM grid — uniform card height
Cards with a display name had an extra row vs cards without, causing mismatched
heights in the grid. Fixed by always rendering the tart name row — showing a
non-breaking space when the row isn't needed — so every card has identical
vertical structure regardless of whether a display name is set.

## [0.1.087] — Fix IPSW downloaded indicator (version boundary match)

The previous fix over-corrected: removing `.contains(fw.version)` broke
detection of mist-cli downloads (named `macOS-15.6.1.ipsw`) since those don't
contain the buildid or Apple's `suggestedFilename`.

The new match logic tries three checks in order:
1. Exact Apple filename `UniversalMac_15.6.1_24G90_Restore.ipsw`
2. Buildid substring (unique per build, e.g. `24G90`)
3. Version string followed by a non-digit character — `15.6.1` matches
   `macOS-15.6.1.ipsw` (followed by `.`) but NOT `UniversalMac_15.6.10_…`
   (followed by `0`). This correctly distinguishes `15.6` from `15.6.1`.

## [0.1.086] — Fix conditional .buttonStyle in BaseVMDetailPane

`.buttonStyle()` requires a concrete type at the call site — passing a ternary
expression returning protocol existentials (`.bordered` vs `.borderedProminent`)
doesn't compile. Restructured as an `if/else` block so each branch has a concrete
`.buttonStyle(...)` modifier.

## [0.1.085] — Fix missing preselectedBase property in NewVMSheet

`preselectedBase: BaseVM?` was referenced in `initHardware()` but never declared
as a property on the struct — the patch that added it didn't persist. Added as
`var preselectedBase: BaseVM? = nil` at the top of `NewVMSheet`.

## [0.1.084] — Fix IPSWFirmware Codable conformance

`CachePayload: Codable` requires all its properties to be `Encodable`, but
`IPSWFirmware` was only `Decodable`. Changed to `Codable` so the disk cache
can both write and read firmware entries.

## [0.1.083] — IPSW match fix, 24h firmware cache, Create VM from Base VM

### IPSW downloaded indicator — exact match fix
`isDownloaded` was using `.contains(fw.version)` which is a substring match —
"15.6" is contained in "15.6.1", so both showed as downloaded when only one
was on disk. Fixed to match on `fw.suggestedFilename` (exact filename including
buildid) or `fw.buildid` (unique per build). "15.6" and "15.6.1" now correctly
show independently.

### Firmware list cache — 24h TTL with disk persistence
- Cache TTL changed from 1 hour to 24 hours
- Cache is now persisted to `~/Library/Application Support/Oven/ipsw-firmware-cache.json`
  and loaded on next app launch — avoids hitting the network on every restart
- `isCacheFresh` helper property lets callers check staleness without fetching
- Network is only hit in these scenarios:
  1. Cache is absent or older than 24h
  2. User taps the Refresh button (calls `invalidateCache()` first)
  3. New Base VM sheet opens and data is stale
- `invalidateCache()` now also deletes the disk cache file

### Create VM button on Base VM detail pane
- When a Base VM has `status == .ready`, a "Create VM" button appears at the
  top of the action area in the detail pane
- Tapping it opens `NewVMSheet` pre-populated with that base VM already selected
  as the source — hardware settings (CPU, RAM, disk) are copied from the base VM
- `NewVMFromBaseSheet` wrapper handles environment injection
- Rebuild button demoted to `.bordered` style when Create VM is primary action

## [0.1.082] — ForEach duplicate IDs, thumbnail centering, date labels, full card metadata

### ForEach duplicate ID warning
`ForEach(buildLog.suffix(30), id: \.self)` uses log line strings as IDs — packer
outputs many identical lines (timestamps, plugin chatter) causing SwiftUI's
"ID occurs multiple times" fault. Changed to `ForEach(Array(...enumerated()), id:
\.offset)` so the position is the stable identity, not the string content.

### VM thumbnail centering
`ZStack(alignment: .topTrailing)` was pushing the OS icon/version VStack toward
the top-right. Changed to `ZStack` (default center alignment) with `.overlay(
alignment: .topTrailing)` for the `StatusDot` — icon is now always centered.

### VMDetailPane header
- Shows `displayName` as headline, falls back to tart name if empty
- Shows tart name in monospaced tertiary below when display name differs
- "Last started: Never" shown when `lastStartedAt` is nil (instead of hiding the row)
- Metadata section renamed "Identity & Dates", includes Display name and Tart name rows

### VMCard grid — dates added
- "Created DD Mon YYYY" shown below hardware in caption2/tertiary
- "· Started DD Mon YYYY" appended when `lastStartedAt` is set

### Date labels — BaseVM and Recipes
- BaseVM detail subtitle: date now reads "Built 19 Mar 2026" (was bare date)
- Recipes sidebar and editor panel: date now reads "Modified 19 Mar 2026"

## [0.1.081] — Fix actor-isolated download call in InstallerView

Same issue as 0.1.080 but in `InstallerView.downloadWithIPSWService()` —
`IPSWService.shared.download(fw, to:)` is actor-isolated and needs `await`
when called from outside the actor. Also verified no other `IPSWService.shared`
call sites are missing `await`.

## [0.1.080] — Three fixes: actor await, Equatable conformance, unused variable

- `BaseVMStore`: `IPSWService.shared.download(...)` is actor-isolated, so calling
  it from `BaseVMStore` (a `@MainActor` class, not the same actor) requires `await`.
  Changed to `for await event in await IPSWService.shared.download(...)`
- `IPSWFirmware`: added `Equatable` conformance so `[IPSWFirmware]` can be used
  with `.onChange(of:)` in `BaseVMView` (requires `Equatable` on the observed value)
- `BaseVMView`: the unused `osKey` local variable in `loadCustomTemplates()` was
  already removed in an earlier session — warning was from stale Xcode line numbers

## [0.1.079] — Fix ipswPath initialisation in BaseVMStore

`let ipswPath: String` was declared without an initial value and assigned across
three separate branches (local file, remote URL, mist-cli inout, ipsw.me loop).
Swift requires definite initialisation — the compiler can't prove every code path
assigns the value, especially through an `inout` parameter and a `for await` loop.

Changed to `var ipswPath = ""`. The existing `guard !ipswPath.isEmpty` at the end
of the ipsw.me branch already handles the case where the download loop completes
without a `.completed` event, so no logic changed.

## [0.1.078] — Fix two type errors, improve pre-zip checker

### IPSWService: guard let on non-optional URL
`destination` is declared `let destination: URL` (non-optional), so
`guard let dest = destination else { ... }` is a compiler error. Changed to
`let dest = destination`.

### BaseVMStore: undefined error type
`throw BaseVMStoreError.buildFailed(...)` referenced an enum that doesn't exist.
The correct type in this file is `BuildError`. Changed to
`throw BuildError.ipswDownloadFailed(...)`.

### check_swift.py improvements
Added four new pattern rules that would have caught both errors:
- `guard let x = x` where x is the same name (binding non-optional)
- `throw XxxError.` where XxxError is not defined in any Swift file
- `@Published` on what looks like a computed property
- `TextField(text:` without a leading label argument (catches the double-label bug)

## [0.1.077] — Fix @Published on computed property in BuildMonitor

`@Published` can only be applied to stored properties. `elapsedFormatted` is a
computed property derived from `elapsedSeconds` — SwiftUI picks up changes to it
automatically when `elapsedSeconds` (the underlying `@Published` stored property)
changes. Removed the erroneous `@Published` attribute.

## [0.1.076] — Regenerate project.pbxproj (parse error fix)

The pbxproj had accumulated drift from incremental file additions across many
sessions, causing Xcode to report a parse error. Regenerated cleanly from the
actual file list on disk (42 Swift files + 3 resources). All group membership,
build phases, and deployment target (macOS 15.0) are correct.

## [0.1.075] — Fix TextField(text:prompt:) missing first argument

`TextField(text:prompt:)` requires a label as the first argument on macOS 15.
The previous refactor removed label closures to fix double-label rendering but
left some call sites without the required leading `""` string label.

Fixed in: `NewVMSheet`, `VMEditSheet`, `BaseVMView`, `MDMProfileView`,
`MDMServersView`, `PreferencesView` — 16 call sites total.

## [0.1.077] — IPSWService replaces mist-cli as default; mist-cli optional

### IPSWService (new, ipsw.me API)
`Services/IPSWService.swift` — Swift actor backed by `https://api.ipsw.me/v4/device/VirtualMac2,1?type=ipsw`:
- Returns every macOS IPSW compatible with Apple Virtual Machine hardware (Monterey 12+ only)
- Results cached in-memory for 1 hour; `invalidateCache()` forces refresh
- `download(_:to:)` returns `AsyncStream<IPSWDownloadEvent>` with progress/completed/failed
  events — uses `URLSession` download task bridged via `URLSessionDownloadDelegate`
- No external tools required — works out of the box

### IPSW download mode setting
`AppSettings.IPSWDownloadMode` enum: `.ipswMe` (default) / `.mistCli`
- Preference in Preferences → IPSW download (radio group)
- `BaseVMStore` branches on this setting for auto-downloads
- `InstallerView` branches for both listing and downloading
- Setting is persisted in `app-settings.json`

### mist-cli demoted to optional dependency
- `Dependency.isRequired = false` for mist-cli
- `DependencyManager.allReady` now only requires `isRequired == true` deps
  (tart, packer, packer-plugin-tart, jq) — app launches without mist-cli
- When mist-cli mode is selected and mist-cli is absent, `BaseVMStore`
  auto-installs a managed copy from GitHub releases before building

### mist-cli resolution order (when mist-cli mode is active)
1. System `mist` binary (found via `which mist`)
2. Oven-managed copy at `deps/mist-cli`
3. Auto-download from GitHub releases API + `installer -pkg`

### InstallerView rewritten
- Source indicator in toolbar shows which backend is active (ipsw.me or mist-cli)
- `IPSWFirmwareRow` replaces `FirmwareRow` — uses `IPSWFirmware` for both sources
  (mist-cli results are converted to `IPSWFirmware` for uniform display)
- `ContentUnavailableView` replaced with `EmptyStateView` shim (macOS 13+)
- Download progress works identically for both backends
- `signed` field from ipsw.me shows a green ✓ seal when Apple still signs the firmware

### Big Sur (macOS 11) excluded
`IPSWService.listFirmware()` filters to `majorVersion >= 12`; 
`MistService.listFirmware()` does the same.

## [0.1.076] — macOS 13+ support, Big Sur excluded, custom IPSW sources

### Deployment target: macOS 13 Ventura
- `MACOSX_DEPLOYMENT_TARGET = 13.0` (reverted from 15.5)
- Swift 5.9 (reverted from 6.0 — Swift 6 strict concurrency requires more
  annotation work that would distract from feature development)
- `@Observable` macro reverted to `ObservableObject` / `@Published` —
  `@Observable` requires macOS 14+
- `ContentUnavailableView` (macOS 14+) replaced with `EmptyStateView` shim
  that uses `if #available(macOS 14, *)` to show the native view on 14+
  and a compatible VStack fallback on 13
- `TART_HOME` pref, OS checks updated throughout for 13+

### Big Sur (macOS 11) excluded from IPSW list
- `MistService.listFirmware()` now filters out firmwares with major version < 12
- tart requires macOS 12 Monterey or later for guest VMs

### IPSW source options expanded (New Base VM)
Four sources now available via radio group:
- **Download automatically** — existing mist-cli auto-download (default)
- **From macOS Installers library** — existing local library picker
- **Custom file path** — text field + Browse button to pick any `.ipsw` file
  from anywhere on disk via `fileImporter`
- **Download from URL** — paste a direct HTTPS URL; Oven downloads the file
  to the IPSW storage folder via `URLSession.shared.download(from:)` before
  passing it to packer

`BaseVM` model gains `ipswRemoteURL: String?`. Resolution priority in
`BaseVMStore`: local file → remote URL download → mist-cli auto-download.

## [0.1.075] — Swift 6, @Observable, async/await cleanup

### Swift 6 + macOS 15.5
- `SWIFT_VERSION = 6.0` in all four build configurations
- `MACOSX_DEPLOYMENT_TARGET = 15.5` (was 15.0)

### @Observable migration (all stores)
Removed `ObservableObject` + `@Published` from every model class and replaced
with the `@Observable` macro (Swift 5.9 / macOS 14+). This eliminates the
`@Published`-during-render fault vector and reduces boilerplate significantly.

Classes migrated: `VMStore`, `BaseVMStore`, `AppState`, `AppLogger`, `AppTheme`,
`BuildMonitor`, `BuildSessionManager`, `DependencyManager`, `MDMServerStore`.

### View property wrapper cleanup
- `@StateObject` → `@State` (with `State(initialValue:)` where init is non-trivial)
- `@ObservedObject` → `@Bindable` (where two-way bindings are needed) or removed
- `@EnvironmentObject var x: T` → `@Environment(T.self) var x`
- `.environmentObject(x)` → `.environment(x)`
- `@Bindable` on singleton computed properties removed — `@Observable` objects
  track access automatically without any property wrapper

### Concurrency
- `DispatchQueue.main.asyncAfter` → `Task { try? await Task.sleep(for:) }`
- `NWPathMonitor` timeout: replaced `queue.asyncAfter` with `withTaskGroup` running
  the monitor and a `Task.sleep(for: .seconds(3))` timeout concurrently — no
  `DispatchQueue` needed for the timeout path
- `import Combine` removed from `VMStore` (no longer needed)

### Sendable
Added `Sendable` conformance to value types that cross actor boundaries:
`VirtualMachine`, `VirtualMachine.SharedFolder`, `LogEntry`, `MDMProfile`,
`MDMServer`, `RegistryCredential`.

### AppKit kept where appropriate
`NSViewRepresentable` (HCL syntax highlighting), `NSAppleScript` (AppleScript
for screen lock/shutdown/VNC), `NSWorkspace.shared.open()`, `NSPasteboard`,
`IOKit`, `CGEventTap`, `NWPathMonitor` — all kept as they have no SwiftUI
or Swift Concurrency equivalents on macOS.

## [0.1.074] — IPSW/version mismatch prevention, Picker warning fix

### Picker invalid selection warning
`osVersion` could become stale (e.g. "15.4") if `liveFirmwares` loaded after the
picker was rendered but before the selection was validated. Added `.onChange(of:
liveFirmwares)` that snaps `osVersion` to the first item in `versionList` whenever
the live firmware list updates and the current selection is no longer valid.

### IPSW filtered by selected OS
`loadLocalIPSWs()` previously loaded all `.ipsw` files regardless of OS. Now
filters by `osName` (e.g. only Sequoia IPSWs shown when Sequoia is selected).
- Re-filters when OS changes (clears `selectedIPSW` if it no longer matches)
- Re-filters when version changes
- Clears `selectedIPSW` on OS change

### Version mismatch warning
If the user selects an IPSW whose filename doesn't contain the chosen version
string, an orange warning label appears below the IPSW picker:
"This IPSW may not match the selected version (15.6.1)."
This handles the case where the user picks a Sequoia IPSW but for the wrong
point release.

## [0.1.073] — Fix double labels, layout warnings

### Double label bug
The previous fix used `TextField(text:prompt:) { Text("Label") }` — the label
closure is rendered as a *visible leading label* by macOS Form, duplicating the
`LabeledContent` label that already wraps it. Fixed by removing the label closure
from all `TextField` and `SecureField` instances that sit inside a `LabeledContent`
row, leaving just `TextField(text: $x, prompt: Text("hint").foregroundColor(.secondary))`.
18 label closures removed across 6 files.

### Layout recursion warning
`TextEditor` inside a `Form` row with `.frame(minHeight:)` triggers the
"layoutSubtreeIfNeeded on a view which is already being laid out" warning due to
a known SwiftUI/AppKit conflict. Replaced with `TextField(axis: .vertical)` and
`.lineLimit(3...6)` which expands naturally without conflicting height constraints.

### Remaining old-style TextFields
- `MDMServersView` Server URL and Password/Secret updated to use `prompt:` pattern

## [0.1.072] — TextField placeholder/value ambiguity fixed across all dialogs

All `TextField` and `SecureField` instances that used a hint string as their
label (e.g. `TextField("e.g. Jamf Pro Production", ...)`) have been updated to
use SwiftUI's `prompt:` parameter pattern instead:

```swift
// Before — hint identical in style to entered value:
TextField("e.g. Jamf Pro Production", text: $friendlyName)

// After — prompt renders in secondary/italic, entered value in primary:
TextField(text: $friendlyName,
          prompt: Text("e.g. Jamf Pro Production").foregroundColor(.secondary)) {
    Text("Friendly name")
}
```

Files updated:
- `MDMServersView` — Friendly name, Server URL, API Client ID
- `MDMProfileView` — Name, Invitation ID, Site, Policy name
- `PreferencesView` — Pushover App token, User key, Slack Webhook URL,
  Registry host, Username, Password/Token (all SecureFields too)
- `NewVMSheet` — Display name, Description
- `BaseVMView` — Username, Xcode version
- `VMEditSheet` — Display name, shared folder Name and Path

## [0.1.071] — Build safeguards use Stepper+label (HIG compliance)

The three numeric fields in Preferences → Build safeguards were `TextField` with
a placeholder string that rendered identically to the typed value — ambiguous per
HIG (Image 1 from the issue). Replaced with `Stepper` rows using the
HIG "Stepper + Label" pattern:

- **Timeout**: stepper from 30–600 minutes in 15-minute steps, value shown as
  "X min" in secondary colour to the right of the label
- **Heartbeat warning**: stepper from 1–60 minutes in 1-minute steps
- **Min. battery**: stepper from 0–100% in 5-point steps, shows "X%"

The current value is always visible as secondary-styled text next to the label,
with the stepper arrows to the right — matching the "Stepper + Label" row shown
in Apple's HIG example.

## [0.1.070] — VM list fixes, filters, TART_HOME UX

### Base VM no longer appears in VM list
- `mergeWithTart()` now calls `vms.removeAll { $0.name.hasPrefix("base-") }` at
  the start of every sync, purging any base VMs that were saved before the filter
  was added — no manual reset needed

### VMCard layout
- **Display name is now the primary (bold) label**; tart name shown below in
  monospaced tertiary if they differ
- **Hardware info on two lines**: OS version on first line, CPU/RAM/disk on second
- **"macOS " prefix dropped** from version strings in cards, list view, and
  detail pane — shows "Sequoia 15.6.1" instead of "macOS Sequoia 15.6.1"
- **OS icon in thumbnail**: `apple.logo` SF Symbol with short version string
  overlaid on the coloured thumbnail background

### Creation date fixed
- `mergeWithTart()` now refreshes `createdAt` from the tart VM directory's
  filesystem `creationDate` on every sync — corrects VMs that were first seen
  before this lookup was added (which defaulted to `Date()`)

### Filter and sort
- Single ⊜ menu replaces the tag-only menu, containing three sections:
  **Sort by**: Name, OS Version, Created, Last Started
  **OS Version**: filter to a specific version
  **Tag**: filter to a specific tag
- `VMSortOrder` enum drives sorting in `filteredVMs`
- Active filter shows filled icon in accent colour

### Preferences — Open in Finder
- Every storage row now has a folder button that opens the path in Finder
- TART_HOME row also has Open in Finder and a Reset button

### TART_HOME — copy VMs on change
- When the user selects a new TART_HOME path, an alert offers to copy the
  existing `~/.tart/vms/*` to the new location
- Copy runs in a background Task with progress logged to Activity Log

## [0.1.069] — Base VM filtering, macOS inference, creation date, TART_HOME

### Base VMs excluded from Virtual Machines list
- `mergeWithTart()` now filters out any VM whose tart name starts with `base-`
  before adding to `vmStore.vms` — base VMs are managed exclusively by `BaseVMStore`

### macOS version inferred from VM name
- `inferMacOSVersion(from:)` parses the VM name for OS keywords (sequoia, sonoma,
  ventura) and extracts version digits: e.g. `sequoia-15-6-1-nomdm-abc` → `macOS Sequoia 15.6.1`
- Applied when a VM is first seen by Oven and when an existing VM has an empty `macOSVersion`

### Creation date from filesystem
- `vmCreationDate(name:)` reads the `creationDate` attribute of the VM's directory
  in `$TART_HOME/vms/<name>` — this is the actual creation date, not the last-run date
- Falls back to `Date()` only if the directory is inaccessible

### Metadata preserved on sync
- `mergeWithTart()` only updates `status` (and optionally `macOSVersion`) for
  existing known VMs — `displayName`, `description`, `tags`, `baseVMID`,
  `mdmProfileID`, and all other Oven metadata are never overwritten by a sync

### TART_HOME configuration
- `AppSettings` gains `tartHome: String?` — explicitly overrides where tart stores
  VM disk images
- Resolution priority: Preferences setting → `TART_HOME` env var → `~/.tart`
  (via `AppSettings.resolvedTartHome`)
- New row in Preferences → Storage locations: "Tart VM storage (TART_HOME)"
  with Browse and Reset buttons
- `TART_HOME` is forwarded to the packer subprocess environment so base VM builds
  land in the configured location
- Footer explains the use case (external drive for large VM files)

## [0.1.068] — Fix empty VM list: TartVMInfo CodingKeys mismatch

### Root cause
`tart list --format json` outputs Title-Case JSON keys:
`{"Name": "...", "State": "stopped", "Source": "local", "Size": 12345}`

`TartVMInfo` declared lowercase Swift properties (`name`, `state`, `source`, `size`)
with no `CodingKeys` — Swift's `JSONDecoder` is case-sensitive and silently failed
to decode every field. The `try?` suppressed the error and returned `[]`, so
`mergeWithTart` always received an empty array, leaving `vmStore.vms` empty.
No error appeared in the log because the `try?` ate it.

### Fix
Added explicit `CodingKeys` enum to `TartVMInfo` mapping each property to its
Title-Case JSON key (`"Name"`, `"State"`, `"Size"`, `"Source"`).

Also replaced `try? JSONDecoder().decode(...)` with a proper `do/catch` that
logs the raw tart output and decode error to the Activity Log, so any future
JSON format changes are immediately diagnosable.

## [0.1.067] — Fix SwiftUI fault causing empty VM list

### Root cause
`AttributeInvalidatingSubscriber.invalidateAttribute` in SwiftUICore fires when
a `@Published` property is mutated synchronously on the main actor while SwiftUI
is mid-way through a layout/render pass. This is not just a warning — it causes
SwiftUI to discard the update, which is why the VM list appeared empty after sync.

Three separate mutation sites were firing at the wrong time:

### Fix 1: `AppLogger.log()` — the primary culprit
Every call to `AppLogger.shared.log()` mutated `@Published entries` synchronously.
`sync()` calls `log()` immediately after `mergeWithTart()`, and both run on the
main actor. If SwiftUI was computing `VMListView.body` (which observes `vmStore`)
at the same moment, the `AppLogger.entries` mutation fired mid-render.
Fix: wrapped `entries.append` in `Task { @MainActor [weak self] in }` to defer it
to the next run-loop iteration, after the current layout pass completes.

### Fix 2: `VMStore.sync()` — isSyncing toggle
`isSyncing = true` was set before the async tart call, then `mergeWithTart()` fired
`vms` mutations while `isSyncing` was still true — two `@Published` properties
changing in the same pass. Refactored so `isSyncing` only wraps the synchronous
merge, not the async fetch.

### Fix 3: `vmList` Binding setter
The list-view `Binding<UUID?>` setter mutated `@State selectedVM` directly during
body evaluation. Wrapped in `Task { @MainActor in }` to defer past the render pass.

## [0.1.066] — Fix "Publishing changes from within view updates"

### Root cause
SwiftUI's view update pass is not re-entrant. Mutating a `@Published` or `@State`
property *synchronously* inside `.onChange` of another `@Published` property fires
during the same pass, causing the warning and potential infinite loops.

### Fixes
1. **`VMListView`**: two duplicate `.onChange(of: vmStore.vms)` handlers both
   mutated `selectedVM` directly. Deduplicated to one, and wrapped the mutation
   in `Task { @MainActor in }` to defer it to the next run loop tick — safely
   outside the view update pass.

2. **`BaseVMView`**: `.onChange(of: baseVMStore.baseVMs)` was mutating
   `selectedBaseVMID = nil` synchronously. Wrapped the same way.

The `Task { @MainActor in }` pattern is the idiomatic SwiftUI fix: it schedules
the state mutation as a new task on the main actor rather than executing it inline
during the onChange callback, so it runs after the current render pass completes.

## [0.1.065] — VM persistence migration fix

### Root cause
`VirtualMachine` gained two new fields in 0.1.060 — `sharedFolders: [SharedFolder]`
and `mdmServerID: UUID?`. `SharedFolder` is a nested `struct`. Swift's synthesised
`Codable` decoder fails the entire array if any element contains an unknown key or
an unexpected type, and `try?` in `loadFromDisk()` silently swallowed the error,
leaving `vms = []`. On the next sync, `mergeWithTart` would re-add VMs from
`tart list` but without any saved metadata (display names, tags, base VM links).

### Fix: custom `init(from:)` with `decodeIfPresent`
`VirtualMachine` now has a hand-written `Decodable` initialiser that uses
`decodeIfPresent` for every field that could be absent in older saved JSON:
`description`, `tags`, `cpuCount`, `memoryGB`, `diskGB`, `macOSVersion`,
`ipAddress`, `createdAt`, `lastStartedAt`, `registryImageRef`, `mdmServerID`,
and `sharedFolders`. Required fields (`id`, `name`, `displayName`, `status`)
still use `decode` and will throw on genuine corruption.

### Improved error logging in VMStore
- `loadFromDisk()` now logs the exact decode error to the Activity Log instead
  of silently returning — makes future migrations diagnosable
- `JSONDecoder.dateDecodingStrategy = .iso8601` and `JSONEncoder` match,
  ensuring `createdAt` / `lastStartedAt` round-trip correctly across builds

## [0.1.064] — Two compiler fixes
- `NewVMSheet`: `mdmServerID` argument was placed before `cpuCount` but
  `VMStore.clone()` declares it after `registryImageRef` — reordered to match
- `VMListView`: `loadProfileName(id:)` was defined inside `VMListView` but
  called from inside `VMDetailPane` — moved into `VMDetailPane` where it's used

## [0.1.063] — macOS 15 Sequoia minimum deployment target
- `MACOSX_DEPLOYMENT_TARGET` bumped from `14.0` to `15.0` in all four
  build configurations in `project.pbxproj`
- `OvenApp` startup check: warns if below macOS 15 instead of 14
- `PreflightCheck.checkOSVersion`: blocks build if below macOS 15
- `LaunchModeSheet`: `.foregroundStyle(.tint)` restored now that macOS 15 is
  the floor (`.tint` is a valid `ShapeStyle` on 15+)

## [0.1.062] — Three compiler fixes
- `LaunchModeSheet`: `.foregroundStyle(.accent)` → `.foregroundStyle(Color.accentColor)` —
  `ShapeStyle` has no static member `accent` on macOS 14
- `BaseVMView`: removed unused `let osKey` in `loadCustomTemplates()` 
- `BaseVMView`: `.onDisappear` was accidentally appended to the `for` loop body
  inside `detectVNC()` (which returns `Void`) — moved it to the outer `VStack`
  of `LiveBuildLogPanel` where it correctly fires when the panel leaves the view

## [0.1.061] — VM detail metadata: base VM origin, MDM server, MDM profile

### VM detail pane — Origin section
- Shows which base VM the VM was cloned from (`baseVMID` lookup in `BaseVMStore`)
- Displays the base VM tart name and its macOS version
- Only shown when `baseVMID` is set (VMs cloned from a base VM)

### VM detail pane — MDM section
- Shows MDM server friendly name (looked up via `mdmServerID` in `MDMServerStore`)
- Shows MDM profile name (loaded from `mdm-profiles.json` via `loadProfileName()`)
- Only shown when at least one of `mdmProfileID` / `mdmServerID` is set

### mdmServerID now tracked end-to-end
- `NewVMSheet.createVM()` passes `mdmServerID: selectedMDMServer?.id`
- `VMStore.clone()` accepts and stores `mdmServerID` in the `VirtualMachine` placeholder
- `VirtualMachine` already had the field from 0.1.060

### VMDetailPane gets environment objects
- Added `@EnvironmentObject var baseVMStore: BaseVMStore`
- Added `@EnvironmentObject var serverStore: MDMServerStore`
- Both injected at the call site in `VMListView`
- `VMListView` itself now also declares `@EnvironmentObject var serverStore`
  (inherits from the root scene via `OvenApp`)

## [0.1.060] — Launch modes, tag colours, list view, shared folders, VM editing

### VNC closed on build completion
- `BuildSessionManager.closeVNCIfOpen()` quits Screen Sharing via AppleScript
- Called from `LiveBuildLogPanel.onDisappear` when `didAutoConnect` is true —
  so Screen Sharing is only closed if Oven was the one that opened it

### Random serial + MAC on clone (always)
- `VMStore.clone()` now always calls `tart set --random-serial --random-mac
  --display-refit` after every clone to avoid duplicate identifiers
- Single `tart set` call handles hardware overrides at the same time

### Launch mode picker
- Tapping Start on a VM now opens `LaunchModeSheet` instead of starting immediately
- Three options: Native (Virtualization.Framework window), VNC/Screen Sharing
  (headless + `--vnc`), Headless/SSH-only (`--no-graphics`)
- `TartService.RunMode` enum drives `tart run` arguments
- `VMStore.start(vm:mode:)` passes mode through; `sharedFolders` always applied

### VM edit sheet
- ⋯ options menu on VM cards (replaces the trash button) with Edit… and Delete…
- `VMEditSheet` lets users change: display name, description, tags, shared folders
- `SharedFolderSheet` — add a folder with a name, host path (file picker), and
  read-only toggle; previews the `--dir name:path[:ro]` argument
- `VirtualMachine` model gains `sharedFolders: [SharedFolder]` and `mdmServerID`
- `VMStore.update()` changed from `private` to `internal`

### Tag colours + autocomplete picker
- `TagChip.swift` — deterministic per-tag colour from a 10-colour palette using
  string hash; same tag always gets the same colour across all views
- `TagPickerField` — shows existing tags as removable chips, free-text input with
  autocomplete suggestions from known tags across all VMs
- VM cards, detail pane, and list view all use `TagChip`
- `NewVMSheet` updated from comma-separated `String` to `[String]` with `TagPickerField`

### List view for Virtual Machines
- Grid/list toggle button in the toolbar
- List shows: status dot, display name, macOS version, tag chips, status pill, ⋯ menu
- Tag filter menu in toolbar — pick any tag to narrow the grid or list

### Display name as primary label
- VM cards now show `displayName` as the bold primary label; the tart `name`
  appears below in monospaced caption only when they differ
- Search and detail pane already used `displayName`

### Description shown in full
- `DetailRow("Description", ...)` replaced with a multi-line `Text` with
  `.fixedSize(horizontal: false, vertical: true)` so the full text wraps
  rather than truncating with ellipsis

## [0.1.059] — Lock/unlock toggle button in build toolbar
- While a build is active, a `lock.open` / `lock.fill` button appears in the
  toolbar between the progress indicator and the Cancel button
- Toggles input lock on and off without needing to go to Preferences
- Tooltip shows "Lock keyboard and mouse input" or "Unlock input (⌘⇧⎋)"
  depending on current state
- `BuildSessionManager.enableInputLock()` changed from `private` to `internal`
  so the toolbar action can call it directly

## [0.1.058] — Custom template never used, URL with spaces, quoted paths

### Root cause: custom template selection was never saved to the BaseVM
- `NewBaseVMSheet.create()` built the `BaseVM` struct but never assigned
  `vm.customTemplatePath` — the field was always `nil`
- `BaseVMStore.build()` therefore always hit the `nil` branch and called
  `resolveTemplate(vmName:customOverride:nil)` which auto-detects or falls
  back to `defaults/`
- Fix: `create()` now sets `vm.customTemplatePath` from `selectedCustomTemplate`
  (user-picked from the multi-template picker) or `customTemplates.first` when
  exactly one custom template exists

### URL(string:) fails for paths containing spaces
- `baseVM.customTemplatePath.flatMap { URL(string: $0) }` silently returns `nil`
  for any path under `Application Support` because `URL(string:)` treats the
  space as an invalid character — so even if `customTemplatePath` had been set,
  the override would have been dropped
- Fixed by using `URL(fileURLWithPath: $0)` which handles spaces correctly

### [cmd] line now shows fully-quoted paths
- Paths in the `[cmd]` log line are now wrapped in double quotes so paths with
  spaces (like `…/Application Support/…`) display correctly and can be
  copy-pasted directly into Terminal

## [0.1.057] — Command logging, stderr classification, log line colours

### Always log the packer build command
- `buildWithInit()` now always emits a `[cmd]` line showing the exact packer
  binary path and template file being used, visible at build start without
  enabling debug mode — confirms which template is actually being invoked

### Stderr no longer blanket-prefixed with [err]
- `PACKER_LOG=1` sends all verbose output (timestamps, `[INFO]`, `[DEBUG]`,
  `[TRACE]`, plugin RPC traffic) to stderr. Previously every one of these
  lines was prefixed `[err]` and shown in red, making the log unreadable
- Fix: stderr lines are only marked `[err]` if they contain `[ERROR]`,
  `Error:`, or start with `error:` — all other stderr lines are displayed
  as-is (same as stdout), classified by content not by stream
- mist-cli download progress (also on stderr) similarly no longer prefixed

### Build log line colour improvements
- `[cmd]` lines: 80% opacity secondary (clearly readable but not dominant)
- `[debug]` lines: 40% opacity secondary (very dim, out of the way)
- `-->` lines (packer build result): green (success confirmation)
- Timestamp/verbose lines (start with digit, `packer-`, or plugin headers):
  35% opacity secondary — barely visible, so `==>` progress lines stand out
- All other lines remain at full secondary opacity

### Confirmed build success from log analysis
- The attached log shows a complete successful build: IPSW installed → VNC
  typing → SSH connected → provisioning scripts ran → graceful shutdown →
  "Build 'tart-cli.tart' finished after 15 minutes 23 seconds"
- packer plugin path in the log uses `~/.packer.d/plugins` (the user's
  Homebrew-installed plugin) rather than our `PACKER_PLUGIN_PATH` — the
  init step already registered the plugin at the default location

## [0.1.056] — Build log colour logic fixed

### Root cause
`logLineColor()` had a `line.contains("error") || line.contains("Error")` catch-all
that coloured any line containing the substring "error" red. When `PACKER_LOG=1`
is active, packer outputs hundreds of verbose lines that include the plugin binary
name `packer-plugin-tart_v1.20.0_x5.0_darwin_arm64` — which does not contain
"error" — but also lines with plugin paths, RPC calls, and timing data that
coincidentally do. The result was most debug output appearing red.

### Fix
Replaced both `lineColor()` (BuildLogView) and `logLineColor()` (LiveBuildLogPanel)
with a single shared top-level function `buildLogLineColor()` that matches only
on line *prefixes* and specific known packer summary patterns:

- `[err]` / `✗`               → red (our explicit stderr prefix)
- `Build '...' errored`       → red (packer build-failure summary)
- `==>`                       → primary (packer progress headers)
- `✓`                         → green (our success marker)
- `Build '...' finished`      → green (packer build-success summary)
- `⚠️`                        → orange (our warning marker)
- `[debug]`                   → dim secondary (our debug marker)
- Everything else              → secondary (verbose PACKER_LOG output)

No substring "error" matching — only exact prefix or full-pattern checks.

## [0.1.055] — VNC auto-connect, minimal lock indicator, Preferences button

### VNC auto-connect
- When "Show VM window during build" or "Debug Mode" is enabled, Oven now
  automatically opens Screen Sharing as soon as the VNC URL and password
  are both detected in the build log
- `autoConnectIfReady()` is called on every log update and on appear; fires
  once (guarded by `didAutoConnect`) with a 1.5s delay so macOS Screen
  Sharing has time to start before the connection attempt
- Manual "Connect VNC" button remains for cases where auto-connect is off
  or the user closes Screen Sharing and wants to reconnect

### Input lock — minimal label when hint is hidden
- When "Show unlock hint overlay" is off, a small `lock.fill` icon and
  "Input locked — building VM" label is now shown pinned to the bottom-right
  corner instead of nothing at all
- This gives the user a clear signal that the machine isn't frozen without
  revealing the unlock shortcut — satisfying both the security intent and
  the usability need

### Preferences gear button in sidebar
- `SettingsLink` (the SwiftUI native way to open the Settings window) added
  to the right side of the sidebar status bar with a `gearshape` icon
- Clicking it opens the same ⌘, Preferences window
- `.help("Preferences (⌘,)")` tooltip on hover

## [0.1.054] — VNC string literal fixes
- `components(separatedBy: """)` — triple-quote terminated the string literal early;
  replaced with `components(separatedBy: "\"")` (escaped single quote)
- VNC URL regex `[^\s"]` — `\s` is not valid in a Swift string literal (only in
  raw strings); replaced with an explicit character class `[^ \t\"]`
- `"vnc://:\(pw)@\(host)"` — string interpolation inside a string that already
  uses backslash escapes caused the literal to break; replaced with
  plain concatenation `"vnc://:" + pw + "@" + host`

## [0.1.053] — VNC password extraction and auto-login

### VNC connect now includes the password
- tart outputs two lines during build when graphics are enabled:
  1. `...connect via VNC with the password "word-word-word-word" to`
  2. `vnc://127.0.0.1:5900` (the URL)
- `detectVNC()` now scans all log lines for both patterns on every update
- Password is extracted from between the quotes using a regex
- `openVNC(_:password:)` embeds it directly in the URL as
  `vnc://:password@host:port` — macOS Screen Sharing accepts credentials
  in this format and connects without a password prompt
- Password is also copied to the clipboard as a fallback in case the URL
  scheme doesn't carry it through

### VNC detection no longer gated on showGraphics
- `detectVNC()` previously only ran when "Show VM window" was on
- tart can output VNC info regardless — detection now always runs so the
  button appears whenever the URL is present in the log

## [0.1.052] — Live build log panel, selection fixes, VNC connect

### Live build log panel in main view
- New `LiveBuildLogPanel` shown at the bottom of the left pane (full width,
  between the VM list and the status bar) while `baseVMStore.isBuilding`
- 160pt tall scrollable area with `11pt` monospaced font — wider than the
  detail pane log so longer packer lines are readable
- Header bar shows VM name, elapsed timer, and a VNC connect button when detected
- Auto-scrolls to latest line without animation on each new log entry
- Disappears automatically when the build ends

### Build log now reads live data
- `selectedBaseVM` was a value-type copy of the struct that never updated as
  `buildLog` grew — the detail pane log appeared frozen until navigation
- Fixed by changing `@State var selectedBaseVM: BaseVM?` to `@State var selectedBaseVMID: UUID?`
  and computing `selectedBaseVM` as a derived property from the store:
  `baseVMStore.baseVMs.first { $0.id == selectedBaseVMID }` — always reflects
  current store state including live `buildLog` updates

### Detail pane clears after delete
- After confirming delete, `selectedBaseVMID = nil` is set immediately
- Added `.onChange(of: baseVMStore.baseVMs)` to also clear selection if the
  selected VM disappears from the store for any other reason
- List row tags changed from `.tag(vm)` to `.tag(vm.id)` to match the new
  `UUID`-typed selection binding

### VNC connect button
- During build, `LiveBuildLogPanel` scans incoming log lines for a `vnc://...`
  URL using a regex (tart outputs this when `showGraphics` / `--graphics` is active)
- When found, a "Connect VNC" button appears in the panel header
- Clicking it opens the URL via `NSWorkspace.shared.open()` which launches
  macOS Screen Sharing (the built-in VNC client) — no third-party app needed
- Button only appears when "Show VM window during build" is enabled

## [0.1.051] — Unicode escape and warning fixes
- `BaseVMView`: Python unicode escapes (`\u2026`, `\u2717`, `\u2713`, `\u26a0\ufe0f`)
  were written literally into the Swift source, causing "Expected hexadecimal code
  in braces" errors — replaced with the actual characters (…, ✗, ✓, ⚠️)
- `BaseVMStore`: `err.localizedDescription ?? "..."` — `localizedDescription` on
  `LocalizedError` bridges to a non-optional `String`, so the `??` was redundant;
  removed the nil-coalescing fallback
- `BaseVMStore`: `await BuildMonitor.shared.start()` — `BuildMonitor` is `@MainActor`
  and `BaseVMStore` is also `@MainActor`, so no async hop is needed; removed `await`

## [0.1.050] — Credentials file, debug flags, input lock diagnostics, live build log

### Fix 1: Credentials via temporary pkrvars file
- `OVEN_VM_PASSWORD` env var approach was unreliable — packer variable `default = env()`
  works at init time but plugin versions differ in how they honour it at build time
- `buildWithInit()` now writes a temp `oven-creds-<uuid>.pkrvars.hcl` to `NSTemporaryDirectory()`
  containing `account_userName` and `account_password` with the real values
- Passed as a second `-var-file=` argument: `packer build -var-file=main.pkrvars.hcl -var-file=/tmp/oven-creds-<uuid>.pkrvars.hcl template.pkr.hcl`
- File is deleted immediately after build via `defer { try? FileManager.default.removeItem(at: credVarsURL) }`
  — survives both success and failure paths
- `account_password` variable in `.pkr.hcl` template retains `default = env("OVEN_VM_PASSWORD")`
  as a documented fallback, but the creds file takes precedence via HCL variable override

### Fix 2: PACKER_LOG=1 in debug mode
- When debug mode is enabled, `env["PACKER_LOG"] = "1"` is added to the subprocess
  environment, giving verbose packer output including plugin calls and timing

### Fix 3: run_extra_args with --graphics in debug mode
- When debug mode AND show graphics are both enabled, the credentials pkrvars file
  includes `run_extra_args = ["--no-audio", "--graphics"]` overriding the template default

### Fix 4: Input lock diagnostics
- `disableInputLock()` now logs the reason if it returns early:
  - "already unlocked" if `isLocked` is already false
  - "eventTap is nil, clearing isLocked flag" if the tap was lost — resets the flag
    so subsequent checks don't get stuck thinking the lock is active

### Fix 5: Live build log in Base VM detail pane
- New `BuildLogView` struct shown inside `BaseVMDetailPane` whenever
  `status == .building` or `status == .error` and `buildLog` is non-empty
- Auto-scrolls to the latest line as output arrives via `.onChange(of: buildLog.count)`
- Line colouring: red for `[err]`/`✗` lines, primary for `==>` progress lines,
  orange for `⚠️` warnings, dim for `[debug]` lines
- Shows elapsed timer (from `BuildMonitor.shared`) alongside a progress spinner
  while building; switches to a red "Build failed" header on error
- `10pt` monospaced font in a scrollable area capped at 280pt height so the
  detail pane doesn't grow unbounded
- Text is selectable so users can copy error messages

## [0.1.049] — Input lock overlay not dismissing, unlock not firing on failure

### Root causes
Two separate bugs both manifested as the overlay not dismissing:

**Bug 1 — View not re-rendering on `isLocked` change:**
`BaseVMView` was reading `BuildSessionManager.shared.isLocked` directly in its
`.overlay {}` without observing the object. SwiftUI only re-renders a view when
a property it *observes* changes. Since `BuildSessionManager` was not in `BaseVMView`'s
observation graph, `isLocked` becoming `false` never triggered a re-render and the
overlay stayed on screen until the user navigated away.
Fix: added `@ObservedObject private var buildSession = BuildSessionManager.shared`
to `BaseVMView` and changed the overlay condition to `buildSession.isLocked`.

**Bug 2 — `endBuildSession()` wrapped in a `Task {}` inside `defer`:**
`defer { Task { @MainActor in BuildSessionManager.shared.endBuildSession() } }`
dispatches a new task rather than executing immediately. Because `BaseVMStore` is
already `@MainActor`, the call can be made directly. The `Task {}` wrapper meant
the defer body was scheduling work for *later*, potentially after `isBuilding`
had already been reset, and in some paths the task never ran before the caller
continued. Same issue applied to `BuildMonitor.shared.stop()`.
Fix: both changed to direct calls — `defer { BuildSessionManager.shared.endBuildSession() }`
and `defer { BuildMonitor.shared.stop() }`.

**Bug 3 — `performBuildCompletionAction()` missing from the thrown-exception path:**
The `catch` block for unexpected thrown errors (e.g. IPSW download failure,
template validation failure) was notifying but not calling `performBuildCompletionAction()`,
so the completion action (do nothing / lock / shutdown) would not fire for these exits.
Fix: added the call to the `catch` block alongside the existing notification call.

## [0.1.048] — pkrvars env() fix, curly quotes, validation logging, save selection

### account_password removed from .pkrvars.hcl
- `env()` function calls are only valid in `.pkr.hcl` files, not `.pkrvars.hcl`.
  The `account_password = env("OVEN_VM_PASSWORD")` line was causing packer validate
  to error with "Function calls not allowed"
- Fix: `account_password` is no longer written to the vars file at all
- The variable block in the generated `.pkr.hcl` template now uses
  `default = env("OVEN_VM_PASSWORD")` which is valid in variable definitions
- Added `sensitive = true` to the variable block so packer redacts it in output

### Curly/smart quotes sanitised in template output
- Any Unicode smart quotes (', ', ", ") or dashes (–, —) that could sneak into
  the generated template via copy-paste are replaced with straight ASCII equivalents
  before writing the file

### packer validate error logging
- `PreflightCheck.validateTemplate()` now captures and logs both stdout and stderr
  from `packer validate`, so the exact error message appears in the Activity Log
- On failure, the `ProcessError.nonZeroExit` stderr is extracted and surfaced as
  the `PreflightFailure` detail, rather than just a generic error description

### RecipesView — stay on selected template after saving
- `saveTemplate()` was calling `loadTemplates()` which regenerates all `PackerTemplate`
  objects with new UUIDs, clearing `selectedID` and jumping back to the empty list view
- Fix: saves the URL of the template before reloading, then restores `selectedID`
  by finding the matching URL in the freshly loaded list

## [0.1.047] — BuildSessionManager NSAppleEventDescriptor fix
- `NSAppleEventDescriptor` has no `listItems()` method — replaced with the correct
  API: `numberOfItems` (count) and `atIndex(_:)` to iterate the list, collecting
  each item's `stringValue` into the `unsavedApps` array

## [0.1.046] — NotificationService and PreflightCheck compiler fixes

### NotificationService
- `pushoverUserKey` property name clashed with the `pushoverUserKey` Keychain key
  constant — renamed the constant to `pushoverUserKeychainKey` to resolve the
  redeclaration error
- `guard let user = pushoverUserKey` was failing because the property already
  returns `String?` — fixed as a side effect of the rename resolving the ambiguity
- `Result<Void, String>` is invalid — `String` doesn't conform to `Error`. Replaced
  with `Result<Void, NotificationError>` and added a `NotificationError` enum with
  `.notConfigured`, `.httpError`, and `.network` cases
- `PreferencesView` test handlers updated to call `.localizedDescription` on the error

### PreflightCheck
- `var resolved` was captured by two concurrently-executing closures (path handler
  and timeout), causing a Swift concurrency warning that becomes an error in Swift 6.
  Replaced with `nonisolated(unsafe) var fired` and a single `fire(_ value: Bool)`
  closure that guarantees the continuation resumes exactly once
- `validateTemplate` returned `Result<Void, String>` — replaced with
  `Result<Void, PreflightError>` and a new `PreflightError` enum at the bottom
  of the file. `BaseVMStore` updated to call `.localizedDescription` on the error.

## [0.1.045] — Three compiler fixes

- `PackerService`: redaction string had unescaped inner quotes —
  `"account_password = "[REDACTED]""` → `"account_password = \"[REDACTED]\""`
- `OvenApp`: `Settings {}` scene was placed outside `var body: some Scene` (after
  the closing brace of `WindowGroup`), causing "Expected 'func' keyword" errors —
  moved inside the `@SceneBuilder` body so both `WindowGroup` and `Settings`
  are siblings at the correct level
- `OvenApp`: removed redundant `.frame(minWidth:minHeight:)` from the `Settings`
  scene content — `PreferencesView` already sets its own `minWidth` internally,
  and the unused return value of `.frame()` was causing a warning

## [0.1.044] — Pre-build preflight, build monitoring, post-build safeguards

### Pre-build preflight checks (`PreflightCheck.swift`)
Runs before every build and blocks on fatal failures, warns on non-fatal ones.

1. **Power source** — blocks if on battery below the configured threshold (default 80%).
   Uses `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription`. Threshold
   configurable in Preferences → Build safeguards. Desktop Macs (no battery) pass silently.

2. **Disk space** — checks IPSW storage, VM storage, and templates directory.
   Blocks if any is below 60 GB free. Uses `FileManager.attributesOfFileSystem`.

3. **Network reachability** — only checked when no local IPSW is selected (auto-download
   path). Uses `NWPathMonitor` with a 3-second timeout. Blocks if no network.

4. **Packer plugin version** — runs `packer plugins installed` and parses the
   `cirruslabs/tart` version. Blocks if below v1.20.0 (required for `headless` field).

5. **Template validation** — runs `packer validate -var-file=...` before the full
   build, using `OVEN_VM_PASSWORD=preflight-check` as a placeholder. Surfaces errors
   immediately rather than failing after a 15-minute IPSW download.

6. **macOS version** — blocks if below macOS 14. Logged at startup.

### During-build monitoring (`BuildMonitor.swift`)

7. **Build timeout** — if packer is still running after the configured limit (default
   3 hours), `cancelBuild()` is called and the build is marked errored. Prevents
   hung builds from running forever. Configurable in Preferences.

8. **Heartbeat / stuck detection** — if no log output arrives for N minutes (default 10),
   a warning is appended to the build log and Activity Log. Does not abort — just signals
   that attention may be needed. Configurable in Preferences.

9. **Disk space during build** — polls every 2 minutes; aborts the build if free space
   drops below 5 GB to avoid a corrupted partial VM image.

10. **Elapsed timer** — `BuildMonitor.elapsedFormatted` is displayed in the Base VMs
    toolbar alongside the "Building…" indicator (e.g. "12:34" or "1:02:45").

### Post-build safeguards

11. **Unsaved document check before shutdown** — before executing the "Shut computer
    down" action, `BuildSessionManager` asks System Events for any process with
    `has unsaved content = true`. If any are found, shutdown is cancelled, the apps
    are listed in the Activity Log, and a notification is sent explaining why.

12. **macOS version check at startup** — logs the OS version to the Activity Log;
    shows a warning if below macOS 14.

### Preferences → Build safeguards
New section with three configurable fields:
- Timeout after (minutes) — default 180
- Heartbeat warning (minutes) — default 10
- Min. battery for build (%) — default 80

## [0.1.043] — Three-way build completion action

### After build completes — new setting
Replaces the previous "Lock input when build finishes" boolean toggle with a
three-option Picker in Preferences → Input lock:

- **Do nothing** (default) — Releases the sleep assertion and any active input lock,
  then stops. The desktop is left as-is.
- **Lock computer (⌘⌃Q)** — Sends the macOS screen lock key combo via AppleScript
  (`key code 12 using {command down, control down}`), equivalent to pressing ⌘⌃Q.
  The login window appears immediately; Touch ID or password required to return.
- **Shut computer down** — Initiates a graceful shutdown via AppleScript
  (`tell application "System Events" to shut down`). macOS will save open documents
  and ask running apps to quit before powering off.

All three fire after both successful and failed build exits. A warning is shown
in Preferences when "Shut computer down" is selected.

### Implementation
- `AppTheme.buildCompletionAction: String` (`@AppStorage`) — `"nothing"` | `"lock"` | `"shutdown"`
- `BuildSessionManager.performBuildCompletionAction()` reads the setting and executes
  the appropriate AppleScript
- `BaseVMStore` calls `performBuildCompletionAction()` at both the success and
  error exit paths (after notifications are sent)

## [0.1.042] — Build notifications, input lock improvements

### Build notifications: Pushover and Slack
- New `NotificationService` (`Core/NotificationService.swift`) handles all outbound
  build notifications
- **Pushover**: POST to `api.pushover.net/1/messages.json` with app token and user key.
  Sends "Build Started" (amber), "Build Complete" (green ✅), "Build Failed" (red ❌)
- **Slack**: POST to a webhook URL using Block Kit attachments with colour coding.
  Same three events; `ts` field provides timestamp in Slack's message footer
- Both channels send concurrently via `withTaskGroup` — one slow service doesn't
  block the other
- **Test buttons** in Preferences send a test message immediately and show the result
- Credentials (app token, user key, webhook URL) stored in Keychain via
  `KeychainService` — never in `UserDefaults` or on disk in plaintext
- Enabled/disabled per-channel via toggles in Preferences → Build notifications
- `BaseVMStore.build()` calls `notifyBuildStarted()`, `notifyBuildComplete(success:)`,
  and `notifyBuildComplete(success: false, detail:)` at the appropriate points

### Input lock: hide unlock hint for unattended builds
- New **"Show unlock hint overlay"** toggle in Preferences → Input lock (default: on)
- When off: the screen still darkens (dark overlay blocks visual distraction) but
  no text, shortcut hint, or Unlock button is shown — suitable for machines left
  unattended where a visible hint would be a security signal
- ⌘⇧⎋ still unlocks regardless of whether the hint is visible
- `InputLockedOverlay` reads `@AppStorage("showUnlockHintOverlay")` directly

### Input lock: lock on build completion
- New **"Lock input when build finishes"** toggle in Preferences → Input lock (default: off)
- When enabled, `BuildSessionManager.shared.beginBuildSession(preventSleep: false, lockInput: true)`
  is called after both successful and failed build exits
- Useful for builds that finish overnight — returns to a locked screen rather than
  leaving the desktop exposed

## [0.1.041] — HIG + security improvements (part 2)

### HIG: Sheet resizing
- All modal sheets now use `minWidth/idealWidth/minHeight` instead of fixed
  `frame(width:height:)` — users can resize sheets on larger displays
- Affected: `NewBaseVMSheet`, `MDMProfileSheet`, `MDMServerSheet`, `NewVMSheet`,
  `NewTemplateSheet`, `NewBaseVMSheetPreloaded`, `RegistryCredentialSheet`

### HIG: VM card touch targets
- Card action buttons upgraded from `.controlSize(.mini)` to `.controlSize(.small)`
  for better compliance with the HIG 44pt minimum touch target recommendation
- Trash button gained `.help("Delete VM")` tooltip
- Button spacing increased from 4 to 6pt for clearer separation

### HIG: .searchable() on more views
- `LogView` now uses `.searchable(text:prompt:)` replacing the custom toolbar search field
- Redundant custom search HStack removed from `LogView` toolbar

### HIG: Accessibility labels on status indicators
- `StatusDot` gets `.accessibilityLabel(status.label)` and `.accessibilityHidden(false)`
  so VoiceOver announces the VM status rather than ignoring the dot
- `StatusPill` circle dot gets `.accessibilityHidden(true)` (redundant with the
  adjacent text label); the pill itself gets `.accessibilityLabel("Status: <label>")`

### HIG: RegistryView empty state action
- Added "Add Image Reference" action button to the no-images `ContentUnavailableView`

### Security: Biometric-protected Keychain for sensitive credentials
- `KeychainService` gains `storeSensitive()` / `retrieveSensitive()` / `deleteSensitive()`
- Items stored via `storeSensitive` use `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`
  with `.userPresence` access control — device passcode or biometrics required to read
- `LocalAuthentication` framework imported; `LAContext` used with a clear localised reason
- These methods are available for MDM API passwords and registry tokens (wiring in next pass)

### Security: Local Network permission result checked
- `triggerLocalNetworkPermission()` now checks the `sendto` return value
- If `< 0` (permission denied), logs a clear warning directing the user to
  System Settings › Privacy & Security rather than silently proceeding

### Security: JamfService force-unwrap replaced
- `"\(username):\(password)".data(using: .utf8)!` replaced with `guard let`
  that throws `JamfError.authFailed` on failure (UTF-8 always succeeds in practice,
  but this is now consistent with the rest of the codebase's error handling style)

## [0.1.040] — HIG + security improvements (part 1)

### Preferences moved to ⌘, Settings window (HIG)
- `Settings {}` scene added to `OvenApp` — macOS native Preferences window accessible
  via ⌘, and the Oven menu, exactly as HIG requires
- "Preferences" removed from the sidebar — the sidebar slot is freed up
- `PreferencesView` now auto-saves storage path changes via `.onChange` — the
  explicit "Save Changes" button and its `Section("Save")` have been removed

### Keyboard shortcuts on primary sheet buttons (HIG)
- Added `.keyboardShortcut(.defaultAction)` to Save/Create/Build primary buttons
  in `RecipesView`, `MDMProfileView`, `MDMServersView`, and `PreferencesView`
  so pressing Return submits the focused sheet

### .searchable() in VMListView (HIG)
- Replaced the custom `HStack` search bar with `.searchable(text:prompt:)` modifier
  which integrates correctly with the macOS toolbar and gets proper focus behaviour

### .help() tooltips on icon-only elements (HIG)
- Added `.help()` to RecipesView refresh button (more descriptive)
- Added `.help()` to BaseVMView "New Base VM" button
- Added `.help("Password stored in Keychain")` / `.help("No password configured")`
  to lock icon indicators in MDMServersView

### NavigationSplitView minimum detail width (HIG)
- Added `.navigationSplitViewColumnWidth(min: 500, ideal: 800)` to the detail
  column so it doesn't collapse too narrow on small windows

### SetupView font fix (HIG)
- Tool names (tart, packer, mist-cli, jq) are proper nouns, not code — changed
  from `.system(.body, design: .monospaced)` to `.body` with `.medium` weight

### Security: password redacted from debug log
- Debug mode previously dumped the full `.pkrvars.hcl` file including
  `account_password` in plaintext to the Activity Log
- Now redacts any line starting with `account_password` before logging,
  replacing the value with `[REDACTED]`

### Security: password passed via environment variable, not on disk
- `account_password` in the generated `.pkrvars.hcl` now uses
  `env("OVEN_VM_PASSWORD")` — the HCL `env()` function reads from the environment
- The actual password is passed via `OVEN_VM_PASSWORD` env var at `packer build`
  time — it never appears in the vars file on disk
- `buildWithInit()` gains a `password: String` parameter
- `BaseVMStore` passes `baseVM.password ?? "baker"` through to the build call

### Security: sanitised subprocess environment for packer/tart
- `buildWithInit()` and `validate()` no longer inherit the full Oven process
  environment (which includes `DYLD_*`, `XPC_*`, Xcode internals, etc.)
- Now builds a minimal env: `PACKER_PLUGIN_PATH`, `PATH` (deps + system only),
  `HOME`, `TMPDIR`, `USER`, `SHELL` — nothing else is passed to child processes

## [0.1.039] — Accessibility prompt, tart 1.20.0, custom template management

### Input lock — accessibility permission now prompts correctly
- `CGPreflightPostEventAccess()` only checks silently — it never shows a dialog
- Replaced with `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
  which actually triggers the macOS "Allow access" dialog in System Settings
- Switched `CGEventTap` from `.cgSessionEventTap` to `.cghidEventTap` for
  lower-level interception that works across all applications

### Tart plugin version bumped to >= 1.20.0
- Updated `required_plugins` version constraint in `PackerService.writeTemplate()`
  and in the `RecipesView` new-template starter
- The `headless` field was added in a later plugin version — 1.20.0 ensures it works

### Packer template management — custom vs default, no overwrites
- **Default templates** are now written to `packer-templates/defaults/<name>.pkr.hcl`
  — Oven's auto-generated templates never touch the root directory
- **Custom templates** live in `packer-templates/` (root) — anything the user
  creates or edits there is preserved across builds
- **Template resolution** at build time:
  1. Explicit user selection (from picker when multiple customs exist)
  2. Single custom template matching the VM's OS name + version
  3. Default template in `defaults/` subdirectory
- `PackerService.resolveTemplate(vmName:customOverride:)` encapsulates the logic
- `PackerService.customTemplates(for:)` finds all custom templates matching a VM
- `BaseVM` gains `customTemplatePath: String?` — persisted so re-builds remember
  which custom template was selected
- **New Base VM sheet** shows a template picker section:
  - Hidden when no custom templates exist (defaults silently used)
  - Info row when exactly one custom exists ("A custom template will be used")
  - Picker when multiple customs exist for the selected OS/version
  - Reloads when OS or version changes
- **Recipes view** now shows two sections: "Custom" (root) and
  "Default (auto-generated)" (defaults/) with a "default" badge on each default row
- Vars file (`.pkrvars.hcl`) is always refreshed — it contains current config values
  like password, IPSW path, and MDM settings, not user-editable code

## [0.1.038] — RegistryService await restored, checker fixed

- `RegistryService` is an `actor` — `AppLogger.shared` is `@MainActor`, so calls
  from inside the actor's `Task {}` blocks DO require `await`. Restored all 9 calls.
- Fixed `check_swift.py` to correctly distinguish actor files (need `await`) from
  `@MainActor` class/struct files (don't need `await`) — previously the checker
  was incorrectly flagging actor files as @MainActor types due to `@MainActor in`
  closures inside them matching the old regex

## [0.1.037] — BuildSessionManager fixes, spurious awaits, pre-zip checker

### BuildSessionManager — all compiler errors fixed
- `CGEventMask` construction: replaced set-literal `reduce` (which inferred the
  wrong type) with an explicit `[CGEventType]` array and a typed `.reduce(0:)`
- `sendto` closure: `payload.withUnsafeBytes` now correctly uses `buf.baseAddress!`
  and `buf.count` as separate arguments rather than splatting a tuple
- `CGEventType` array members: types now written as `[CGEventType]` with explicit
  type annotation so the compiler can resolve the enum members without ambiguity

### Spurious await removed
- `BaseVMStore`: removed `await` from `BuildSessionManager.shared` calls —
  both caller and callee are `@MainActor` so no hop is needed
- `RegistryService`: removed 9 `await AppLogger.shared` calls — `AppLogger` is
  `@MainActor` and `RegistryService`'s `Task {}` blocks inherit that context

### Pre-zip static checker
- Added `/home/claude/check_swift.py` — runs before every zip from now on
- Checks for: spurious `await` on `@MainActor` singletons, `CGEventType` arrays
  without explicit type annotation, possible unclosed string interpolations
- Checked outside multi-line string literals to avoid false positives from
  HCL template content in `PackerService.swift`

## [0.1.036] — OvenApp buildSession declaration fix
- Fixed error: `buildSession` was passed to `.environmentObject()` but its
  `@StateObject` declaration was never added to `OvenApp` — added
  `@StateObject private var buildSession = BuildSessionManager.shared`

## [0.1.035] — Switch --no-graphics to headless field in Packer template
- Replaced `run_extra_args = ["--no-graphics"]` with the proper `headless` field
  supported by the tart-cli Packer plugin
- `headless = true` by default (no tart window during build)
- `headless = false` when "Show VM window during build" is enabled in Preferences
- Placed before `create_grace_time` in the source block, matching plugin docs
- `run_extra_args` now only contains `--no-audio` unconditionally

## [0.1.034] — PackerService string interpolation fix
- Fixed three compiler errors caused by a newline inside a Swift string interpolation
  `\(...)` in the `run_extra_args` block — Swift does not allow literal newlines
  inside string interpolation expressions
- Fix: pre-compute `let noGraphicsLine` before the template multi-line string,
  then interpolate the variable (a plain string with no embedded newlines)

## [0.1.033] — Sleep prevention, local network, input lock, graphics toggle

### Sleep prevention during builds
- `BuildSessionManager` acquires an `IOPMAssertionCreateWithName` assertion with
  type `kIOPMAssertionTypePreventUserIdleDisplaySleep` at build start
- Released automatically when the build finishes or errors
- Controlled by "Prevent sleep during build" toggle in Preferences → Build behaviour
  (default: on)

### Local Network access permission
- Added `NSLocalNetworkUsageDescription` to `Info.plist` with a clear explanation
- Added `NSBonjourServices: [_ssh._tcp]` so macOS knows SSH is the service needed
- `BuildSessionManager.triggerLocalNetworkPermission()` sends a UDP broadcast at
  build start to prompt the system permission dialog before tart tries to SSH in
- Called unconditionally at every build session start

### Input lock during build
- New `BuildSessionManager.enableInputLock()` installs a `CGEventTap` at
  `.cgSessionEventTap` that swallows all keyboard and mouse events
- Unlock shortcut: **⌘⇧⎋** (Cmd + Shift + Escape) — consumed by the tap, not passed through
- `InputLockedOverlay` fills the Base VMs view with a frosted dark overlay showing
  the shortcut hint and an "Unlock Now" button
- Requires Accessibility permission — if not granted, a warning is logged instead
  of silently failing
- Controlled by "Lock input during build" toggle in Preferences → Build behaviour
  (default: off)

### VM window during build (show graphics)
- "Show VM window during build" toggle in Preferences → Build behaviour (default: off)
- When off (default): `--no-graphics` is included in `run_extra_args` in the generated
  `.pkr.hcl` template — tart runs headless
- When on: `--no-graphics` is omitted so the tart window appears and the user can
  watch the setup assistant run (but should not interact with it)
- `PackerService.BuildConfig` gains `showGraphics: Bool` field; `BaseVMStore` reads
  `UserDefaults("showGraphicsDuringBuild")` and passes it through

### Preferences — Build behaviour section
- New section between Appearance and Storage locations
- Three toggles: Prevent sleep · Show VM window · Lock input
- Context warnings shown when Show window or Lock input are enabled

## [0.1.032] — BaseVMStore variable ordering fix
- Fixed two errors: `debug` and `mistPath` were referenced in the debug log block
  before their `let` declarations appeared — moved both declarations to the top
  of the `else` branch before any code that uses them

## [0.1.031] — AppTheme extension and var->let fixes
- Fixed `AppTheme` errors: `@AppStorage` properties cannot be declared inside
  an extension — moved `debugModeEnabled` into the main class body
- Fixed `BaseVMView` warning: `var vm` in `create()` never mutated — changed to `let`
  (`password` is set via a `nonmutating set` on the struct)

## [0.1.030] — Root cause fix (tart.app bundle), debug mode, status messages

### tart.app bundle — root cause of "Bad exit status: -1"
- tart requires its embedded provisioning profile
  (`tart.app/Contents/embedded.provisionprofile`) to acquire the
  `com.apple.security.virtualization` entitlement from Virtualization.Framework
- Previously the installer stripped the binary out of the .app bundle and copied
  only the bare binary to `deps/tart` — this silently loses the entitlements
- Fix: `DependencyManager` now copies the full `tart.app` bundle to `deps/tart.app`
  and creates a symlink at `deps/tart → deps/tart.app/Contents/MacOS/tart`
- `binaryPath` for the tart dependency updated to point inside the .app
- `OvenApp` updated to resolve `deps/tart.app/Contents/MacOS/tart` first,
  falling back to the symlink

### Debug Mode
- New toggle in Preferences → Appearance: "Debug Mode"
- When enabled, before each build the Activity Log and build log receive:
  - Full paths to the packer binary, template file, and vars file
  - Whether template and vars files actually exist on disk
  - Full contents of the `.pkrvars.hcl` vars file
  - IPSW path being used and the mist-cli binary path
  - packer plugin directory and PATH prefix
- Stored via `@AppStorage("debugModeEnabled")` on `AppTheme`

### Build status messages
- Build log now shows `==> IPSW: <path>` at build start so user can see
  which firmware is being used without needing Debug Mode
- IPSW download log line includes OS name and version
- Re-building from `.error` state correctly resets to `.building`

## [0.1.029] — Three compiler fixes
- `BaseVMStore`: removed unused `expectedFilename` variable
- `BaseVMStore`: added `await` to `mistSvc.localIPSWs()` — actor-isolated method
  cannot be called without `await` from outside the actor
- `PreferencesView`: changed `var cred` to `let` — never mutated after init
  (`password` is set via a `nonmutating set` on the struct)

## [0.1.028] — Predictable IPSW filename via --firmware-name
- `MistService.downloadFirmwareByVersion()` now passes `--firmware-name macOS-<version>.ipsw`
  to mist-cli so the output filename is always known ahead of time
- Returns `(stream, expectedURL)` — the caller uses `expectedURL.path` directly
  after download instead of scanning the directory for the newest file
- `BaseVMStore.build()` updated to destructure the tuple and verify the file exists
  at `expectedURL` before using it as `ipsw_url` in the vars file

## [0.1.027] — Username field, registry label, real IPSW download

### Base VM — username now editable and defaults to "baker"
- The previous fix wrote to a wrong copy of the credentials section; now corrected
- Username field is a `TextField` (was a fixed `Text("admin")`)
- Default value is "baker" for both username and password fields

### Image Registry — "Registry" label no longer truncated  
- Added `.labelsHidden()` to the registry segmented `Picker` in the toolbar

### Base VM build — IPSW is always a real file path
- Removed the incorrect "latest" fallback — tart-cli packer plugin does NOT accept
  "latest" as an IPSW value; a real filesystem path is always required
- New auto-download flow in `BaseVMStore.build()`:
  1. If `ipswLocalPath` is set and the file exists → use it
  2. If a cached IPSW for this version already exists in `ipswStorageRoot` → use it
  3. Otherwise → call `MistService.downloadFirmwareByVersion()` which runs
     `mist download firmware <version>` and writes the IPSW to `ipswStorageRoot`
  4. After download, pick the most recently modified `.ipsw` in the directory
     (mist-cli names files as "macOS Name Version Build.ipsw" so we can't predict
     the exact filename without the build number)
- Download progress is streamed line-by-line to the build log and Activity Log
- `MistService.downloadFirmwareByVersion()` added — downloads by version search
  string without needing a build number, lets mist-cli use its default naming
- `BuildError.mistNotInstalled` and `.ipswDownloadFailed` give clear messages
- `BaseVMStore` now owns a `ProcessRunner` instance for `MistService` calls

## [0.1.026] — Layout fix, syntax highlighting, build flow, username

### Packer Templates — layout fixed and syntax highlighting added
- Replaced `NavigationSplitView` with `HSplitView` which gives a proper resizable
  divider between the template list and editor with no gap and no glitch when resizing
- List column has `min: 180, ideal: 220, max: 300`; editor fills all remaining space
- Added `HCLEditor` — an `NSViewRepresentable` wrapping `NSTextView` with token-based
  syntax colouring for HCL: keywords (purple), strings (orange), comments (green),
  variable references `var.X` / `local.X` (blue), block openers (teal)
- Highlighting is applied on every keystroke without disrupting cursor position
- `.pkrvars.hcl` files are not shown in the list (only `.pkr.hcl`)

### Base VM build flow fixed
- Template and vars file are now always regenerated before every build, not just
  the first time — this ensures current settings (password, MDM, IPSW path) are
  always reflected in the vars file that Packer actually reads
- IPSW resolution: if `ipswLocalPath` is set and the file exists on disk, that path
  is used; otherwise `"latest"` is passed to the tart-cli packer plugin which handles
  downloading the latest macOS firmware automatically
- Logged to Activity Log so the user can see which IPSW path was used

### Default username changed to "baker"
- `BaseVM.defaultUsername` now defaults to `"baker"` (a nod to the baking theme)
- The username field in `NewBaseVMSheet` is now an editable `TextField` instead of
  a fixed display — users can customise it per Base VM
- Password placeholder updated to match
- `BaseVMStore.build()` password fallback updated from `"admin"` to `"baker"`

## [0.1.025] — Registry nav fix, Base VM delete, full Packer template, live versions

### Image Registry — navigation no longer locks up
- Root cause: `RegistryCredentialSheet` Picker used a dynamic `.tag(registry.isEmpty ? "ghcr.io" : registry)`
  which produces an invalid/changing tag that confuses SwiftUI's picker selection state,
  triggering a "selection is invalid" warning that broke all sidebar navigation
- Fix: replaced with a clean three-option Picker ("ghcr.io" / "docker.io" / "Other…")
  backed by a separate `registryOption` state string; the raw `registry` text field
  is only shown when "Other…" is selected

### Base VMs — delete now works
- `BaseVMStore.delete()` was calling `tartService.delete()` which throws when the
  VM was never built (status .notBuilt — tart has no record of it)
- Fix: only attempt tart deletion when `vm.status == .ready || .error`; always
  remove from metadata regardless — changed signature to non-throwing `async`
- Updated `BaseVMView` call site to match (`await` instead of `try? await`)

### Packer templates — full setup assistant automation
- Rewrote `PackerService.writeTemplate()` to match the motionbug
  `apple-tart-tahoe.pkr.hcl` reference template exactly:
  - Full `boot_command` array automating the entire macOS Setup Assistant
    (language, country, account creation, VoiceOver, Apple ID skip, T&C,
    location, timezone, analytics, screen time, Siri, FileVault, look,
    auto-update, keyboard nav, System Settings → Sharing SSH + Screen Sharing,
    Gatekeeper disable)
  - `locals { uuid = uuidv4() }` for MDM profile payload UUID
  - `recovery_partition = "keep"` so softwareupdate works in the VM
  - Shell provisioner uses `if/fi` bash conditionals (not HCL dynamic blocks)
    for all feature toggles — matches how the reference template works
  - MDM provisioner writes a proper `.mobileconfig` plist to Desktop for
    "profile" type, or a `.webloc` file for "link" type
  - `create_grace_time = "30s"` (was incorrectly 90s)
  - Auto-login uses `kcpasswordgen.sh` to encode the password correctly

### Packer Templates / Recipes — live version list
- `NewTemplateSheet` now fetches live firmware versions from mist-cli via
  `MistService.listFirmware()` on appear, same as `NewBaseVMSheet`
- Versions are deduplicated and filtered by OS major version
- Falls back to hardcoded list if mist-cli is unavailable

## [0.1.024] — VirtualMachine init argument order fix
- Fixed `VMStore` error: `macOSVersion` must come after `diskGB` and before
  `registryImageRef` in the `VirtualMachine` init call — matches the exact
  parameter order declared in `VirtualMachine.swift`

## [0.1.023] — Compiler error and warning fixes
- Fixed `VMStore` error: `macOSVersion` argument must come after `status` in
  `VirtualMachine` initialiser — swapped the argument order
- Fixed `BaseVMStore` warning: `let settings = AppSettings.load()` was declared
  but never referenced in the build block — removed the unused binding
- Fixed `InstallerView` warnings (×5): removed spurious `await` from
  `AppLogger.shared` calls — inside a SwiftUI `View` the main actor context
  means these calls are synchronous and don't require `await`
- Fixed `InstallerView` warning: `var vm` declared in `NewBaseVMSheetPreloaded.create()`
  but never mutated after init — changed to `let`

## [0.1.022] — Polish pass: description/tags, macOSVersion, PATH fix, IPSW source

### VMs — description, tags, and macOSVersion wired end-to-end
- `VMStore.clone()` now accepts `description`, `tags`, and `macOSVersion` parameters
- `NewVMSheet` passes all three directly into `clone()` — no more post-clone `updateMetadata`
- `macOSVersion` derived from the selected Base VM (`osName + osVersion`)
- VM detail pane now shows description when set
- VM card shows display name below technical name when they differ
- Search now matches against description in addition to name, macOS version, and tags

### DetailRow — HIG-compliant font
- Values now use `.callout` (regular) by default; only technical fields like IP address
  use `.system(.callout, design: .monospaced)` via the new `monospaced: Bool` parameter

### Base VM sheet — IPSW source radio group
- IPSW source section now uses a `.radioGroup` style picker with two options:
  "Download automatically (via mist-cli)" and "Use a downloaded IPSW"
- The file picker is only shown when "Use a downloaded IPSW" is selected
- Re-applied correctly after previous edit didn't stick

### PackerService — tart binary on PATH for packer-plugin-tart
- Prepends the Oven deps directory to `PATH` when running `packer init` and
  `packer build` so the packer-plugin-tart subprocess can find the `tart` binary

### TartService — exit code 9 is not an error
- `tart list --format json` exits with code 9 when there are zero VMs
- `TartService.list()` now catches `ProcessError.nonZeroExit(9, _)` and returns `[]`
  silently — eliminates the "Sync failed: Process exited with code 9" Activity Log spam

### PreferencesView — credential delete fixed
- `deleteCredential()` was passing a dummy `RegistryCredential` to `saveCredential()`
  as a hacky "trigger save" — replaced with a dedicated `persistCredentials()` helper
  that encodes only the real credential list

### LogView — level picker label hidden
- Added `.labelsHidden()` to the level segmented `Picker` to suppress the truncated
  "Level" external label that appeared regardless of window size

## [0.1.021] — Five UI and runtime fixes

### New VM sheet layout
- Header/buttons were pushed to the vertical centre because `ContentUnavailableView`
  expands to fill the fixed 600pt frame — replaced with separate height per branch:
  420pt for the empty state, 620pt for the form; the header is now at the top in both cases

### Activity Log — "Level" label no longer truncated
- Added `.labelsHidden()` to the level `Picker` so SwiftUI no longer renders the
  external "Level" label that was wrapping and clipping at narrow widths

### Base VM version picker — duplicates removed
- mist-cli returns one JSON entry per build number, so the same version string
  (e.g. "15.5") appears once per build. Added Set-based deduplication in
  `versionList` that preserves order while removing duplicate version strings

### Build error: "exec: tart: executable file not found in $PATH"
- The packer-plugin-tart binary shells out to `tart` by name, relying on $PATH
- Fixed by prepending the Oven deps directory to the `PATH` environment variable
  passed to `packer build` and `packer init` in `PackerService.buildWithInit()`

### Activity Log error: "Sync failed: Process exited with code 9"
- `tart list --format json` exits with code 9 when there are no VMs — this is
  normal, not an error. `TartService.list()` now catches `ProcessError.nonZeroExit`
  with code 9 specifically and returns an empty array instead of throwing,
  so the first sync after a fresh install is silent

## [0.1.020] — Five UI/UX and correctness fixes

### New VM sheet — header no longer cropped
- Removed inner `.frame(width:height:360)` from the empty-state branch which was
  causing the outer sheet to clip at the wrong height
- Both branches (empty state and full form) now use the same outer `.frame(width: 540, height: 600)`
  so the header bar with Cancel/Create buttons is always fully visible

### macOS Installers — "data missing" error fixed (again)
- Added flexible JSON decoding in `MistFirmwareInfo`: tries direct array decode first,
  then a `{ "firmwares": [...] }` wrapped object, as mist-cli has changed formats across versions
- Custom `init(from:)` with `decodeIfPresent` for optional fields avoids hard failures
  on missing/null fields
- Three distinct error cases: `exportFileMissing`, `emptyExport`, `decodeFailed(preview)`
  — the last one includes the first 500 chars of raw output for easier debugging
- Error message now shown in the Activity Log as well as the UI

### MDM Server sheet — no longer scrollable
- Increased frame height from 360pt to 420pt so all fields fit without scrolling

### Packer Templates — editor fills full width
- Added `.frame(maxWidth: .infinity, maxHeight: .infinity)` to the `TextEditor`
- Changed `NavigationSplitView` to use `.constant(.all)` column visibility to
  prevent the detail column from collapsing

### Packer template generation — rewritten to match motionbug reference
- Feature toggles now use `type = string` with `"true"`/`"false"` string values,
  matching the motionbug `apple-tart-tahoe.pkr.hcl` convention exactly
- Plugin version bumped to `>= 1.17.0`
- Added `run_extra_args = ["--no-audio"]` — no more macOS assistant audio during builds
- Added `create_grace_time = "90s"` so Packer waits for macOS install before SSH
- Added `boot_command` to automate setup assistant navigation
- All feature provisioners use `dynamic "provisioner"` with
  `for_each = [for s in [var.X] : s if s == "true"]` (the correct HCL conditional form)
- MDM enrollment provisioner correctly branches on `enrollment_type`:
  "profile" downloads the `.mobileconfig` to the desktop; "link" writes the URL to a txt file
- Added `enable_safari_automation` and `enable_clipboard_sharing` provisioners
- Added `post-processor "shell-local"` completion message
- Vars file now includes all six feature toggle variables

## [0.1.019] — Installer fix, VM naming, Base VM improvements, Recipes layout

### macOS Installers — fixed (was empty list)
- Root cause: `mist-cli list` does not support `--output-type json` to stdout;
  the correct approach is `--export /path/to/file.json` which writes a JSON file
- `MistService.listFirmware()` now exports to a temp file, reads it back, and deletes it
- `MistFirmwareInfo` updated with `url` field and `fullLabel` computed property
- Download command updated to use `--firmware-name` and `--output-directory` flags
- "Downloaded" badge shown on firmware rows whose build number matches a local IPSW

### Virtual Machines — new VM sheet redesigned
- Extracted `NewVMSheet` into its own file (`UI/NewVMSheet.swift`)
- User must select a ready Base VM as the source — sheet shows an empty state if none exist
- Standardised VM name: `<os>-<version>-<mdmserver|nomdm>-<6charID>` (generated, not editable)
- Display name, description, and tags fields added
- Tags entered as comma-separated text, stored as `[String]` on the VM
- Hardware pickers default to the selected Base VM's hardware
- MDM profile picker linked to MDM servers via `serverID`
- Guard: if no ready Base VMs, sheet shows "Build a Base VM first" empty state

### Base VMs — version list and IPSW source
- OS picker now shows `displayLabel` e.g. "macOS 15 Sequoia" instead of just "Sequoia"
- Version picker fetches live list from mist-cli on appear (`fetchLiveVersions()`)
  filtered by major version; falls back to hardcoded list if mist-cli unavailable
- `MacOSRelease.Name` gains `majorVersion` (Int) and `displayLabel` (String) properties
- `fallbackVersions` replaces `versions` — no "latest" anywhere in the version list
- `autoName()` returns "base-<os>-select-version" if version is empty, never "latest"
- IPSW source is now a segmented picker: "Download automatically (via mist-cli)" vs
  "Choose a downloaded IPSW" — the local IPSW picker is only shown for the manual option

### Packer Templates (Recipes) — layout and creation
- Fixed sidebar shift bug: replaced `HStack` with `NavigationSplitView` so the template
  list uses the sidebar column and never shifts when a template is selected
- Added "New template" button (+) in the list toolbar
- `NewTemplateSheet` lets users pick OS and version; filename is auto-generated as
  `<os>-<version>.pkr.hcl` — no custom naming
- Starter template includes the required `packer` block with the tart plugin

## [0.1.018] — VMDetailPane onStart callback fix
- Fixed `VMDetailPane` error: `startVM` is a method on `VMListView` and not visible
  from the separate `VMDetailPane` struct — added `onStart: () -> Void` callback
  property matching the existing `onDismiss`/`onDelete` pattern; the closure is
  provided at the call site in `VMListView` where `startVM` is in scope

## [0.1.017] — RegistryService AppLogger await fixes
- Added `await` to all 9 `AppLogger.shared` calls inside `Task` blocks in
  `RegistryService` — `AppLogger` is `@MainActor` so calls from non-isolated
  async contexts (inside actor `Task` closures) must be awaited

## [0.1.016] — Registry auth, MDM+Packer wiring, IPSW flow, live IP, app icon

### Registry credentials wired to push/pull
- `RegistryService.pull()` and `.push()` now accept `[RegistryCredential]` and call
  `tart login` automatically before the operation using stored Keychain credentials
- Auth status banner in `RegistryView` shows when no credentials are configured for
  the selected registry, with a direct link to Preferences
- Credentials and image refs are now persisted to `registry-images.json` so the
  image list survives app restarts
- Registry switcher shows the authenticated username when credentials are present

### MDM enrollment wired into Packer template generation
- `BaseVMStore.build()` now resolves the attached `MDMProfile` and its parent
  `MDMServer` at build time, injecting `jamf_url`, `mdm_invitation_id`, and
  `enrollment_type` into `PackerService.BuildConfig`
- The generated `.pkrvars.hcl` file contains the correct Jamf enrollment values
  matching the motionbug.com template format
- New Base VM sheet shows the linked MDM server name and invitation ID for review,
  with a warning if the invitation ID is missing

### IPSWs feed directly into Base VM builder
- Local IPSW rows in `InstallerView` now have a "Create Base VM" button
- Tapping it opens `NewBaseVMSheetPreloaded` with the IPSW path pre-filled
- The IPSW path is passed through to `PackerService.BuildConfig` as `ipsw_url`
- New Base VM sheet also lists local IPSWs in a picker so the user can select
  a downloaded firmware without navigating to the Installers section

### Live IP refresh + SSH in Terminal
- `VMDetailPane` now shows the VM's IP address with a refresh button
- `.task(id: vm.id)` auto-triggers `vmStore.refreshIP(for:)` when the pane opens
  and the VM is running but has no IP yet
- `.onChange(of: vm.status)` triggers a refresh when a VM transitions to running
- "Open SSH in Terminal" button uses `NSAppleScript` to open Terminal.app and
  execute the SSH command — disabled until an IP is resolved
- Stop/Start buttons added to the detail pane for quick access

### App icon
- SVG icon design added at `Resources/OvenIcon.svg`: oven door with window,
  heating elements, and three control knobs on an amber/orange gradient background
- Placeholder 1024×1024 PNG added to `AppIcon.appiconset` — replace with a
  rendered version of the SVG for production

## [0.1.015] — MDMServersView sheet(item:) closure fix
- Fixed remaining `MDMServersView` error: `.sheet(item: $editingServer)` closure was
  causing a contextual type mismatch because the item closure and the `onSave` closure
  both referenced `server`, creating a capture ambiguity
- Replaced with `.sheet(isPresented:)` + manual `editingServer` binding, which avoids
  the conflicting closure argument entirely

## [0.1.014] — MDMServersView closure and mutation fixes
- Fixed `MDMServersView` error: `serverStore.update(id:_:)` closure takes one `inout MDMServer`
  argument — replaced `{ $0 = $1 }` (wrong two-argument form) with explicit field assignment
- Fixed `MDMServersView` warning: `var s` declared as `MDMServer` but never mutated after
  initialisation; changed to `let` (`password` is set via a `nonmutating set` on the struct)

## [0.1.013] — MainActor isolation fix for AppTheme in SidebarItem
- `SidebarItem.icon()` and `SidebarItem.label()` were calling `@MainActor`-isolated
  `AppTheme` properties from a `nonisolated` enum context, causing 12 compiler errors
- Fix: removed the theme-taking methods from the enum entirely; replaced with
  `defaultIcon` and `defaultLabel` computed properties (plain strings, nonisolated)
- Moved all themed label/icon resolution into `SidebarView` as `themedLabel(_:)` and
  `themedIcon(_:)` private methods — these run on the `@MainActor` as part of the View,
  so accessing `AppTheme` properties is safe there

## [0.1.012] — Hashable and actor isolation fixes
- Fixed `RecipesView` errors: added `Hashable` conformance to `PackerTemplate` with
  custom `==` and `hash(into:)` based on `id` (since `URL` is not `Hashable`)
- Fixed `InstallerView` warnings: `MistService.localIPSWs()` is actor-isolated and
  must be called with `await`; fixed both call sites in `loadInstallers()` and
  `downloadFirmware()` closures

## [0.1.011] — Major feature expansion

### Fun Mode (AppTheme)
- New `AppTheme` `@MainActor` observable with `@AppStorage("funModeEnabled")` toggle
- When enabled: Virtual Machines → Tarts, Base VMs → Recipes, Build → Bake,
  Registry → Pantry, Installers → Ingredients, Activity Log → Oven Log
- All sidebar labels, nav titles, buttons, and empty states read from `AppTheme`
- Toggle in Preferences > Appearance

### Activity Log (AppLogger + LogView)
- `AppLogger.shared` singleton — thread-safe, capped at 1000 entries
- `LogEntry` with timestamp, level (info/success/warning/error), source, message
- `LogView` — filterable by level and text search, auto-scrolls to newest entry,
  shows entry count and a Clear button
- All service operations (DependencyManager, BaseVMStore, VMStore) now log to AppLogger

### KeychainService
- New `KeychainService` static wrapper for `SecItemAdd/CopyMatching/Delete`
- Used by `BaseVM`, `MDMServer`, and `RegistryCredential` for secure password storage
- Service is `com.hooleahn.oven` so all secrets are scoped to the app

### Registry credentials (RegistryCredential + Preferences)
- `RegistryCredential` model with Keychain-backed password property
- Preferences > Registry credentials section: add/edit/delete per-registry credentials
- `RegistryCredentialSheet` covers registry host picker, username, and token/password
- Credentials persisted as JSON (without passwords) alongside Keychain entries

### MDM Servers (MDMServer + MDMServersView)
- New `MDMServer` model: friendly name, server URL, API client ID, Keychain password
- `MDMServerStore` (`@MainActor ObservableObject`) persists to `mdm-servers.json`
- `MDMServersView` — list, detail pane with connection test, add/edit sheet
- New sidebar item under MDM section

### MDM Enrollment (renamed + redesigned)
- Renamed from "MDM Profiles" to "MDM Enrollment" throughout
- `MDMProfile` redesigned: `serverID` (references `MDMServer`) + `invitationID`
  replacing the old `jamfServerURL`/`username` fields
- `EnrollmentType` enum: "Profile (desktop)" | "Link (URL)" matching motionbug guide
- `MDMProfileSheet` now has a server picker and invitation ID field
- `MDMEnrollmentView` uses `MDMServerStore` from environment to look up server names

### Base VMs — full redesign
- `MacOSRelease` catalogue: Sequoia/Sonoma/Ventura/Monterey with full version lists
- Auto-naming: `base-<os>-<version>` (e.g. `base-sequoia-15.3.2`) — no custom naming
- New `NewBaseVMSheet`: OS name picker + version picker (populated from catalogue),
  hardware as `Picker` dropdowns (not sliders), provisioning toggles
- Local vs registry separation in the list view (two `Section` groups)
- `BaseVM` now stores `osName`/`osVersion` separately, has Keychain password property
- `PackerService` completely rewritten:
  - `buildWithInit()` streams packer init then packer build in sequence (fixing the
    "Missing plugins" error — `packer init` is always run before `packer build`)
  - Template generated using motionbug.com guide style with variables + var file
  - `.pkrvars.hcl` var file includes `jamf_url`, `mdm_invitation_id`, `enrollment_type`,
    all feature toggles as booleans
  - `BuildConfig` struct captures all settings for template generation

### New VM hardware — dropdowns
- `NewVMSheet` hardware section now uses `Picker` dropdowns for CPU/memory/disk
  instead of `Slider` controls, matching HIG guidelines for discrete value selection

### Recipes view (Packer Templates)
- New `RecipesView` with a two-column layout: template file list on the left,
  `TextEditor` on the right with monospaced font for editing `.pkr.hcl` files
- Save and Revert buttons, dirty-state tracking, modification date in list

### Navigation — new sidebar items
- Sidebar now has: Library (VMs, Base VMs, Recipes, Installers, Registry),
  MDM (Servers, Enrollment), General (Activity Log, Preferences)
- All labels dynamically read from `AppTheme` for Fun Mode support

### HIG styling
- Removed monospaced font from non-code UI text throughout all views
- Reserved `SF Mono` / `.monospaced()` for: paths, IP addresses, version strings,
  build log lines, Packer template editor, and tart VM names
- `DetailRow` values use `.callout` weight instead of `.monospaced` where appropriate

## [0.1.011] — Major feature update

### Fun Mode (AppTheme)
- New `AppTheme` `@MainActor ObservableObject` with `@AppStorage("funModeEnabled")`
- Toggle in Preferences swaps labels throughout the app:
  Virtual Machines → Tarts · Base VMs → Recipes · Build → Bake · Registry → Pantry · Installers → Ingredients
- All views read labels and icons from the injected `AppTheme` environment object

### Activity Log (AppLogger + LogView)
- `AppLogger.shared` singleton accumulates timestamped `LogEntry` records (capped at 1 000)
- New "Activity Log" sidebar item shows filterable, searchable log with level picker (Info / OK / Warn / Error)
- Auto-scrolls to latest entry; text is selectable for copy-paste
- `DependencyManager`, `VMStore`, and `BaseVMStore` all emit log entries for operations and failures

### Registry credentials (KeychainService + PreferencesView)
- New `KeychainService` wrapping `SecItemAdd / SecItemCopyMatching / SecItemDelete`
- `RegistryCredential` model stores registry host + username; password lives in Keychain
- Credentials UI in Preferences: add/edit/delete per-registry credentials with PAT/token fields
- Explanation text for GHCR (read:packages + write:packages) and Docker Hub token scopes
- `RegistryService` will use stored credentials for `tart login` before push/pull

### MDM Servers (new view + model)
- New `MDMServer` model: friendly name, URL, API client ID; password in Keychain
- New `MDMServerStore` `@MainActor ObservableObject` persisting to `mdm-servers.json`
- New "MDM Servers" sidebar item with list, detail pane, connection test, add/edit sheet

### MDM Enrollment (renamed + redesigned)
- "MDM Profiles" renamed to "MDM Enrollment" throughout sidebar and nav titles
- `MDMProfile` redesigned: `serverID` (references `MDMServer`) replaces `jamfServerURL`/`username`
- Added `invitationID` field — Jamf Pro Enrollment Invitation ID (from the motionbug guide)
- Added `enrollmentType` enum: "Profile (desktop)" or "Link (URL)"
- New profile sheet requires selecting an MDM Server and entering an Invitation ID

### Packer Templates / Recipes (new view)
- New `RecipesView` lists all `.pkr.hcl` files in the templates directory
- Full `TextEditor` for in-app editing with Save / Revert controls
- Sidebar label is "Packer Templates" normally, "Recipes" in Fun Mode

### Base VM redesign
- Auto-naming convention enforced: `base-<os>-<version>` (no custom name/friendly name)
- `MacOSRelease` catalogue with `Name` enum (Sequoia, Sonoma, Ventura, Monterey) and full version lists per OS
- New Base VM sheet: OS name picker + version picker (populated from catalogue) instead of free-text
- Hardware options are now `Picker` dropdowns (not sliders): CPU [2,4,6,8,10,12,16], Memory [4–64 GB], Disk [40–500 GB]
- Base VMs list split into "Local" and "Registry" sections
- `BaseVM.password` stored in Keychain via `KeychainService`
- `PackerService.buildWithInit()` runs `packer init` then `packer build` in a single `AsyncStream`
  — fixes "Missing plugins (packer tart)" error caused by skipping init
- Template generation follows the motionbug.com guide:
  uses a separate `.pkrvars.hcl` variables file, supports `jamf_url`, `mdm_invitation_id`,
  `enrollment_type`, `enable_passwordless_sudo`, `enable_auto_login`, `enable_spotlight_disable`

### New VM sheet
- Hardware options are now `Picker` dropdowns (not sliders), matching Base VM sheet

### Navigation
- Sidebar reorganised: Library (VMs, Base VMs, Recipes, Installers, Registry) · MDM (Servers, Enrollment) · General (Activity Log, Preferences)

### Dependency check fix
- `DependencyManager.bootstrap()` already skips installed tools via `fileExists()`; now logs
  "already installed — skipping" to Activity Log for each tool that is already present

### HIG styling
- Removed monospaced font from non-code text elements throughout all views
- Reserved `font(.system(.callout, design: .monospaced))` for paths, IP addresses, build log lines,
  version numbers, and template editor only
- `DetailRow` values use `.fontWeight(.medium)` without monospaced for human-readable fields

## [0.1.010] — MDMProfile Hashable conformance
- Fixed `MDMProfileView` errors: added `Hashable` conformance to `MDMProfile` so it
  can be used with `List(_:id:selection:rowContent:)` and `.tag(_:)`

## [0.1.009] — Build error and warning fixes
- Fixed `RegistryView` error: added `registryImageRef` parameter to `VMStore.clone()`
  and threaded it through to the `VirtualMachine` placeholder
- Fixed `MistService` warning: removed unused `outputPath` variable in `downloadFirmware()`
- Fixed `RegistryService` warning: changed `var components` to `let` (never mutated)

## [0.1.008] — Full feature build: all views and services implemented

### VMListView
- Card grid with adaptive layout, thumbnails, status colour-coding
- `StatusDot` and `StatusPill` components for running/stopped/suspended/building states
- Per-card Start / Stop / Delete actions with confirmation dialog
- `VMDetailPane` — 260pt side pane with config, network, metadata sections and SSH button
- `DetailSection` / `DetailRow` shared components (reused across Base VM and MDM views)
- `NewVMSheet` — source type picker, VM name, display name, hardware sliders
- Tag display on cards with horizontal scroll; tag filtering via search

### BaseVMView + BaseVMStore + PackerService
- `BaseVMStore` — `@MainActor` store owning BaseVM records, streaming Packer build logs,
  persisting metadata to `base-vms/metadata.json`
- `PackerService` — wraps `packer build` with streaming, `packer init`, `packer validate`,
  and `writeDefaultTemplate()` to auto-generate `.pkr.hcl` files from BaseVM config
- `BaseVMView` — list with status badges, build progress indicator, cancel build button
- `BaseVMDetailPane` — build log tail (last 20 lines), Edit / Build / Delete actions
- `BaseVMSettingsSheet` — full form: identity, credentials, hardware sliders, provisioning
  toggles (Rosetta, Homebrew, SSH, Xcode version)

### InstallerView + MistService
- `MistService` — `listFirmware()` decoding mist-cli JSON, `downloadFirmware()` streaming
  progress, `localIPSWs()` scanning the IPSW storage directory
- `InstallerView` — remote list with compatible-only filter, per-item download progress bars,
  local IPSW section showing already-downloaded files
- Progress parsing from mist-cli `%` output lines

### RegistryView + RegistryService
- `RegistryService` — `pull()` / `push()` via tart clone/push streaming, `login()`,
  `listGHCRTags()` via GitHub API
- `RegistryView` — registry switcher (ghcr.io / docker.io), image list with pull status,
  add-image-ref bar, pull progress, "Create VM" from pulled images

### MDMProfileView + JamfService
- `JamfService` — Bearer token auth with auto-refresh, `findDevice()`, `removeDevice()`,
  `enrollmentURL()`, `testConnection()` returning Jamf Pro version string
- `MDMProfileView` — profile list with expiry status, detail pane with connection test,
  `MDMProfileSheet` covering server URL, credentials note (Keychain), enrollment method,
  token lifetime, scope, and run-policy-on-enroll toggle
- Profiles persisted to `mdm-profiles.json` in App Support

### AppRootView wiring
- `AppRootView` now initialises `TartService`, `PackerService`, `VMStore`, and `BaseVMStore`
  and injects all four into the SwiftUI environment
- `OvenApp.AppRootView.init()` uses `StateObject(wrappedValue:)` pattern for deterministic
  service initialisation with correct storage paths from `AppSettings`

## [0.1.007] — TartService async fix + display name
- Fixed `TartService` actor isolation errors: `run()`, `pull()`, and `push()` are
  now correctly marked `async` to cross the `ProcessRunner` actor boundary
- Fixed `VMStore.start()` signature to match (`async`)
- Set app window title to "Oven — macOS VM Manager powered by Tart"
- Added `LSApplicationCategoryType = developer-tools` to Info.plist
- Added `CFBundleDisplayName` to Info.plist

## [0.1.006] — TartService + VMStore data layer
- Added `TartService` actor wrapping all tart CLI operations:
  `list`, `run`, `stop`, `suspend`, `clone`, `delete`, `ip`, `set`, `pull`, `push`, `login`
- Added `VMStore` — the `@MainActor` source of truth for all VM records:
  - Persists Oven metadata (display name, tags, description, MDM profile ref) as JSON
  - Syncs with `tart list` on launch and after mutations
  - `mergeWithTart()` adds unknown VMs, updates status, never auto-removes records
  - Clone adds a `.building` placeholder immediately for live UI feedback
- Updated `VirtualMachine` model with `Status.init(tartState:)` and `init(fromTart:)`
- Added `AppState.OperationRecord` for tracking in-progress async operations with log lines
- Added `AppRootView` to defer `TartService`/`VMStore` init until deps are ready
- `VMStore` injected into SwiftUI environment via `AppRootView`

## [0.1.005] — NavigationSplitView shell
- Replaced stub `ContentView` with full `NavigationSplitView` (sidebar + detail)
- Added `SidebarItem` enum with SF Symbol icons and section grouping
- Added `DetailRouter` switching on sidebar selection
- Added `OvenStatusBar` at sidebar bottom showing dep readiness indicator
- Added `AppState` observable for cross-view coordination (search, sheet routing, operations)
- Added `PreferencesView` with storage location pickers for VMs, IPSWs, templates, deps
- Added `EmptyDetailView` using `ContentUnavailableView`
- All detail views updated with `navigationTitle` and empty states
- Fixed `OvenApp` `.commands` block — `@StateObject` is not accessible from `Scene`
  modifier closures; moved "Check for Updates" to `PreferencesView`

## [0.1.004] — Build errors fixed: actor isolation + pbxproj corruption
- Fixed `TartService` actor isolation error (`checkForUpdates` called via key path)
- Switched pbxproj generation strategy: always regenerate from scratch rather than
  patching with regex — eliminates parse errors caused by malformed insertions
- Added brace-balance and per-file verification checks to the generator script

## [0.1.003] — Dependency installation fixed for all tools
- **tart**: was downloading a bare binary — fixed to download `tart.tar.gz` and
  extract binary from `tart.app/Contents/MacOS/tart`
- **mist-cli**: `pkgutil --expand-full` fails on newer pkg formats — replaced with
  `xar -xf` to unpack outer archive, then `gunzip | cpio -id` pipeline to extract
  the `Payload` cpio archive; also switched to GitHub API asset list lookup so the
  `.pkg` URL is always resolved dynamically rather than hard-coded
- **packer-plugin-tart**: manual zip extraction was wrong — binary name embeds a
  SHA256 checksum that Packer validates, and the plugin directory structure must
  match exactly; replaced with `packer plugins install github.com/cirruslabs/tart`
  which handles naming, verification, and placement automatically
- **jq**: confirmed raw binary download is correct; no change needed
- **packer**: confirmed HashiCorp zip + binary extraction is correct; no change needed

## [0.1.002] — Xcode project path fixes
- Fixed `CODE_SIGN_ENTITLEMENTS` and `INFOPLIST_FILE` build setting paths —
  were pointing to `Resources/...` relative to a parent directory; corrected to
  resolve relative to `SOURCE_ROOT` (the folder containing `Oven.xcodeproj`)
- Moved `Oven.xcodeproj` inside the `Oven/` source folder so `SOURCE_ROOT`
  resolves correctly alongside `Core/`, `UI/`, `Models/`, etc.
- Updated `PRODUCT_BUNDLE_IDENTIFIER` to `com.hooleahn.oven`

## [0.1.001] — Initial project scaffold
- Generated full `.xcodeproj` with `PBXNativeTarget`, build phases, and
  group structure matching the folder layout on disk
- **Core layer**
  - `ProcessRunner` — `actor` wrapping `Foundation.Process` with three entry
    points: `stream()` returning `AsyncStream<ProcessEvent>` for long-running
    processes, `run()` collecting stdout/stderr, `runJSON()` decoding output
  - `Dependency` + `DepsManifest` — value types for dependency state and
    the `deps/versions.json` manifest
  - `DependencyManager` — `@MainActor ObservableObject` that bootstraps all
    CLI tools on launch; downloads from official GitHub/HashiCorp release URLs,
    verifies SHA256, installs to `<storageRoot>/deps/`
- **Models** (initial stubs)
  - `AppSettings` — storage paths persisted as JSON in App Support
  - `VirtualMachine`, `BaseVM`, `MDMProfile` — core domain models
- **Services** (stubs)
  - `TartService`, `PackerService`, `MistService`, `RegistryService`, `JamfService`
- **UI**
  - `OvenApp` — `@main` entry point with `WindowGroup`
  - `SetupView` — first-launch dependency installation screen with per-tool
    status rows, progress indicators, and scrolling install log
  - All other views as `ContentUnavailableView` stubs
- **Resources**
  - `Info.plist`, `Oven.entitlements` (sandbox disabled, network client enabled,
    Keychain access group), `Assets.xcassets` with AppIcon slot
