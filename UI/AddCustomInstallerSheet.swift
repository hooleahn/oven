import SwiftUI
import UniformTypeIdentifiers

struct AddCustomInstallerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var customInstallerStore: CustomInstallerStore
    @EnvironmentObject var customOSStore: CustomOSStore

    @State private var displayName = ""
    @State private var osName: MacOSRelease.Name = .sequoia
    @State private var customOSReleaseName = ""
    @State private var customOSMajorVersion = ""
    @State private var majorVersionError: String? = nil
    @State private var osVersion = ""
    @State private var osVersionError: String? = nil
    @State private var isBeta = false
    @State private var betaLabel = ""
    @State private var ipswPath = ""
    @State private var copyToStorage = true
    @State private var isPresentingFilePicker = false
    @State private var pickerCommittedURL: URL? = nil
    @State private var pickerPendingURL: URL? = nil

    private static let ipswVersionRegex = /^\d+(\.\d+)*$/

    private var canRegister: Bool {
        !ipswPath.isEmpty
        && osVersionError == nil
        && majorVersionError == nil
        && (osName != .custom || (!customOSReleaseName.isEmpty && !customOSMajorVersion.isEmpty))
        && !customInstallerStore.isCopying
    }

    private var pickerOSNames: [MacOSRelease.Name] {
        MacOSRelease.Name.allCases.filter { $0 != .unknown && $0 != .any }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Register Custom Installer").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                if customInstallerStore.isCopying {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Register") { Task { await register() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canRegister)
                }
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section("IPSW File") {
                    LabeledContent("File") {
                        HStack {
                            if ipswPath.isEmpty {
                                Text("No file selected")
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else {
                                Text(URL(fileURLWithPath: ipswPath).lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            Button("Browse…") {
                                pickerPendingURL = nil
                                isPresentingFilePicker = true
                            }
                            .controlSize(.small)
                        }
                    }
                    Toggle("Copy to Oven's IPSW storage", isOn: $copyToStorage)
                }

                Section("OS") {
                    Picker("macOS", selection: $osName) {
                        ForEach(pickerOSNames, id: \.self) { release in
                            Text(release.displayLabel).tag(release)
                        }
                    }
                    .onChange(of: osName) { _, _ in
                        customOSReleaseName = ""
                        customOSMajorVersion = ""
                        majorVersionError = nil
                    }
                    if osName == .custom {
                        if !customOSStore.entries.isEmpty {
                            Menu("Pick existing…") {
                                ForEach(customOSStore.entries) { entry in
                                    Button(entry.pickerLabel) {
                                        customOSReleaseName = entry.releaseName
                                        customOSMajorVersion = String(entry.majorVersion)
                                    }
                                }
                            }
                            .controlSize(.small)
                        }
                        LabeledContent("Release name") {
                            TextField("e.g. Yuba", text: $customOSReleaseName)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Major version") {
                            VStack(alignment: .trailing, spacing: 2) {
                                TextField("e.g. 27", text: $customOSMajorVersion)
                                    .multilineTextAlignment(.trailing)
                                    .onChange(of: customOSMajorVersion) { _, v in
                                        let filtered = v.filter { $0.isNumber }
                                        if filtered != v { customOSMajorVersion = filtered }
                                        majorVersionError = (!filtered.isEmpty && Int(filtered) == nil)
                                            ? "Must be a positive integer" : nil
                                    }
                                if let err = majorVersionError {
                                    Text(err).font(.caption).foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    LabeledContent("Version") {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("e.g. 15.4 or 26.5", text: $osVersion)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: osVersion) { _, v in
                                    osVersionError = (!v.isEmpty && v.wholeMatch(of: Self.ipswVersionRegex) == nil)
                                        ? "Use digits and dots only (e.g. 15.4)" : nil
                                }
                            if let err = osVersionError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }

                Section("Beta") {
                    Toggle("Beta OS", isOn: $isBeta)
                    if isBeta {
                        LabeledContent("Beta label") {
                            TextField("e.g. Beta 1, RC 2", text: $betaLabel)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section {
                    LabeledContent("Display name") {
                        TextField(autoDisplayName, text: $displayName)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Label")
                } footer: {
                    Text("Leave blank to use the auto-generated name.")
                }
            }
            .formStyle(.grouped)

            if let err = customInstallerStore.copyError {
                Text(err)
                    .font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 500)
        .fileImporter(isPresented: $isPresentingFilePicker,
                      allowedContentTypes: [UTType(filenameExtension: "ipsw") ?? .data]) { result in
            pickerPendingURL = try? result.get()
        }
        .onChange(of: pickerPendingURL) { _, url in
            guard let url, url != pickerCommittedURL else { return }
            pickerCommittedURL = url
            ipswPath = url.path
        }
    }

    private var autoDisplayName: String {
        let betaSuffix = isBeta ? (betaLabel.isEmpty ? " Beta" : " \(betaLabel)") : ""
        switch osName {
        case .custom:
            let name = customOSReleaseName
            let vers = osVersion.isEmpty ? customOSMajorVersion : osVersion
            if !name.isEmpty && !vers.isEmpty { return "\(name) \(vers)\(betaSuffix)" }
            if !name.isEmpty { return name + betaSuffix }
            if !vers.isEmpty { return vers + betaSuffix }
            return "Custom OS\(betaSuffix)"
        default:
            if osVersion.isEmpty { return osName.rawValue + betaSuffix }
            return "\(osName.rawValue) \(osVersion)\(betaSuffix)"
        }
    }

    private func register() async {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        await customInstallerStore.register(
            displayName: name.isEmpty ? autoDisplayName : name,
            osName: osName,
            customOSReleaseName: customOSReleaseName.trimmingCharacters(in: .whitespaces),
            customOSMajorVersion: customOSMajorVersion.trimmingCharacters(in: .whitespaces),
            osVersion: osVersion.trimmingCharacters(in: .whitespaces),
            isBeta: isBeta,
            betaLabel: betaLabel.trimmingCharacters(in: .whitespaces),
            sourceURL: URL(fileURLWithPath: ipswPath),
            copyToStorage: copyToStorage
        )
        if customInstallerStore.copyError == nil {
            // Auto-save to custom OS store if using a custom release name
            if osName == .custom,
               !customOSReleaseName.isEmpty,
               let major = Int(customOSMajorVersion) {
                customOSStore.findOrCreate(releaseName: customOSReleaseName, majorVersion: major)
            }
            dismiss()
        }
    }
}
