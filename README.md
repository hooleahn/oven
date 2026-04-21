# Oven
![image](https://github.com/hooleahn/oven/blob/cc947c527ae98a2dfaff0d97db1c1afb1cf552fe/Icon%20Exports/Icon-macOS-Default-128x128%402x.png)


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
