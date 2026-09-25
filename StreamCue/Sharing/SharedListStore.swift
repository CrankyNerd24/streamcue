import CloudKit
import Foundation
import Observation
import SwiftData

/// One shared source of the household list for the whole app, so the Shows
/// and Movies tabs (each showing their own kind's slice of it) stay in sync
/// with each other without both independently hitting CloudKit. Injected
/// once at the root via `.environment`.
@Observable
final class SharedListStore {
    /// `AppDelegate`/`SceneDelegate` sit outside SwiftUI's view hierarchy and
    /// can't reach an `@Environment`-injected instance, so share-acceptance
    /// (the only caller outside the view tree) goes through this instead.
    static let shared = SharedListStore()

    private(set) var items: [SharedItem] = []
    private(set) var isLoading = false
    var errorMessage: String?

    func items(for kind: MediaKind) -> [SharedItem] {
        items.filter { $0.kind == kind }
    }

    func contains(tmdbID: Int, kind: MediaKind) -> Bool {
        items.contains { $0.tmdbID == tmdbID && $0.kind == kind }
    }

    func item(tmdbID: Int, kind: MediaKind) -> SharedItem? {
        items.first { $0.tmdbID == tmdbID && $0.kind == kind }
    }

    /// Fetches the household list and mirrors any new title into this
    /// device's own personal list — a shared show is meant to behave exactly
    /// like one you added yourself (air dates, notifications, everything),
    /// not sit in a separate, feature-limited list of its own.
    @MainActor
    func refresh(context: ModelContext) async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await SharedListManager.fetchAll()
            syncToPersonalList(context: context)
        } catch SharedListError.notSetUp {
            items = []
        } catch let error as CKError where error.code == .notAuthenticated {
            // No iCloud account on this device (the Simulator, usually) —
            // CloudKit reports it as a missing auth token. This runs on every
            // launch, so treat it like having no household list rather than
            // alerting; sharing actions still surface it if tried.
            items = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Skips anything already personally tracked, and anything the user
    /// deliberately removed after it arrived — `Library.removeShow`/
    /// `removeMovie` mark a shared title ignored on removal specifically so
    /// this doesn't resurrect it on the next refresh.
    @MainActor
    private func syncToPersonalList(context: ModelContext) {
        for item in items where !Library.isIgnored(tmdbID: item.tmdbID, kind: item.kind, context: context) {
            // Watched wins, same as the dedup merge in Library — this only
            // ever turns a personal copy on, never off, so it can't fight
            // with someone still watching it on their own device.
            switch item.kind {
            case .tv:
                let show = Library.addShow(tmdbID: item.tmdbID, name: item.title, posterPath: item.posterPath, context: context)
                if item.watched && !show.watched {
                    show.watched = true
                }
                // Day offset has no "wins" — the household shares one
                // broadcast delay, so whoever set it last is authoritative.
                if item.dayOffset != show.dayOffset {
                    show.dayOffset = item.dayOffset
                }
            case .movies:
                let movie = Library.addMovie(tmdbID: item.tmdbID, title: item.title, posterPath: item.posterPath, context: context)
                if item.watched && !movie.watched {
                    movie.watched = true
                }
            }
        }
    }

    /// Pushes this device's watched state for a title already on the
    /// household list up to the shared record, so marking something watched
    /// personally shows up as watched on everyone else's copy too. A no-op
    /// if the title isn't shared, or the shared record already agrees.
    func syncWatched(tmdbID: Int, kind: MediaKind, watched: Bool) async {
        guard let item = item(tmdbID: tmdbID, kind: kind), item.watched != watched else { return }
        await setWatched(item, watched: watched)
    }

    /// Same idea as `syncWatched`, for a show's day offset. TV only — movies
    /// have no such field.
    @MainActor
    func syncDayOffset(tmdbID: Int, dayOffset: Int) async {
        guard let item = item(tmdbID: tmdbID, kind: .tv), item.dayOffset != dayOffset else { return }
        await setDayOffset(item, dayOffset: dayOffset)
    }

    func add(tmdbID: Int, kind: MediaKind, title: String, posterPath: String?, dayOffset: Int = 0) async {
        do {
            let item = try await SharedListManager.add(
                tmdbID: tmdbID,
                kind: kind,
                title: title,
                posterPath: posterPath,
                dayOffset: dayOffset
            )
            items.insert(item, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setWatched(_ item: SharedItem, watched: Bool) async {
        guard let index = items.firstIndex(of: item) else { return }
        items[index].watched = watched
        do {
            try await SharedListManager.setWatched(item, watched: watched)
        } catch {
            items[index].watched = !watched
            errorMessage = error.localizedDescription
        }
    }

    /// Records with a day-offset push in flight. Tapping the stepper fires
    /// one call per tap; rather than racing a CloudKit save per tap, later
    /// taps just update `items` and the push already running picks up the
    /// newest value when its current save finishes.
    private var dayOffsetPushes: Set<CKRecord.ID> = []

    @MainActor
    func setDayOffset(_ item: SharedItem, dayOffset: Int) async {
        guard let index = items.firstIndex(of: item) else { return }
        items[index].dayOffset = dayOffset
        guard dayOffsetPushes.insert(item.recordID).inserted else { return }
        defer { dayOffsetPushes.remove(item.recordID) }

        var confirmed = item.dayOffset
        while let latest = items.first(where: { $0.recordID == item.recordID })?.dayOffset, latest != confirmed {
            do {
                try await SharedListManager.setDayOffset(item, dayOffset: latest)
                confirmed = latest
            } catch {
                if let index = items.firstIndex(where: { $0.recordID == item.recordID }) {
                    items[index].dayOffset = confirmed
                }
                errorMessage = error.localizedDescription
                return
            }
        }
    }

    func remove(_ item: SharedItem) async {
        let previous = items
        items.removeAll { $0.id == item.id }
        do {
            try await SharedListManager.remove(item)
        } catch {
            items = previous
            errorMessage = error.localizedDescription
        }
    }

}
