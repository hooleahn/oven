import SwiftUI

// MARK: - macOS 13 compatibility shim for ContentUnavailableView

struct EmptyStateView<Actions: View>: View {
    let title: String
    let systemImage: String
    let description: String?
    @ViewBuilder let actions: () -> Actions

    init(_ title: String, systemImage: String, description: String? = nil,
         @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions
    }

    var body: some View {
        if #available(macOS 14, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let description { Text(description) }
            } actions: {
                actions()
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text(title).font(.headline)
                if let description {
                    Text(description).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                actions()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        }
    }
}
