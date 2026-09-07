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
