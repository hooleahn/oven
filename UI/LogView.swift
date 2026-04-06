import SwiftUI
import AppKit

struct LogView: View {
    @EnvironmentObject var logger: AppLogger
    @State private var filterLevel: LogEntry.Level? = nil
    @State private var searchText = ""

    var filtered: [LogEntry] {
        logger.entries
            .filter { filterLevel == nil || $0.level == filterLevel }
            .filter { searchText.isEmpty || $0.message.localizedCaseInsensitiveContains(searchText) || $0.source.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.footnote)
                    TextField("Filter log…", text: $searchText).textFieldStyle(.plain).font(.callout)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .frame(maxWidth: 200)

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

                Spacer()

                Text("\(logger.entries.count) entries")
                    .font(.caption).foregroundStyle(.secondary)

                Button("Export…") { exportLog() }
                    .controlSize(.small)
                Button("Clear") { logger.clear() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)

            Divider()

            if filtered.isEmpty {
                EmptyStateView("No Log Entries", systemImage: "list.bullet.rectangle",
                               description: "Operations will be logged here as you use Oven.")
            } else {
                ScrollViewReader { proxy in
                    List(filtered) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                            .listRowSeparator(.visible)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
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
        .navigationTitle("Activity Log")
    }

    private func exportLog() {
        let lines = logger.entries.map { entry -> String in
            let ts = entry.timestamp.formatted(date: .abbreviated, time: .standard)
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.formattedTimestamp)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Image(systemName: levelIcon)
                .font(.caption)
                .foregroundStyle(levelColor)
                .frame(width: 14)

            Text(entry.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)

            Text(entry.message)
                .font(.callout)
                .foregroundStyle(entry.level == .error ? .red : .primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
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
