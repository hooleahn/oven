import SwiftUI

// MARK: - BuildProgressHeader
//
// Displays a 5-phase progress row + determinate progress bar + elapsed/ETA line.
// Consumed by LiveBuildLogPanel and BuildLogView while a build is active.

struct BuildProgressHeader: View {

    var monitor = BuildMonitor.shared
    @State var buildPhases: [BuildPhase] = BuildPhase.allCases

    var body: some View {
        VStack(spacing: 8) {
            // Phase indicator row
            HStack(spacing: 0) {
                ForEach(buildPhases.indices, id: \.self) { index in
                                    let phase = buildPhases[index]
                                    
                                    if index > 0 {
                                        // Connector line
                                        Rectangle()
                                            // Usamos 'phase' y 'monitor.phase' para la lógica
                                            .fill(phase.rawValue <= monitor.phase.rawValue
                                                  ? Color.accentColor
                                                  : Color.secondary.opacity(0.3)) // 'secondary' es más seguro en SwiftUI que 'separator'
                                            .frame(maxWidth: .infinity, maxHeight: 2)
                                    }
                    PhaseCircle(
                        phase: phase,
                        currentPhase: monitor.phase
                    )
                }
            }
            .padding(.horizontal, 12)

            // Determinate progress bar
            ProgressView(value: monitor.progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .padding(.horizontal, 12)

            // Elapsed · ETA
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(monitor.elapsedFormatted + " elapsed")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let remaining = monitor.remainingFormatted {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(remaining + " remaining")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Text(monitor.phase.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
        .padding(.top, 8)
        .background(.bar)
    }
}

// MARK: - PhaseCircle

private struct PhaseCircle: View {

    let phase: BuildPhase
    let currentPhase: BuildPhase

    @State private var pulsing = false

    private var isCurrent: Bool { phase == currentPhase }
    private var isComplete: Bool { phase.rawValue < currentPhase.rawValue }
    private var isFuture: Bool  { phase.rawValue > currentPhase.rawValue }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Background circle
                Circle()
                    .fill(circleBackground)
                    .frame(width: 28, height: 28)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                } else if isCurrent {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .scaleEffect(pulsing ? 1.3 : 1.0)
                        .opacity(pulsing ? 0.6 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                            value: pulsing
                        )
                } else {
                    Circle()
                        .fill(.quaternary)
                        .frame(width: 10, height: 10)
                }
            }

            Text(phase.label)
                .font(.caption2.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isFuture ? .tertiary : (isCurrent ? .primary : .secondary))
                .lineLimit(1)
        }
        .frame(minWidth: 44)
        .onAppear { if isCurrent { pulsing = true } }
        .onChange(of: currentPhase) { _, _ in pulsing = isCurrent }
    }

    private var circleBackground: Color {
        if isComplete { return .accentColor }
        if isCurrent  { return Color.accentColor.opacity(0.18) }
        return Color(nsColor: .quaternaryLabelColor)
    }
}

// MARK: - Preview

#Preview {
    BuildProgressHeader()
        .frame(width: 400)
}
