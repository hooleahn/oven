import SwiftUI
import AppKit


struct LiveBuildLogPanel: View {
    let baseVM: VirtualMachine
    var monitor = BuildMonitor.shared
    @State private var vncURL: String? = nil
    @State private var vncPassword: String? = nil
    @State private var didAutoConnect = false
    @AppStorage("showGraphicsDuringBuild") private var showGraphics: Bool = false
    @AppStorage("debugModeEnabled") private var debugMode: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Building \(baseVM.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(monitor.elapsedFormatted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if let vnc = vncURL {
                    Button {
                        openVNC(vnc, password: vncPassword)
                    } label: {
                        Label("Connect VNC", systemImage: "display.and.arrow.down")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(vncPassword != nil ? "Open VNC (password copied to clipboard)" : "Open VNC viewer")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Log output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(baseVM.buildLog.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(logLineColor(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1)
                                .id(idx)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: baseVM.buildLog.count) { _, _ in
                    if let last = baseVM.buildLog.indices.last {
                        withAnimation(nil) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                    // Parse VNC URL from log output, then auto-connect if appropriate
                    detectVNC(in: baseVM.buildLog)
                    autoConnectIfReady()
                }
                .onAppear {
                    if let last = baseVM.buildLog.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                    detectVNC(in: baseVM.buildLog)
                    autoConnectIfReady()
                }
            }
        }
        .onDisappear {
            // Build ended — close VNC if it was auto-opened
            if didAutoConnect {
                BuildSessionManager.shared.closeVNCIfOpen()
            }
        }
    }

    private func logLineColor(_ line: String) -> Color {
        buildLogLineColor(line)
    }

    private func detectVNC(in log: [String]) {
        // tart outputs two relevant lines:
        // 1. "...connect via VNC with the password "napkin-source-mom-garage" to"
        // 2. "vnc://127.0.0.1:5900" (on the next line, or same line)
        // We scan all lines for both patterns regardless of showGraphics —
        // tart may output VNC info even in headless mode.
        for line in log {
            // Extract password from: ...password "some-words-here" to
            if vncPassword == nil,
               let range = line.range(of: #"password "([^"]+)""#,
                                      options: .regularExpression) {
                let match = String(line[range])
                // Extract just the password between the quotes
                // Split on quote character to extract the password value
                let parts = match.components(separatedBy: "\"")
                if parts.count >= 2 { vncPassword = parts[1] }
            }
            // Extract VNC URL
            if vncURL == nil,
               let range = line.range(of: #"vnc://[^ \t\"]+"#, options: .regularExpression) {
                vncURL = String(line[range])
            }
        }
    }

    private func autoConnectIfReady() {
        guard !didAutoConnect,
              (showGraphics || debugMode),
              let url = vncURL else { return }
        didAutoConnect = true
        // Small delay so Screen Sharing has time to become ready
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            openVNC(url, password: vncPassword)
        }
    }

    private func openVNC(_ url: String, password: String?) {
        // Embed password in the VNC URL: vnc://:password@host:port
        // macOS Screen Sharing supports credentials in the URL
        var urlWithCreds = url
        if let pw = password {
            // Transform vnc://host:port → vnc://:password@host:port
            if url.hasPrefix("vnc://") {
                let host = String(url.dropFirst("vnc://".count))
                urlWithCreds = "vnc://:" + pw + "@" + host
            }
            // Also copy to clipboard as a fallback
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pw, forType: .string)
        }
        if let u = URL(string: urlWithCreds) {
            NSWorkspace.shared.open(u)
        }
    }
}
