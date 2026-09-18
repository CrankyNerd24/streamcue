import Foundation
import EventKit

enum RemindersError: LocalizedError {
    case accessDenied
    case noDefaultList

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Reminders access was declined. You can change it in Settings → Privacy."
        case .noDefaultList:
            return "No default Reminders list is set up on this device."
        }
    }
}

/// Writes a single reminder for a show's next episode. Manual only — the app
/// never touches Reminders unless you tap the button.
@MainActor
final class RemindersService {
    static let shared = RemindersService()

    private let store = EKEventStore()

    private func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// Returns the reminder's identifier so it can be removed later.
    func add(title: String, notes: String?, due: Date) async throws -> String {
        guard await requestAccess() else { throw RemindersError.accessDenied }
        guard let list = store.defaultCalendarForNewReminders() else {
            throw RemindersError.noDefaultList
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = list
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: due
        )
        reminder.addAlarm(EKAlarm(absoluteDate: due))

        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func remove(identifier: String) async {
        guard await requestAccess() else { return }
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return
        }
        try? store.remove(reminder, commit: true)
    }
}

/// Keeps Reminders in step with air dates, optionally without being asked.
@MainActor
enum ReminderSync {
    static let autoKey = "autoReminders"

    /// Also requires premium so a lapsed refund doesn't leave the toggle's
    /// stored `true` still writing reminders in the background.
    static var isAutomatic: Bool {
        UserDefaults.standard.bool(forKey: autoKey) && PurchaseManager.shared.isPremium
    }

    /// The show's air date at the notification hour, or nil if it's passed.
    static func due(for show: TrackedShow) -> Date? {
        guard let airDate = show.effectiveAirDate else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: airDate)
        components.hour = Notifications.hour
        components.minute = 0
        guard let due = Calendar.current.date(from: components), due > .now else { return nil }
        return due
    }

    /// Creates reminders for anything dated that doesn't have one, and moves
    /// any whose date has shifted since. Returns how many it wrote.
    @discardableResult
    static func sync(_ shows: [TrackedShow], force: Bool = false) async -> Int {
        guard force || isAutomatic else { return 0 }

        var written = 0
        for show in shows {
            guard let due = due(for: show) else { continue }

            // Date moved since the reminder was made — replace it.
            if let existing = show.reminderID,
               let previous = show.reminderDate,
               previous != due {
                await RemindersService.shared.remove(identifier: existing)
                show.reminderID = nil
                show.reminderDate = nil
            }

            guard show.reminderID == nil else { continue }

            do {
                show.reminderID = try await RemindersService.shared.add(
                    title: "Watch \(show.name)",
                    notes: show.nextEpisodeLabel,
                    due: due
                )
                show.reminderDate = due
                written += 1
            } catch {
                // Access denied or no list — no point trying the rest.
                return written
            }
        }
        return written
    }
}
