import SwiftUI
import SwiftData

@main
struct StreamCueApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [TrackedShow.self, TrackedMovie.self, PendingEpisode.self])
    }
}

struct RootView: View {
    @AppStorage(OnboardingView.completedKey) private var hasCompletedSetup = false

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("My shows", systemImage: "list.bullet") }

            WatchlistView()
                .tabItem { Label("Movies", systemImage: "film") }

            SubscriptionsView()
                .tabItem { Label("Services", systemImage: "rectangle.stack") }

            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles") }
        }
        .tint(Theme.primary)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: .constant(!hasCompletedSetup)) {
            OnboardingView()
        }
    }
}
