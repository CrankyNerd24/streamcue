import Foundation
import SwiftData
import UserNotifications

/// Local notifications for shows with a known air date. TMDB gives a date but
/// no time, so everything fires at an hour you pick rather than at broadcast.
@MainActor
enum Notifications {
    static let enabledKey = "notificationsEnabled"
    static let hourKey = "notificationHour"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// When on, alerts name nothing — no show title, no episode, no service.
    static let privateKey = "privateNotifications"

    static var isPrivate: Bool {
        UserDefaults.standard.bool(forKey: privateKey)
    }

    static var hour: Int {
        let stored = UserDefaults.standard.integer(forKey: hourKey)
        return stored == 0 ? 18 : stored
    }

    /// Returns false if the user declined, so the caller can flip the toggle back.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// When the icon badge ticks up for an episode that has no alert or
    /// reminder to go with it.
    static let defaultBadgeHour = 19

    /// Keeps the stored toggle honest against the system's actual permission
    /// state. Nothing else notices when that drifts — a device-wide privacy
    /// reset or the user revoking access in Settings both leave `isEnabled`
    /// stuck at true with no alerts actually scheduled. Flipping it back to
    /// false here means turning the toggle back on goes through
    /// `requestPermission()` again instead of silently doing nothing.
    static func syncEnabledState() async {
        guard isEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return
        default:
            UserDefaults.standard.set(false, forKey: enabledKey)
        }
    }

    /// Clears everything pending and rebuilds from the current shows. Cheaper
    /// than diffing, and the list is small. Also owns the icon badge, so call
    /// it whenever Ready to watch changes as well as when air dates do.
    static func reschedule(for shows: [TrackedShow], context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let records = (try? context.fetch(FetchDescriptor<PendingEpisode>())) ?? []
        let outstanding = records.filter { !$0.watched && !$0.dismissed }.count
        // Without permission iOS silently ignores the badge.
        try? await center.setBadgeCount(outstanding)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        await scheduleBadges(
            for: shows,
            records: records,
            outstanding: outstanding,
            calendar: calendar
        )

        guard isEnabled else { return }

        // Private mode collapses to one alert per day. Scheduling one per show
        // would otherwise stack identical anonymous notifications, which tells
        // an onlooker how many things you watch without telling you anything.
        if isPrivate {
            var counts: [DateComponents: Int] = [:]
            for show in shows {
                guard let fire = fireDate(for: show, calendar: calendar) else { continue }
                counts[calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                       default: 0] += 1
            }

            for (components, count) in counts {
                let content = UNMutableNotificationContent()
                content.title = "Airing today"
                content.body = count == 1
                    ? "Something you track airs today."
                    : "\(count) things you track air today."
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "day-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: components,
                        repeats: false
                    )
                )
                try? await center.add(request)
            }
            return
        }

        for show in shows {
            guard let fire = fireDate(for: show, calendar: calendar) else { continue }

            let content = UNMutableNotificationContent()
            content.title = show.name
            content.body = body(for: show)
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fire
                ),
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: "show-\(show.tmdbID)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    /// Silent, badge-only notifications that raise the icon count as each
    /// tracked episode airs. The app can't run at a set time, so without these
    /// the badge only caught up when you opened it. Each one carries the
    /// running total: what's in Ready to watch now plus everything due to air
    /// by then. Rebuilt whenever that list changes, so the totals stay right.
    private static func scheduleBadges(
        for shows: [TrackedShow],
        records: [PendingEpisode],
        outstanding: Int,
        calendar: Calendar
    ) async {
        let center = UNUserNotificationCenter.current()
        let times = shows.compactMap { badgeDate(for: $0, records: records, calendar: calendar) }
        let counts = Dictionary(grouping: times, by: { $0 }).mapValues(\.count)

        var total = outstanding
        for time in counts.keys.sorted() {
            // A newer rebuild has started; let it write the totals.
            if Task.isCancelled { return }
            total += counts[time] ?? 0

            let content = UNMutableNotificationContent()
            content.badge = NSNumber(value: total)

            let request = UNNotificationRequest(
                identifier: "badge-\(Int(time.timeIntervalSince1970))",
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: time
                    ),
                    repeats: false
                )
            )
            try? await center.add(request)
        }
    }

    /// When a show's next episode should count on the badge: the time its
    /// alert or reminder goes off, or `defaultBadgeHour` if it has neither.
    /// Nil if that's passed, or if the episode is already recorded — it's in
    /// the count (or was dealt with) already.
    private static func badgeDate(
        for show: TrackedShow,
        records: [PendingEpisode],
        calendar: Calendar
    ) -> Date? {
        guard let airDate = show.effectiveAirDate else { return nil }
        let recorded = records.contains {
            $0.showID == show.tmdbID
                && $0.airDate.map { calendar.isDate($0, inSameDayAs: airDate) } == true
        }
        guard !recorded else { return nil }

        // Alerts and reminders both go off at the notification hour.
        let isScheduled = isEnabled || ReminderSync.isAutomatic || show.reminderID != nil
        return fireDate(
            for: show,
            hour: isScheduled ? hour : defaultBadgeHour,
            calendar: calendar
        )
    }

    /// The show's air date at the given hour, or nil if that's passed.
    private static func fireDate(
        for show: TrackedShow,
        hour: Int = Notifications.hour,
        calendar: Calendar
    ) -> Date? {
        guard let airDate = show.effectiveAirDate else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: airDate)
        components.hour = hour
        components.minute = 0
        guard let fire = calendar.date(from: components), fire > .now else { return nil }
        return fire
    }

    private static func body(for show: TrackedShow) -> String {
        var parts: [String] = []
        if let episode = show.nextEpisodeLabel {
            parts.append("\(episode) airs today")
        } else {
            parts.append("Airs today")
        }
        if let service = show.freeOn.first {
            parts.append("Free on \(service)")
        } else if let service = show.subscriptionOn.first {
            parts.append(service)
        }
        return parts.joined(separator: " · ")
    }
}
