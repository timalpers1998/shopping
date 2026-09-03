import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Theme.textSecondary)
            Text(title).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
            if let message { Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center) }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        EmptyStateView(icon: "wifi.exclamationmark", title: "Couldn't load", message: message, actionTitle: "Retry", action: retry)
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content.overlay(
            LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                .offset(x: phase * 400)
                .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 } }
        ).clipped()
    }
}
extension View { func shimmer() -> some View { modifier(ShimmerModifier()) } }
