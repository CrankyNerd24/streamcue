import Foundation
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

    /// Number of episodes waiting on the app icon. Clears itself when the
    /// count reaches zero. Requires notification permission — without it iOS
    /// silently ignores the badge.
    static func updateBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(max(0, count))
    }

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
    /// than diffing, and the list is small.
    static func reschedule(for shows: [TrackedShow]) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        guard isEnabled else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current

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

    /// The show's air date at the user's chosen hour, or nil if that's passed.
    private static func fireDate(for show: TrackedShow, calendar: Calendar) -> Date? {
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
