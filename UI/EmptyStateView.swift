import SwiftUI

struct EmptyStateView<Actions: View, Content: View>: View {
    let title: String
    let systemImage: String
    let description: String?
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let content: () -> Content

    init(_ title: String,
         systemImage: String,
         description: String? = nil,
         @ViewBuilder actions: @escaping () -> Actions = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content = { EmptyView() }) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions
        self.content = content
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description {
                Text(description)
            }
        } actions: {
            VStack(spacing: 12) {
                content()
                actions()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
