import SwiftUI

/// iOS already scrolls to top when you tap the status bar, but almost nobody
/// knows that. This appears only after a long scroll so it isn't permanent
/// furniture.
struct BackToTopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(Theme.divider, lineWidth: 0.5)
                }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel("Back to top")
    }
}

extension View {
    /// Reports how far the scroll view has travelled from the top.
    /// Uses the system's own scroll geometry rather than a GeometryReader
    /// preference, which proved unreliable inside a lazy grid.
    func trackScrollDistance(_ distance: Binding<CGFloat>) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            distance.wrappedValue = newValue
        }
    }
}
