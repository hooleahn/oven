import SwiftUI


struct BuildLogView: View {
    let baseVM: VirtualMachine
    var monitor = BuildMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    baseVM.buildStatus == .building ? "Building…" : "Build failed",
                    systemImage: baseVM.buildStatus == .building ? "terminal" : "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(baseVM.buildStatus == .error ? .red : .secondary)
                Spacer()
                if baseVM.buildStatus == .building {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(monitor.elapsedFormatted)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(baseVM.buildLog.joined(separator: "\n"), forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy full build log to clipboard")
                .disabled(baseVM.buildLog.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(baseVM.buildLog.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(lineColor(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator.opacity(0.5)) }
                .onChange(of: baseVM.buildLog.count) { _, _ in
                    if let last = baseVM.buildLog.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
                .onAppear {
                    if let last = baseVM.buildLog.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private func lineColor(_ line: String) -> Color {
        buildLogLineColor(line)
    }
}
