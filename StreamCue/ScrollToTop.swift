import SwiftUI

/// Reports how far a scroll view has travelled, so a jump-to-top control can
/// stay hidden until it's actually useful.
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    /// Place at the very top of a scroll view's content.
    func reportsScrollOffset(in space: String) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ScrollOffsetKey.self,
                    value: geometry.frame(in: .named(space)).minY
                )
            }
        )
    }
}

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
