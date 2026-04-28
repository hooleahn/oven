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
        ZStack {
            // Subtle radial gradient background
            RadialGradient(
                colors: [Color.primary.opacity(0.03), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: systemImage)
                    .font(.system(.largeTitle, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let description {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 400)
                    }
                }

                content()

                actions()
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
