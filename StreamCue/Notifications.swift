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
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
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

        for show in shows {
            guard let airDate = show.nextAirDate else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: airDate)
            components.hour = hour
            components.minute = 0

            guard let fireDate = calendar.date(from: components), fireDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = show.name
            content.body = body(for: show)
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
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
