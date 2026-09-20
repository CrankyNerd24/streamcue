import SwiftUI
import SwiftData

/// Lets `AppDelegate`/`SceneDelegate` — outside the SwiftUI view hierarchy,
/// so no `@Environment(\.modelContext)` — reach the same context views use.
/// `ModelContainer.mainContext` is the exact context `.modelContainer(_:)`
/// hands to descendant views, so there's no separate-context merge risk.
enum AppContainer {
    static var shared: ModelContainer!
}

@main
struct StreamCueApp: App {
    // Only needed to catch CKShare-invite acceptance (see AppDelegate.swift)
    // — SwiftUI's App/Scene lifecycle has no hook for it.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        AppContainer.shared = container
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(BackgroundRefresh.taskID)) {
            await BackgroundRefresh.run(container: container)
            await BackgroundRefresh.schedule()
        }
    }
}

struct RootView: View {
    @AppStorage(OnboardingView.completedKey) private var hasCompletedSetup = false
    // The same instance `AppDelegate` reaches to refresh/report errors after
    // a share is accepted — see `SharedListStore.shared`.
    @State private var sharedList = SharedListStore.shared
    @Environment(\.modelContext) private var context

    /// Drives the tab badge — same filter the Ready to watch section uses.
    @Query(filter: #Predicate<PendingEpisode> { !$0.watched && !$0.dismissed })
    private var pending: [PendingEpisode]

    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("My shows", systemImage: "list.bullet") }
                .badge(pending.count)

            WatchlistView()
                .tabItem { Label("Movies", systemImage: "film") }

            SubscriptionsView()
                .tabItem { Label("Services", systemImage: "rectangle.stack") }

            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles") }
        }
        .tint(Theme.primary)
        .preferredColorScheme(.dark)
        .environment(sharedList)
        .task { await sharedList.refresh(context: context) }
        .alert(
            "Household list error",
            isPresented: Binding(
                get: { sharedList.errorMessage != nil },
                set: { if !$0 { sharedList.errorMessage = nil } }
            )
        ) {
            Button("OK") { sharedList.errorMessage = nil }
        } message: {
            Text(sharedList.errorMessage ?? "")
        }
        .fullScreenCover(isPresented: .constant(!hasCompletedSetup)) {
            OnboardingView()
        }
    }
}
