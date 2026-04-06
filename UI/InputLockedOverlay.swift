import SwiftUI


struct InputLockedOverlay: View {
    private var session = BuildSessionManager.shared
    @AppStorage("showUnlockHintOverlay") private var showHint: Bool = true

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            if showHint {
                // Full hint overlay
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white)
                    Text("Input Locked")
                        .font(.title2).fontWeight(.semibold).foregroundStyle(.white)
                    Text("Keyboard and mouse are disabled while Oven bakes your base VM.")
                        .font(.callout).foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center).frame(maxWidth: 320)
                    Text("Press ⌘⇧⎋ to unlock")
                        .font(.callout)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                    Button("Unlock Now") {
                        BuildSessionManager.shared.disableInputLock()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                }
                .padding(40)
            } else {
                // Minimal label — always visible even when hint is suppressed
                // so the user knows why the machine isn't responding
                VStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Input locked — building VM")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                // Pin to bottom-trailing so it stays out of the way
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
