import SwiftUI

// MARK: - ExecMethod

enum ExecMethod: String, Hashable {
    case ssh          = "SSH (sshpass)"
    case guestAgent   = "Guest Agent"
}

// MARK: - ExecuteCommandSheet

struct ExecuteCommandSheet: View {
    @Environment(\.dismiss) private var dismiss
    let vm: VirtualMachine

    @State private var selectedMethod: ExecMethod
    @State private var command: String = ""
    @State private var outputLines: [(String, Bool)] = []   // (line, isStderr)
    @State private var isRunning = false
    @State private var exitCode: Int32? = nil

    init(vm: VirtualMachine, initialMethod: ExecMethod = .ssh) {
        self.vm = vm
        _selectedMethod = State(initialValue: initialMethod)
    }

    // MARK: - Availability checks

    private var sshpassPath: String? {
        let depPath = AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/sshpass").path
        if FileManager.default.fileExists(atPath: depPath) { return depPath }
        let systemPaths = ["/opt/homebrew/bin/sshpass", "/usr/local/bin/sshpass", "/opt/local/bin/sshpass"]
        return systemPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private var tartBinaryPath: String {
        AppSettings.defaultLocalStorageRoot
            .appendingPathComponent("deps/tart.app/Contents/MacOS/tart").path
    }

    private var canUseSSH: Bool {
        vm.status == .running &&
        vm.ipAddress != nil && !(vm.ipAddress?.isEmpty ?? true) &&
        vm.sshPassword != nil &&
        sshpassPath != nil
    }

    private var canUseGuestAgent: Bool {
        vm.supportsGuestAgent && vm.status == .running
    }

    private var canRun: Bool {
        !command.trimmingCharacters(in: .whitespaces).isEmpty && !isRunning &&
        ((selectedMethod == .ssh && canUseSSH) ||
         (selectedMethod == .guestAgent && canUseGuestAgent))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                methodPicker
                warningBanner
                commandRow
                if !outputLines.isEmpty || isRunning {
                    outputPanel
                }
            }
            .padding(16)
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 220)
    }

    // MARK: - Sub-views

    private var headerBar: some View {
        HStack {
            Text("Execute Command")
                .font(.headline)
            Text("— \(vm.displayName.isEmpty ? vm.name : vm.displayName)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.escape)
        }
        .padding(16)
        .background(.bar)
    }

    private var methodPicker: some View {
        HStack {
            Text("Method")
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $selectedMethod) {
                Text(ExecMethod.ssh.rawValue).tag(ExecMethod.ssh)
                Text(ExecMethod.guestAgent.rawValue).tag(ExecMethod.guestAgent)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
        }
    }

    @ViewBuilder private var warningBanner: some View {
        if selectedMethod == .ssh && !canUseSSH {
            warningRow(message: sshUnavailableReason)
        } else if selectedMethod == .guestAgent && !canUseGuestAgent {
            warningRow(message: guestAgentUnavailableReason)
        }
    }

    private func warningRow(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var sshUnavailableReason: String {
        if vm.status != .running { return "VM must be running to use SSH." }
        if vm.ipAddress == nil || vm.ipAddress?.isEmpty == true { return "Waiting for IP address…" }
        if vm.sshPassword == nil { return "No password stored. Set a password in the VM's edit sheet." }
        return "sshpass not found. Install via Homebrew: brew install sshpass"
    }

    private var guestAgentUnavailableReason: String {
        if !vm.supportsGuestAgent {
            return "Tart Guest Agent is not enabled for this VM. Enable it in the VM's edit sheet."
        }
        return "VM must be running to use Guest Agent."
    }

    private var commandRow: some View {
        HStack(spacing: 8) {
            TextField("Command to run inside VM…", text: $command)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canRun { runCommand() } }
            Button("Run") { runCommand() }
                .buttonStyle(.borderedProminent)
                .disabled(!canRun)
        }
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Output")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let code = exitCode {
                    Text("Exit \(code)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(code == 0 ? .green : .red)
                }
                if isRunning {
                    ProgressView().controlSize(.mini)
                }
                Button("Clear") {
                    outputLines = []
                    exitCode = nil
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isRunning)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(outputLines.indices, id: \.self) { i in
                            let (line, isErr) = outputLines[i]
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(isErr ? .red : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: outputLines.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            .frame(minHeight: 120, maxHeight: 300)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5) }
    }

    // MARK: - Run logic

    private func runCommand() {
        guard canRun else { return }
        isRunning = true
        exitCode = nil
        switch selectedMethod {
        case .ssh:         Task { await runViaSSH() }
        case .guestAgent:  Task { await runViaGuestAgent() }
        }
    }

    @MainActor
    private func runViaSSH() async {
        guard let ip = vm.ipAddress, !ip.isEmpty,
              let password = vm.sshPassword, !password.isEmpty,
              let sshpass = sshpassPath else {
            isRunning = false; return
        }
        let user = vm.sshUsername.isEmpty ? "baker" : vm.sshUsername
        let runner = ProcessRunner()
        let stream = await runner.stream(sshpass, arguments: [
            "-p", password,
            "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=10",
            "\(user)@\(ip)",
            command
        ])
        for await event in stream {
            switch event {
            case .stdout(let line):  outputLines.append((line, false))
            case .stderr(let line):  if !line.isEmpty { outputLines.append((line, true)) }
            case .exit(let code):    exitCode = code; isRunning = false
            }
        }
    }

    @MainActor
    private func runViaGuestAgent() async {
        guard FileManager.default.fileExists(atPath: tartBinaryPath) else {
            outputLines.append(("tart not found at \(tartBinaryPath)", true))
            isRunning = false; return
        }
        let runner = ProcessRunner()
        let stream = await runner.stream(tartBinaryPath, arguments: [
            "exec", vm.name,
            "/bin/sh", "-c", command
        ])
        for await event in stream {
            switch event {
            case .stdout(let line):  outputLines.append((line, false))
            case .stderr(let line):  if !line.isEmpty { outputLines.append((line, true)) }
            case .exit(let code):    exitCode = code; isRunning = false
            }
        }
    }
}
