import SwiftUI
import AppKit

struct LogView: View {
    @EnvironmentObject var logger: AppLogger
    @EnvironmentObject var appState: AppState
    @State private var filterLevel: LogEntry.Level? = nil
    @State private var searchText = ""
    @State private var isRefreshing: Bool = false
    @State private var refreshRotation: Double = 0

    var filtered: [LogEntry] {
        logger.entries
            .filter { filterLevel == nil || $0.level == filterLevel }
            .filter { searchText.isEmpty || $0.message.localizedCaseInsensitiveContains(searchText) || $0.source.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Time grouping

    private enum TimeGroup: String, CaseIterable {
        case lastHour  = "Last Hour"
        case today     = "Today"
        case yesterday = "Yesterday"
        case older     = "Older"
    }

    private func timeGroup(for entry: LogEntry) -> TimeGroup {
        let now = Date()
        let cal = Calendar.current
        if now.timeIntervalSince(entry.timestamp) < 3600 { return .lastHour }
        if cal.isDateInToday(entry.timestamp)            { return .today }
        if cal.isDateInYesterday(entry.timestamp)        { return .yesterday }
        return .older
    }

    private func entries(in group: TimeGroup) -> [LogEntry] {
        filtered.filter { timeGroup(for: $0) == group }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                EmptyStateView("No Log Entries", systemImage: "list.bullet.rectangle",
                               description: "Operations will be logged here as you use Oven.")
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(TimeGroup.allCases, id: \.self) { group in
                            let groupEntries = entries(in: group)
                            if !groupEntries.isEmpty {
                                Section {
                                    ForEach(Array(groupEntries.enumerated()), id: \.element.id) { index, entry in
                                        LogEntryRow(entry: entry, isEven: index.isMultiple(of: 2))
                                            .id(entry.id)
                                            .listRowSeparator(.hidden)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12))
                                            .listRowBackground(
                                                index.isMultiple(of: 2)
                                                    ? Color.primary.opacity(0.02)
                                                    : Color.clear
                                            )
                                    }
                                } header: {
                                    Text(group.rawValue)
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .textCase(nil)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: logger.entries.count) { _, _ in
                        if let last = filtered.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter log…")
        .toolbar {
            // 1. Navigation group (empty)
            ToolbarItemGroup(placement: .navigation) {}

            // 2. Primary action — Export log (⌘N not applicable; Export is primary here)
            ToolbarItem(placement: .primaryAction) {
                Button("Export…") { exportLog() }
                    .help("Export activity log to a file")
            }

            // 3. Secondary actions — Clear
            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Clear") { logger.clear() }
                    .help("Clear all log entries")
            }

            // 4. Flexible space
            ToolbarItem(placement: .automatic) {
                Spacer()
            }

            // 5. Search provided by .searchable

            // 6. Level filter picker + entry count
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Text("\(logger.entries.count) entries")
                        .font(.caption).foregroundStyle(.secondary)

                    Picker(selection: $filterLevel) {
                        Text("All").tag(Optional<LogEntry.Level>.none)
                        Text("Info").tag(Optional(LogEntry.Level.info))
                        Text("OK").tag(Optional(LogEntry.Level.success))
                        Text("Warn").tag(Optional(LogEntry.Level.warning))
                        Text("Error").tag(Optional(LogEntry.Level.error))
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    .labelsHidden()
                }
            }

            // 7. Refresh (⌘R) — scrolls to latest entry
            ToolbarItem(placement: .automatic) {
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        refreshRotation = 360
                    }
                    // Brief animation then reset — log is always live
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isRefreshing = false
                        refreshRotation = 0
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? refreshRotation : 0))
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Scroll to latest log entry (⌘R)")
            }
        }
        .navigationTitle("Activity Log")
        .task { appState.windowTitle = "Logs"; appState.windowSubtitle = "" }
    }

    private func exportLog() {
        let lines = logger.entries.map { entry -> String in
            let ts = entry.timestamp.formatted(date: .numeric, time: .standard)
            return "[" + ts + "] [" + entry.source + "] " + entry.message
        }
        let text = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.title = "Export Activity Log"
        panel.nameFieldStringValue = "oven-activity-log.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Log entry row

struct LogEntryRow: View {
    let entry: LogEntry
    var isEven: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // 3px colored accent bar on the left edge
            Rectangle()
                .fill(accentBarColor)
                .frame(width: 3)
                .padding(.vertical, 4)

            Text(entry.formattedTimestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.5))
                .frame(width: 60, alignment: .leading)

            Image(systemName: levelIcon)
                .font(.caption)
                .foregroundStyle(levelColor)
                .frame(width: 14)

            Text(entry.source)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.5))
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)

            Text(entry.message)
                .font(.callout)
                .fontWeight(entry.level == .error ? .medium : .regular)
                .foregroundStyle(entry.level == .error ? .red : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .padding(.leading, 12)
    }

    private var accentBarColor: Color {
        switch entry.level {
        case .success: return .green
        case .error:   return .red
        case .warning: return .orange
        case .info:    return .blue.opacity(0.6)
        }
    }

    private var levelIcon: String {
        switch entry.level {
        case .info:    return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .info:    return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
