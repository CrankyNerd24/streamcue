import SwiftUI
import SwiftData

@main
struct StreamCueApp: App {
    private let container: ModelContainer

    init() {
        let schema = Schema([
            TrackedShow.self,
            TrackedMovie.self,
            PendingEpisode.self,
            IgnoredTitle.self
        ])

        // Try CloudKit first. If the device has no iCloud account, or CloudKit
        // is unavailable, fall back to a local store so the app still works
        // rather than refusing to launch.
        do {
            let cloud = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            container = try ModelContainer(for: schema, configurations: [cloud])
        } catch {
            do {
                let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                container = try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("Could not create a model container: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
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
