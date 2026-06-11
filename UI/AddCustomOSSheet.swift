import SwiftUI

struct AddCustomOSSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CustomOSStore.self) private var customOSStore

    var onAdd: ((CustomOSEntry) -> Void)? = nil

    @State private var releaseName = ""
    @State private var majorVersionText = ""
    @State private var majorVersionError: String? = nil

    private var majorVersionInt: Int? { Int(majorVersionText.trimmingCharacters(in: .whitespaces)) }

    private var canAdd: Bool {
        !releaseName.trimmingCharacters(in: .whitespaces).isEmpty
        && majorVersionInt != nil
        && majorVersionInt! > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Custom OS").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.escape)
                Button("Add") { addEntry() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
            .padding(16).background(.bar)
            Divider()
            Form {
                Section {
                    LabeledContent("Release name") {
                        TextField("e.g. Yuba", text: $releaseName)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Major version") {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("e.g. 27", text: $majorVersionText)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: majorVersionText) { _, v in
                                    let filtered = v.filter { $0.isNumber }
                                    if filtered != v { majorVersionText = filtered }
                                    majorVersionError = (!filtered.isEmpty && Int(filtered) == nil)
                                        ? "Must be a positive integer" : nil
                                }
                            if let err = majorVersionError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                } footer: {
                    Text("This custom OS will appear in all OS pickers alongside standard macOS releases.")
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 360, idealWidth: 400, minHeight: 220)
    }

    private func addEntry() {
        guard let v = majorVersionInt, v > 0 else { return }
        let entry = CustomOSEntry(
            releaseName: releaseName.trimmingCharacters(in: .whitespaces),
            majorVersion: v
        )
        customOSStore.add(entry)
        onAdd?(entry)
        dismiss()
    }
}
