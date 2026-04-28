import Foundation

// MARK: - ToastCenter

@MainActor
@Observable
final class ToastCenter {

    static let shared = ToastCenter()

    // MARK: - Toast model

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let severity: Severity
        let source: String
        /// Optional closure to deep-link into the app when the user taps "Details".
        let deepLink: (@MainActor () -> Void)?
    }

    enum Severity {
        case info, warning, error
    }

    // MARK: - State

    /// Ordered list of currently-visible toasts (oldest first).
    var toasts: [Toast] = []

    private init() {}

    // MARK: - API

    func push(
        _ message: String,
        severity: Severity,
        source: String,
        deepLink: (@MainActor () -> Void)? = nil
    ) {
        let toast = Toast(message: message, severity: severity, source: source, deepLink: deepLink)
        toasts.append(toast)

        // Auto-dismiss after 6 seconds.
        Task {
            try? await Task.sleep(for: .seconds(6))
            dismiss(id: toast.id)
        }
    }

    func dismiss(id: Toast.ID) {
        toasts.removeAll { $0.id == id }
    }
}
