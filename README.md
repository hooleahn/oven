# Oven

macOS VM Manager — build and manage macOS VMs using tart, Packer, and mist-cli.

## Requirements
- macOS 14.0+
- Xcode 15.4+
- Apple Silicon Mac recommended

## Opening in Xcode
Open `Oven/Oven.xcodeproj`. Set your Development Team in Signing & Capabilities.

## Project layout
```
Oven/
├── Oven.xcodeproj
├── Core/          ProcessRunner · Dependency · DependencyManager
├── Models/        AppSettings · VirtualMachine · BaseVM · MDMProfile
├── Services/      TartService · PackerService · MistService · RegistryService · JamfService
├── UI/            OvenApp · ContentView · SetupView · all view stubs
└── Resources/     Info.plist · Oven.entitlements · Assets.xcassets
```
