import Foundation
import BackgroundTasks
import SwiftData

/// Asks iOS to wake the app periodically so air dates, alerts and reminders
/// are current before you open it. The system decides when this actually runs
/// — the interval below is a floor requested, not a promise.
@MainActor
enum BackgroundRefresh {
    static let taskID = "com.streamcue.weeklyRefresh"

    /// One week. iOS may run it sooner if you use the app often, or later —
    /// or not at all if the device is low on battery.
    static let interval: TimeInterval = 7 * 24 * 60 * 60

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator doesn't support this, and a duplicate submit throws.
            // Neither is worth surfacing.
        }
    }

    /// The same work the app does on open: refresh stale shows, record newly
    /// aired episodes, tidy up, then rebuild alerts and reminders.
    static func run(container: ModelContainer) async {
        let context = container.mainContext

        guard let shows = try? context.fetch(FetchDescriptor<TrackedShow>()) else { return }

        for show in shows where show.isStale {
            try? await show.refresh(includeRatings: false)
            await EpisodeSync.sync(show, context: context)
        }

        if let movies = try? context.fetch(FetchDescriptor<TrackedMovie>()) {
            for movie in movies where movie.isStale {
                try? await movie.refresh(includeRatings: false)
            }
        }

        EpisodeSync.prune(context: context)
        Library.deduplicate(context: context)

        await Notifications.reschedule(for: shows)
        await ReminderSync.sync(shows)

        try? context.save()
    }
}
