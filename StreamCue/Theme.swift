import SwiftUI

/// Palette drawn from the app icon: warm near-black cabinet, cream, and the
/// test-pattern colours. Orange is reserved for "airing tonight" and nothing
/// else; green means free to watch.
enum Theme {
    static let background = Color(red: 0.090, green: 0.082, blue: 0.059)
    static let card       = Color(red: 0.129, green: 0.118, blue: 0.086)
    static let divider    = Color(red: 0.173, green: 0.161, blue: 0.129)
    static let posterWell = Color(red: 0.243, green: 0.227, blue: 0.173)

    static let primary    = Color(red: 0.949, green: 0.929, blue: 0.882)
    static let secondary  = Color(red: 0.541, green: 0.522, blue: 0.467)
    static let tertiary   = Color(red: 0.420, green: 0.404, blue: 0.361)

    static let tonight    = Color(red: 0.847, green: 0.388, blue: 0.122)
    static let free       = Color(red: 0.561, green: 0.796, blue: 0.561)
    /// Aired but not yet dealt with.
    static let unwatched  = Color(red: 0.898, green: 0.663, blue: 0.227)

    /// Test-pattern bars sampled from the app icon, in screen order.
    static let bars: [Color] = [
        Color(red: 0.847, green: 0.388, blue: 0.122),
        Color(red: 0.898, green: 0.663, blue: 0.227),
        Color(red: 0.561, green: 0.796, blue: 0.561),
        Color(red: 0.435, green: 0.663, blue: 0.722),
        Color(red: 0.949, green: 0.929, blue: 0.882),
        Color(red: 0.310, green: 0.502, blue: 0.573)
    ]
}

extension View {
    /// Dark canvas behind a List, with the system list background removed.
    func themedList() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}
